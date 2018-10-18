﻿#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function New-DbaAvailabilityGroup {
<#
    .SYNOPSIS
        Automates the creation of database mirrors.

    .DESCRIPTION
        Automates the creation of database mirrors.

        * Verifies that a secondary is possible
        * Sets the recovery model to Full if needed
        * If the database does not exist on secondary or witness, a backup/restore is performed
        * Sets up endpoints if necessary
        * Creates a login and grants permissions to service accounts if needed
        * Starts endpoints if needed
        * Sets up partner for secondary
        * Sets up partner for primary
        * Sets up witness if one is specified

        NOTE: If a backup / restore is performed, the backups will be left in tact on the network share.

        Thanks for this, Thomas Stringer! https://blogs.technet.microsoft.com/heyscriptingguy/2013/04/29/set-up-an-alwayson-availability-group-with-powershell/

        Notes from shawn to add in:
        (1) the NT AUTHORITY account has to be given rights to each replica, with rights to alter/connect to the endpoint
        (2) the service account for each instance has to be explicitly created (the link to the NT SERVICE account won't be sufficient), connect access to the endpoint on the instance

        So if there is no domain account, on step 2 you would have to add the computer account for everything.

    .PARAMETER Primary
        The primary SQL Server instance. Server version must be SQL Server version 2012 or higher.

    .PARAMETER PrimarySqlCredential
        Login to the primary instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Secondary
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SecondarySqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Name
        The name of the Availability Group.

    .PARAMETER DtcSupport
        Indicates whether the DtcSupport is enabled

    .PARAMETER ClusterType
        Cluster type of the Availability Group.
        Options include: External, Wsfc or None. External by default.

    .PARAMETER AutomatedBackupPreference
        Specifies how replicas in the primary role are treated in the evaluation to pick the desired replica to perform a backup.

    .PARAMETER FailureConditionLevel
        Specifies the different conditions that can trigger an automatic failover in Availability Group.

    .PARAMETER HealthCheckTimeout
        This setting used to specify the length of time, in milliseconds, that the SQL Server resource DLL should wait for information returned by the sp_server_diagnostics stored procedure before reporting the Always On Failover Cluster Instance (FCI) as unresponsive.

        Changes that are made to the timeout settings are effective immediately and do not require a restart of the SQL Server resource.

        Defaults to 30000 (30 seconds).

    .PARAMETER Basic
        Indicates whether the availability group is basic. Basic availability groups like pumpkin spice and uggs.

        https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/basic-availability-groups-always-on-availability-groups

    .PARAMETER DatabaseHealthTrigger
        Indicates whether the availability group triggers the database health.

    .PARAMETER Passthru
        Don't create the availability group, just pass thru an object that can be further customized before creation.

    .PARAMETER Database
        The database or databases to add.

    .PARAMETER NetworkShare
        The network share where the backups will be backed up and restored from.

        Each SQL Server service account must have access to this share.

        NOTE: If a backup / restore is performed, the backups will be left in tact on the network share.

    .PARAMETER UseLastBackups
        Use the last full backup of database.

    .PARAMETER Force
        Drop and recreate the database on remote servers using fresh backup.

    .PARAMETER AvailabilityMode
        Sets the availability mode of the availability group replica. Options are: AsynchronousCommit and SynchronousCommit. SynchronousCommit is default.

    .PARAMETER FailoverMode
        Sets the failover mode of the availability group replica. Options are Automatic and Manual. Automatic is default.

    .PARAMETER BackupPriority
        Sets the backup priority availability group replica. Default is 50.

    .PARAMETER Endpoint
        By default, this command will attempt to find a DatabaseMirror endpoint. If one does not exist, it will create it.

        If an endpoint must be created, the name "hadr_endpoint" will be used. If an alternative is preferred, use Endpoint.

    .PARAMETER ConnectionModeInPrimaryRole
        Specifies the connection intent modes of an Availability Replica in primary role. AllowAllConnections by default.

    .PARAMETER ConnectionModeInSecondaryRole
        Specifies the connection modes of an Availability Replica in secondary role. AllowAllConnections by default.

    .PARAMETER ReadonlyRoutingConnectionUrl
        Sets the read only routing connection url for the availability replica.

    .PARAMETER SeedingMode
        Specifies how the secondary replica will be initially seeded.

        Automatic enables direct seeding. This method will seed the secondary replica over the network. This method does not require you to backup and restore a copy of the primary database on the replica.

        Manual requires you to create a backup of the database on the primary replica and manually restore that backup on the secondary replica.

    .PARAMETER Certificate
        Specifies that the endpoint is to authenticate the connection using the certificate specified by certificate_name to establish identity for authorization.

        The far endpoint must have a certificate with the public key matching the private key of the specified certificate.

    .PARAMETER IPAddress
        Sets the IP address of the availability group listener.

    .PARAMETER SubnetMask
        Sets the subnet IP mask of the availability group listener.

    .PARAMETER Port
        Sets the number of the port used to communicate with the availability group.

    .PARAMETER Dhcp
        Indicates whether the object is DHCP.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: HA
        Author: Chrissy LeMaire (@cl), netnerds.net
        dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaAvailabilityGroup

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql2016a -Name SharePoint

        Creates a new availability group on sql2016a named SharePoint

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql2016a -Name SharePoint -Secondary sql2016b

        Creates a new availability group on sql2016b named SharePoint with a secondary on sql2016b

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql2017 -Name SharePoint -ClusterType None -FailoverMode Manual

        Creates a new availability group on sql2017 named SharePoint

    .EXAMPLE
        PS C:\> $params = @{
        >>    Primary = 'sql2017'
        >>    Name    = 'SharePoint'
        >>    IPAddress = '10.0.1.25'
        >>    ClusterType = 'None'
        >>    AutomatedBackupPreference = 'None'
        >>}

        PS C:\> New-DbaAvailabilityGroup @params

        Performs a bunch of checks to ensure the pubs database on sql2017a
        can be mirrored from sql2017a to sql2017b. Logs in to sql2019 and sql2017a
        using Windows credentials and sql2017b using a SQL credential.

        Prompts for confirmation for most changes. To avoid confirmation, use -Confirm:$false or
        use the syntax in the second example.

    .EXAMPLE
        PS C:\> $params = @{
        >> Primary = 'sql2017a'
        >> Secondary = 'sql2017b'
        >> SecondarySqlCredential = 'sqladmin'
        >> Witness = 'sql2019'
        >> Database = 'pubs'
        >> NetworkShare = '\\nas\sql\share'
        >> Force = $true
        >> Confirm = $false
        >> }

        PS C:\> Invoke-DbaDbMirror @params

        Performs a bunch of checks to ensure the pubs database on sql2017a
        can be mirrored from sql2017a to sql2017b. Logs in to sql2019 and sql2017a
        using Windows credentials and sql2017b using a SQL credential.

        Drops existing pubs database on Secondary and Witness and restores them with
        a fresh backup.

        Does all the things in the decription, does not prompt for confirmation.

#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter]$Primary,
        [PSCredential]$PrimarySqlCredential,
        [DbaInstanceParameter[]]$Secondary,
        [PSCredential]$SecondarySqlCredential,
        # AG

        [parameter(Mandatory)]
        [string]$Name,
        [switch]$DtcSupport,
        [ValidateSet('External', 'Wsfc', 'None')]
        [string]$ClusterType = 'External',
        [ValidateSet('None', 'Primary', 'Secondary', 'SecondaryOnly')]
        [string]$AutomatedBackupPreference = 'Secondary',
        [ValidateSet('OnAnyQualifiedFailureCondition', 'OnCriticalServerErrors', 'OnModerateServerErrors', 'OnServerDown', 'OnServerUnresponsive')]
        [string]$FailureConditionLevel = "OnServerDown",
        [int]$HealthCheckTimeout = 30000,
        [switch]$Basic,
        [switch]$DatabaseHealthTrigger,
        [switch]$Passthru,
        # database

        [string[]]$Database,
        [string]$NetworkShare,
        [switch]$UseLastBackups,
        [switch]$Force,
        # replica

        [ValidateSet('AsynchronousCommit', 'SynchronousCommit')]
        [string]$AvailabilityMode = "SynchronousCommit",
        [ValidateSet('Automatic', 'Manual')]
        [string]$FailoverMode = "Automatic",
        [int]$BackupPriority = 50,
        [ValidateSet('AllowAllConnections', 'AllowReadWriteConnections')]
        [string]$ConnectionModeInPrimaryRole = 'AllowAllConnections',
        [ValidateSet('AllowAllConnections', 'AllowNoConnections', 'AllowReadIntentConnectionsOnly')]
        [string]$ConnectionModeInSecondaryRole = 'AllowAllConnections',
        [ValidateSet('Automatic', 'Manual')]
        [string]$SeedingMode = 'Automatic',
        [string]$Endpoint,
        [string]$ReadonlyRoutingConnectionUrl,
        [string]$Certificate,
        # network

        [ipaddress[]]$IPAddress,
        [ipaddress]$SubnetMask = "255.255.255.0",
        [int]$Port = 1433,
        [switch]$Dhcp,
        [switch]$EnableException
    )
    process {
        $stepCounter = 0
        $totalSteps = 7
        $activity = "Adding new availability group $name"
        if ($Force -and $Secondary -and (-not $NetworkShare -and -not $UseLastBackups)) {
            Stop-Function -Message "NetworkShare or UseLastBackups is required when Force is used"
            return
        }

        try {
            $server = Connect-SqlInstance -SqlInstance $Primary -SqlCredential $PrimarySqlCredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Primary -Continue
        }

        Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Checking perquisites"

        if (Get-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $Name) {
            Stop-Function -Message "Availability group named $Name already exists on $Primary"
            return
        }

        if ($Certificate) {
            $cert = Get-DbaDbCertificate -SqlInstance $server -Certificate $Certificate
            if (-not $cert) {
                Stop-Function -Message "Certificate $Certificate does not exist on $Primary" -ErrorRecord $_ -Target $Primary -Continue
            }
        }

        if (($NetworkShare)) {
            if (-not (Test-DbaPath -SqlInstance $server -Path $NetworkShare)) {
                Stop-Function -Continue -Message "Cannot access $NetworkShare from $Primary"
                return
            }
        }

        if ($Database -and -not $UseLastBackups -and -not $NetworkShare -and $Secondary) {
            Stop-Function -Continue -Message "You must specify a NetworkShare when adding databases to the availability group"
            return
        }

        if ($Secondary) {
            $secondaries = @()
            foreach ($computer in $Secondary) {
                try {
                    $secondaries += Connect-SqlInstance -SqlInstance $computer -SqlCredential $SecondarySqlCredential
                }
                catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Primary -Continue
                }
            }
        }

        # database checks
        if ($Database) {
            $dbs += Get-DbaDatabase -SqlInstance $server -Database $Database
        }

        foreach ($primarydb in $dbs) {
            if ($primarydb.MirroringStatus -ne "None") {
                Stop-Function -Continue -Message "Cannot setup mirroring on database ($dbname) due to its current mirroring state: $($primarydb.MirroringStatus)"
            }

            if ($primarydb.Status -ne "Normal") {
                Stop-Function -Continue -Message "Cannot setup mirroring on database ($dbname) due to its current state: $($primarydb.Status)"
            }

            if ($primarydb.RecoveryModel -ne "Full") {
                if ((Test-Bound -ParameterName UseLastBackups)) {
                    Stop-Function -Continue -Message "$dbName not set to full recovery. UseLastBackups cannot be used."
                }
                else {
                    Set-DbaDbRecoveryModel -SqlInstance $server -Database $primarydb.Name -RecoveryModel Full
                }
            }
        }

        Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Creating availability group named $Name on $Primary"

        # Start work
        if ($Pscmdlet.ShouldProcess($Primary, "Creating availability group named $Name")) {
            try {
                $ag = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroup -ArgumentList $server, $Name
                $ag.AutomatedBackupPreference = [Microsoft.SqlServer.Management.Smo.AvailabilityGroupAutomatedBackupPreference]::$AutomatedBackupPreference
                $ag.FailureConditionLevel = [Microsoft.SqlServer.Management.Smo.AvailabilityGroupFailureConditionLevel]::$FailureConditionLevel
                $ag.HealthCheckTimeout = $HealthCheckTimeout
                $ag.BasicAvailabilityGroup = $Basic
                $ag.DatabaseHealthTrigger = $DatabaseHealthTrigger

                if ($server.VersionMajor -ge 14) {
                    $ag.ClusterType = $ClusterType
                }

                if ($PassThru) {
                    $defaults = 'LocalReplicaRole', 'Name as AvailabilityGroup', 'PrimaryReplicaServerName as PrimaryReplica', 'AutomatedBackupPreference', 'AvailabilityReplicas', 'AvailabilityDatabases', 'AvailabilityGroupListeners'
                    return (Select-DefaultView -InputObject $ag -Property $defaults)
                }

                $replicaparams = @{
                    InputObject                   = $ag
                    AvailabilityMode              = $AvailabilityMode
                    FailoverMode                  = $FailoverMode
                    BackupPriority                = $BackupPriority
                    ConnectionModeInPrimaryRole   = $ConnectionModeInPrimaryRole
                    ConnectionModeInSecondaryRole = $ConnectionModeInSecondaryRole
                    SeedingMode                   = $SeedingMode
                    Endpoint                      = $Endpoint
                    ReadonlyRoutingConnectionUrl  = $ReadonlyRoutingConnectionUrl
                    Certificate                   = $Certificate
                }
                
                $null = Add-DbaAgReplica @replicaparams -EnableException -SqlInstance $server
                # something is up with .net create(), force a stop
                Invoke-Create -Object $ag
            }
            catch {
                $msg = $_.Exception.InnerException.InnerException.Message
                if (-not $msg) {
                    $msg = $_
                }
                Stop-Function -Message $msg -ErrorRecord $_ -Target $Primary
                return
            }
        }

        # Add permissions
        Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Adding endpoint connect permissions"

        foreach ($second in $secondaries) {
            $serviceaccounts = $server.ServiceAccount, $second.ServiceAccount | Select-Object -Unique

            try {
                Grant-DbaAgPermission -SqlInstance $server, $second -Login $serviceaccounts -Type Endpoint -Permission Connect -EnableException
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $second
                return
            }
        }


        # Join secondaries
        Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Adding secondary replicas"

        foreach ($second in $secondaries) {
            try {
                $null = Add-DbaAgReplica @replicaparams -EnableException -SqlInstance $second
                Join-DbaAvailabilityGroup -SqlInstance $second -InputObject $ag -EnableException
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $second -Continue
            }
        }

        foreach ($second in $secondaries) {

        }

        # Add databases
        Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Adding databases"

        $allbackups = @{ }
        foreach ($db in $Database) {
            $null = Add-DbaAgDatabase -SqlInstance $server -AvailabilityGroup $Name -Database $db
            foreach ($second in $secondaries) {
                $primarydb = Get-DbaDatabase -SqlInstance $server -Database $db
                $secondb = Get-DbaDatabase -SqlInstance $second -Database $db
                if (-not $seconddb -or $Force) {
                    try {
                        if (-not $allbackups[$db]) {
                            if ($UseLastBackups) {
                                $allbackups[$db] = Get-DbaBackupHistory -SqlInstance $primarydb.Parent -Database $primarydb.Name -IncludeCopyOnly -Last -EnableException
                            }
                            else {
                                $fullbackup = $primarydb | Backup-DbaDatabase -BackupDirectory $NetworkShare -Type Full -EnableException
                                $logbackup = $primarydb | Backup-DbaDatabase -BackupDirectory $NetworkShare -Type Log -EnableException
                                $allbackups[$db] = $fullbackup, $logbackup
                            }
                            Write-Message -Level Verbose -Message "Backups still exist on $NetworkShare"
                        }
                        if ($Pscmdlet.ShouldProcess("$Secondary", "restoring full and log backups of $primarydb from $Primary")) {
                            # keep going to ensure output is shown even if dbs aren't added well.
                            $null = $allbackups[$db] | Restore-DbaDatabase -SqlInstance $second -WithReplace -NoRecovery -TrustDbBackupHistory -EnableException
                        }
                    }
                    catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                    }
                }
                $null = Add-DbaAgDatabase -SqlInstance $second -AvailabilityGroup $Name -Database $db
            }
        }

        # Add listener
        Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Adding endpoint connect permissions"

        if ($IPAddress) {
            $null = Add-DbaAgListener -InputObject $ag -IPAddress $IPAddress -SubnetMask $SubnetMask -Port $Port -Dhcp:$Dhcp
        }
        elseif ($Dhcp) {
            $null = Add-DbaAgListener -InputObject $ag -Port $Port -Dhcp:$Dhcp
            foreach ($second in $secondaries) {
                $secag = Get-DbaAvailabilityGroup -SqlInstance $second -AvailabilityGroup $Name
                $null = Add-DbaAgListener -InputObject $secag -Port $Port -Dhcp:$Dhcp
            }
        }

        # Get results
        Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Getting new availability groups"

        Get-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $Name

        foreach ($second in $secondaries) {
            Get-DbaAvailabilityGroup -SqlInstance $second -AvailabilityGroup $Name
        }
    }
}