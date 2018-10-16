﻿$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 6
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\New-DbaClientAlias).Parameters.Keys
        $knownParameters = 'ComputerName','Credential','ServerName','Alias','Protocol','EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "adds the alias" {
        $results = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias-new -Verbose:$false
        It "returns accurate information" {
            $results.AliasName | Should Be dbatoolscialias-new, dbatoolscialias-new
        }
        $results | Remove-DbaClientAlias
    }
}