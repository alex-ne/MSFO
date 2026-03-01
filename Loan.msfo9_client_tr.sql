SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 05/02/2024
-- Description:	Выгрузка в МСФО клиентов
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[msfo9_client_tr] 
	@Source varchar(100),
	@Date date,
	@ClientId uniqueidentifier = NULL
AS
BEGIN
	-- Очистка транзитной таблицы МСФО
	DELETE FROM dbo.syn_MSFO_msfo9_client_tr
	WHERE 
	  source = @Source
	  AND
	  DATEDIFF(day , ISNULL(@date, date1), date1) = 0		  
	
	-- ВЫГРУЗКА
	DECLARE 
		@param int,
		@Id uniqueidentifier = @ClientId

	SELECT 
		@param = IIF(@Date IS NULL, 1, 0),
		@Date = ISNULL(@Date, GETDATE())

	-- Внутренний код банка
	DECLARE @BankCode int  
	SELECT @BankCode = IntegerValue FROM dbo.T_ConfigParam
	WHERE Name ='InternalBankCode'

	DECLARE @msfo9_client_tr table
	(
		[date1] [date] NOT NULL
		,[source] [varchar](255) NOT NULL
		,[oid] [varchar](255) NOT NULL
		,[name] [varchar](255) NOT NULL
		,[full_name] [varchar](255) NULL
		,[status] [varchar](2) NOT NULL
		,[client_type] [varchar](60) NULL
		,[is_resident] [bit] NULL
		,[inn] [varchar](255) NULL
		,[kpp] [varchar](255) NULL
		,[okved] [varchar](255) NULL
		,[okato] [varchar](255) NULL
		,[date_reg] [date] NULL
		,[date_birth] [date] NULL
		,[gender] [varchar](1) NULL
		,[segment] [varchar](255) NULL
		,[rating_internal] [varchar](255) NULL
		,[rating_internal_score] [decimal](18, 2) NULL	
		,[Branch_Code] smallint NULL
		,[fin_position] [varchar](60) NULL	
	)

	IF (@BankCode = 9)
	BEGIN
		INSERT INTO @msfo9_client_tr
		(
			[date1],[source],[oid],[name],[full_name],[status]
			,[client_type],[is_resident],[inn],[kpp],[okved],[okato]
			,[date_reg],[date_birth],[gender],[segment],[rating_internal]
			,[rating_internal_score],[fin_position]			
		)	
		EXEC dbo.msfo9_client_tr @Date, @Source, @param, null

		UPDATE lst
		SET [Branch_Code] = cast(div.Branch as smallint) 
		FROM @msfo9_client_tr lst
		INNER JOIN dbo.T_Customer cus ON cus.CustomerID = lst.oid
		INNER JOIN dbo.T_Division div with (nolock) ON div.DivisionID = cus.Division
	END
	ELSE
		INSERT INTO @msfo9_client_tr
		EXEC dbo.msfo9_client_tr @Date, @Source, @param, null

	INSERT INTO dbo.syn_MSFO_msfo9_client_tr
	(
		date1,source,oid,name,full_name,status,
		client_type,is_resident,inn,kpp,
		okved,okato,date_reg,date_birth,
		gender,segment,rating_internal,
		rating_internal_score,branch_code,
		fin_position
	)
	SELECT * FROM @msfo9_client_tr

	RETURN @@ROWCOUNT
END
