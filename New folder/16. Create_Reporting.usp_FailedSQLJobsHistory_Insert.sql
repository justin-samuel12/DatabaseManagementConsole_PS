SET ANSI_NULLS, ANSI_PADDING, ANSI_WARNINGS, ARITHABORT, CONCAT_NULL_YIELDS_NULL, QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;

GO
USE [$(Database_Name)]
GO
/********************* VARIABLES *******************************/
	DECLARE @CreateDate DateTime2 = getdate();
	DECLARE @SQL VARCHAR(MAX) ='';

	DECLARE @VersionNumber numeric(3,2) ='1.0';
	DECLARE @Option varchar(256)= 'New';
	DECLARE @Author varchar(256)= 'justin_samuel';
	DECLARE @ObjectName varchar(256) = 'Reporting.usp_FailedSQLJobsHistory_Insert';
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
-- Create date: 5/8/2013
-- Description: Insert into [Reports].[t_FailedSQLJobsHistory]
-- =============================================
CREATE PROCEDURE ' + @ObjectName + '
AS
BEGIN TRY;
/********************* VARIABLES *******************************/
	DECLARE @DTNow DateTime2 = getdate();
	DECLARE @SQLTable TABLE (Instanceid int,JobId uniqueidentifier,JobName sysname,StepName sysname, RunStatus varchar(11),
							 SqlMessageId int,SqlSeverity int,Message nvarchar(4000),ExecutionDatetime datetime2,
							  RunDuration int, Server sysname ,CreateDatetime datetime2)
	DECLARE @xml NVARCHAR(MAX);
	DECLARE @body NVARCHAR(MAX)='''';
	DECLARE @subject VARCHAR(256) = ''SQL Failed Jobs for: '' + @@SERVERNAME;
	DECLARE @receipants varchar(max);
/***************************************************************/
	SET NOCOUNT ON;
	
	-- insert into table variable
	insert @SQLTable
	SELECT instance_id, job_id, Job_Name, Step_name, Run_status, Sql_message_id, Sql_severity, [message], exec_date, run_duration, [server],@DTNow
	FROM [Collector].[v_FailedSQLJobs] with(nolock)
	WHERE instance_id NOT IN ( SELECT instanceid FROM [Reporting].[t_FailedSQLJobsHistory] WHERE [Server] = @@SERVERNAME )			

	IF @@ROWCOUNT > 0
		begin
		
			EXEC [Configuration].[usp_AlertEmail_Get] @receipants OUTPUT; -- get email
		
			SET @xml = CAST(( SELECT JobName AS ''td'','''', 
									 StepName AS ''td'','''', 
									 SqlMessageId AS ''td'','''', 
									 SqlSeverity AS ''td'','''', 
									 [message] AS ''td'','''', 
									 ExecutionDatetime AS ''td'','''', 
									 RunDuration  AS ''td''
			FROM  @SQLTable ORDER BY Instanceid 
			FOR XML PATH(''tr''), ELEMENTS ) AS NVARCHAR(MAX));


			SET @body =''<html>Please see below for failed SQL Jobs executed on: '' + cast( @DTNow as varchar )+ ''</br></br>
						<table border = 1> 
						<tr valign=top>
						<th> Job Name </th> 
						<th> Step Name </th>
						<th> SQL Message Id </th>
						<th> SQL Severity </th>
						<th> Message </th>
						<th> Execution Datetime </th>
						<th> Run Duration </th>
						</tr>'';    

			SET @body = @body + REPLACE(@xml,''<tr>'',''<tr valign=top>'') +''</table></body></html>'';
			EXEC [Configuration].[usp_EmailNotification] ''Database'',@Subject, @body, @receipants;

			-- finally insert into Reports.t_FailedSQLJobsHistory
			INSERT INTO Reports.t_FailedSQLJobsHistory
			SELECT * FROM @SQLTable
		end

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
		
		IF OBJECT_ID('Config.usp_VersionControl_Merge') IS NOT NULL EXEC Configuration.usp_VersionControl_Merge @VersionNumber = @VersionNumber, @ScriptName = '$(File_Name)', @Author = @Author, @ObjectName = @ObjectName, @Option = @Option, @Description = @Description, @ReleaseDate = @ReleaseDate, @isError = 1, @ErrorMsg = @ErrorMessage;
		RAISERROR (@ErrorMessage,16,1) WITH LOG;
END CATCH;
GO

