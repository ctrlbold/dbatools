#requires -Version 3.0
param(
    [Collections.IDictionary]
    [Alias('Options')]
    $Option = @{ }
)

$start = [DateTime]::Now

if (($PSVersionTable.PSVersion.Major -lt 6) -or ($PSVersionTable.Platform -and $PSVersionTable.Platform -eq 'Win32NT')) {
    $script:isWindows = $true
} else {
    $script:isWindows = $false
}

if ($IsLinux -or $IsMacOS) {
    # this doesn't exist by default
    # https://github.com/PowerShell/PowerShell/issues/1262
    $env:COMPUTERNAME = hostname
}

if ('Sqlcollaborative.Dbatools.dbaSystem.DebugHost' -as [Type]) {
    # If we've already got for module import,
    [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::ImportTimeEntries.Clear() # clear it (since we're clearly re-importing)
}

#region Import helper functions
function Import-ModuleFile {
    <#
    .SYNOPSIS
        Helps import dbatools files according to configuration

    .DESCRIPTION
        Helps import dbatools files according to configuration
        Always dotsource this function!

    .PARAMETER Path
        The full path to the file to import

    .EXAMPLE
        PS C:\> Import-ModuleFile -Path $function.FullName

        Imports the file stored at '$function.FullName'
    #>
    [CmdletBinding()]
    param (
        $Path
    )

    if (-not $path) {
        return
    }

    if ($script:doDotSource) {
        . (Resolve-Path -Path $Path)
    } else {
        $txt = [IO.File]::ReadAllText((Resolve-Path -Path $Path).ProviderPath)
        $ExecutionContext.InvokeCommand.InvokeScript($TXT, $false, [Management.Automation.Runspaces.PipelineResultTypes]::None, $null, $null)
    }
}

function Write-ImportTime {
    <#
    .SYNOPSIS
        Writes an entry to the import module time debug list

    .DESCRIPTION
        Writes an entry to the import module time debug list

    .PARAMETER Text
        The message to write

    .EXAMPLE
        PS C:\> Write-ImportTime -Text "Starting SMO Import"

        Adds the message "Starting SMO Import" to the debug list
#>
    param (
        [string]$Text,
        $Timestamp = ([DateTime]::now)
    )


    if (-not $script:dbatools_ImportPerformance) {
        $script:dbatools_ImportPerformance = New-Object Collections.ArrayList
    }

    if (-not ('Sqlcollaborative.Dbatools.Configuration.Config' -as [type])) {
        $script:dbatools_ImportPerformance.AddRange(@(New-Object PSObject -Property @{ Time = $timestamp; Action = $Text }))
    } else {
        if ([Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::ImportTimeEntries.Count -eq 0) {
            foreach ($entry in $script:dbatools_ImportPerformance) {
                $te = New-Object Sqlcollaborative.Dbatools.dbaSystem.StartTimeEntry($entry.Action, $entry.Time, [Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId)
                [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::ImportTimeEntries.Add($te)
            }
            $script:dbatools_ImportPerformance.Clear()
        }
        $te = New-Object Sqlcollaborative.Dbatools.dbaSystem.StartTimeEntry($Text, $timestamp, ([Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId))
        [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::ImportTimeEntries.Add($te)
    }
}

Write-ImportTime -Text "Start" -Timestamp $start
Write-ImportTime -Text "Loading System.Security"
Add-Type -AssemblyName System.Security
Write-ImportTime -Text "Loading import helper functions"
#endregion Import helper functions

# Not supporting the provider path at this time 2/28/2017
if ($ExecutionContext.SessionState.Path.CurrentLocation.Drive.Name -eq 'SqlServer') {
    Write-Warning "SQLSERVER:\ provider not supported. Please change to another directory and reload the module."
    Write-Warning "Going to continue loading anyway, but expect issues."
}

Write-ImportTime -Text "Resolved path to not SQLSERVER PSDrive"

$script:PSModuleRoot = $PSScriptRoot

if ($PSVersionTable.PSEdition -and $PSVersionTable.PSEdition -ne 'Desktop') {
    $script:core = $true
} else {
    $script:core = $false
}

#region Import Defines
if ($psVersionTable.Platform -ne 'Unix' -and 'Microsoft.Win32.Registry' -as [Type]) {
    $regType = 'Microsoft.Win32.Registry' -as [Type]
    $hkcuNode = $regType::CurrentUser.OpenSubKey("SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System")
    if ($dbaToolsSystemNode) {
        $userValues = @{ }
        foreach ($v in $hkcuNode.GetValueNames()) {
            $userValues[$v] = $hkcuNode.GetValue($v)
        }
        $dbatoolsSystemUserNode = $systemValues
    }
    $hklmNode = $regType::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System")
    if ($dbaToolsSystemNode) {
        $systemValues = @{ }
        foreach ($v in $hklmNode.GetValueNames()) {
            $systemValues[$v] = $hklmNode.GetValue($v)
        }
        $dbatoolsSystemSystemNode = $systemValues
    }
} else {
    $dbatoolsSystemUserNode = @{ }
    $dbatoolsSystemSystemNode = @{ }
}

#region Dot Sourcing
# Detect whether at some level dotsourcing was enforced
$script:doDotSource = $dbatools_dotsourcemodule -or
$dbatoolsSystemSystemNode.DoDotSource -or
$dbatoolsSystemUserNode.DoDotSource -or
$option.DoDotSource
#endregion Dot Sourcing

#region Copy DLL Mode
# copy dll mode adds mess but is useful for installations using install.ps1
$script:copyDllMode = $dbatools_copydllmode -or
$dbatoolsSystemSystemNode.CopyDllMode -or
$dbatoolsSystemUserNode.CopyDllMode -or
$option.CopyDllMode
#endregion Copy DLL Mode

#region Always Compile
$script:alwaysBuildLibrary = $dbatools_alwaysbuildlibrary -or
$dbatoolsSystemSystemNode.AlwaysBuildLibrary -or
$dbatoolsSystemUserNode.AlwaysBuildLibrary -or
$option.AlwaysBuildLibrary
#endregion Always Compile

#region Serial Import
$script:serialImport = $dbatools_serialimport -or
$dbatoolsSystemSystemNode.SerialImport -or
$dbatoolsSystemUserNode.SerialImport -or
$Option.SerialImport
#endregion Serial Import

#region Multi File Import
$script:multiFileImport = $dbatools_multiFileImport -or
$dbatoolsSystemSystemNode.MultiFileImport -or
$dbatoolsSystemUserNode.MultiFileImport -or
$option.MultiFileImport


$gitDir = $script:PSModuleRoot, '.git' -join [IO.Path]::DirectorySeparatorChar
if ($dbatools_enabledebug -or
    $option.Debug -or
    $DebugPreference -ne 'silentlycontinue' -or
    [IO.Directory]::Exists($gitDir)) {
    $script:multiFileImport, $script:SerialImport, $script:doDotSource = $true, $true, $true
}
#endregion Multi File Import

Write-ImportTime -Text "Validated defines"
#endregion Import Defines

if (($PSVersionTable.PSVersion.Major -le 5) -or $script:isWindows) {
    Get-ChildItem -Path (Resolve-Path "$script:PSModuleRoot\bin\") -Filter "*.dll" -Recurse | Unblock-File -ErrorAction Ignore
    Write-ImportTime -Text "Unblocking Files"
}

$script:DllRoot = (Resolve-Path -Path "$script:PSModuleRoot\bin\").ProviderPath

<#
If dbatools has not been imported yet, it also hasn't done libraries yet. Fix that.
Previously checked for SMO being available, but that would break import with SqlServer loaded
Some people also use the dbatools library for other things without the module, so also check,
whether the modulebase has been set (first thing it does after loading library through dbatools import)
Theoretically, there's a minor cuncurrency collision risk with that, but since the cost is only
a little import time loss if that happens ...
#>
if ((-not ('Sqlcollaborative.Dbatools.dbaSystem.DebugHost' -as [type])) -or (-not [Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleBase)) {
    . $script:psScriptRoot\internal\scripts\libraryimport.ps1
    Write-ImportTime -Text "Starting import SMO libraries"
}

<#

    Do the rest of the loading

#>

# This technique helps a little bit
# https://becomelotr.wordpress.com/2017/02/13/expensive-dot-sourcing/

# Load our own custom library
# Should always come before function imports
. $psScriptRoot\bin\library.ps1
. $psScriptRoot\bin\typealiases.ps1
Write-ImportTime -Text "Loading dbatools library"

# Tell the library where the module is based, just in case
[Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleBase = $script:PSModuleRoot

if ($script:multiFileImport -or -not (Test-Path -Path "$psScriptRoot\allcommands.ps1")) {
    # All internal functions privately available within the toolset
    foreach ($file in (Get-ChildItem -Path "$psScriptRoot\internal\functions\" -Recurse -Filter *.ps1)) {
        . $file.FullName
    }
    Write-ImportTime -Text "Loading Internal Commands"

    #    . $psScriptRoot\internal\scripts\cmdlets.ps1

    Write-ImportTime -Text "Registering cmdlets"

    # All exported functions
    foreach ($file in (Get-ChildItem -Path "$script:PSModuleRoot\functions\" -Recurse -Filter *.ps1)) {
        . $file.FullName
    }
    Write-ImportTime -Text "Loading Public Commands"

} else {
    #    . $psScriptRoot\internal\scripts\cmdlets.ps1
    Write-Verbose -Message "Loading allcommands.ps1 to speed up import times"
    . $psScriptRoot\allcommands.ps1
    #. (Resolve-Path -Path "$script:PSModuleRoot\allcommands.ps1")
    Write-ImportTime -Text "Loading Public and Private Commands"

    Write-ImportTime -Text "Registering cmdlets"
}

# Load configuration system
# Should always go after library and path setting
. $psScriptRoot\internal\configurations\configuration.ps1
Write-ImportTime -Text "Configuration System"

# Resolving the path was causing trouble when it didn't exist yet
# Not converting the path separators based on OS was also an issue.
if (-not ([Sqlcollaborative.Dbatools.Message.LogHost]::LoggingPath)) {
    [Sqlcollaborative.Dbatools.Message.LogHost]::LoggingPath = Join-DbaPath $script:AppData "PowerShell" "dbatools"
}

# Run all optional code
# Note: Each optional file must include a conditional governing whether it's run at all.
# Validations were moved into the other files, in order to prevent having to update dbatools.psm1 every time
# 96ms
foreach ($file in (Get-ChildItem -Path "$script:PSScriptRoot\optional" -Filter *.ps1)) {
    . $file.FullName
}
Write-ImportTime -Text "Loading Optional Commands"

# Process TEPP parameters
. $psScriptRoot\internal\scripts\insertTepp.ps1
Write-ImportTime -Text "Loading TEPP"


# Process transforms
. $psScriptRoot\internal\scripts\message-transforms.ps1
Write-ImportTime -Text "Loading Message Transforms"

# Load scripts that must be individually run at the end #
#-------------------------------------------------------#

# Start the logging system (requires the configuration system up and running)
. $psScriptRoot\internal\scripts\logfilescript.ps1
Write-ImportTime -Text "Script: Logging"

# Start the tepp asynchronous update system (requires the configuration system up and running)
. $psScriptRoot\internal\scripts\updateTeppAsync.ps1
Write-ImportTime -Text "Script: Asynchronous TEPP Cache"

# Start the maintenance system (requires pretty much everything else already up and running)
. $psScriptRoot\internal\scripts\dbatools-maintenance.ps1
Write-ImportTime -Text "Script: Maintenance"

#region Aliases

# New 3-char aliases
$shortcuts = @{
    'ivq' = 'Invoke-DbaQuery'
    'cdi' = 'Connect-DbaInstance'
}
foreach ($_ in $shortcuts.GetEnumerator()) {
    New-Alias -Name $_.Key -Value $_.Value
}

# Leave forever
$forever = @{
    'Get-DbaRegisteredServer' = 'Get-DbaRegServer'
    'Attach-DbaDatabase'      = 'Mount-DbaDatabase'
    'Detach-DbaDatabase'      = 'Dismount-DbaDatabase'
    'Start-SqlMigration'      = 'Start-DbaMigration'
    'Write-DbaDataTable'      = 'Write-DbaDbTableData'
    'Get-DbaDbModule'         = 'Get-DbaModule'
}
foreach ($_ in $forever.GetEnumerator()) {
    Set-Alias -Name $_.Key -Value $_.Value
}
#endregion Aliases

#region Post-Import Cleanup
Write-ImportTime -Text "Loading Aliases"

# region Commands
$script:xplat = @(
    'Start-DbaMigration',
    'Copy-DbaDatabase',
    'Copy-DbaLogin',
    'Copy-DbaAgentServer',
    'Copy-DbaSpConfigure',
    'Copy-DbaDbMail',
    'Copy-DbaDbAssembly',
    'Copy-DbaAgentSchedule',
    'Copy-DbaAgentOperator',
    'Copy-DbaAgentJob',
    'Copy-DbaCustomError',
    'Copy-DbaInstanceAuditSpecification',
    'Copy-DbaEndpoint',
    'Copy-DbaInstanceAudit',
    'Copy-DbaServerRole',
    'Copy-DbaResourceGovernor',
    'Copy-DbaXESession',
    'Copy-DbaInstanceTrigger',
    'Copy-DbaRegServer',
    'Copy-DbaSysDbUserObject',
    'Copy-DbaAgentProxy',
    'Copy-DbaAgentAlert',
    'Copy-DbaStartupProcedure',
    'Get-DbaDbDetachedFileInfo',
    'Copy-DbaAgentJobCategory',
    'Test-DbaPath',
    'Export-DbaLogin',
    'Watch-DbaDbLogin',
    'Expand-DbaDbLogFile',
    'Test-DbaMigrationConstraint',
    'Test-DbaNetworkLatency',
    'Find-DbaDbDuplicateIndex',
    'Remove-DbaDatabaseSafely',
    'Set-DbaTempdbConfig',
    'Test-DbaTempdbConfig',
    'Repair-DbaDbOrphanUser',
    'Remove-DbaDbOrphanUser',
    'Find-DbaDbUnusedIndex',
    'Get-DbaDbSpace',
    'Test-DbaDbOwner',
    'Set-DbaDbOwner',
    'Test-DbaAgentJobOwner',
    'Set-DbaAgentJobOwner',
    'Measure-DbaDbVirtualLogFile',
    'Get-DbaDbRestoreHistory',
    'Get-DbaTcpPort',
    'Test-DbaDbCompatibility',
    'Test-DbaDbCollation',
    'Test-DbaConnectionAuthScheme',
    'Test-DbaInstanceName',
    'Repair-DbaInstanceName',
    'Stop-DbaProcess',
    'Find-DbaOrphanedFile',
    'Get-DbaAvailabilityGroup',
    'Get-DbaLastGoodCheckDb',
    'Get-DbaProcess',
    'Get-DbaRunningJob',
    'Set-DbaMaxDop',
    'Test-DbaDbRecoveryModel',
    'Test-DbaMaxDop',
    'Remove-DbaBackup',
    'Get-DbaPermission',
    'Get-DbaLastBackup',
    'Connect-DbaInstance',
    'Get-DbaDbBackupHistory',
    'Get-DbaAgBackupHistory',
    'Read-DbaBackupHeader',
    'Test-DbaLastBackup',
    'Get-DbaMaxMemory',
    'Set-DbaMaxMemory',
    'Get-DbaDbSnapshot',
    'Remove-DbaDbSnapshot',
    'Get-DbaDbRoleMember',
    'Get-DbaServerRoleMember',
    'Get-DbaDbAsymmetricKey',
    'New-DbaDbAsymmetricKey',
    'Remove-DbaDbAsymmetricKey',
    'Invoke-DbaDbTransfer',
    'New-DbaDbTransfer',
    'Remove-DbaDbData',
    'Resolve-DbaNetworkName',
    'Export-DbaAvailabilityGroup',
    'Write-DbaDbTableData',
    'New-DbaDbSnapshot',
    'Restore-DbaDbSnapshot',
    'Get-DbaInstanceTrigger',
    'Get-DbaDbTrigger',
    'Get-DbaDbState',
    'Set-DbaDbState',
    'Get-DbaHelpIndex',
    'Get-DbaAgentAlert',
    'Get-DbaAgentOperator',
    'Get-DbaSpConfigure',
    'Rename-DbaLogin',
    'Find-DbaAgentJob',
    'Find-DbaDatabase',
    'Get-DbaXESession',
    'Export-DbaXESession',
    'Test-DbaOptimizeForAdHoc',
    'Find-DbaStoredProcedure',
    'Measure-DbaBackupThroughput',
    'Get-DbaDatabase',
    'Find-DbaUserObject',
    'Get-DbaDependency',
    'Find-DbaCommand',
    'Backup-DbaDatabase',
    'New-DbaDirectory',
    'Get-DbaDbQueryStoreOption',
    'Set-DbaDbQueryStoreOption',
    'Restore-DbaDatabase',
    'Get-DbaDbFileMapping',
    'Copy-DbaDbQueryStoreOption',
    'Get-DbaExecutionPlan',
    'Export-DbaExecutionPlan',
    'Set-DbaSpConfigure',
    'Test-DbaIdentityUsage',
    'Get-DbaDbAssembly',
    'Get-DbaAgentJob',
    'Get-DbaCustomError',
    'Get-DbaCredential',
    'Get-DbaBackupDevice',
    'Get-DbaAgentProxy',
    'Get-DbaDbEncryption',
    'Remove-DbaDatabase',
    'Get-DbaQueryExecutionTime',
    'Get-DbaTempdbUsage',
    'Find-DbaDbGrowthEvent',
    'Test-DbaLinkedServerConnection',
    'Get-DbaDbFile',
    'Get-DbaDbFileGrowth',
    'Set-DbaDbFileGrowth',
    'Read-DbaTransactionLog',
    'Get-DbaDbTable',
    'Invoke-DbaDbShrink',
    'Get-DbaEstimatedCompletionTime',
    'Get-DbaLinkedServer',
    'New-DbaAgentJob',
    'Get-DbaLogin',
    'New-DbaScriptingOption',
    'Save-DbaDiagnosticQueryScript',
    'Invoke-DbaDiagnosticQuery',
    'Export-DbaDiagnosticQuery',
    'Invoke-DbaWhoIsActive',
    'Set-DbaAgentJob',
    'Remove-DbaAgentJob',
    'New-DbaAgentJobStep',
    'Set-DbaAgentJobStep',
    'Remove-DbaAgentJobStep',
    'New-DbaAgentSchedule',
    'Set-DbaAgentSchedule',
    'Remove-DbaAgentSchedule',
    'Backup-DbaDbCertificate',
    'Get-DbaDbCertificate',
    'Get-DbaEndpoint',
    'Get-DbaDbMasterKey',
    'Get-DbaSchemaChangeHistory',
    'Get-DbaInstanceAudit',
    'Get-DbaInstanceAuditSpecification',
    'Get-DbaProductKey',
    'Get-DbatoolsLog',
    'Restore-DbaDbCertificate',
    'New-DbaDbCertificate',
    'New-DbaDbMasterKey',
    'New-DbaServiceMasterKey',
    'Remove-DbaDbCertificate',
    'Remove-DbaDbMasterKey',
    'Get-DbaInstanceProperty',
    'Get-DbaInstanceUserOption',
    'New-DbaConnectionString',
    'Get-DbaAgentSchedule',
    'Read-DbaTraceFile',
    'Get-DbaInstanceInstallDate',
    'Backup-DbaDbMasterKey',
    'Get-DbaAgentJobHistory',
    'Get-DbaMaintenanceSolutionLog',
    'Invoke-DbaDbLogShipRecovery',
    'Find-DbaTrigger',
    'Find-DbaView',
    'Invoke-DbaDbUpgrade',
    'Get-DbaDbUser',
    'Get-DbaAgentLog',
    'Get-DbaDbMailLog',
    'Get-DbaDbMailHistory',
    'Get-DbaDbView',
    'Remove-DbaDbView',
    'New-DbaSqlParameter',
    'Get-DbaDbUdf',
    'Get-DbaDbPartitionFunction',
    'Get-DbaDbPartitionScheme',
    'Get-DbaDefaultPath',
    'Get-DbaDbStoredProcedure',
    'Test-DbaDbCompression',
    'Mount-DbaDatabase',
    'Dismount-DbaDatabase',
    'Get-DbaAgReplica',
    'Get-DbaAgDatabase',
    'Get-DbaModule',
    'Sync-DbaLoginPermission',
    'New-DbaCredential',
    'Get-DbaFile',
    'Set-DbaDbCompression',
    'Get-DbaTraceFlag',
    'Invoke-DbaCycleErrorLog',
    'Get-DbaAvailableCollation',
    'Get-DbaUserPermission',
    'Get-DbaAgHadr',
    'Find-DbaSimilarTable',
    'Get-DbaTrace',
    'Get-DbaSuspectPage',
    'Get-DbaWaitStatistic',
    'Clear-DbaWaitStatistics',
    'Get-DbaTopResourceUsage',
    'New-DbaLogin',
    'Get-DbaAgListener',
    'Invoke-DbaDbClone',
    'Disable-DbaTraceFlag',
    'Enable-DbaTraceFlag',
    'Start-DbaAgentJob',
    'Stop-DbaAgentJob',
    'New-DbaAgentProxy',
    'Test-DbaDbLogShipStatus',
    'Get-DbaXESessionTarget',
    'New-DbaXESmartTargetResponse',
    'New-DbaXESmartTarget',
    'Get-DbaDbVirtualLogFile',
    'Get-DbaBackupInformation',
    'Start-DbaXESession',
    'Stop-DbaXESession',
    'Set-DbaDbRecoveryModel',
    'Get-DbaDbRecoveryModel',
    'Get-DbaWaitingTask',
    'Remove-DbaDbUser',
    'Get-DbaDump',
    'Invoke-DbaAdvancedRestore',
    'Format-DbaBackupInformation',
    'Get-DbaAgentJobStep',
    'Test-DbaBackupInformation',
    'Invoke-DbaBalanceDataFiles',
    'Select-DbaBackupInformation',
    'Publish-DbaDacPackage',
    'Copy-DbaDbTableData',
    'Copy-DbaDbViewData',
    'Invoke-DbaQuery',
    'Remove-DbaLogin',
    'Get-DbaAgentJobCategory',
    'New-DbaAgentJobCategory',
    'Remove-DbaAgentJobCategory',
    'Set-DbaAgentJobCategory',
    'Get-DbaServerRole',
    'Find-DbaBackup',
    'Remove-DbaXESession',
    'New-DbaXESession',
    'Get-DbaXEStore',
    'New-DbaXESmartTableWriter',
    'New-DbaXESmartReplay',
    'New-DbaXESmartEmail',
    'New-DbaXESmartQueryExec',
    'Start-DbaXESmartTarget',
    'Get-DbaDbOrphanUser',
    'Get-DbaOpenTransaction',
    'Get-DbaDbLogShipError',
    'Test-DbaBuild',
    'Get-DbaXESessionTemplate',
    'ConvertTo-DbaXESession',
    'Start-DbaTrace',
    'Stop-DbaTrace',
    'Remove-DbaTrace',
    'Set-DbaLogin',
    'Copy-DbaXESessionTemplate',
    'Get-DbaXEObject',
    'ConvertTo-DbaDataTable',
    'Find-DbaDbDisabledIndex',
    'Get-DbaXESmartTarget',
    'Remove-DbaXESmartTarget',
    'Stop-DbaXESmartTarget',
    'Get-DbaRegServerGroup',
    'New-DbaDbUser',
    'Measure-DbaDiskSpaceRequirement',
    'New-DbaXESmartCsvWriter',
    'Invoke-DbaXeReplay',
    'Find-DbaInstance',
    'Test-DbaDiskSpeed',
    'Get-DbaDbExtentDiff',
    'Read-DbaAuditFile',
    'Get-DbaDbCompression',
    'Invoke-DbaDbDecryptObject',
    'Get-DbaDbForeignKey',
    'Get-DbaDbCheckConstraint',
    'Set-DbaAgentAlert',
    'Get-DbaWaitResource',
    'Get-DbaDbPageInfo',
    'Get-DbaConnection',
    'Test-DbaLoginPassword',
    'Get-DbaErrorLogConfig',
    'Set-DbaErrorLogConfig',
    'Get-DbaPlanCache',
    'Clear-DbaPlanCache',
    'ConvertTo-DbaTimeline',
    'Get-DbaDbMail',
    'Get-DbaDbMailAccount',
    'Get-DbaDbMailProfile',
    'Get-DbaDbMailConfig',
    'Get-DbaDbMailServer',
    'New-DbaDbMailServer',
    'New-DbaDbMailAccount',
    'New-DbaDbMailProfile',
    'Get-DbaResourceGovernor',
    'Get-DbaRgResourcePool',
    'Get-DbaRgWorkloadGroup',
    'Get-DbaRgClassifierFunction',
    'Export-DbaInstance',
    'Invoke-DbatoolsRenameHelper',
    'Measure-DbatoolsImport',
    'Get-DbaDeprecatedFeature',
    'Test-DbaDeprecatedFeature'
    'Get-DbaDbFeatureUsage',
    'Stop-DbaEndpoint',
    'Start-DbaEndpoint',
    'Set-DbaDbMirror',
    'Repair-DbaDbMirror',
    'Remove-DbaEndpoint',
    'Remove-DbaDbMirrorMonitor',
    'Remove-DbaDbMirror',
    'New-DbaEndpoint',
    'Invoke-DbaDbMirroring',
    'Invoke-DbaDbMirrorFailover',
    'Get-DbaDbMirrorMonitor',
    'Get-DbaDbMirror',
    'Add-DbaDbMirrorMonitor',
    'Test-DbaEndpoint',
    'Get-DbaDbSharePoint',
    'Get-DbaDbMemoryUsage',
    'Clear-DbaLatchStatistics',
    'Get-DbaCpuRingBuffer',
    'Get-DbaIoLatency',
    'Get-DbaLatchStatistic',
    'Get-DbaSpinLockStatistic',
    'Add-DbaAgDatabase',
    'Add-DbaAgListener',
    'Add-DbaAgReplica',
    'Grant-DbaAgPermission',
    'Invoke-DbaAgFailover',
    'Join-DbaAvailabilityGroup',
    'New-DbaAvailabilityGroup',
    'Remove-DbaAgDatabase',
    'Remove-DbaAgListener',
    'Remove-DbaAvailabilityGroup',
    'Revoke-DbaAgPermission',
    'Get-DbaDbCompatibility',
    'Set-DbaDbCompatibility',
    'Invoke-DbatoolsFormatter',
    'Remove-DbaAgReplica',
    'Resume-DbaAgDbDataMovement',
    'Set-DbaAgListener',
    'Set-DbaAgReplica',
    'Set-DbaAvailabilityGroup',
    'Set-DbaEndpoint',
    'Suspend-DbaAgDbDataMovement',
    'Sync-DbaAvailabilityGroup',
    'Get-DbaMemoryCondition',
    'Remove-DbaDbBackupRestoreHistory',
    'New-DbaDatabase'
    'New-DbaDacOption',
    'Get-DbaDbccHelp',
    'Get-DbaDbccMemoryStatus',
    'Get-DbaDbccProcCache',
    'Get-DbaDbccUserOption',
    'Get-DbaAgentServer',
    'Set-DbaAgentServer',
    'Invoke-DbaDbccFreeCache'
    'Export-DbatoolsConfig',
    'Import-DbatoolsConfig',
    'Reset-DbatoolsConfig',
    'Unregister-DbatoolsConfig',
    'Join-DbaPath',
    'Resolve-DbaPath',
    'Import-DbaCsv',
    'Invoke-DbaDbDataMasking',
    'New-DbaDbMaskingConfig',
    'Get-DbaDbccSessionBuffer',
    'Get-DbaDbccStatistic',
    'Get-DbaDbDbccOpenTran',
    'Invoke-DbaDbccDropCleanBuffer',
    'Invoke-DbaDbDbccCheckConstraint',
    'Invoke-DbaDbDbccCleanTable',
    'Invoke-DbaDbDbccUpdateUsage',
    'Get-DbaDbIdentity',
    'Set-DbaDbIdentity',
    'Get-DbaRegServer',
    'Get-DbaRegServerStore',
    'Add-DbaRegServer',
    'Add-DbaRegServerGroup',
    'Export-DbaRegServer',
    'Import-DbaRegServer',
    'Move-DbaRegServer',
    'Move-DbaRegServerGroup',
    'Remove-DbaRegServer',
    'Remove-DbaRegServerGroup',
    'New-DbaCustomError',
    'Remove-DbaCustomError',
    'Get-DbaDbSequence',
    'New-DbaDbSequence',
    'Remove-DbaDbSequence',
    'Select-DbaDbSequenceNextValue',
    'Set-DbaDbSequence',
    'Get-DbaDbUserDefinedTableType',
    'Get-DbaDbServiceBrokerService',
    'Get-DbaDbServiceBrokerQueue ',
    # Config system
    'Get-DbatoolsConfig',
    'Get-DbatoolsConfigValue',
    'Set-DbatoolsConfig',
    'Register-DbatoolsConfig',
    # Data generator
    'New-DbaDbDataGeneratorConfig',
    'Invoke-DbaDbDataGenerator',
    'Get-DbaRandomizedValue',
    'Get-DbaRandomizedDatasetTemplate',
    'Get-DbaRandomizedDataset',
    'Get-DbaRandomizedType',
    'Export-DbaDbTableData',
    'Backup-DbaServiceMasterKey',
    'Invoke-DbaDbPiiScan',
    'New-DbaAzAccessToken',
    'Add-DbaDbRoleMember',
    'Disable-DbaStartupProcedure',
    'Enable-DbaStartupProcedure',
    'Get-DbaDbFilegroup',
    'Get-DbaDbObjectTrigger',
    'Get-DbaStartupProcedure',
    'Get-DbatoolsChangeLog',
    'Get-DbaXESessionTargetFile',
    'Get-DbaDbRole',
    'New-DbaDbRole',
    'New-DbaDbTable',
    'New-DbaDiagnosticAdsNotebook',
    'New-DbaServerRole',
    'Remove-DbaDbRole',
    'Remove-DbaDbRoleMember',
    'Remove-DbaServerRole',
    'Test-DbaDbDataGeneratorConfig',
    'Test-DbaDbDataMaskingConfig',
    'Get-DbaAgentAlertCategory',
    'New-DbaAgentAlertCategory',
    'Remove-DbaAgentAlertCategory',
    'Save-DbaKbUpdate',
    'Get-DbaKbUpdate',
    'Get-DbaDbLogSpace',
    'Export-DbaDbRole',
    'Export-DbaServerRole',
    'Get-DbaBuildReference',
    'Update-DbaBuildReference',
    'Install-DbaFirstResponderKit',
    'Install-DbaWhoIsActive',
    'Update-Dbatools',
    'Add-DbaServerRoleMember',
    'Get-DbatoolsPath',
    'Set-DbatoolsPath',
    'Export-DbaSysDbUserObject',
    'Test-DbaDbQueryStore',
    'Install-DbaMultiTool',
    'New-DbaAgentOperator',
    'Remove-DbaAgentOperator',
    'Remove-DbaDbTableData',
    'Get-DbaDbSchema',
    'New-DbaDbSchema',
    'Set-DbaDbSchema',
    'Remove-DbaDbSchema',
    'Get-DbaDbSynonym',
    'New-DbaDbSynonym',
    'Remove-DbaDbSynonym',
    'Install-DbaDarlingData',
    'New-DbaDbFileGroup',
    'Remove-DbaDbFileGroup',
    'Set-DbaDbFileGroup',
    'Remove-DbaLinkedServer',
    'Test-DbaAvailabilityGroup',
    'Export-DbaUser',
    'Get-DbaSsisExecutionHistory',
    'New-DbaConnectionStringBuilder',
    'New-DbatoolsSupportPackage',
    'Export-DbaScript',
    'Get-DbaAgentJobOutputFile',
    'Set-DbaAgentJobOutputFile',
    'Import-DbaXESessionTemplate',
    'Export-DbaXESessionTemplate',
    'Import-DbaSpConfigure',
    'Export-DbaSpConfigure',
    'Test-DbaMaxMemory',
    'Install-DbaMaintenanceSolution',
    'Get-DbaManagementObject'
)

$script:noncoresmo = @(
    # SMO issues
    'Get-DbaRepDistributor',
    'Copy-DbaPolicyManagement',
    'Copy-DbaDataCollector',
    'Get-DbaPbmCategory',
    'Get-DbaPbmCategorySubscription',
    'Get-DbaPbmCondition',
    'Get-DbaPbmObjectSet',
    'Get-DbaPbmPolicy',
    'Get-DbaPbmStore',
    'Get-DbaRepPublication',
    'Test-DbaRepLatency',
    'Export-DbaRepServerSetting',
    'Get-DbaRepServer'
)
$script:windowsonly = @(
    # filesystem (\\ related),
    'Move-DbaDbFile'
    'Copy-DbaBackupDevice',
    'Read-DbaXEFile',
    'Watch-DbaXESession',
    # Registry
    'Get-DbaRegistryRoot',
    # GAC
    'Test-DbaManagementObject',
    # CM and Windows functions
    'Rename-DbaDatabase',
    'Get-DbaNetworkConfiguration',
    'Set-DbaNetworkConfiguration',
    'Get-DbaExtendedProtection',
    'Set-DbaExtendedProtection',
    'Install-DbaInstance',
    'Invoke-DbaAdvancedInstall',
    'Update-DbaInstance',
    'Invoke-DbaAdvancedUpdate',
    'Invoke-DbaPfRelog',
    'Get-DbaPfDataCollectorCounter',
    'Get-DbaPfDataCollectorCounterSample',
    'Get-DbaPfDataCollector',
    'Get-DbaPfDataCollectorSet',
    'Start-DbaPfDataCollectorSet',
    'Stop-DbaPfDataCollectorSet',
    'Export-DbaPfDataCollectorSetTemplate',
    'Get-DbaPfDataCollectorSetTemplate',
    'Import-DbaPfDataCollectorSetTemplate',
    'Remove-DbaPfDataCollectorSet',
    'Add-DbaPfDataCollectorCounter',
    'Remove-DbaPfDataCollectorCounter',
    'Get-DbaPfAvailableCounter',
    'Export-DbaXECsv',
    'Get-DbaOperatingSystem',
    'Get-DbaComputerSystem',
    'Set-DbaPrivilege',
    'Set-DbaTcpPort',
    'Set-DbaCmConnection',
    'Get-DbaUptime',
    'Get-DbaMemoryUsage',
    'Clear-DbaConnectionPool',
    'Get-DbaLocaleSetting',
    'Get-DbaFilestream',
    'Enable-DbaFilestream',
    'Disable-DbaFilestream',
    'Get-DbaCpuUsage',
    'Get-DbaPowerPlan',
    'Get-DbaWsfcAvailableDisk',
    'Get-DbaWsfcCluster',
    'Get-DbaWsfcDisk',
    'Get-DbaWsfcNetwork',
    'Get-DbaWsfcNetworkInterface',
    'Get-DbaWsfcNode',
    'Get-DbaWsfcResource',
    'Get-DbaWsfcResourceType',
    'Get-DbaWsfcRole',
    'Get-DbaWsfcSharedVolume',
    'Export-DbaCredential',
    'Export-DbaLinkedServer',
    'Get-DbaFeature',
    'Update-DbaServiceAccount',
    'Remove-DbaClientAlias',
    'Disable-DbaAgHadr',
    'Enable-DbaAgHadr',
    'Stop-DbaService',
    'Start-DbaService',
    'Restart-DbaService',
    'New-DbaClientAlias',
    'Get-DbaClientAlias',
    'Stop-DbaExternalProcess',
    'Get-DbaExternalProcess',
    'Remove-DbaNetworkCertificate',
    'Enable-DbaForceNetworkEncryption',
    'Disable-DbaForceNetworkEncryption',
    'Get-DbaForceNetworkEncryption',
    'Get-DbaHideInstance',
    'Enable-DbaHideInstance',
    'Disable-DbaHideInstance',
    'New-DbaComputerCertificateSigningRequest',
    'Remove-DbaComputerCertificate',
    'New-DbaComputerCertificate',
    'Get-DbaComputerCertificate',
    'Add-DbaComputerCertificate',
    'Backup-DbaComputerCertificate',
    'Test-DbaComputerCertificateExpiration',
    'Get-DbaNetworkCertificate',
    'Set-DbaNetworkCertificate',
    'Remove-DbaDbLogshipping',
    'Invoke-DbaDbLogShipping',
    'New-DbaCmConnection',
    'Get-DbaCmConnection',
    'Remove-DbaCmConnection',
    'Test-DbaCmConnection',
    'Get-DbaCmObject',
    'Set-DbaStartupParameter',
    'Get-DbaNetworkActivity',
    'Get-DbaInstanceProtocol',
    'Install-DbatoolsWatchUpdate',
    'Uninstall-DbatoolsWatchUpdate',
    'Watch-DbatoolsUpdate',
    'Get-DbaPrivilege',
    'Get-DbaMsdtc',
    'Get-DbaPageFileSetting',
    'Copy-DbaCredential',
    'Test-DbaConnection',
    'Reset-DbaAdmin',
    'Copy-DbaLinkedServer',
    'Get-DbaDiskSpace',
    'Test-DbaDiskAllocation',
    'Test-DbaPowerPlan',
    'Set-DbaPowerPlan',
    'Test-DbaDiskAlignment',
    'Get-DbaStartupParameter',
    'Get-DbaSpn',
    'Test-DbaSpn',
    'Set-DbaSpn',
    'Remove-DbaSpn',
    'Get-DbaService',
    'Get-DbaClientProtocol',
    'Get-DbaWindowsLog',
    # WPF
    'Show-DbaInstanceFileSystem',
    'Show-DbaDbList',
    # AD
    'Test-DbaWindowsLogin',
    'Find-DbaLoginInGroup',
    # 3rd party non-core DLL or sqlpackage.exe
    'Install-DbaSqlWatch',
    'Uninstall-DbaSqlWatch',
    'New-DbaDacProfile',
    'Export-DbaDacPackage',
    # Unknown
    'Get-DbaErrorLog'
)

# If a developer or appveyor calls the psm1 directly, they want all functions
# So do not explicitly export because everything else is then implicitly excluded
if (-not $script:multiFileImport) {
    $exports =
    @(if (($PSVersionTable.Platform)) {
            if ($PSVersionTable.Platform -ne "Win32NT") {
                $script:xplat
            } else {
                $script:xplat
                $script:windowsonly
            }
        } else {
            $script:xplat

            $script:windowsonly
            $script:noncoresmo
        })

    $aliasExport = @(
        foreach ($k in $script:Renames.Keys) {
            $k
        }
        foreach ($k in $script:Forever.Keys) {
            $k
        }
        foreach ($c in $script:shortcuts.Keys) {
            $c
        }
    )

    Export-ModuleMember -Alias $aliasExport -Function $exports -Cmdlet Select-DbaObject, Set-DbatoolsConfig

    Write-ImportTime -Text "Exported module member"
} else {
    Export-ModuleMember -Alias * -Function * -Cmdlet *
}

$timeout = 20000
$timeSpent = 0
while ($script:smoRunspace.Runspace.RunspaceAvailability -eq 'Busy') {
    [Threading.Thread]::Sleep(10)
    $timeSpent = $timeSpent + 50

    if ($timeSpent -ge $timeout) {
        Write-Warning @"
The module import has hit a timeout while waiting for some background tasks to finish.
This may result in some commands not working as intended.
This should not happen under reasonable circumstances, please file an issue at:
https://github.com/sqlcollaborative/dbatools/issues
Or contact us directly in the #dbatools channel of the SQL Server Community Slack Channel:
https://dbatools.io/slack/
Timeout waiting for temporary runspaces reached! The Module import will complete, but some things may not work as intended
"@
        $global:smoRunspace = $script:smoRunspace
        break
    }
}

if ($script:smoRunspace) {
    $script:smoRunspace.Runspace.Close()
    $script:smoRunspace.Runspace.Dispose()
    $script:smoRunspace.Dispose()
    $script:smoRunspace = $null
}
Write-ImportTime -Text "Waiting for runspaces to finish"
$myInv = $MyInvocation
if ($option.LoadTypes -or
    ($myInv.Line -like '*.psm1*' -and
        (-not (Get-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Server)
        ))) {
    Update-TypeData -AppendPath (Resolve-Path -Path "$script:PSModuleRoot\xml\dbatools.Types.ps1xml")
    Write-ImportTime -Text "Loaded type extensions"
}
#. Import-ModuleFile "$script:PSModuleRoot\bin\type-extensions.ps1"
#Write-ImportTime -Text "Loaded type extensions"

$td = (Get-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Server)
[Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleImported = $true;
$loadedModuleNames = Get-Module | Select-Object -ExpandProperty Name
if ($loadedModuleNames -contains 'sqlserver' -or $loadedModuleNames -contains 'sqlps') {
    if (Get-DbatoolsConfigValue -FullName Import.SqlpsCheck) {
        Write-Warning -Message 'SQLPS or SqlServer was previously imported during this session. If you encounter weird issues with dbatools, please restart PowerShell, then import dbatools without loading SQLPS or SqlServer first.'
        Write-Warning -Message 'To disable this message, type: Set-DbatoolsConfig -Name Import.SqlpsCheck -Value $false -PassThru | Register-DbatoolsConfig'
    }
}
#endregion Post-Import Cleanup
