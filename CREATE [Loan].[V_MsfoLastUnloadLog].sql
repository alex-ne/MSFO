CREATE OR ALTER VIEW [Loan].[V_MsfoLastUnloadLog] AS
SELECT u.[MsfoUnloadLogID]
      ,e.[MsfoEventLogID]
      ,e.[ForDate]
      ,u.[Start]
      ,u.[Number]
      ,u.[TargetTable]
      ,u.[Duration]
      ,u.[Status]
      ,u.[RecordCount]
      ,u.[ErrorNumber]
      ,u.[ErrorProc]
      ,u.[ErrorMessage]
FROM [Loan].[MsfoEventLog] e
INNER JOIN [Loan].[MsfoUnloadLog] u ON u.MsfoEventLogID = e.MsfoEventLogID
WHERE e.[Start] = (select MAX([Start]) from [Loan].[MsfoEventLog] where ForDate = e.forDate)
