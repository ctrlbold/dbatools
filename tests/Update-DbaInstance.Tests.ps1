$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

$exeDir = "C:\Temp\dbatools_$CommandName"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Prevent the functions from executing dangerous stuff and getting right responses where needed
        Mock -CommandName Invoke-Program -MockWith { $null } -ModuleName dbatools
        Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName dbatools
        Mock -CommandName Test-ElevationRequirement -MockWith { $null } -ModuleName dbatools
        Mock -CommandName Restart-Computer -MockWith { $null } -ModuleName dbatools
        Mock -CommandName Register-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
            [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
        }
        Mock -CommandName Unregister-RemoteSessionConfiguration -ModuleName dbatools -MockWith {
            [pscustomobject]@{ 'Name' = 'dbatoolsInstallSqlServerUpdate' ; Successful = $true ; Status = 'Dummy' }
        }
        Mock -CommandName Get-DbaDiskSpace -MockWith { [pscustomobject]@{ Name = 'C:\'; Free = 1 } } -ModuleName dbatools
    }
    Context "Validate parameters" {
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\$CommandName).Parameters.Keys
        $knownParameters = 'ComputerName', 'Credential', 'Version', 'MajorVersion', 'Type', 'Path', 'Restart', 'EnableException','Kb'
        $paramCount = $knownParameters.Count
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
    Context "Validate upgrades to a latest version" {
        BeforeAll {
            #this is our 'currently installed' versions
            Mock -CommandName Get-SqlServerVersion -ModuleName dbatools -MockWith {
                @(
                    [pscustomobject]@{
                        "SqlInstance" = $null
                        "Build" = "11.0.5058"
                        "NameLevel" = "2012"
                        "SPLevel" = "SP2"
                        "CULevel" = $null
                        "KBLevel" = "2958429"
                        "BuildLevel" = [version]'11.0.5058'
                        "MatchType" = "Exact"
                    }
                    [pscustomobject]@{
                        "SqlInstance" = $null
                        "Build" = "10.0.5770"
                        "NameLevel" = "2008"
                        "SPLevel" = "SP3"
                        "CULevel" = "CU3"
                        "KBLevel" = "2648098"
                        "BuildLevel" = [version]'10.0.5770'
                        "MatchType" = "Exact"
                    }
                )
            }
            if (-Not(Test-Path $exeDir)) {
                $null = New-Item -ItemType Directory -Path $exeDir
            }
            #Create dummy files for specific patch versions
            $kbs = @(
                'SQLServer2008SP4-KB2979596-x64-ENU.exe'
                'SQLServer2012-KB4018073-x64-ENU.exe'
            )
            foreach ($kb in $kbs) {
                $null = New-Item -ItemType File -Path (Join-Path $exeDir $kb) -Force
            }
        }
        AfterAll {
            if (Test-Path $exeDir) {
                Remove-Item $exeDir -Force -Recurse
            }
        }
        It "Should mock-upgrade SQL2008 to latest SP" {
            $result = Update-DbaInstance -MajorVersion 2008 -Type ServicePack -Path $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Get-SqlServerVersion -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools
            #no remote execution in tests
            #Assert-MockCalled -CommandName Register-RemoteSessionConfiguration -Exactly 0 -Scope It -ModuleName dbatools
            #Assert-MockCalled -CommandName Unregister-RemoteSessionConfiguration -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP4
            $result.KB | Should -Be 2979596
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008SP4-KB2979596-x64-ENU.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'
        }
        It "Should mock-upgrade both versions to latest SPs" {
            $results = Update-DbaInstance -Type ServicePack -Path $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Get-SqlServerVersion -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 4 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 2 -Scope It -ModuleName dbatools
            #no remote execution in tests
            #Assert-MockCalled -CommandName Register-RemoteSessionConfiguration -Exactly 0 -Scope It -ModuleName dbatools
            #Assert-MockCalled -CommandName Unregister-RemoteSessionConfiguration -Exactly 1 -Scope It -ModuleName dbatools

            ($results | Measure-Object).Count | Should -Be 2

            #2008SP4
            $result = $results | Where-Object MajorVersion -eq 2008
            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP4
            $result.KB | Should -Be 2979596
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008SP4-KB2979596-x64-ENU.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'

            #2012SP4
            $result = $results | Where-Object MajorVersion -eq 2012
            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2012
            $result.TargetLevel | Should -Be SP4
            $result.KB | Should -Be 4018073
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2012-KB4018073-x64-ENU.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'
        }
    }
    Context "Validate upgrades to a specific KB" {
        BeforeAll {
            #this is our 'currently installed' versions
            Mock -CommandName Get-SqlServerVersion -ModuleName dbatools -MockWith {
               @(
                    [pscustomobject]@{
                        "SqlInstance" = $null
                        "Build" = "13.0.4435"
                        "NameLevel" = "2016"
                        "SPLevel" = "SP1"
                        "CULevel" = "CU3"
                        "KBLevel" = "4019916"
                        "BuildLevel" = [version]'13.0.4435'
                        "MatchType" = "Exact"
                    }
                    [pscustomobject]@{
                        "SqlInstance" = $null
                        "Build" = "10.0.4279"
                        "NameLevel" = "2008"
                        "SPLevel" = "SP2"
                        "CULevel" = "CU3"
                        "KBLevel" = "2498535"
                        "BuildLevel" = [version]'10.0.4279'
                        "MatchType" = "Exact"
                    }
                )
            }
            if (-Not(Test-Path $exeDir)) {
                $null = New-Item -ItemType Directory -Path $exeDir
            }
            #Create dummy files for specific patch versions
            $kbs = @(
                'SQLServer2008SP3-KB2546951-x64-ENU.exe'
                'SQLServer2008-KB2555408-x64-ENU.exe'
                'SQLServer2008-KB2738350-x64-ENU.exe'
                'SQLServer2016-KB4040714-x64.exe'
                'SQLServer2008-KB2738350-x64-ENU.exe'
                'SQLServer2016-KB4024305-x64-ENU.exe'
            )
            foreach ($kb in $kbs) {
                $null = New-Item -ItemType File -Path (Join-Path $exeDir $kb) -Force
            }
        }
        AfterAll {
            if (Test-Path $exeDir) {
                Remove-Item $exeDir -Force -Recurse
            }
        }
        It "Should mock-upgrade SQL2008 to SP3 (KB2546951)" {
            $result = Update-DbaInstance -Kb KB2546951 -Path $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Get-SqlServerVersion -Exactly 1 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools
            #no remote execution in tests
            #Assert-MockCalled -CommandName Register-RemoteSessionConfiguration -Exactly 0 -Scope It -ModuleName dbatools
            #Assert-MockCalled -CommandName Unregister-RemoteSessionConfiguration -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3
            $result.KB | Should -Be 2546951
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008SP3-KB2546951-x64-ENU.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'
        }
        It "Should mock-upgrade SQL2016 to SP1CU4 (KB3182545 + KB4024305) " {
            $result = Update-DbaInstance -Kb 3182545, 4024305 -Path $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Get-SqlServerVersion -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 2 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 1 -Scope It -ModuleName dbatools
            #no remote execution in tests
            #Assert-MockCalled -CommandName Register-RemoteSessionConfiguration -Exactly 0 -Scope It -ModuleName dbatools
            #Assert-MockCalled -CommandName Unregister-RemoteSessionConfiguration -Exactly 1 -Scope It -ModuleName dbatools

            $result | Should -Not -BeNullOrEmpty
            $result.MajorVersion | Should -Be 2016
            $result.TargetLevel | Should -Be SP1CU4
            $result.KB | Should -Be 4024305
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2016-KB4024305-x64-ENU.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'
        }
        It "Should mock-upgrade both versions to different KBs" {
            $results = Update-DbaInstance -Kb 3182545, 4040714, KB2546951, KB2738350 -Path $exeDir -Restart -EnableException -Confirm:$false
            Assert-MockCalled -CommandName Get-SqlServerVersion -Exactly 4 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Invoke-Program -Exactly 6 -Scope It -ModuleName dbatools
            Assert-MockCalled -CommandName Restart-Computer -Exactly 3 -Scope It -ModuleName dbatools
            #no remote execution in tests
            #Assert-MockCalled -CommandName Register-RemoteSessionConfiguration -Exactly 0 -Scope It -ModuleName dbatools
            #Assert-MockCalled -CommandName Unregister-RemoteSessionConfiguration -Exactly 1 -Scope It -ModuleName dbatools

            ($results | Measure-Object).Count | Should -Be 3

            #2016SP1CU5
            $result = $results | Select-Object -First 1
            $result.MajorVersion | Should -Be 2016
            $result.TargetLevel | Should -Be SP1CU5
            $result.KB | Should -Be 4040714
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2016-KB4040714-x64.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'

            #2008SP3
            $result = $results | Select-Object -First 1 -Skip 1
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3
            $result.KB | Should -Be 2546951
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008SP3-KB2546951-x64-ENU.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'

            #2008SP3CU7
            $result = $results | Select-Object -First 1 -Skip 2
            $result.MajorVersion | Should -Be 2008
            $result.TargetLevel | Should -Be SP3CU7
            $result.KB | Should -Be 2738350
            $result.Successful | Should -Be $true
            $result.Restarted | Should -Be $true
            $result.Installer | Should -Be (Join-Path $exeDir 'SQLServer2008-KB2738350-x64-ENU.exe')
            $result.Message | Should -BeNullOrEmpty
            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'
        }
    }
    Context "Should mock-upgrade to a set of specific versions" {
        BeforeAll {
            #Mock Get-Item and Get-ChildItem with a dummy file
            Mock -CommandName Get-ChildItem -ModuleName dbatools -MockWith {
                [pscustomobject]@{
                    FullName = 'c:\mocked\filename.exe'
                }
            }
            Mock -CommandName Get-Item -ModuleName dbatools -MockWith { 'c:\mocked' }
        }
        AfterAll {
        }
        $versions = @{
            '2005' = @{
                Mock = { [pscustomobject]@{
                        "SqlInstance" = $null
                        "Build" = "9.0.1399"
                        "NameLevel" = "2005"
                        "SPLevel" = "RTM"
                        "CULevel" = $null
                        "KBLevel" = $null
                        "BuildLevel" = [version]'9.0.1399'
                        "MatchType" = "Exact"
                    }
                }
                Versions = @{
                    'SP1' = 0
                    'SP2' = 0
                    'SP4' = 0, 3
                }
            }
            '2008' = @{
                Mock = { [pscustomobject]@{
                        "SqlInstance" = $null
                        "Build" = "10.0.1600"
                        "NameLevel" = "2008"
                        "SPLevel" = "RTM"
                        "CULevel" = $null
                        "KBLevel" = $null
                        "BuildLevel" = [version]'10.0.1600'
                        "MatchType" = "Exact"
                    }
                }
                Versions = @{
                    'SP0' = 1, 10
                    'SP1' = 0, 16
                    'SP2' = 0, 11
                    'SP3' = 0, 17
                    'SP4' = 0
                }
            }
            '2008R2' = @{
                Mock = { [pscustomobject]@{
                        "SqlInstance" = $null
                        "Build" = "10.50.1600"
                        "NameLevel" = "2008R2"
                        "SPLevel" = "RTM"
                        "CULevel" = $null
                        "KBLevel" = $null
                        "BuildLevel" = [version]'10.50.1600'
                        "MatchType" = "Exact"
                    }
                }
                Versions = @{
                    'SP0' = 1, 14
                    'SP1' = 0, 13
                    'SP2' = 0, 13
                    'SP3' = 0
                }
            }
            '2012' = @{
                Mock = { [pscustomobject]@{
                        "SqlInstance" = $null
                        "Build" = "11.0.2100"
                        "NameLevel" = "2012"
                        "SPLevel" = "RTM"
                        "CULevel" = $null
                        "KBLevel" = $null
                        "BuildLevel" = [version]'10.0.2100'
                        "MatchType" = "Exact"
                    }
                }
                Versions = @{
                    'SP0' = 1, 11
                    'SP1' = 0, 16
                    'SP2' = 0, 16
                    'SP3' = 0, 10
                    'SP4' = 0
                }
            }
            '2014' = @{
                Mock = { [pscustomobject]@{
                        "SqlInstance" = $null
                        "Build" = "12.0.2000"
                        "NameLevel" = "2014"
                        "SPLevel" = "RTM"
                        "CULevel" = $null
                        "KBLevel" = $null
                        "BuildLevel" = [version]'12.0.2000'
                        "MatchType" = "Exact"
                    }
                }
                Versions = @{
                    'SP0' = 1, 14
                    'SP1' = 0, 13
                    'SP2' = 0, 14
                    'SP3' = 0
                }
            }
            '2016' = @{
                Mock = { [pscustomobject]@{
                        "SqlInstance" = $null
                        "Build" = "13.0.1601"
                        "NameLevel" = "2016"
                        "SPLevel" = "RTM"
                        "CULevel" = $null
                        "KBLevel" = $null
                        "BuildLevel" = [version]'13.0.1601'
                        "MatchType" = "Exact"
                    }
                }
                Versions = @{
                    'SP0' = 1, 9
                    'SP1' = 0, 12
                    'SP2' = 0, 4
                }
            }
            '2017' = @{
                Mock = { [pscustomobject]@{
                        "SqlInstance" = $null
                        "Build" = "14.0.1000"
                        "NameLevel" = "2017"
                        "SPLevel" = "RTM"
                        "CULevel" = $null
                        "KBLevel" = $null
                        "BuildLevel" = [version]'14.0.1000'
                        "MatchType" = "Exact"
                    }
                }
                Versions = @{
                    'SP0' = 1, 12
                }
            }
        }
        foreach ($v in $versions.Keys | Sort-Object) {
            #this is our 'currently installed' versions
            Mock -CommandName Get-SqlServerVersion -ModuleName dbatools -MockWith $versions[$v].Mock
            #cycle through every sp and cu defined
            $upgrades = $versions[$v].Versions
            foreach($upgrade in $upgrades.Keys | Sort-Object) {
                foreach ($cu in $upgrades[$upgrade]) {
                    $tLevel = $upgrade
                    $steps = 0
                    if ($tLevel -eq 'SP0') { $tLevel = 'RTM' }
                    else { $steps++ }
                    if ($cu -gt 0) {
                        $cuLevel = "$($tLevel)CU$cu"
                        $steps++
                    } else {
                        $cuLevel = $tLevel
                    }
                    It "$v to $cuLevel" {
                        $results = Update-DbaInstance -Version "$v$cuLevel" -Path 'mocked' -Restart -EnableException -Confirm:$false
                        Assert-MockCalled -CommandName Get-SqlServerVersion -Exactly $steps -Scope It -ModuleName dbatools
                        Assert-MockCalled -CommandName Invoke-Program -Exactly ($steps*2) -Scope It -ModuleName dbatools
                        Assert-MockCalled -CommandName Restart-Computer -Exactly $steps -Scope It -ModuleName dbatools
                        for($i=0; $i -lt $steps; $i++) {
                            $result = $results | Select-Object -First 1 -Skip $i
                            $result | Should -Not -BeNullOrEmpty
                            $result.MajorVersion | Should -Be $v
                            if ($steps -gt 1 -and $i -eq 0) { $result.TargetLevel | Should -Be $tLevel }
                            else { $result.TargetLevel | Should -Be $cuLevel }
                            $result.KB | Should -BeGreaterThan 0
                            $result.Successful | Should -Be $true
                            $result.Restarted | Should -Be $true
                            $result.Installer | Should -Be 'c:\mocked\filename.exe'
                            $result.Message | Should -BeNullOrEmpty
                            $result.ExtractPath | Should -BeLike '*\dbatools_KB*Extract'
                        }
                    }
                }
            }
        }
    }
    Context "Negative tests" {
        BeforeAll {
            #this is our 'currently installed' versions
            Mock -CommandName Get-SqlServerVersion -ModuleName dbatools -MockWith {
                @(
                    [pscustomobject]@{
                        "SqlInstance" = $null
                        "Build" = "10.0.4279"
                        "NameLevel" = "2008"
                        "SPLevel" = "SP2"
                        "CULevel" = "CU3"
                        "KBLevel" = "2498535"
                        "BuildLevel" = [version]'10.0.4279'
                        "MatchType" = "Exact"
                    }
                )
            }
            if (-Not(Test-Path $exeDir)) {
                $null = New-Item -ItemType Directory -Path $exeDir
            }
        }
        AfterAll {
            if (Test-Path $exeDir) {
                Remove-Item $exeDir -Force -Recurse
            }
        }
        It "fails when a reboot is pending" {
            #override default mock
            Mock -CommandName Test-PendingReboot -MockWith { $true } -ModuleName dbatools
            { Update-DbaInstance -Version 2008SP3CU7 -EnableException } | Should throw 'Reboot the computer before proceeding'
            #revert default mock
            Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName dbatools
        }
        It "fails when Version string is incorrect" {
            { Update-DbaInstance -Version '' -EnableException } | Should throw 'Cannot validate argument on parameter ''Version'''
            { Update-DbaInstance -Version $null -EnableException } | Should throw 'Cannot validate argument on parameter ''Version'''
            { Update-DbaInstance -Version SQL2008 -EnableException } | Should throw 'Either SP or CU should be specified'
            { Update-DbaInstance -Version SQL2008-SP3 -EnableException } | Should throw 'is an incorrect Version value'
            { Update-DbaInstance -Version SP2CU -EnableException } | Should throw 'is an incorrect Version value'
            { Update-DbaInstance -Version SPCU2 -EnableException } | Should throw 'is an incorrect Version value'
            { Update-DbaInstance -Version SQLSP2CU2 -EnableException } | Should throw 'is an incorrect Version value'
        }
        It "fails when MajorVersion string is incorrect" {
            { Update-DbaInstance -MajorVersion 08 -EnableException } | Should throw 'is an incorrect MajorVersion value'
            { Update-DbaInstance -MajorVersion 2008SP3 -EnableException } | Should throw 'is an incorrect MajorVersion value'
        }
        It "fails when KB is missing in the folder" {
            { Update-DbaInstance -Path $exeDir -EnableException } | Should throw 'Could not find installer for the SQL2008 update KB'
            { Update-DbaInstance -Version 2008SP3CU7 -Path $exeDir -EnableException } | Should throw 'Could not find installer for the SQL2008 update KB'
        }
        It "fails when SP level is lower than required" {
            { Update-DbaInstance -Type CumulativeUpdate -EnableException } | Should throw 'Current SP version SQL2008SP2 is not the latest available'
        }
        It "fails when repository is not available" {
            { Update-DbaInstance -Version 2008SP3CU7 -Path .\NonExistingFolder -EnableException } | Should throw 'Cannot find path'
            { Update-DbaInstance -Version 2008SP3CU7 -EnableException } | Should throw 'Path to SQL Server updates folder is not set'
        }
    }
}

