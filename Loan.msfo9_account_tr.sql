SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 23/11/2023
-- Description:	Выгрузка в МСФО счетов, относящихся к кредитным договорам
-- v 2.0, 2024-12-25
-- =============================================
-- Modify 2026-01-14
CREATE OR ALTER PROCEDURE [Loan].[msfo9_account_tr] 
	@Source varchar(100),
	@Date date, 				    -- Дата выгрузки. Если @Date <> NULL, выгружаются счета, открытые в дату выгрузки,
									-- а также регистры с ненулевыми оборотами (dk_val или ck_val > 0). 					
	@ContractID uniqueidentifier = null    -- Только счета для указанного договора. Если NULL - условие игнорируется	
AS
BEGIN
	-- Очистка транзитной таблицы МСФО
		
	DELETE FROM dbo.syn_MSFO_msfo9_account_tr
	WHERE 
	  source = @Source
	  AND
	  DATEDIFF(day , ISNULL(@date, date1), date1) = 0
	  AND
	  ((@ContractID IS NULL) OR (contract_oid = @ContractID))	

	/******************************************************************************************************************/
	BEGIN -- ВСПОМОГАТЕЛЬНЫЕ ДАННЫЕ

	DECLARE 
		-- Глубина проверки закрытых траншей/договоров - 
		-- максимальная длинна интервала от даты закрвтия до даты выгрузки в днях 
		@Depth int = 0,
		-- Для формирования знаяения поля [name] можно использовать старый или новый формат
		-- 0 - имя формируется на основании имени типа регистра и включает в себя номер транша, если договор является траншем КЛ
		-- 1 - имя строится на основании имени типа счета.
		@UseOldNameFormat bit = 0

	-- 0.1.0 Таблица загруженных ранее договоров и траншей
	DECLARE 
		@ContractList table
		(
			ID uniqueidentifier PRIMARY KEY,	-- Идентификатор объекта
			CustomerID uniqueidentifier,		-- Клиент
			branch_code smallint,				-- Код подразделения
			[Name] varchar(255),				-- Наименование
			IdType int							-- Тип объекта:
												-- 0 - договор
												-- 1 - транш
												-- 2 - портфель
		)

	-- Добавление договоров к списку
	INSERT INTO @ContractList	
	SELECT 
		con.ContractID as ID,
		src.client_oid as CustomerID,
		src.branch_code,					
		src.number as [Name],
		0 as IdType
	FROM dbo.syn_MSFO_msfo9_loan_tr src
	INNER JOIN [Loan].[Contract] con ON con.ContractID =  src.oid		
	WHERE src.date1 = @Date and src.source = @Source AND
		(@ContractID IS NULL OR con.ContractID = @ContractID)

	-- Добавление банковских гарантий к списку
	INSERT INTO @ContractList	
	SELECT 
		con.ContractID as ID,
		src.client_oid as CustomerID,
		src.branch_code,					
		src.number as [Name],
		0 as IdType
	FROM dbo.syn_MSFO_msfo9_guarantee_tr src
	INNER JOIN [Loan].[Contract] con ON con.ContractID =  src.oid		
	WHERE src.date1 = @Date and src.source = @Source AND
		(@ContractID IS NULL OR con.ContractID = @ContractID)

	-- Добавление траншей к списку
	INSERT INTO @ContractList	
	SELECT 
		iss.IssueID as ID,
		src.client_oid as CustomerID,
		src.branch_code,		
		(dcn.Number + ' - ' + CAST(iss.IssueNumber as varchar)) as [Name],
		1 as IdType
	FROM dbo.syn_MSFO_msfo9_loan_tr src
	INNER JOIN [Loan].[Issue] iss ON iss.IssueID =  src.oid
	INNER JOIN [dbo].[T_Contract] dcn ON dcn.ContractID = iss.ContractID
	WHERE src.date1 = @Date and src.source = @Source AND
		(@ContractID IS NULL OR iss.ContractID = @ContractID)

	-- Добавление портфелей к списку
	INSERT INTO @ContractList
	SELECT 
		ppf.PortfolioID as ID, 
		NULL as CustomerID,
		ISNULL(bank.branch_code, 0) as branch_code,		
		ptb.[Name],
		2 as IdType
	FROM [GbPledges].[Portfolio] ppf WITH (NOLOCK) 
		LEFT JOIN [GbPledges].[PortfolioTypeBack] ptb WITH (NOLOCK) ON ptb.PortfolioTypeBackID = ppf.[PortfolioTypeBack]		
		OUTER APPLY
		(
			SELECT 
				dbo.Get_Division_Code(div.DivisionID) as division_code,
				CAST(ISNULL(brn.InnerCode, '0') as int) as branch_code		
			FROM [GbPledges].[PortfolioTypeBackLink] ptl WITH (NOLOCK)
			INNER JOIN [dbo].[T_Division] div WITH (NOLOCK) ON div.DivisionID = ptl.BackOffice
			INNER JOIN [dbo].[T_Branch] brn WITH (NOLOCK) ON brn.BranchID = div.Branch
			WHERE ptl.PortfolioTypeBack = ppf.PortfolioTypeBack and ptl.CreateAccount = 1
		) bank
	where ptb.BeginDate <= @Date

	-- Добавление закрытых договоров, у которых имеются не нулевые остатки на регистрах
	INSERT INTO @ContractList	
	SELECT 
		con.ContractID as ID,
		dcn.Client as CustomerID,
		IIF(brn.InnerCode IS NULL, 0, brn.InnerCode) as branch_code,		
		dcn.Number as [Name],
		0 as IdType
	FROM [Loan].[Contract] con
	inner join dbo.T_Contract dcn on con.ContractID = dcn.ContractID
	left join [dbo].[T_Branch] brn with (nolock) on brn.BranchID = dcn.Branch
	inner join Loan.Register reg on reg.ContractID = dcn.ContractID and reg.IssueID is NULL
	inner join Loan.RegisterType rgt on rgt.RegisterTypeID = reg.RegisterTypeID 
		and rgt.Brief not in ('Гарант', 'Лим', 'НеиспЛим', 'Обесп', 'ОбеспРез', 'БГарант', 'РезервБГарант', 'ЛимБГарант', 'НеисЛимБГарант')
	outer apply
	(
		select top(1) RestOut
		from Loan.RegisterRest 
		where RegisterID = reg.RegisterID
			and cast(OperDay as date) <= @Date			
		order by OperDay desc
	) rst
	where con.ContractKind = 0 and dcn.[Status] not in (0, 3)
		and (IsNULL(dcn.ClosedDate, @Date) between DateAdd(day, -@Depth, @Date) and DateAdd(day, -1, @Date))
		and rst.RestOut > 0

	-- Добавление закрытых траншей, у которых имеются не нулевые остатки на регистрах
	INSERT INTO @ContractList	
	SELECT 
		iss.IssueID as ID,
		dcn.Client as CustomerID,
		IIF(brn.InnerCode IS NULL, 0, brn.InnerCode) as branch_code,		
		(dcn.Number + ' - ' + CAST(iss.IssueNumber as varchar)) as [Name],
		1 as IdType
	FROM [Loan].[Contract] con
	INNER JOIN [dbo].[T_Contract] dcn ON dcn.ContractID = con.ContractID
	INNER JOIN [Loan].[Issue] iss ON iss.ContractID = dcn.ContractID	
	left join [dbo].[T_Branch] brn with (nolock) on brn.BranchID = dcn.Branch
	INNER JOIN Loan.Register reg ON reg.IssueID = iss.IssueID
	OUTER APPLY
	(
		select top(1) RestOut
		from Loan.RegisterRest 
		where RegisterID = reg.RegisterID
			and cast(OperDay as date) <= @Date			
		order by OperDay desc
	) rst
	WHERE con.ContractKind = 0 and dcn.[Status] not in (0, 3)
		and (IsNULL(iss.CloseDate, @Date) between DateAdd(day, -@Depth, @Date) and DateAdd(day, -1, @Date))
		and rst.RestOut > 0

	--select * from @ContractList

	-- 0.2.0 Таблица связей (Тип регистра - Тип счета)
	DECLARE @AccountRegisterLink table(RegisterTypeID int, AccountTypeID int)
	INSERT INTO @AccountRegisterLink (RegisterTypeID, AccountTypeID)
	SELECT RegisterTypeID, AccountTypeID
	FROM [Loan].[AccountRegisterLink_new]

	-- Удаляем связки портфельных счетов типа МСФО9_Доход...,  МСФО9_Расх...
	delete @AccountRegisterLink
	from @AccountRegisterLink t
	where exists		
	(
		select lnk.RegisterTypeID, lnk.AccountTypeID
		from dbo.T_AccountType act
		inner join Loan.AccountRegisterLink_new lnk on lnk.AccountTypeID = act.AccountTypeID
		inner join Loan.RegisterType rgt on rgt.RegisterTypeID = lnk.RegisterTypeID and SubType = 2
		where (act.code like '%МСФО9_Доход%' or act.code like 'МСФО9_Расх%') 
			and lnk.RegisterTypeID = t.RegisterTypeID
			and lnk.AccountTypeID = t.AccountTypeID
	)

	-- 0.2.1 Дополняем таблицу связей (Тип регистра - Тип счета)
	-- записями для рекистра "Резерв по НКЛ"

	INSERT INTO @AccountRegisterLink (RegisterTypeID, AccountTypeID)
	VALUES 
		(166, 10029)
		--(166, 10045)
		--,(166, 10072)
		,(256, 11402)
		,(206, 231)
		,(218, 232)
		,(208, 234)
		,(209, 235)
		-- Требования:
		--,(11, 10043)		  --&&&
		--,(15, 10043)		  --&&&
		,(23, 10043)		  --&&&
		,(33, 10043)		  --&&&

		--,!(12, 10053)
		,(16, 10053)		
		-- Резервы:
		--,(60,  10018)
		--,(164, 10018)
		,(165, 10135)
		,(167, 10133)
		,(168, 10078)
		,(76, 10135)
		,(81, 10120)
		--,(84, 10050)
		,(64, 10133)
		,(77, 10078)
		-- Просрочка		
		,(6 , 10005), (8 , 10005)					-- ПРОСРОЧЕННАЯ ЗАДОЛЖЕННОСТЬ
		--!,(12, 10053)--, (16, 10053)
		,(20, 10053)		-- ПРОСРОЧЕННЫЕ ПРОЦЕНТЫ
		--,(24, 10053)
		,(35, 10053)--, (36, 10043)
		--,(37, 10053)
		,(39, 10053)--, (41, 10043) 
		,(43, 10053), (45, 10053)
		--!, (49, 10053)
