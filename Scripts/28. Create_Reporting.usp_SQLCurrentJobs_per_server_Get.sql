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
	DECLARE @ObjectName varchar(256) = 'Reporting.usp_SQLCurrentJobs_per_server_Get';
	DECLARE @Description VARCHAR(100)='Creation of stored procedure: '+ @ObjectName
	DECLARE @ReleaseDate datetime = '10/31/2014';
	DECLARE @DTNow DateTime2 = getdate();
/***************************************************************/
BEGIN TRY
	-- 1. Drop if exists
		IF OBJECT_ID(@ObjectName) IS NOT NULL BEGIN EXEC ('DROP PROC ' + @ObjectName + '') END;

	-- 2. Create table	
			SET @SQL = '
-- =============================================
-- Create date: 10/31/2014
-- Description:	Get all current sql jobs per instance
-- =============================================
CREATE PROCEDURE ' + @ObjectName + '
	@servername sysname = @@servername
AS

BEGIN TRY

/********************* VARIABLES *******************************/
	DECLARE @Sql nvarchar(4000)='''';
	DECLARE @JobResults Reporting.udtt_SQLCurrentJobResults;
	DECLARE @paramdefinition nvarchar(500) =''@JobResults Reporting.udtt_SQLCurrentJobResults READONLY'';				   
/**************************************************************/

SET @Sql =''
EXEC master.dbo.xp_sqlagent_enum_jobs 1, ''''''''
	with result sets
	((
	job_id uniqueidentifier NOT NULL, 
	last_run_date int NOT NULL, 
	last_run_time int NOT NULL, 
	next_run_date int NOT NULL, 
	next_run_time int NOT NULL, 
	next_run_schedule_id int NOT NULL, 
	requested_to_run int NOT NULL, /* bool*/ 
	request_source int NOT NULL, 
	request_source_id sysname COLLATE database_default NULL, 
	running int NOT NULL, /* bool*/ 
	current_step int NOT NULL, 
	current_retry_attempt int NOT NULL, 
	job_state int NOT NULL
))
''
SET @Sql = ''SELECT a.* FROM OPENROWSET(''''SQLNCLI'''', ''''Server=''+@servername+'';Trusted_Connection=yes;'''',''''''+ replace(@Sql,'''''''','''''''''''') +'''''') AS A''

INSERT @JobResults 
EXEC (@sql);

SET @Sql = ''SELECT r.job_id, 
				job.name AS Job_Name,
				ISNULL((SELECT TOP 1 start_execution_date FROM [msdb].[dbo].[sysjobactivity] WHERE job_id = r.job_id ORDER BY start_execution_date DESC),''''1900-01-01 00:00:00.000'''' ) AS Job_Start_DateTime, 
				ISNULL(cast ((SELECT TOP 1 ISNULL(stop_execution_date, GETDATE()) - start_execution_date FROM [msdb].[dbo].[sysjobactivity] WHERE job_id = r.job_id ORDER BY start_execution_date DESC) AS time),''''00:00:00.0000000'''')AS Job_Duration, 
				r.current_step AS Current_Running_Step_ID, 
				CASE 
					WHEN r.running = 0 THEN jobinfo.last_run_outcome 
					ELSE /*convert to the uniform status numbers (my design)*/ 
						CASE 
							WHEN r.job_state = 0 THEN 1 /*success*/ 
							WHEN r.job_state = 4 THEN 1 
							WHEN r.job_state = 5 THEN 1 
							WHEN r.job_state = 1 THEN 2 /*in progress*/ 
							WHEN r.job_state = 2 THEN 2 
							WHEN r.job_state = 3 THEN 2 
							WHEN r.job_state = 7 THEN 2 
						END 
				END AS Run_Status, 
				CASE 
					WHEN r.running = 0 THEN /* sysjobservers will give last run status, but does not know about current running jobs*/ 
						CASE 
							WHEN jobInfo.last_run_outcome = 0 THEN ''''Failed'''' 
							WHEN jobInfo.last_run_outcome = 1 THEN ''''Success'''' 
							WHEN jobInfo.last_run_outcome = 3 THEN ''''Canceled'''' 
							ELSE ''''Unknown'''' 
						END /* succeeded, failed or was canceled.*/ 
					WHEN r.job_state = 0 THEN ''''Success'''' 
					WHEN r.job_state = 4 THEN ''''Success'''' 
					WHEN r.job_state = 5 THEN ''''Success'''' 
					WHEN r.job_state = 1 THEN ''''In Progress'''' 
					WHEN r.job_state = 2 THEN ''''In Progress'''' 
					WHEN r.job_state = 3 THEN ''''In Progress'''' 
					WHEN r.job_state = 7 THEN ''''In Progress'''' 
					ELSE ''''Unknown'''' 
				END AS Run_Status_Description,
				CASE	
					WHEN job.enabled = 1 THEN ''''Enabled''''
					ELSE ''''Disabled''''
				END as JobEnable
			FROM @jobResults as R
				 LEFT JOIN OPENROWSET(''''SQLNCLI'''', ''''Server=''+ @servername + '';Trusted_Connection=yes;'''',''''SELECT * FROM msdb.dbo.sysjobservers'''') AS jobInfo ON r.job_id = jobInfo.job_id
				 INNER JOIN OPENROWSET(''''SQLNCLI'''', ''''Server=''+ @servername + '';Trusted_Connection=yes;'''',''''SELECT * FROM msdb.dbo.sysjobs'''') AS job ON r.job_id = job.job_id
			ORDER BY job.enabled DESC, job.name 
				 ''
		EXEC sp_executesql @sql, @paramdefinition, @jobResults = @jobResults

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