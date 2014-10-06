SET ANSI_NULLS, ANSI_PADDING, ANSI_WARNINGS, ARITHABORT, CONCAT_NULL_YIELDS_NULL, QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO
USE [$(Database_Name)]
GO
-- =============================================
-- Author: Justin Samuel
-- Create date: 11-5-2013
-- Description:	Creation of config tables
-- =============================================

/********************* VARIABLES *******************************/
	DECLARE @FileName varchar(max)='';
	DECLARE @the_script varchar(max)

	DECLARE @xml xml;
	DECLARE @ServerName sysname;
	DECLARE @instanceName sysname;
	DECLARE @Backuplocation varchar(1000);
	DECLARE @user varchar(500);
	DECLARE @email varchar(500);
	DECLARE @Cur CURSOR;

	DECLARE @VersionNumber numeric(3,2) ='1.0';
	DECLARE @Folder varchar(256)= '00. Prerequisites';
	DECLARE @Option varchar(256)= 'New';
	DECLARE @Author varchar(256)= 'justin_samuel';
	DECLARE @Description VARCHAR(100)='Pre-Requisites'
	DECLARE @ReleaseDate datetime = '10/1/2013';
	DECLARE @DTNow DateTime2 = getdate();
/***************************************************************/

BEGIN TRY

	-- 1. Drop Objects
		SET @FileName = 'Dropping Objects'
		SELECT @the_script = REPLACE(REPLACE(REPLACE(Execution.BulkColumn,'ï»¿',''),'<Configuration_File>','$(Configuration_File)'),'<Database_Name>','$(Database_Name)')
		FROM OPENROWSET
		(
			BULK  '$(Working_Directory)\Objects\03. Drop_Objects.txt',
			SINGLE_CLOB 
		) Execution

		EXEC (@the_script);
	
	-- 2. Create tables
		SET @FileName = 'Creating Tables'
		SELECT @the_script = REPLACE(REPLACE(REPLACE(Execution.BulkColumn,'ï»¿',''),'<Configuration_File>','$(Configuration_File)'),'<Database_Name>','$(Database_Name)')
		FROM OPENROWSET
		(
			BULK  '$(Working_Directory)\Objects\04. Create_Tables.txt',
			SINGLE_CLOB 
		) Execution

		EXEC (@the_script);
		
	-- 3. Create Version Control Merge SP 
		SET @FileName = 'Creating Version Control Merge SP'
		SELECT @the_script =REPLACE(REPLACE(REPLACE(Execution.BulkColumn,'ï»¿',''),'<Configuration_File>','$(Configuration_File)'),'<Database_Name>','$(Database_Name)')
		FROM OPENROWSET
		(
			BULK  '$(Working_Directory)\Objects\05. Create_VersionControl_Merge.txt',
			SINGLE_CLOB 
		) Execution

		EXEC (@the_script);

	-- 3a. Backfilling the previous file
		SET @FileName = 'Backfill'
		EXEC Configuration.usp_VersionControl_Merge @VersionNumber = @VersionNumber, @ScriptName = '01. Server_Configuration.sql', @Author = @Author, @ObjectName ='Database', @Option = @Option, @Description = @Description, @ReleaseDate = @ReleaseDate, @isError = 0, @ErrorMsg = NULL
		EXEC Configuration.usp_VersionControl_Merge @VersionNumber = @VersionNumber, @ScriptName = '02. Create_SQL_profile_mail.sql', @Author = @Author, @ObjectName ='Database', @Option = @Option, @Description = @Description, @ReleaseDate = @ReleaseDate, @isError = 0, @ErrorMsg = NULL
		EXEC Configuration.usp_VersionControl_Merge @VersionNumber = @VersionNumber, @ScriptName = '03. Create_Database.sql', @Author = @Author, @ObjectName ='Database', @Option = @Option, @Description = @Description, @ReleaseDate = @ReleaseDate, @isError = 0, @ErrorMsg = NULL
	
		
	-- 4. Creating Version Control Get List SP 
		SET @FileName = 'Creating Version Control Get List SP'
		SELECT @the_script =REPLACE(REPLACE(REPLACE(Execution.BulkColumn,'ï»¿',''),'<Configuration_File>','$(Configuration_File)'),'<Database_Name>','$(Database_Name)')
		FROM OPENROWSET
		(
			BULK  '$(Working_Directory)\Objects\06. Create_VersionControl_GetList.txt',
			SINGLE_CLOB 
		) Execution

		EXEC (@the_script);

	-- 5. Create Schema DDL 
		SET @FileName = 'Creating Schema DDL Trigger'
		SELECT @the_script =REPLACE(REPLACE(REPLACE(Execution.BulkColumn,'ï»¿',''),'<Configuration_File>','$(Configuration_File)'),'<Database_Name>','$(Database_Name)')
		FROM OPENROWSET
		(
			BULK  '$(Working_Directory)\Objects\07. Create_Schema_DDL.txt',
			SINGLE_CLOB 
		) Execution

		EXEC (@the_script);

	-- 6. Create Email Notification
		SET @FileName = 'Creating Email Notification'
		SELECT @the_script =REPLACE(REPLACE(REPLACE(Execution.BulkColumn,'ï»¿',''),'<Configuration_File>','$(Configuration_File)'),'<Database_Name>','$(Database_Name)')
		FROM OPENROWSET
		(
			BULK  '$(Working_Directory)\Objects\08. Create_EmailNotification.txt',
			SINGLE_CLOB 
		) Execution

		EXEC (@the_script);

	-- 7. Create Server Instance
		SET @FileName = 'Creating Server Instance'
		SELECT @the_script =REPLACE(REPLACE(REPLACE(Execution.BulkColumn,'ï»¿',''),'<Configuration_File>','$(Configuration_File)'),'<Database_Name>','$(Database_Name)')
		FROM OPENROWSET
		(
			BULK  '$(Working_Directory)\Objects\09. Create_ServerInstance.txt',
			SINGLE_CLOB 
		) Execution

		EXEC (@the_script);

	-- 8. Create Server Instance Linkserver
		SET @FileName = 'Creating Server Instance Linkserver'
		SELECT @the_script =REPLACE(REPLACE(REPLACE(Execution.BulkColumn,'ï»¿',''),'<Configuration_File>','$(Configuration_File)'),'<Database_Name>','$(Database_Name)')
		FROM OPENROWSET
		(
			BULK  '$(Working_Directory)\Objects\10. Create_ServerInstance_LinkedServer_Configure.txt',
			SINGLE_CLOB 
		) Execution

		EXEC (@the_script);
	
	-- 09. Configure Server Instance
	-- 09a. Get XML information
		SELECT @Xml = CAST(BulkColumn AS XML)
		FROM OPENROWSET (BULK '$(Configuration_File)', SINGLE_BLOB) AS DATA;
	
	-- 09b. Declare Cursor for users
		SET @Cur = CURSOR FOR 
			SELECT
				t.c.value('@Server','NVARCHAR(256)') ,
				t.c.value('@Instance','NVARCHAR(256)') ,
				t.c.value('@Backuplocation','NVARCHAR(1000)')
			FROM @xml.nodes('/Root/InstancesConfiguration/PrimaryInstance') AS T(c)
			UNION
			SELECT
				t.c.value('@Server','NVARCHAR(256)') ,
				t.c.value('@Instance','NVARCHAR(256)') ,
				t.c.value('@Backuplocation','NVARCHAR(1000)')
			FROM @xml.nodes('/Root/InstancesConfiguration/SecondaryInstances/Instances/Database') AS T(c)

	-- 09c. Open Cursor
		OPEN @Cur
		
	-- 09d. Fetch
		FETCH NEXT FROM @Cur INTO @ServerName, @InstanceName, @Backuplocation

	-- 09e. Start loop
		WHILE @@FETCH_STATUS = 0
		BEGIN
			EXEC [Configuration].[usp_ServerInstance_Insert] @ServerName, @InstanceName, @Backuplocation;
			FETCH NEXT FROM @Cur INTO @ServerName, @InstanceName, @Backuplocation
		END

	-- 09f. Cleanup
		CLOSE @Cur;
		DEALLOCATE @Cur;	
			

	-- 09g. Declare Cursor for DBAdminEmails
		SET @Cur = CURSOR FOR 
			SELECT
				t.c.value('@User','NVARCHAR(500)') ,
				t.c.value('@Address','NVARCHAR(500)') 
			FROM @xml.nodes('/Root/MiscConfiguration/DBAdminEmails/Email') AS T(c)			

	-- 09h. Open Cursor
		OPEN @Cur
		
	-- 09i. Fetch
		FETCH NEXT FROM @Cur INTO @user, @email

	-- 09j. Start loop
		WHILE @@FETCH_STATUS = 0
		BEGIN
			
			INSERT INTO Configuration.t_AlertEmail (Name, EmailAddress)
			Values(@user, @email)

			FETCH NEXT FROM @Cur INTO @user, @email
		END

	-- 09k. Cleanup
		CLOSE @Cur;
		DEALLOCATE @Cur;	
			

	-- 10. Finally execute [Config].[usp_VersionControl_Merge] to fill in
		SET @FileName = 'Insert into Version Control'
		EXEC Configuration.usp_VersionControl_Merge @VersionNumber = @VersionNumber, @ScriptName = '$(File_Name)', @Author = @Author, @ObjectName ='Database', @Option = @Option, @Description = @Description, @ReleaseDate = @ReleaseDate, @isError = 0, @ErrorMsg = NULL

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
		
		IF OBJECT_ID('Configuration.usp_VersionControl_Merge') IS NOT NULL EXEC Configuration.usp_VersionControl_Merge @VersionNumber = @VersionNumber, @ScriptName = '$(File_Name)', @Author = @Author, @ObjectName ='Database', @Option = @Option, @Description = @Description, @ReleaseDate = @ReleaseDate, @isError = 1, @ErrorMsg = @ErrorMessage;
		RAISERROR (@ErrorMessage,16,1) WITH LOG;
END CATCH;
GO