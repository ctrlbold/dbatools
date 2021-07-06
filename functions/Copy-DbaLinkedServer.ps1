function Copy-DbaLinkedServer {
    <#
    .SYNOPSIS
        Copy-DbaLinkedServer migrates Linked Servers from one SQL Server to another. Linked Server logins and passwords are migrated as well.

    .DESCRIPTION
        By using password decryption techniques provided by Antti Rantasaari (NetSPI, 2014), this script migrates SQL Server Linked Servers from one server to another, while maintaining username and password.

        Credit: https://blog.netspi.com/decrypting-mssql-database-link-server-passwords/

    .PARAMETER Source
        Source SQL Server (2005 and above). You must have sysadmin access to both SQL Server and Windows.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server (2005 and above). You must have sysadmin access to both SQL Server and Windows.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER LinkedServer
        The linked server(s) to process - this list is auto-populated from the server. If unspecified, all linked servers will be processed.

    .PARAMETER ExcludeLinkedServer
        The linked server(s) to exclude - this list is auto-populated from the server

    .PARAMETER UpgradeSqlClient
        Upgrade any SqlClient Linked Server to the current version

    .PARAMETER ExcludePassword
        Copies the logins but does not access, decrypt or create sensitive information

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        By default, if a Linked Server exists on the source and destination, the Linked Server is not copied over. Specifying -force will drop and recreate the Linked Server on the Destination server.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: WSMan, Migration, LinkedServer
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers
        Limitations: This just copies the SQL portion. It does not copy files (i.e. a local SQLite database, or Microsoft Access DB), nor does it configure ODBC entries.

    .LINK
        https://dbatools.io/Copy-DbaLinkedServer

    .EXAMPLE
        PS C:\> Copy-DbaLinkedServer -Source sqlserver2014a -Destination sqlcluster

        Copies all SQL Server Linked Servers on sqlserver2014a to sqlcluster. If Linked Server exists on destination, it will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaLinkedServer -Source sqlserver2014a -Destination sqlcluster -LinkedServer SQL2K5,SQL2k -Force

        Copies over two SQL Server Linked Servers (SQL2K and SQL2K2) from sqlserver to sqlcluster. If the credential already exists on the destination, it will be dropped.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Justification = "Internal functions are ignored")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$LinkedServer,
        [object[]]$ExcludeLinkedServer,
        [switch]$UpgradeSqlClient,
        [switch]$ExcludePassword,
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

        function Copy-DbaLinkedServers {
            param (
                [string[]]$LinkedServer,
                [bool]$force
            )

            Write-Message -Level Verbose -Message "Collecting Linked Server logins and passwords on $($sourceServer.Name)."
            if ($ExcludePassword) {
                $sourcelogins = @()
                foreach ($svr in $sourceServer.LinkedServers) {
                    $sourcelogins += [pscustomobject]@{
                        Name     = $sourcelogin.Name
                        Identity = $sourcelogin.LinkedServerLogins.RemoteUser
                        Password = $null
                    }
                }
            } else {
                $sourcelogins = Get-DecryptedObject -SqlInstance $sourceServer -Type LinkedServer
            }

            $serverlist = $sourceServer.LinkedServers

            if ($LinkedServer) {
                $serverlist = $serverlist | Where-Object Name -In $LinkedServer
            }
            if ($ExcludeLinkedServer) {
                $serverList = $serverlist | Where-Object Name -NotIn $ExcludeLinkedServer
            }

            foreach ($currentLinkedServer in $serverlist) {
                $provider = $currentLinkedServer.ProviderName
                try {
                    $destServer.LinkedServers.Refresh()
                    $destServer.LinkedServers.LinkedServerLogins.Refresh()
                } catch {
                    #here to avoid an empty catch
                    $null = 1
                }

                $linkedServerName = $currentLinkedServer.Name
                $linkedServerProductName = $currentLinkedServer.ProductName
                $linkedServerDataSource = $currentLinkedServer.DataSource

                $copyLinkedServer = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $linkedServerName
                    ProductName       = $linkedServerProductName
                    DataSource        = $linkedServerDataSource
                    Type              = "Linked Server"
                    Status            = $null
                    Notes             = $provider
                    DateTime          = [DbaDateTime](Get-Date)
                }

                # This does a check to warn of missing OleDbProviderSettings but should only be checked on SQL on Windows
                if ($destServer.Settings.OleDbProviderSettings.Name.Length -ne 0) {
                    if (!$destServer.Settings.OleDbProviderSettings.Name -contains $provider -and !$provider.StartsWith("SQLN")) {
                        $copyLinkedServer.Status = "Skipped"
                        $copyLinkedServer.Notes = "Missing provider"
                        $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Write-Message -Level Verbose -Message "$($destServer.Name) does not support the $provider provider. Skipping $linkedServerName."
                        continue
                    }
                }

                if ($null -ne $destServer.LinkedServers[$linkedServerName]) {
                    if (!$force) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "$linkedServerName exists $($destServer.Name). Skipping.")) {
                            $copyLinkedServer.Status = "Skipped"
                            $copyLinkedServer.Notes = "Already exists on destination"
                            $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "$linkedServerName exists $($destServer.Name). Skipping."
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping $linkedServerName")) {
                            if ($currentLinkedServer.Name -eq 'repl_distributor') {
                                Write-Message -Level Verbose -Message "repl_distributor cannot be dropped. Not going to try."
                                continue
                            }

                            $destServer.LinkedServers[$linkedServerName].Drop($true)
                            $destServer.LinkedServers.refresh()
                        }
                    }
                }

                Write-Message -Level Verbose -Message "Attempting to migrate: $linkedServerName."
                If ($Pscmdlet.ShouldProcess($destinstance, "Migrating $linkedServerName")) {
                    try {
                        $sql = $currentLinkedServer.Script() | Out-String
                        Write-Message -Level Debug -Message $sql

                        if ($UpgradeSqlClient -and $sql -match "sqlncli") {
                            $destProviders = $destServer.Settings.OleDbProviderSettings | Where-Object { $_.Name -like 'SQLNCLI*' }
                            $newProvider = $destProviders | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name

                            Write-Message -Level Verbose -Message "Changing sqlncli to $newProvider"
                            $sql = $sql -replace ("sqlncli[0-9]+", $newProvider)
                        }

                        $destServer.Query($sql)

                        if ($copyLinkedServer.ProductName -eq 'SQL Server' -and $copyLinkedServer.Name -ne $copyLinkedServer.DataSource) {
                            $sql2 = "EXEC sp_setnetname '$($copyLinkedServer.Name)', '$($copyLinkedServer.DataSource)'; "
                            $destServer.Query($sql2)
                        }

                        $destServer.LinkedServers.Refresh()
                        Write-Message -Level Verbose -Message "$linkedServerName successfully copied."

                        $copyLinkedServer.Status = "Successful"
                        $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyLinkedServer.Status = "Failed"
                        $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Stop-Function -Message "Issue adding linked server $destServer." -Target $linkedServerName -InnerErrorRecord $_
                        $skiplogins = $true
                    }
                }

                if ($skiplogins -ne $true) {
                    $destlogins = $destServer.LinkedServers[$linkedServerName].LinkedServerLogins
                    $lslogins = $sourcelogins | Where-Object { $_.Name -eq $linkedServerName }

                    foreach ($login in $lslogins) {
                        $currentlogin = $destlogins | Where-Object { $_.RemoteUser -eq $login.Identity }

                        $copyLinkedServer.Type = $login.Identity

                        if ($currentlogin.RemoteUser.length -ne 0) {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Migrating linked server identity $($login.Identity)")) {
                                try {
                                    if ($login.Password) {
                                        $currentlogin.SetRemotePassword($login.Password)
                                        $currentlogin.Alter()
                                    }

                                    $copyLinkedServer.Status = "Successful"
                                    $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                } catch {
                                    $copyLinkedServer.Status = "Failed"
                                    $copyLinkedServer | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                                    Stop-Function -Message "Failed to copy login." -Target $login -InnerErrorRecord $_
                                }
                            }
                        }
                    }
                }
            }
        }

        if ($null -ne $SourceSqlCredential.Username) {
            Write-Message -Level Verbose -Message "You are using a SQL Credential. Note that this script requires Windows Administrator access on the source server. Attempting with $($SourceSqlCredential.Username)."
        }
        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
            return
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        if (!(Test-SqlSa -SqlInstance $sourceServer -SqlCredential $SourceSqlCredential)) {
            Stop-Function -Message "Not a sysadmin on $source. Quitting." -Target $sourceServer
            return
        }

        Write-Message -Level Verbose -Message "Checking if Remote Registry is enabled on $Source."
        $resolvedComputerName = Resolve-DbaComputerName -ComputerName $Source
        try {
            $null = Invoke-Command2 -ComputerName $resolvedComputerName -ScriptBlock { Get-ItemProperty -Path "HKLM:\SOFTWARE\" }
        } catch {
            Stop-Function -Message "Can't connect to registry on $Source." -Target $resolvedComputerName -ErrorRecord $_
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            if (!(Test-SqlSa -SqlInstance $destServer -SqlCredential $DestinationSqlCredential)) {
                Stop-Function -Message "Not a sysadmin on $destinstance" -Target $destServer -Continue
            }

            # Magic happens here
            Copy-DbaLinkedServers $LinkedServer -Force:$force
        }
    }
}