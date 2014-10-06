:setvar Database_Name "DatabaseManagementConsole"
:setvar File_Name "09. Create_Collector.usp_Maintenance_Backups.sql"

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
	DECLARE @ObjectName varchar(256) = 'Collector.usp_Maintenance_Backups';
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
-- Create date: 3/1/2013
-- Description:	Full / Differential / Transaction Log Backup of database. Due to maintanance wizard not correctly handling database ready only state  
-- =============================================
CREATE PROCEDURE ' + @ObjectName + '
AS
/********************* VARIABLES *******************************/
	DECLARE @Date_Now							DATETIME2	= GETDATE();
	DECLARE @Date_ZeroOutTime					DATETIME2	= DATEADD(DAY, DATEDIFF(DAY, 0 , @Date_Now),0 ) -- 00:00:00AM
	DECLARE @Date_NowNoMinutesTile				DATETIME2	= DATEADD(HOUR, DATEPART(HOUR,@Date_Now), @Date_ZeroOutTime);
	DECLARE @Operationtype						NVARCHAR(50) = NULL;
	DECLARE @Operationstatus					NVARCHAR(50) =''Success'';
	DECLARE @SQL								VARCHAR(MAX);
	DECLARE @Backupfolderlocation				VARCHAR(100) = [Configuration].[svfn_DefaultFolderLocation_Get](''BackupDirectory'') ; -- backupfolder local
	DECLARE @Backupfileconvention				VARCHAR(500) = CONVERT(VARCHAR, @Date_Now ,112) + ''_'' + REPLACE( CAST(@Date_Now AS TIME(2)) ,'':'',''-'');
	DECLARE @Backupfolder						VARCHAR(500);
	DECLARE @Backupfile							VARCHAR(500);
	DECLARE @BackupType							VARCHAR(1) = NULL;
	DECLARE @ErrorMsg							VARCHAR(50);
	DECLARE @Backupsetid						INT;
	DECLARE @Databases							TABLE ( Id INT Identity(1,1), Database_Id INT PRIMARY KEY Clustered, Name Sysname, Recovery_Model Int );
	DECLARE @TotalDatabasesCount				INT;
	DECLARE @DatabaseLoopCount					INT			  = 1;
	DECLARE @Database_ID						INT;
	DECLARE @Database_Name						SYSNAME;
	DECLARE @Recovery_Model						INT;
