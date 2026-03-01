SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 10/12/2024
-- Description:	Выгрузка в МСФО типов договоров гарантий
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[msfo9_guarantee_type_tr]
	@Source varchar(40)
AS
BEGIN
	print '[Кредиты] Типы договоров гарантий'

	-- Очистка транзитной таблицы ОО
	DELETE FROM dbo.syn_MSFO_msfo9_guarantee_type_tr
	WHERE source = @Source

	INSERT INTO dbo.syn_MSFO_msfo9_guarantee_type_tr
	(		
		 [source]				 --[varchar](40) NOT NULL, источник данных (код учетной системы банка, откуда были выгружены данные)		
		,[id]					 --[varchar](60) NOT NULL, идентификатор кода справочника	
		,[description]			 --[varchar](255) NOT NULL, описание кода	
		,[is_finance_obligation] --[bit] NULL, Тип обязательства: 1 - финансовое, 0 - нефинансовое
	)
	VALUES
		(@Source, 0, 'Банковская гарантия', 0),
		(@Source, 1, 'Международная гарантия', 0),
		(@Source, 2, 'Контр-гарантия', 0),
		(@Source, 3, 'Гарантия против контр-гарантии', 0)

	RETURN @@ROWCOUNT
END

