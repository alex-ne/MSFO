SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- Version 2.141.4.0
CREATE OR ALTER PROCEDURE [Loan].[pr_LoadMsfo9Corrections]
	@date   [datetime],
	@branch [int]
WITH EXECUTE AS CALLER
AS
BEGIN
	SET @date = ISNULL(@date, GETDATE())

	DECLARE @CorrectionList table
	(
		Idx int IDENTITY(1,1), 
		Source varchar(10),				
		ContractID uniqueidentifier,
		IssueID uniqueidentifier,
		PortfolioID uniqueidentifier,
		MsfoOperationType varchar(255),
		TransactionDate date,		
		TransactionSum decimal(31, 2),
		AccNumberDebet varchar(255),
		SymbolDebet varchar(5),
		AccNumberCredit varchar(255),
		SymbolCredit varchar(5),
		Description varchar(255)
	)
	
	-- Добавляем новые операции МСФО из транзитной таблицы с пометкой Source = 'MSFO'
	INSERT INTO @CorrectionList
	SELECT 
		'MSFO' as Source,		
		CAST([contract_oid] as uniqueidentifier) as ContractID,
		CAST(NULLIF([tranche_oid], '') as uniqueidentifier) as IssueID,
		CAST(NULLIF([portfolio_oid], '') as uniqueidentifier) as PortfolioID,
		[operation_type] as MsfoOperationType,
		[date1] as TransactionDate,		
		[sum_rub] as TransactionSum,
		[acc_number_debet] as AccNumberDebet,
		substring([acc_number_debet], 14, 5) as SymbolDebet,
		[acc_number_credit] as AccNumberCredit,
		substring([acc_number_credit], 14, 5) as SymbolCredit,
		[payment_purpose] as Description
	FROM [dbo].[syn_MSFO_msfo9_acc_entries_tr]
	WHERE [date1] = @Date AND [source] = 'GEstBank-Loan' and [branch_code] = @branch
	
	
	
	ORDER BY ContractID, IssueID, PortfolioID
	
	

	select r.* from @CorrectionList r
	 inner join Loan.Contract c with (nolock) on r.ContractId = c.ContractId
	union all
	select r.* from @CorrectionList r
	 inner join GbPledges.Portfolio p with (nolock) on r.PortfolioID = p.PortfolioID 

END;
