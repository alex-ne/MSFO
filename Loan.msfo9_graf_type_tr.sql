/****** Object:  StoredProcedure [Loan].[msfo9_graf_type_tr]    Script Date: 02.10.2024 16:03:47 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Немтинов А.В.
-- Create date: 28/11/2023
-- Description:	Выгрузка в транзитную таблицу типы графиков погашения кредита
-- =============================================
CREATE OR ALTER PROCEDURE [Loan].[msfo9_graf_type_tr] 
	@Source varchar(100)
AS
BEGIN
-- Удаляем типы графиков погашения кредита, записанные в транзитную таблицу ранее
DELETE FROM dbo.syn_MSFO_msfo9_graf_type_tr WHERE [source] = @Source

-- Добавляем в транзитную таблицу новые типы графиков погашения кредита
INSERT INTO dbo.syn_MSFO_msfo9_graf_type_tr(oid, source, [description], day_payment)
VALUES
	(0,  @Source, 'Аннуитетный', NULL),                                                                 
	(1,  @Source, 'Равными долями', NULL),                                                              
	(2,  @Source, 'Фиксированная сумма', NULL),                                                         
	(3,  @Source, 'Погашение в конце', NULL),                                                           
	(4,  @Source, 'Произвольный', NULL),                                                                
	(5,  @Source, 'Аннуитетный с отсрочкой по ОД', NULL),                                               
	(6,  @Source, 'Аннуитетный с пересчетом графика', NULL),                                            
	(7,  @Source, 'АИЖК-1', NULL),                                                                      
	(8,  @Source, 'АИЖК-2', NULL),                                                                      
	(9,  @Source, 'Военная ипотека', NULL),                                                             
	(10, @Source, 'Аннуитетный с пересчетом при отсрочке платежа', NULL),                              
	(11, @Source, 'На погашаемую сумму', NULL),                                                        
	(12, @Source, 'АИЖК-3', NULL),                                                                     
	(13, @Source, 'Аннуитетный с пересчетом (мульти)', NULL),                                          
	(14, @Source, 'Аннуитетный с отсрочкой начала погашения', NULL),                                   
	(15, @Source, 'Не определён', NULL)	

RETURN @@ROWCOUNT

END

