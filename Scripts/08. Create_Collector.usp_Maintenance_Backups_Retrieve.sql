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
	DECLARE @ObjectName varchar(256) = 'Collector.usp_Maintenance_Backups_Retrieve';
	DECLARE @Description VARCHAR(100)='Creation of stored procedure: '+ @ObjectName
	DECLARE @ReleaseDate datetime = '11/10/2014';
	DECLARE @DTNow DateTime2 = getdate();
/***************************************************************/
BEGIN TRY
	-- 1. Drop if exists
		IF OBJECT_ID(@ObjectName) IS NOT NULL BEGIN EXEC ('DROP PROCEDURE ' + @ObjectName + '') END;

	-- 2. Create table	
			SET @SQL = '
-- =============================================
-- Create date: ''' + cast(@ReleaseDate as varchar) + '''
-- Description:	Retrieve backupset info and verify
-- =============================================
CREATE PROCEDURE ' + @ObjectName + '
	@MaintenanceBackupSetId				INT,
	@Backupfile							VARCHAR(500),
	@BackupType							VARCHAR(1),
	@Operationtype						NVARCHAR(50),
	@ExecutionCommand				    VARCHAR(MAX),
	@Database_name						SYSNAME
AS
BEGIN TRY;
	SET NOCOUNT ON;
	/******************************** VARIABLES ********************************/
		DECLARE @backupsetid						INT;
		DECLARE @ErrorMessage						VARCHAR(1000);
		DECLARE @VerifyBackupFile					NVARCHAR(4000) = '''';
	/**************************************************************************/
	
	-- 1. execution of command
		EXEC (@ExecutionCommand);
	
	-- 2. validate
		SET @backupsetid = ( SELECT MAX(backup_set_id) FROM msdb..backupset WHERE database_name = @database_name and [type] = @BackupType );	
		IF @backupsetid IS NULL 
			BEGIN 
				SET @ErrorMessage = ''Verify failed. Backup information for database: '' + @database_name + '' not found.'';
				EXEC Collector.usp_Maintenance_Backups_Merge @MaintenanceBackupSetId = @MaintenanceBackupSetId,  @isError = 1, @ErrorMessage = @ErrorMessage
				RAISERROR (@ErrorMessage, 16, 1); 
				RETURN;
			END
		ELSE
			BEGIN
				SET @VerifyBackupFile = ''RESTORE VERIFYONLY FROM DISK = ''''''++ @Backupfile +''''''  WITH CHECKSUM'';								
				EXEC SP_EXECUTESQL @VerifyBackupFile;
				if @@ERROR <>0 
					BEGIN
						SET @ErrorMessage = ''Verify failed for file: ''+ @Backupfile +''. Backup information for database: '' + @database_name + '' not found.'';
						EXEC Collector.usp_Maintenance_Backups_Merge @MaintenanceBackupSetId = @MaintenanceBackupSetId,  @isError = 1, @ErrorMessage = @ErrorMessage
						RAISERROR (@ErrorMessage, 16, 1);
						RETURN;
					END;
				ELSE
					EXEC Collector.usp_Maintenance_Backups_Merge @backup_set_id = @backupsetid, @MaintenanceBackupSetId = @MaintenanceBackupSetId, @Filename = @Backupfile
			END;
END TRY
BEGIN CATCH
	DECLARE @ProcedureName		SYSNAME			= QUOTENAME(OBJECT_SCHEMA_NAME(@@PROCID)) +''.'' + QUOTENAME(object_name(@@PROCID))
	DECLARE @ErrorMessageFormat	VARCHAR(8000)	= ''There was an error when executing the stored procedure: %s'' + char(13) + ''Please see below for information'' + char(13) + char(13) +
													''Error Message: %s'' + char(13) + 
													''Error Severity: %i'' + char(13) + 
													''Error State: %i'' + char(13) + 
													''Error Number: %i'';
	SET	@ErrorMessage							= FORMATMESSAGE(@ErrorMessageFormat, @ProcedureName, ERROR_MESSAGE() , ERROR_SEVERITY() ,ERROR_STATE(), ERROR_NUMBER ());	
	RAISERROR (@ErrorMessage,16,1);		
END CATCH;
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
		
		IF OBJECT_ID('Configuration.usp_VersionControl_Merge') IS NOT NULL EXEC Configuration.usp_VersionControl_Merge @VersionNumber = @VersionNumber, @ScriptName = '$(File_Name)', @Author = @Author, @ObjectName = @ObjectName, @Option = @Option, @Description = @Description, @ReleaseDate = @ReleaseDate, @isError = 1, @ErrorMsg = @ErrorMessage;
		RAISERROR (@ErrorMessage,16,1) WITH LOG;
END CATCH;
GO
