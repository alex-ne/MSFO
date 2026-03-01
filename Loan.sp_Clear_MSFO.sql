SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 21/12/2023
-- Description:	Очистка в МСФО набора таблиц из Loan - на заданную дату
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[sp_Clear_MSFO] 
	@Date date = NULL				    -- Очищаются данные на заданную дату. 
AS
BEGIN 
	IF @Date IS NULL  
		RETURN 0

	DECLARE 
		@Source varchar(100) = 'GEstBank-Loan',
		@Pos int = 0

	SET @pos += 1 
	DELETE FROM [dbo].[syn_MSFO_msfo9_guarantee_tr]
	WHERE date1 = @Date AND source = @Source 

	SET @pos += 1 
	DELETE FROM [dbo].[syn_MSFO_msfo9_pledge_tr]
	WHERE date1 = @Date AND source = @Source 

	SET @pos += 1 
	DELETE FROM [dbo].[syn_MSFO_msfo9_client_tr]
	WHERE date1 = @Date AND source = @Source 

	SET @pos += 1 
	DELETE FROM [dbo].[syn_MSFO_msfo9_pledge_tr]
	WHERE date1 = @Date AND source = @Source 

	SET @pos += 1 
	DELETE FROM [dbo].[syn_MSFO_msfo9_graf_tr]
	WHERE date1 = @Date AND source = @Source 

	SET @pos += 1 
	DELETE FROM [dbo].[syn_MSFO_msfo9_portfolio_tr]
	WHERE date1 = @Date AND source = @Source 

	SET @pos += 1 
	DELETE FROM [dbo].[syn_MSFO_msfo9_account_tr]
	WHERE date1 = @Date AND source = @Source 

	SET @pos += 1 
	DELETE FROM [dbo].[syn_MSFO_msfo9_loan_tr]
	WHERE date1 = @Date AND source = @Source 

	RETURN @pos
END
