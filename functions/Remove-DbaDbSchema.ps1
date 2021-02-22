function Remove-DbaDbSchema {
    <#
    .SYNOPSIS
        Drops one or more schemas from the specified database(s).

    .DESCRIPTION
        Drops one or more schemas from the specified database(s). As noted in the remarks section of the documentation for DROP SCHEMA there must not be any objects in the schema.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The target database(s).

    .PARAMETER SchemaName
        The name(s) of the schema(s)

    .PARAMETER InputObject
        Allows piping from Get-DbaDatabase.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Data, Database, Migration, Permission, Security, Schema, Table, User
        Author: Adam Lancaster https://github.com/lancasteradam

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbSchema

    .EXAMPLE
        PS C:\> Remove-DbaDbSchema -SqlInstance sqldev01 -Database example1 -SchemaName TestSchema1

        Removes the TestSchema1 schema in the example1 database in the sqldev01 instance.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqldev01, sqldev02 -Database example1 | Remove-DbaDbSchema -SchemaName TestSchema1, TestSchema2

        Passes in the example1 db via pipeline and removes the TestSchema1 and TestSchema2 schemas.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [Parameter(Mandatory)]
        [string[]]$SchemaName,
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

            foreach ($sName in $SchemaName) {

                if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Dropping the schema $sName on the database $($db.Name)")) {
                    try {
                        $schema = $db | Get-DbaDbSchema -SchemaName $sName
                        $schema.Drop()
                    } catch {
                        Stop-Function -Message "Failure on $($db.Parent.Name) to drop the schema $sName in the database $($db.Name)" -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}