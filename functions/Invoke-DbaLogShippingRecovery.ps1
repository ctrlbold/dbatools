﻿Function Invoke-DbaLogShippingRecovery {
    <#
.SYNOPSIS 
Invoke-DbaLogShippingRecovery recovers log shipped databases to a normal state to act upon a migration or disaster.

.DESCRIPTION
By default all the databases for a particular instance are recovered.
If the database is in the right state, either standby or recovering, the process will try to recover the database.

At first the function will check if the backup source directory can still be reached.
If so it will look up the last transaction log backup for the database. If that backup file is not the last copied file the log shipping copy job will be started.
If the directory cannot be reached for the function will continue to the restoring process.
After the copy job check is performed the job is disabled to prevent the job to run.

For the restore the log shipping status is checked in the msdb database.
If the last restored file is not the same as the last file name found, the log shipping restore job will be executed.
After the restore job check is performed the job is disabled to prevent the job to run

The last part is to set the databse online by restoring the databases with recovery

.PARAMETER SqlServer
SQLServer name or SMO object representing the SQL Server to connect to

.PARAMETER Database
Database to perform the restore for. This value can also be piped enabling multiple databases to be recovered. 
If this value is not supplied all databases will be recovered.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER NoRecovery
Allows you to choose to not restore the database to a functional state (Normal) in the final steps of the process.
By default the database is restored to a functional state (Normal). 

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.PARAMETER Force
Use this parameter to force the function to continue and perform any adjusting actions to successfully execute

.PARAMETER Delay
Set the delay in seconds to wait for the copy and/or restore jobs. 
By default the delay is 5 seconds

.NOTES 
Author: Sander Stad (@sqlstad), sqlstad.nl
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Invoke-DbaLogShippingRecovery

.EXAMPLE   
Invoke-DbaLogShippingRecovery -SqlServer 'server1' 

Recovers all the databases on the instance that are enabled for log shiping

.EXAMPLE   
Invoke-DbaLogShippingRecovery -SqlServer 'server1' -SqlCredential $cred -Verbose

Recovers all the databases on the instance that are enabled for log shiping using a credential

.EXAMPLE   
Invoke-DbaLogShippingRecovery -SqlServer 'server1' -database 'db_logship' -Verbose

Recovers the database "db_logship" to a normal status

.EXAMPLE   
db1, db2, db3, db4 | Invoke-DbaLogShippingRecovery -SqlServer 'server1' -Verbose

Recovers the database db1, db2, db3, db4 to a normal status

.EXAMPLE   
Invoke-DbaLogShippingRecovery -SqlServer 'server1' -WhatIf

Shows what would happen if the command were executed.

#>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param
    (
        [Parameter(Mandatory=$true, Position=1)]
        [Alias("ServerInstance", "SqlInstance")]
        [object]$SqlServer,
        [Parameter(Mandatory=$false, Position=2, ValueFromPipeline=$true)]
        [string[]]$Database = $null,
        [Parameter(Mandatory=$false, Position=3)][System.Management.Automation.PSCredential]$SqlCredential,
        [Parameter(Mandatory=$false, Position=4)][switch]$NoRecovery,
        [Parameter(Mandatory=$false, Position=5)][switch]$Silent,
        [Parameter(Mandatory=$false, Position=6)][switch]$Force,
        [Parameter(Mandatory=$false, Position=7)][int]$Delay = 5
    )

    BEGIN {
        $Islocal = $false

        # Check the instance if it is a named instance
        if($SqlServer -contains '\') {
            $ServerNameName = $SqlServer.Split("\")[0]
            $InstanceName = $SqlServer.Split("\")[1]
        }
        else{
            $ServerNameName = $SqlServer
            $InstanceName = ''
        }
		
        # Check if it's local or remote
        if ($ServerNameName -eq "." -or $ServerNameName -eq "localhost" -or $ServerNameName -eq $env:ServerNamename -or $ServerNameName -eq "127.0.0.1") {
            $Islocal = $true
        }
        
        Write-Message -Message "Attempting to connect to Sql Server.." -Level 2 -Silent $Silent
        try {
            $ServerName = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
        }
        catch {
            Stop-Function -Message "Could not connect to Sql Server instance" -Silent $Silent -InnerErrorRecord $_ -Target $SqlServer 
            return
        }
		
        # Setting the CIM session options
        $SessionOption = New-CimSessionOption -Protocol DCom
    }

    PROCESS {
        Write-Message -Message "Started Log Shipping Recovery" -Level 2 -Silent $Silent

        #region Query setup
        # Query for retrieving the log shipping information
        $query = "
----------------------------------------------------------------
SELECT  lss.primary_server, lss.primary_database, lsd.secondary_database, lss.backup_source_directory,
        lss.backup_destination_directory, lss.last_copied_file, lss.last_copied_date,
        lsd.last_restored_file, sj1.name AS 'copyjob', sj2.name AS 'restorejob'
FROM    msdb.dbo.log_shipping_secondary AS lss
        INNER JOIN msdb.dbo.log_shipping_secondary_databases AS lsd ON lsd.secondary_id = lss.secondary_id
		INNER JOIN msdb.dbo.sysjobs AS sj1 ON sj1.job_id = lss.copy_job_id
		INNER JOIN msdb.dbo.sysjobs AS sj2 ON sj2.job_id = lss.restore_job_id "
        
        # Check if they commandlet is eecuted from a pipeline
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            $db = $_
            
            $query += "WHERE lsd.secondary_database = '$db' "
        }
        else {
            # If just one database is set in the database parameter
            if($Database -ne $null) {
                $db = $Database[0]

                $query += "WHERE lsd.secondary_database = '$db'"
            }
        }
        
        # Add an extra line to easier read the query when in verbose mode
        $query +="
----------------------------------------------------------------"
        #endregion Query setup

        # Retrieve the log shipping information from the secondary instance
        try {
            Write-Message -Message "Retrieving log shipping information from the secondary instance" -Level 5 -Silent $Silent
            $logshipping_details = Invoke-Sqlcmd2 -ServerInstance $SqlServer -Database 'msdb' -Query $query 
        }
        catch {
            Stop-Function -Message ("Error retrieving the log shipping details: " + $_.Exception.Message) -Silent $Silent -InnerErrorRecord $_ -Target $SqlServer
            
            return
        }

        #region CIM Session creation
        Write-Message -Level Verbose -Message "Creating CimSession on $ServerName over WSMan"

        # Check if the CIM session needs to be created using a credential
        if (!$Credential){
            $CIMSession = New-CimSession -ServerName $ServerName -ErrorAction SilentlyContinue
        }
        else{
            $CIMSession = New-CimSession -ServerName $ServerName -ErrorAction SilentlyContinue -Credential $SqlCredential
        }
        
        # Create a CIM session if it's not yet created
        if ($CIMSession.id -eq $null){
            Write-Message -Level Verbose -Message "Creating CimSession on $ServerName over WSMan failed. Creating CimSession on $ServerName over DCom"
            
            if (!$Credential){
                $CIMSession = New-CimSession -ServerName $ServerName -SessionOption $SessionOption -ErrorAction SilentlyContinue -Credential $SqlCredential
            }
            else{
                $CIMSession = New-CimSession -ServerName $ServerName -SessionOption $SessionOption -ErrorAction SilentlyContinue
            }
        }
        
        # Check if the CIM session was created successfully
        if ($CIMSession.id -eq $null){
            Stop-Function -Message "Can't create CimSession on $ServerName"
        }
        
        # Checking the status of the SQL Server Agent service
        Write-Message -Message ("Retrieving the status of the SQL Server Agent" + $ls.secondary_database + "'") -Level 2 -Silent $Silent

        # Get the agent service from the CIM session
        try{
            if($InstanceName -eq ''){
                $agentservice = Get-CimInstance -CimSession $CIMSession -classname Win32_Service -ErrorAction Stop | Where-Object -like -value '*sql*agent*' -Property 'Name'
            }
            else{
                $agentservice = Get-CimInstance -CimSession $CIMSession -classname Win32_Service -ErrorAction Stop | Where-Object -like -value ('*sql*agent*$' + $InstanceName) -Property 'Name'
            }
        }
        catch
        {
            if ($_.Exception -match "namespace")
            {
                Stop-Function -Message "Can't get SQL Server Agent Info for '$ServerName'. Unsupported operating system."
            }
            else
            {
                Stop-Function -Message "Can't get SQL Server Agent Info for '$ServerName'. Check logs for more details."
            }
        }
        #endregion CIM Session creation

        #region SQL Server Agent check
        # Check if the service is running
        if($agentservice.State -ne 'Running') {
            # Check if the service needs to be started forcefully
            if($Force) {
                try {
                    # Start the service
                    $agentservice | Invoke-CimMethod -Name StartService
                }
                catch {
                    # Stop the funcion when the service was unable to start
                    Stop-Function -Message "Unable to start SQL Server Agent Service" -Silent $Silent -InnerErrorRecord $_ -Target $SqlServer

                    return
                }
            }

            # If the force switch and the silent switch are not set
            if((!$Force) -and (!$Silent)) {
                # Set up the parts for the user choice
                $Title = "SQL Server Agent is not running"
                $Info = "Do you want to start the SQL Server Agent service?"
                
                $Options = [System.Management.Automation.Host.ChoiceDescription[]] @("&Start", "&Quit")
                [int]$Defaultchoice = 0
                $choice = $host.UI.PromptForChoice($Title , $Info , $Options, $Defaultchoice)

                # Check the given option 
                if($choice -eq 0) {
                    try {
                        # Start the service
                        $agentservice | Invoke-CimMethod -Name StartService
                    }
                    catch {
                        # Stop the funcion when the service was unable to start
                        Stop-Function -Message "Unable to start SQL Server Agent Service" -Silent $Silent -InnerErrorRecord $_ -Target $SqlServer
                    }
                }
                else {
                    Stop-Function -Message ("The SQL Server Agent service needs to be started to be able to recover the databases") -Silent $Silent -InnerErrorRecord $_ -Target $SqlServer

                    return
                }
            }

            # If the force switch it not set and the silent switch is set
            if((!$Force) -and ($Silent)) {
                
                Stop-Function -Message ("The SQL Server Agent service needs to be started to be able to recover the databases") -Silent $Silent -InnerErrorRecord $_ -Target $SqlServer

                return
            }
        }
        #endregion SQL Server Agent check

        #region Log Shipping Recovery
        # Check if the agent is running
        if($agentservice.State -eq 'Running'){
            # Check if there are any databases to recover
            if($logshipping_details -ne $null) {

                # Loop through each of the log shipped databases
                foreach($ls in $logshipping_details) {
                    # Check if the database is in the right state
                    if($ServerName.Databases[$ls.secondary_database].Status -in ('Normal, Standby', 'Standby', 'Restoring')) {

                        Write-Message -Message ("Started Recovery for '" + $ls.secondary_database + "'") -Level 2 -Silent $Silent

                        #region Copy of remaining backup files
                        # Check if the backup source directory can be reached
                        if(Test-Path $ls.backup_source_directory) {
                            # Get the last file from the backup source directory
                            $latestfile = Get-ChildItem -Path $ls.backup_source_directory -filter ("*" + $ls.primary_database + "*") | Where-Object {($_.Extension -eq '.trn') } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                        
                            # Check if the latest file is also the latest copied file
                            if($latestfile.Name -ne ([string]$ls.last_copied_file).Split('\')[-1]) {
                                Write-Message -Message "Synchronizing the latest transaction log backup file(s)" -Level 5 -Silent $Silent

                                # Start the job to get the latest files
                                if($PSCmdlet.ShouldProcess($SqlServer, ("Starting copy job " + $ls.copyjob))) {
                                    $ServerName.JobServer.Jobs[$ls.copyjob].Start()

                                    Write-Message -Message ("Copying files to '" + $ls.backup_destination_directory + "'") -Level 5 -Silent $Silent
                                
                                    # Check if the file has been copied
                                    $query = "SELECT last_copied_file FROM msdb.dbo.log_shipping_secondary WHERE primary_database = '" + $ls.primary_database + "'"
                                    $latestcopy = Invoke-Sqlcmd2 -ServerInstance $SqlServer -Database 'msdb' -Query $query

                                    Write-Message -Message "Waiting for the copy action to complete.." -Level 5 -Silent $Silent

                                    while($latestfile.Name -ne ([string]$latestcopy.last_copied_file).Split('\')[-1]) {
                                        # Sleep for while to let the files be copied
                                        Start-Sleep -Seconds $Delay

                                        # Again get the latest file to check if the process can continue
                                        $latestcopy = Invoke-Sqlcmd2 -ServerInstance $SqlServer -Database 'msdb' -Query $query
                                    }
                                }

                                Write-Message -Message "Copying of backup files finished" -Level 5 -Silent $Silent
                            }
                        }
                        else {
                            Write-Message -Message "Couldn't reach the backup source directory. Continuing..." -Level 5 -Silent $Silent 
                        }
                        #endregion Copy of remaining backup files

                        # Disable the log shipping copy job on the secondary instance
                        if($PSCmdlet.ShouldProcess($SqlServer, ("Disabling copy job " + $ls.copyjob))) {
                            Write-Message -Message ("Disabling copy job " + $ls.copyjob) -Level 5 -Silent $Silent
                            $ServerName.JobServer.Jobs[$ls.copyjob].IsEnabled = $false
                            $ServerName.JobServer.Jobs[$ls.copyjob].Alter()
                        }

                        # Check if the file has been copied
                        $query = "SELECT last_restored_file FROM dbo.log_shipping_secondary_databases WHERE secondary_database = '" + $ls.secondary_database + "'"
                        $latestrestore = Invoke-Sqlcmd2 -ServerInstance $SqlServer -Database 'msdb' -Query $query

                        #region Restore of remaining backup files
                        # Check if the last copied file is newer than the last restored file
                        if($latestfile.Name -ne ([string]$latestrestore.last_restored_file).Split('\')[-1]) {
                            Write-Message -Message "Last file found has not yet been restored yet" -Level 5 -Silent $Silent
                            # Start the restore job
                            if($PSCmdlet.ShouldProcess($SqlServer, ("Starting restore job " + $ls.restorejob))) {
                                Write-Message -Message ("Starting restore job " + $ls.restorejob) -Level 5 -Silent $Silent
                                $ServerName.JobServer.Jobs[$ls.restorejob].Start()
                            
                                Write-Message -Message "Waiting for the restore action to complete.."-Level 5 -Silent $Silent

                                # Check if the jobs is still running
                                while($latestfile.Name -ne ([string]$latestrestore.last_restored_file).Split('\')[-1]) {
                                    # Sleep for while to let the files be copied
                                    Start-Sleep -Seconds $Delay

                                    # Again get the latest file to check if the process can continue
                                    $latestrestore = Invoke-Sqlcmd2 -ServerInstance $SqlServer -Database 'msdb' -Query $query
                                }
                            }
                        }
                        #endregion Restore of remaining backup files

                        # Disable the log shipping restore job on the secondary instance
                        if($PSCmdlet.ShouldProcess($SqlServer, ("Disabling restore job " + $ls.restorejob))) {
                            Write-Message -Message ("Disabling restore job " + $ls.restorejob) -Level 5 -Silent $Silent
                            $ServerName.JobServer.Jobs[$ls.restorejob].IsEnabled = $false
                            $ServerName.JobServer.Jobs[$ls.restorejob].Alter()
                        }

                        #region Restore database to normal state
                        # Check for the last time if everything is up-to-date
                        if($latestfile.Name -eq [string]$latestrestore.last_restored_file.Split('\')[-1]) {
                            # Check if the database needs to recovered to it's notmal state
                            if($NoRecovery -eq $false) {
                                if($PSCmdlet.ShouldProcess($ls.secondary_database, "Restoring database with recovery")) {
                                    Write-Message -Message "Restoring the database to it's normal state" -Level 2 -Silent $Silent
                                    $query = "RESTORE DATABASE " + $ls.secondary_database + " WITH RECOVERY"
                                    Invoke-Sqlcmd2 -ServerInstance $SqlServer -Database 'master' -Query $query 
                                }
                            }
                            elseif($NoRecovery -eq $true) {
                                Write-Message -Message "Skipping restore with recovery" -Level 2 -Silent $Silent
                            }
                        }
                        #endregion Restore database to normal state

                    }
                    else {
                        Write-Message "The database '$db' doesn't have the right status to be recovered" -Level 3 -Silent $Silent
                    }
                }
            }
            else {
                Write-Message -Message "The database '$db' is not configured for log shipping." -Level 2 -Warning -Silent $Silent
            }

            Write-Message -Message ("Finished Recovery for '" + $ls.secondary_database + "'") -Level 2 -Silent $Silent

            # Reset the log ship details
            $logshipping_details = $null
        }
        else{
            Stop-Function -Message ("The SQL Server Agent service needs to be started to be able to recover the databases") -Silent $Silent -InnerErrorRecord $_ -Target $SqlServer
            return
        }
        #endregion Log Shipping Recovery
    }

    END {
        Write-Message -Message "Finished Log Shipping Recovery" -Level 1 -Silent $Silent
    }

}


