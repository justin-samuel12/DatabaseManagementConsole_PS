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
-- Create date: ''' + cast(@ReleaseDate as varchar) + '''
-- Description:	Create restore scripts   
-- =============================================
CREATE PROCEDURE ' + @ObjectName + '
	@Databasename	SYSNAME
AS
	/********************* VARIABLES *******************************/
		DECLARE @backupfolderlocation				VARCHAR(100)= [Configuration].[svfn_DefaultFolderLocation_Get](''BackupDirectory'') ; -- backupfolder local
		DECLARE @backupfoldername					VARCHAR(200); -- backupfolder + database name
		DECLARE @restorescriptconvention			VARCHAR(500) = ''_Restore_File_'' + CONVERT(VARCHAR, GETDATE(),112);
		DECLARE @restorescriptfilename				VARCHAR(200); -- name of the restore file 
		DECLARE @extention							VARCHAR(3) = ''SQL''; -- extention
	
		DECLARE @headertext							VARCHAR(500);
		DECLARE @footertext							VARCHAR(500);

		DECLARE @fullbackupsetid					INT;
		DECLARE @differentialbackupsetid			INT;

		DECLARE @sql								VARCHAR(8000)='''';
	
		DECLARE @fs									INT
		DECLARE @oleresult							INT
		DECLARE @fileid								INT
	
		DECLARE @fileTable							TABLE (Id INT Identity(1,1),files varchar(2000) );
		DECLARE @InfoTable							TABLE (Id INT Identity(1,1),comments varchar(2000), restorationscripts varchar(8000) );
		DECLARE @whileloop							INT = 1;
		DECLARE @CountOfRecords						INT = 0;
	/***************************************************************/
BEGIN TRY;
	SET NOCOUNT ON;

		SET @SQL +=''USE '' + quotename(@databasename) +''; select ''''Move '''''''''''' + name + '''''''''''' To ''''''''''''  + filename + '''''''''''',''''
						from sysfiles''
		INSERT @fileTable EXEC ( @SQL);
		SET @SQL = '''';

		-- 2. now loop and put the value in a variable
		WHILE @whileloop <= ( SELECT count(1) FROM @fileTable )
			BEGIN
				SET @SQL += ( SELECT files FROM @fileTable WHERE Id = @whileloop) + char(13);
				SET @whileloop +=1;
			END
			
		--set backup foldername to backup folder local + database name	
		set @backupfoldername=  @backupfolderlocation ++ @databasename;
		set @restorescriptfilename =  @backupfoldername + ''\'' + @databasename + @restorescriptconvention  + ''.'' + @extention;
	
		-- Get the latest full backupset
		SET @fullbackupsetid = ( SELECT MAX(MaintenanceBackupSetId) FROM [Collector].[t_MaintenanceBackupSet] WHERE [DATABASE]= @DATABASENAME AND [type] like ''Full%''); 
			
		-- Get the latest differential backupset
		SET @differentialbackupsetid = ( SELECT MAX(MaintenanceBackupSetId) FROM [Collector].[t_MaintenanceBackupSet] WHERE [DATABASE]= @DATABASENAME AND [type] like ''Different%''); 
	 
		-- Create Header text
		SELECT @Headertext = ''/*'' + CHAR(13) +''restoration script for database: '' + UPPER(NAME) +'''' + CHAR(13) +''user access: ''+ USER_ACCESS_DESC +'''' + CHAR(13) +''recovery model: ''+ RECOVERY_MODEL_DESC +'''' + CHAR(13) +''creation date:'' + CONVERT(VARCHAR, GETDATE(),121) +'''' + CHAR(13) +''*/''++ CHAR(13) ++ CHAR(13) ++''USE [MASTER]'' 
		FROM MASTER.SYS.DATABASES WHERE NAME = @DATABASENAME;

		-- Create Footer text
		SET @Footertext = CHAR(13) ++ ''-- Complete restore process with recovery statement''++ CHAR(13) ++ ''RESTORE DATABASE '' + QUOTENAME(@databasename) + '' WITH RECOVERY'' ++ CHAR(13) ++ ''GO'' ++ CHAR(13) ++ ''DBCC CHECKDB (''+ @databasename +'')'';
				
		-- first insert Full Backup
		insert into @InfoTable
		select ''-- Restore type: ''+ type + ''; Backup Size (in KB):'' + cast(SizeInKB as varchar)+ ''; Is Damaged:'' + (case when isdamaged=0 then ''No'' else ''Yes'' end),
				CASE WHEN TYPE Like''Transaction%'' then ''RESTORE LOG ['' + [Database] +'']''++ char(10) ++''FROM DISK = N''''''+ [FileName]  +''''''''  ++ char(10) ++  ''WITH '' + @SQL + '' NOUNLOAD, NORECOVERY, REPLACE''
				 ELSE ''RESTORE DATABASE ['' + [Database] +'']''++ char(10) ++''FROM DISK = N''''''+ [FileName]  +''''''''  ++ char(10) ++  ''WITH '' + @SQL + '' NOUNLOAD, NORECOVERY, REPLACE'' END		
		from [Collector].[t_MaintenanceBackupSet] (nolock)
		WHERE MaintenanceBackupSetId = @Fullbackupsetid;


		-- Then differential + log transaction
		IF  ( @Differentialbackupsetid ) IS NULL -- if there are no differentials
			BEGIN
				insert into @InfoTable
				select ''-- Restore type: ''+ type + ''; Backup Size (in KB):'' + cast(SizeInKB as varchar)+ ''; Is Damaged:'' + (case when isdamaged=0 then ''No'' else ''Yes'' end),
					CASE WHEN TYPE Like''Transaction%'' then ''RESTORE LOG ['' + [Database] +'']''++ char(10) ++''FROM DISK = N''''''+ [FileName]  +''''''''  ++ char(10) ++  ''WITH '' + @SQL + '' NOUNLOAD, NORECOVERY, REPLACE''
					 ELSE ''RESTORE DATABASE ['' + [Database] +'']''++ char(10) ++''FROM DISK = N''''''+ [FileName]  +''''''''  ++ char(10) ++  ''WITH '' + @SQL + '' NOUNLOAD, NORECOVERY, REPLACE'' END		
				from [Collector].[t_MaintenanceBackupSet] (nolock)
				WHERE MaintenanceBackupSetId > @Fullbackupsetid and [database] = @databasename
				ORDER BY MaintenanceBackupSetId;
			END
		ELSE
			BEGIN
				insert into @InfoTable
				select ''-- Restore type: ''+ type + ''; Backup Size (in KB):'' + cast(SizeInKB as varchar)+ ''; Is Damaged:'' + (case when isdamaged=0 then ''No'' else ''Yes'' end),
					CASE WHEN TYPE Like''Transaction%'' then ''RESTORE LOG ['' + [Database] +'']''++ char(10) ++''FROM DISK = N''''''+ [FileName]  +''''''''  ++ char(10) ++  ''WITH '' + @SQL + '' NOUNLOAD, NORECOVERY, REPLACE''
					 ELSE ''RESTORE DATABASE ['' + [Database] +'']''++ char(10) ++''FROM DISK = N''''''+ [FileName]  +''''''''  ++ char(10) ++  ''WITH '' + @SQL + '' NOUNLOAD, NORECOVERY, REPLACE'' END		
				from [Collector].[t_MaintenanceBackupSet] (nolock)
				WHERE MaintenanceBackupSetId >= @Differentialbackupsetid and [database] = @databasename
				ORDER BY MaintenanceBackupSetId;
			END;

			-- now create file
			SELECT @CountOfRecords = Count(1) FROM @InfoTable;
			SET @whileloop = 1;

			IF @CountOfRecords > 0 -- if there are records, create
				BEGIN
					
					-- Create filesystemobject		
					EXECUTE @OLEResult = sp_OACreate ''Scripting.FileSystemObject'' , @fs OUT

					-- Opens the file specified by the @File input parameter 
					EXECUTE @OLEResult = sp_OAMethod @FS,''CreateTextFile'', @fileid OUT, @restorescriptfilename, 1

					-- first create header
					EXECUTE @OLEResult = sp_OAMethod @FileID, ''WriteLine'', Null	, @Headertext

				
					WHILE @whileloop <= @CountOfRecords
						BEGIN
							 SELECT @SQL = CHAR(13) + Comments + CHAR(13) + RestorationScripts FROM @InfoTable Where Id = @whileloop;
							 EXECUTE @OLEResult = sp_OAMethod @FileID, ''WriteLine'', Null	, @SQL;
							 SET @whileloop +=1;
						END;
				
					-- Last create footer
					EXECUTE @OLEResult = sp_OAMethod @FileID, ''WriteLine'', Null	, @Footertext			
				
				
					-- Cleanup
					EXECUTE @OLEResult = sp_OADestroy @fileid
					EXECUTE @OLEResult = sp_OADestroy @fs
				END;
				
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
