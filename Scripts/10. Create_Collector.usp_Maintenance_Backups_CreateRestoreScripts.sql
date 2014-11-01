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
	DECLARE @ObjectName varchar(256) = 'Collector.usp_Maintenance_Backups_CreateRestoreScripts';
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
-- Create date: 3/1/2013
-- Description:	Create restore scripts   
-- =============================================
CREATE PROCEDURE ' + @ObjectName + '
AS
/********************* VARIABLES *******************************/
	DECLARE @DATABASENAME SYSNAME; -- database name
	DECLARE @BACKUPFOLDERLOCATION VARCHAR(100)= [Configuration].[svfn_DefaultFolderLocation_Get](''BackupDirectory'') ; -- backupfolder local
	DECLARE @BACKUPFOLDERNAME VARCHAR(200); -- backupfolder + database name
	DECLARE @RESTORESCRIPTCONVENTION VARCHAR(500) = ''_RESTORE_FILE_'' + CONVERT(VARCHAR, GETDATE(),112);
	DECLARE @RESTORESCRIPTFILENAME VARCHAR(200); -- name of the restore file 
	DECLARE @EXTENTION VARCHAR(3) = ''SQL''; -- extention
	
	DECLARE @HEADERTEXT VARCHAR(500);
	DECLARE @FOOTERTEXT VARCHAR(500);

	DECLARE @FULLBACKUPSETID INT;
	DECLARE @DIFFERENTIALBACKUPSETID INT;

	DECLARE @SQL NVARCHAR(4000);
	
	DECLARE @FS INT
	DECLARE @OLERESULT INT
	DECLARE @FILEID INT
