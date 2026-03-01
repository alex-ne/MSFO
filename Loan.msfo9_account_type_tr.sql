/****** Object:  StoredProcedure [Loan].[msfo9_account_type_tr]    Script Date: 24.06.2024 18:06:00 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 23/11/2023
-- Description:	Выгрузка в транзитную таблицу типов счетов Loan, относящихся к операциям корректировки МСФО
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[msfo9_account_type_tr] 
	@Source varchar(100),
	@Date date
AS
BEGIN
	-- Удаляем записи, добавленные в транзитную таблицу ранее
	DELETE FROM dbo.syn_MSFO_msfo9_account_type_tr
	WHERE source = @Source and date1 = @Date

	-- Заливаем в транзитную таблицу типы регистров, прочитанные на момент вызова процедуры 
	INSERT INTO dbo.syn_MSFO_msfo9_account_type_tr(date1, source, oid, [name])
	SELECT  @Date, @Source, [RegisterTypeID] as oid, [Name]      
	FROM [Loan].[RegisterType]

	-- Резервы по присужденным пени
	INSERT INTO dbo.syn_MSFO_msfo9_account_type_tr(date1, source, oid, [name])
	VALUES
		(@Date, @Source, '113r', 'Резерв по присужденным пени по просроченной задолженности'),
		(@Date, @Source, '114r', 'Резерв по присужденным пени по просроченным процентам')
	
	RETURN @@ROWCOUNT

END

GO


