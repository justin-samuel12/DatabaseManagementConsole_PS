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
	DECLARE @ObjectName varchar(256) = 'Collector.usp_Backupset_Insert';
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
-- Author: Justin Samuel
-- Create date: 3/1/2013
-- Description:	Insert from MSDB..Backupset onto Collector.t_Backupset
-- =============================================
CREATE PROCEDURE ' + @ObjectName + '
	@BackupSetId INT, -- Id for MSDB..Backupset
	@FileName varchar(256),  -- Name of the file
	@CreateDate datetime2 = NULL
AS
BEGIN TRY;
	SET NOCOUNT ON;
	/******************************** VARIABLES ********************************/
		DECLARE @SQL varchar(max)='''';
		DECLARE @databasename sysname;
		DECLARE @fileTable table (Id INT Identity(1,1),files varchar(2000) );
		DECLARE @whileloop int = 1;
	/**************************************************************************/
		SET @databasename = ( select DATABASE_NAME FROM MSDB..BACKUPSET WHERE BACKUP_SET_ID = @BACKUPSETID  );
		SET @SQL +=''USE '' + quotename(@databasename) +''; select ''''Move '''''''''''' + name + '''''''''''' To ''''''''''''  + filename + '''''''''''',''''
						from sysfiles''
		INSERT @fileTable EXEC ( @SQL);
		SET @SQL = '''';

	-- 1. validations
		if ( @CreateDate IS NULL )  BEGIN SET @CreateDate = GETDATE() END;
				
	-- 2. now loop and put the value in a variable
		WHILE @whileloop <= ( SELECT count(1) FROM @fileTable )
			BEGIN
				SET @SQL += ( SELECT files FROM @fileTable WHERE Id = @whileloop) + char(13);
				SET @whileloop +=1;
			END

	-- 3. insert into table
		INSERT INTO Collector.t_Backupset 
					( name,  firstlsn, lastlsn, backupstartdate, backupfinishdate, sizeinkb, type, [database], filename, 
						recoverymodel, isdamaged, restorationscripts, machinenamewherefileresides, createdatetime )
		SELECT 
			NAME, 
			FIRST_LSN, 
			LAST_LSN, 
			BACKUP_START_DATE, 
			BACKUP_FINISH_DATE, 
			(BACKUP_SIZE + 1536) / 1024, 
			CASE WHEN TYPE =''D'' THEN ''Full Backup'' WHEN TYPE =''I'' THEN ''Differential''  WHEN TYPE =''L'' THEN ''Transactional Log'' ELSE ''Other'' END,  
			DATABASE_NAME, 
			@FILENAME, 
			RECOVERY_MODEL, 
			IS_DAMAGED, 
			CASE WHEN TYPE =''L'' then ''RESTORE LOG ['' + database_name +'']''++ char(10) ++''FROM DISK = N''''''+ @FileName  +''''''''  ++ char(10) ++  ''WITH '' + @SQL + '' NOUNLOAD, NORECOVERY, REPLACE''
				 ELSE ''RESTORE DATABASE ['' + database_name +'']''++ char(10) ++''FROM DISK = N''''''+ @FileName  +''''''''  ++ char(10) ++  ''WITH '' + @SQL + '' NOUNLOAD, NORECOVERY, REPLACE''
			END + CHAR(13)+ CHAR(13),		   
			SERVER_NAME, 
			@CreateDate
		FROM MSDB..BACKUPSET
		WHERE BACKUP_SET_ID = @BACKUPSETID  
		
		   
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

