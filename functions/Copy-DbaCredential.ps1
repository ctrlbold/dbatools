function Copy-DbaCredential {
    <#
    .SYNOPSIS
        Copy-DbaCredential migrates SQL Server Credentials from one SQL Server to another while maintaining Credential passwords.

    .DESCRIPTION
        By using password decryption techniques provided by Antti Rantasaari (NetSPI, 2014), this script migrates SQL Server Credentials from one server to another while maintaining username and password.

        Credit: https://blog.netspi.com/decrypting-mssql-database-link-server-passwords/

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

    .PARAMETER Credential
        This command requires access to the Windows OS via PowerShell remoting. Use this credential to connect to Windows using alternative credentials.

    .PARAMETER Name
        Only include specific names
        Note: if spaces exist in the credential name, you will have to type "" or '' around it.

    .PARAMETER ExcludeName
        Excluded credential names

    .PARAMETER Identity
        Only include specific identities
        Note: if spaces exist in the credential identity, you will have to type "" or '' around it.

    .PARAMETER ExcludeIdentity
        Excluded identities

    .PARAMETER Force
        If this switch is enabled, the Credential will be dropped and recreated if it already exists on Destination.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: WSMan, Migration
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires:
        - PowerShell Version 3.0
        - Administrator access on Windows
        - sysadmin access on SQL Server.
        - DAC access enabled for local (default)

    .LINK
        https://dbatools.io/Copy-DbaCredential

    .EXAMPLE
        PS C:\> Copy-DbaCredential -Source sqlserver2014a -Destination sqlcluster

        Copies all SQL Server Credentials on sqlserver2014a to sqlcluster. If Credentials exist on destination, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaCredential -Source sqlserver2014a -Destination sqlcluster -Name "PowerShell Proxy Account" -Force

        Copies over one SQL Server Credential (PowerShell Proxy Account) from sqlserver to sqlcluster. If the Credential already exists on the destination, it will be dropped and recreated.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]
        $SourceSqlCredential,
        [PSCredential]
        $Credential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [string[]]$Name,
        [string[]]$ExcludeName,
        [Alias('CredentialIdentity')]
        [string[]]$Identity,
        [Alias('ExcludeCredentialIdentity')]
        [string[]]$ExcludeIdentity,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if (-not $script:isWindows) {
            Stop-Function -Message "Copy-DbaCredential is only supported on Windows"
            return
        }
        $null = Test-ElevationRequirement -ComputerName $Source.ComputerName

        if ($Force) { $ConfirmPreference = 'none' }

        function Copy-Credential {
            <#
                .SYNOPSIS
                    Copies Credentials from one server to another using a combination of SMO's .Script() and manual password updates.

                .OUTPUT
                    System.Data.DataTable
            #>
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "", Justification = "For Credentials")]
            param (
                [string[]]$Credentials,
                [bool]$Force
            )

            Write-Message -Level Verbose -Message "Collecting Credential logins and passwords on $($sourceServer.Name)"
            $sourceCredentials = Get-DecryptedObject -SqlInstance $sourceServer -Type Credential
            $credentialList = Get-DbaCredential -SqlInstance $sourceServer -Name $Name -ExcludeName $ExcludeName -Identity $Identity -ExcludeIdentity $ExcludeIdentity

            Write-Message -Level Verbose -Message "Starting migration"
            foreach ($credential in $credentialList) {
                $destServer.Credentials.Refresh()
                $credentialName = $credential.Name

                $copyCredentialStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Type              = "Credential"
                    Name              = $credentialName
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($null -ne $destServer.Credentials[$credentialName]) {
                    if (!$force) {
                        $copyCredentialStatus.Status = "Skipping"
                        $copyCredentialStatus.Notes = "Already exists on destination"
                        if ($Pscmdlet.ShouldProcess($destServer.Name, "Skipping $credentialName, already exists")) {
                            $copyCredentialStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }

                        Write-Message -Level Verbose -Message "$credentialName exists $($destServer.Name). Skipping."
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance.Name, "Dropping $credentialName")) {
                            $destServer.Credentials[$credentialName].Drop()
                            $destServer.Credentials.Refresh()
                        }
                    }
                }

                Write-Message -Level Verbose -Message "Attempting to migrate $credentialName"
                try {
                    $currentCred = $sourceCredentials | Where-Object { $_.Name -eq "[$credentialName]" }
                    $sqlcredentialName = $credentialName.Replace("'", "''")
                    $identity = $currentCred.Identity.Replace("'", "''")
                    $password = $currentCred.Password.Replace("'", "''")
                    if ($Pscmdlet.ShouldProcess($destinstance.Name, "Copying $identity ($credentialName)")) {
                        $destServer.Query("CREATE CREDENTIAL [$sqlcredentialName] WITH IDENTITY = N'$identity', SECRET = N'$password'")
                        $destServer.Credentials.Refresh()
                        Write-Message -Level Verbose -Message "$credentialName successfully copied"
                        $copyCredentialStatus.Status = "Successful"
                        $copyCredentialStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                } catch {
                    $copyCredentialStatus.Status = "Failed"
                    $copyCredentialStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    Stop-Function -Message "Error creating credential" -Target $credentialName -ErrorRecord $_
                }
            }
        }

        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }

        if ($null -ne $SourceSqlCredential.Username) {
            Write-Message -Level Verbose -Message "You are using SQL credentials and this script requires Windows admin access to the $Source server. Trying anyway."
        }

        Invoke-SmoCheck -SqlInstance $sourceServer

        Write-Message -Level Verbose -Message "Checking if Remote Registry is enabled on $Source"
        $resolvedComputerName = Resolve-DbaComputerName -ComputerName $Source -Credential $Credential
        try {
            $null = Invoke-Command2 -ComputerName $resolvedComputerName -Credential $Credential -ScriptBlock { Get-ItemProperty -Path "HKLM:\SOFTWARE\" }
        } catch {
            Stop-Function -Message "Can't connect to registry on $Source" -Target $resolvedComputerName -ErrorRecord $_
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            Invoke-SmoCheck -SqlInstance $destServer

            Copy-Credential $credentials -force:$force
        }
    }
}
