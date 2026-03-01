SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 24/11/2023
-- Description:	Выгрузка в МСФО кредитных договоров, кредитных линий и траншей 
-- =============================================
-- Modify 2026-01-14
CREATE OR ALTER PROCEDURE [Loan].[msfo9_loan_tr] 
	@Source varchar(100),
	@Date date, 				    -- выгружаются все кредитные доглвора, открытые по состоянию на указанную дату. Если @Date = NULL 
									-- - дата выгрузки принимаеться текущая, состояние КД на дату не проверяется.	
	@ContractID uniqueidentifier = NULL   -- Идентификатор выгружаемого КД или транша (если @ContractID = NULL - условие не проверяется)
AS
BEGIN
	-- Очистка транзитной таблицы МСФО
	DELETE FROM dbo.syn_MSFO_msfo9_loan_tr
	WHERE 
	  source = @Source
	  AND
	  DATEDIFF(day , ISNULL(@date, date1), date1) = 0
	  AND
	  ((@ContractID IS NULL) OR (oid = @ContractID))

	-- Идентификатор потребительского кредита
    declare 
		@EmptyProductID uniqueidentifier 

	select @EmptyProductID = ProductID
	from dbo.T_Product
	where [Name] = 'Потребительский кредит'

	-- Список ID некорректных договоров и траншей, присутствующих в БД разработки:
	DECLARE @expContract table(Id uniqueidentifier)

	-- Исключаем договора, для которых не прописаны счета
	insert into @expContract(Id)
	select con.ContractID
	from [Loan].[Contract] con 
	where NOT EXISTS(select 1 from [Loan].[Account] where ContractID = con.ContractID)

	--DELETE FROM @expContract

	-- Список идентификаторов кредитных договоров, подлежащих выгрузке в транзитную таблицу МСФО
	DECLARE
		@LoanContractIds table (ID uniqueidentifier, ActualStatus int, FactCloseDate date, PortfolioID uniqueidentifier )
		INSERT INTO @LoanContractIds
		SELECT con.ContractID as ID, 
			act.[Status] as ActualStatus, 
			fact.CloseDate as FactCloseDate,
			ISNULL(pfl.PortfolioID, pcn.PortfolioID) as PortfolioID
		FROM [Loan].[Contract] con
		INNER JOIN [dbo].[T_Contract] bcn ON bcn.ContractID = con.ContractID
		INNER JOIN [GbPledges].[T_LoanContract] pcn WITH (NOLOCK) ON pcn.ContractID = con.ContractID
		OUTER APPLY	
		(
			SELECT CloseDate = IIF(con.ContractType = 6, 
				bcn.ClosedDate,
				[Loan].[sf_GetContractFactEndDate] (con.ContractID))
		) fact
		OUTER APPLY
		(
			SELECT
				IIF(bcn.[Status] in (1, 2), 1, 0) as IsValid,
				IIF(@Date >= ISNULL(bcn.StartDate, DATEADD(DAY, 1, @Date)) and @Date < ISNULL(bcn.ClosedDate, DATEADD(DAY, 1, @Date)), 1, 0) as IsOpened,
				IIF(@Date < ISNULL(bcn.ClosedDate, DATEADD(DAY, 1, @Date)), 0, 1) as IsClosed,
				(
					SELECT TOP (1)	[ContractStatus] as [Status]
					FROM [Loan].[ContractStatusHistory]
					WHERE [ContractID] = bcn.ContractID AND [OperDay] <= @Date 
					ORDER BY [OperDay] DESC, [DateChange] DESC
				) as HistoryStatus			
		) sfd
		OUTER APPLY
		(
				select IIF(sfd.IsValid = 1 and sfd.IsOpened = 1 and sfd.IsClosed = 0, 
					1, IIF(sfd.IsValid = 1 and sfd.IsClosed = 1, 
						2, ISNULL(sfd.HistoryStatus, 0))) as [Status]
		) act
		OUTER APPLY
		(
			SELECT TOP (1) [PortfolioID]
     		FROM [GbPledges].[ContractPortfolioHistory] WITH (NOLOCK)
			WHERE [ContractID] = con.ContractID and DateBegin <= @Date
			ORDER BY DateBegin DESC
		) pfl
		WHERE con.ContractKind = 0 AND	
			(act.[Status] = 1 
			 OR (NOT @date IS NULL 
				 AND act.[Status] = 2
				 AND @date = fact.CloseDate
				)
			)
			AND
			((@ContractID IS NULL) 
		     OR 
			 (con.[ContractID] = @ContractID))
			--AND
			--DATEDIFF(day , ISNULL(@date, bcn.StartDate), bcn.StartDate) = 0


