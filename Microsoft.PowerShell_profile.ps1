$major = $PSVersionTable.PSVersion.Major
$minor = $PSVersionTable.PSVersion.Minor
Write-Host "Loading profile for PowerShell $major.$minor" 

# Aliases
Set-Alias npp ${env:ProgramFiles(x86)}\Notepad++\notepad++.exe
Set-Alias ILMerge ${env:ProgramFiles(x86)}\Microsoft\ILMerge\ILMerge.exe
Set-Alias ildasm "${env:ProgramFiles(x86)}\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.6 Tools\ildasm.exe"
Set-Alias nuget "${env:ProgramFiles(x86)}\Nuget\nuget.exe"
Set-Alias nimbleText "${env:ProgramFiles(x86)}\NimbleText\NimbleText.exe"

# Global variables
$tsqlBackupsLocation = "$mydocs\Customer DBs"
$tsqlAutomaticBackupLocation = "$tsqlBackupsLocation\Automatic backups"

# Reload profile
function Reload-Profile() {
  # This is just . $profile, but at the moment I won't remember that
  . $profile
  Write-Host "May not pick up changes for existing functions, try re-launching PowerShell"
}

function Help-Me() {
  # This is for when I forget/trying to learn stuff
  Write-Host "To see what methods and properties an cmdlet has do this"
  Write-Host "Get-Service | Get-Member"
  Write-Host ""
  Write-Host ""
}

# SQL Server functionality
function Tsql ($query) {
  sqlcmd -S 127.0.0.1\SQLEXPRESS -d VMS_DevConfig -Q $query
}

function Tsql-Open-Backups() {
  explorer $tsqlBackupsLocation
}

function Tsql-Restore-Backup ($backup) {
  $performRestore = $TRUE # Could just use $backup and check for null/empty, but good to have a boolean example in here
  $reason = ""
  
  # Check if database exists, don't restore if already exists
  if (!($queryResults -contains "VMS_DevConfig")) {
    # If no parameter is passed in then look at the automatic backups
	if ([string]::IsNullOrEmpty($backup)) {
	  # No backup file supplied, list the most recent backups in the automatic backup folder
      # prompt which one (by number) to restore
	  Write-Host "Select a backup"
      $files = Get-ChildItem -Path $tsqlAutomaticBackupLocation | Sort-Object LastWriteTime -descending | Select-Object -first 10
	  [int]$fileCount = 1
      ForEach ($f in $files) {
	    Write-Host "$fileCount $f"
		$fileCount++
	  }
	  $filesLength = $files.Length
      [int]$val = Read-Host "Enter 1 to $filesLength to restore most recent backup" # Add error handling for non-ints later
	  
      if (($val -ge 1) -and ($val -le $filesLength)) {
        $file = $files[$val - 1]
        $backup = "$tsqlAutomaticBackupLocation\" + $file.Name
		$performRestore = $TRUE
      }
      else {
        $reason = "no valid backup selected"
		$performRestore = $FALSE
      }
	}
  }
  else {
    $reason = "database already exists - delete it first"
	$performRestore = $FALSE
  }
  
  if ($performRestore -eq $TRUE) {
    Write-Host "Restoring " $backup
    	
    # If the backup is an old version that stored the ldf & mdf in Program Files then we need to explicitly move it to C:\ProgramData\Titan\Database
    # SQL Server Server Management Studio does this bit automatically under the bonnet!
	
    $query = "SELECT name FROM master..sysdatabases WHERE name <> 'tempdb' AND name <> 'model' AND name <> 'msdb'"
    $queryResults = sqlcmd -S 127.0.0.1\SQLEXPRESS -Q "$nocount;$query" -W -h -1
    $move = "WITH MOVE 'VMS_DevConfig_dat' TO 'C:\ProgramData\Titan\Database\VMS_DevConfig.mdf', MOVE 'VMS_DevConfig_log' TO 'C:\ProgramData\Titan\Database\VMS_DevConfig.ldf'"
    sqlcmd -S 127.0.0.1\SQLEXPRESS -Q "RESTORE DATABASE VMS_DevConfig FROM DISK = '$backup' $move"
  }
  else {
    Write-Host "Restore not performed, $reason"
  }
}

