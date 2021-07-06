function Sync-DbaLoginPermission {
    <#
    .SYNOPSIS
        Copies SQL login permissions from one server to another.

    .DESCRIPTION
        Syncs only SQL Server login permissions, roles, etc. Does not add or drop logins. If a matching login does not exist on the destination, the login will be skipped. Credential removal is not currently supported for this operation.

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

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

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

    .LINK
        https://dbatools.io/Sync-DbaLoginPermission

    .EXAMPLE
        PS C:\> Sync-DbaLoginPermission -Source sqlserver2014a -Destination sqlcluster

        Syncs only SQL Server login permissions, roles, etc. Does not add or drop logins or users. To copy logins and their permissions, use Copy-SqlLogin.

    .EXAMPLE
        PS C:\> Sync-DbaLoginPermission -Source sqlserver2014a -Destination sqlcluster -Exclude realcajun -SourceSqlCredential $scred -DestinationSqlCredential $dcred

        Copies all login permissions except for realcajun using SQL Authentication to connect to each server. If a login already exists on the destination, the permissions will not be migrated.

    .EXAMPLE
        PS C:\> Sync-DbaLoginPermission -Source sqlserver2014a -Destination sqlcluster -Login realcajun, netnerds

        Copies permissions ONLY for logins netnerds and realcajun.

    #>
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [string[]]$Login,
        [string[]]$ExcludeLogin,
        [switch]$EnableException
    )
    begin {
        function Sync-Only {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [object]$sourceServer,
                [object]$destServer,
                [array]$Logins,
                [array]$Exclude
            )

            $stepCounter = 0
            foreach ($sourceLogin in $allLogins) {

                $username = $sourceLogin.Name
                $currentLogin = $sourceServer.ConnectionContext.TrueLogin

                Write-ProgressHelper -Activity "Executing Sync-DbaLoginPermission to sync login permissions from $($sourceServer.Name)" -StepNumber ($stepCounter++) -Message "Updating permissions for $username on $($destServer.Name)" -TotalSteps $allLogins.count

                if ($currentLogin -eq $username) {
                    Write-Message -Level Verbose -Message "Sync does not modify the permissions of the current user. Skipping."
                    continue
                }

                # Here we don't need the FullComputerName, but only the maschine name to compare to the host part of the login name. So ComputerName should be fine.
                $serverName = $sourceServer.ComputerName
                $userBase = ($username.Split("\")[0]).ToLowerInvariant()

                if ($serverName -eq $userBase -or $username.StartsWith("NT ")) {
                    continue
                }

                if ($null -eq ($destLogin = $destServer.Logins.Item($username))) {
                    continue
                }

                Update-SqlPermission -SourceServer $sourceServer -SourceLogin $sourceLogin -DestServer $destServer -DestLogin $destLogin
            }
        }

        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
            $allLogins = Get-DbaLogin -SqlInstance $sourceServer -Login $Login -ExcludeLogin $ExcludeLogin
            $loginName = $allLogins.Name
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if ($null -eq $loginName) {
            Stop-Function -Message "No matching logins found for $($login -join ', ') on $Source"
            return
        }

        foreach ($dest in $Destination) {
            try {
                $destServer = Connect-SqlInstance -SqlInstance $dest -SqlCredential $DestinationSqlCredential -MinimumVersion 8
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $dest -Continue
            }

            if ($PSCmdlet.ShouldProcess("Syncing Logins $Login")) {
                Sync-Only -SourceServer $sourceServer -DestServer $destServer
            }
        }
    }
}