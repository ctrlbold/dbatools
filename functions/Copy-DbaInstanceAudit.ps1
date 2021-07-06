function Copy-DbaInstanceAudit {
    <#
    .SYNOPSIS
        Copy-DbaInstanceAudit migrates server audits from one SQL Server to another.

    .DESCRIPTION
        By default, all audits are copied. The -Audit parameter is auto-populated for command-line completion and can be used to copy only specific audits.

        If the audit already exists on the destination, it will be skipped unless -Force is used.

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

    .PARAMETER Audit
        The audit(s) to process. Options for this list are auto-populated from the server. If unspecified, all audits will be processed.

    .PARAMETER ExcludeAudit
        The audit(s) to exclude. Options for this list are auto-populated from the server.

    .PARAMETER Path
        Destination file path. If not specified, the file path of the source will be used (or the default data directory).

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        If this switch is enabled, the audits will be dropped and recreated on Destination.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaInstanceAudit

    .EXAMPLE
        PS C:\> Copy-DbaInstanceAudit -Source sqlserver2014a -Destination sqlcluster

        Copies all server audits from sqlserver2014a to sqlcluster, using Windows credentials. If audits with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaInstanceAudit -Source sqlserver2014a -Destination sqlcluster -Audit tg_noDbDrop -SourceSqlCredential $cred -Force

        Copies a single audit, the tg_noDbDrop audit from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If an audit with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaInstanceAudit -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    .EXAMPLE
        PS C:\> Copy-DbaInstanceAudit -Source sqlserver-0 -Destination sqlserver-1 -Audit audit1 -Path 'C:\audit1'

        Copies audit audit1 from sqlserver-0 to sqlserver-1. The file path on sqlserver-1 will be set to 'C:\audit1'.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]
        $SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]
        $DestinationSqlCredential,
        [object[]]$Audit,
        [object[]]$ExcludeAudit,
        [string]$Path,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        $serverAudits = $sourceServer.Audits

        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {

            try {
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            $destAudits = $destServer.Audits
            foreach ($currentAudit in $serverAudits) {
                $auditName = $currentAudit.Name

                $copyAuditStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $auditName
                    Type              = "Server Audit"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($Audit -and $auditName -notin $Audit -or $auditName -in $ExcludeAudit) {
                    continue
                }

                if ($Path) {
                    $currentAudit.FilePath = $Path
                }

                if ($destAudits.Name -contains $auditName) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Server audit $auditName exists at destination. Use -Force to drop and migrate.")) {
                            $copyAuditStatus.Status = "Skipped"
                            $copyAuditStatus.Notes = "Already exists on destination"
                            Write-Message -Level Verbose -Message "Server audit $auditName exists at destination. Use -Force to drop and migrate."
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping server audit $auditName")) {
                            try {
                                Write-Message -Level Verbose -Message "Dropping server audit $auditName."
                                foreach ($spec in $destServer.ServerAuditSpecifications) {
                                    if ($auditSpecification.Auditname -eq $auditName) {
                                        $auditSpecification.Drop()
                                    }
                                }

                                $destServer.audits[$auditName].Disable()
                                $destServer.audits[$auditName].Alter()
                                $destServer.audits[$auditName].Drop()
                            } catch {
                                $copyAuditStatus.Status = "Failed"
                                $copyAuditStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                                Stop-Function -Message "Issue dropping audit from destination." -Target $auditName -ErrorRecord $_
                            }
                        }
                    }
                }

                if ($null -ne ($currentAudit.Filepath) -and -not (Test-DbaPath -SqlInstance $destServer -Path $currentAudit.Filepath)) {
                    if ($Force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "$($currentAudit.Filepath) does not exist on $destinstance. Skipping $auditName. Specify -Force to create the directory.")) {
                            $copyAuditStatus.Status = "Skipped"
                            $copyAuditStatus.Notes = "$($currentAudit.Filepath) does not exist on $destinstance. Skipping $auditName. Specify -Force to create the directory."
                            $copyAuditStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        continue
                    } else {
                        Write-Message -Level Verbose -Message "Force specified. Creating directory."

                        $resolvedComputerName = Resolve-DbaComputerName -ComputerName $destServer
                        $root = $currentAudit.Filepath.Substring(0, 3)
                        $rootUnc = Join-AdminUnc $resolvedComputerName $root

                        if ((Test-Path $rootUnc) -eq $true) {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Creating directory $($currentAudit.Filepath)")) {
                                try {
                                    $null = New-DbaDirectory -SqlInstance $destServer -Path $currentAudit.Filepath -EnableException
                                } catch {
                                    Write-Message -Level Warning -Message "Couldn't create directory $($currentAudit.Filepath). Using default data directory."
                                    $datadir = Get-SqlDefaultPaths $destServer data
                                    $currentAudit.FilePath = $datadir
                                }
                            }
                        } else {
                            $datadir = Get-SqlDefaultPaths $destServer data
                            $currentAudit.FilePath = $datadir
                        }
                    }
                }
                if ($Pscmdlet.ShouldProcess($destinstance, "Creating server audit $auditName")) {
                    try {
                        Write-Message -Level Verbose -Message "File path $($currentAudit.Filepath) exists on $destinstance."
                        Write-Message -Level Verbose -Message "Copying server audit $auditName."
                        $sql = $currentAudit.Script() | Out-String
                        $destServer.Query($sql)
                        $copyAuditStatus.Status = "Successful"
                        $copyAuditStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyAuditStatus.Status = "Failed"
                        $copyAuditStatus.Notes = (Get-ErrorMessage -Record $_)
                        $copyAuditStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Stop-Function -Message "Issue creating audit." -Target $auditName -ErrorRecord $_
                    }
                }
            }
        }
    }
}