SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 21/12/2023
-- Description:	Очистка в МСФО набора таблиц из Loan - по всем датам заданного периода
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[sp_ClearRange_MSFO] 
	@Start date = NULL,	-- дата начала интервала выгрузки; если NULL - берется текущая			   
	@Finish date = NULL -- дата окончания интервала выгрузки; если NULL - берется текущая	
AS
BEGIN 
	SET @Start = ISNULL(@Start, GETDATE())
	SET @Finish = ISNULL(@Finish, GETDATE())

	IF @Start > @Finish
		RETURN

	DECLARE
		@Date date = @Start,
		@rc int

	print ('Clear From: ' + FORMAT(@Start, 'd', 'de-de') + ' To: ' + FORMAT(@Finish, 'd', 'de-de'))

	WHILE @Date <= @Finish
	BEGIN
		print(@Date) 
		EXEC [Loan].[sp_Clear_MSFO] @Date
		SET @Date = DATEADD(DAY, 1, @Date)		
	END
END
