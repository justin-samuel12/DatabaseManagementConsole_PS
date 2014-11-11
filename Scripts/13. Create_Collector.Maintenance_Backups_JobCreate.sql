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
	DECLARE @ObjectName varchar(256) = 'Collector.usp_Maintenance_Backups_JobCreate';
	DECLARE @Description VARCHAR(100)='Creation of proc: '+ @ObjectName;	
	DECLARE @ReleaseDate datetime = '10/1/2013';
	DECLARE @DTNow DateTime2 = getdate();
/***************************************************************/
BEGIN TRY
	-- 1. Drop if exists
		IF OBJECT_ID(@ObjectName) IS NOT NULL BEGIN EXEC ('DROP PROC ' + @ObjectName + '') END;

	-- 1. Create table	
			SET @SQL = '
-- =============================================
-- Create date: ''' + cast(@ReleaseDate as varchar) + '''
-- Description:	SP that will create job that will execute the backup process
-- =============================================
CREATE PROCEDURE ' + @ObjectName + '
	@DatabaseName SYSNAME = ''$(Database_Name)''
AS
BEGIN TRY;
		DECLARE @JobName varchar(256) = @DatabaseName+''.Collector.Maintenance_Backups'';
		DECLARE @job_id binary(16);
		DECLARE @SQL varchar(4000)='''';

		SELECT @job_id = job_id FROM msdb.dbo.sysjobs WHERE name = '''' + @JobName + ''''
		IF ( @job_id is not null ) begin EXEC msdb.dbo.sp_delete_job @job_id = @job_id, @delete_unused_schedule=1 end ;

		SET @SQL = ''BEGIN TRANSACTION;
					DECLARE @ReturnCode INT = 0
					IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N''''Database Backup'''' AND category_class=1)
						BEGIN
							EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N''''JOB'''', @type=N''''LOCAL'''', @name=N''''Database Backup''''
							IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
						END

						DECLARE @jobId BINARY(16)
						EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name = '''''' + @JobName + '''''', 
								@enabled=1, 
								@notify_level_eventlog=0, 
								@notify_level_email=0, 
								@notify_level_netsend=0, 
								@notify_level_page=0, 
								@delete_level=0, 
								@description=N''''Backup of database. Runs every hr and will create either full/differential or trans log.'''', 
								@category_name=N''''Database Backup'''', 
								@owner_login_name=N''''sa'''', @job_id = @jobId OUTPUT

						IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
												EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N''''Execution of Maintenance Plan'''', 
								@step_id=1, 
								@cmdexec_success_code=0, 
								@on_success_action=1, 
								@on_success_step_id=0, 
								@on_fail_action=2, 
								@on_fail_step_id=0, 
								@retry_attempts=0, 
								@retry_interval=0, 
								@os_run_priority=0, 
								@subsystem=N''''TSQL'''', 
								@command=N''''use ['' + @DatabaseName +'']
						go
						exec [Collector].[usp_Maintenance_Backups_Configure]'''', 
								@database_name=N''''master'''', 
								@flags=0
						IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
						EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
						IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

						EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name = '''''' + @JobName + '''''', 
								@enabled=1, 
								@freq_type=4, 
								@freq_interval=1, 
								@freq_subday_type=8, 
								@freq_subday_interval=1, 
								@freq_relative_interval=0, 
								@freq_recurrence_factor=0, 
								@active_start_date=20131022, 
								@active_end_date=99991231, 
								@active_start_time=1500, 
								@active_end_time=235959, 
								@schedule_uid=N''''55ef72c9-902e-4aa7-9b51-0e6d3a3b42d6''''
						IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
						EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N''''(local)''''
						IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
						COMMIT TRANSACTION
						GOTO EndSave
						QuitWithRollback:
							IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
						EndSave:'';
				EXEC (@SQL);
END TRY
BEGIN CATCH
	DECLARE @ProcedureName		SYSNAME			= QUOTENAME(OBJECT_SCHEMA_NAME(@@PROCID)) +''.'' + QUOTENAME(object_name(@@PROCID))
	DECLARE @ErrorMessageFormat	VARCHAR(8000)	= ''There was an error when executing the stored procedure: %s'' + char(13) + ''Please see below for information'' + char(13) + char(13) +
													''Error Message: %s'' + char(13) + 
													''Error Severity: %i'' + char(13) + 
													''Error State: %i'' + char(13) + 
													''Error Number: %i'';
	DECLARE @ErrorMessage		VARCHAR(MAX)	= FORMATMESSAGE(@ErrorMessageFormat, @ProcedureName, ERROR_MESSAGE() , ERROR_SEVERITY() ,ERROR_STATE(), ERROR_NUMBER ());	
	RAISERROR (@ErrorMessage,16,1) WITH LOG;
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
		
		IF OBJECT_ID('Config.usp_VersionControl_Merge') IS NOT NULL EXEC Configuration.usp_VersionControl_Merge @VersionNumber = @VersionNumber, @ScriptName = '$(File_Name)', @Author = @Author, @ObjectName = @ObjectName, @Option = @Option, @Description = @Description, @ReleaseDate = @ReleaseDate, @isError = 1, @ErrorMsg = @ErrorMessage;
		RAISERROR (@ErrorMessage,16,1) WITH LOG;
END CATCH;

EXEC ('EXEC ' + @ObjectName);