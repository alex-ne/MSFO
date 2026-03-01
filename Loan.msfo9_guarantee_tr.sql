SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 10/12/2024
-- Description:	Выгрузка в МСФО-9 договоров гарантий
-- =============================================
-- Modified 20251111
CREATE OR ALTER PROCEDURE [Loan].[msfo9_guarantee_tr]
	@Source varchar(40),
	@Date date = NULL, 					-- выгружаются данные на заданную дату	
	@ContractID uniqueidentifier = NULL -- Идентификатор выгружаемого КД. Если NULL - выгрузка по всем договорам
AS
BEGIN
	print '[Кредиты] Договора гарантий'

	-- Очистка транзитной таблицы ОО
	DELETE FROM dbo.syn_MSFO_msfo9_guarantee_tr
	WHERE 
		source = @Source
		AND
		DATEDIFF(day , ISNULL(@date, date1), date1) = 0
		AND
		((@ContractID IS NULL) OR (oid = @ContractID))	  


	-- ВЫГРУЗКА
	SET @Date = ISNULL(@Date, GETDATE())

	-- Таблица соответствия состояний гарантии и состояний базового проекта
	DECLARE
		@GuaranteeStatusMapping table
		(
			Id int,
			BaseId int,
			GuaranteeStatusName varchar(25),
			ProjectStatusName varchar(25)
		)

	INSERT INTO @GuaranteeStatusMapping
	VALUES
		(6, 1, 'Действует', 'Открыт'),
		(8, 2, 'Закрыта', 'Закрыт'),
		(9, 2, 'Оплачена по требованию', 'Закрыт'),
		(10, 0, 'Проект', 'Проект'),
		(11, 3, 'Аннулирована до выдачи', 'Удален')

	-- Формируем список гарантий для выгрузки на заданную дату
	DECLARE
		@GuaranteeList table
		(
			ContractID uniqueidentifier,
			GarantType int,
			IsLine bit,
			GarantStatus int,
			GarantScope uniqueidentifier,
			Beneficiary uniqueidentifier,
			MainContract uniqueidentifier,
			Number varchar(50),
			ContractDate date,
			StartDate date,
			EndDate date,
			ClosedDate date,
			Branch int, 
			Division int,
			Client uniqueidentifier,
			Currency varchar(3),
			BeneficiaryCreditCommisionSum decimal(19, 2),
			ReservRatio decimal(6, 4),			
			QualityCode int,
			PortfolioID uniqueidentifier
		)

	INSERT INTO @GuaranteeList
	SELECT 
		con.ContractID, 
		con.GarantType,
		IIF(con.GarantKind in (1, 2), 1, 0) as IsLine,
		ISNULL(info.ContractGarantStatus, con.ContractGarantStatus) as GarantStatus,
		con.GarantScope,
		con.Beneficiary,
		IIF(con.GarantKind = 3, con.GarantLineContract, NULL) as MainContract,
		ISNULL(info.Number, dcn.Number) as Number,
		ISNULL(info.ContractDate, dcn.ContractDate) as ContractDate,
		ISNULL(info.StartDate, dcn.StartDate) as StartDate,
		ISNULL(info.EndDate, dcn.EndDate) as EndDate,
		ISNULL(info.ClosedDate, dcn.ClosedDate) as ClosedDate,
		ISNULL(info.Branch, dcn.Branch) as Branch,
		ISNULL(info.Division, dcn.Division) as Division, 
		ISNULL(info.Customer, dcn.Client) as Client,
		ISNULL(crr.InternationalCode, '643') as Currency,	
		con.BeneficiaryCreditCommisionSum,
		risk.ReservRatio, --as coef_reserve,				
		risk.QualityCode, --as category_quality,
		ISNULL(portfolio.CurrentID, pcn.PortfolioID) as PortfolioID	
	FROM [Loan].[Contract] con
	INNER JOIN [dbo].[T_Contract] dcn ON dcn.ContractID = con.ContractID
	INNER JOIN [GbPledges].[T_LoanContract] pcn ON pcn.ContractID = dcn.ContractID
	OUTER APPLY
	(
		SELECT TOP(1)
			conh.[CreateDate]					
			,dcnh.[ContractDate]				
			,dcnh.[EndDate]						
			,dcnh.[ClosedDate]					
			,dcnh.[Number]						
			,dcnh.[StartDate]					
			,dcnh.[Status]						
			,dcnh.[Branch]						
			,dcnh.[Division]					
			,dcnh.[Customer]					
			,dcnh.[Currency]			
			,conh.[ContractGarantStatus]
			,gsm.BaseId as BaseStatus
		FROM [Loan].[ContractHistory] conh
		INNER JOIN [dbo].[T_Contract_History] dcnh ON dcnh.HistoryID = conh.HistoryID		
		INNER JOIN @GuaranteeStatusMapping gsm ON gsm.Id = conh.[ContractGarantStatus]
		WHERE 
			dcnh.ChangeType in (37,38,39,40) AND
			CAST(conh.CreateDate as DATE) <= @Date AND
			dcnh.[ContractID] = con.ContractID
		ORDER BY 
			conh.CreateDate DESC
	) info
	LEFT JOIN [dbo].[T_Currency] crr ON crr.Code = ISNULL(info.Currency, dcn.Currency) 
	OUTER APPLY 
	(
		SELECT
				rgh.[ReservationRateValue] as ReservRatio,
				rgr.Code as QualityCode
		FROM [dbo].[T_ChangeCustomerRiskGroup] rgh
		INNER JOIN [dbo].[T_RiskGroup] rgr ON rgr.RiskGroupID = rgh.NewValueRiskGroup
		WHERE
			rgh.[ChangeCustomerRiskGroupID] = [Loan].[fn_ContractCategoryQuality](con.ContractID, @Date)
	) risk
	OUTER APPLY 
	(
		SELECT TOP (1) cph.[PortfolioID] as CurrentID
		FROM [GbPledges].[ContractPortfolioHistory] cph
		WHERE 
			cph.[ContractID] = con.ContractID AND 
			cph.DateBegin <= @date
		ORDER BY DateBegin DESC
	) portfolio
	WHERE con.ContractKind = 2
		AND IsNULL(info.BaseStatus, dcn.[Status]) in (1, 2) -- рассматриваем только открытые или закрытые гарантии 
		AND (@Date BETWEEN info.ContractDate AND ISNULL(info.ClosedDate, @Date)) -- Дата выгрузки попадает в интервал действия гарантии, включая день закрытия

	--select * from @GuaranteeList

	-- ВЫГРУЗКА В ТРАНЗИТНУЮ ТАБЛИЦУ
	INSERT INTO dbo.syn_MSFO_msfo9_guarantee_tr
	(
		[date1]							--[date] NOT NULL, дата, за которую выгружаются данные
		,[branch_code]					--[int] NOT NULL, официальный код филиала от ЦБ
		,[division_code]				--[int] NULL, код подразделения
		,[source]						--[varchar](40) NOT NULL, источник данных (код учетной системы банка, откуда были выгружены данные)
		,[oid]							--[varchar](60) NOT NULL, идентификатор гарантии в учетной системе банка
		,[number]						--[varchar](255) NULL, Номер гарантии/неиспользованной гарантийной линии/аккредитива
		,[beneficiary_inn]				--[varchar](255) NULL, ИНН, для нерезидентов - КИО Бенефициара		  
		,[beneficiary_name]				--[varchar](255) NULL, Наименование Бенефициара		  
		,[curr]							--[varchar](3) NOT NULL, Валюта гарантии/неиспользованной гарантийной линии/аккредитива. Трехзначный цифровой ОКВ (643 - руб., 840 - доллары США и т.д.)		  
		,[date_open]					--[date] NOT NULL, Дата выдачи		  
		,[date_end]						--[date] NULL, Дата истечения					  
		,[date_close]					--[date] NULL, Дата фактического окончания договора					  
		,[type_guarantee]				--[varchar](60) NOT NULL, Идентификатор справочника видов гарантий. Справочник: Гарантии_Типы
		,[comission_rate]				--[decimal](18, 6) Комиссия за открытие гарантии/неиспользованной гарантийной линии/аккредитива. В процентах, при выгрузке в долях, пример: 0,01 (для 1%)
		,[comission_sum]				--[decimal](18, 2) сумма  комиссии/лимит гарантийной линии в валюте договора
		,[comission_rate_year]  		--[decimal](18, 6) Комиссия за открытие гарантии/неиспользованной гарантийной линии/аккредитива. В процентах годовых, при выгрузке в долях, пример: 0,01 (для 1%)
		,[client_oid]					--[varchar](60) NOT NULL, идентификатор клиента(принципала) в учетной системе банка		  		  
		,[is_line]						--[bit] NOT NULL, признак гарантийной линии				  
		,[main_contract_oid]			--[varchar](60) NULL, Идентификатор договора гарантийной линии в учетной системе банка. Заполняется только для гарантий выданных в рамках гарантийной линии			  
		,[summa_val]					--[decimal](18, 2) NOT NULL, Сумма гарантии/лимит гарантийной линии в валюте договора	  
		,[coef_reserve]					--[decimal](18, 6) NULL, % расчетного резерва по РСБУ на отчетную дату. Например, в виде коэффициента: 0.01 для 1%.		  
		,[category_quality]				--[int] NULL, Категория качества, которая соответствует коэффициенту резервирования coef_reserve					  
		,[portfolio_oid]				--[varchar](60) NULL, идентификатор портфеля, если договор отнесен к портфелю
	)
	SELECT 
		@Date as date1,
		ISNULL(lst.Branch, 0) as branch_code,
		dbo.Get_Division_Code(lst.Division) as division_code,
		@Source as source,
		lst.ContractID as oid,
		lst.Number as number,						
		cus.INN as beneficiary_inn,			
		cus.[Name] as beneficiary_name,			
		lst.Currency as curr,						
		lst.ContractDate as date_open,					
		lst.EndDate as date_end,					
		lst.ClosedDate as date_close,					
		lst.GarantType as type_guarantee,	
		NULL as comission_rate,			
		lst.BeneficiaryCreditCommisionSum as comission_sum,			
		NULL as comission_rate_year,				
		lst.Client as client_oid,					
		lst.IsLine as is_line,	
		lst.MainContract as main_contract_oid,
		[Loan].[sf_GetContractRegisterRest](lst.ContractID, 2, @Date) as summa_val, 
		lst.ReservRatio as coef_reserve,				
		lst.QualityCode as category_quality,
		lst.PortfolioID as portfolio_oid				
	FROM @GuaranteeList lst
	LEFT JOIN [dbo].[T_Customer] cus ON cus.CustomerID = lst.Beneficiary

	RETURN @@ROWCOUNT
END




