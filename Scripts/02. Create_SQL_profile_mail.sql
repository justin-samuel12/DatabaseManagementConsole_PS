SET ANSI_NULLS, ANSI_PADDING, ANSI_WARNINGS, ARITHABORT, CONCAT_NULL_YIELDS_NULL, QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO
USE [master]
GO
-- =============================================
-- Create date: 11-5-2013
-- Description:	Installation of SQL Mail Configuration
-- =============================================

/**************************variables******************************/ 
	declare @xml XML;	
	declare @profile_name varchar(256);
	declare @account_name varchar(256);
	declare @email_address varchar(256);
	declare @description varchar(256);
	declare @display_name varchar(256);
	declare @replyto_address varchar(256);
	declare @mailserver_name varchar(256);
	declare @port int;
	declare @username varchar(256);
	declare @password varchar(256);
	declare @enable_ssl int;
	
	SELECT @Xml = CAST(BulkColumn AS XML)
	FROM OPENROWSET (BULK '$(Configuration_File)', SINGLE_BLOB) AS DATA;

	SELECT  @profile_name = ref.value ('(./MailConfig[@Name="profile_Name"])[1]/@Value' , 'nvarchar(256)'),
		@account_name = ref.value ('(./MailConfig[@Name="account_name"])[1]/@Value' , 'nvarchar(256)'),
		@email_address = ref.value ('(./MailConfig[@Name="email_address"])[1]/@Value' , 'nvarchar(256)'),
		@description = ref.value ('(./MailConfig[@Name="description"])[1]/@Value' , 'nvarchar(256)'),
		@replyto_address = ref.value ('(./MailConfig[@Name="replyto_address"])[1]/@Value' , 'nvarchar(256)'),
		@display_name = ref.value ('(./MailConfig[@Name="display_name"])[1]/@Value' , 'nvarchar(256)'),
		@mailserver_name = ref.value ('(./MailConfig[@Name="mailserver_name"])[1]/@Value' , 'nvarchar(256)'),
		@port = ref.value ('(./MailConfig[@Name="port"])[1]/@Value' , 'int'),
		@username = ref.value ('(./MailConfig[@Name="username"])[1]/@Value' , 'nvarchar(256)'),
		@password = ref.value ('(./MailConfig[@Name="password"])[1]/@Value' , 'nvarchar(256)'),
		@enable_ssl = ref.value ('(./MailConfig[@Name="enable_ssl"])[1]/@Value' , 'int')
	FROM @Xml.nodes('//Root/MiscConfiguration/DatabaseMail/Settings') as R(ref)	
/****************************************************************/ 
	BEGIN TRY;
		IF NOT ( @profile_Name is NULL )
			BEGIN
		-- 1. stop sysmail:
			EXECUTE MSDB..SYSMAIL_STOP_SP

		-- 2. initial cleanup:
		-- 2a. check if profile account exists, if so, delete
			IF EXISTS( SELECT * FROM MSDB.dbo.sysmail_profileaccount pa, msdb.dbo.sysmail_profile p, msdb.dbo.sysmail_account a
						WHERE pa.profile_id = p.profile_id AND pa.account_id = a.account_id AND 
							  p.name = @profile_name AND a.name = @account_name
					 )
				BEGIN
						PRINT 'Deleting Profile Account'
						EXECUTE msdb..SYSMAIL_DELETE_PROFILEACCOUNT_SP @PROFILE_NAME = @PROFILE_NAME, @ACCOUNT_NAME = @ACCOUNT_NAME
				END
 
 		-- 2b. check if profile exists, if so, delete
			IF EXISTS ( SELECT * FROM msdb.dbo.sysmail_profile p WHERE p.name = @profile_name )
				BEGIN
					  PRINT 'Deleting Profile.'
					  EXECUTE msdb..SYSMAIL_DELETE_PROFILE_SP @PROFILE_NAME = @PROFILE_NAME
				END

		-- 2c. check if account exists, if so, delete
			IF EXISTS( SELECT * FROM msdb.dbo.sysmail_account a WHERE a.name = @account_name )
			BEGIN
				  PRINT 'Deleting Account.'
				  EXECUTE msdb..SYSMAIL_DELETE_ACCOUNT_SP @ACCOUNT_NAME = @ACCOUNT_NAME
			END

		-- 3. setting up accounts & profiles for db mail:
		-- 3a. create a database mail account
			EXECUTE msdb.DBO.SYSMAIL_ADD_ACCOUNT_SP 
				@account_name = @account_name,
				@description = @description,
				@email_address = @email_address,
				@replyto_address = @replyto_address,
				@display_name = @display_name,
				@mailserver_name = @mailserver_name, -- smtp.xxxx.net
				@port = @port, -- or 25
				@username = @username, -- change to username, in this case, gmail uses the email address
				@password = 'pa$$w0rd1',
				@enable_ssl = @enable_ssl
 
		-- 3b. Create a Database Mail profile
			EXECUTE msdb.DBO.SYSMAIL_ADD_PROFILE_SP @PROFILE_NAME = @PROFILE_NAME, @DESCRIPTION = 'Profile used used dba e-mail.'
 
		-- 3c. Add the account to the profile
			EXECUTE msdb.dbo.SYSMAIL_ADD_PROFILEACCOUNT_SP @PROFILE_NAME = @PROFILE_NAME, @ACCOUNT_NAME = @ACCOUNT_NAME, @SEQUENCE_NUMBER =1
 
		-- 3d. Grant access to the profile to the DBMailUsers role
			EXECUTE msdb.DBO.SYSMAIL_ADD_PRINCIPALPROFILE_SP @PROFILE_NAME = @PROFILE_NAME, @PRINCIPAL_NAME = 'PUBLIC', @IS_DEFAULT = 1

		-- 4. start sysmail:
			EXECUTE msdb..SYSMAIL_START_SP

		END
	
	END TRY
	BEGIN CATCH
		-- 1. Raise Error
			DECLARE @ProcedureName		SYSNAME			= '$(File_Name)';
			DECLARE @ErrorMessageFormat	VARCHAR(8000)	= 'There was an error when executing the file: %s' + char(13) + 'Please see below for details' + char(13) + char(13) +
															'Error Message: %s' + char(13) + 
															'Error Severity: %i' + char(13) + 
															'Error State: %i' + char(13) + 
															'Error Number: %i';
			DECLARE @ErrorMessage		VARCHAR(MAX)	= FORMATMESSAGE(@ErrorMessageFormat, @ProcedureName, ERROR_MESSAGE() , ERROR_SEVERITY() ,ERROR_STATE(), ERROR_NUMBER ());	
			RAISERROR (@ErrorMessage,16,1) WITH LOG;
		
	END CATCH;

