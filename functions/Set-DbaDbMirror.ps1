﻿#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Set-DbaDbMirror {
    <#
        .SYNOPSIS
            Sets properties of database mirrors.

        .DESCRIPTION
            Sets properties of database mirrors.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
            to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)
    
        .PARAMETER Database
            The target database.
    
        .PARAMETER Partner
            Sets the partner fqdn.
    
        .PARAMETER Witness
            Sets the witness fqdn.
    
        .PARAMETER SafetyLevel
            Sets the mirroring safety level.
    
        .PARAMETER State
            Sets the mirror state.
    
        .PARAMETER InputObject
            Allows piping from Get-DbaDatabase.
    
        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Mirror, HA
            Author: Chrissy LeMaire (@cl), netnerds.net
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Set-DbaDbMirror

        .EXAMPLE
            PS C:\> Set-DbaDbMirror -SqlInstance localhost

            Returns all Endpoint(s) on the local default SQL Server instance

        .EXAMPLE
            PS C:\> Set-DbaDbMirror -SqlInstance localhost, sql2016

            Returns all Endpoint(s) for the local and sql2016 SQL Server instances
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string]$Partner,
        [string]$Witness,
        [ValidateSet('Full','Off','None')]
        [string]$SafetyLevel,
        [ValidateSet('ForceFailoverAndAllowDataLoss', 'Failover', 'RemoveWitness', 'Resume', 'Suspend', 'Off')]
        [string]$State,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified"
            return
        }
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }
        
        foreach ($db in $InputObject) {
            try {
                if ($Partner) {
                    # use t-sql cuz $db.Alter() doesnt always work against restoring dbs
                    $db.Parent.Query("ALTER DATABASE $db SET PARTNER = N'$Partner'")
                }
                elseif ($Witness) {
                    $db.Parent.Query("ALTER DATABASE $db SET WITNESS = N'$Witness'")
                }
                
                if ($SafetyLevel) {
                    $db.MirroringSafetyLevel = $SafetyLevel
                }
                
                if ($State) {
                    $db.ChangeMirroringState($State)
                }
                
                $db.Alter()
                
                $db
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
    }
}