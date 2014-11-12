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
	DECLARE @ObjectName varchar(256) = 'Collector.usp_Maintenance_Backups_Configure';
	DECLARE @Description VARCHAR(100)= 'Creation of stored procedure: '+ @ObjectName
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
-- Description:	Configure backups
-- =============================================
CREATE PROCEDURE ' + @ObjectName + '
AS
BEGIN TRY;
	SET NOCOUNT ON;
/********************* VARIABLES *******************************/
DECLARE @Date_Now DATETIME2 = GETDATE(), @Date_NULL DATETIME2 = dateadd(Day,-1,getdate()), @DMCDatabase SYSNAME  = DB_NAME(), @ServerName SYSNAME  = CONVERT(varchar(128),SERVERPROPERTY(''servername'') ),@Operationtype NVARCHAR(50) = NULL, @Operationstatus NVARCHAR(50) =''Success'', @SQL VARCHAR(MAX), @Backupfolderlocation VARCHAR(100) = [Configuration].[svfn_DefaultFolderLocation_Get](''BackupDirectory''),@Backupfileconvention VARCHAR(500) = CONVERT(VARCHAR, GETDATE() ,112) + ''_'' + REPLACE( CAST(GETDATE() AS TIME(2)) ,'':'',''-''),@Backupfolder VARCHAR(500), @Backupfile VARCHAR(500), @BackupType VARCHAR(1) = NULL,
@ErrorMsg VARCHAR(50), @Backupsetid INT, @TotalDatabasesCount INT,@DatabaseLoopCount INT = 1,@Database_ID INT, @Database_Name SYSNAME, @Recovery_Model INT,@JobName VARCHAR(256), @JobCommand1 VARCHAR(1000), @JobCommand2 VARCHAR(1000),@ProcessFinishDatetime Datetime2, @isJobRunning BIT, @MaintenanceBackupSetId INT;
DECLARE @Databases TABLE ( Id INT Identity(1,1), Database_Id INT PRIMARY KEY Clustered, Name Sysname, Recovery_Model Int );
/***************************************************************/
INSERT @Databases (Database_Id, Name, Recovery_Model)
	SELECT DATABASE_ID, NAME, RECOVERY_MODEL FROM MASTER.SYS.DATABASES WITH(NOLOCK) WHERE IS_READ_ONLY = 0 AND IS_IN_STANDBY = 0 AND DATABASE_ID <>2;
	SET @TotalDatabasesCount = @@ROWCOUNT;

	WHILE @DatabaseLoopCount < = @TotalDatabasesCount
			BEGIN
				-- 2a. Set preconditions
				SET @BackupType = NULL;	SET @ProcessFinishDatetime = NULL;SET @isJobRunning = NULL; SET @MaintenanceBackupSetId = NULL;
				
				SELECT @Database_ID = Database_Id, @Database_Name = Name, @Recovery_Model = Recovery_Model	FROM @Databases WHERE id = @DatabaseLoopCount;
				SET @Backupfolder = @backupfolderlocation ++ @database_name; Execute Master.dbo.xp_create_subdir @Backupfolder;
				--get latest info per db
				SELECT @ProcessFinishDatetime = ProcessFinishDatetime, @isJobRunning = isJobRunning FROM [Collector].[v_MaintenanceBackup]	WHERE MaintenanceBackupHistoryId = (select MAX(MaintenanceBackupHistoryId) FROM [Collector].[v_MaintenanceBackup] WHERE [Database] = @Database_Name);
				SET @ProcessFinishDatetime = isnull(@ProcessFinishDatetime,@Date_NULL); SET @isJobRunning = isnull(@isJobRunning,0);
				-- if there is no current job running
				IF (@isJobRunning = 0)
					BEGIN
						-- 2b1. Full backups. If operation runs for first time and there are no full backups for that day then this step will execute first
						IF ( CAST(@ProcessFinishDatetime as Date) <> Cast( @date_now as date) )
							BEGIN
								SET @Operationtype =''Full Backup'';
								SET @BackupType =''D'';
								SET @Backupfile =  @backupfolder + ''\'' + @database_name + ''_Database_Full_'' + @backupfileconvention  + ''.bak'';
								SET @SQL =''BACKUP DATABASE ['' + @database_name +'']
											TO DISK = N''''''''''+ @backupfile + '''''''''' 
											WITH NOFORMAT, NOINIT, NAME = N''''''''''+ + @database_name + ''_Database_Full_'' + @backupfileconvention + '''''''''', SKIP, REWIND, NOUNLOAD, COMPRESSION, CHECKSUM,  STATS = 10''			
							END;
						-- 2b2. Differential backups. Run every 4 hrs only starting at 4AM
						ELSE IF @Database_ID > 4 AND DATEPART(HH,@Date_Now) IN (4,8,12,16,20)
							BEGIN
								SET @Operationtype =''Differential Backup'';
								SET @BackupType =''I'';
								SET @Backupfile =  @backupfolder + ''\'' + @database_name + ''_Database_Differential_'' + @backupfileconvention  + ''.dif'';
								SET @SQL =''BACKUP DATABASE ['' + @database_name +'']
											TO DISK = N''''''''''+ @backupfile + '''''''''' 
											WITH NOFORMAT, NOINIT, DIFFERENTIAL, NAME = N''''''''''++ @database_name + ''_Database_Differential_'' + @backupfileconvention +'''''''''', SKIP, REWIND, NOUNLOAD, COMPRESSION, CHECKSUM, STATS = 10''			
							END;
						-- 2b3. Transaction Log
						ELSE IF @Database_ID > 4 AND @Recovery_Model IN (1,2) 
							BEGIN
								SET @Operationtype =''Transaction Log'';
								SET @BackupType =''L'';
								SET @Backupfile =  @backupfolder + ''\'' + @database_name + ''_Transaction_Log_'' + @backupfileconvention  + ''.trn'';
								SET @SQL =''BACKUP LOG ['' + @database_name +'']
											TO DISK = N''''''''''+ @backupfile + '''''''''' 
											WITH NOFORMAT, NOINIT, NAME = N''''''''''++ @database_name + ''_Transaction_Log_'' + @backupfileconvention +'''''''''', SKIP, REWIND, NOUNLOAD, COMPRESSION, CHECKSUM, STATS = 10''			
							END;
					-- 2c. insert into Collector.usp_Maintenance_Backups_Retrieve and create dynamic job
					IF (@BackupType IS NOT NULL )
						BEGIN
							SET @JobName = FORMATMESSAGE(''DMC.Backup_%s_%s_[%s]'', @Database_Name, @Operationtype, convert(varchar,@Date_Now, 120));
							EXEC [Collector].[usp_Maintenance_Backups_Merge] @DatabaseName = @Database_Name, @JobName = @JobName, @MaintenanceBackupSetId = @MaintenanceBackupSetId OUTPUT
							SET @JobCommand1 = ''USE '' + QUOTENAME(@DMCDatabase) + '' 
