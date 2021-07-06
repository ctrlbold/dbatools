function Copy-DbaLogin {
    <#
    .SYNOPSIS
        Migrates logins from source to destination SQL Servers. Supports SQL Server versions 2000 and newer.

    .DESCRIPTION
        SQL Server 2000: Migrates logins with SIDs, passwords, server roles and database roles.

        SQL Server 2005 & newer: Migrates logins with SIDs, passwords, defaultdb, server roles & securables, database permissions & securables, login attributes (enforce password policy, expiration, etc.)

        The login hash algorithm changed in SQL Server 2012, and is not backwards compatible with previous SQL Server versions. This means that while SQL Server 2000 logins can be migrated to SQL Server 2012, logins created in SQL Server 2012 can only be migrated to SQL Server 2012 and above.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Login
        The login(s) to process. Options for this list are auto-populated from the server. If unspecified, all logins will be processed.

    .PARAMETER ExcludeLogin
        The login(s) to exclude. Options for this list are auto-populated from the server.

    .PARAMETER ExcludeSystemLogins
        If this switch is enabled, NT SERVICE accounts will be skipped.

    .PARAMETER ExcludePermissionSync
        Skips permission syncs

    .PARAMETER SyncSaName
        If this switch is enabled, the name of the sa account will be synced between Source and Destination

    .PARAMETER OutFile
        Calls Export-DbaLogin and exports all logins to a T-SQL formatted file. This does not perform a copy, so no destination is required.

    .PARAMETER InputObject
        Takes the parameters required from a Login object that has been piped into the command

    .PARAMETER NewSid
        Ignore sids from the source login objects to generate new sids on the destination server. Useful when copying login onto the same server

    .PARAMETER LoginRenameHashtable
        Pass a hash table into this parameter to create logins under different names based on hashtable mapping.

    .PARAMETER ObjectLevel
        Include object-level permissions for each user associated with copied login.

    .PARAMETER KillActiveConnection
        If this switch and -Force are enabled, all active connections and sessions on Destination will be killed.

        A login cannot be dropped when it has active connections on the instance.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        If this switch is enabled, the Login(s) will be dropped and recreated on Destination. Logins that own Agent jobs cannot be dropped at this time.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Login
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaLogin

    .EXAMPLE
        PS C:\> Copy-DbaLogin -Source sqlserver2014a -Destination sqlcluster -Force

        Copies all logins from Source Destination. If a SQL Login on Source exists on the Destination, the Login on Destination will be dropped and recreated.

        If active connections are found for a login, the copy of that Login will fail as it cannot be dropped.

    .EXAMPLE
        PS C:\> Copy-DbaLogin -Source sqlserver2014a -Destination sqlcluster -Force -KillActiveConnection

        Copies all logins from Source Destination. If a SQL Login on Source exists on the Destination, the Login on Destination will be dropped and recreated.

        If any active connections are found they will be killed.

    .EXAMPLE
        PS C:\> Copy-DbaLogin -Source sqlserver2014a -Destination sqlcluster -ExcludeLogin realcajun -SourceSqlCredential $scred -DestinationSqlCredential $dcred

        Copies all Logins from Source to Destination except for realcajun using SQL Authentication to connect to both instances.

        If a Login already exists on the destination, it will not be migrated.

    .EXAMPLE
        PS C:\> Copy-DbaLogin -Source sqlserver2014a -Destination sqlcluster -Login realcajun, netnerds -force

        Copies ONLY Logins netnerds and realcajun. If Login realcajun or netnerds exists on Destination, the existing Login(s) will be dropped and recreated.

    .EXAMPLE
        PS C:\> Copy-DbaLogin -LoginRenameHashtable @{ "PreviousUser" = "newlogin" } -Source $Sql01 -Destination Localhost -SourceSqlCredential $sqlcred -Login PreviousUser

        Copies PreviousUser as newlogin.

    .EXAMPLE
        PS C:\> Copy-DbaLogin -LoginRenameHashtable @{ OldLogin = "NewLogin" } -Source Sql01 -Destination Sql01 -Login ORG\OldLogin -ObjectLevel -NewSid

        Clones OldLogin as NewLogin onto the same server, generating a new SID for the login. Also clones object-level permissions.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 | Out-GridView -Passthru | Copy-DbaLogin -Destination sql2017

        Displays all available logins on sql2016 in a grid view, then copies all selected logins to sql2017.

    .EXAMPLE
        PS C:\> $loginSplat = @{
        >> Source = $Sql01
        >> Destination = "Localhost"
        >> SourceSqlCredential = $sqlcred
        >> Login = 'ReadUserP', 'ReadWriteUserP', 'AdminP'
        >> LoginRenameHashtable = @{
        >> "ReadUserP" = "ReadUserT"
        >> "ReadWriteUserP" = "ReadWriteUserT"
        >> "AdminP"         = "AdminT"
        >> }
        >> }
        PS C:\> Copy-DbaLogin @loginSplat

        Copies the three specified logins to 'localhost' and renames them according to the LoginRenameHashTable.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(ParameterSetName = "File", Mandatory)]
        [parameter(ParameterSetName = "SqlInstance", Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(ParameterSetName = "SqlInstance", Mandatory)]
        [parameter(ParameterSetName = "InputObject", Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$Login,
        [object[]]$ExcludeLogin,
        [switch]$ExcludeSystemLogins,
        [parameter(ParameterSetName = "Live")]
        [parameter(ParameterSetName = "SqlInstance")]
        [switch]$SyncSaName,
        [parameter(ParameterSetName = "File", Mandatory)]
        [string]$OutFile,
        [parameter(ParameterSetName = "InputObject", ValueFromPipeline)]
        [object[]]$InputObject,
        [hashtable]$LoginRenameHashtable,
        [switch]$KillActiveConnection,
        [switch]$NewSid,
        [switch]$Force,
        [switch]$ObjectLevel,
        [switch]$ExcludePermissionSync,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }
        function Copy-Login {
            [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
            Param (
                $SourceServer,
                $DestServer,
                $Login,
                $Exclude
            )
            if ($LoginRenameHashtable.Keys -contains $Login.name) {
                $newUserName = $LoginRenameHashtable[$Login.name]
            } else {
                $newUserName = $Login.name
            }

            $copyLoginStatus = [pscustomobject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Type              = "Login - $($Login.LoginType)"
                Name              = $newUserName
                DestinationLogin  = $newUserName
                SourceLogin       = $Login.name
                Status            = $null
                Notes             = $null
                DateTime          = [DbaDateTime](Get-Date)
            }

            if ($ExcludeLogin -contains $Login.name) { continue }

            if ($Login.id -eq 1) { continue }

            if ($newUserName.StartsWith("##") -or $newUserName -eq 'sa') {
                Write-Message -Level Verbose -Message "Skipping $newUserName."
                continue
            }

            if ($Login.LoginType -like 'Window*' -and $destServer.DatabaseEngineEdition -eq 'SqlManagedInstance' ) {
                Write-Message -Level Verbose -Message "$Login is a Windows login, not supported on a SQL Managed Instance"
                $copyLoginStatus.Status = "Skipped"
                $copyLoginStatus.Notes = "$($Login.name) is a Windows login, not supported on a SQL Managed Instance"
                $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                continue
            }

            # Here we don't need the FullComputerName, but only the maschine name to compare to the host part of the login name. So ComputerName should be fine.
            $serverName = $sourceServer.ComputerName

            $currentLogin = $DestServer.ConnectionContext.truelogin

            if ($currentLogin -eq $newUserName -and $force) {
                if ($Pscmdlet.ShouldProcess("console", "Stating $newUserName is skipped because it is performing the migration.")) {
                    Write-Message -Level Verbose -Message "Cannot drop login performing the migration. Skipping."
                    $copyLoginStatus.Status = "Skipped"
                    $copyLoginStatus.Notes = "Current login"
                    $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                continue
            }

            if (($destServer.LoginMode -ne [Microsoft.SqlServer.Management.Smo.ServerLoginMode]::Mixed) -and ($Login.LoginType -eq [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin)) {
                Write-Message -Level Verbose -Message "$Destination does not have Mixed Mode enabled. [$($Login.Name)] is an SQL Login. Enable mixed mode authentication after the migration completes to use this type of login."
            }

            $userBase = ($Login.Name.Split("\")[0]).ToLowerInvariant()

            if ($serverName -eq $userBase -or $Login.Name.StartsWith("NT ")) {
                if ($sourceServer.ComputerName -ne $destServer.ComputerName) {
                    if ($Pscmdlet.ShouldProcess("console", "Stating $($Login.Name) was skipped because it is a local machine name.")) {
                        Write-Message -Level Verbose -Message "$($Login.Name) was skipped because it is a local machine name."
                        $copyLoginStatus.Status = "Skipped"
                        $copyLoginStatus.Notes = "Local machine name"
                        $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                } else {
                    if ($ExcludeSystemLogins) {
                        if ($Pscmdlet.ShouldProcess("console", "$($Login.Name) was skipped because ExcludeSystemLogins was specified.")) {
                            Write-Message -Level Verbose -Message "$($Login.Name) was skipped because ExcludeSystemLogins was specified."

                            $copyLoginStatus.Status = "Skipped"
                            $copyLoginStatus.Notes = "System login"
                            $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        continue
                    }

                    if ($Pscmdlet.ShouldProcess("console", "Stating local login $($Login.Name) since the source and destination server reside on the same machine.")) {
                        Write-Message -Level Verbose -Message "Copying local login $($Login.Name) since the source and destination server reside on the same machine."
                    }
                }
            }

            if ($null -ne $destServer.Logins.Item($newUserName) -and !$force) {
                if ($Pscmdlet.ShouldProcess("console", "Stating $newUserName is skipped because it exists at destination.")) {
                    Write-Message -Level Verbose -Message "$newUserName already exists in destination. Use -Force to drop and recreate."
                    $copyLoginStatus.Status = "Skipped"
                    $copyLoginStatus.Notes = "Already exists on destination"
                    $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                continue
            }

            if ($null -ne $destServer.Logins.Item($newUserName) -and $force) {
                if ($newUserName -eq $destServer.ServiceAccount) {
                    if ($Pscmdlet.ShouldProcess("console", "$newUserName is the destination service account. Skipping drop.")) {
                        Write-Message -Level Verbose -Message "$newUserName is the destination service account. Skipping drop."

                        $copyLoginStatus.Status = "Skipped"
                        $copyLoginStatus.Notes = "Destination service account"
                        $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Dropping $newUserName")) {

                    # Kill connections, delete user
                    Write-Message -Level Verbose -Message "Attempting to migrate $newUserName"
                    Write-Message -Level Verbose -Message "Force was specified. Attempting to drop $newUserName on $destinstance."

                    try {
                        $ownedDbs = $destServer.Databases | Where-Object Owner -eq $newUserName

                        foreach ($ownedDb in $ownedDbs) {
                            Write-Message -Level Verbose -Message "Changing database owner for $($ownedDb.name) from $newUserName to sa."
                            $ownedDb.SetOwner('sa')
                            $ownedDb.Alter()
                        }

                        $ownedJobs = $destServer.JobServer.Jobs | Where-Object OwnerLoginName -eq $newUserName

                        foreach ($ownedJob in $ownedJobs) {
                            Write-Message -Level Verbose -Message "Changing job owner for $($ownedJob.name) from $newUserName to sa."
                            $ownedJob.Set_OwnerLoginName('sa')
                            $ownedJob.Alter()
                        }

                        $activeConnections = $destServer.EnumProcesses() | Where-Object Login -eq $newUserName

                        if ($activeConnections -and $KillActiveConnection) {
                            if (!$destServer.Logins.Item($newUserName).IsDisabled) {
                                $disabled = $true
                                $destServer.Logins.Item($newUserName).Disable()
                            }

                            $activeConnections | ForEach-Object { $destServer.KillProcess($_.Spid) }
                            Write-Message -Level Verbose -Message "-KillActiveConnection was provided. There are $($activeConnections.Count) active connections killed."
                        } elseif ($activeConnections) {
                            Write-Message -Level Verbose -Message "There are $($activeConnections.Count) active connections found for the login $newUserName. Utilize -KillActiveConnection with -Force to kill the connections."
                        }
                        try {
                            $destServer.Logins.Item($newUserName).Drop()
                        } catch {
                            # just in case the kill didn't work, it'll leave behind a disabled account
                            if ($disabled) { $destServer.Logins.Item($newUserName).Enable() }
                            throw $_
                        }

                        Write-Message -Level Verbose -Message "Successfully dropped $newUserName on $destinstance."
                    } catch {
                        $copyLoginStatus.Status = "Failed"
                        $copyLoginStatus.Notes = (Get-ErrorMessage -Record $_).Message
                        $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Stop-Function -Message "Could not drop $newUserName." -Category InvalidOperation -ErrorRecord $_ -Target $destServer -Continue 3>$null
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($destinstance, "Adding SQL login $newUserName")) {

                Write-Message -Level Verbose -Message "Attempting to add $newUserName to $destinstance."
                try {
                    $splatNewLogin = @{
                        SqlInstance          = $destServer
                        InputObject          = $Login
                        NewSid               = $NewSid
                        LoginRenameHashtable = $LoginRenameHashtable
                    }
                    if ($Login.DefaultDatabase -notin $destServer.Databases.Name) {
                        $copyLoginStatus.Notes = "Database $($Login.DefaultDatabase) does not exist on $destServer, switching DefaultDatabase to 'master' for $($Login.Name)"
                        Write-Message -Level Warning -Message $copyLoginStatus.Notes
                        $splatNewLogin.DefaultDatabase = 'master'
                    }
                    $destLogin = New-DbaLogin @splatNewLogin -EnableException:$true
                    $copyLoginStatus.Status = "Successful"
                } catch {
                    $copyLoginStatus.Status = "Failed"
                    $copyLoginStatus.Notes = (Get-ErrorMessage -Record $_).Message
                    $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    Stop-Function -Message "Failed to add $newUserName to $destinstance." -Category InvalidOperation -ErrorRecord $_ -Target $destServer -Continue 3>$null
                }

                $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                if (-not $ExcludePermissionSync) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Updating SQL login $newUserName permissions")) {
                        # In rare cases, when the instance has a case sensitive collation and there are two logins that differ only in case, New-DbaLogin will return them both into $destLogin
                        # So we loop, just in case...
                        foreach ($dl in $destLogin) {
                            Update-SqlPermission -SourceServer $sourceServer -SourceLogin $Login -DestServer $destServer -DestLogin $dl -ObjectLevel:$ObjectLevel
                        }
                    }
                }
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        $loginsCollection = @()
        if ($InputObject) {
            $loginsCollection += $InputObject
        } else {
            $loginsCollection += Get-DbaLogin -SqlInstance $Source -SqlCredential $SourceSqlCredential -Login $Login -EnableException:$EnableException
        }

        if ($OutFile) {
            return (Export-DbaLogin -SqlInstance $Source -SqlCredential $SourceSqlCredential -FilePath $OutFile -Login $loginsCollection -ObjectLevel:$ObjectLevel -ExcludeLogin $ExcludeLogin -EnableException:$EnableException)
        }
        foreach ($loginObject in $loginsCollection) {
            $sourceServer = $loginObject.Parent
            $sourceVersionMajor = $sourceServer.VersionMajor

            foreach ($destinstance in $Destination) {
                try {
                    $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -AzureUnsupported
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
                }

                $destVersionMajor = $destServer.VersionMajor
                if ($sourceVersionMajor -gt 10 -and $destVersionMajor -lt 11) {
                    Stop-Function -Message "Login migration from version $sourceVersionMajor to $destVersionMajor is not supported." -Target $sourceServer
                }

                if ($sourceVersionMajor -lt 8 -or $destVersionMajor -lt 8) {
                    Stop-Function -Message "SQL Server 7 and below are not supported." -Target $sourceServer
                }

                if ($destserver.ConnectionContext.TrueLogin -notin $destserver.Logins.Name -and $Force) {
                    if ($Login -or $ExcludeLogin -or $InputObject) {
                        Write-Message -Level Verbose -Message "Force was used and $($destserver.ConnectionContext.TrueLogin) not found in logins list but an explicit Login or ExcludeLogin was specified, so we trust you won't drop the group that allows $($destserver.ConnectionContext.TrueLogin) access. Proceeding."
                    } else {
                        Stop-Function -Message "Force was used, no explicit -Login or -ExcludeLogin was specified and $($destserver.ConnectionContext.TrueLogin) cannot be found in the logins list. It may be part of a group. This will likely result in you being locked out of the server. To use Force, $($destserver.ConnectionContext.TrueLogin) must be added directly to logins before proceeding." -Target $destserver
                        continue
                    }
                }

                Write-Message -Level Verbose -Message "Attempting Login Migration."
                Copy-Login -sourceserver $sourceServer -destserver $destServer -Login $loginObject -Exclude $ExcludeLogin

                if ($SyncSaName) {
                    $sa = $sourceServer.Logins | Where-Object id -eq 1
                    $destSa = $destServer.Logins | Where-Object id -eq 1
                    $saName = $sa.Name
                    if ($saName -ne $destSa.name) {
                        Write-Message -Level Verbose -Message "Changing sa username to match source ($saName)."
                        if ($Pscmdlet.ShouldProcess($destinstance, "Changing sa username to match source ($saName)")) {
                            $destSa.Rename($saName)
                            $destSa.Alter()
                        }
                    }
                }
            }
        }
    }
}