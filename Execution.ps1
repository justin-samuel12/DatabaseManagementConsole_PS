Param( [string]$SelectionOption = "Create" )

##this sets the execution policy automatically
#Set-ExecutionPolicy -ExecutionPolicy Unrestricted

# Import the SQL Server Module.
Import-Module “sqlps” -DisableNameChecking
add-pssnapin sqlserverprovidersnapin100 -ErrorAction SilentlyContinue
add-pssnapin sqlservercmdletsnapin100 -ErrorAction SilentlyContinue
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")

#Clear contents 
Clear-History;
Clear-Host;

#Get the ID and security principal of the current user account
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
 
# Get the security principal for the Administrator role
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator
 
# Check to see if we are currently running "as Administrator"
if (!$myWindowsPrincipal.IsInRole($adminRole))
   {
   # We are not running "as Administrator" - so relaunch as administrator
   start-process PowerShell.exe -verb Runas -wait -argumentlist ('-File "'+$MyInvocation.MyCommand.Path+'"'), $SelectionOption
   
   #Exit from the current, unelevated, process
   $PID;
   stop-process -Id $PID;
   }

#region Log

Add-Type -TypeDefinition @"
   [System.Flags]
  	public enum LogLevel
    {
        Debug = 0x01,    /// <summary>debug-level</summary>
        Info = 0x02,    /// <summary>info-level</summary>
        Warn = 0x04,    /// <summary>warn-level</summary>
        Error = 0x08,    /// <summary>errorlevel</summary>
        User1 = 0x10,    /// <summary>user-defined level 1</summary>
        User2 = 0x20,    /// <summary>user-defined level 2</summary>
        All = 0xFF    /// <summary>all levels</summary>
    }
"@

Add-Type -TypeDefinition @"
   [System.Flags]
  	public enum LogType
    {
        log,            /// <summary>simple log</summary>
        txt,           /// <summary>text-formatted log</summary>
        xhtml_plain   /// <summary>xhtml-formatted log</summary>
    };
"@


function WriteToLogFile{
	param ( [string]$Message )
	
	# check to see if folder exists, if not create
	if ( -not (Test-Path $LogFolder) ) { New-Item -ItemType Directory -Force -Path $LogFolder };
	
	# since ps can't handle text delimited with outputting text file, have to use alternative method
	if ( -not (Test-Path $File) ) { [System.IO.File]::Create($File).Close(); WriteLogHeaderFooter 'Header'; }#create if not exists
	#Start-Sleep -Seconds 1;
	Add-Content -Path $File -Value ("$logLevel :`t`t`t" +(Get-Date).ToString("s") + "`t$Message");	 
    Write-Host $Message;
}
function WriteLogHeaderFooter{
	param([string]$selection)

	If ($selection -eq 'Header')
		{ $HeaderFooter ="//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
:: Log File for $SQLDatabaseName
:: Date Creation: " + (Get-Date).toString("D") + "
:: Powershell Version: " + (Get-PSVersion) + "
:: Executed by: " + [System.Security.Principal.WindowsIdentity]::GetCurrent().Name + "
:: Executed Machine: " + [System.Environment]::MachineName + "
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Level			Date			Event
-------------------	-------------------	---------------------------------------------------------------------------------------------------------"
		}
	Else {$HeaderFooter ="`r`n**********************************************************************************************************************************"
	}
	
	Add-Content -Path $File -Value $HeaderFooter
}

function WriteToLogFile_ArrayList{
	param ([string] $Title, [Array]$Data)
	$EventData = $null;
	
	# extracting all the elements from the array
	for ([int]$i = 0; $i -lt $Data.Count;$i++){ $EventData += ($i + 1).ToString() + ') ' + $Data[$i] + $MessageReturnChar + "`t";};
	$EventData = "$Title$MessageReturnChar" + "`t" + $EventData;
	WriteToLogFile $EventData.Trim();
}

function Get-PSVersion {
    if (test-path variable:psversiontable ) {$psversiontable.psversion} else {[version]"1.0.0.0"}
}


#endregion

#region Functionalities

function OnError{
	$logLevel = [loglevel]::Warn
	WriteToLogFile $ErrorMessage.Replace("|","$MessageReturnChar") ;     
	if ($FolderPath.Length -ne 0) {WriteToLogFile ("Execution failed while processing script: $FolderPath\$ScriptName")}
	WriteLogHeaderFooter 'Footer'
    PauseExecution
    exit;
}

function PauseExecution ($Message="Press any key to continue..."){
    Write-Host -NoNewLine $Message
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host ""
}

