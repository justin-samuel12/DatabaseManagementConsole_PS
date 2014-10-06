SET ANSI_NULLS, ANSI_PADDING, ANSI_WARNINGS, ARITHABORT, CONCAT_NULL_YIELDS_NULL, QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO
USE [master]
GO
/********************* VARIABLES *******************************/
	DECLARE @xml xml;
	DECLARE @ServerConfigurationName VARCHAR(500);
	DECLARE @Value VARCHAR(500);
	DECLARE @sysalert_Deadlock sysname = 'Respond to DEADLOCK_GRAPH';
	DECLARE @sysalert_Blockedprocess sysname = 'Respond to BLOCKED_PROCESS_REPORT';
	
	DECLARE @cpu_count int;
	DECLARE @file_count int;
	DECLARE @logical_name sysname;
	DECLARE @file_name nvarchar(520);
	DECLARE @physical_name nvarchar(520);
	DECLARE @alter_command nvarchar(max);

	DECLARE @NumErrorLogs INT;
	DECLARE @TCPPort NVARCHAR(200);
/***************************************************************/
	BEGIN TRY;	
		-- 1. Delete all Server Alerts / triggers
			IF EXISTS (SELECT NULL FROM master.sys.server_triggers WHERE name ='DDLTrigger_Audit')
				BEGIN DROP TRIGGER [DDLTrigger_Audit] ON ALL SERVER END;

			IF ( select 1 from msdb..sysalerts where name = @sysalert_Deadlock) is not null
				BEGIN EXEC msdb.dbo.sp_delete_alert @name= @sysalert_Deadlock END;

			IF ( select 1 from msdb..sysalerts where name = @sysalert_Blockedprocess) is not null
				BEGIN EXEC msdb.dbo.sp_delete_alert @name= @sysalert_Blockedprocess END;

		-- 2. Show Advance option
			Exec sp_configure 'show advanced options',1;
			Reconfigure with override;

		-- 3. Get XML information
			SELECT @Xml = CAST(BulkColumn AS XML)
			FROM OPENROWSET (BULK '$(Configuration_File)', SINGLE_BLOB) AS DATA;
	
		-- 4. Declare Cursor
			DECLARE Cur CURSOR FOR 
			SELECT t.c.value('@Name','NVARCHAR(100)') , 
				   t.c.value('@value','NVARCHAR(100)') 
			FROM @xml.nodes('/Root/ServerConfiguration/ServerOptions/Options/Option') AS T(c)

		-- 5. Open Cursor
			OPEN Cur
		
		-- 6. Fetch
			FETCH NEXT FROM Cur INTO @ServerConfigurationName, @Value

		-- 7. Start loop
			WHILE @@FETCH_STATUS = 0
				BEGIN
				
					EXEC ('exec sp_configure ''' + @ServerConfigurationName + ''',' + @Value );
					EXEC ('reconfigure with override');			
    
					FETCH NEXT FROM Cur INTO @ServerConfigurationName, @Value
				END

		-- 8. Cleanup
			Exec sp_configure 'show advanced options',0;
			Reconfigure with override;

			CLOSE Cur;
			DEALLOCATE Cur;

		 -- 9. Change tempdb location and add neccessary temp files
			EXEC ('ALTER DATABASE [tempdb] MODIFY FILE ( NAME = N''tempdev'', FILENAME =N''$(TempDB_Data)\tempdb.mdf' + ''', SIZE = 5120KB , MAXSIZE = UNLIMITED, FILEGROWTH = 1024KB )');
			EXEC ('ALTER DATABASE [tempdb] MODIFY FILE ( NAME = N''templog'', FILENAME =N''$(TempDB_Log)\templog.ldf' + ''', SIZE = 1024KB , MAXSIZE = UNLIMITED, FILEGROWTH = 10% )');

			SELECT  @physical_name = physical_name FROM tempdb.sys.database_files WHERE   name = 'tempdev';
			SELECT  @file_count = COUNT(*) FROM tempdb.sys.database_files WHERE type_desc = 'ROWS'
			SELECT  @cpu_count = cpu_count FROM sys.dm_os_sys_info

			WHILE @file_count < @cpu_count -- Add * 0.25 here to add 1 file for every 4 cpus, * .5 for every 2 etc.
			 BEGIN
				SELECT  @logical_name = 'tempdev' + CAST(@file_count AS nvarchar)
				SELECT  @file_name = REPLACE(@physical_name, 'tempdb.mdf', @logical_name + '.ndf')
				SELECT  @alter_command = 'ALTER DATABASE [tempdb] ADD FILE ( NAME =N''' + @logical_name + ''', FILENAME =N''' +  @file_name + ''', SIZE = 5120KB , MAXSIZE = UNLIMITED, FILEGROWTH = 1024KB )'
				PRINT   @alter_command
				EXEC    sp_executesql @alter_command
				SELECT  @file_count += 1
			 END		
			
		-- 10. Error Log cleanup threshold -- total num of error logs to keep
			SELECT @NumErrorLogs = @xml.value('(/Root[1]/ServerConfiguration[1]/ServerProperties[1]/Properties[1]/Property[@Name="NumErrorLogs"][1])/@value','NVARCHAR(200)')
			PRINT 'set NumErrorLogs('+ CAST(@NumErrorLogs AS VARCHAR) + ')'
			EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'NumErrorLogs', REG_DWORD, @NumErrorLogs

		-- 11. disable TcpDynamicPorts
		    PRINT 'disable TcpDynamicPorts'
			EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer\SuperSocketNetLib\TCP\IPAll', N'TcpDynamicPorts', REG_SZ, N''

		-- 12. set TCP Port    
			SELECT @TCPPort = @xml.value('(/Root[1]/ServerConfiguration[1]/ServerProperties[1]/Properties[1]/Property[@Name="TCPPort"][1])/@value','NVARCHAR(200)')
			PRINT 'set TCP port (' + @TCPPort + ')'
			EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer\SuperSocketNetLib\TCP\IPAll', N'TcpPort', REG_SZ, @TCPPort
	 
	END TRY
	BEGIN CATCH
		-- 1. if loop is still open and error occur, check the status and clean up if neccessary
				if ( cursor_status('global', 'Cur') > -2 )
					BEGIN
						CLOSE Cur;
						DEALLOCATE Cur;
					END;

		-- 2. Raise Error
			DECLARE @ProcedureName		SYSNAME			=  '$(File_Name)';
			DECLARE @ErrorMessageFormat	VARCHAR(8000)	= 'There was an error when executing the step: %s|' +
															'Error Message: %s|' + 
															'Error Severity: %i|' + 
															'Error State: %i|' + 
															'Error Number: %i';
			DECLARE @ErrorMessage		VARCHAR(MAX)	= FORMATMESSAGE(REPLACE(@ErrorMessageFormat,char(13),'`r`n'), @ProcedureName, ERROR_MESSAGE() , ERROR_SEVERITY() ,ERROR_STATE(), ERROR_NUMBER ());	
			RAISERROR (@ErrorMessage,16,1) WITH LOG;
	END CATCH;