GO
EXEC [Collector].[usp_Maintenance_Backups_Retrieve]
											@MaintenanceBackupSetId = '''''' + CAST(@MaintenanceBackupSetId as varchar(100)) + '''''', 
											@Backupfile = '''''' + @Backupfile + '''''', 
											@BackupType = '''''' + @BackupType + '''''',
											@Operationtype = '''''' + @Operationtype + '''''',
											@ExecutionCommand = '''''' + @SQL + '''''',
											@database_name = '''''' + @Database_Name + '''''''';
							SET @JobCommand2 = ''USE '' + QUOTENAME(@DMCDatabase) + '' 
GO 
EXEC [Collector].[usp_Maintenance_Backups_CreateRestoreScripts] '''''' + @Database_Name + '''''''';
							IF EXISTS ( select job_id  FROM msdb.dbo.sysjobs WHERE name = @JobName ) begin EXEC msdb.dbo.sp_delete_job @job_name= @JobName, @delete_unused_schedule=1 end ;
							EXEC msdb..sp_add_job @job_name= @JobName, @enabled=1, @delete_level=1, @description= @JobName, @owner_login_name=N''sa'';
							EXEC msdb..sp_add_jobstep @job_name= @JobName, @step_name= @Operationtype,@step_id=1, @cmdexec_success_code=0,@on_success_action=3, @on_success_step_id=0, @on_fail_action=2, @subsystem = N''TSQL'', @command= @JobCommand1,@database_name=N''master'';
							EXEC msdb..sp_add_jobstep @job_name= @JobName, @step_name=N''Create restore scripts'',@step_id=2, @cmdexec_success_code=0,@on_success_action=1,@on_success_step_id=0,@on_fail_action=2, @subsystem=N''TSQL'', @command= @JobCommand2, @database_name=N''master'';
							EXEC msdb..sp_add_jobserver @job_name = @jobName, @server_name = @serverName;
						
							WAITFOR DELAY ''00:00:01'';
							EXEC msdb..sp_start_job @job_name = @jobName
						END;
					END;
				SET @DatabaseLoopCount +=1;
			END;
END TRY
BEGIN CATCH
		DECLARE @ProcedureName		SYSNAME			= QUOTENAME(OBJECT_SCHEMA_NAME(@@PROCID)) +''.'' + QUOTENAME(object_name(@@PROCID))
		DECLARE @ErrorMessageFormat	VARCHAR(8000)	= ''There was an error when executing the stored procedure: %s'' + char(13) + ''Please see below for information'' + char(13) + char(13) +
														''Error Message: %s'' + char(13) + 
														''Error Severity: %i'' + char(13) + 
														''Error State: %i'' + char(13) + 
														''Error Number: %i'';
		DECLARE @ErrorMessage		VARCHAR(MAX)	= FORMATMESSAGE(@ErrorMessageFormat, @ProcedureName, ERROR_MESSAGE() , ERROR_SEVERITY() ,ERROR_STATE(), ERROR_NUMBER ());	
		EXEC Collector.usp_Maintenance_Backups_Merge @MaintenanceBackupSetId = @MaintenanceBackupSetId,  @isError = 1, @ErrorMessage = @ErrorMessage;
	    RAISERROR (@ErrorMessage,16,1) WITH LOG;
END CATCH;
';
	--PRINT @SQL
	EXEC (@SQL);
	 
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







