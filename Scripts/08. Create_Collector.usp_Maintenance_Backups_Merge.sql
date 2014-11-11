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
	DECLARE @ObjectName varchar(256) = 'Collector.usp_Maintenance_Backups_Merge';
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
-- Description: Merge SP
-- =============================================
CREATE PROCEDURE ' + @ObjectName + '
	@DatabaseName			SYSNAME = NULL,
	@Jobname				VARCHAR(256)  = NULL,
	@isJobRunning			Bit  = NULL,
	@isError				Bit  = NULL,
	@ErrorMsg				varchar(max)='''',
	@Filename				varchar(500)='''', 
	@backup_set_id			INT = 0,
	@MaintenanceBackupSetId INT  = NULL OUTPUT	

AS
BEGIN TRY;
	SET NOCOUNT ON;
	/******************************** VARIABLES ********************************/
		DECLARE @DTNow datetime2=  getdate();
	/**************************************************************************/

	if @MaintenanceBackupSetId IS NULL -- initial insert
		BEGIN
			-- insert INTO [Collector].[t_MaintenanceBackupSet]
			INSERT INTO [Collector].[t_MaintenanceBackupSet]([Database]) VALUES(@DatabaseName);
			SET @MaintenanceBackupSetId = SCOPE_IDENTITY();

			-- then into [Collector].[t_MaintenanceBackupHistory]
			INSERT INTO [Collector].[t_MaintenanceBackupHistory] (MaintenanceBackupSetId, Jobname, ProcessStartDatetime, CreateDatetime)
			VALUES (@MaintenanceBackupSetId, @Jobname, @DTNow, @DTNow)

		END;
	ELSE
		BEGIN
			-- if isError is flag then update
			IF ( @isError = ''true'' )
					BEGIN
						UPDATE [Collector].[t_MaintenanceBackupHistory] 
						SET isJobRunning = 0,
							isError = 1,
							ErrorMessage = @ErrorMsg,
							ProcessFinishDatetime = @DTNow
						WHERE MaintenanceBackupSetId = @MaintenanceBackupSetId;
					END

			ELSE
				BEGIN
					-- update [Collector].[t_MaintenanceBackupSet]
					UPDATE T
					SET T.Backup_set_id = S.Backup_set_id,
						T.name = S.NAME,  
						T.firstlsn = S.FIRST_LSN, 
						T.lastlsn = S.LAST_LSN, 
						T.backupstartdate = S.BACKUP_START_DATE, 
						T.backupfinishdate = S.BACKUP_FINISH_DATE, 
						T.sizeinkb = (S.BACKUP_SIZE + 1536) / 1024, 
						T.[type] = CASE WHEN s.[TYPE] =''D'' THEN ''Full Backup'' WHEN s.[TYPE] =''I'' THEN ''Differential'' WHEN s.[TYPE] =''L'' THEN ''Transactional Log'' ELSE ''Other'' END, 
						T.[database]= S.DATABASE_NAME, 
						T.[filename] = @FILENAME, 
						T.recoverymodel = S.RECOVERY_MODEL, 
						T.isdamaged = S.IS_DAMAGED,  
						T.machinenamewherefileresides = S.SERVER_NAME
					FROM [Collector].[t_MaintenanceBackupSet] T,
						 MSDB..Backupset S
					WHERE T.MaintenanceBackupSetId = @MaintenanceBackupSetId AND
						S.[Backup_set_id] = @backup_set_id

					-- update [Collector].[t_MaintenanceBackupSet]
					UPDATE [Collector].[t_MaintenanceBackupHistory]
					SET isJobrunning = 0, 
						isError = 0, 
						ErrorMessage = NULL, 
						ProcessFinishDatetime = @DTNow
					WHERE MaintenanceBackupSetId = @MaintenanceBackupSetId

				END;
		END;

Complete:
	SELECT @MaintenanceBackupSetId;

END TRY
BEGIN CATCH
	DECLARE @ProcedureName		SYSNAME			= QUOTENAME(OBJECT_SCHEMA_NAME(@@PROCID)) +''.'' + QUOTENAME(object_name(@@PROCID))
	DECLARE @ErrorMessageFormat	VARCHAR(8000)	= ''There was an error when executing the stored procedure: %s'' + char(13) + ''Please see below for information'' + char(13) + char(13) +
													''Error Message: %s'' + char(13) + 
													''Error Severity: %i'' + char(13) + 
													''Error State: %i'' + char(13) + 
													''Error Number: %i'';
	DECLARE @ErrorMessage		VARCHAR(MAX)	= FORMATMESSAGE(@ErrorMessageFormat, @ProcedureName, ERROR_MESSAGE() , ERROR_SEVERITY() ,ERROR_STATE(), ERROR_NUMBER ());	
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