Describe "$CommandName Integration Tests" -Tag 'IntegrationTests' {
    BeforeAll {
        #ignore restart requirements
        Mock -CommandName Test-PendingReboot -MockWith { $false } -ModuleName dbatools
        #ignore elevation requirements
        Mock -CommandName Test-ElevationRequirement -MockWith { $null } -ModuleName dbatools
        #no restarts
        Mock -CommandName Restart-Computer -MockWith { $null } -ModuleName dbatools
        #Mock Get-Item and Get-ChildItem with a dummy file
        Mock -CommandName Get-ChildItem -ModuleName dbatools -MockWith {
            [pscustomobject]@{
                FullName = 'c:\mocked\filename.exe'
            }
        }
        Mock -CommandName Get-Item -ModuleName dbatools -MockWith { 'c:\mocked' }
    }
    Context "WhatIf upgrade all local versions to latest SPCU" {
        It "Should whatif-upgrade to latest SPCU" {
            $results = Update-DbaInstance -ComputerName $script:instance1 -Type ServicePack -Path $exeDir -Restart -EnableException -WhatIf 3>$null
            foreach ($result in $results) {
                $result.MajorVersion | Should -BeLike 20*
                $result.TargetLevel | Should -BeLike 'SP*'
                $result.KB | Should -Not -BeNullOrEmpty
                $result.Successful | Should -Be $true
                $result.Restarted | Should -Be $false
                $result.Installer | Should -Be 'c:\mocked\filename.exe'
                $result.Message | Should -Be 'The installation was not performed - running in WhatIf mode'
            }
        }
    }
}