function SQLServerCheckServices( [string] $Service, [Boolean] $Override= $false ){
	$SqlStatus = $null;
	$SqlSrvName = "MSSQL$" +$Service;
	$SqlAgentSrvName = "SQLAgent$" +$Service ;
	$SqlSrvDisplayName = "SQL Server ($Service)";
	$SqlAgentSrvDisplayName = "SQL Server Agent ($Service)";
	
	#first check Server Name
	$SqlStatus = Get-Service | Where-Object {$_.DisplayName -eq "$SqlSrvDisplayName"} | select Status
	if ($SqlStatus -like '*Stopped*' -or $Override -eq $true)
		{
			WriteToLogFile ("Restart of SQL Server ($Service) service -- initiated" );
			Stop-Service -DisplayName $SqlSrvDisplayName -Force -Verbose;
			Start-Service -DisplayName $SqlSrvDisplayName -Verbose;
			Set-Service -Name $SqlSrvName -StartupType "Automatic" -Verbose; 
			WriteToLogFile ("Service status of " + $SqlSrvDisplayName + ": " + (Get-Service $SqlSrvDisplayName).status);
			WriteToLogFile ("Restart of SQL Server ($Service) service -- completed" );	
		} 
	
	#then check agent
	$SqlStatus = $null;
	$SqlStatus = Get-Service | Where-Object {$_.DisplayName -eq "$SqlAgentSrvDisplayName"} | select Status
	if ($SqlStatus -like '*Stopped*' -or $Override -eq $true)
		{
			WriteToLogFile ("Restart of SQL Server Agent ($Service) service -- initiated" );
			Stop-Service -DisplayName $SqlAgentSrvDisplayName -Force -Verbose;
			Start-Service -DisplayName $SqlAgentSrvDisplayName -Verbose;
			Set-Service -Name $SqlAgentSrvName -StartupType "Automatic" -Verbose; 
			WriteToLogFile ("Service status of " + $SqlAgentSrvDisplayName + ": " + (Get-Service $SqlAgentSrvDisplayName).status);
			WriteToLogFile ("Restart of SQL Server Agent ($Service) service -- completed" );	
		} 
}


function GetSQLMaxMemory(){
    $mem = Get-WMIObject -class Win32_PhysicalMemory | Measure-Object -Property capacity -Sum 
    $memtotal = ($mem.Sum / 1MB);
    $min_os_mem = 2048 ;
    if ($memtotal -le $min_os_mem) {Return $null;}
    $sql_mem = $memtotal * 0.8 ;
    $sql_mem -= ($sql_mem % 1024) ;  
    return $sql_mem ;
}

