function Get-DbaDbccUserOptions {
    <#
    .SYNOPSIS
        Execution of Database Console Command DBCC USEROPTIONS

    .DESCRIPTION
        Returns the results of DBCC USEROPTIONS

        Read more:
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-useroptions-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DBCC
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbccUserOptions

    .EXAMPLE
        PS C:\> Get-DbaDbccUserOptions -SqlInstance Server1

        Get results of DBCC USEROPTIONS for Instance Server1

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbccUserOptions

        Get results of DBCC USEROPTIONS for Instances Sql1 and Sql2/sqlexpress

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Get-DbaDbccUserOptions -SqlInstance Server1 -SqlCredential $cred

        Connects using sqladmin credential and gets results of DBCC USEROPTIONS for Instance Server1 using

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    begin {
        $stringBuilder = New-Object System.Text.StringBuilder
        $null = $stringBuilder.Append("DBCC USEROPTIONS WITH NO_INFOMSGS")
    }
    process {
        $query = $StringBuilder.ToString()

        foreach ($instance in $SqlInstance) {
            Write-Message -Message "Attempting Connection to $instance" -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error connecting to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                Write-Message -Message "Query to run: $query" -Level Verbose
                $results = $server.Query($query)
            } catch {
                Stop-Function -Message "Failure running $query against $instance" -ErrorRecord $_ -Target $server -Continue
            }
            foreach ($row in $results) {
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    SetOption    = $row[0]
                    Value        = $row[1]
                }
            }
        }
    }
}