/***************************************************************/
BEGIN TRY;
	SET NOCOUNT ON;
		-- 1. Declare cursor. Make sure that only online databases are shown
			DECLARE DBCURSOR CURSOR FAST_FORWARD FOR 			
				SELECT NAME FROM MASTER.SYS.DATABASES WHERE IS_READ_ONLY = 0 AND IS_IN_STANDBY = 0 AND DATABASE_ID <> 2;

		-- 2. Open cursor	
			OPEN DBCURSOR
	
		-- 3. Fetch
			FETCH NEXT FROM DBCURSOR INTO @DATABASENAME
	
		-- 4. loop
			WHILE @@FETCH_STATUS = 0
				BEGIN
					--set backup foldername to backup folder local + database name	
					SET @BACKUPFOLDERNAME=  @BACKUPFOLDERLOCATION ++ @DATABASENAME;
					SET @RESTORESCRIPTFILENAME =  @BACKUPFOLDERNAME + ''\'' + @DATABASENAME + @RESTORESCRIPTCONVENTION  + ''.'' + @EXTENTION;
			
					-- Create restore scripts	
					-- Set the variable to nothing
					SET @SQL = '''' 
				
					-- Get the latest full backupset
					SET @FULLBACKUPSETID = ( SELECT MAX(BACKUPSETID) FROM [Collector].[t_Backupset] WHERE [DATABASE]= @DATABASENAME AND type IN (''Full Backup'')); 
			
					-- Get the latest differential backupset
					SET @DIFFERENTIALBACKUPSETID = ( SELECT MAX(BACKUPSETID) FROM [Collector].[t_Backupset] WHERE [DATABASE]= @DATABASENAME AND type IN (''DIfferential'')); 
				
					-- Create Header text
					SELECT @HEADERTEXT = ''/*'' + CHAR(13) +''restoration script for database: '' + UPPER(NAME) +'''' + CHAR(13) +''user access: ''+ USER_ACCESS_DESC +'''' + CHAR(13) +''recovery model: ''+ RECOVERY_MODEL_DESC +'''' + CHAR(13) +''creation date:'' + CONVERT(VARCHAR, GETDATE(),121) +'''' + CHAR(13) +''*/''++ CHAR(13) ++ CHAR(13) ++''USE [MASTER]'' 
					FROM MASTER.SYS.DATABASES WHERE NAME = @DATABASENAME;

					-- Create Footer text
					SET @FOOTERTEXT = ''-- Complete restore process with recovery statement''++ CHAR(13) ++ ''RESTORE DATABASE '' + QUOTENAME(@databasename) + '' WITH RECOVERY'' ++ CHAR(13) ++ ''GO'' ++ CHAR(13) ++ ''DBCC CHECKDB (''+ @databasename +'')'';
				
					-- Create Restore verbiage								
					-- First the full backup
					SELECT @SQL  = @SQL + ''-- Restore type: ''+ type + ''; Backup Size (in KB):'' + cast(SizeInKB as varchar)+ ''; Is Damaged:'' + (case when isdamaged=0 then ''No'' else ''Yes'' end) + CHAR(13) + RestorationScripts
					FROM [Collector].[t_Backupset]
					WHERE backupsetid = @FULLBACKUPSETID;

					-- Then differential + log transaction
					IF  ( @DIFFERENTIALBACKUPSETID ) IS NULL -- if there are no differentials
						BEGIN
							SELECT @SQL  = @SQL + ''-- Restore type: ''+ type + ''; Backup Size (in KB):'' + cast(SizeInKB as varchar)+ ''; Is Damaged:'' + (case when isdamaged=0 then ''No'' else ''Yes'' end) + CHAR(13) + RestorationScripts
							FROM [Collector].[t_Backupset]
							WHERE backupsetid > @FULLBACKUPSETID and [database] = @databasename
							ORDER BY backupsetid;
						END
					ELSE
						BEGIN
							SELECT @SQL  = @SQL + ''-- Restore type: ''+ type + ''; Backup Size (in KB):'' + cast(SizeInKB as varchar)+ ''; Is Damaged:'' + (case when isdamaged=0 then ''No'' else ''Yes'' end) + CHAR(13) + RestorationScripts
							FROM [Collector].[t_Backupset]
							WHERE backupsetid >= @DIFFERENTIALBACKUPSETID and [database] = @databasename
							ORDER BY backupsetid;	
						END
							
					SET @SQL = @HEADERTEXT ++ CHAR(13) ++ CHAR(13)++ @SQL ++ CHAR(13) ++ @FOOTERTEXT
				
					-- Create filesystemobject		
					EXECUTE @OLEResult = sp_OACreate ''Scripting.FileSystemObject'' , @FS OUT

					-- Opens the file specified by the @File input parameter 
					--EXECUTE @OLEResult = sp_OAMethod @FS,''OpenTextFile'', @FileID OUT, @RESTORESCRIPTFILENAME, 8, 1
					EXECUTE @OLEResult = sp_OAMethod @FS,''CreateTextFile'', @FileID OUT, @RESTORESCRIPTFILENAME, 1

					-- Appends the string value line to the file specified by the @File input parameter
					EXECUTE @OLEResult = sp_OAMethod @FileID, ''WriteLine'', Null	, @SQL

					-- Cleanup
					EXECUTE @OLEResult = sp_OADestroy @FileID
					EXECUTE @OLEResult = sp_OADestroy @FS
				
					-- Add to BackupsetRestoreScripts table
					MERGE [Collector].[t_BackupsetRestoreScripts] AS TARGET
					USING (SELECT @RESTORESCRIPTFILENAME) AS SOURCE (FileName) ON (TARGET.[FileName] = Source.[FileName])
					WHEN MATCHED THEN
						UPDATE SET Target.CreateDatetime = GETDATE()
					WHEN NOT MATCHED THEN
						INSERT ([Database],[FileName], CreateDatetime)
						VALUES (@databasename, @RESTORESCRIPTFILENAME, GETDATE());
			
			FETCH NEXT FROM DBCURSOR INTO @DATABASENAME
			
		END
		
		--close and cleanup	
			CLOSE DBCURSOR
			DEALLOCATE DBCURSOR
END TRY
BEGIN CATCH
	-- 1. create error message
		DECLARE @ProcedureName		SYSNAME			= QUOTENAME(OBJECT_SCHEMA_NAME(@@PROCID)) +''.'' + QUOTENAME(object_name(@@PROCID))
		DECLARE @ErrorMessageFormat	VARCHAR(8000)	= ''There was an error when executing the stored procedure: %s'' + char(13) + ''Please see below for information'' + char(13) + char(13) +
														''Error Message: %s'' + char(13) + 
														''Error Severity: %i'' + char(13) + 
														''Error State: %i'' + char(13) + 
														''Error Number: %i'';
		DECLARE @ErrorMessage		VARCHAR(MAX)	= FORMATMESSAGE(@ErrorMessageFormat, @ProcedureName, ERROR_MESSAGE() , ERROR_SEVERITY() ,ERROR_STATE(), ERROR_NUMBER ());	
		
	-- 2. if loop is still open and error occur, check the status and clean up if neccessary
		if ( cursor_status(''global'', ''DBCURSOR'') > -2 )
			BEGIN
				CLOSE DBCURSOR;
				DEALLOCATE DBCURSOR;
			END;	
	
	-- 3. send the error message
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
