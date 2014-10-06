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
	DECLARE @ObjectName varchar(256) = '$(Database_Name).Collector.BlockedEvents';
	DECLARE @Description VARCHAR(100)='Creation of job: ' + @ObjectName;
	DECLARE @ReleaseDate datetime = '10/1/2013';
	DECLARE @DTNow DateTime2 = getdate();
/***************************************************************/
BEGIN TRY
	-- 1. Allow SQL Agent to replace WMI tokens:
	EXEC msdb.dbo.sp_set_sqlagent_properties @alert_replace_runtime_tokens=1

	-- 2. Drop if exists
		DECLARE @job_id binary(16);
		SELECT @job_id = job_id FROM msdb.dbo.sysjobs WHERE name = @ObjectName
		IF ( @job_id is not null ) begin EXEC msdb.dbo.sp_delete_job @job_id = @job_id, @delete_unused_schedule=1 end ;

	-- 3. Create table	
			SET @SQL = '
BEGIN TRANSACTION;
	DECLARE @ReturnCode INT = 0
	IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N''Database Reporting'' AND category_class=1)
		BEGIN
			EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N''JOB'', @type=N''LOCAL'', @name=N''Database Reporting''
			IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
		END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'''+ @ObjectName +''', 
			@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N''Job for responding to BLOCKED_PROCESS_REPORT events'', 
		@category_name=N''Database Monitoring'', 
		@owner_login_name=N''sa'', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Delete Files]    Script Date: 10/22/2013 4:40:56 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N''Insert graph into LogEvents'', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N''TSQL'', 
		@command=N''SET QUOTED_IDENTIFIER ON;
DECLARE @Blockingxml XML = N''''$(ESCAPE_SQUOTE(WMI(TextData)))'''';
EXEC [$(Database_Name)].[Collector].[usp_BlockedEvents_Insert] @BlockingXML
'', 
		@database_name=N''master'', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N''(local)''
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

DECLARE @sysalert sysname = ''Respond to BLOCKED_PROCESS_REPORT'';
DECLARE @server_namespace varchar(255) =  N''\\.\root\Microsoft\SqlServer\ServerEvents\MSSQLSERVER'';

IF ISNULL(CHARINDEX(''\'',@@SERVERNAME), 0)> 0
	BEGIN
		SET @server_namespace = N''\\.\root\Microsoft\SqlServer\ServerEvents\''+SUBSTRING(@@SERVERNAME,ISNULL(CHARINDEX(''\'',@@SERVERNAME), 0)+ 1,LEN(@@SERVERNAME)-ISNULL(CHARINDEX(''/'',@@SERVERNAME), 0))
	END;
		
if ( select 1 from msdb..sysalerts where name = @sysalert) is not null
	begin EXEC msdb.dbo.sp_delete_alert @name= @sysalert end;

EXEC msdb.dbo.sp_add_alert @name = @sysalert, 
	@wmi_namespace= @server_namespace, 
    @wmi_query=N''SELECT * FROM BLOCKED_PROCESS_REPORT'', 
    @job_name='''+ @ObjectName +''';
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
