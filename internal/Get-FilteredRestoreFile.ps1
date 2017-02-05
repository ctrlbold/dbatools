function Get-FilteredRestoreFile
{
<#
.SYNOPSIS
Internal Function to Filter a set of SQL Server backup files

.DESCRIPTION
Takes an array of FileSystem Objects and then filters them down by date to get a potential Restore set
First step is to pass them to a SQLInstance to be parsed with Read-DBABackupHeader
The we find the last full backup before the RestorePoint.
Then filter for and Diff backups between the full backup and the RestorePoint
Tnen find the T-log backups needed to bridge the gap up until the RestorePoint
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$Files,
        [parameter(Mandatory = $true)]
        [object]$SqlServer,
        [DateTime]$RestoreTime = (Get-Date).addyears(1),
        [System.Management.Automation.PSCredential]$SqlCredential 

	)
    Begin
    {
        $FunctionName = "Filter-RestoreFile"
        Write-Verbose "$FunctionName - Starting"



        $Results = @()
        $InternalFiles = @()
    }
    # -and $_.BackupStartDate -lt $RestoreTime
    process
        {

        foreach ($file in $files){
            $InternalFiles += $file
        }
    }
    End
    {
        Write-Verbose "$FunctionName - Read File headers (Read-DBABackupHeader)"
        $SQLBackupdetails  = $InternalFiles | Select-Object -ExpandProperty FullName | Read-DBAbackupheader -sqlserver $SQLSERVER -SqlCredential:$SqlCredential
        Write-Verbose "$FunctionName - Find Newest Full backup"
        $Fullbackup = $SQLBackupdetails | where-object {$_.BackupType -eq "1" -and $_.BackupStartDate -lt $RestoreTime} | Sort-Object -Property BackupStartDate -descending | Select-Object -First 1
        if ($Fullbackup -eq $null)
        {
            Write-Error "$FunctionName - No Full backup found to anchor the restore"
        }

       $Results += $SQLBackupdetails | where-object {$_.BackupType -eq "1" -and $_.FirstLSN -eq $FullBackup.FirstLSN}
        
       Write-Verbose "$FunctionName - Got a Full backup, now find diffs if they exist"
       $Diffbackups = $SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Database Differential' -and $_.DatabaseBackupLSN -eq $Fullbackup.FirstLsn -and $_.BackupStartDate -lt $RestoreTime}

        $TlogStartlsn = 0
        if ($Diffbackups.count -gt 0){
            Write-Verbose "$FunctionName - we have at least one diff so look for tlogs after the last one"
            #If we have a Diff backup, we only need T-log backups post that point
            $TlogStartLSN = ($DiffBackups | sort-object -propert FirstLSN -Descending | select-object -Propert StartLsn -first 1).FirstLSN
            $Results += $Diffbackups
        }
        

        Write-Verbose "$FunctionName - Got a Full/Diff backups, now find all Tlogs needed"
        $Tlogs = $SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Transaction Log' -and $_.DatabaseBackupLSN -eq $Fullbackup.FirstLsn -and $_.FirstLSN -gt $TlogStartLSN -and $_.StartTime -lt $RestoreTime}
        $Results += $Tlogs
        #Catch the last Tlog that covers the restore time!
        $Tlogfinal = $SQLBackupdetails | Where-Object {$_.BackupTypeDescription -eq 'Transaction Log' -and $_.BackupStartDate -gt $RestoreTime} | Sort-Object -Property LastLSN  | select -First 1
        $Results += $Tlogfinal
        Write-Verbose "$FunctionName - Returning Results to caller"
        $Results
    }
}