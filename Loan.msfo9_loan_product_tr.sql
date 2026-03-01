/****** Object:  StoredProcedure [Loan].[msfo9_loan_product_tr]    Script Date: 06.09.2024 12:56:29 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 27/11/2023
-- Description:	Выгрузка в транзитную таблицу типов кредитных продуктов
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[msfo9_loan_product_tr] 
	@Source varchar(100)
AS
BEGIN
	-- Удаляем типы КД, записанные в транзитную таблицу ранее
	DELETE FROM dbo.syn_MSFO_msfo9_loan_product_tr WHERE [source] = @Source

	-- Добавляем в транзитную таблицу новые значения типов КД
	INSERT INTO dbo.syn_MSFO_msfo9_loan_product_tr(id, source, [name], short_name)
	SELECT [ProductTypeID] AS Id, @Source, [Name], [Brief]
	FROM [Loan].[ProductType]

	--INSERT INTO dbo.syn_MSFO_msfo9_loan_product_tr(id, source, [name])
	--SELECT [ProductID] AS Id, @Source, [Name]
	--FROM [dbo].[T_Product]

	RETURN @@ROWCOUNT
END

