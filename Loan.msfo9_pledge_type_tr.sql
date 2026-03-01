SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 19/06/2023
-- Description:	Выгрузка в транзитную таблицу типов обеспечения Loan
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[msfo9_pledge_type_tr] 
	@Source varchar(100)
AS
BEGIN
	-- Удаляем записи, добавленные в транзитную таблицу ранее
	DELETE FROM [dbo].[syn_MSFO_msfo9_pledge_type_tr]
	WHERE source = @Source;

	with lst as (select max(CollateralTypeID) as id FROM GbPledges.T_CollateralType group by Code)

	-- Заливаем в транзитную таблицу типы обеспечения, прочитанные на момент вызова процедуры 
	INSERT INTO [dbo].[syn_MSFO_msfo9_pledge_type_tr]([id], [source], [description])
	SELECT clt.Code as [id], @Source as [source], CAST(clt.[Name] as NVARCHAR(255)) as [description] 
	FROM lst c
	INNER JOIN GbPledges.T_CollateralType clt on c.Id = clt.CollateralTypeID
	ORDER BY clt.Code
	
	RETURN @@ROWCOUNT

END

