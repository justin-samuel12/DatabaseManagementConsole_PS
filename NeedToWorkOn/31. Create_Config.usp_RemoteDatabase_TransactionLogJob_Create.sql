SET ANSI_NULLS, ANSI_PADDING, ANSI_WARNINGS, ARITHABORT, CONCAT_NULL_YIELDS_NULL, QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO
USE [$(Database_Name)]
GO
IF OBJECT_ID(N'Config.usp_RemoteDatabase_TransactionLogJob_Create')  IS NOT NULL
BEGIN
	DROP PROCEDURE Config.usp_RemoteDatabase_TransactionLogJob_Create;
END
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author: Justin Samuel
-- Create date: 2/22/2014
-- Description:	Configure Maintenance job (Transaction Log)
-- =============================================
CREATE PROCEDURE Config.usp_RemoteDatabase_TransactionLogJob_Create
AS
BEGIN TRY;
	SET NOCOUNT ON;
	
		--1. Drop if exists
			DECLARE @job_id binary(16);
			SELECT @job_id = job_id FROM msdb.dbo.sysjobs WHERE name = 'DatabaseManagementTool.Maintenance_TransactionLog'
			IF ( @job_id is not null ) begin EXEC msdb.dbo.sp_delete_job @job_id = @job_id, @delete_unused_schedule=1 end ;

			BEGIN TRANSACTION
			DECLARE @ReturnCode INT
			SELECT @ReturnCode = 0
			/****** Object:  JobCategory [Database Maintenance]    Script Date: 3/16/2014 12:32:45 PM ******/
			IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Database Maintenance' AND category_class=1)
			BEGIN
			EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
			IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

			END

			DECLARE @jobId BINARY(16)
			EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DatabaseManagementTool.Maintenance_TransactionLog', 
					@enabled=1, 
					@notify_level_eventlog=0, 
					@notify_level_email=0, 
					@notify_level_netsend=0, 
					@notify_level_page=0, 
					@delete_level=0, 
					@description=N'Logs of all databases except system db''s and for Full or Bulk Log recovery state', 
					@category_name=N'Database Maintenance', 
					@owner_login_name=N'sa', @job_id = @jobId OUTPUT
			IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
			/****** Object:  Step [Transaction Logs]    Script Date: 3/16/2014 12:32:45 PM ******/
			EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Transaction Logs', 
					@step_id=1, 
					@cmdexec_success_code=0, 
					@on_success_action=3, 
					@on_success_step_id=0, 
					@on_fail_action=2, 
					@on_fail_step_id=0, 
					@retry_attempts=0, 
					@retry_interval=0, 
					@os_run_priority=0, @subsystem=N'TSQL', 
					@command=N'use [DatabaseManagementTool]
			go
			exec [Maintenance].[usp_Maintenance_TransactionLog]', 
					@database_name=N'master', 
					@flags=0
			IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
			/****** Object:  Step [Create Restore Scripts]    Script Date: 3/16/2014 12:32:45 PM ******/
			EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Create Restore Scripts', 
					@step_id=2, 
					@cmdexec_success_code=0, 
					@on_success_action=1, 
					@on_success_step_id=0, 
					@on_fail_action=2, 
					@on_fail_step_id=0, 
					@retry_attempts=0, 
					@retry_interval=0, 
					@os_run_priority=0, @subsystem=N'TSQL', 
					@command=N'use [DatabaseManagementTool]
			go
			exec [Maintenance].[usp_Maintenance_CreateRestoreScripts]', 
					@database_name=N'master', 
					@flags=0
			IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
			EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
			IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
			EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Maintenance_TransactionLog', 
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
					@schedule_uid=N'55ef72c9-902e-4aa7-9b51-0e6d3a3b42d6'
			IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
			EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
			IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
			COMMIT TRANSACTION
			GOTO EndSave
			QuitWithRollback:
				IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
			EndSave:
							

END TRY	
BEGIN CATCH
		DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
		DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
		DECLARE @ErrorState INT = ERROR_STATE();
	
		DECLARE @ERROR_MSG NVARCHAR(MAX)='';
		SELECT @ERROR_MSG = 'Error Message: ' + @ErrorMessage + char(13) + 'Error Severity: ' + convert(varchar,@ErrorSeverity)  + char(13) + 'Error State: ' + convert(varchar,@ErrorState)  + char(13) + 'Error Number: ' + convert(varchar,ERROR_NUMBER());
	
		RAISERROR (@ERROR_MSG,16,1) WITH LOG;
		
END CATCH;