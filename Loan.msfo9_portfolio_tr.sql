SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 04/12/2023
-- Description:	Выгрузка в МСФО портфелей кредитных договоров
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[msfo9_portfolio_tr] 
	@Source varchar(100),
	@Date date, 						    -- Выгрудаентся только актуальне на заданную дату портфели. Если NULL, - ограничение не налогается	
	@PortfolioID uniqueidentifier = NULL    -- Выгрузка портфеля, идентификатор которого задан. Если NULL, -  ограничение не налогается
AS
BEGIN

	-- Вспомогательная таблица - список столбцов
	DECLARE @PortfolioAccountColumns table
	(
	    PortfolioAccountColumnId int NOT NULL, 
		ColumnName varchar(255) NOT NULL, 
		AccountType int NOT NULL,
		IsCession bit NULL
	) 

	INSERT INTO @PortfolioAccountColumns(PortfolioAccountColumnId, ColumnName, AccountType)
	VALUES
	(1, 'acc_corr_ac_act', 246),
	(2, 'acc_corr_ac_pas', 247),
	(3, 'acc_corr_reserve_principal_pas', 229),
	(4, 'acc_corr_reserve_principal_act', 228),
	(5, 'acc_corr_reserve_overdue_principal_pas', 239), --32
	(6, 'acc_corr_reserve_overdue_principal_act', 238), --33
	(7, 'acc_corr_reserve_interest_pas', 231),
	(8, 'acc_corr_reserve_interest_act', 230),
	(9, 'acc_corr_reserve_overdue_interest_pas', 241),
	(10, 'acc_corr_reserve_overdue_interest_act', 240),
	(11, 'acc_corr_reserve_nkl_pas', 235),
	(12, 'acc_corr_reserve_nkl_act', 234),
	(13, 'acc_reserve_principal', 10018), --24
	(14, 'acc_reserve_overdue_principal', 10133), --25
	(15, 'acc_reserve_interest', 10135),
	(16, 'acc_reserve_overdue_interest', 10078),
	(17, 'acc_reserve_nkl', 10029),
	(18, 'acc_reserve_komis', 10120),
	(19, 'acc_corr_reserve_komis_pas', 233),
	(20, 'acc_corr_reserve_komis_act', 232),
	(21, 'acc_reserve_penalty', 10079),--#10079
	(22, 'acc_corr_reserve_penalty_pas', 237),
	(23, 'acc_corr_reserve_penalty_act', 236),
	(24, 'acc_reserve_principal_cession', 10018), --13
	(25, 'acc_reserve_overdue_principal_cession', 10133), --14
	(26, 'acc_reserve_premium', 10134),
	(27, 'acc_reserve_overdue_premium', 10087),
	(28, 'acc_reserve_discount', 10142),
	(29, 'acc_reserve_overdue_discount', 10125),
	(30, 'acc_corr_reserve_principal_cession_pas', 243),--34
	(31, 'acc_corr_reserve_principal_cession_act', 242),--35
	(32, 'acc_corr_reserve_overdue_principal_cession_pas', 239), -- 5
	(33, 'acc_corr_reserve_overdue_principal_cession_act', 238), -- 6 
	(34, 'acc_corr_reserve_premium_pas', 243),--30
	(35, 'acc_corr_reserve_premium_act', 242),--31
	(36, 'acc_corr_reserve_overdue_premium_pas', 10009),--#10009
	(37, 'acc_corr_reserve_overdue_premium_act', 10012),--#10012
	(38, 'acc_corr_reserve_discount_pas', 245),
	(39, 'acc_corr_reserve_discount_act', 244),
	(40, 'acc_corr_reserve_overdue_discount_pas', 10016),--#10016
	(41, 'acc_corr_reserve_overdue_discount_act', 10017),--#10017
	(42, 'acc_reserve_overdue_komis_perc', 10020),--#10020
	(43, 'acc_corr_reserve_overdue_komis_perc_pas', 10021),--#10021
	(44, 'acc_corr_reserve_overdue_komis_perc_act', 10025),--#10025
	(45, 'acc_reserve_overdue_komis_nonperc', 10037),--#10037
	(46, 'acc_corr_reserve_overdue_komis_nonperc_pas', 10058),--#10058
	(47, 'acc_corr_reserve_overdue_komis_nonperc_act', 10064);--#10064	   

	-- Список портфелей, подлежащих выгрузке в транзитную таблицу МСФО
	DECLARE @target TABLE (
		[PortfolioID] uniqueidentifier NOT NULL,
		[branch_code] [smallint] NOT NULL,
		[division_code] [smallint] NULL,
		[name] [varchar](255) NOT NULL,
		[coef_reserve] [decimal](18, 6) NOT NULL,
		[category_quality] [smallint] NOT NULL,
		[status] [varchar](2) NOT NULL,
		[is_registr] [bit] NULL,	
		[short_name] [varchar](255) NULL,
		[is_cession] bit)

	INSERT INTO @target
	SELECT DISTINCT
		ppf.PortfolioID,
		ISNULL(bank.branch_code, 0) as branch_code, 
		bank.division_code,		
		IIF(ptb.Name IS NULL, '', ptb.Name + '. ') + 
		IIF(pcr.Name IS NULL, '', UPPER(SUBSTRING(pcr.Name, 1, 1)) + SUBSTRING(pcr.Name, 2, LEN(pcr.Name)))	as [name],
		ISNULL(risk.ReservRatio, drg.MaximumRedundancyRatio) as coef_reserve,
		ISNULL(risk.QualityCode, drg.Code) as category_quality,
		CASE ptb.FreezeClientStatus
		WHEN 0 THEN 'ф'
		WHEN 1 THEN 'ю'
		ELSE '?'
		END as [status],
		0 as [is_registr], 
		NULL as [short_name], --???
		IIF(ptb.ContractType = 4, 1, 0) as [is_cession]
	FROM [GbPledges].[Portfolio] ppf WITH (NOLOCK) 
		LEFT JOIN [GbPledges].[PortfolioTypeBack] ptb WITH (NOLOCK) ON ptb.PortfolioTypeBackID = ppf.[PortfolioTypeBack]
		LEFT JOIN [GbPledges].[PortfolioCriteria] pcr WITH (NOLOCK) ON pcr.PortfolioCriteriaID = ppf.PortfolioCriteria
		LEFT JOIN [dbo].[T_RiskGroup] drg WITH (NOLOCK) ON drg.RiskGroupID = ppf.RiskGroupID
		OUTER APPLY
		(
			SELECT 
				ISNULL(COUNT(acc.AccountID), 0) as conunt
			FROM [Loan].[Account] acc WITH (NOLOCK)
			INNER JOIN [dbo].[T_Account] bac WITH (NOLOCK) ON bac.AccountID = acc.BaseAccountID 
			WHERE    
			   ((NOT acc.PortfolioID IS NULL) AND (acc.PortfolioID = ppf.PortfolioID))
			   AND
			   ((@Date IS NULL) OR (@Date BETWEEN bac.DateOpen AND ISNULL(bac.DateClose, @Date)))
		) inn	
		OUTER APPLY
		(
			SELECT TOP(1) 
				rgh.[ReservationRateValue] as ReservRatio, 
				rgr.Code as QualityCode				
			FROM [dbo].[T_ChangeCustomerRiskGroup] rgh WITH (NOLOCK)
			INNER JOIN [dbo].[T_RiskGroup] rgr WITH (NOLOCK) ON rgr.RiskGroupID = rgh.NewValueRiskGroup 
			WHERE rgh.[Portfolio] = ppf.PortfolioID
				AND rgh.ActionStartDate <= @Date
			ORDER BY rgh.ActionStartDate DESC
		) risk
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
	WHERE		
		(@PortfolioID IS NULL OR ppf.PortfolioID = @PortfolioID)
		AND
		(inn.[conunt] > 0)

	--select * from @target

	-- Очистка транзитной таблицы МСФО
	DELETE FROM dbo.syn_MSFO_msfo9_portfolio_tr
	WHERE 
		source = @Source
		AND date1 = @date
		AND	(@PortfolioID IS NULL OR oid = @PortfolioID)

	-- Добавление портфелей из списка в транзитную таблицу МСФО
	INSERT INTO dbo.syn_MSFO_msfo9_portfolio_tr --@Portfolio
	(
		[date1],
		[branch_code],
		[division_code],
		[source],
		[oid],
		[name],	
		[coef_reserve],
		[category_quality],
		[status],
		[is_registr],
		[short_name]
		--,
		--[acc_corr_ac_act],
		--[acc_corr_ac_pas],
		--[acc_corr_reserve_principal_pas],
		--[acc_corr_reserve_principal_act],
		--[acc_corr_reserve_interest_pas],
		--[acc_corr_reserve_interest_act],
		--[acc_corr_reserve_nkl_pas],
		--[acc_corr_reserve_nkl_act],
		--[acc_reserve_principal],
		--[acc_reserve_overdue_principal],
		--[acc_reserve_interest],
		--[acc_reserve_overdue_interest],
		--[acc_reserve_nkl],	
		--[acc_corr_reserve_overdue_principal_pas],
		--[acc_corr_reserve_overdue_principal_act],
		--[acc_corr_reserve_overdue_interest_pas],
		--[acc_corr_reserve_overdue_interest_act],
		--[acc_reserve_komis],
		--[acc_corr_reserve_komis_pas],
		--[acc_corr_reserve_komis_act],	
		--[acc_reserve_penalty],
		--[acc_corr_reserve_penalty_pas],
		--[acc_corr_reserve_penalty_act],
		--[acc_reserve_principal_cession],
		--[acc_reserve_overdue_principal_cession],
		--[acc_reserve_premium],
		--[acc_reserve_overdue_premium],
		--[acc_reserve_discount],
		--[acc_reserve_overdue_discount],
		--[acc_corr_reserve_principal_cession_pas],
		--[acc_corr_reserve_principal_cession_act],
		--[acc_corr_reserve_overdue_principal_cession_pas],
		--[acc_corr_reserve_overdue_principal_cession_act],
		--[acc_corr_reserve_premium_pas],
		--[acc_corr_reserve_premium_act],
		--[acc_corr_reserve_overdue_premium_pas],
		--[acc_corr_reserve_overdue_premium_act],
		--[acc_corr_reserve_discount_pas],
		--[acc_corr_reserve_discount_act],
		--[acc_corr_reserve_overdue_discount_pas],
		--[acc_corr_reserve_overdue_discount_act],
		--[acc_reserve_overdue_komis_perc],
		--[acc_corr_reserve_overdue_komis_perc_pas],
		--[acc_corr_reserve_overdue_komis_perc_act],
		--[acc_reserve_overdue_komis_nonperc],
		--[acc_corr_reserve_overdue_komis_nonperc_pas],
		--[acc_corr_reserve_overdue_komis_nonperc_act]
	)
    SELECT DISTINCT
   	  @Date as [date1],
	  lst.[branch_code],
	  lst.[division_code],
	  @Source as [source],
	  lst.PortfolioID as [oid],
	  lst.[name],
	  lst.[coef_reserve],
	  lst. [category_quality],
	  lst.[status],
	  0 as [is_registr],	
	  lst.[short_name]
	  --,	  
	  --pivacc.[acc_corr_ac_act],
   --   pivacc.[acc_corr_ac_pas],
   --   pivacc.[acc_corr_reserve_principal_pas],
   --   pivacc.[acc_corr_reserve_principal_act],
   --   pivacc.[acc_corr_reserve_interest_pas],
   --   pivacc.[acc_corr_reserve_interest_act],
   --   pivacc.[acc_corr_reserve_nkl_pas],
   --   pivacc.[acc_corr_reserve_nkl_act],
   --   pivacc.[acc_reserve_principal],
   --   pivacc.[acc_reserve_overdue_principal]L,
   --   pivacc.[acc_reserve_interest],
   --   pivacc.[acc_reserve_overdue_interest],
   --   pivacc.[acc_reserve_nkl],	
   --   pivacc.[acc_corr_reserve_overdue_principal_pas],
   --   pivacc.[acc_corr_reserve_overdue_principal_act],
   --   pivacc.[acc_corr_reserve_overdue_interest_pas],
   --   pivacc.[acc_corr_reserve_overdue_interest_act],
   --   pivacc.[acc_reserve_komis],
   --   pivacc.[acc_corr_reserve_komis_pas],
   --   pivacc.[acc_corr_reserve_komis_act],	
   --   pivacc.[acc_reserve_penalty],
   --   pivacc.[acc_corr_reserve_penalty_pas],
   --   pivacc.[acc_corr_reserve_penalty_act],
   --   pivacc.[acc_reserve_principal_cession],
   --   pivacc.[acc_reserve_overdue_principal_cession],
   --   pivacc.[acc_reserve_premium],
   --   pivacc.[acc_reserve_overdue_premium],
   --   pivacc.[acc_reserve_discount],
   --   pivacc.[acc_reserve_overdue_discount],
   --   pivacc.[acc_corr_reserve_principal_cession_pas],
   --   pivacc.[acc_corr_reserve_principal_cession_act],
   --   pivacc.[acc_corr_reserve_overdue_principal_cession_pas],
   --   pivacc.[acc_corr_reserve_overdue_principal_cession_act],
   --   pivacc.[acc_corr_reserve_premium_pas],
   --   pivacc.[acc_corr_reserve_premium_act],
   --   pivacc.[acc_corr_reserve_overdue_premium_pas],
   --   pivacc.[acc_corr_reserve_overdue_premium_act],
   --   pivacc.[acc_corr_reserve_discount_pas],
   --   pivacc.[acc_corr_reserve_discount_act],
   --   pivacc.[acc_corr_reserve_overdue_discount_pas],
   --   pivacc.[acc_corr_reserve_overdue_discount_act],
   --   pivacc.[acc_reserve_overdue_komis_perc],
   --   pivacc.[acc_corr_reserve_overdue_komis_perc_pas],
   --   pivacc.[acc_corr_reserve_overdue_komis_perc_act],
   --   pivacc.[acc_reserve_overdue_komis_nonperc],
   --   pivacc.[acc_corr_reserve_overdue_komis_nonperc_pas],
   --   pivacc.[acc_corr_reserve_overdue_komis_nonperc_act]
	FROM @target lst
	OUTER APPLY
	(
		SELECT *
		FROM   
		(
			SELECT pac.ColumnName, acc.AccountID
			FROM [GbPledges].[Portfolio] prf
			inner join Loan.Account acc on acc.PortfolioID = prf.PortfolioID
			inner join [dbo].[T_Account] bac on bac.AccountID = acc.BaseAccountID
			inner join @PortfolioAccountColumns pac on pac.AccountType = bac.AccountType
			where prf.PortfolioID = lst.PortfolioID	 AND
				(@Date BETWEEN bac.DateOpen AND ISNULL(bac.DateClose, @Date))
		)  src  
		PIVOT  
		(
			MIN (src.AccountID)
			FOR src.ColumnName IN  
			( 
				[acc_corr_ac_act],                                   
				[acc_corr_ac_pas],                                   
				[acc_corr_reserve_principal_pas],
				[acc_corr_reserve_principal_act],                    
				[acc_corr_reserve_overdue_principal_pas],            
				[acc_corr_reserve_overdue_principal_act],            
				[acc_corr_reserve_interest_pas],                     
				[acc_corr_reserve_interest_act],                     
				[acc_corr_reserve_overdue_interest_pas],             
				[acc_corr_reserve_overdue_interest_act],             
				[acc_corr_reserve_nkl_pas],                          
				[acc_corr_reserve_nkl_act],                          
				[acc_reserve_principal],                             
				[acc_reserve_overdue_principal],                     
				[acc_reserve_interest],                              
				[acc_reserve_overdue_interest],                      
				[acc_reserve_nkl],                                   
				[acc_reserve_komis],                                 
				[acc_corr_reserve_komis_pas],                        
				[acc_corr_reserve_komis_act],                        
				[acc_reserve_penalty],                               
				[acc_corr_reserve_penalty_pas],                      
				[acc_corr_reserve_penalty_act],                      
				[acc_reserve_principal_cession],                     
				[acc_reserve_overdue_principal_cession],             
				[acc_reserve_premium],                               
				[acc_reserve_overdue_premium],                       
				[acc_reserve_discount],                              
				[acc_reserve_overdue_discount],                      
				[acc_corr_reserve_principal_cession_pas],            
				[acc_corr_reserve_principal_cession_act],            
				[acc_corr_reserve_overdue_principal_cession_pas],
				[acc_corr_reserve_overdue_principal_cession_act],
				[acc_corr_reserve_premium_pas],                      
				[acc_corr_reserve_premium_act],                      
				[acc_corr_reserve_overdue_premium_pas],              
				[acc_corr_reserve_overdue_premium_act],              
				[acc_corr_reserve_discount_pas],                     
				[acc_corr_reserve_discount_act],                     
				[acc_corr_reserve_overdue_discount_pas],             
				[acc_corr_reserve_overdue_discount_act],             
				[acc_reserve_overdue_komis_perc],                    
				[acc_corr_reserve_overdue_komis_perc_pas],           
				[acc_corr_reserve_overdue_komis_perc_act],           
				[acc_reserve_overdue_komis_nonperc],                 
				[acc_corr_reserve_overdue_komis_nonperc_pas],
				[acc_corr_reserve_overdue_komis_nonperc_act]
			)
		) piv
	) pivacc	


RETURN @@ROWCOUNT

END