drop table if exists #temp_contract_plan_repayment_date		
	-- ВЫГРУЗКА
	DECLARE @row_count int = 0;

with cte as (
select c.ContractID, tc.StartDate, min(ah.ChangeDate) ChangeDate
from Loan.Contract c 
	join dbo.T_Contract tc with (nolock) on c.ContractID = tc.ContractID
	join Loan.AgreementHistory ah with (nolock) on c.ContractID = ah.ContractID
  where ah.ChangeType = 4
	and ah.ChangeDate > @date
	and ((@ContractID IS NULL) OR (tc.[ContractID] = @ContractID)) 
group by c.ContractID, tc.StartDate
)

select ah.ContractID, dateadd(day, ContractTerm, cte.StartDate) PlanRepaymentDate
into #temp_contract_plan_repayment_date	
from Loan.AgreementHistory ah
	join cte with (nolock) on ah.ContractID = cte.ContractID and ah.ChangeDate = cte.ChangeDate 
where ah.ChangeType = 4 and ah.ContractTerm is not null and ah.IssueID is null;

	SET @Date = ISNULL(@Date, GETDATE())
	
	-- Добавление КД и КЛ из списка в транзитную таблицу МСФО
	INSERT INTO dbo.syn_MSFO_msfo9_loan_tr
		([date1],
		[branch_code],
		[division_code],
		[source],
		[oid],
		[main_contract_oid],
		[client_oid],
		[number],
		[date_open],
		[date_issue],
		[date_end],
		[date_close],
		[reason_end],
		[portfolio_oid],
		[purpose],
		[rate],		
		[id_credit_type],
		[id_product],
		[id_credit_segment],
		[summa_val],
		[curr],
		[coef_reserve],
		[category_quality],
		[date_start_overdue_principal],
		[date_start_overdue_interest],
		[id_graf_freq_main],
		[id_graf_freq_proc],
		[annual_payment],
		[is_over],
		[cline_type],
		[is_floating_rate],
		[oid_fi_class],
		[fair_value],	
		[is_mbk])
	SELECT DISTINCT
		@Date as date1, 	
		IIF(brn.InnerCode IS NULL, 0, brn.InnerCode) as branch_code,	--официальный код филиала от ЦБ
		dbo.Get_Division_Code(dcn.Division) as division_code,--код подразделения
		@Source as source, 
		con.ContractID as oid, 
		NULL as main_contract_oid,
		cus.CustomerID as client_oid, 
		dcn.Number as number, 	
		dcn.ContractDate as date_open, 
		(	
			SELECT MIN(iss.IssueDate) 
			FROM [Loan].[Issue] iss 
			WHERE iss.ContractID = con.ContractID
		) as date_issue, 	 		 
		isnull(tmp.PlanRepaymentDate, ISNULL(ids.FactCloseDate, dcn.EndDate)) as date_end,
		IIF(ids.ActualStatus < 2, NULL, ids.FactCloseDate) as date_close,
		IIF(ids.ActualStatus = 2, IIF(ISNULL(ocs.is_cession, 0) = 1, 'Цессия', 'Погашен'), NULL) as reason_end,
		ids.PortfolioID as portfolio_oid,
		Pps.[Name] as purpose,		 		 
		ISNULL(prt.fordate, 0) as rate, --процентная ставка на дату выгрузки	--!!! Костыль - исправить в данных !!!
		ISNULL(prd.ProductID, @EmptyProductID) as id_credit_type,  -- идентификатор типа кредита. Из справочника: Кредиты_Типы кредита 
		con.ProductTypeID as id_product,
		CAST(per.MSBCriterion as varchar(255)) as id_credit_segment,
		ISNULL([Loan].[sf_GetContractSum](con.ContractID, @Date), 0) as summa_val,
		IIF(ISNULL(dcn.Currency, '810') = '810', '643', dcn.Currency) as curr,
		risk.ReservRatio as coef_reserve,
		risk.QualityCode as category_quality,
		coi.dt_Overdue as date_start_overdue_principal,	     
	    coi.dt_ProcOverdue as date_start_overdue_interest,
		ISNULL(con.RepaymentScheduleType, 15) as id_graf_freq_main, --График погашения основного долга. Из справочника: Типы графиков выплат
		ISNULL(con.RepaymentScheduleType, 15) as id_graf_freq_proc,  --График погашения процентов. Из справочника: Типы графиков выплат
		con.ApproxMonthlyPayment as annual_payment,  --Размер периодического платежа при аннуитетном погашении
		IIF(con.ContractType = 6, 1, 0) as is_over, --Признак овердрафта			
		case con.ContractType
			when 3 then 'ВКЛ'
			when 2 then 'НКЛ'
			else NULL
		end as cline_type, --тип кредитной линии
		IIF(frt.code > 0, 1, 0) as is_floating_rate, --признак плавающей ставки
		NULL as oid_fi_class, -- ???
		NULL as fair_value, --Справедливая стоимость в валюте договора	 
  		0 as is_mbk
	FROM @LoanContractIds ids 
		INNER JOIN [Loan].[Contract] con WITH (NOLOCK) ON con.ContractID = ids.ID
		INNER JOIN [dbo].[T_Contract] dcn WITH (NOLOCK) ON dcn.ContractID = con.ContractID AND dcn.[Status] < 3
		LEFT JOIN [dbo].[T_Branch] brn WITH (NOLOCK) ON brn.BranchID = dcn.Branch
		INNER JOIN [dbo].[T_Customer] cus WITH (NOLOCK) ON cus.CustomerID = dcn.Client 	
		LEFT JOIN [dbo].[T_LegalPerson] per WITH (NOLOCK) ON per.LegalPersonID = cus.LegalPerson
		LEFT JOIN [GbPledges].[T_LoanPurpose] pps WITH (NOLOCK) ON pps.LoanPurposeID = con.LoanPurposeID
		INNER JOIN loan.ProductType pdt WITH (NOLOCK) ON pdt.ProductTypeID = con.ProductTypeID
		LEFT JOIN dbo.T_LoanProgram prg WITH (NOLOCK) ON prg.LoanProgramID = pdt.LoanProgramID
		LEFT JOIN dbo.T_Product prd WITH (NOLOCK) ON prd.ProductID = prg.Product	
		LEFT JOIN #temp_contract_plan_repayment_date tmp WITH (NOLOCK) ON con.ContractID = tmp.ContractID
		OUTER APPLY [Loan].[fn_GetContractOverdueInfo](con.ContractID, @Date) coi				
		OUTER APPLY 
		(
			SELECT TOP(1) IIF(cop.BaseOperationID IS NULL, 0, 1) is_cession
			FROM [Loan].[BaseOperation] cop WITH (NOLOCK) 
			WHERE cop.ContractID = con.ContractID 
				AND cop.[Status] = 1
				AND cop.OperationTypeID = 88
				AND cop.OperDate <= @Date
			ORDER BY cop.OperDate DESC
		) ocs
		OUTER APPLY 
		(
			SELECT
				 rgh.[ReservationRateValue] as ReservRatio,
				 rgr.Code as QualityCode
			FROM [dbo].[T_ChangeCustomerRiskGroup] rgh
			INNER JOIN [dbo].[T_RiskGroup] rgr WITH (NOLOCK) ON rgr.RiskGroupID = rgh.NewValueRiskGroup 
			WHERE 
				rgh.[ChangeCustomerRiskGroupID] =	[Loan].[fn_ContractCategoryQuality](con.ContractID, @Date)
		) risk
		OUTER APPLY
		(
			SELECT SUM(ISNULL(shv.[BaseRateID], 0) * ISNULL(shv.Rate, 0)) as code 
			FROM [Loan].[Issue] iss WITH (NOLOCK)
			LEFT JOIN [Loan].[PercentSchemeValue] shv WITH (NOLOCK) ON shv.PercentSchemeID = iss.OdPercentScheme
			WHERE iss.ContractID = con.ContractID
		) frt
		OUTER APPLY
		(
			SELECT Loan.sf_GetSchemeValueForADate(con.OdPercentScheme, @Date) as fordate 
		) prt
	WHERE 	
		-- Исключаем некорректные  КД и КЛ, присутствующие в БД разработки:
		NOT con.ContractID IN (select id from @expContract)

	SET @row_count += @@ROWCOUNT;

	with cte as (
select iss.IssueID, iss.IssueDate, min(ah.ChangeDate) as ChangeDate from Loan.Issue iss
 join Loan.AgreementHistory ah with (nolock) on iss.IssueID = ah.IssueID  
  where ah.ChangeType = 1
	and ah.ChangeDate > @Date
	and ((@ContractID IS NULL) OR (iss.[ContractID] = @ContractID)) 
group by iss.IssueID, iss.IssueDate
)
select ah.IssueID, dateadd(day, IssueTerm, cte.IssueDate) PlanRepaymentDate
into #temp_issue_plan_repayment_date 
from Loan.AgreementHistory ah
		join cte with (nolock) on ah.IssueID = cte.IssueID and ah.ChangeDate = cte.ChangeDate 
