-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 02/10/2024
-- Description:	Тестирование выгрузка в транзитные таблицы данных МСФО
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[msfo9_test_proc] 
	@Table varchar(40),				-- имя целевой таблицы МСФО без схемы и скобок
	@Source varchar(40) = NULL,		-- раздел целевой таблицы МСФО. По умолчанию 'Test'
	@Date date = NULL,				-- дата выгрузки (если нужна). По умолчанию текущий день.
	@Id uniqueidentifier = NULL,	-- ид выгружаемого объекта (если нужен). По умолчанию NULL - выгружаются все объекты 
	@ExecMaska int = NULL			-- битовая маска выполняемых действий:
									-- 0001 - выполнить выгрузку
									-- 0010 - отобразить указанный раздел целевой таблицы
									-- 0100 - очистить  указанный раздел целевой таблицы
									-- По умолчанию последовательно выполняются все действия (0111)
AS
BEGIN

DECLARE	
	@HasDate bit,
	@Tab_Name varchar(255),
	@Proc_Name varchar(255),
	@Clear_Sql nvarchar(1024),
	@Proc_Sql nvarchar(1024),
	@Show_Sql nvarchar(1024),
	@src varchar(40),
	@tdt varchar(40),
	@tid varchar(40),
	@ParamList nvarchar(1024), 
	@Signature nvarchar(1024), 
	@SignatureType int

SELECT
	@ExecMaska = ISNULL(@ExecMaska, 1 + 2 + 4),
	@Source = ISNULL(@Source, 'Test'),
	@HasDate = 
	IIF(@Table IN  ('msfo9_account_type_tr',
					'msfo9_graf_type_tr',
					'msfo9_loan_product_tr',
					'msfo9_loan_type_tr',
					'msfo9_loan_yul_segment_tr',
					'msfo9_pledge_type_tr'),
					0, 1)

SELECT 	
	@src = '''' + @Source + '''',
	@tdt = '''' + CAST(@Date as varchar) + '''',
	@tid = IIF(@Id IS NULL, '', ' ''' + CAST(@Id as varchar) + ''''),
	@Tab_Name = 'dbo.syn_MSFO_' + @Table,
	@Proc_Name = '[Loan].[' + @Table + ']'

SELECT	
	@ParamList = '@Source varchar(40)' +
	IIF(@HasDate = 0, '', ', @Date date, @Id uniqueidentifier'),
	@Signature = ' @Source' +
	IIF(@HasDate = 0, '', ', @Date, @Id'),
	@SignatureType = IIF(@HasDate = 0, 1, 2)

SELECT 
	@Clear_Sql = 'DELETE FROM ' + @Tab_Name + 
		' WHERE source = ' + @src + 
		IIF(@HasDate = 0, '', ' AND date1 = ' + @tdt),
	@Proc_Sql = 'EXEC ' + @Proc_Name + @Signature,
	@Show_Sql = 'SELECT * FROM ' + @Tab_Name + 
		' WHERE source = ' + @src + 
		IIF(@HasDate = 0, '', ' AND date1 = ' + @tdt)

--select @Clear_Sql as 'Clear', @Proc_Sql as 'Proc', @Show_Sql as 'Show'

IF (1 & @ExecMaska = 1)
BEGIN
	IF (@SignatureType = 1)
		EXEC sp_executesql @Proc_Sql, @ParamList, @Source
	IF (@SignatureType = 2)
		EXEC sp_executesql @Proc_Sql, @ParamList, @Source, @Date, @Id	
END

IF (2 & @ExecMaska = 2)
	EXEC sp_executesql  @Show_Sql

IF (4 & @ExecMaska = 4)
	EXEC sp_executesql @Clear_Sql

END

GO