/*		-- Корректировки резервов
		,(200, 228), (201, 228)		-- Корректировка резерва по ссуде А
		,(202, 229), (203, 229)		-- Корректировка резерва по ссуде П
		,(204, 230), (205, 230)		-- Корректировка резерва по срочным процентам А
		,(206, 231), (207, 231)		-- Корректировка резерва по срочным процентам П		
		,(218, 232), (219, 232)		-- Корректировка резерва по комиссиям А		
		,(220, 233), (221, 233)		-- Корректировка резерва по комиссиям П		
		,(208, 234)      			-- Корректировка резерва по НКЛ А	
		,(209, 235)      			-- Корректировка резерва по НКЛ П	
		,(210, 238), (211, 238)		-- Корректировка резерва по просроченному долгу А	
		,(212, 239), (213, 239)		-- Корректировка резерва по просроченному долгу П
		,(214, 240), (215, 240)		-- Корректировка резерва по просроченным процентам А
		,(216, 241), (217, 241)		-- Корректировка резерва по просроченным процентам П
*/
	-- 0.3.0  Целевые типы регистров
	DECLARE @TargetRegTypes table
	(
		[RegisterTypeID] int, 
		[Name] varchar(255), 
		[Brief] varchar(50), 
		[SubType] int, 
		[level] int, 
		[LastRegisterTypeID] int
	) 

	-- 0.3.1 Вносим в в список типы регистров нулевого уровня наследования
	INSERT INTO @TargetRegTypes
	VALUES
		-- Траншевые базовые регистры		
		(7,  'Срочная задолженность по траншу', 'ОдСрТр', 1, 0, 7),																
		(8,  'Просроченная задолженность по траншу', 'ОдПрТр', 1, 0, 8),															
		--(15, 'Срочная задолженность по процентам по траншу', 'ПроцСрТр', 1, 0, 15),												
		--!(16, 'Просрченная задолженность по процентам по траншу', 'ПроцПрТр', 1, 0, 16),		
		(28, 'Задолженность по повышенным процентам по траншу', 'ПовТр', 1, 0, 28),	
		(23, 'Срочная задолженность по процентам (баланс) по траншу', 'ПроцСрБалТр', 1, 0, 23),
		(24, 'Просроченная задолженность по процентам (баланс) по траншу', 'ПроцПрБалТр', 1, 0, 24),
		(33, 'Расчетные проценты по балансу по траншу', 'ПроцРасБалТр', 1, 0, 33),			
		--!(36, 'Задолженность по процентам по траншу по просроченному ОД по срочной ставке', 'ПрОДПроцТр', 1, 0, 36),
		--!(41, 'Срочная задолженность по процентам по траншу по просрочненному ОД по срочной ставке', 'ПрОДПроцСрТр', 1, 0, 41),		
		--!(42, 'Просроченная задолженность по процентам по траншу по просрочненному ОД по срочной ставке', 'ПрОДПроцПрТр', 1, 0, 42),
		(49, 'Срочная задолженность по процентам  по траншу (баланс) по просроченному ОД по срочной ставке', 'ПрОДПроцСрБалТр', 1, 0, 49),
		(50, 'Просроченная задолженность по процентам  по траншу (баланс) по просроченному ОД по срочной ставке', 'ПрОДПроцПрБалТр', 1, 0, 50),
		(57, 'Расчетные проценты по балансу по траншу (просроченная задолженность)', 'ПрОДРасБалТр', 1, 0, 57),
		(69, 'Комиссия задолженность по траншу', 'КомТр', 1, 0, 69),	
		(74, 'Сумма пени по просроченной задолженности по траншу', 'ПениОдТр', 1, 0, 74),		
		(75, 'Сумма пени по просроченным процентам по траншу', 'ПениПроцТр', 1, 0, 75),	
		(83, 'Банковская гарантия по соглашению', 'БГарант', 0, 1, 83),
		(84, 'Резерв по банковской гарантии', 'РезервБГарант', 0, 1, 84),		
		--регистры резерва
		(164, 'Резерв по ссуде', 'РезТр', 1, 0, 164),
		(165, 'Резерв по срочным процентам', 'РезПроцТр', 1, 0, 165),
		(167, 'Резерв по просроченному долгу', 'РезПрТр', 1, 0, 167),
		(168, 'Резерв по просроченным процентам', 'РезПрТр', 1, 0, 168),
		(169, 'Резерв по комиссии', 'РезКомТр', 1, 0, 169),
		-- Договорные базовые регистры
		(1,	 'Лимит', 'Лим', 0, 0, 1),
		(2,  'Неиспользованный лимит', 'НеиспЛим', 0, 0, 2),
		(5,  'Срочная задолженность', 'ОдСр', 0, 1, 7),		
		(113, 'Учет присужденных пени по просроченной задолженности', 'ПениОдСуд', 0, 0, 113),
		(114, 'Учет присужденных пени по просроченным процентам', 'ПениПроцСуд', 0, 0, 114),
		-- Траншевые регистры МСФО
		(201, 'Корректировка резерва по ссуде А по траншу', 'МСФО9_КоррРезАТр', 1, 0, 201),
		(203, 'Корректировка резерва по ссуде П по траншу', 'МСФО9_КоррРезПТр', 1, 0, 203),
		(205, 'Корректировка резерва по срочным процентам А по траншу', 'МСФО9_КоррРезПроцАТр', 1, 0, 205),
		(207, 'Корректировка резерва по срочным процентам П по траншу', 'МСФО9_КоррРезПроцПТр', 1, 0, 207),
		(211, 'Корректировка резерва по просроченному долгу А по траншу', 'МСФО9_КоррРезПрАТр', 1, 0, 211),
		(213, 'Корректировка резерва по просроченному долгу П по траншу', 'МСФО9_КоррРезПрПТр', 1, 0, 213),
		(215, 'Корректировка резерва по просроченным процентам А по траншу', 'МСФО9_КоррРезПроцПрАТр', 1, 0, 215),
		(217, 'Корректировка резерва по просроченным процентам П по траншу', 'МСФО9_КоррРезПроцПрПТр', 1, 0, 217),
		(219, 'Корректировка резерва по комиссии А по траншу', 'МСФО9_КоррРезКомАТр', 1, 0, 219),
		(221, 'Корректировка резерва по комиссии П по траншу', 'МСФО9_КоррРезКомПТр', 1, 0, 221),

		--(223, 'Корректировка резерва по штрафам и пени А по траншу', 'МСФО9_КоррРезШтрафПениАТр', 1, 0, 223),--
		--(225, 'Корректировка резерва по штрафам и пени П по траншу', 'МСФО9_КоррРезШтрафПениПТр', 1, 0, 225),--
		(222, 'Корректировка резерва по штрафам и пени А', 'МСФО9_КоррРезШтрафПениА', 0, 0,	223),
		(224, 'Корректировка резерва по штрафам и пени П', 'МСФО9_КоррРезШтрафПениП', 0, 0,	225),

		(231, 'Корректировка стоимости А по траншу', 'МСФО9_КоррСтАТр', 1, 0, 231),
		(233, 'Корректировка стоимости П по траншу', 'МСФО9_КоррСтПТр', 1, 0, 233)

	-- Все операционные портфельные регистры относим к регистрам 0-го уровля
	INSERT INTO @TargetRegTypes
	SELECT 
		rgt.RegisterTypeID,
		rgt.[Name],
		rgt.Brief,
		rgt.SubType,
		0 as [level],
		rgt.RegisterTypeID
	FROM Loan.RegisterType rgt 
	WHERE rgt.subtype = 2 and rgt.IsOperational = 1

	--  0.3.2 Вносим в в список типы регистров уровень наследования которых выше 0
	-- Добавляем регистры 1-го уровня 
	INSERT INTO @TargetRegTypes
	VALUES
		(5,	 'Срочная задолженность', 'ОдСр', 0, 1, 7),
		(6,  'Просроченная задолженность', 'ОдПр', 0, 1, 8),
		--(11, 'Задолженность по процентам срочная', 'ПроцСр', 0, 1, 15),
		--!(12, 'Задолженность по процентам просроченная', 'ПроцПр', 0, 1, 16),
		(27, 'Задолженность по повышенным процентам', 'Пов', 0, 1, 28),
		--!(37, 'Задолженность по процентам срочная по просроченному ОД по срочной ставке', 'ПрОДПроцСр', 0, 1, 41),
		--!(38, 'Задолженность по процентам просроченная по просроченному ОД по срочной ставке', 'ПрОДПроцПр', 0, 1, 42),
		(59, 'Комиссия задолженность', 'Ком', 0, 1, 69),
		(71, 'Сумма пени по просроченной задолженности по договору', 'ПениОд', 0, 1, 74),
		(72, 'Сумма пени по просроченным процентам по договору', 'ПениПроц', 0, 1, 75),
		-- Корректировки резерва
		(206, 'Корректировка резерва по срочным процентам П', 'МСФО9_КоррРезПроцП', 0, 1, 207), 
		(208, 'Корректировка резерва по НКЛ А', 'МСФО9_КоррРезНКЛАТр', 0, 1, 208),
		(209, 'Корректировка резерва по НКЛ П', 'МСФО9_КоррРезНКЛП', 0, 1, 209),
		(218, 'Корректировка резерва по комиссии А', 'МСФО9_КоррРезКомА', 0, 1, 219),
		(254, 'Расчеты по прочим доходам, связанным с предоставлением (размещением) денежных средств', 'РасчКом', 0, 1, 254), 
		(256, 'Просроченная задолженность по процентным комиссиям', 'КомПроцПр', 0, 1, 256), 
		-- Регистры резерва :
		(67,  'Резерв по договру (283-П)', 'Рез283', 0, 1, 67),
		(109, 'Резервы на выкупленные средства', 'РезВыкупСред', 0, 1, 164),
		(76,  'Резервы по процентам (302-П)', 'РезПроц302', 0, 1, 165),
		(153, 'Резервы на возможные потери по процентам на сумму оплаченного требования по БГ', 'РезПроцРаскр', 0, 1, 165),
		(110, 'Резервы по выкупленным процентам', 'РезВыкупПроц', 0, 1, 165),
		(142, 'Резервы на возможные потери по просроченной задолженности', 'БГРезервРаскрПр', 0, 1, 167),
		(77,  'Резервы по просроченным процентам (302-П)', 'РезПрПроц302', 0, 1, 168),
		(111, 'Резервы по выкупленным просроченным процентам', 'РезВыкупПрПроц', 0, 1, 168),
		(120, 'Резерв по просроченной комиссии', 'РезКомПр', 0, 1, 169),
		(81,  'Резерв по комиссионным вознаграждениям', 'РезКом', 0, 1, 81)
	-- Добавляем регистры МСФО 1-го уровня 
	INSERT INTO @TargetRegTypes
	SELECT rgt.RegisterTypeID, rgt.[Name], rgt.Brief, rgt.SubType, 1 as [level], trt.[LastRegisterTypeID]
	FROM @TargetRegTypes trt 
	INNER JOIN [Loan].[RegisterTypeLink] rtl ON rtl.ChildRegisterTypeID = trt.RegisterTypeID
	INNER JOIN [Loan].[RegisterType] rgt ON rgt.RegisterTypeID = rtl.ParentRegisterTypeID
	WHERE trt.[level] = 0 
		AND rgt.Brief like 'МСФО9%'
		AND NOT EXISTS(SELECT 1 FROM @TargetRegTypes WHERE [level] = 0 AND RegisterTypeID = rgt.RegisterTypeID)

	delete from @TargetRegTypes where RegisterTypeID = 202

	--select * from @TargetRegTypes

	-- 0.4 Для каждого целевого типа регистра выводим набор допустимых типов счетов
	-- и уровень приоритета для выбора одного типа счета, 
	-- если имеется несколько связанных с регистром счетов
	declare @TypeLinks table
	(
		RegisterTypeID int, -- тип регистра
		AccountTypeID int,  -- тип счета
		AccountPriority int	-- приоритет выбора счета (0 - высший)
	)

	-- Базовые разрешенные регистры
    insert into @TypeLinks
	SELECT distinct arl.RegisterTypeID, arl.AccountTypeID, trt.[level]
	FROM @AccountRegisterLink arl
	INNER JOIN @TargetRegTypes trt ON trt.RegisterTypeID = arl.RegisterTypeID

	-- Разрешенные регистры первого уровня
	insert into @TypeLinks
	SELECT distinct rtl.ParentRegisterTypeID, rtp.AccountTypeID, rtp.AccountPriority + 10
	FROM @TypeLinks rtp	
	INNER JOIN [Loan].[RegisterTypeLink] rtl ON rtl.ChildRegisterTypeID = rtp.RegisterTypeID

	-- Разрешенные регистры второго уровня
	insert into @TypeLinks
	SELECT distinct rtl.ParentRegisterTypeID, rtp.AccountTypeID, rtp.AccountPriority + 10
	FROM @TypeLinks rtp	
	INNER JOIN [Loan].[RegisterTypeLink] rtl ON rtl.ChildRegisterTypeID = rtp.RegisterTypeID
	WHERE rtp.AccountPriority >= 10
	
	-- !!! Здесь можно подкрутить приоритеты выбора типа счета для регистра, изменив AccountPriority !!! -- 

	-- Для правильного учета не прописанных в стандартной схеме счетов резервов на возможные потери >>>
	update @TypeLinks
	set AccountPriority = 5
	where AccountTypeID = 10050 and RegisterTypeID in (113, 114)
	-- <<< Для правильного учета не прописанных в стандартной схеме счетов резервов на возможные потери 

	--select * 
	--from @TypeLinks	
	--order by RegisterTypeID, AccountPriority

	-- 0.5 Назначеем дату, если отсутствует
	SET @Date = ISNULL(@Date, GETDATE())
	END
	/******************************************************************************************************************/
	BEGIN -- ЗАГРУЗКА РЕГИСТРОВ
		-- Список регистров, которые имеют не пустую историю 
		-- движения средств до заданной даты
		declare @EnabledRegisters table(id uniqueidentifier)
		insert into @EnabledRegisters
		select reg.RegisterID
		from Loan.Register reg
		left join Loan.RegisterRest rst on 
			rst.RegisterID = reg.RegisterID
			and rst.OperDay <= @Date 
		group by reg.RegisterID, reg.Rest
		having Count(rst.RegisterRestID) > 0

		DECLARE		 
			@RegisterList table 
			(
				 RegisterID uniqueidentifier PRIMARY KEY 
				,RegisterTypeID int		
				,PortfolioID uniqueidentifier 
				,ContractID uniqueidentifier 
				,IssueID uniqueidentifier		
				,contract_oid uniqueidentifier
				,rest decimal(21, 2)
				,over_in decimal(21, 2)
				,over_out decimal(21, 2)
				,INDEX IDX_Ref NONCLUSTERED (RegisterTypeID, PortfolioID, ContractID, IssueID)
			)

		-- 1.1 Регистры КД и КЛ
		INSERT INTO @RegisterList
		SELECT DISTINCT
			rg.RegisterID,
			rg.RegisterTypeID,
			NULL,
			con.ContractID,
			NULL,
			con.ContractID as contract_oid,
			ISNULL(IIF(saldo.OperDay = @Date, saldo.RestIn, saldo.RestOut), 0)  as rest,
			ISNULL(rest.OverIn, 0) as over_in, 
			ISNULL(rest.OverOut, 0) as over_out	
		FROM @ContractList lst
		INNER JOIN [Loan].[Contract] con ON con.ContractID = lst.ID
		INNER JOIN [dbo].[T_Contract] dcn ON dcn.ContractID = con.ContractID
		INNER JOIN [Loan].[Register] rg ON rg.ContractID = con.ContractID AND rg.IssueID IS NULL
		--INNER JOIN @EnabledRegisters er ON er.id = rg.RegisterID 
		INNER JOIN @TargetRegTypes rf ON 
			rf.RegisterTypeID = rg.RegisterTypeID 
			AND rf.SubType = 0 -- договорные регистры
		LEFT JOIN [Loan].[RegisterRest] rest WITH (NOLOCK) ON rest.RegisterID = rg.RegisterID and rest.OperDay = @date
		OUTER APPLY
		(
			SELECT TOP(1) OperDay, RestIn, RestOut
			FROM [Loan].[RegisterRest] WITH (NOLOCK)
			WHERE RegisterID = rg.RegisterID and OperDay <= @date
			ORDER BY OperDay DESC
		) saldo	
		where lst.IdType = 0
			
		-- 1.2 Регистры траншей кредитных договоров	
		INSERT INTO @RegisterList
		SELECT DISTINCT
			rg.RegisterID,
			rg.RegisterTypeID,
			NULL,
			con.ContractID,
			iss.IssueID,
			iss.ContractID as contract_oid,
			ISNULL(IIF(saldo.OperDay = @Date, saldo.RestIn, saldo.RestOut), 0)  as rest,
			ISNULL(rest.OverIn, 0) as over_in, 
			ISNULL(rest.OverOut, 0) as over_out							
		FROM @ContractList lst
		INNER JOIN [Loan].[Issue] iss ON iss.ContractID = lst.ID
		INNER JOIN [Loan].[Contract] con ON con.ContractID = iss.ContractID
		INNER JOIN [Loan].[Register] rg ON rg.ContractID = iss.ContractID AND rg.IssueID = iss.IssueID	
		--INNER JOIN @EnabledRegisters er ON er.id = rg.RegisterID 
		INNER JOIN @TargetRegTypes rf ON 
			rf.RegisterTypeID = rg.RegisterTypeID 
			AND rf.[level] = 0			-- 0-го уровня
			AND rf.SubType = 1		    -- траншевые регистры
		LEFT JOIN [Loan].[RegisterRest] rest WITH (NOLOCK) ON rest.RegisterID = rg.RegisterID and rest.OperDay = @date
		OUTER APPLY
		(
			SELECT TOP(1) OperDay, RestIn, RestOut
			FROM [Loan].[RegisterRest] WITH (NOLOCK)
			WHERE RegisterID = rg.RegisterID and OperDay <= @date
			ORDER BY OperDay DESC
		) saldo	
		WHERE lst.IdType = 0 AND NOT con.ContractType IN (2, 3, 6, 7)

		-- 1.3 Регистры траншей кредитных линий и овердрафтов
		INSERT INTO @RegisterList
		SELECT DISTINCT
			rg.RegisterID,
			rg.RegisterTypeID,
			NULL,
			con.ContractID,
			iss.IssueID,
			iss.IssueID as contract_oid,
			ISNULL(IIF(saldo.OperDay = @Date, saldo.RestIn, saldo.RestOut), 0)  as rest,
			ISNULL(rest.OverIn, 0) as over_in, 
			ISNULL(rest.OverOut, 0) as over_out	
		FROM @ContractList lst
		INNER JOIN [Loan].[Issue] iss ON iss.IssueID = lst.ID
		INNER JOIN [Loan].[Contract] con ON con.ContractID = iss.ContractID
		INNER JOIN [Loan].[Register] rg ON rg.ContractID = con.ContractID AND rg.IssueID = iss.IssueID
		--INNER JOIN @EnabledRegisters er ON er.id = rg.RegisterID 
		INNER JOIN @TargetRegTypes rf ON 
			rf.RegisterTypeID = rg.RegisterTypeID 
			AND rf.[level] = 0			-- 0-го уровня
			AND rf.SubType = 1 -- траншевые регистры
		LEFT JOIN [Loan].[RegisterRest] rest WITH (NOLOCK) ON rest.RegisterID = rg.RegisterID and rest.OperDay = @date
		OUTER APPLY
		(
			SELECT TOP(1) OperDay, RestIn, RestOut
			FROM [Loan].[RegisterRest] WITH (NOLOCK)
			WHERE RegisterID = rg.RegisterID and OperDay <= @date
			ORDER BY OperDay DESC
		) saldo	
		WHERE lst.IdType = 1 AND con.ContractType IN (2, 3, 6, 7)

		-- 1.4. Регистры кредитных портфелей
		INSERT INTO @RegisterList
		SELECT DISTINCT
			rg.RegisterID,
			rg.RegisterTypeID,
			prt.PortfolioID,
			NULL,
			NULL,
			lst.ID as contract_oid,
			ISNULL(IIF(saldo.OperDay = @Date, saldo.RestIn, saldo.RestOut), 0)  as rest,
			ISNULL(rest.OverIn, 0) as over_in, 
			ISNULL(rest.OverOut, 0) as over_out	
		FROM @ContractList lst
		INNER JOIN GbPledges.Portfolio prt ON prt.PortfolioID = lst.ID
		LEFT JOIN [GbPledges].[PortfolioTypeBack] ptb WITH (NOLOCK) ON ptb.PortfolioTypeBackID = prt.[PortfolioTypeBack]
		INNER JOIN [Loan].[Register] rg ON rg.PortfolioID = prt.PortfolioID
		--INNER JOIN @EnabledRegisters er ON er.id = rg.RegisterID 
		INNER JOIN @TargetRegTypes rf ON 
			rf.RegisterTypeID = rg.RegisterTypeID 
			AND rf.[level] = 0			-- 0-го уровня
			AND rf.SubType = 2 -- портфельные регистры
		LEFT JOIN [Loan].[RegisterRest] rest WITH (NOLOCK) ON rest.RegisterID = rg.RegisterID and rest.OperDay = @date
		OUTER APPLY
		(
			SELECT TOP(1) OperDay, RestIn, RestOut
			FROM [Loan].[RegisterRest] WITH (NOLOCK)
			WHERE RegisterID = rg.RegisterID and OperDay <= @date
			ORDER BY OperDay DESC
		) saldo	
		WHERE lst.IdType = 2 AND 	
			@Date >= ptb.BeginDate	

		--select distinct * from @RegisterList
		--select '@@@ RegisterList' as step, GETDATE() as steptime
	END	
	/******************************************************************************************************************/
	BEGIN -- ЗАГРУЗКА СЧЕТОВ
		-- 4. Формируем список счетов
		DECLARE
			@DistantFutureDate date = '3000-01-01'

		-- Список счетов 
		DECLARE @AccountList table
		(	
			AccountID uniqueidentifier 				
			,AccountNumber varchar(255)
			,AccountName  varchar(255)
			,AccountType int
			,AccountTypeName varchar(255)
			,ContractListID uniqueidentifier
			,PortfolioID uniqueidentifier
			,ContractID uniqueidentifier
			,IssueID uniqueidentifier
			,IsActive bit
			,SubType int
			,Currency varchar(3)
			,WillClose datetime
			,UNIQUE CLUSTERED(AccountID, ContractListID)
			,INDEX IDX_Ref NONCLUSTERED (AccountType, PortfolioID, ContractID, IssueID)
		) 

		-- Счета договоров и кредитных линий		
		INSERT INTO @AccountList
		SELECT DISTINCT		    
			acc.AccountID		
			,bac.AccountNumber
			,bac.[Name] as AccountName
			,act.AccountTypeID
			,act.[Name] as AccountTypeName 
			,lst.ID as ContractListID
			,NULL as PortfolioID
			,acc.ContractID
			,NULL as IssueID			
			,IIF(act.AccountKind = 1, 1, 0) as IsActive
			,0 as SubType
			,IIF(ISNULL(bac.Currency, '810') = '810', '643', bac.Currency) AS Currency
			,IIF(bac.DateClose is null, @DistantFutureDate, bac.DateClose) as WillClose
		FROM @ContractList lst
		INNER JOIN [Loan].[Account] acc ON acc.ContractID = lst.ID 
		INNER JOIN [dbo].[T_Account] bac ON bac.AccountID = acc.BaseAccountID
		INNER JOIN [dbo].[T_AccountType] act ON act.AccountTypeID = acc.AccountType	
		OUTER APPLY
		(
			select 
				iif(ContractType = 1, 0, 1) as IsContract
			from Loan.Contract
			where ContractID = lst.Id
		) kd
		WHERE lst.IdType = 0 
			and cast(bac.DateOpen as date) <= @Date  
			and (bac.DateClose is null or cast(bac.DateClose as date) >= DateAdd(day, -@Depth, @Date))
			and not (act.AccountTypeID = 10143 and kd.IsContract = 1)

		-- Счета траншей кредитных линий и овердрафтов 		
		INSERT INTO @AccountList
		SELECT DISTINCT		    
			acc.AccountID		
			,bac.AccountNumber
			,bac.[Name] as AccountName
			,act.AccountTypeID
			,act.[Name] as AccountTypeName 
			,lst.ID as ContractListID
			,NULL as PortfolioID
			,NULL as ContractID
			,acc.IssueID			
			,IIF(act.AccountKind = 1, 1, 0) as IsActive
			,1 as SubType
			,IIF(ISNULL(bac.Currency, '810') = '810', '643', bac.Currency) AS Currency
			,IIF(bac.DateClose is null, @DistantFutureDate, bac.DateClose) as WillClose
		FROM @ContractList lst
		INNER JOIN [Loan].[Account] acc ON acc.IssueID = lst.ID
		INNER JOIN [dbo].[T_Account] bac ON bac.AccountID = acc.BaseAccountID
		INNER JOIN [dbo].[T_AccountType] act ON act.AccountTypeID = acc.AccountType	
		WHERE lst.IdType = 1 AND
			cast(bac.DateOpen as date) <= @Date AND 
			(bac.DateClose is null or cast(bac.DateClose as date) >= DateAdd(day, -@Depth, @Date))

		-- Счета портфелей	
		INSERT INTO @AccountList
		SELECT DISTINCT		    
			acc.AccountID		
			,bac.AccountNumber
			,bac.[Name] as AccountName
			,act.AccountTypeID
			,act.[Name] as AccountTypeName 
			,lst.ID as ContractListID
			,acc.PortfolioID
			,NULL as ContractID
			,NULL as IssueID			
			,IIF(act.AccountKind = 1, 1, 0) as IsActive
			,2 as SubType
			,IIF(ISNULL(bac.Currency, '810') = '810', '643', bac.Currency) AS Currency
			,IIF(bac.DateClose is null, @DistantFutureDate, bac.DateClose) as WillClose
		FROM @ContractList lst
		INNER JOIN [Loan].[Account] acc ON acc.PortfolioID = lst.ID and acc.ContractID is null and acc.IssueID is null
		INNER JOIN [dbo].[T_Account] bac ON bac.AccountID = acc.BaseAccountID
		INNER JOIN [dbo].[T_AccountType] act ON act.AccountTypeID = acc.AccountType		
		WHERE lst.IdType = 2 AND
			cast(bac.DateOpen as date) <= @Date AND 
			(bac.DateClose is null or cast(bac.DateClose as date) >= @Date)

		-- Исключаем из рассмотрения счета с неопределенными номерами
		delete 
		from @AccountList 
		where not (len(rtrim(ltrim(AccountNumber))) = 20 and AccountNumber not like '%[^0-9]%')

		--select * from @AccountList
	END

	/******************************************************************************************************************/
	BEGIN -- СВЯЗКА СЧЕТ-РЕГИСТР		
		--============================================================================================================
		--  Прямой ход алгоритма:
		--  Назовем счет А доступным для регистра R, если тип счета А связан с типом регистра R или с одним из его родительских типов. 
		--  Для каждого регистра, из всех доступных в рамках договора счетов, выбираем наиболее приоритетный.
		--  Счета выстраиваются по приоритетам в соответствии с таблицей @TypeLinks. Если тип счета непосредственно связан
		--  с типом регистра, выставляется высшийц приоритет. Если счет связан с предками типа регистра, выставляются более низкие
		--  приоритеты (чем дальше поколения предка регистра, связанного со счетом, тем ниже приоритет). Приоритет может быть перенастроен, 
		--  если есть такая необходимость  
		--============================================================================================================	
		-- Избыточный список пар (Регистр - Счет)
		DECLARE 
			@ExtendedList table
			(
				RegisterID uniqueidentifier, 
				AccountID uniqueidentifier, 
				PortfolioID uniqueidentifier,
				ContractID uniqueidentifier, 
				IssueID uniqueidentifier, 
				RegSubType int,
				BaseRegType int, 
				RegLevel int
			)

		insert into @ExtendedList
		select distinct 
			rgs.RegisterID, 
			lac.AccountID, 
			rgs.PortfolioID,
			rgs.ContractID, 
			rgs.IssueID,
			trt.SubType as RegSubType,
			trt.LastRegisterTypeID as BaseRegType, 
			trt.[level] as RegLevel
		from @RegisterList rgs
		inner join @TargetRegTypes trt on trt.RegisterTypeID = rgs.RegisterTypeID
		outer APPLY
		(
			select top(1) al.AccountID
			from @TypeLinks tl
			inner join @AccountList al on 
				al.AccountType = tl.AccountTypeID and 
				(
					--(al.SubType = 0 and al.ContractID = rgs.ContractID and al.IssueID = NULL and rgs.IssueID IS NULL) OR
					--(al.SubType = 1 and al.IssueID = rgs.IssueID) OR
					--(al.SubType = 2 and al.PortfolioID = rgs.PortfolioID and rgs.ContractID IS NULL)
					(al.PortfolioID is not null and rgs.PortfolioID is not null and al.PortfolioID = rgs.PortfolioID) or
					(al.IssueID is not null and rgs.IssueID is not null and al.IssueID = rgs.IssueID) or
					(al.ContractID is not null and rgs.ContractID is not null and al.ContractID = rgs.ContractID)						
				)			
			where tl.RegisterTypeID = rgs.RegisterTypeID
			order by tl.AccountPriority asc, al.WillClose desc
		) lac
		where lac.AccountID is not null

		-- Добавляем не прописанные в стандартной схеме счета резервов на возможные потери >>>
		insert into @ExtendedList
		select distinct 
			rgs.RegisterID, 
			lac.AccountID, 
			rgs.PortfolioID,
			rgs.ContractID, 
			rgs.IssueID,
			trt.SubType as RegSubType,
			trt.LastRegisterTypeID as BaseRegType, 
			1 as RegLevel
		from @RegisterList rgs
		inner join @TargetRegTypes trt on trt.RegisterTypeID = rgs.RegisterTypeID
		outer APPLY
		(			
			select top(1) al.AccountID
			from @TypeLinks tl
			inner join @AccountList al on 
				al.AccountType = tl.AccountTypeID and 
				(
					(al.PortfolioID is not null and rgs.PortfolioID is not null and al.PortfolioID = rgs.PortfolioID) or
					(al.IssueID is not null and rgs.IssueID is not null and al.IssueID = rgs.IssueID) or
					(al.ContractID is not null and rgs.ContractID is not null and al.ContractID = rgs.ContractID)						
				)			
			where tl.AccountTypeID = 10050 and
				tl.RegisterTypeID = rgs.RegisterTypeID	
			order by al.WillClose desc
		) lac
		where lac.AccountID is not null
		-- <<< Добавляем не прописанные в стандартной схеме счета резервов на возможные потери 

		--select * from @ExtendedList

		--============================================================================================================
		--  Обратный ход алгоритма:
		--  ОПРЕДЕЛЕНИЕ
		--  Регистр называем базовым, если его тип присутствует в таблице @TargetRegTypes, причем
		--  значения полей RegisterTypeID и LastRegisterTypeID - совпадают.
		--  Регистры считаем эквивалентными, если они относятся к одному договору и траншу и имеют 
		--  одинаковый базовый тип LastRegisterTypeID, прописанный в таблице @TargetRegTypes.
		--		Из каждого набора эквивалентных регистров, выбираем тот, чей уровень RegLevel минимален. 
		--  Смысл уровня регистра - количество переходов от базового к текущему. Например, траншевый регистр ОдСрТр (7) 
		--  является базовым для ОдСр (5). 
		--  Если в одном классе присутствуют одновременно регистры ОдСрТр и ОдСр, то выбираем только ОдСрТр, а ОдСр отбрасывается
		--  Если в одном классе присутствуют одновременно несколько базовых регистров, то учитываются они все.		
		--============================================================================================================	
		-- Список пар (ID регистра - ID счета) для выгрузки
		DECLARE
			@TargetList table(RegisterID uniqueidentifier, AccountID uniqueidentifier, IsExternal bit) 
	
		-- Из каждого класса эквивалентности выбираем по одному регистру с минимальным уровнем наследования 
		insert into @TargetList
		select distinct member.RegisterID, member.AccountID, 0 
		from @ExtendedList ext		
		outer APPLY
		(
			select top(1) RegisterID, AccountID
			from @ExtendedList
			where 
				(
					(ext.RegSubType = 2 and PortfolioID = ext.PortfolioID) or
					(ext.RegSubType = 1 and IssueID = ext.IssueID) or
					(ext.RegSubType = 0 and ContractID = ext.ContractID)
				)
				and BaseRegType = ext.BaseRegType
			order by RegLevel
		) member
		where not member.AccountID is null

		-- Добавляем, если есть, не прописанные в стандартной схеме счета резервов на возможные потери >>>
		insert into @TargetList
		select distinct 
			ext.RegisterID, ext.AccountID, 1 
		from @ExtendedList ext
		inner join Loan.Account acc with (nolock) on acc.AccountID = ext.AccountID		
		where ext.BaseRegType in (113, 114) 
			and acc.AccountType = 10050
			and not ext.AccountID is null
		-- <<< Добавляем, если есть, не прописанные в стандартной схеме счета резервов на возможные потери

		--select * from @TargetList lst
		----inner join @RegisterList rgs on rgs.RegisterID = lst.RegisterID
		----inner join @AccountList acs on acs.AccountID = lst.AccountID 

	END
	
	/******************************************************************************************************************/
	BEGIN -- ВЫГРУЗКА В МСФО-9
	DECLARE	@rc_main int, @rc_cess int

		DROP TABLE IF EXISTS #msfo9_account_tr			
		SELECT DISTINCT			
			@Date as date1, 
			lst.branch_code,
			@Source as source, 
			--rgs.RegisterID as oid, 
			IIF(pars.IsExternal = 1, Loan.fn_InvertGUID(rgs.RegisterID), rgs.RegisterID) as oid,
			acs.AccountNumber as number, 			
			rgt.[Name] + ' ' + lst.[Name] +					
				IIF(cust.[Name] is null, '', ' ('+ TRIM(cust.[Name]) +')')	as [name],
			acs.AccountNumber as number_balance, 				
			iif(lst.IdType = 2, NULL, rgs.contract_oid) as contract_oid, 
			lst.CustomerID as client_oid,	
			IIF(acs.IsActive = 1, 1, -1) * rgs.rest  as ik_val,			--входящий остаток на дату выгрузки в валюте счета
			IIF(acs.IsActive = 1, rgs.Over_In, -rgs.Over_Out) as dk_val,	--дебетовый оборот за дату выгрузки в валюте счета
			IIF(acs.IsActive = 1, -rgs.Over_Out, rgs.Over_In) as ck_val,	--кредитовый оборот за дату выгрузки в валюте счета						
			acs.currency as curr, 
			cast(rgs.RegisterTypeID as varchar) + IIF(pars.IsExternal = 1, 'r', '') as account_type, 	
			1 as is_registr,
			rgs.PortfolioId as portfolio_oid,
			NULL as disposal_val	
		INTO #msfo9_account_tr			
		FROM @TargetList pars
		INNER JOIN @RegisterList rgs ON rgs.RegisterID = pars.RegisterID
		INNER JOIN Loan.RegisterType rgt WITH (NOLOCK) ON rgt.RegisterTypeID = rgs.RegisterTypeID
		OUTER APPLY
		(
			SELECT TOP(1) *
			FROM @AccountList 
			WHERE AccountID = pars.AccountID
			ORDER BY SubType DESC			
		) acs
		INNER JOIN @ContractList lst ON lst.ID = acs.ContractListID
		LEFT JOIN [dbo].[T_Customer] cust WITH (NOLOCK) ON cust.[CustomerID] = lst.CustomerID	
		where rgt.RegisterTypeID <> 38 -- !!! Установить в INNER JOIN Loan.RegisterType фильтр на все не операционные регистры !!!
		
		SET @rc_main = @@ROWCOUNT
		
		INSERT INTO [dbo].[syn_MSFO_msfo9_account_tr]	
		SELECT * FROM #msfo9_account_tr
		
		EXEC @rc_cess = [Loan].[msfo9_account_cession_tr]	@Source, @Date

	END	
	/******************************************************************************************************************/
	RETURN  @rc_main + @rc_cess
END
