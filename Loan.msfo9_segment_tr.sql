SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 28/11/2023
-- Description:	Выгрузка в транзитную таблицу сегментов кредитьвания
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[msfo9_segment_tr] 
	@Source varchar(100)
AS
BEGIN
	-- Удаляем сегменты бизнеса, записанные в транзитную таблицу ранее
	DELETE FROM dbo.syn_MSFO_msfo9_segment_tr WHERE [source] = @Source

	-- Добавляем в транзитную таблицу новые значения сегментов бизнеса
	INSERT INTO dbo.syn_MSFO_msfo9_segment_tr(id, source, [name])
	VALUES
		(1, @Source, 'Малый'),
		(2, @Source, 'Средний'),
		(3, @Source, 'Крупный'),
		(4, @Source, 'Микропредприятие')

	RETURN @@ROWCOUNT

END

GO


