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
	DECLARE @ObjectName varchar(256) = 'Collector.usp_Maintenance_Backups_DeleteFolderContents';
	DECLARE @Description VARCHAR(100)='Creation of stored procedure: '+ @ObjectName;
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
-- Description:	Delete backup files   
-- =============================================
CREATE PROCEDURE ' + @ObjectName + '
	@DaysToRetain INT = 4 -- how many days back to start deletion (default is to keep 4 days).
AS
BEGIN
	SET NOCOUNT ON; SET XACT_ABORT ON;
/*********************************************** VARIABLES *********************************************************************************/
	DECLARE @DateToRemove				DateTime =  DATEADD(DAY, DATEDIFF(DAY, 0 , GETDATE()) - @DaysToRetain,0 ); -- actual date
	DECLARE @Backupfolderlocation		VARCHAR(100) = [Configuration].[svfn_DefaultFolderLocation_Get](''BackupDirectory''); -- backupfolder local
	DECLARE @Command					VARCHAR(256) = ''DIR "''+ @Backupfolderlocation + ''" /B /T:C'';
	DECLARE @SQL						NVARCHAR(4000) = NULL;
	DECLARE @RC							INT;
	DECLARE @Tmp						TABLE (returnval NVARCHAR(1000), rownum INT IDENTITY(1,1));
	DECLARE @DirectoryName				NVARCHAR(1000);
	DECLARE @DirectoryLoopCounter		INT = 1;
	DECLARE @DirectoryFilesTotalCount	INT = 0;
	DECLARE @FileDetails				TABLE
											(
												Name             VARCHAR(500), --File Name and Extension
												[Path]           VARCHAR(500), --Full path including file name
												DateCreated      DATETIME,     --Date file was created
												DateLastAccessed DATETIME,     --Date file was last read
												DateLastModified DATETIME,     --Date file was last written to
												Attributes       INT,          --Read only, Compressed, Archived
												ArchiveBit       AS CASE WHEN Attributes&  32=32   THEN 1 ELSE 0 END,
												CompressedBit    AS CASE WHEN Attributes&2048=2048 THEN 1 ELSE 0 END,
												ReadOnlyBit      AS CASE WHEN Attributes&   1=1    THEN 1 ELSE 0 END,
												Size             INT,          --File size in bytes
												[Type]           VARCHAR(100)  --Long Windows file type (eg.''Text Document'',etc)
											);

	IF OBJECT_ID(''TempDB..#DirectoryFilesInformaton'') IS NOT NULL BEGIN DROP TABLE #DirectoryFilesInformaton END;
	CREATE TABLE #DirectoryFilesInformaton (RowNum INT IDENTITY(1,1), Name VARCHAR(500) PRIMARY KEY CLUSTERED, Depth  BIT, IsFile BIT)					
/****************************************************************************************************************************************/
	-- 1. Populate Temp Table with the contents of the outfiles directory
		INSERT @tmp EXEC master..xp_cmdshell @Command
	
	-- 2. Remove any unwanted data
		DELETE FROM @tmp where returnval is null;
	
	-- 3. Loop thru each directory and get data
		WHILE @DirectoryLoopCounter <= ( SELECT COUNT( Rownum ) FROM @tmp )
			BEGIN
				DECLARE @ObjFile		  INT;				  --File object
				DECLARE @ObjFileSystem	  INT;				  --File System Object  
				DECLARE @Attributes       INT		   = 0	  --Read only, Hidden, Archived, etc, as a bit map
				DECLARE @DateCreated      DATETIME			  --Date file was created
				DECLARE @DateLastAccessed DATETIME			  --Date file was last read (accessed)
				DECLARE @DateLastModified DATETIME			  --Date file was last written to
				DECLARE @Name             VARCHAR(500) = NULL --File Name and Extension
				DECLARE @Path             VARCHAR(500) = NULL --Full path including file name
				DECLARE @Size             INT          = 0	  --File size in bytes
				DECLARE @Type             VARCHAR(100) = NULL --Long Windows file type (eg.''Text Document'',etc)
				DECLARE @CurrentFileName  VARCHAR(500);
				DECLARE @FileCount		  INT		   = 0; 
				DECLARE @FileLoopCounter  INT          = 1;		
				SELECT @DirectoryName = @Backupfolderlocation + Returnval +''\'' FROM @tmp WHERE rownum = @DirectoryLoopCounter;
				-- create temp table to get all files for current dir
				INSERT INTO #DirectoryFilesInformaton (Name, Depth, IsFile) EXEC Master.dbo.xp_DirTree @DirectoryName,1,1; -- get all files for that directory
				SET @FileCount = @@ROWCOUNT;				
				--=================================================================================================
				--      Get the properties for each file.  This is one of the few places that a WHILE
				--      loop is required in T-SQL.
				--=================================================================================================
				--===== Create a file system object and remember the "handle"
				EXEC dbo.sp_OACreate ''Scripting.FileSystemObject'', @ObjFileSystem OUT
					WHILE @FileLoopCounter <= @FileCount
						BEGIN
							SELECT @CurrentFileName = @DirectoryName + name FROM #DirectoryFilesInformaton WHERE RowNum = @FileLoopCounter and IsFile = 1;
							--===== Create an object for the path/file and remember the "handle"
							EXEC dbo.sp_OAMethod @ObjFileSystem,''GetFile'', @ObjFile OUT, @CurrentFileName
                
							--===== Get the all the required attributes for the file itself
							EXEC dbo.sp_OAGetProperty @ObjFile, ''Path'',             @Path             OUT
							EXEC dbo.sp_OAGetProperty @ObjFile, ''Name'',             @Name             OUT
							EXEC dbo.sp_OAGetProperty @ObjFile, ''DateCreated'',      @DateCreated      OUT
							EXEC dbo.sp_OAGetProperty @ObjFile, ''DateLastAccessed'', @DateLastAccessed OUT
							EXEC dbo.sp_OAGetProperty @ObjFile, ''DateLastModified'', @DateLastModified OUT
							EXEC dbo.sp_OAGetProperty @ObjFile, ''Attributes'',       @Attributes       OUT
							EXEC dbo.sp_OAGetProperty @ObjFile, ''Size'',             @Size             OUT
							EXEC dbo.sp_OAGetProperty @ObjFile, ''Type'',             @Type             OUT
        
							--===== Insert the file details into the return table        
							INSERT @FileDetails ([Path], Name,  DateCreated, DateLastAccessed, DateLastModified, Attributes, Size, [Type])
							SELECT @Path, @Name,@DateCreated, @DateLastAccessed,@DateLastModified,@Attributes,@Size,@Type

							-- set Total count
							SET @FileLoopCounter +=1
						END;
							
					--===== House keeping, destroy and drop the file objects to keep memory leaks from happening
					   TRUNCATE TABLE #DirectoryFilesInformaton;				
					   EXEC sp_OADestroy @ObjFileSystem
					   EXEC sp_OADestroy @ObjFile
			SET @DirectoryLoopCounter +=1
		END;

		-- 4. loop thru to delete files
		DELETE FROM @FileDetails where @DateToRemove < @DateCreated -- delete all irrvelant files that are not to be deleted
		DECLARE @t_FilesToDelete TABLE ( RowNum INT IDENTITY(1,1) PRIMARY KEY CLUSTERED, FullFileName NVARCHAR(4000))
		INSERT @t_FilesToDelete (FullFileName) SELECT Path FROM @FileDetails
		SET @DirectoryFilesTotalCount = @@ROWCOUNT;
				
		IF ( @DirectoryFilesTotalCount > 0 )
			BEGIN
				SET @DirectoryLoopCounter = 1;
				WHILE @DirectoryLoopCounter <= @DirectoryFilesTotalCount
					BEGIN
						SELECT @CurrentFileName = FullFileName from @t_FilesToDelete Where RowNum = @DirectoryLoopCounter;
						SET @SQL =''''; -- reuse the @sql variable 
						SET @SQL = ''DEL "'' + @CurrentFileName + ''" /F /Q''  

						EXECUTE @RC = master.dbo.xp_cmdshell @SQL 
										
						IF @rc <> 0 
							BEGIN 
								RAISERROR (''Error deleting file:  %s'', 16, 1, @CurrentFileName);		
								RETURN;
							END

						SET @DirectoryLoopCounter +=1
					END;
			END;		
		-- 5. Delete from Backupset tables / msdb backupset
		DELETE FROM [Collector].[t_Backupset] WHERE DATEADD(DAY, DATEDIFF(DAY, 0 , CreateDatetime),0 ) <= @DateToRemove;
		DELETE FROM [Collector].[t_BackupsetOperation] WHERE DATEADD(DAY, DATEDIFF(DAY, 0 , CreateDatetime),0 ) <= @DateToRemove;
		DELETE FROM [Collector].[t_BackupsetRestoreScripts] WHERE DATEADD(DAY, DATEDIFF(DAY, 0 , CreateDatetime),0 ) <= @DateToRemove;
		
		EXEC MSDB..SP_DELETE_BACKUPHISTORY @DateToRemove;
END		
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
