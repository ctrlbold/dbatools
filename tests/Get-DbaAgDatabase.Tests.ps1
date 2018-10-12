$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        <#
            Get commands, Default count = 11
            Commands with SupportShouldProcess = 13
        #>
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaAgDatabase).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'Database', 'InputObject', 'EnableException'
        $paramCount = $knownParameters.Count
        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

InModuleScope dbatools {
    . "$PSScriptRoot\constants.ps1"
    $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
    Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
        Mock Connect-SqlInstance {
            Import-Clixml $script:appveyorlabrepo\agserver.xml
        }
        Context "gets ag databases" {
            It -Skip "returns results with proper data" {
                $results = Get-DbaAgDatabase -SqlInstance sql2016c
                foreach ($result in $results) {
                    $result.Replica | Should -Be 'SQL2016C'
                    $result.SynchronizationState | Should -Be 'NotSynchronizing'
                }
            }
            It -Skip "returns results with proper data for one database" {
                $results = Get-DbaAgDatabase -SqlInstance sql2016c -Database WSS_Content
                $results.Replica | Should -Be 'SQL2016C'
                $results.SynchronizationState | Should -Be 'NotSynchronizing'
                $results.DatabaseName | Should -Be 'WSS_Content'
            }
        }
    }
}