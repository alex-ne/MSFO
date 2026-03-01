SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 06/11/2024
-- Description:	Выгрузка в МСФО счетов выбытия, относящихся к цессиям кредитных договоров
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[msfo9_account_cession_tr] 
	@Source varchar(100),
	@Date date 				    
AS
BEGIN

	DECLARE
		@CessionOperationType int = 88, -- тип операции цессии
		@AccountTypeID int = 10019		-- Счет выбытия

	-- Очистка транзитной таблицы МСФО - удаляем только счета выбытия

	DELETE FROM dbo.syn_MSFO_msfo9_account_tr
	WHERE 
	  source = @Source
	  AND
	  ISNULL(@date, date1) = date1
	  AND
	  account_type = @AccountTypeID AND is_registr = 0

	SET @Date = ISNULL(@Date, GETDATE())
	/******************************************************************************************************************/
	BEGIN -- 1. Cession Operation List
		-- Формируем список всех операций, имеющих отношение к операцям цессии
		DECLARE
			@CessionOperations table
			(
				BaseOperationID uniqueidentifier, 
				ParentOperationID uniqueidentifier, 
				ContractID uniqueidentifier, 
				IssueID uniqueidentifier, 
				[Level] int, 
				OperationTypeID int, 
				OperDate date, 
				OperSum decimal(21, 2), 
				[Status] int, 
				[Description] varchar(1024)
			)

		-- Все операции цессии на заданную дату (уровень 0)
		INSERT INTO @CessionOperations
		SELECT 
			BaseOperationID, 
			ParentOperationID, 
			ContractID, 
			IssueID, 
			0 as [Level], 
			OperationTypeID, 
			OperDate, 
			OperSum, 
			[Status], 
			[Description]
		FROM Loan.BaseOperation
		WHERE 
			OperationTypeID = @CessionOperationType
			and OperDate = @Date
			and [Status] = 1

		-- Добавляем дочерние операции первого уровня
		INSERT INTO @CessionOperations
		SELECT 
			bop.BaseOperationID, 
			bop.ParentOperationID, 
			bop.ContractID, 
			bop.IssueID, 
			1 as [Level], 
			bop.OperationTypeID, 
			bop.OperDate, 
			bop.OperSum, 
			bop.[Status], 
			bop.[Description]
		FROM @CessionOperations cess
		INNER JOIN Loan.BaseOperation bop ON bop.ParentOperationID = cess.BaseOperationID
		WHERE cess.[Level] = 0 and bop.[Status] = 1

		-- Добавляем дочерние операции второго уровня
		INSERT INTO @CessionOperations
		SELECT 
			bop.BaseOperationID, 
			bop.ParentOperationID, 
			bop.ContractID, 
			bop.IssueID, 
			2 as [Level], 
			bop.OperationTypeID, 
			bop.OperDate, 
			bop.OperSum, 
			bop.[Status], 
			bop.[Description]
		FROM @CessionOperations cess
		INNER JOIN Loan.BaseOperation bop ON bop.ParentOperationID = cess.BaseOperationID
		WHERE cess.[Level] = 1 and bop.[Status] = 1

		-- Удаляем из списка все операции, не связанные с целевым счетом AccountType = 10019
		DELETE FROM @CessionOperations 
		WHERE NOT EXISTS
		(
			SELECT *
			FROM Loan.[Transaction] trn 
			INNER JOIN Loan.[Account] acc ON acc.AccountID = trn.DtAccountID
			WHERE 
				trn.OperationID = BaseOperationID
				and acc.AccountType = @AccountTypeID
		)

		IF (SELECT COUNT(1) FROM @CessionOperations) = 0 RETURN 
	END
	/***********************************************************************************************************/

	BEGIN -- 2. Register Movements
	-- Движения по регистрам

	DECLARE
		@RegMovement table
		(
			MovementID uniqueidentifier, 
			BaseOperationID uniqueidentifier, 
			AccountID uniqueidentifier, 
			ContractID uniqueidentifier, 
			IssueID uniqueidentifier, 	
			RegisterID uniqueidentifier, 
			AccountTypeID int,
			OperationTypeID int, 
			RegisterTypeID int, 
			AccountNumber varchar(20),
			OperationDescription varchar(255),
			RegTypeName varchar(255),
			AccountTypeName varchar(255),
			OperDate date,
			ik_val decimal(31, 2),	
			dk_val decimal(31, 2),	
			ck_val decimal(31, 2),
			Currency varchar(3)
		)
	-- Формируем список проводок на счет выбытия, связанных с операциями передачи в цессию  
	INSERT INTO @RegMovement
	SELECT 
		mv.MovementID, 
		mv.BaseOperationID, 
		acc.AccountID,
		cess.ContractID, 
		cess.IssueID, 
		reg.RegisterID,
		acc.AccountType,
		cess.OperationTypeID,
		reg.RegisterTypeID,	
		bac.AccountNumber,
		cess.[Description] as OperationDescription,
		rgt.[Name] as RegTypeName,
		act.[Name] as AccountTypeName,
		cess.OperDate,
		IIF(act.AccountKind = 1, 1, -1) *
			ISNULL(IIF(saldo.OperDay = @Date, saldo.RestIn, saldo.RestOut), 0) as ik_val,	--входящий остаток на дату выгрузки в валюте счета
		IIF(act.AccountKind = 1, 
			ISNULL(saldo.OverIn, 0),
			-ISNULL(saldo.OverOut, 0)) as dk_val,											--дебетовый оборот за дату выгрузки в валюте счета
		IIF(act.AccountKind = 1,
			-ISNULL(saldo.OverOut, 0),
			ISNULL(saldo.OverIn, 0)) as ck_val,												--кредитовый оборот за дату выгрузки в валюте счета						
		IIF(ISNULL(bac.Currency, '810') = '810', '643', bac.Currency) AS Currency
	FROM @CessionOperations cess
	inner join Loan.[Transaction] trn on trn.OperationID = cess.BaseOperationID
	inner join Loan.[Account] acc on acc.AccountID = trn.DtAccountID 
	inner join dbo.T_AccountType act on act.AccountTypeID = acc.AccountType
	INNER JOIN [dbo].[T_Account] bac ON bac.AccountID = acc.BaseAccountID
	inner join Loan.Movement mv on mv.BaseOperationID = cess.BaseOperationID
	inner join Loan.Register reg on reg.RegisterID = mv.RegisterID
	inner join Loan.RegisterType rgt on rgt.RegisterTypeID = reg.RegisterTypeID
	OUTER APPLY
	(
		SELECT TOP(1) OperDay, RestIn, OverIn, OverOut, RestOut
		FROM [Loan].[RegisterRest] WITH (NOLOCK)
		WHERE RegisterID = reg.RegisterID and OperDay <= @date
		ORDER BY OperDay DESC
	) saldo	
	WHERE act.AccountTypeID = @AccountTypeID
		AND reg.RegisterTypeID <> 2 -- исключаем регистр изменения лимита
	ORDER BY cess.BaseOperationID
	END

	/***********************************************************************************************************/
	-- 3. ВЫГРУЗКА В МСФО
	INSERT INTO [dbo].[syn_MSFO_msfo9_account_tr]	
	SELECT 			
		@Date as date1, 
		IIF(brn.InnerCode IS NULL, '0000', brn.InnerCode) as branch_code,
		@Source as source, 
		src.AccountID as oid, 
		src.AccountNumber as number, 
		src.AccountTypeName + ' ' + bcn.Number + 
			IIF(cust.[Name] is null, '', '('+ TRIM(cust.[Name]) +')') as [name],
		src.AccountNumber as number_balance, 
		src.ContractID as contract_oid,  		
		bcn.Client as client_oid,	
		src.ik_val, --входящий остаток на дату выгрузки в валюте счета
		src.dk_val,	--дебетовый оборот за дату выгрузки в валюте счета
		src.ck_val,	--кредитовый оборот за дату выгрузки в валюте счета						
		src.Currency as curr, 
		src.AccountTypeID as account_type, 	
		0 as is_registr,
		pcn.PortfolioId as portfolio_oid,
		NULL as disposal_val		
	FROM 
	(
		select 
			AccountID, ContractID, AccountTypeID, AccountNumber, AccountTypeName, OperDate, Currency,
			SUM(ik_val) as ik_val, SUM(dk_val) as dk_val, SUM(ck_val) as ck_val
		from @RegMovement
		group BY
			AccountID, ContractID, AccountTypeID, AccountNumber, AccountTypeName, OperDate, Currency
	) src	
	INNER JOIN [dbo].[T_Contract] bcn WITH (NOLOCK) ON bcn.ContractID = src.ContractID
	INNER JOIN [GbPledges].[T_LoanContract] pcn WITH (NOLOCK) ON pcn.ContractID = bcn.ContractID
	LEFT JOIN [dbo].[T_Branch] brn WITH (NOLOCK) ON brn.BranchID = bcn.Branch
	LEFT JOIN [dbo].[T_Customer] cust WITH (NOLOCK) ON cust.[CustomerID] = bcn.Client

	RETURN @@ROWCOUNT

END
