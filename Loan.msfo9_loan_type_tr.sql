/****** Object:  StoredProcedure [Loan].[msfo9_loan_type_tr]    Script Date: 06.09.2024 12:56:42 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 24/11/2023
-- Description:	Выгрузка в транзитную таблицу типов кредитных договоров
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[msfo9_loan_type_tr] 
	@Source varchar(100)
AS
BEGIN
	-- Удаляем типы КД, записанные в транзитную таблицу ранее
	DELETE FROM dbo.syn_MSFO_msfo9_loan_type_tr WHERE [source] = @Source
	/*
	-- Добавляем в транзитную таблицу новые значения типов КД
	INSERT INTO dbo.syn_MSFO_msfo9_loan_type_tr(id, source, [name])
	VALUES
		(1, @Source, 'Кредит'),
		(2, @Source, 'Кредитная линия с лимитом выдачи'),
		(3, @Source, 'Кредитная линия с лимитом задолженности'),
		(4, @Source, 'Права требования'),
		(5, @Source, 'Проданная ссуда'),
		(6, @Source, 'Овердрафт');
	*/
	
	-- Добавляем в транзитную таблицу новые значения типов КД
	INSERT INTO dbo.syn_MSFO_msfo9_loan_type_tr(id, source, [name])
	SELECT 
		ProductID as id, 
		@Source, 
		[Name] 
	FROM [dbo].[T_Product] 
	WHERE active = 1
	

	RETURN @@ROWCOUNT

END

