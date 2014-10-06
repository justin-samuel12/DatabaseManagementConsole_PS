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
	DECLARE @ObjectName varchar(256) = 'Reporting.usp_SQLServiceStoppedStatus_Get';
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
-- Author: Justin Samuel
-- Create date: 09/25/2014
-- Description: Get all sql stopped services
-- =============================================
CREATE PROCEDURE ' + @ObjectName + '
AS
BEGIN TRY;
/********************* VARIABLES *******************************/
	DECLARE @DTNow DateTime2 = getdate();
	DECLARE @SQLTable TABLE (Status varchar(256), Service varchar(256), DisplayName varchar(256))
	DECLARE @xml NVARCHAR(MAX);
	DECLARE @body NVARCHAR(MAX)='''';
	DECLARE @subject VARCHAR(256) = ''SQL Service Stopped for: '' + @@SERVERNAME;
	DECLARE @receipants varchar(max);
/***************************************************************/
	SET NOCOUNT ON;
		-- drop if exists then create
		if object_id(''tempdb..#statusTable'') is not null begin drop table #statustable end;
		create table #statusTable (rowId int primary key identity(1,1), value varchar(4000));

	-- insert into temp table	
		declare @getstatusCmd varchar(256) = ''"Get-Service -name *sql* | Format-Table -AutoSize -Property Name, Status, Displayname"'';
		set @getstatusCmd = ''powershell.exe -noprofile -command '' + @getstatusCmd

		INSERT #STATUSTABLE
		EXEC XP_CMDSHELL @GETSTATUSCMD; 

		;with _cte as
		(
		SELECT [Status],
			   Name, 
			   ServiceName
		FROM #statusTable 
			CROSS APPLY (SELECT SUBSTRING(LTRIM(RTRIM(value)),1, CHARINDEX('' '',LTRIM(RTRIM(value))) -1) Name) A 
			CROSS APPLY (SELECT SUBSTRING(LTRIM(RTRIM(REPLACE(value, A.Name, ''''))),1, CHARINDEX('' '',LTRIM(RTRIM(REPLACE(value, A.Name,'''')))) -1) as [Status]) B
			CROSS APPLY (SELECT LTRIM(RTRIM(REPLACE(REPLACE(value, B.[Status], ''''),A.Name,''''))) as ServiceName) C 
		where value is not null and rowId >3
		)

		INSERT @SQLTable
		SELECT * FROM _CTE WHERE [STATUS] <>''RUNNING'' AND ( NAME LIKE ''SQLAGENT%'' OR NAME LIKE ''MSSQL%'' )

		IF @@ROWCOUNT > 0
		begin
		
			EXEC [Configuration].[usp_AlertEmail_Get] @receipants OUTPUT; -- get email
		
			SET @xml = CAST(( SELECT Status AS ''td'','''', 
									 Service AS ''td'','''', 
									 DisplayName  AS ''td''
			FROM  @SQLTable 
			ORDER BY Service 
			FOR XML PATH(''tr''), ELEMENTS ) AS NVARCHAR(MAX));


			SET @body =''<html>Please see below for SQL services that are not running executed on: '' + cast( @DTNow as varchar )+ ''</br></br>
						<table border = 1> 
						<tr valign=top>
						<th> Status </th> 
						<th> Service </th>
						<th> DisplayName </th>
						</tr>'';    

			SET @body = @body + REPLACE(@xml,''<tr>'',''<tr valign=top>'') +''</table></body></html>'';
			EXEC [Configuration].[usp_EmailNotification] ''Database'',@Subject, @body, @receipants;

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
