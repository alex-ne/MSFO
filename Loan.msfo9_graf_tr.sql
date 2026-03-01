/****** Object:  StoredProcedure [Loan].[msfo9_graf_tr]    Script Date: 29.10.2024 12:07:59 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 07/12/2023
-- Description:	Выгрузка в МСФО информации по движениям средств, связанных с КД
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[msfo9_graf_tr] 
	@Source varchar(100),
	@Date date, 				 -- Выгружаются графики на заданную дату @Date. Eсли @Date = NULL - выгружаются графики на текущую дату
	@ContractID uniqueidentifier = NULL -- Только для КД с идентификатором @ContractID. Если @ContractID = NULL - ограничение не налогается.
AS
BEGIN
	-- Список идентификаторов траншей и кредитных договоров, 
	-- удовлетворяющих критерию, построенному на основании параметров процедуры
	DECLARE
		@BaseIds table (ContractId uniqueidentifier, IssueId uniqueidentifier)

	INSERT INTO @BaseIds
	SELECT 		    
		isnull(con.ContractID, iss.ContractID),
		iss.IssueID
	FROM dbo.syn_MSFO_msfo9_loan_tr lc
	LEFT JOIN [Loan].[Issue] iss ON iss.IssueID = lc.oid
	LEFT JOIN [Loan].[Contract] con ON con.ContractID = lc.oid and not con.ContractType in (2, 3, 6)			
	WHERE 
		lc.source = @Source AND 
		DATEDIFF(day , ISNULL(@date, lc.date1), lc.date1) = 0 AND
		((@ContractID IS NULL) OR (con.ContractID = @ContractID))

	-- Удаляем выгрузку с теми же параметрами (если была произведена ранее)
	DELETE FROM dbo.syn_MSFO_msfo9_graf_tr
	WHERE 
		(DATEDIFF(day , ISNULL(@date, date1), date1) = 0)
		AND 
		(source = @Source) 	

	SET @Date = ISNULL(@Date, GETDATE())
	
	DECLARE @Row_Count int = 0

	-- Графики траншей
	INSERT INTO dbo.syn_MSFO_msfo9_graf_tr
	SELECT 
		@Date as date1, 	
		@Source as source,
		ids.IssueId as contract_oid,
		mvs.date_payment, -- Дата платежа по графику выплат ОД транша
		mvs.debt_main,
		mvs.debt_interest,
		mvs.commissions,
		mvs.other_payments,
		mvs.other_expenses,
		mvs.overdue_main,
		mvs.overdue_interest,
		mvs.penalty
	FROM @BaseIds ids 
	OUTER APPLY
	(
		SELECT * 
		FROM [Loan].[fn_GetIssueGraphics](ids.IssueId, @Date)		
	) mvs
	WHERE 
		NOT ids.IssueId IS NULL AND	
		NOT mvs.date_payment IS NULL
	ORDER BY date_payment, contract_oid

	SET @Row_Count += @@rowcount

	-- Графики договоров
	INSERT INTO dbo.syn_MSFO_msfo9_graf_tr
	SELECT 
		@Date as date1, 	
		@Source as source,
		ids.ContractId as contract_oid,
		mvs.date_payment, -- Дата платежа по графику выплат ОД договора
		mvs.debt_main,
		mvs.debt_interest,
		mvs.commissions,
		mvs.other_payments,
		mvs.other_expenses,
		mvs.overdue_main,
		mvs.overdue_interest,
		mvs.penalty
	FROM @BaseIds ids 
	OUTER APPLY
	(
		SELECT * 
		FROM [Loan].[fn_GetContractGraphics](ids.ContractId, @Date)		
	) mvs
	WHERE 
		ids.IssueId IS NULL	AND	
		NOT mvs.date_payment IS NULL
	ORDER BY date_payment, contract_oid

	SET @Row_Count += @@rowcount

	RETURN @Row_Count

END