/***************************************************************/
BEGIN TRY;
	SET NOCOUNT ON; SET XACT_ABORT ON;
	-- 1. Insert all databases minus tempdb
		INSERT @Databases (Database_Id, Name, Recovery_Model)
		SELECT DATABASE_ID, NAME, RECOVERY_MODEL FROM MASTER.SYS.DATABASES WITH(NOLOCK) WHERE IS_READ_ONLY = 0 AND IS_IN_STANDBY = 0 AND DATABASE_ID <>2;
		SET @TotalDatabasesCount = @@ROWCOUNT;

		-- 2. Loop thru each	
		WHILE @DatabaseLoopCount < = @TotalDatabasesCount
			BEGIN
				-- 2a. Set preconditions
				SET @BackupType = NULL;

				SELECT @Database_ID = Database_Id, @Database_Name = Name, @Recovery_Model = Recovery_Model			
				FROM @Databases WHERE id = @DatabaseLoopCount;

				SET @BACKUPFOLDER = @backupfolderlocation ++ @database_name;
				EXECUTE MASTER.DBO.XP_CREATE_SUBDIR @BACKUPFOLDER;
			
				-- 2b. Full backups. If operation runs for first time and there are no full backups for that day then this step will execute first
				IF NOT EXISTS ( SELECT TOP 1 1
								FROM msdb..backupset 
								WHERE [type] = ''D'' and 
										database_name = @Database_Name and 
										DATEADD(DAY, DATEDIFF(DAY, 0 , backup_finish_date ),0 ) = @Date_ZeroOutTime )
					BEGIN
						SET @Operationtype =''Full Backup'';
						SET @BackupType =''D'';
						SET @Backupfile =  @backupfolder + ''\'' + @database_name + ''_Database_Full_'' + @backupfileconvention  + ''.bak'';
						SET @SQL =''BACKUP DATABASE ['' + @database_name +'']
									TO DISK = N''''''+ @backupfile + '''''' 
									WITH NOFORMAT, NOINIT, NAME = N''''''+ + @database_name + ''_Database_Full_'' + @backupfileconvention + '''''', SKIP, REWIND, NOUNLOAD, NO_COMPRESSION, CHECKSUM,  STATS = 10''			
						EXEC(@SQL);
					END;
				-- 2c. Differential backups. Run every 4 hrs only starting at 4AM
				ELSE IF ( @Database_ID > 4 AND 
							datediff(hh,@Date_ZeroOutTime, @Date_Now ) IN (4,8,12,16,20) AND 
							NOT EXISTS ( select TOP 1 1
										from msdb..backupset with(nolock)
										where [Type] = ''I'' AND
												backup_finish_date BETWEEN @Date_NowNoMinutesTile AND DATEADD(HOUR,1,@Date_NowNoMinutesTile) AND
													backup_set_id = (select max(backup_set_id) from msdb..backupset with(nolock)
																	where database_name = @Database_Name)
										)
						)
					BEGIN
						SET @Operationtype =''Differential Backup'';
						SET @BackupType =''I'';
						SET @Backupfile =  @backupfolder + ''\'' + @database_name + ''_Database_Differential_'' + @backupfileconvention  + ''.dif'';
						SET @SQL =''BACKUP DATABASE ['' + @database_name +'']
									TO DISK = N''''''+ @backupfile + '''''' 
									WITH NOFORMAT, NOINIT, DIFFERENTIAL, NAME = N''''''++ @database_name + ''_Database_Differential_'' + @backupfileconvention +'''''', SKIP, REWIND, NOUNLOAD, NO_COMPRESSION, CHECKSUM, STATS = 10''			
						EXEC(@SQL);
					END;
				-- 2d. Transaction Log
				ELSE IF ( @Database_ID > 4 AND @Recovery_Model IN (1,2) AND 
							NOT EXISTS ( select TOP 1 1
										from msdb..backupset with(nolock)
										where [Type] = ''L'' AND
												backup_finish_date BETWEEN @Date_NowNoMinutesTile AND DATEADD(HOUR,1,@Date_NowNoMinutesTile) AND
													backup_set_id = (select max(backup_set_id) from msdb..backupset with(nolock)
																	where database_name =@Database_Name)
										)
						)
					BEGIN
						SET @Operationtype =''Transaction Log'';
						SET @BackupType =''L'';
						SET @Backupfile =  @backupfolder + ''\'' + @database_name + ''_Transaction_Log_'' + @backupfileconvention  + ''.trn'';
						SET @SQL =''BACKUP LOG ['' + @database_name +'']
									TO DISK = N''''''+ @backupfile + '''''' 
									WITH NOFORMAT, NOINIT, NAME = N''''''++ @database_name + ''_Transaction_Log_'' + @backupfileconvention +'''''', SKIP, REWIND, NOUNLOAD, NO_COMPRESSION, CHECKSUM, STATS = 10''			
						EXEC(@SQL)
					END;	
				-- 2e. if backuptype is not null, validate backup and insert into tables
				IF @BackupType IS NOT NULL
					BEGIN
					--verify backup file	
						SET @backupsetid = ( SELECT MAX(backup_set_id) FROM msdb..backupset WHERE database_name = @database_name and [type] = @BackupType );	
						IF @backupsetid IS NULL 
							BEGIN 
								SET @ErrorMsg = ''Verify failed. Backup information for database: '' + @database_name + '' not found.'';
								RAISERROR (@ErrorMsg, 16, 1) WITH LOG; 
							END
				
					-- insert into [Maintenance].[t_Backupset]
						EXEC [Collector].[usp_Backupset_Insert] @backupsetid, @backupfile, @Date_Now ;

					-- insert into [Collector].[t_BackupsetOperation]
						EXEC [Collector].[usp_BackupsetOperation_Insert] @Database_Name ,@operationtype, @operationstatus, null, @date_now;
					END;

				SET @DatabaseLoopCount +=1;
			END;		
END TRY
BEGIN CATCH
	-- 1. change the operation status to fail
		SET @Operationstatus = ''Failure'';

		DECLARE @ProcedureName		SYSNAME			= QUOTENAME(OBJECT_SCHEMA_NAME(@@PROCID)) +''.'' + QUOTENAME(object_name(@@PROCID))
		DECLARE @ErrorMessageFormat	VARCHAR(8000)	= ''There was an error when executing the stored procedure: %s'' + char(13) + ''Please see below for information'' + char(13) + char(13) +
														''Error Message: %s'' + char(13) + 
														''Error Severity: %i'' + char(13) + 
														''Error State: %i'' + char(13) + 
														''Error Number: %i'';
		DECLARE @ErrorMessage		VARCHAR(MAX)	= FORMATMESSAGE(@ErrorMessageFormat, @ProcedureName, ERROR_MESSAGE() , ERROR_SEVERITY() ,ERROR_STATE(), ERROR_NUMBER ());	
		
		-- record error in the [Collector].[t_BackupsetOperation]
			EXEC [Collector].[usp_BackupsetOperation_Insert] @Database_Name, @operationtype, @operationstatus, @errormessage, @date_now;
	
	-- 3. send the error message
      RAISERROR (@ErrorMessage,16,1) WITH LOG;

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
GO
