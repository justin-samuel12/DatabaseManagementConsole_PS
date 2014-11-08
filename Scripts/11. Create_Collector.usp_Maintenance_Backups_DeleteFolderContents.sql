SET ANSI_NULLS, ANSI_PADDING, ANSI_WARNINGS, ARITHABORT, CONCAT_NULL_YIELDS_NULL, QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO
USE [$(Database_Name)]
GO
/********************* VARIABLES *******************************/
	DECLARE @SQL VARCHAR(MAX) ='';

	DECLARE @VersionNumber numeric(3,2) ='1.0';
	DECLARE @Option varchar(256)= 'New';
	DECLARE @Author varchar(256)= 'justin_samuel';
	DECLARE @ObjectName varchar(256) = 'Collector.usp_Maintenance_Backups_DeleteFolderContents';
	DECLARE @Description VARCHAR(100)='Creation of stored procedure: '+ @ObjectName;
	DECLARE @ReleaseDate datetime = '10/1/2013';
	DECLARE @DTNow DateTime2 = getdate();
/***************************************************************/
BEGIN TRY
	-- 1. Drop if exists
		IF OBJECT_ID(@ObjectName) IS NOT NULL BEGIN EXEC ('DROP PROC ' + @ObjectName + '') END;

	-- 2. Create table	
			SET @SQL = '
-- =============================================
-- Create date: 3/1/2013
-- Description:	Delete backup files   
-- =============================================
CREATE PROCEDURE ' + @ObjectName + '
	@DaysToRetain INT = 4 -- how many days back to start deletion (default is to keep 4 days).
AS
BEGIN
	SET NOCOUNT ON; 	
	DECLARE @DateToRemove				DateTime =  DATEADD(DAY, DATEDIFF(DAY, 0 , GETDATE()) - @DaysToRetain,0 ); -- actual date
	DECLARE @Backupfolderlocation		VARCHAR(100) = [Configuration].[svfn_DefaultFolderLocation_Get](''BackupDirectory''); -- backupfolder local
	DECLARE @SQL						NVARCHAR(4000) = ''FORFILES /p '' + @Backupfolderlocation + '' /s /m *.* /d -'' + cast(@DaysToRetain as varchar(5)) + '' /c "CMD /C del /Q /F @FILE"'';
	
	EXEC xp_cmdshell @SQL;
				
	-- Delete from Backupset tables / msdb backupset
	DELETE FROM [Collector].[t_Backupset] WHERE DATEADD(DAY, DATEDIFF(DAY, 0 , CreateDatetime),0 ) <= @DateToRemove;
	DELETE FROM [Collector].[t_BackupsetOperation] WHERE DATEADD(DAY, DATEDIFF(DAY, 0 , CreateDatetime),0 ) <= @DateToRemove;
	DELETE FROM [Collector].[t_BackupsetRestoreScripts] WHERE DATEADD(DAY, DATEDIFF(DAY, 0 , CreateDatetime),0 ) <= @DateToRemove;
		
	EXEC MSDB..SP_DELETE_BACKUPHISTORY @DateToRemove;
END		
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
