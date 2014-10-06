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
	DECLARE @ObjectName varchar(256) = 'Collector.usp_BlockedEvents_Insert';
	DECLARE @Description VARCHAR(100)='Creation of stored procedure: '+ @ObjectName
	DECLARE @ReleaseDate datetime = '10/1/2013';
	DECLARE @DTNow DateTime2 = getdate();
/***************************************************************/
BEGIN TRY
	-- 1. Drop if exists
		IF OBJECT_ID(@ObjectName) IS NOT NULL BEGIN EXEC ('DROP PROC ' + @ObjectName + '') END;

	-- 2. Create table	
			SET @SQL = '
-- =============================================
-- Author:	Justin Samuel
-- Create date: 11/29/2013
-- Description:	Insert into Monitor.t_BlockedEvents 
-- =============================================
CREATE PROCEDURE ' + @ObjectName + '
	@Blockingxml XML
AS
BEGIN TRY;
	/*************************** VARIABLES **********************************/
	DECLARE @MessageSubject VARCHAR(100)  = ''Alert! Blocking On '' + @@servername + ''\'' + @@servicename;
	DECLARE @MessageBody VARCHAR(max)='''';
	DECLARE @recipients varchar(max)='''';
	DECLARE @Id INT;

	CREATE TABLE #BlockingDetails ( Nature VARCHAR(100),waittime VARCHAR(100), transactionname VARCHAR(100), lockMode VARCHAR(100), 
				[status] VARCHAR(100), clientapp VARCHAR(100), hostname VARCHAR(100), loginname VARCHAR(100), 
				currentdb VARCHAR(100), inputbuf VARCHAR(1000) )
	/*************************************************************************/
	--Blocked process details
		INSERT INTO #BlockingDetails
		SELECT 
			Nature			= ''Blocked'',
			waittime		= isnull(d.c.value(''@waittime'',''varchar(100)''),''''),
			transactionname = isnull(d.c.value(''@transactionname'',''varchar(100)''),''''),
			lockMode		= isnull(d.c.value(''@lockMode'',''varchar(100)''),''''),
			status			= isnull(d.c.value(''@status'',''varchar(100)''),''''),
			clientapp		= isnull(d.c.value(''@clientapp'',''varchar(100)''),''''),
			hostname		= isnull(d.c.value(''@hostname'',''varchar(100)''),''''),
			loginname		= isnull(d.c.value(''@loginname'',''varchar(100)''),''''),
			currentdb		= isnull(db_name(d.c.value(''@currentdb'',''varchar(100)'')),''''),
			inputbuf		= isnull(d.c.value(''inputbuf[1]'',''varchar(1000)''),'''')
		FROM @blockingxml.nodes(''TextData/blocked-process-report/blocked-process/process'') d(c)


	--Blocking process details
		INSERT INTO #BlockingDetails
		SELECT 
			Nature			= ''BlockedBy'',
			waittime		= '''',
			transactionname = '''',
			lockMode		= '''',
			status			= isnull(d.c.value(''@status'',''varchar(100)''),''''),
			clientapp		= isnull(d.c.value(''@clientapp'',''varchar(100)''),''''),
			hostname		= isnull(d.c.value(''@hostname'',''varchar(100)''),''''),
			loginname		= isnull(d.c.value(''@loginname'',''varchar(100)''),''''),
			currentdb		= isnull(db_name(d.c.value(''@currentdb'',''varchar(100)'')),''''),
			inputbuf		= isnull(d.c.value(''inputbuf[1]'',''varchar(1000)''),'''')
		FROM @blockingxml.nodes(''TextData/blocked-process-report/blocking-process/process'') d(c)

		EXEC [Configuration].[usp_AlertEmail_Get] @recipients OUTPUT; -- get email

		SELECT @MessageBody =
		(
			SELECT td = 
			currentdb + ''</td><td>''  +  Nature + ''</td><td>'' + waittime + ''</td><td>'' + transactionname + ''</td><td>'' + 
			lockMode + ''</td><td>'' + status + ''</td><td>'' + clientapp +  ''</td><td>'' + 
			hostname + ''</td><td>'' + loginname + ''</td><td>'' +  inputbuf
			FROM #BlockingDetails
			FOR XML PATH( ''tr'' )     
		)  

		SELECT @MessageBody = ''<table cellpadding="2" cellspacing="2" border="1">''    
					  + ''<tr><th>currentdb</th><th>Nature</th><th>waittime</th><th>transactionname</th></th></th><th>lockMode</th></th>
					  </th><th>status</th></th></th><th>clientapp</th></th></th><th>hostname</th></th>
					  </th><th>loginname</th><th>inputbuf</th></tr>''    
					  + replace( replace( @MessageBody, ''&lt;'', ''<'' ), ''&gt;'', ''>'' )     
					  + ''</table>''  +  ''<table cellpadding="2" cellspacing="2" border="1"><tr><th>XMLData</th></tr><tr><td>'' + replace( replace( convert(varchar(max),@blockingxml),  ''<'',''&lt;'' ),  ''>'',''&gt;'' )  
					  + ''</td></tr></table>''

		DROP TABLE #BlockingDetails

	--Sending Mail
		EXEC [Configuration].[usp_EmailNotification] @subject = @MessageSubject, @body = @MessageBody, @recipients = @recipients;
			
	--Inserting into a table for further reference
		INSERT INTO [Collector].[t_BlockedEvents] (BlockedReport, AlertDateTime)
		VALUES (@Blockingxml,getdate())

		SET @Id = SCOPE_IDENTITY();

	--Updating the SPID column
		UPDATE B
		SET B.SPID = B.BlockedReport.value(''(/TextData/blocked-process-report/blocking-process/process/@spid)[1]'',''int'')
		FROM [Collector].[t_BlockedEvents] B 
		where  B.BlockedEventsId = @Id;

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