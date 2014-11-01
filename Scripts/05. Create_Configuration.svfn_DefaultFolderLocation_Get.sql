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
	DECLARE @ObjectName varchar(256) = 'Configuration.svfn_DefaultFolderLocation_Get';
	DECLARE @Description VARCHAR(100)='Creation of function: '+ @ObjectName
	DECLARE @ReleaseDate datetime = '10/1/2013';
	DECLARE @DTNow DateTime2 = getdate();
/***************************************************************/
BEGIN TRY
	-- 1. Drop if exists
		IF OBJECT_ID(@ObjectName) IS NOT NULL BEGIN EXEC ('DROP FUNCTION ' + @ObjectName + '') END;

	-- 2. Create table	
			SET @SQL = '
-- =============================================
-- Create date: 3/23/2013
-- Description:	Backup SQL Default file location function
-- =============================================
CREATE FUNCTION ' + @ObjectName + '
( 
	@Type varchar(100) --BackupDirectory/ DefaultData / DefaultLog 
)
RETURNS VARCHAR(100)
AS
BEGIN
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
     
			-- get the default location per type value
			EXEC master..xp_regread 
				@rootkey=''HKEY_LOCAL_MACHINE'',
				@key=@RegKey,
				@value_name=@type,
				@value = @value OUTPUT

			-- final validation
			IF (( right(ltrim(rtrim(@Value)),1) ) <>''\'' ) set @Value += ''\'';			
		END

		RETURN @Value;
END
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
		
		IF OBJECT_ID('Configuration.usp_VersionControl_Merge') IS NOT NULL EXEC Configuration.usp_VersionControl_Merge @VersionNumber = @VersionNumber, @ScriptName = '$(File_Name)', @Author = @Author, @ObjectName = @ObjectName, @Option = @Option, @Description = @Description, @ReleaseDate = @ReleaseDate, @isError = 1, @ErrorMsg = @ErrorMessage;
		RAISERROR (@ErrorMessage,16,1) WITH LOG;
END CATCH;
GO
