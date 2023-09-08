# Enable machine to download modules
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Install-PackageProvider -Name "Nuget" -RequiredVersion "2.8.5.201" -Force
Import-PackageProvider -Name "Nuget" -RequiredVersion "2.8.5.201" -Force
Install-Module SQLServer -Force -AllowClobber
Import-Module SQLServer -Force

# Variable to Change
$SQLSaUser = "${sql_sa_user}"
$SQLSaPassword = "${sql_sa_password}"
$SQLInstallationFolder = "${sql_installation_folder}"
$SQLSourceEdition = "*${sql_source_edition}*"

# Variables no need to change
$CopySystemFileLocation = "C:\Windows\Temp"
$pendingRebootTests = @(
    @{
        Name     = 'RebootPending'
        Test     = { Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing'  -Name 'RebootPending' -ErrorAction Ignore }
        TestType = 'ValueExists'
    }
    @{
        Name     = 'RebootRequired'
        Test     = { Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update'  -Name 'RebootRequired' -ErrorAction Ignore }
        TestType = 'ValueExists'
    }
    @{
        Name     = 'PendingFileRenameOperations'
        Test     = { Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction Ignore }
        TestType = 'NonNullValue'
    }
)
foreach ($test in $pendingRebootTests) {
    $result = Invoke-Command -ScriptBlock $test.Test
    if ($test.TestType -eq 'ValueExists' -and $result) {
        Write-Host "Reboot Required, restart after rebooting server"
        Throw
    }
    elseif ($test.TestType -eq 'NonNullValue' -and $result -and $result.($test.Name)) {
        Write-Host "Reboot Required, restart after rebooting server"
        Throw
    }
    else {
        Write-Host "No pending Reboot, proceeding with next check"
    }
}

# Find No. of SQL Instances Installed
$TotalInstances = Get-Service | Where-Object { $_.DisplayName -like "SQL Server (*" } | Measure-Object
If ($TotalInstances.Count -gt 1) {
    Write-Host "Multiple SQL Instances are Installed on this Server. Not supported at this time" -Color Red
    Throw
}
elseif ($TotalInstances.Count -eq 0) {
    Write-Host "SQL is not installed on this machine" -Color Red
    Throw
}

# Check Whether Enterprise Edition is installed or not
$InstanceName = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server').InstalledInstances
$InstanceID = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL' -Name $InstanceName
$Edition = Get-ItemPropertyValue -Path ("HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\" + $InstanceID + "\Setup") -Name 'Edition'
$Port = Get-ItemPropertyValue -Path ("HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\" + $InstanceID + "\MSSQLServer\SuperSocketNetLib\Tcp\IPAll") -Name "TcpPort"
$InstanceName | Out-File -FilePath C:\Windows\temp\InstanceName.txt
if ($InstanceName -eq 'MSSQLSERVER') {
    $SQLInstanceName = "localhost"
    Write-Host $SQLInstanceName
}
else {
    $SQLInstanceName = "localhost\" + $InstanceName #+','+ $Port
    Write-Host $SQLInstanceName
}
if ($Edition -notlike $SQLSourceEdition) {
    Write-Host "It's not $SQLSourceEdition Edition. No Need to run script to downgrade"
    Throw
}
else {
    Write-Host "Checking whether SQL is running or not"
}


$ConnectionString = "Server= $SQLInstanceName;Database=Master;User Id = $SQLSaUser;Password = $SQLSaPassword;TrustServerCertificate=True"
$timeStamp = Get-Date -format yyyy_MM_dd_HHmmss

#Check if SQL Server is running
$InstanceService = Get-Service | Where-Object { $_.DisplayName -like "SQL Server (*" }
$status = get-service $InstanceService.Name | select Status
if ($status.Status -eq "Running") {
    Write-Host "SQLServer is Running"
}
else {
    Write-Host "SQL Server is not running"
    Throw
}
Try {
    #Check if SQL Server is Clustered or not
    [array]$Clustered = Invoke-Sqlcmd -ConnectionString $ConnectionString -Query "select  SERVERPROPERTY('IsClustered') as IsClustered,SERVERPROPERTY('IsHadrEnabled') as IsHadrEnabled" -ErrorAction stop
}
Catch {
    Write-Host ($Error[0].Exception)
    Throw
}
if ($Clustered.isClustered -eq 1 -or $Clustered.IsHadrEnabled -eq 1) {
    Write-Host "SQL is clustered or Part of Always on Availability Groups. Not supported at this time" -Color Red
    Throw
}
#GET DB File Location (we are getting this info, Uninstalling SQL will not remove tempdb files if they are in custom location)
[array]$TempDBFileLocation = Invoke-Sqlcmd -ConnectionString $ConnectionString  -Query "USE tempdb;
                                                    SELECT
                                                      physical_name
                                                    FROM sys.database_files;"
$TempDBFileLocation.physical_name
$userdbfilepath = "C:\windows\temp" + '\userdatabase_path.csv'
$SQLPathCOMMAND = "SET NOCOUNT ON
             DECLARE    @cmd        VARCHAR(MAX),
                        @dbname     VARCHAR(200),
                        @prevdbname VARCHAR(200)
             SELECT @cmd = '', @dbname = ';', @prevdbname = ''
             CREATE TABLE #Attach (Seq INT IDENTITY(1,1) PRIMARY KEY,
                                     dbname     SYSNAME NULL,
                                     fileid     INT NULL,
                                     filename   VARCHAR(1000) NULL,
                                     TxtAttach  VARCHAR(MAX) NULL
                                    )
             INSERT INTO #Attach
             SELECT
                DISTINCT DB_NAME(dbid) AS dbname, fileid, filename, CONVERT(VARCHAR(MAX),'') AS TxtAttach
             FROM master.dbo.sysaltfiles
             WHERE dbid IN (SELECT dbid FROM master.dbo.sysaltfiles )
             AND DATABASEPROPERTYEX( DB_NAME(dbid) , 'Status' ) = 'ONLINE'
             AND DB_NAME(dbid) NOT IN ('master','tempdb','msdb','model')
             ORDER BY dbname, fileid, filename
             UPDATE #Attach
             SET @cmd = TxtAttach =
             CASE WHEN dbname <> @prevdbname
             THEN CONVERT(VARCHAR(200),'exec sp_attach_db @dbname = N''' + dbname + '''')
             ELSE @cmd
             END +',@filename' + CONVERT(VARCHAR(10),fileid) + '=N''' + filename +'''',
             @prevdbname = CASE WHEN dbname <> @prevdbname THEN dbname ELSE @prevdbname END,
             @dbname = dbname
             FROM #Attach  WITH (INDEX(0),TABLOCKX)
             OPTION (MAXDOP 1)
             SELECT dbname,TxtAttach
             from
             (SELECT dbname, MAX(TxtAttach) AS TxtAttach FROM #Attach
             GROUP BY dbname) AS x
             DROP TABLE #Attach
             GO"
$userdbpathoutput = invoke-sqlcmd -ConnectionString $ConnectionString   -query $SQLPathCOMMAND | Export-Csv -Path $userdbfilepath -NoTypeInformation
$systemfiles = Invoke-sqlcmd -ConnectionString $ConnectionString  -Query "select filename from sysaltfiles where dbid in (1,3,4)"
$InstanceService = (Get-Service | Where-Object { $_.DisplayName -like "SQL Server (*" })

# Stop dependencies.
Get-Service -Name $InstanceService.Name -DependentServices | Stop-Service

# Stop SQL
Get-Service -Name $InstanceService.Name | Stop-Service
Write-Host "SQL Service has been stopped"

$files = $systemfiles.filename
foreach ($file in $files) {
    Copy-Item -Path $file -Destination $CopySystemFileLocation -Force
}

#Setup File Location
$setupfileLocation = Get-ChildItem -Recurse -Include setup.exe -Path "$env:ProgramFiles\Microsoft SQL Server" -ErrorAction SilentlyContinue |
Where-Object { $_.FullName -match 'Setup Bootstrap\\SQL' -or $_.FullName -match 'Bootstrap\\Release\\Setup.exe' -or $_.FullName -match 'Bootstrap\\Setup.exe' } |
Sort-Object FullName -Descending | Select-Object -First 1
$DirectoryName = $setupfileLocation.DirectoryName
Write-Host "SQL Uninstallation Started"
#$InstanceName="MSSQLSERVER"

$Path = $DirectoryName ###############################################PARAMETER 2 for Features#####################################
$action = "/ACTION=""unInstall"" /QS /FEATURES=SQL,AS,RS,IS,Tools /INSTANCENAME=""$InstanceName"""
Start-Process -WorkingDirectory $Path setup.exe  $action -Verb runAs -Wait

#Delete Orphan tempdb files
foreach ($file in $TempDBFileLocation.physical_name) {
    Remove-Item  $file -Force
    Write-Host "$file is removed"
}
$SQLErrorLogFile = Split-Path $setupfileLocation.DirectoryName
$SQLErrorLogFileLocation = $SQLErrorLogFile + "\Log\Summary.txt"
$CheckError = Select-String -Path $SQLErrorLogFileLocation -Pattern "Failed: see details below"
if ([string]::IsNullOrWhiteSpace($CheckError)) {
    Write-Host "SQL Uninstalled Successfully"
    Restart-Computer -Force
}
else {
    Write-Host "SQL Uninstallation failed"
    Throw
}