function Tsql-Delete-Database() {
  $confirmation = Read-Host "This will delete VMS_DevConfig, do you want to continue? (y/n)"
  If ($confirmation -Match 'y') {
    Write-Host "Database VMS_DevConfig deletion in progress ..."
    sqlcmd -S 127.0.0.1\SQLEXPRESS -Q "DROP DATABASE VMS_DevConfig"
    Write-Host "Database VMS_DevConfig deleted"
  }
  else {
    Write-Host "No database VMS_DevConfig deletion performed"
  }
}

function Tsql-List-Databases() {
  # "SET NOCOUNT ON" means the "(N rows affected)" at the bottom of the query is not displayed
  $nocount = "SET NOCOUNT ON"
  # -W removes trailing spaces, -h -1 specifies no headers to be shown, https://msdn.microsoft.com/en-us/library/ms162773.aspx 
  $query = "SELECT name FROM master..sysdatabases WHERE name <> 'tempdb' AND name <> 'model' AND name <> 'msdb'"
  $queryResults = sqlcmd -S 127.0.0.1\SQLEXPRESS -Q "$nocount;$query" -W -h -1
  if ($queryResults -contains "VMS_DevConfig") {
    # Get the version number
    $versionNumber = sqlcmd -S 127.0.0.1\SQLEXPRESS -d VMS_DevConfig -Q "SET NOCOUNT ON;SELECT major_number, minor_number, revision FROM tblVersionNumber WHERE is_current=1;SET NOCOUNT OFF" -W -h -1
	$versionNumber = $versionNumber -replace " ","."
	
	# Confirm we are looking at a database which has the build_type (introduced in 6.18)
	$buildTypeExists = sqlcmd -S 127.0.0.1\SQLEXPRESS -d VMS_DevConfig -Q "IF COL_LENGTH('tblVersionNumber','build_type') IS NOT NULL BEGIN PRINT 'EXISTS' END" -W -h -1
	
	if ($buildTypeExists -eq "EXISTS") {
	  #Get the build type (case statement converts it from number to text)
      $buildType = sqlcmd -S 127.0.0.1\SQLEXPRESS -d VMS_DevConfig -Q "SET NOCOUNT ON;SELECT CASE WHEN build_type = 3 THEN 'GeoLog Secure' WHEN build_type = 1 THEN 'Titan Secure' WHEN build_type = 2 THEN 'Titan Standard' WHEN build_type = 4 THEN 'Insecure' ELSE 'Unknown' END FROM tblVersionNumber WHERE is_current=1" -W -h -1	
    }
	  
	$queryResults = "VMS_DevConfig" + " " + $versionNumber + " " + $buildType
  }
  
  Write-Host $queryResults
}

function Tsql-Backup-Database() {
  # backup up database to a folder called automatic backups
  # do not delete the database, this must be done manually
  $date = Get-Date -format yyyyMMdd_HHmmss
  $versionNumber = sqlcmd -S 127.0.0.1\SQLEXPRESS -d VMS_DevConfig -Q "SET NOCOUNT ON;SELECT major_number, minor_number, revision FROM tblVersionNumber WHERE is_current=1;SET NOCOUNT OFF" -W -h -1
  $versionNumber = $versionNumber -replace " ","."
  $tag = $versionNumber + "_" + $date
  
  $backupFile = "VMS_DevConfig_$tag.bak"
  $backupLocation = "$tsqlAutomaticBackupLocation\$backupFile"
  $backUpName = "VMS_DevConfig backup"
  Write-Host "Backing up to $backupFile"
  Tsql "BACKUP DATABASE VMS_DevConfig TO DISK = '$backupLocation' WITH FORMAT, MEDIANAME = 'MyBackups', NAME = '$backupName'"
}

function Tsql-Tips() {
  # Some TSQL stuff which I always forget
  Write-Host "Get top 100 rows of a table:"
  Write-Host "SELECT TOP 100 * FROM TABLE"  
}

function sign ($filename) {
  $cert = @(gci cert:\currentuser\My -codesign)[0]
  Set-AuthenticodeSignature $filename $cert
}

