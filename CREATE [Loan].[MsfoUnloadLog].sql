SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP TABLE IF EXISTS [Loan].[MsfoUnloadLog]

CREATE TABLE [Loan].[MsfoUnloadLog](
	[MsfoUnloadLogID] uniqueidentifier NOT NULL,
	[MsfoEventLogID] uniqueidentifier NOT NULL,	
	[Start] datetime NOT NULL,
	[Number] int NOT NULL,
	[TargetTable] varchar(50) NOT NULL,
	[Duration] decimal(9, 3) NULL,
	[Status] int NOT NULL,
	[RecordCount] int NULL,
	[ErrorNumber] int NULL, 
	[ErrorProc] varchar(255) NULL,
	[ErrorMessage] varchar(1024) NULL,
 CONSTRAINT [PK_MsfoUnloadLog] PRIMARY KEY CLUSTERED 
(
	[MsfoUnloadLogID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [Loan].[MsfoUnloadLog]  WITH NOCHECK ADD  CONSTRAINT [FK_MsfoEventLog] FOREIGN KEY([MsfoEventLogID])
REFERENCES [Loan].[MsfoEventLog] ([MsfoEventLogID])
GO