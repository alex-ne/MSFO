SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 21/12/2023
-- Description:	Первоначальная настройка синонимов таблиц МСФО-9 для загрузки/выгрузки данных из/в Loan
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[sp_Init_MSFO] 
	@DataBase nvarchar(255),	-- Имя базы данных МСФО
	@Schema nvarchar(255)		-- Схема целевых таблиц в БД МСФО
AS
BEGIN
	-- Типы счетов
	EXEC [dbo].[p_UpdateMsfoTableSynonym] @DataBase, @Schema, 'msfo9_account_type_tr'
	-- Счета
	EXEC [dbo].[p_UpdateMsfoTableSynonym] @DataBase, @Schema, 'msfo9_account_tr'
	-- Клиенты
	EXEC [dbo].[p_UpdateMsfoTableSynonym] @DataBase, @Schema, 'msfo9_client_tr'
	-- Типы кредитных договоров
	EXEC [dbo].[p_UpdateMsfoTableSynonym] @DataBase, @Schema, N'msfo9_loan_type_tr'
	-- Кредитные договора 
	EXEC [dbo].[p_UpdateMsfoTableSynonym] @DataBase, @Schema, N'msfo9_loan_tr'
	-- Типы графиков погашения 
	EXEC [dbo].[p_UpdateMsfoTableSynonym] @DataBase, @Schema, N'msfo9_graf_type_tr'
	-- График погашения 
	EXEC [dbo].[p_UpdateMsfoTableSynonym] @DataBase, @Schema, N'msfo9_graf_tr'
	-- Продукты 
	EXEC [dbo].[p_UpdateMsfoTableSynonym] @DataBase, @Schema, N'msfo9_loan_product_tr'
	-- Сегменты 
	EXEC [dbo].[p_UpdateMsfoTableSynonym] @DataBase, @Schema, N'msfo9_segment_tr'
	-- Сегменты бизнеса (юд кд)
	EXEC [dbo].[p_UpdateMsfoTableSynonym] @DataBase, @Schema, N'msfo9_loan_yul_segment_tr'
	-- Портфели кредитов 
	EXEC [dbo].[p_UpdateMsfoTableSynonym] @DataBase, @Schema, N'msfo9_portfolio_tr'
	-- Обеспечение кредитов
	EXEC [dbo].[p_UpdateMsfoTableSynonym] @DataBase, @Schema, N'msfo9_pledge_tr'
	-- Типы обеспечения кредитов
	EXEC [dbo].[p_UpdateMsfoTableSynonym] @DataBase, @Schema, N'msfo9_pledge_type_tr'
	-- Гарантии
	EXEC [dbo].[p_UpdateMsfoTableSynonym] @DataBase, @Schema, N'msfo9_guarantee_tr'
	-- Типы гарантий
	EXEC [dbo].[p_UpdateMsfoTableSynonym] @DataBase, @Schema, N'msfo9_guarantee_type_tr'
	-- Операции
	EXEC [dbo].[p_UpdateMsfoTableSynonym] @DataBase, @Schema, 'msfo9_acc_entries_tr'
END
