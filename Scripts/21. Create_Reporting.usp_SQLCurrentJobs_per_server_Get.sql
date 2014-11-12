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
-- Create date: ''' + cast(@ReleaseDate as varchar) + '''
-- Description:	Get all current sql jobs per instance
-- =============================================
CREATE PROCEDURE ' + @ObjectName + '
	@servername sysname = @@servername
AS

BEGIN TRY

/********************* VARIABLES *******************************/	
	DECLARE @Sql								nvarchar(4000)='''';
	DECLARE @paramdefinition					nvarchar(500) =''@JobResults [Reporting].[udtt_SqlCurrentJobResults] READONLY'';	
	DECLARE @job_Id								uniqueidentifier = null;
	DECLARE @JobCount							INT;
	DECLARE @JobLoop							INT = 1;	
	DECLARE @Job_Name							SYSNAME;
	DECLARE @ProductVersionTable				TABLE 
												(
													ProductVersion INT
												);
	DECLARE @SQLJobsCurrentStatus table			(	
													Row_id int identity(1,1),
													Job_Id uniqueidentifier,
													Job_Name sysname,
													Job_StartDateTime datetime2,
													Job_Duration time,
													Current_Running_stepId int,
													Run_Status int,
													Run_StatusDesc varchar(100),
													JobEnabled varchar(10)
												);			   
	DECLARE @SQLJobsStepCurrentStatus table		(
													Job_Name sysname,
													Step_Name varchar(500),
													Run_Status int,
													Run_StatusDesc nvarchar(4000),
													Step_StartDateTime datetime2,
													Step_Duration time
												);			  
	DECLARE @JobResults							[Reporting].[udtt_SqlCurrentJobResults];
/**************************************************************//*
	master.dbo.xp_sqlagent_enum_jobs running description
	--------------------------------------------------------------------------------------------
	value	description													Summary
	0		Returns only those jobs that are no idle or suspended		Completed / Not Started
	1		Executing													In Progress
	2		Waiting for Thread											In Progress
	3		Between retries												Retrying
	4		Idle														Completed / Not Started
	5		Suspended													Completed / Not Started
	7		Performing Completion actions								In Progress

	msdb..sysjobs description
	--------------------------------------------------------------------------------------------
	value	description
	0		Failed
	1		Succeed
	3		Cancelled

	msdb..sysjobistory description
	--------------------------------------------------------------------------------------------
	value	description		Summary
	0		Failed			Failed											
	1		Succeed			Success / In Progress
	2		Retry			Retrying
	3		Canceled		Failed
	4		In Progress		Success / In Progress
*/
-- since there has been changes starting with SQL 2012, validate which version and added different code 
	SET @Sql = ''SELECT a.* FROM OPENROWSET(''''SQLNCLI'''', ''''Server=''+@servername+'';UID=DMAdmin;Pwd=pa$$w0rd1;'''','''' SELECT parsename(convert(varchar(100),SERVERPROPERTY(''''''''ProductVersion'''''''')),4) '''') AS A'';
	INSERT @ProductVersionTable EXEC (@sql);

-- get job information
	IF ( (select ProductVersion from @ProductVersionTable) > 10 ) -- use result set from SQL 2012
		BEGIN
			SET @Sql =''EXEC master.dbo.xp_sqlagent_enum_jobs 1, ''''''''
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
					))'';
		END
	ELSE
		BEGIN
			SET @Sql =''SET FMTONLY OFF; EXEC master.dbo.xp_sqlagent_enum_jobs 1, '''''''''';
		END;

	SET @Sql = ''SELECT a.* FROM OPENROWSET(''''SQLNCLI'''', ''''Server=''+@servername+'';UID=DMAdmin;Pwd=pa$$w0rd1;'''',''''''+ replace(@Sql,'''''''','''''''''''') +'''''') AS A'';
	INSERT @JobResults EXEC (@sql);

	SET @Sql = ''SELECT r.job_id, 
				job.name AS Job_Name,
				ISNULL((SELECT TOP 1 A1.start_execution_date FROM OPENROWSET(''''SQLNCLI'''', ''''Server=''+ @servername + '';UID=DMAdmin;Pwd=pa$$w0rd1;'''',''''SELECT * FROM msdb.dbo.sysjobactivity'''') AS A1
						WHERE A1.job_id = r.Job_ID order by A1.start_execution_date desc),''''1900-01-01 00:00:00.000'''' ) AS Job_Start_DateTime, 
				ISNULL(CAST((SELECT TOP 1 ISNULL(A1.stop_execution_date, GETDATE()) - A1.start_execution_date FROM OPENROWSET(''''SQLNCLI'''', ''''Server=''+ @servername + '';UID=DMAdmin;Pwd=pa$$w0rd1;'''',''''SELECT * FROM msdb.dbo.sysjobactivity'''') AS A1
						WHERE A1.job_id = r.Job_ID order by A1.start_execution_date desc) as time),''''00:00:00.0000000'''')AS Job_Duration, 
				r.current_step AS Current_Running_Step_ID, 
				CASE 
					WHEN r.running = 0 THEN jobinfo.last_run_outcome 
					ELSE 
						CASE 
							WHEN r.job_state = 0 THEN 1 /*success*/ 
							WHEN r.job_state = 1 THEN 2 /*in progress*/ 
							WHEN r.job_state = 2 THEN 2 
							WHEN r.job_state = 3 THEN 2
							WHEN r.job_state = 4 THEN 1 
							WHEN r.job_state = 5 THEN 1 
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
					WHEN r.job_state = 0 THEN ''''Completed / Not Started'''' 
					WHEN r.job_state = 1 THEN ''''In Progress'''' 
					WHEN r.job_state = 2 THEN ''''In Progress'''' 
					WHEN r.job_state = 3 THEN ''''Retrying'''' 
					WHEN r.job_state = 4 THEN ''''Completed / Not Started'''' 
					WHEN r.job_state = 5 THEN ''''Completed / Not Started'''' 
					WHEN r.job_state = 7 THEN ''''In Progress'''' 
					ELSE ''''Unknown'''' 
				END AS Run_Status_Description,
				CASE	
					WHEN job.enabled = 1 THEN ''''Enabled''''
					ELSE ''''Disabled''''
				END as JobEnable
			FROM @jobResults as R
				 LEFT JOIN OPENROWSET(''''SQLNCLI'''', ''''Server=''+ @servername + '';UID=DMAdmin;Pwd=pa$$w0rd1;'''',''''SELECT * FROM msdb.dbo.sysjobservers'''') AS jobInfo ON r.job_id = jobInfo.job_id
				 INNER JOIN OPENROWSET(''''SQLNCLI'''', ''''Server=''+ @servername + '';UID=DMAdmin;Pwd=pa$$w0rd1;'''',''''SELECT * FROM msdb.dbo.sysjobs'''') AS job ON r.job_id = job.job_id
			ORDER BY job.enabled DESC, job.name 
				 ''
		
			INSERT @SQLJobsCurrentStatus
			EXEC sp_executesql @sql, @paramdefinition, @jobResults = @jobResults;
			Set @JobCount = @@ROWCOUNT;

-- get Step information			
	SET @paramdefinition=''@Job_Id uniqueidentifier'';	

	WHILE ( @JobLoop <= @JobCount )
		BEGIN
			SELECT @job_Id = Job_Id, @Job_Name = Job_Name FROM @SQLJobsCurrentStatus where Row_id = @JobLoop

			SET @Sql ='' DECLARE @Job_Start_DateTime as smalldatetime;
						SELECT TOP 1 @Job_Start_DateTime = A.start_execution_date
						FROM OPENROWSET(''''SQLNCLI'''', ''''Server=''+ @servername + '';UID=DMAdmin;Pwd=pa$$w0rd1;'''',''''SELECT * FROM msdb.dbo.sysjobactivity'''') AS A
						WHERE job_id = @Job_ID order by start_execution_date desc;
	
						SELECT '''''' + @Job_Name + '''''' as Job_id, 
							  ''''Step '''' + cast(Steps.step_id as varchar) + ''''. '''' + Steps.step_name, 
							  ISNULL( run_status , 4 ), 
							  ISNULL(CASE 
										WHEN ISNULL( run_status , 0 ) IN (0,3)  THEN Message 
										ELSE ISNULL( run_status_description, ''''Success/In Progress'''' ) 
										END,''''Unknown status'''') AS run_status_description, 
							  Step_Start_DateTime,
							  Step_Duration	
						FROM( SELECT Jobstep.step_name, Jobstep.step_id FROM OPENROWSET(''''SQLNCLI'''', ''''Server=''+ @servername + '';UID=DMAdmin;Pwd=pa$$w0rd1;'''',''''SELECT * FROM msdb.dbo.sysjobsteps'''') AS Jobstep WHERE Jobstep.job_id = @Job_ID) AS Steps
						LEFT JOIN (SELECT JobHistory.step_id, 
										CASE --convert to the uniform status numbers we are using
											WHEN JobHistory.run_status = 0 THEN 0
											WHEN JobHistory.run_status = 1 THEN 1
											WHEN JobHistory.run_status = 2 THEN 2
											WHEN JobHistory.run_status = 3 THEN 3
											WHEN JobHistory.run_status = 4 THEN 2
											ELSE 4
										END AS run_status, 
										CASE 
											WHEN JobHistory.run_status = 0 THEN ''''Failed'''' 
											WHEN JobHistory.run_status = 1 THEN ''''Success'''' 
											WHEN JobHistory.run_status = 2 THEN ''''In Progress''''
											WHEN JobHistory.run_status = 3 THEN ''''Canceled''''
											WHEN JobHistory.run_status = 4 THEN ''''In Progress'''' 
											ELSE ''''Unknown'''' 
										END AS run_status_description,
										JobHistory.Message,
										CAST(STR(run_date) AS DATETIME) + cast(CAST(STUFF(STUFF(REPLACE(STR(run_time, 6, 0), '''' '''', ''''0''''), 3, 0, '''':''''), 6, 0, '''':'''') AS TIME)as datetime) as Step_Start_DateTime,
										CAST(CAST(STUFF(STUFF(REPLACE(STR(JobHistory.run_duration % 240000, 6, 0), '''' '''', ''''0''''), 3, 0, '''':''''), 6, 0, '''':'''') AS DATETIME) AS TIME)  AS Step_Duration
						FROM OPENROWSET(''''SQLNCLI'''', ''''Server='' + @servername + '';UID=DMAdmin;Pwd=pa$$w0rd1;'''',''''SELECT * from msdb.dbo.sysjobhistory WITH (NOLOCK)'''') as JobHistory 
						WHERE job_id = @Job_ID and 
								CAST(STR(run_date) AS DATETIME) + cast(CAST(STUFF(STUFF(REPLACE(STR(run_time, 6, 0), '''' '''', ''''0''''), 3, 0, '''':''''), 6, 0, '''':'''') AS TIME) as datetime) >= @Job_Start_DateTime) AS StepStatus ON Steps.step_id = StepStatus.step_id
						ORDER BY Steps.step_id;''

						INSERT @SQLJobsStepCurrentStatus 
						EXEC sp_executesql @sql, @paramdefinition, @Job_Id = @Job_Id;
						

			SET @JobLoop +=1;
		END

-- show all info
			SELECT Job_Name, NULL Step_Name, Current_Running_stepId, Run_Status,Run_StatusDesc, Job_StartDateTime, Job_Duration, JobEnabled,''Job-Level'' as Step
			FROM @SQLJobsCurrentStatus
			UNION
			SELECT Job_Name, Step_Name, NULL, Run_Status,Run_StatusDesc, Step_StartDateTime ,Step_Duration, NULL,''Step-Level'' as Step
			FROM @SQLJobsStepCurrentStatus
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