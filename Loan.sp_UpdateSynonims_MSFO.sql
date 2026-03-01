-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 15/05/2025
-- Description:	Настройка синонимов таблиц выгрузки в МСФО
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[sp_UpdateSynonims_MSFO] 
	@TargetDataBase varchar(255) = NULL	-- Целевая БД, на которую будут указывать ссылки синонимов
									    -- Если NULL - берется база dh_MSFO для текущего контура
AS
BEGIN
	DECLARE 	
		@Nm varchar(255),
		@Contour varchar(10),
		@p int

	IF @TargetDataBase IS NULL
	BEGIN
		SET @Nm = REVERSE(DB_NAME()) 
		SET @p = CHARINDEX('_', @Nm)
		SET @Contour = REVERSE(SUBSTRING(@Nm, 1, @p))
		SET @TargetDataBase = 'dh_MSFO' + @Contour
	END

	IF DB_ID(@TargetDataBase) IS NOT NULL
		PRINT N'Целевая база для построения синонимов: ' + @TargetDataBase
	ELSE
		RAISERROR (N'Целевая база для построения синонимов %s не найдена.', 10, 1, @TargetDataBase)

	DECLARE @SQLString AS NVARCHAR (1000);
	SET @SQLString = 
	N'SELECT TABLE_SCHEMA + ''.'' + TABLE_NAME as DestName ' +
	'FROM [' + @TargetDataBase + '].INFORMATION_SCHEMA.TABLES ' +
	'WHERE TABLE_TYPE = ''BASE TABLE'' ' +
	'	AND TABLE_SCHEMA = ''dbo'' ' +
	'	AND TABLE_NAME like ''msfo9_%'''

	DECLARE @DestTables table (Id int IDENTITY(1, 1), [Name] varchar(50))
	INSERT INTO @DestTables([Name])
	EXECUTE sp_executesql
		@SQLString

	DECLARE @MsfoTables table (Id int IDENTITY(1, 1), [Name] varchar(50), [SynonimName] varchar(50), Presenrs bit)
	INSERT INTO @MsfoTables([Name], [SynonimName], Presenrs)
	SELECT DISTINCT ext.[Name], ext.[LocalSynonym], IIF(dest.Id IS NOT NULL, 1, 0) as Presenrs
	FROM [dbo].[T_ExternalSystemsDBObject] ext
	LEFT JOIN @DestTables dest ON dest.[Name] = ext.[Name]
	WHERE [LocalSynonym] like 'syn_MSFO%'
	ORDER BY [Name]


	DECLARE 
		@pos int,
		@cmd varchar(1024),
		@Name varchar(255),
		@SynonimName varchar(255),
		@Presenrs bit,
		@NewLineChar AS CHAR(2) = CHAR(13)+CHAR(10),
		@ErrorList varchar(MAX)

	DECLARE SynonimCursor CURSOR FOR
		SELECT [Id], [Name], [SynonimName], Presenrs FROM @MsfoTables ORDER BY [Id]

	OPEN SynonimCursor

	FETCH NEXT FROM SynonimCursor INTO @pos, @Name, @SynonimName, @Presenrs

	BEGIN TRY
	WHILE @@FETCH_STATUS = 0
	BEGIN		 
		IF @Presenrs = 1
		BEGIN
			SET @cmd = 
				'DROP SYNONYM IF EXISTS [dbo].[' + @SynonimName + ']
				 CREATE SYNONYM [dbo].[' + @SynonimName + ']
				 FOR ' + @TargetDataBase + '.' + @Name
			EXEC (@cmd)	
		END
		ELSE
		BEGIN
			PRINT 'Can not Create Synonim ''' + @SynonimName + ''''
			SET @ErrorList = @ErrorList + @NewLineChar + @SynonimName
		END
		--select @pos, @cmd
		SET @pos = @pos + 1			
		FETCH NEXT FROM SynonimCursor INTO @pos, @Name, @SynonimName, @Presenrs
	END
	END TRY
	BEGIN CATCH
	IF (@@TRANCOUNT > 0)
		ROLLBACK TRANSACTION;

	SELECT  -- Если нужно обработать ошибку - заскобачить THROW
		ERROR_NUMBER() AS ErrorNumber  
		,ERROR_PROCEDURE() AS ErrorProcedure  
		,ERROR_MESSAGE() AS ErrorMessage
		,@pos as RowNumber 
		,@Name as TableName;  

	THROW
	END CATCH

	CLOSE SynonimCursor;
	DEALLOCATE SynonimCursor;	

	IF LEN(@ErrorList) > 0
		RAISERROR (N'Не удалось создать синонимы: %s не найдена.', 10, 1, @ErrorList)

RETURN @pos
END
