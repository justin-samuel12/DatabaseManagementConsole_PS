SET ANSI_NULLS, ANSI_PADDING, ANSI_WARNINGS, ARITHABORT, CONCAT_NULL_YIELDS_NULL, QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;

GO
USE [$(Database_Name)]
GO
EXEC sp_configure 'show advanced options',1
RECONFIGURE WITH OVERRIDE
GO
EXEC sp_configure 'blocked process threshold (s)',30
RECONFIGURE WITH OVERRIDE 
GO
EXEC sp_configure 'show advanced options',0
RECONFIGURE WITH OVERRIDE
GO
/********************* VARIABLES *******************************/
	DECLARE @SQL VARCHAR(MAX) ='';

	DECLARE @VersionNumber numeric(3,2) ='1.0';
	DECLARE @Option varchar(256)= 'New';
	DECLARE @Author varchar(256)= 'justin_samuel';
	DECLARE @ObjectName varchar(256) = 'Collector.t_BlockedEvents';
	DECLARE @Description VARCHAR(100)='Creation of table: '+ @ObjectName
	DECLARE @ReleaseDate datetime = '10/1/2013';
	DECLARE @DTNow DateTime2 = getdate();
/***************************************************************/

BEGIN TRY
	-- 1. Drop if exists
		IF OBJECT_ID(@ObjectName) IS NOT NULL BEGIN EXEC ('DROP Table ' + @ObjectName + '') END;

	-- 2. Create table	
			SET @SQL = '
CREATE TABLE ' + @ObjectName + ' (
			[BlockedEventsId] INT NOT NULL  IDENTITY(1,1), 
			[SPID] INT NULL,
			[BlockedReport] XML NOT NULL,
			[AlertDateTime] DATETIME2 NOT NULL DEFAULT(GETDATE()),
			CONSTRAINT [pk_t_BlockedEvents] PRIMARY KEY CLUSTERED 
				( BlockedEventsId ASC )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
			) ON [PRIMARY]
';
	 
	--PRINT @SQL
	 EXEC (@SQL)
	 
	 -- 3. insert into [Config].[t_VersionControl]
	 EXEC Configuration.usp_VersionControl_Merge @VersionNumber = @VersionNumber, @ScriptName = '$(File_Name)', @Author = @Author, 
			@ObjectName = @ObjectName, @Option = @Option, @Description = @Description, @ReleaseDate = @ReleaseDate, @isError = 0, @ErrorMsg = NULL;
END TRY
BEGIN CATCH
		DECLARE @ProcedureName		SYSNAME			=  '$(File_Name)';
		DECLARE @ErrorMessageFormat	VARCHAR(8000)	= 'There was an error when executing the step: %s|' +
														'Error Message: %s|' + 
														'Error Severity: %i|' + 
														'Error State: %i|' + 
														'Error Number: %i';
		DECLARE @ErrorMessage		VARCHAR(MAX)	= FORMATMESSAGE(REPLACE(@ErrorMessageFormat,char(13),'`r`n'), @ProcedureName, ERROR_MESSAGE() , ERROR_SEVERITY() ,ERROR_STATE(), ERROR_NUMBER ());	
		
		IF OBJECT_ID('Config.usp_VersionControl_Merge') IS NOT NULL EXEC Configuration.usp_VersionControl_Merge @VersionNumber = @VersionNumber, @ScriptName = '$(File_Name)', @Author = @Author, @ObjectName = @ObjectName, @Option = @Option, @Description = @Description, @ReleaseDate = @ReleaseDate, @isError = 1, @ErrorMsg = @ErrorMessage;
		RAISERROR (@ErrorMessage,16,1) WITH LOG;
END CATCH;
GO
