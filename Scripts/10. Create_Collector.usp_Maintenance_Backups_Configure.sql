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
		DECLARE @Date_Now							DATETIME2	 = GETDATE();
		DECLARE @DMCDatabase						SYSNAME		 = DB_NAME();
		DECLARE @ServerName							SYSNAME		 = CONVERT(varchar(128) ,  SERVERPROPERTY(''servername'') );
		DECLARE @Operationtype						NVARCHAR(50) = NULL;
		DECLARE @Operationstatus					NVARCHAR(50) =''Success'';
		DECLARE @SQL								VARCHAR(MAX);
		DECLARE @Backupfolderlocation				VARCHAR(100) = [Configuration].[svfn_DefaultFolderLocation_Get](''BackupDirectory'') ; -- backupfolder local
		DECLARE @Backupfileconvention				VARCHAR(500) = CONVERT(VARCHAR, @Date_Now ,112) + ''_'' + REPLACE( CAST(@Date_Now AS TIME(2)) ,'':'',''-'');
		DECLARE @Backupfolder						VARCHAR(500);
		DECLARE @Backupfile							VARCHAR(500);
		DECLARE @BackupType							VARCHAR(1)	 = NULL;
		DECLARE @ErrorMsg							VARCHAR(50);
		DECLARE @Backupsetid						INT;
		DECLARE @Databases							TABLE ( Id INT Identity(1,1), Database_Id INT PRIMARY KEY Clustered, Name Sysname, Recovery_Model Int );
		DECLARE @TotalDatabasesCount				INT;
		DECLARE @DatabaseLoopCount					INT			  = 1;
		DECLARE @Database_ID						INT;
		DECLARE @Database_Name						SYSNAME;
		DECLARE @Recovery_Model						INT;
		DECLARE @FullBackupPeriod					INT; 
		DECLARE @FullBackupIsActive					BIT;
		DECLARE @DiffBackupPeriod					INT; 
		DECLARE @DiffBackupIsActive					BIT;
		DECLARE @TransLogBackupPeriod				INT; 
		DECLARE @TransLogBackupIsActive				BIT;
		DECLARE @Datediff							INT;
		DECLARE @MaintenanceBackupSetId				INT;
		DECLARE @JobName							VARCHAR(256);
		DECLARE @JobCommand							VARCHAR(1000);
	/***************************************************************/
	
	SELECT @FullBackupPeriod = Configuration.svfn_BackupConversion_Get(Period, Interval), @FullBackupIsActive = isActive FROM [Configuration].[t_BackupManagement] (nolock) WHERE ProcessType = ''Full Backup''
	SELECT @DiffBackupPeriod = Configuration.svfn_BackupConversion_Get(Period, Interval), @DiffBackupIsActive = isActive FROM [Configuration].[t_BackupManagement] (nolock) WHERE ProcessType = ''Differential Backup''
	SELECT @TransLogBackupPeriod = Configuration.svfn_BackupConversion_Get(Period, Interval), @TransLogBackupIsActive = isActive FROM [Configuration].[t_BackupManagement] (nolock) WHERE ProcessType = ''Transaction Log''
	
	INSERT @Databases (Database_Id, Name, Recovery_Model)
	SELECT DATABASE_ID, NAME, RECOVERY_MODEL FROM MASTER.SYS.DATABASES WITH(NOLOCK) WHERE IS_READ_ONLY = 0 AND IS_IN_STANDBY = 0 AND DATABASE_ID <>2;
	SET @TotalDatabasesCount = @@ROWCOUNT;

	WHILE @DatabaseLoopCount < = @TotalDatabasesCount
			BEGIN
				-- 2a. Set preconditions
				SET @BackupType = NULL;
				SET @MaintenanceBackupSetId = NULL;
				
				SELECT @Database_ID = Database_Id, @Database_Name = Name, @Recovery_Model = Recovery_Model			
				FROM @Databases WHERE id = @DatabaseLoopCount;

				SET @BACKUPFOLDER = @backupfolderlocation ++ @database_name;
				EXECUTE MASTER.DBO.XP_CREATE_SUBDIR @BACKUPFOLDER;

				-- get the latest
				SELECT @datediff = datediff(SS, isnull(max(ProcessFinishDatetime),dateadd(Day,-1,getdate())), getdate())
				from [Collector].[t_MaintenanceBackupHistory] mbh (nolock)
						inner join [Collector].[t_MaintenanceBackupSet] mbs on mbh.[MaintenanceBackupSetId] = mbs.[MaintenanceBackupSetId]
				where [Database] = @Database_Name and ProcessFinishDatetime<>''12/31/2999'' and isJobrunning = 0

				-- 2b1. Full backups. If operation runs for first time and there are no full backups for that day then this step will execute first
				IF ( @FullBackupIsActive =''True'' AND @datediff >= @FullBackupPeriod )
					BEGIN
						SET @Operationtype =''Full Backup'';
						SET @BackupType =''D'';
						SET @Backupfile =  @backupfolder + ''\'' + @database_name + ''_Database_Full_'' + @backupfileconvention  + ''.bak'';
						SET @SQL =''BACKUP DATABASE ['' + @database_name +'']
									TO DISK = N''''''''''+ @backupfile + '''''''''' 
									WITH NOFORMAT, NOINIT, NAME = N''''''''''+ + @database_name + ''_Database_Full_'' + @backupfileconvention + '''''''''', SKIP, REWIND, NOUNLOAD, NO_COMPRESSION, CHECKSUM,  STATS = 10''			
					END;
				-- 2b2. Differential backups. Run every 4 hrs only starting at 4AM
				ELSE IF @Database_ID > 4 AND @DiffBackupIsActive = ''true'' AND @datediff >= @DiffBackupPeriod
					BEGIN
						SET @Operationtype =''Differential Backup'';
						SET @BackupType =''I'';
						SET @Backupfile =  @backupfolder + ''\'' + @database_name + ''_Database_Differential_'' + @backupfileconvention  + ''.dif'';
						SET @SQL =''BACKUP DATABASE ['' + @database_name +'']
									TO DISK = N''''''''''+ @backupfile + '''''''''' 
									WITH NOFORMAT, NOINIT, DIFFERENTIAL, NAME = N''''''''''++ @database_name + ''_Database_Differential_'' + @backupfileconvention +'''''''''', SKIP, REWIND, NOUNLOAD, NO_COMPRESSION, CHECKSUM, STATS = 10''			
					END;
				-- 2b3. Transaction Log
				ELSE IF @Database_ID > 4 AND @Recovery_Model IN (1,2) AND @TransLogBackupIsActive = ''true'' AND @datediff >= @TransLogBackupPeriod
					BEGIN
						SET @Operationtype =''Transaction Log'';
						SET @BackupType =''L'';
						SET @Backupfile =  @backupfolder + ''\'' + @database_name + ''_Transaction_Log_'' + @backupfileconvention  + ''.trn'';
						SET @SQL =''BACKUP LOG ['' + @database_name +'']
									TO DISK = N''''''''''+ @backupfile + '''''''''' 
									WITH NOFORMAT, NOINIT, NAME = N''''''''''++ @database_name + ''_Transaction_Log_'' + @backupfileconvention +'''''''''', SKIP, REWIND, NOUNLOAD, NO_COMPRESSION, CHECKSUM, STATS = 10''			
					END;	

				-- 2c. insert into Collector.usp_Maintenance_Backups_Retrieve and create dynamic job
					IF (@BackupType IS NOT NULL )
						BEGIN
							SET @JobName = FORMATMESSAGE(''DMC.Backup_%s_%s_[%s]'', @Database_Name, @Operationtype, convert(varchar,@Date_Now, 120));
							EXEC [Collector].[usp_Maintenance_Backups_Merge] @DatabaseName = @Database_Name, @JobName = @JobName, @MaintenanceBackupSetId = @MaintenanceBackupSetId OUTPUT

							SET @JobCommand = ''USE '' + QUOTENAME(@DMCDatabase) + '' 
									GO
									EXEC [Collector].[usp_Maintenance_Backups_Retrieve]
											@MaintenanceBackupSetId = '''''' + CAST(@MaintenanceBackupSetId as varchar(100)) + '''''', 
											@Backupfile = '''''' + @Backupfile + '''''', 
											@BackupType = '''''' + @BackupType + '''''',
											@Operationtype = '''''' + @Operationtype + '''''',
											@ExecutionCommand = '''''' + @SQL + '''''',
											@database_name = '''''' + @Database_Name + '''''''';

							IF EXISTS ( select job_id  FROM msdb.dbo.sysjobs WHERE name = @JobName ) begin EXEC msdb.dbo.sp_delete_job @job_name= @JobName, @delete_unused_schedule=1 end ;
							EXEC msdb..sp_add_job @job_name= @JobName, @enabled=1, @delete_level=1, @description= @JobName, @owner_login_name=N''sa'';
							EXEC msdb..sp_add_jobstep @job_name= @JobName, @step_name= @Operationtype,	@subsystem = N''TSQL'', @command= @JobCommand, @database_name=N''master'';
							EXEC msdb..sp_add_jobserver @job_name = @jobName, @server_name = @serverName;
							EXEC msdb..sp_start_job @job_name = @jobName
						END;
	

				SET @DatabaseLoopCount +=1;
				WAITFOR DELAY ''00:00:01''
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
		
		-- record error in the [Collector].[t_BackupsetOperation]
			EXEC Collector.usp_Maintenance_Backups_Merge @MaintenanceBackupSetId = @MaintenanceBackupSetId,  @isError = 1, @ErrorMessage = @ErrorMessage;
	
	-- 3. send the error message
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