function SetSQLInstanceMemory ( [string]$SQLInstanceName, [int]$maxMem = $null, [int]$minMem = $null ) {
	try {
			WriteToLogFile ("Setting Min/Max Memory for server -- initiated" );
			
			[reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
			$srv = new-object Microsoft.SQLServer.Management.Smo.Server($SQLInstanceName)
			$srv.ConnectionContext.LoginSecure = $true

			$srv.Configuration.MaxServerMemory.ConfigValue = $maxMem
			$srv.Configuration.MinServerMemory.ConfigValue = $minMem

			$srv.Configuration.Alter()
			
			WriteToLogFile ("Setting Min/Max Memory for server -- completed" );
		}
	catch 
		{ 
			$ErrorMessage =  [System.Exception]$_.Exception.Message;
			OnError;
		}
}

function ExecuteScripts ( [string]$Script, [string]$ScriptFullName, [System.Object]$Variables ) {
	
try {				
	$error.Clear();
	[string]$ErrorMessage=$null;
	
	$ContentsVariable = @();
	$ContentsVariable = $Variables ;
	$ContentsVariable += "File_Name=" + $Script;
	
	[Boolean]$isError = $false;	
	WriteToLogFile ( $Script + " -- starting!")
					
	#execute
	Invoke-Sqlcmd -ServerInstance $SQLExecutedOn -database master -InputFile $ScriptFullName -QueryTimeout 1200 -Variable $ContentsVariable -OutputSqlErrors $true -ErrorAction Stop -Verbose 

	if ($error.count -gt 0)  {$ErrorMessage = $error;  $isError = $true; OnError;  } 
	else {	WriteToLogFile ( $Script + " -- completed successful!")  };	
	}
catch { 
	$isError = $true;
	$ErrorMessage = [System.Exception]$_.Exception.Message; 
	OnError;
	}
}

#endregion

#Region Executables

function Main-Process{

	$ErrorActionPreference = "Stop" #stop after first error
	######################################################## VARIABLES ############################################################
	# initialize the items variable with the contents of a directory
	$CurrentDirectory = Split-Path $script:MyInvocation.MyCommand.Path;
	$ConfigurationFile= $CurrentDirectory.ToString()+'\Configuration.xml';
	$XMLContentsVariables = @();
	$MessageReturnChar = "`r`n`t`t`t`t`t`t";
	$SQLDatabaseName = "DatabaseManagementConsole";
	$LogFolder = $CurrentDirectory.ToString() + '\Logs\';	
	$File = $LogFolder + $SQLDatabaseName + '_'  + (Get-Date).ToString("yyyy_MM_dd") + '.' + [LogType]::Log;	
	################################################################################################################################
	# 1. check to see if folder exists
		$CurrentDirectory =  "$CurrentDirectory\Scripts";
		if ( -not ( Test-Path $CurrentDirectory )) {
			$ErrorMessage ="Scripts folder does not exists. Cannot continue without script folder. Exiting now..."+ $MessageReturnChar + 
							"Please ensure folder exists and scripts are in the folder before executing again.";
			OnError 
		};
		
	# 2. check to see if configuration file exists. If not, error out and quit
		if ( -not ( Test-Path $ConfigurationFile )) {
			$ErrorMessage ="Configuration file does not exist. Exiting now..."+ $MessageReturnChar + 
							"Please have configuration file before executing again";
			OnError
		};	
	
	# 3. set location and scripts array
		Set-Location $CurrentDirectory
		$Scripts = Get-ChildItem $CurrentDirectory -Filter *.sql ;		
			
	# 4. create Log. If user selects create, recreate the log file.
		if ( $SelectionOption -eq 'Create' ){if (Test-Path $File){Remove-Item $File;} }
		$logLevel = [LogLevel]::Info;
		WriteToLogFile ('Scripts directory location: ' + $CurrentDirectory);
		WriteToLogFile ('User selection: ' + $SelectionOption);
		
	# 5. get the data from xml
		$ConfigurationXML = [xml](get-content $ConfigurationFile)
		$SQLServerName = if ( $ConfigurationXML.Root.InstancesConfiguration.PrimaryInstance.Server.Length -eq 0 ) { "." } ELSE { $ConfigurationXML.Root.InstancesConfiguration.PrimaryInstance.Server };
		$SQLInstance = $ConfigurationXML.Root.InstancesConfiguration.PrimaryInstance.Instance;
		$ClusteredOrStandAlone = New-Object Microsoft.SqlServer.Management.Smo.Server("$SQLServerName\$SQLInstance");
		$SQLExecutedOn = "$SQLServerName\$SQLInstance";
				
	# 6. write type of change (Create / Update) on this instance
		WriteToLogFile ("$SelectionOption on Instance: $SQLExecutedOn")
	
	# 7. write type of change (Create / Update) for this database
		WriteToLogFile ("$SelectionOption for Database: $SQLDatabaseName")
		
	# 8. loop thru different subs in the configuration file
		# 8a. Folders
			$nodeinfo=@();
			foreach ($node in $ConfigurationXML.Root.DMCConfiguration.DMCDatabaseFolders.Folder.file){
				$Folder = $node.Location -replace '\\','\';
				if ( -not ( Test-Path -path "$Folder" )) { New-Item "$Folder" -item directory }; # if folder doesn't exists, create
				$nodeinfo += $node.Name + ' = ' + $Folder 					
			};
			$XMLContentsVariables +=$nodeinfo;
			# only write if creating
			if ( $SelectionOption -eq 'Create' ) { WriteToLogFile_ArrayList -Title '--- Folder Information ----' -Data $nodeinfo;}

		# 8b. Configurations
			if ($ConfigurationXML.Root.DMCConfiguration.DMCDatabaseProperties.Properties.Property){ 
				$nodeinfo=@();	
				
				foreach ($node in $ConfigurationXML.Root.DMCConfiguration.DMCDatabaseProperties.Properties.Property) { 
					$nodeinfo += $node.Name + ' = ' + $node.Value ;
				};
			$XMLContentsVariables +=$nodeinfo;
			if ( $SelectionOption -eq 'Create') { WriteToLogFile_ArrayList -Title '--- Database Configuration ----' -Data $nodeinfo; }
			}

		# 8c. Server Configuration -- optional only if option is for installation
			if ($ConfigurationXML.Root.ServerConfiguration.ServerOptions.Options.Option){
					if ( $SelectionOption -eq 'Create' ) { WriteToLogFile ("---- Server Configuration ----$MessageReturnChar" + "`tWill be executing all the contents in the Server Configuration node"); }
			}

	# 9. Add Database plus the working directory onto the $XMLContentsVariables 
		$XMLContentsVariables += "Database_Name="+ $SQLDatabaseName;
	    $XMLContentsVariables += "Working_Directory=" + $CurrentDirectory;
		$XMLContentsVariables += "Configuration_File=" + $ConfigurationFile;
		#PauseExecution;		
			
	# 10. combining both installation and upgrade into one powershell script with separate functions
		if ( $SelectionOption -eq 'Create' ) { Create; } Else { Update };

}

function Create{
	# 1. Loop thru each file	
		ForEach ( $script in $Scripts ) { ExecuteScripts -Script $script -ScriptFullName "$CurrentDirectory\$script" -Variables $XMLContentsVariables }
		
	# 2. Setting Min/Max Memory for SQL instance. Rule of thumb, set max to 80% of total ram
		$maxRam = GetSQLMaxMemory
		if ( $maxRam -ne $null)
		{
			WriteLogHeaderFooter 'Footer'
			SetSQLInstanceMemory -SQLInstanceName $SQLExecutedOn -maxMem $maxRam -minMem 1024
		}
	
		# 3. Restarting SQL Services
		if ($ClusteredOrStandAlone.IsClustered -notlike "*True*") {	
			WriteLogHeaderFooter 'Footer';
			SQLServerCheckServices -Service $SQLInstance -Override $true;
			}
				
	# 4. Completion
		WriteLogHeaderFooter 'Footer'
		PauseExecution;
}

function Update{

	# 1. Validate database exists before proceeding with update process
		$null = [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")# we set this to null so that nothing is displayed
		$server = new-object ("Microsoft.SqlServer.Management.Smo.Server") $SQLExecutedOn
		if (($null -eq $server.Databases[$SQLDatabaseName]) -or ($null -eq $server.Databases[$SQLDatabaseName].Tables.Item("t_VersionControl", "Configuration")))
		{
			$SelectionOption ="Create";
			Write-Host "$SQLDatabaseName does not exists. Will proceed with Creation process.....";
			PauseExecution;
			Main-Process;
		 	exit;
		}
	
	#2. Loop thru to get list of all files
	#Create Table and columns
		$FileListDataTable = New-Object System.Data.DataTable "Scripts_Table"; 
		$FileListDataColumn1 = New-Object System.Data.DataColumn Id,([int]);
		$FileListDataColumn2 = New-Object System.Data.DataColumn ScriptName,([string]);
		$FileListDataColumn3 = New-Object System.Data.DataColumn FullFilePath,([string]);
		$FileListDataTable.Columns.Add( $FileListDataColumn1 );
		$FileListDataTable.Columns.Add( $FileListDataColumn2 );
		$FileListDataTable.Columns.Add( $FileListDataColumn3 );
						
		$rowNum = 1;		
		ForEach ( $script in $Scripts )
		{
			$row = $FileListDataTable.NewRow();
			$row.Id = $rowNum;
			$row.FullFilePath = "$CurrentDirectory\$script";
			$row.ScriptName = $script.Name;
			$FileListDataTable.Rows.Add($row);
			$rowNum++;				
		}
	
	# 3. Get list of files to be executed via SQL
		try{
	
			# Connection and StoredProc Info
			$ConnectionString = "Data Source=$SQLExecutedOn;Initial Catalog=$SQLDatabaseName;Integrated Security=SSPI;" 
			$StoredProc = 'Configuration.usp_VersionControl_GetList'; 
			
			# Connect
			$SqlConnection = new-object System.Data.SqlClient.SqlConnection $ConnectionString	
			$SqlConnection.Open();
			
			# Create Sqlcommand type and params
			$SqlCommand = new-object System.Data.SqlClient.SqlCommand
			$SqlCommand.Connection = $ConnectionString
			$SqlCommand.CommandType = [System.Data.CommandType]"StoredProcedure"
			$SqlCommand.CommandText= $StoredProc
			$null = $SqlCommand.Parameters.Add("@VersionControlTable", [System.Data.SqlDbType]::Structured)
			$SqlCommand.Parameters["@VersionControlTable"].Value = $FileListDataTable
			
			# Create and fill dataset
			$SqlDataset = new-object System.Data.Dataset
			$SqlDataAdapter = new-object System.Data.SqlClient.SqlDataAdapter ($SqlCommand)
			$null = $SqlDataAdapter.fill($SqlDataset)
			$SqlConnection.Close()
		}
		catch [System.Exception] {
			$ErrorMessage = $_.Exception.Message; 
		    $SqlConnection.Close();
		  	OnError;
		}		
			
	# 4. Check if there is any new updates		
	if ( $SqlDataset.Tables[0].Rows.Count -eq '0' )
	{
		WriteToLogFile ('There are no new updates at this time....')
		WriteLogHeaderFooter 'Footer'
		PauseExecution;	
	}
	else
	{
		foreach ( $TableRows in $SqlDataset.Tables[0].Rows ){ ExecuteScripts -Script $TableRows.ScriptName -ScriptFullName $TableRows.FullFileName -Variables $XMLContentsVariables	}
				
	# 3. Restarting SQL Services
		if ($ClusteredOrStandAlone.IsClustered -notlike "*True*") {	
			WriteLogHeaderFooter 'Footer';
			SQLServerCheckServices -Service $SQLInstance -Override $false;
			}	
		
	# Completion
		WriteLogHeaderFooter 'Footer'
		PauseExecution;	
		exit;			
	}
}
#endregion

Main-Process #execute process