where ah.ChangeType = 1 and cte.IssueDate is not null;

	-- Добавление траншей кредитных линий и овердрафтов в транзитную таблицу МСФО
	-- !!! Транши, не относящиеся к кредитным линиям или овердрафтов, не добавляются !!!
	INSERT INTO dbo.syn_MSFO_msfo9_loan_tr
		([date1],
		[branch_code],
		[division_code],
		[source],
		[oid],
		[main_contract_oid],
		[client_oid],
		[number],
		[date_open],
		[date_issue],
		[date_end],
		[date_close],
		[reason_end],
		[portfolio_oid],
		[purpose],
		[rate],		
		[id_credit_type],
		[id_product],
		[id_credit_segment],
		[summa_val],
		[curr],
		[coef_reserve],
		[category_quality],
		[date_start_overdue_principal],
		[date_start_overdue_interest],
		[id_graf_freq_main],
		[id_graf_freq_proc],
		[annual_payment],
		[is_over],
		[cline_type],
		[is_floating_rate],
		[oid_fi_class],
		[fair_value],	
		[is_mbk])
	SELECT DISTINCT
		@Date as date1, 	
		IIF(brn.InnerCode IS NULL, 0, brn.InnerCode) as branch_code,	--официальный код филиала от ЦБ
		dbo.Get_Division_Code(dcn.Division) as division_code,--код подразделения
		@Source as source, 
		iss.IssueID as oid, 
		iss.ContractID as main_contract_oid,  
		cus.CustomerID as client_oid, -- iss.Lessee
		iss.IssueNumber as number, 
		iss.IssueDate as date_open, 
		iss.IssueDate as date_issue, 
		isnull(tmp.PlanRepaymentDate, iss.PlanRepaymentDate) as date_end,
		fact.close_date as date_close,		 
		IIF(flags.is_end = 1, 'Погашен', NULL) as reason_end,
		ids.PortfolioID as portfolio_oid,
		Pps.[Name] as purpose,		 
		ISNULL(prt.fordate, 0) as rate, --процентная ставка на дату выгрузки	--!!! Костыль - исправить в данных !!!	 
		ISNULL(prd.ProductID, @EmptyProductID) as id_credit_type, --идентификатор типа кредита. Из справочника: Кредиты_Типы кредита		 
		con.ProductTypeID as id_product, 
		CAST(per.MSBCriterion as varchar(255)) as id_credit_segment,
		ISNULL(iss.IssueSum, 0) as summa_val, 
		IIF(ISNULL(dcn.Currency, '810') = '810', '643', dcn.Currency) as curr,
		risk.ReservRatio as coef_reserve,
		risk.QualityCode as category_quality,
		coi.dt_Overdue as date_start_overdue_principal,	     
	    coi.dt_ProcOverdue as date_start_overdue_interest,
		ISNULL(con.RepaymentScheduleType, 15) as id_graf_freq_main, --График погашения основного долга. Из справочника: Типы графиков выплат
		ISNULL(con.RepaymentScheduleType, 15) as id_graf_freq_proc,  --График погашения процентов. Из справочника: Типы графиков выплат
		con.ApproxMonthlyPayment as annual_payment,  --Размер периодического платежа при аннуитетном погашении
		0 as is_over, --Признак овердрафта
		NULL as cline_type, --тип кредитной линии
		IIF(frt.code > 0, 1, 0) as is_floating_rate, --признак плавающей ставки
		NULL as oid_fi_class,
		NULL as fair_value, --Справедливая стоимость в валюте договора	 
  		0 as is_mbk
	FROM @LoanContractIds ids 
		INNER JOIN [Loan].[Contract] con WITH (NOLOCK) ON con.ContractID = ids.ID  
		INNER JOIN [dbo].[T_Contract] dcn WITH (NOLOCK) ON dcn.ContractID = con.ContractID AND dcn.[Status] < 3
		INNER JOIN [Loan].[Issue] iss WITH (NOLOCK) ON iss.ContractID = con.ContractID				
		LEFT JOIN [dbo].[T_Branch] brn WITH (NOLOCK) ON brn.BranchID = dcn.Branch
		INNER JOIN [dbo].[T_Customer] cus WITH (NOLOCK) ON cus.CustomerID = dcn.Client 	
		LEFT JOIN [dbo].[T_LegalPerson] per WITH (NOLOCK) ON per.LegalPersonID = cus.LegalPerson
		LEFT JOIN [GbPledges].[T_LoanPurpose] pps WITH (NOLOCK) ON pps.LoanPurposeID = con.LoanPurposeID			
		INNER JOIN loan.ProductType pdt WITH (NOLOCK) ON pdt.ProductTypeID = con.ProductTypeID
		LEFT JOIN dbo.T_LoanProgram prg WITH (NOLOCK) ON prg.LoanProgramID = pdt.LoanProgramID
		LEFT JOIN dbo.T_Product prd WITH (NOLOCK) ON prd.ProductID = prg.Product	
		left join #temp_issue_plan_repayment_date tmp with (nolock) on iss.IssueID = tmp.IssueID
		OUTER APPLY [Loan].[fn_GetContractOverdueInfo](con.ContractID, @Date) coi
		OUTER APPLY
		(
			SELECT 		
				ISNULL((SELECT TOP(1) OperDate
					 FROM [Loan].[BaseOperation] WITH (NOLOCK) 
					 WHERE IssueID = iss.IssueID AND OperDate <= @Date AND [Status] = 1 AND OperationTypeID = 1
					 ORDER BY OperDate DESC), iss.IssueDate) as open_date,
				iss.CloseDate as close_date
		) fact
		OUTER APPLY
		(
			SELECT 
				IIF(fact.close_date < @Date, 1, 0) as is_end,
				IIF(@Date between fact.open_date and ISNULL(fact.close_date, @Date), 1, 0) as is_active 
		) flags
		OUTER APPLY 
		(
			SELECT
				 rgh.[ReservationRateValue] as ReservRatio,
				 rgr.Code as QualityCode
			FROM [dbo].[T_ChangeCustomerRiskGroup] rgh
			INNER JOIN [dbo].[T_RiskGroup] rgr WITH (NOLOCK) ON rgr.RiskGroupID = rgh.NewValueRiskGroup 
			WHERE 
				rgh.[ChangeCustomerRiskGroupID] = [Loan].[fn_IssueCategoryQuality](iss.IssueID, @Date)
		) risk
		OUTER APPLY
		(
			SELECT ISNULL(SUM(ISNULL(shv.[BaseRateID], 0) * ISNULL(shv.Rate, 0)), 0) as code 
			FROM [Loan].[PercentSchemeValue] shv WITH (NOLOCK)
			WHERE shv.PercentSchemeID = iss.OdPercentScheme
		) frt
		OUTER APPLY
		(
			SELECT
			    Loan.sf_GetSchemeValueForADate(iss.OdPercentScheme, @Date) as fordate	
		) prt
	WHERE 		 
		con.ContractType IN (2, 3, 6, 7) -- только транши кредитных линий или овердрафтов
		--AND iss.[Status] < 2
		AND flags.is_active = 1
		-- Исключаем некорректные транши БД разработки:
		AND NOT con.ContractID IN (select id from @expContract)

	SET @row_count += @@ROWCOUNT

	RETURN @row_count

END