# SIG # Begin signature block
# MIIFuQYJKoZIhvcNAQcCoIIFqjCCBaYCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUKxvZg1iwRrz4TMrbVTG7Trtf
# hVygggNCMIIDPjCCAiqgAwIBAgIQuoXR2byjco1JfjGaYnjWJjAJBgUrDgMCHQUA
# MCwxKjAoBgNVBAMTIVBvd2VyU2hlbGwgTG9jYWwgQ2VydGlmaWNhdGUgUm9vdDAe
# Fw0xNTA1MDYwODM5MDBaFw0zOTEyMzEyMzU5NTlaMBoxGDAWBgNVBAMTD1Bvd2Vy
# U2hlbGwgVXNlcjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALRYSXjI
# gSEXUTezL1O/mObDjWv1XoftMlSvN1kifO64psG/41twoCdkyaZImQoaDPnbRr+i
# uLISpcSfJ7skbvTnRx8F3Ms98Pi/4pmwU6C6hLt8GKA556Frd2+puf+0gtAvetXT
# EnhLZoJFJOV0dFxa8kYeNvhx59rTI3Dniojd8bUXFz9TQVKhtOsCg7byewmHuu9T
# khzBshIy1ezNvYW3kS+yBNLiDcqxGqXeW4qXCC4CoDlVV1rMfVcqgHhg8hRG6K3Q
# afCCE5seh2IRVThIYzRXAQ8p951EtMAyaK06/NUE2dmYIM+iam1RY64nVFV8/LEe
# tIq/ZBSGpwOfDaUCAwEAAaN2MHQwEwYDVR0lBAwwCgYIKwYBBQUHAwMwXQYDVR0B
# BFYwVIAQuS5doYTbp8lzZU+lF2zZ/aEuMCwxKjAoBgNVBAMTIVBvd2VyU2hlbGwg
# TG9jYWwgQ2VydGlmaWNhdGUgUm9vdIIQqyhqM7qTL7pIBrc5nvIk3DAJBgUrDgMC
# HQUAA4IBAQBxerO14kZ8frAawSxqcTJ9jYNg+L7rIs923pvyuFpQ5+WM7bzxkiNV
# 9PJoXRGTuUAljMPPol9e4t/JWbKmf6jUKgSpWH7IUkeSbpZ5cpDzIofUfNZtUDsZ
# 23l+kAQByRgoXYN/I9M/woIO8BcCWr6mLTcap3SXZ2GU29K+sjXbRlybwTRLbvxp
# 9Y22uz8BdGH1R3v3gW3JSOQe1K4zNyBzRzTGWF/P6/jlHkbOVp7qruS/cIAfMt4+
# ps8/SQVWPrMxyXRcs7+yNNCWD5+Q7/AhwEFx7A/irDaENssd/iC6UXpMV4/tYFDl
# DdkWLErnGUpWlOHwraiLWF6G+3pa36aAMYIB4TCCAd0CAQEwQDAsMSowKAYDVQQD
# EyFQb3dlclNoZWxsIExvY2FsIENlcnRpZmljYXRlIFJvb3QCELqF0dm8o3KNSX4x
# mmJ41iYwCQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJ
# KoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQB
# gjcCARUwIwYJKoZIhvcNAQkEMRYEFCHi/UjFo9EqI4FR3z9wErVPjStSMA0GCSqG
# SIb3DQEBAQUABIIBAKe4jAt+crqJxqRg8jCH+UDtCIjXEicSm9Lc+m7d0HwmUISx
# x53AlzhWzaNwpPpFt8RvWIrls3EEub0m2/Or9k2f4DYYD6qGXBDo9GathVjnJmf1
# +DFMqzDWwEOVBu2rU8LhTTwiqzibJ/rIO+CTmK3+oqmr6hkNw7u9596FD/OZBDFe
# 8+fy+QjWBjZqkuNxgrTXCwst5JJg4GLjGiQxPipaQZr9Y57eVp0HY1SxTx6FKJxN
# BcpDfF8jhBEylM2Sxw1PGu1y8urMb+TgmOGgflThpdOH2nr2CUTqnBkmMKmb7AKx
# xiUTy3BfEBiXTwfPVxjDXdxwgQbWbPjRsafRX2s=
# SIG # End signature block
