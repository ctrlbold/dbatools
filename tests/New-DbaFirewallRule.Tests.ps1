$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'Credential', 'Auto', 'Configuration', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        #$null = Remove-DbaFirewallRule -SqlInstance $script:instance2 -Confirm:$false
    }

    AfterAll {
        #$null = Remove-DbaFirewallRule -SqlInstance $script:instance2 -Confirm:$false
    }

    $resultsNew = New-DbaFirewallRule -SqlInstance $script:instance2 -Auto -Confirm:$false
    $resultsGet = Get-DbaFirewallRule -SqlInstance $script:instance2
    $resultsRemoveBrowser = $resultsGet | Where-Object { $_.DisplayName -eq "SQL Server Browser" } | Remove-DbaFirewallRule -Confirm:$false
    $resultsRemove = Remove-DbaFirewallRule -SqlInstance $script:instance2 -Confirm:$false

    $instanceName = ([DbaInstanceParameter]$script:instance2).InstanceName

    It "creates two firewall rules" {
        $resultsNew.Count | Should -Be 2
    }

    It "creates first firewall rule for SQL Server instance" {
        $resultsNew[0].DisplayName | Should -Be "SQL Server instance $instanceName"
        $resultsNew[0].Successful | Should -Be $true
        $resultsNew[0].Warning | Should -Be $null
        $resultsNew[0].Error | Should -Be $null
        $resultsNew[0].Exception | Should -Be $null
    }

    It "creates second firewall rule for SQL Server Browser" {
        $resultsNew[1].DisplayName | Should -Be "SQL Server Browser"
        $resultsNew[1].Successful | Should -Be $true
        $resultsNew[1].Warning | Should -Be $null
        $resultsNew[1].Error | Should -Be $null
        $resultsNew[1].Exception | Should -Be $null
    }

    It "returns two firewall rules" {
        $resultsGet.Count | Should -Be 2
    }

    It "returns one firewall rule for SQL Server instance" {
        $resultInstance = $resultsGet | Where-Object DisplayName -eq "SQL Server instance $instanceName"
        $resultInstance.Protocol | Should -Be "TCP"
    }

    It "returns one firewall rule for SQL Server Browser" {
        $resultInstance = $resultsGet | Where-Object DisplayName -eq "SQL Server Browser"
        $resultInstance.Protocol | Should -Be "UDP"
        $resultInstance.LocalPort | Should -Be "1434"
    }

    It "removes firewall rule for Browser" {
        $resultsRemoveBrowser.IsRemoved | Should -Be $true
    }

    It "removes firewall rule for Browser without warnings" {
        $resultsRemoveBrowser.Warning | Should -Be $null
    }

    It "removes firewall rule for Browser without errors" {
        $resultsRemoveBrowser.Error | Should -Be $null
    }

    It "removes firewall rule for Browser without exception" {
        $resultsRemoveBrowser.Exception | Should -Be $null
    }

    It "removes other firewall rule" {
        $resultsRemove.IsRemoved | Should -Be $true
    }

    It "removes other firewall rule without warnings" {
        $resultsRemove.Warning | Should -Be $null
    }

    It "removes other firewall rule without errors" {
        $resultsRemove.Error | Should -Be $null
    }

    It "removes other firewall rule without exception" {
        $resultsRemove.Exception | Should -Be $null
    }

}