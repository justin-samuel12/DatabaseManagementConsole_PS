SET ANSI_NULLS, ANSI_PADDING, ANSI_WARNINGS, ARITHABORT, CONCAT_NULL_YIELDS_NULL, QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO
USE [master]
GO
/********************* VARIABLES *******************************/
	DECLARE @FileName varchar(256);
	DECLARE @the_script varchar(max);
	DECLARE @xml xml;
	DECLARE @ServerName sysname;
	DECLARE @Backuplocation varchar(1000);
	DECLARE @Cur CURSOR;
	DECLARE @VersionNumber numeric(3,2) ='1.0';
	DECLARE @Option varchar(256)= 'New';
	DECLARE @Author varchar(256)= 'justin_samuel';
	DECLARE @Description VARCHAR(100)='Pre-Requisites'
	DECLARE @ReleaseDate datetime = '10/1/2013';
	DECLARE @DTNow DateTime2 = getdate();
/***************************************************************/
BEGIN TRY
	-- 1. Check if database is online and exists. If true, drop.
		IF (DB_ID(N'$(Database_Name)') IS NOT NULL AND DATABASEPROPERTYEX(N'$(Database_Name)','Status') <> N'ONLINE')
		BEGIN
			RAISERROR(N'The state of the target database, %s, is not set to ONLINE. To deploy to this database, its state must be set to ONLINE.', 16, 127,N'$(Database_Name)') WITH NOWAIT
			RETURN
		END

		IF (DB_ID(N'$(Database_Name)') IS NOT NULL) 
		BEGIN
			PRINT N'Dropping current version of $(Database_Name)...'
			ALTER DATABASE [$(Database_Name)]
			SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
			DROP DATABASE [$(Database_Name)];
		END
			
		-- delete all jobs associated to this database
		DECLARE @job_id uniqueidentifier;
		DECLARE Job_Cursor CURSOR FOR 
			SELECT job_id FROM msdb.dbo.sysjobs WHERE name like '$(Database_Name)%' ;

		OPEN Job_Cursor;
		FETCH NEXT FROM Job_Cursor INTO @job_id
		WHILE @@FETCH_STATUS = 0
			BEGIN 
				EXEC msdb.dbo.sp_delete_job @job_id = @job_id, @delete_unused_schedule=1   
				FETCH NEXT FROM Job_Cursor INTO @job_id
			END;
		CLOSE Job_Cursor;
		DEALLOCATE Job_Cursor;
			
	-- 2. Create Database
		PRINT N'Creating $(Database_Name)...'
		CREATE DATABASE [$(Database_Name)] ON 
		PRIMARY(NAME = '$(Database_Name)_Primary', FILENAME = '$(Primary_Data)\$(Database_Name).mdf', SIZE = 5120KB , MAXSIZE = UNLIMITED, FILEGROWTH = 1024KB ),
		FILEGROUP [Configure](NAME = [$(Database_Name)_ConfigurationFG], FILENAME = '$(Secondary_Configuration_Data)\$(Database_Name)_ConfigurationFG.ndf', SIZE = 5120 KB, FILEGROWTH = 1024KB)
		LOG ON (NAME = '$(Database_Name)_log', FILENAME = '$(Primary_Log)\$(Database_Name)_log.ldf', SIZE = 1024KB , MAXSIZE = 1024GB , FILEGROWTH = 5%)
			
	-- 3. Changing properties of the database
		IF (1 = FULLTEXTSERVICEPROPERTY('IsFullTextInstalled')) BEGIN EXEC [$(Database_Name)].[dbo].[sp_fulltext_database] @action = 'enable' END;

		ALTER DATABASE [$(Database_Name)] 
			SET ANSI_NULLS ON,ANSI_PADDING ON,ANSI_WARNINGS ON,ARITHABORT ON,CONCAT_NULL_YIELDS_NULL ON,NUMERIC_ROUNDABORT OFF,QUOTED_IDENTIFIER ON,ANSI_NULL_DEFAULT OFF,
			CURSOR_DEFAULT GLOBAL, CURSOR_CLOSE_ON_COMMIT OFF,AUTO_CREATE_STATISTICS ON,AUTO_SHRINK OFF,AUTO_UPDATE_STATISTICS ON,RECURSIVE_TRIGGERS OFF,
			AUTO_UPDATE_STATISTICS_ASYNC OFF,PAGE_VERIFY CHECKSUM,DATE_CORRELATION_OPTIMIZATION OFF,DISABLE_BROKER,PARAMETERIZATION SIMPLE,SUPPLEMENTAL_LOGGING OFF,
			TRUSTWORTHY ON,DB_CHAINING OFF ,HONOR_BROKER_PRIORITY OFF, RECOVERY SIMPLE
		WITH ROLLBACK IMMEDIATE;

		ALTER DATABASE [$(Database_Name)] SET CHANGE_TRACKING = ON(AUTO_CLEANUP = ON, CHANGE_RETENTION = 365 DAYS)WITH ROLLBACK IMMEDIATE;
		ALTER DATABASE [$(Database_Name)] SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE;
		ALTER DATABASE [$(Database_Name)] SET ALLOW_SNAPSHOT_ISOLATION OFF; 
		ALTER DATABASE [$(Database_Name)] SET READ_COMMITTED_SNAPSHOT OFF;

		EXEC sys.sp_db_vardecimal_storage_format N'$(Database_Name)', N'ON'
		ALTER AUTHORIZATION ON DATABASE::[$(Database_Name)] TO sa;

	-- 4. Create Users
		SET @FileName = 'Create Users'
		SELECT @the_script = REPLACE(REPLACE(REPLACE(Execution.BulkColumn,'ï»¿',''),'<Configuration_File>','$(Configuration_File)'),'<Database_Name>','$(Database_Name)')
		FROM OPENROWSET
		(
			BULK  '$(Working_Directory)\Objects\01. Create_Users.txt',
			SINGLE_CLOB 
		) Execution

		EXEC (@the_script);

	-- 5. Create Schemas
		SET @FileName = 'Create Schemas'
		SELECT @the_script = REPLACE(REPLACE(REPLACE(Execution.BulkColumn,'ï»¿',''),'<Configuration_File>','$(Configuration_File)'),'<Database_Name>','$(Database_Name)')
		FROM OPENROWSET
		(
			BULK  '$(Working_Directory)\Objects\02. Create_Schemas.txt',
			SINGLE_CLOB 
		) Execution

		EXEC (@the_script);
END TRY

-- start error catching 
BEGIN CATCH
	-- 1. if loop is still open and error occur, check the status and clean up if neccessary
			if ( cursor_status('global', '@Cur') > -2 )
				BEGIN
					CLOSE @Cur;
					DEALLOCATE @Cur;
				END;

	-- 2. Raise Error
		DECLARE @ProcedureName		SYSNAME			=  @FileName;
		DECLARE @ErrorMessageFormat	VARCHAR(8000)	= 'There was an error when executing the step: %s|' +
														'Error Message: %s|' + 
														'Error Severity: %i|' + 
														'Error State: %i|' + 
														'Error Number: %i';
		DECLARE @ErrorMessage		VARCHAR(MAX)	= FORMATMESSAGE(REPLACE(@ErrorMessageFormat,char(13),'`r`n'), @ProcedureName, ERROR_MESSAGE() , ERROR_SEVERITY() ,ERROR_STATE(), ERROR_NUMBER ());	
		RAISERROR (@ErrorMessage,16,1) WITH LOG;
END CATCH;
GO
	