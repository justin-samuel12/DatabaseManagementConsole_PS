SET ANSI_NULLS, ANSI_PADDING, ANSI_WARNINGS, ARITHABORT, CONCAT_NULL_YIELDS_NULL, QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO
USE [$(Database_Name)]
GO
IF OBJECT_ID(N'Config.usp_RemoteDatabase_Configure')  IS NOT NULL
BEGIN
	DROP PROCEDURE Config.usp_RemoteDatabase_Configure;
END
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author: Justin Samuel
-- Create date: 2/22/2014
-- Description:	Configure Remote database
-- =============================================
CREATE PROCEDURE Config.usp_RemoteDatabase_Configure
AS
BEGIN TRY;
	SET NOCOUNT ON;
	/************************* VARIABLES *************************************/
		DECLARE @databasename sysname ='DatabaseManagementTool';
		DECLARE @sql varchar(max);
		DECLARE @serverinstanceid uniqueidentifier;
		DECLARE @serverinstance sysname;
		DECLARE @backuplocation nvarchar(1000);
	/*************************************************************************/
		-- check to see if database exists on server
		DECLARE ServerCursor Cursor FOR SELECT ServerInstanceId, ServerName + '\' + InstanceName, BackupLocation FROM Config.t_ServerInstance WHERE PrimaryConsoleServer = 0 AND isMonitored = 1 AND DMTDBInstalledDatetime = '12/31/2999';

		OPEN ServerCursor;
		FETCH NEXT FROM ServerCursor into @serverinstanceid, @serverinstance,@backuplocation

		WHILE @@FETCH_STATUS = 0
			BEGIN
					-- create linkedserver
						EXEC [Config].[usp_ServerInstance_LinkedServer_Configure] @serverinstance,'Create';


					-- enable options on server
						SET @sql ='Exec sp_configure ''''show advanced options'''',1;
								   Reconfigure with override;

								   Exec sp_configure ''''OLE AUTOMATION PROCEDURES'''',1;
								   Reconfigure with override;

								   Exec sp_configure ''''XP_CMDSHELL'''',1;
								   Reconfigure with override;

								   Exec sp_configure ''''recovery interval (min)'''',1;
								   Reconfigure with override;

								   Exec sp_configure ''''network packet size (B)'''',4096;
								   Reconfigure with override;

								   Exec sp_configure ''''backup compression default'''',1;
								   Reconfigure with override;

								   Exec sp_configure ''''Ad Hoc Distributed Queries'''',1;
								   Reconfigure with override;

								   Exec sp_configure ''''Agent XPs'''',1;
								   Reconfigure with override;

								   Exec sp_configure ''''show advanced options'''',0;
								   Reconfigure with override;'
						EXEC ('EXEC [' + @serverinstance + '].tempdb.dbo.sp_executesql N'''+ @sql +'''')


					-- check to see if db exists on that server. if exists, destroy
						SET @sql = 'if exists ( select * from master.sys.databases where name = ''''' + @databasename +''''' )
									begin
										ALTER DATABASE ' + QUOTENAME(@databasename) +' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
										DROP DATABASE ' + QUOTENAME(@databasename) +';
									end;'			
						EXEC ('EXEC [' + @serverinstance + '].tempdb.dbo.sp_executesql N'''+ @sql +'''')

					-- delete all jobs associated to this database
						SET @sql = 'DECLARE @job_id uniqueidentifier;
									DECLARE Job_Cursor CURSOR FOR SELECT job_id FROM msdb.dbo.sysjobs WHERE name like ''''' + @databasename +'%'''' ;

									OPEN Job_Cursor;
									FETCH NEXT FROM Job_Cursor INTO @job_id
									WHILE @@FETCH_STATUS = 0
										BEGIN 
											EXEC msdb.dbo.sp_delete_job @job_id = @job_id, @delete_unused_schedule=1   
											FETCH NEXT FROM Job_Cursor INTO @job_id
										END;
									CLOSE Job_Cursor;
									DEALLOCATE Job_Cursor;'		
						EXEC ('EXEC [' + @serverinstance + '].tempdb.dbo.sp_executesql N'''+ @sql +'''')

					-- create the database
						SET @sql = 	'CREATE DATABASE '+ QUOTENAME(@databasename) +''
						EXEC ('EXEC [' + @serverinstance + '].tempdb.dbo.sp_executesql N'''+ @sql +'''')

						SET @sql = 'IF (1 = FULLTEXTSERVICEPROPERTY(''''IsFullTextInstalled'''')) BEGIN EXEC '+ QUOTENAME(@databasename) +'.[dbo].[sp_fulltext_database] @action = ''''enable'''' END;'
						EXEC ('EXEC [' + @serverinstance + '].tempdb.dbo.sp_executesql N'''+ @sql +'''')
								
						SET @sql = 'ALTER DATABASE '+ QUOTENAME(@databasename) +'
										SET ANSI_NULLS ON,ANSI_PADDING ON,ANSI_WARNINGS ON,ARITHABORT ON,CONCAT_NULL_YIELDS_NULL ON,NUMERIC_ROUNDABORT OFF,QUOTED_IDENTIFIER ON,ANSI_NULL_DEFAULT OFF,
										CURSOR_DEFAULT GLOBAL, CURSOR_CLOSE_ON_COMMIT OFF,AUTO_CREATE_STATISTICS ON,AUTO_SHRINK OFF,AUTO_UPDATE_STATISTICS ON,RECURSIVE_TRIGGERS OFF,
										AUTO_UPDATE_STATISTICS_ASYNC OFF,PAGE_VERIFY CHECKSUM,DATE_CORRELATION_OPTIMIZATION OFF,DISABLE_BROKER,PARAMETERIZATION SIMPLE,SUPPLEMENTAL_LOGGING OFF,
										TRUSTWORTHY ON,DB_CHAINING OFF ,HONOR_BROKER_PRIORITY OFF, RECOVERY SIMPLE
									WITH ROLLBACK IMMEDIATE;'
						EXEC ('EXEC [' + @serverinstance + '].tempdb.dbo.sp_executesql N'''+ @sql +'''')
				
						SET @sql = 'ALTER DATABASE '+ QUOTENAME(@databasename) +' SET CHANGE_TRACKING = ON(AUTO_CLEANUP = ON, CHANGE_RETENTION = 365 DAYS)WITH ROLLBACK IMMEDIATE;
									ALTER DATABASE '+ QUOTENAME(@databasename) +' SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE;
									ALTER DATABASE '+ QUOTENAME(@databasename) +' SET ALLOW_SNAPSHOT_ISOLATION OFF; 
									ALTER DATABASE '+ QUOTENAME(@databasename) +' SET READ_COMMITTED_SNAPSHOT OFF;
				
									EXEC sys.sp_db_vardecimal_storage_format '+ QUOTENAME(@databasename) +', N''''ON''''
									ALTER AUTHORIZATION ON DATABASE::'+ QUOTENAME(@databasename) +' TO sa;'
						EXEC ('EXEC [' + @serverinstance + '].tempdb.dbo.sp_executesql N'''+ @sql +'''')

					---- create schema
						SET @sql = 'CREATE SCHEMA Config AUTHORIZATION dbo;'
						exec ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')

					---- create the tables		
						SET @sql = REPLACE((SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('Config.usp_RemoteDatabase_TablesSchema_Create')),'''','''''');
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')

						SET @sql ='EXEC Config.usp_RemoteDatabase_TablesSchema_Create; DROP PROC Config.usp_RemoteDatabase_TablesSchema_Create'
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')

					-- insert values into tables
						SET @sql = 'INSERT INTO Config.t_ServerInstance (ServerInstanceId, InstanceName, BackupLocation)
									VALUES (''''' +  CAST(@serverinstanceid as varchar(100)) + ''''',''''' + @serverinstance + ''''',''''' + @backuplocation + ''''')'
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')

					-- SVFN_ backuplocaion
						SET @sql = (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('Config.svfn_BackupLocation_Get'));
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')

					-- All Maintenance SP
						SET @sql = REPLACE((SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('Maintenance.usp_Backupset_Insert')),'''','''''');
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')

						SET @sql = REPLACE((SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('Maintenance.usp_Maintenance_CreateRestoreScripts')),'''','''''');
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')
		
						SET @sql = REPLACE((SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('Maintenance.usp_Maintenance_DeleteBackupContents')),'''','''''');
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')

						SET @sql = REPLACE((SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('Maintenance.usp_Maintenance_DifferentialBackup')),'''','''''');
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')

						SET @sql = REPLACE((SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('Maintenance.usp_Maintenance_FolderContents')),'''','''''');
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')
		
						SET @sql = REPLACE((SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('Maintenance.usp_Maintenance_FullBackup')),'''','''''');
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')

						SET @sql = REPLACE((SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('Maintenance.usp_Maintenance_TransactionLog')),'''','''''');
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')

						SET @sql = REPLACE((SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('Maintenance.usp_BackupsetOperation_Insert')),'''','''''');
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')

						SET @sql = REPLACE((SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('Reports.usp_BackupsetOperation_Insert')),'''','''''');
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')

					-- All Maintenance Jobs
						SET @sql = REPLACE((SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('Config.usp_RemoteDatabase_FullBackupJob_Create')),'''','''''');
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')
						
						SET @sql = REPLACE((SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('Config.usp_RemoteDatabase_TransactionLogJob_Create')),'''','''''');
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')
						
						SET @sql = REPLACE((SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('Config.usp_RemoteDatabase_DifferentialJob_Create')),'''','''''');
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')
					
						SET @sql = REPLACE((SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('Config.usp_RemoteDatabase_DeleteBackupJob_Create')),'''','''''');
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')


						SET @sql ='EXEC Config.usp_RemoteDatabase_FullBackupJob_Create;
									EXEC Config.usp_RemoteDatabase_TransactionLogJob_Create;
									EXEC Config.usp_RemoteDatabase_DifferentialJob_Create;
									EXEC Config.usp_RemoteDatabase_DeleteBackupJob_Create; 
									DROP PROC Config.usp_RemoteDatabase_FullBackupJob_Create;
									DROP PROC Config.usp_RemoteDatabase_TransactionLogJob_Create;
									DROP PROC Config.usp_RemoteDatabase_DifferentialJob_Create;
									DROP PROC Config.usp_RemoteDatabase_DeleteBackupJob_Create;'
						EXEC ('EXEC [' + @serverinstance + '].['+@databasename +'].dbo.sp_executesql N'''+ @sql +'''')
	

				-- remove linked server	
					EXEC [Config].[usp_ServerInstance_LinkedServer_Configure] @serverinstance,'Remove';


				-- update table
				UPDATE Config.t_ServerInstance
				SET DMTDBInstalledDatetime = getdate()
				WHERE ServerInstanceId =  @serverinstanceid

				FETCH NEXT FROM SERVERCURSOR INTO @SERVERINSTANCEID, @SERVERINSTANCE,@BACKUPLOCATION
			END

		CLOSE SERVERCURSOR;
		DEALLOCATE SERVERCURSOR;
END TRY
	BEGIN CATCH
		-- 1. if loop is still open and error occur, check the status and clean up if neccessary
			if ( cursor_status('global', 'ServerCursor') > -2 )
				BEGIN
					Close ServerCursor;
					Deallocate ServerCursor;
				END;

		DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
		DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
		DECLARE @ErrorState INT = ERROR_STATE();
	
		DECLARE @ERROR_MSG NVARCHAR(MAX)='';
		SELECT @ERROR_MSG = 'Error Message: ' + @ErrorMessage + char(13) + 'Error Severity: ' + convert(varchar,@ErrorSeverity)  + char(13) + 'Error State: ' + convert(varchar,@ErrorState)  + char(13) + 'Error Number: ' + convert(varchar,ERROR_NUMBER());
	
		RAISERROR (@ERROR_MSG,16,1);
		
	END CATCH;	

	GO
	exec Config.usp_RemoteDatabase_Configure;



























