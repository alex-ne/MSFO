SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 19/06/2023
-- Description:	Выгрузка в МСФО договоров обеспечения, относящихся к кредитным договорам
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[msfo9_pledge_tr] 
	@Source varchar(100),
	@Date date, 							-- Дата выгрузки. Если @Date <> NULL, договора обеспечения, активные на дату выгрузки.					
	@ContractID uniqueidentifier = NULL		-- Только обеспечение для указанного кредитного договора. Если NULL - условие игнорируется	
AS
BEGIN
	-- Очистка транзитной таблицы МСФО
	DELETE FROM dbo.syn_MSFO_msfo9_pledge_tr
	WHERE 
	  source = @Source
	  AND
	  DATEDIFF(day , ISNULL(@date, date1), date1) = 0
	  AND
	  ((@ContractID IS NULL) OR (contract_oid = @ContractID))	

	-- Назначеем дату выгрузки, если отсутствует
	SET @Date = ISNULL(@Date, GETDATE())

	-- Код банка
	DECLARE @BankCode int
	select @BankCode = IntegerValue
	from dbo.T_ConfigParam
	where [Name] ='InternalBankCode'

	-- Обновляем временную таблицу цепочек следования залогов #PledgeSeries
	drop table if exists #PledgeSeries
	create table #PledgeSeries
	(
		PledgeID uniqueidentifier,
		SwitchDate date,
		PrevPledgeID uniqueidentifier,
		PledgeLevel int,
		BasePledgeID uniqueidentifier
	)

	EXEC [Loan].[sp_Update_PledgeSeries]

	-- Список кредитных договоров и линий, для которых выгружается обеспечение на заданную дату
	DECLARE @ContractList table (ContractID uniqueidentifier)
	
	INSERT INTO @ContractList
	SELECT DISTINCT con.ContractID
	FROM dbo.syn_MSFO_msfo9_loan_tr src
	LEFT JOIN [Loan].[Contract] con ON con.ContractID = IIF(main_contract_oid IS NULL, src.oid, src.main_contract_oid)
	WHERE
		source = @Source
		AND
		DATEDIFF(day , ISNULL(@date, date1), date1) = 0

	-- Идентификаторы обеспечения (залоги и поручительства), 
	-- ассоциированные с заданным кредитными кредитными договорами 
	DECLARE @IdList table
	(	 
		LinkHistoryID uniqueidentifier,
		ContractID uniqueidentifier,
		SecurityContract uniqueidentifier,
		SecurityID uniqueidentifier,
		PledgeContractID uniqueidentifier,
		CollateralTypeID uniqueidentifier,
		GuaranteeID uniqueidentifier,
		PledgeID uniqueidentifier,
		PledgeOwnerID uniqueidentifier,
		PledgeObjectID uniqueidentifier,
		ClientID uniqueidentifier
	)

	INSERT INTO @IdList
	SELECT	
		lnk.LinkPledgeAndLoanContractHistoryID as LinkHistoryID,
		con.ContractID,
		ISNULL(c.ContractID, ctg.ContractID) as SecurityContract, -- ид договора залога или поручительства 
		ISNULL(p.PledgeID, ctg.ContractID)	as SecurityID,		  -- ид залога или договора поручительства 
		c.ContractID as PledgeContractID,
		IIF(p.PledgeID IS NULL, ctg.CollateralType, pob.CollateralType) as CollateralTypeID,	
		ctg.ContractID as GuaranteeID,
		p.PledgeID as PledgeID,	
		pow.PledgeOwnerID,
		pob.PledgeObjectID,
		ISNULL(c.Client, g.Client) as ClientID
	FROM @ContractList id
	INNER JOIN [Loan].[Contract] con ON con.ContractID = id.ContractID
	INNER JOIN GbPledges.T_LinkPledgeContractToContract lpc ON lpc.Contract = con.ContractID	
		AND @Date between lpc.LinkDate and isnull(lpc.LinkExpirationDate, @Date)
	OUTER APPLY
	(
		SELECT TOP(1) 
			 [LinkPledgeAndLoanContractHistoryID]
		FROM [GbPledges].[T_LinkPledgeAndLoanContractHistory]
		WHERE [LoanContract] = con.ContractID
			AND [PledgeContract] = lpc.PledgeContract
			AND [RestOperDay] <= @Date
		ORDER BY DistributionDate DESC
	) lnk
	LEFT JOIN GbPledges.T_Pledge p ON p.PledgeContract = lpc.PledgeContract	and p.PledgeStatus = 1
	LEFT JOIN T_PledgeOwner pow ON pow.PledgeOwnerID = p.PledgeObjectAndOwner
	LEFT JOIN T_PledgeObject pob ON pob.PledgeObjectID = pow.PledgeObject
	LEFT JOIN GbPledges.T_GuaranteeContract ctg ON ctg.ContractID = lpc.PledgeContract	
	LEFT JOIN dbo.T_Contract g ON g.ContractID = ctg.ContractID
		and (@Date between g.StartDate and ISNULL(g.ClosedDate, @Date))
		and (g.Status not in (0,3))
	LEFT JOIN dbo.T_Contract c ON c.ContractID = lpc.PledgeContract  
		and (@Date between c.StartDate and ISNULL(c.ClosedDate, @Date))
		and (c.Status not in (0,3))
	WHERE (@ContractID IS NULL OR con.ContractID = @ContractID)
	ORDER BY IIF(p.PledgeID IS NULL, 1, 0), lpc.LinkPledgeContractToContractID	

	-- Неопределенный тип обеспечения
	DECLARE	@UndefinedCollateralType uniqueidentifier
	SELECT @UndefinedCollateralType = CollateralTypeID
	FROM GbPledges.T_CollateralType
	WHERE [Name] = 'Прочее'

	-- Выгрузка в транзитную таблицу [msfo9_pledge_tr]
	INSERT INTO [dbo].[syn_MSFO_msfo9_pledge_tr]
		([date1]					
		,[branch_code]				
		,[source]					
		,[contract_oid]				
		,[contract_type]			
		,[pledge_source]			
		,[pledge_oid]				
		,[pledge_contract_number]	
		,[id_pledge_type]			
		,[name]						
		,[category_rsbu]			
		,[fair_summa_curr]			
		,[fair_summa_val]			
		,[insure_curr]				
		,[insure_summa_val]			
		,[date_last_measurement]	
		,[summa_with_discount_curr]	
		,[summa_with_discount_val]	
		,[client_oid])	
	SELECT DISTINCT
		 @Date as [date1]					
		, IIF(brn.InnerCode IS NULL, 0, brn.InnerCode) as [branch_code]
		, @Source
		, ids.ContractID as [contract_oid]				
		, 'к' as [contract_type]		
		, ISNULL(es.[Name], @Source) as [pledge_source]	--источник данных (код учетной системы банка, откуда был выгружен договор обеспечения)
		, ids.SecurityID as [pledge_oid]				--идентификатор договора обеспечения в учетной системе банка
		, scn.Number as [pledge_contract_number]		--номер договора обеспечения
		, combine.id_pledge_type	--[varchar](255) NULL, Тип обеспечения по классификации Банка. Справочник Банка: Обеспечения_Типы			 
		, combine.[name]	-- описание обеспечения
		, combine.[category_rsbu]							-- Категория качества обеспечения. Варианты: 1, 2  - официальные. И можно выгружать 3 - для тех, что не удовлетворяют требованиям 580-П. Учет справедливой стоимости обеспечения: 1 - 100%, 2 - 50%, 3 - 0%.
		, cr.currency as [fair_summa_curr]			    	-- код валюты справедливой стоимости обеспечения, относящегося к договору (643 - руб., 840 - доллары США и т.д.)
		, combine.[fair_summa_val]				-- справедливая стоимость обеспечения, относящегося к договору, в валюте
		, cr.currency as [insure_curr]						-- код валюты страховки обеспечения, относящаяся к договору (643 - руб., 840 - доллары США и т.д.)
		, combine.[insure_summa_val]			-- сумма страховки обеспечения, относящаяся к договору, в валюте
		, plg.FairValueConfirmationDate 
						   as [date_last_measurement]		-- дата последней оценки справедливой стоимости обеспечения
		, cr.currency as summa_with_discount_curr 	--[varchar](3) NULL, Код валюты стоимости обеспечения с учетом дисконта в валюте(для расчета резервов по МСФО9)
		, 0 as summa_with_discount_val													--[decimal](18, 2) NULL, Стоимость обеспечения с учетом дисконта (для расчета резервов по МСФО9) в валюте						 		
		, ids.ClientID as client_oid
	FROM @IdList ids
	INNER join [dbo].[T_PledgeContract] pcn ON pcn.ContractID = ids.PledgeContractID
	LEFT JOIN [dbo].[T_ExternalSystem] es ON es.Code = pcn.SourceSystem
	LEFT JOIN [GbPledges].[T_Pledge] plg on plg.PledgeID = ids.PledgeID 
	LEFT JOIN GbPledges.T_PledgeObject pob ON pob.PledgeObjectID = ids.PledgeObjectID
	left JOIN GbPledges.T_CollateralType clt ON clt.CollateralTypeID = ISNULL(pob.CollateralType, ids.CollateralTypeID) --ISNULL(ids.CollateralTypeID, @UndefinedCollateralType))
	LEFT JOIN [GbPledges].[T_InsuranceContract] icn ON icn.PledgeContract = ids.SecurityContract
	INNER join [dbo].[T_Contract] scn ON scn.ContractID = ids.SecurityContract
	LEFT JOIN [dbo].[T_Branch] brn WITH (NOLOCK) ON brn.BranchID = scn.Branch
	OUTER APPLY
	(
		SELECT IIF(scn.Currency = '810', '643', scn.[Currency]) as currency
	) cr
	OUTER APPLY
	(
		SELECT TOP(1) QualityCategory
		FROM [GbPledges].[T_PledgeQualityCategory] 
		WHERE PledgeObject = ids.PledgeObjectID
		ORDER BY QualitySettingDate DESC
	) actual
		outer apply
	(
		select top(1) FairValue, InsuranceSum
		from GbPledges.T_LinkPledgeAndLoanContractHistory
		where LoanContract = ids.ContractID 
			and Pledge = ids.PledgeID
			and DistributionDate <= @Date
		order by DistributionDate desc
	) lnk0
	outer apply
	(
		select top(1) FairValue, InsuranceSum
		from GbPledges.T_LinkPledgeAndLoanContractHistory
		where LinkPledgeAndLoanContractHistoryID = ids.LinkHistoryID
			and DistributionDate <= @Date
		order by DistributionDate desc
	) lnk1
	outer apply
	(
		select top(1) ass.FairValue, ass.CollateralValue
		from GbPledges.T_PledgeAssessment ass
		inner join GbPledges.T_PledgeConclusion cnc on cnc.PledgeConclusionID = ass.PledgeConclusion
		inner join dbo.gest_Activity act on act.ActivityID = cnc.LinkedActivity
		where @BankCode = 12
			and ass.PledgeObject = ids.PledgeObjectID
			and act.[Status] = 3
			and ass.AssessmentDate <= @Date
		order by ass.AssessmentDate desc
	) plass
	LEFT JOIN GbPledges.T_GuaranteeContract ctg ON ctg.ContractID = ids.GuaranteeID
	OUTER APPLY -- для последзалога plg.Pledge возвращает справедливую и залоговую стоимость базового залога на заданную дату
	(
		select top(1) pp.FairValue, pp.CollateralValue
		from #PledgeSeries s
		inner join #PledgeSeries p on p.BasePledgeID = s.BasePledgeID					
		inner join [GbPledges].[T_Pledge] pp on pp.PledgeID = p.PledgeID		
		where s.PledgeID = plg.PledgeID			
			and (isnull(p.SwitchDate, '1900-01-01') <= @Date) 
		order by p.PledgeLevel desc		
	) base_pledge
	OUTER APPLY
	(
		-- Залоги
		select
			cast(pob.PledgeKind as varchar) as id_pledge_type,
			pob.[name],
			IIF(plg.ConsiderReserveCalculating = 1, ISNULL(actual.QualityCategory, pob.QualityCategory), 0) as [category_rsbu],
			case @BankCode
			when 12 then 
				iif(isnull(plg.FairValue, 0) > 0, 
					isnull(lnk0.FairValue, 0), 
					iif(plg.SubsequentPledge = 0,
						isnull(plass.CollateralValue, isnull(plg.CollateralValue, 0)),
						iif(isnull(plg.BasicStateSetDate, @Date) > @Date, isnull(base_pledge.CollateralValue, 0), 0) 
						)
					) 
			else isnull(lnk0.FairValue, 0)
			end as fair_summa_val,
			lnk0.[InsuranceSum] as [insure_summa_val]
		where ids.PledgeID IS NOT NULL
		union
		-- Поручительства
		select
			clt.[Code] as id_pledge_type,	 
			clt.[Name],
			ctg.QualityCategory as [category_rsbu],
			lnk1.[FairValue] as [fair_summa_val],				
			lnk1.[InsuranceSum] as [insure_summa_val]			
		where ids.PledgeID IS NULL
	) combine
	where ids.SecurityID is not null

    RETURN @@ROWCOUNT
END
