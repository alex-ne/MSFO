SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 21/12/2023
-- Description:	Выгрузка в МСФО набора таблиц из Loan
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[sp_Unload_MSFO] 
	@Date date = NULL				    -- Выгрудаентся только данные на заданную дату. 
										-- Если NULL, - первоначальная выгругка всех данных на текущую дату.	
	--,@AllGood bit OUT
AS
BEGIN
	DECLARE 
		@Source varchar(100) = 'GEstBank-Loan',
		@MsfoUnloadLogID uniqueidentifier,
		@MsfoEventLogID uniqueidentifier = NEWID(),
		@UnloadStart datetime = GETDATE(),
		@ErrorCount int = 0

	DECLARE
		@ProcList table (Id int, IsActual bit, [Name] varchar(64), HasDateArg bit)

	INSERT INTO @ProcList(Id, IsActual, [Name], HasDateArg)
	VALUES 
		 ( 1, 1, 'msfo9_loan_type_tr', 0)
		,( 2, 1, 'msfo9_account_type_tr', 1)
		,( 3, 1, 'msfo9_loan_product_tr', 0)
		,( 4, 1, 'msfo9_loan_yul_segment_tr', 0)
		,( 5, 1, 'msfo9_segment_tr', 0)
		,( 6, 1, 'msfo9_graf_type_tr', 0)
		,( 7, 1, 'msfo9_pledge_type_tr', 0)
		,( 8, 1, 'msfo9_guarantee_type_tr', 0)
		,( 9, 1, 'msfo9_loan_tr', 1)
		,(10, 1, 'msfo9_guarantee_tr', 1)
		,(11, 1, 'msfo9_portfolio_tr', 1)
		,(12, 1, 'msfo9_account_tr', 1)
		,(13, 1, 'msfo9_graf_tr', 1)
		,(14, 1, 'msfo9_client_tr', 1)
		,(15, 1, 'msfo9_pledge_tr', 1) 

	INSERT INTO [Loan].[MsfoEventLog] ([MsfoEventLogID], [EventType], [ForDate], [Start], [ErrorCount])
	VALUES (@MsfoEventLogID, 0, @Date, @UnloadStart, @ErrorCount)

	DECLARE		
		@Step int,
		@Step0 int,
		@TargetTable varchar(50),
		@Duration decimal(9, 3),
		@Status int,
		@RecordCount int,
		@ErrorNumber int, 
		@ErrorProc varchar(255),
		@ErrorMessage varchar(1024)
	
	DECLARE 
		@cmd nvarchar(255),
		@par nvarchar(255),		
		@start datetime,
		@finish datetime,
		@Name varchar(64), 
		@HasDateArg bit

	DECLARE UnloadCursor CURSOR FOR
		SELECT Id, [Name], HasDateArg
		FROM @ProcList
		WHERE IsActual = 1
		ORDER BY Id

	OPEN UnloadCursor
	FETCH NEXT FROM UnloadCursor 
	INTO @Step, @Name, @HasDateArg		

	WHILE @@FETCH_STATUS = 0
	BEGIN
		BEGIN TRY
			SELECT 
				@MsfoUnloadLogID = NEWID(),
				@TargetTable = 'dbo.syn_MSFO_' + @Name,
				@Duration = 0,
				@Step0 = @Step,
				@Status = 0,
				@RecordCount = 0,
				@ErrorNumber = NULL, 
				@ErrorProc = NULL,
				@ErrorMessage = NULL,
				@start = GETDATE()				

			IF @HasDateArg = 0
			BEGIN
			SELECT 
				@cmd = 'EXEC Loan.' + @Name + ' @Source',
				@par = '@Source varchar(40)'

			EXEC sp_executesql @cmd, @par, @Source;
			SET @cmd = N'SELECT @RC = COUNT(*) FROM dbo.syn_MSFO_' + @Name + 
				' WHERE ' + 'source = ''' + @Source + ''''
			END
			IF @HasDateArg = 1 
			BEGIN
			SELECT 
				@cmd = 'EXEC Loan.' + @Name + ' @Source, @Date',
				@par = '@Source varchar(40), @Date date'
			EXEC sp_executesql @cmd, @par, @Source, @Date;

			SET @cmd = N'SELECT @RC = COUNT(*) FROM dbo.syn_MSFO_' + @Name + 
				' WHERE ' + 'source = ''' + @Source + ''' and date1 = ''' + cast(@Date as nvarchar) + ''''
			END	

			SET @par = '@RC int OUTPUT'
			EXEC sp_executesql @cmd, @par, @RC = @RecordCount OUTPUT

			SELECT 
				@Status = 1,
				@finish = GETDATE()
		END TRY
		BEGIN CATCH
			SELECT 
				@ErrorCount = @ErrorCount + 1,
				@Status = 0,
				@finish = GETDATE(),
				@ErrorNumber = ERROR_NUMBER(),
				@ErrorProc = ERROR_PROCEDURE(),
				@ErrorMessage = ERROR_MESSAGE() 
		END CATCH		

		FETCH NEXT FROM UnloadCursor 
		INTO @Step, @Name, @HasDateArg

		INSERT INTO [Loan].[MsfoUnloadLog]
		VALUES
		(
			@MsfoUnloadLogID,
            @MsfoEventLogID,              
			@Start,
            @Step0,
            @TargetTable,
            DATEDIFF(millisecond, @start, @finish)/1000.0,
            @Status,
            @RecordCount,
            @ErrorNumber,
            @ErrorProc,
            @ErrorMessage
		)

		SET @start = @finish
	END

	CLOSE UnloadCursor;		
	DEALLOCATE UnloadCursor;	

	UPDATE [Loan].[MsfoEventLog] 
	SET [ErrorCount] = @ErrorCount
	WHERE MsfoEventLogID = @MsfoEventLogID

	DELETE FROM [Loan].[MsfoEventLog] --[Loan].[MsfoUnloadLog]
	WHERE [ForDate] < DATEADD(year, -1, GETDATE())

	--SET @AllGood = IIF(@ErrorCount = 0, 1, 0)
END
