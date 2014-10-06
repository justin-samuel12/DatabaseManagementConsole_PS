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
	DECLARE @ObjectName varchar(256) = 'Configuration.usp_DefaultFolderLocation_Reconfigure';
	DECLARE @Description VARCHAR(100)='Creation of stored proc: '+ @ObjectName
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
-- Create date: 10/02/2014
-- Description:	Reconfigure Default Location for server
-- =============================================
CREATE PROCEDURE ' + @ObjectName + '
	@Type varchar(100), --BackupDirectory/ DefaultData / DefaultLog
	@NewFolderPath varchar(500),
	@Status varchar(100) OUTPUT
AS
BEGIN TRY;
	SET NOCOUNT ON;

	DECLARE @InstanceName nvarchar(50)= CONVERT(NVARCHAR,isnull(SERVERPROPERTY(''INSTANCENAME''), ''MSSQLSERVER''));
	DECLARE @RegKey_Value VARCHAR(100)
	DECLARE @RegKey_InstanceName nvarchar(500)
	DECLARE @RegKey nvarchar(500)
	DECLARE @Value VARCHAR(100)

	IF ( SELECT Convert(varchar(1),(SERVERPROPERTY(''ProductVersion''))) ) <> 8
	BEGIN
		-- first get the named instance
		SET @RegKey_InstanceName=''SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL''
 
		-- then get the registry key
		EXECUTE xp_regread @rootkey = ''HKEY_LOCAL_MACHINE'', @key = @RegKey_InstanceName, @value_name = @InstanceName, @value = @RegKey_Value OUTPUT
		SET @RegKey=''SOFTWARE\Microsoft\Microsoft SQL Server\''+ @RegKey_Value +''\MSSQLServer\''
     
		EXEC MASTER..XP_REGWRITE 
			@rootkey=	   ''HKEY_LOCAL_MACHINE'',
			@key=		   @RegKey,
			@value_name=   @type,
			@type=		   ''REG_SZ'', 
			@value=		   @NewFolderPath

		SET @Status = ''Server : '' + @@SERVERNAME + '' backuplocation has been changed to: '' + @NewFolderPath ;

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
	RAISERROR (@ErrorMessage,16,1);		
END CATCH;
';
	 
		EXEC (@SQL)
	 
	 -- 3. insert into [Configuration].[t_VersionControl]
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
		IF OBJECT_ID('Configuration.usp_VersionControl_Merge') IS NOT NULL EXEC Configuration.usp_VersionControl_Merge @VersionNumber = @VersionNumber, @ScriptName = '$(File_Name)', @Author = @Author, @ObjectName = @ObjectName, @Option = @Option, @Description = @Description, @ReleaseDate = @ReleaseDate, @isError = 1, @ErrorMsg = @ErrorMessage ;
		RAISERROR (@ErrorMessage,16,1);
END CATCH;

BEGIN TRY
	DECLARE @ExecutionString nvarchar(500) ='EXEC Configuration.usp_DefaultFolderLocation_Reconfigure @Type ,@NewFolderPath, @Status OUTPUT';
	DECLARE @ExecutionParamDefinition nvarchar(500) ='@Type varchar(100), @NewFolderPath varchar(500), @Status varchar(100) OUTPUT';
	DECLARE @ParamIn1 varchar(100) = 'BackupDirectory';
	DECLARE @ParamIn2 varchar(500) = (select [BackupLocation] from [Configuration].[t_ServerInstance] (nolock) where servername + '\' + [InstanceName] = @@SERVERNAME);
	DECLARE @ParamOut1 varchar(100);
	
	EXECUTE sp_executesql @ExecutionString,@ExecutionParamDefinition,
								@Type = @ParamIn1,
								@NewFolderPath = @ParamIn2,
								@Status = @ParamOut1 OUTPUT;

	PRINT @ParamOut1;
	
END TRY
BEGIN CATCH
		SET @ProcedureName				=  '$(File_Name)';
		SET @ErrorMessageFormat	     	= 'There was an error when executing the step: %s|' +
														'Error Message: %s|' + 
														'Error Severity: %i|' + 
														'Error State: %i|' + 
														'Error Number: %i';
		SET @ErrorMessage	        	= FORMATMESSAGE(REPLACE(@ErrorMessageFormat,char(13),'`r`n'), @ProcedureName, ERROR_MESSAGE() , ERROR_SEVERITY() ,ERROR_STATE(), ERROR_NUMBER ());	
		IF OBJECT_ID('Configuration.usp_VersionControl_Merge') IS NOT NULL EXEC Configuration.usp_VersionControl_Merge @VersionNumber = @VersionNumber, @ScriptName = '$(File_Name)', @Author = @Author, @ObjectName = @ObjectName, @Option = @Option, @Description = @Description, @ReleaseDate = @ReleaseDate, @isError = 1, @ErrorMsg = @ErrorMessage;
		RAISERROR (@ErrorMessage,16,1);
END CATCH;
