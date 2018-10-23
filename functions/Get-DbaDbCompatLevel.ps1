﻿function Get-DbaDbCompatLevel {
<#
    .SYNOPSIS
        Displays the compatibility level for database(s).

    .DESCRIPTION
        Get the current Database Compatability Level for all databases on a server or list of databases passed in to the function.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        SqlCredential object used to connect to the SQL Server as a different user.

    .PARAMETER Database
        The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

    .PARAMETER InputObject
        A collection of databases (such as returned by Get-DbaDatabase)

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step. For example:

        Are you sure you want to perform this action?
        Performing the operation "Update database" on target "pubs on SQL2016\VNEXT".
        [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Compatability, Database
        Author: Garry Bargsley, http://blog.garrybargsley.com/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbCompatLevel

    .EXAMPLE
        PS C:\> Get-DbaDbCompatLevel -SqlInstance localhost\sql2017

        Displays Database Compatability Level for all user databases on server localhost\sql2017

    .EXAMPLE
        PS C:\> Get-DbaDbCompatLevel -SqlInstance localhost\sql2017 -Database Test

        Displays Database Compatability Level for database Test on server localhost\sql2017

#>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Position = 0)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [object[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [Alias('Silent')]
        [switch]$EnableException
    )
    process {

        if (Test-Bound -not 'SqlInstance', 'InputObject') {
            Write-Message -Level Warning -Message "You must specify either a SQL instance or pipe a database collection"
            continue
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
                $server.ConnectionContext.StatementTimeout = [Int32]::MaxValue
            }
            catch {
                Stop-Function -Message "Failed to process Instance $Instance" -ErrorRecord $_ -Target $instance -Continue
            }
            $InputObject += $server.Databases | Where-Object IsAccessible
        }

        $InputObject = $InputObject | Where-Object { $_.IsSystemObject -eq $false }
        if ($Database) {
            $InputObject = $InputObject | Where-Object { $_.Name -contains $Database }
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            $ServerVersion = $server.VersionMajor
            Write-Message -Level Verbose -Message "SQL Server is using Version: $ServerVersion"

            $compat = $db.CompatibilityLevel

            If ($Pscmdlet.ShouldProcess("console", "Outputting object")) {
                $db.Refresh()

                [PSCustomObject]@{
                    ComputerName  = $server.ComputerName
                    InstanceName  = $server.ServiceName
                    SqlInstance   = $server.DomainInstanceName
                    Database      = $db.name
                    Compatibility = $compat
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Invoke-DbaDatabaseUpgrade
    }
}