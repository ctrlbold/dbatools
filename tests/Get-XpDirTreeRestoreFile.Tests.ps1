#Thank you Warren http://ramblingcookiemonster.github.io/Testing-DSC-with-Pester-and-AppVeyor/

if(-not $PSScriptRoot)
{
    $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
$Verbose = @{}
if($env:APPVEYOR_REPO_BRANCH -and $env:APPVEYOR_REPO_BRANCH -notlike "master")
{
    $Verbose.add("Verbose",$True)
}



$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace('.Tests.', '.')
Import-Module $PSScriptRoot\..\internal\$sut -Force
#Need to load various functions so we can mock It, breaks Appveyor otherwise

. $PSScriptRoot\..\internal\Connect-SQLServer.ps1 
. $PSScriptRoot\..\functions\Test-SQLPath.ps1 
. $PSScriptRoot\..\optional\Invoke-SqlCmd2.ps1
Describe "Get-XpDirTree Unit Tests" -Tag 'Unittests'{
    mock Connect-SqlServer {$true}
    mock Test-SqlPath {$true}

    Context "Test Connection and User Rights" {
        Mock Test-SQLPath {$false}
        Mock Write-Warning {Throw}  ## Need to mock the warnign to stop the error in tests

        It "Should throw on an invalid SQL Connection" {
            Mock Connect-SQLServer {Throw} ## Mock the Connect call to hit the catch inside the function
            #mock Test-SQLConnection {(1..12) | %{[System.Collections.ArrayList]$t += @{ConnectSuccess = $false}}}         
            {Get-XpDirTreeRestoreFile -path c:\dummy -sqlserver bad\bad} | Should Throw
        }
        It "Should throw if SQL Server can't see the path" {   
            $srv = New-Object Microsoft.SQLServer.Management.Smo.Server dummy    ## Mock the server object else throws on Connect and doesnt test path
            {Get-XpDirTreeRestoreFile -path c:\dummy -sqlserver $srv} | Should Throw 
        }
        It 'Calls Connect-SQLServer Mock Once' {
        $assertMockParams = @{
            'CommandName' = 'Connect-SQLServer'
            'Times' = 1
            'Exactly' = $true
        }
        Assert-MockCalled @assertMockParams ## Ensure Mocks are called 
    }
    It 'Calls Test-SqlPath Mock Once' {
        $assertMockParams = @{
            'CommandName' = 'Test-SqlPath'
            'Times' = 1
            'Exactly' = $true
        }
        Assert-MockCalled @assertMockParams ## Ensure Mocks are called 
    }
    }
    Context "Non recursive filestructure" {
        $array = (@{subdirectory='full.bak';depth=1;file=1},
        @{subdirectory='full2.bak';depth=1;file=1})
        Mock Invoke-SqlCmd2 {$array} -ParameterFilter {$Query -and $Query -eq "EXEC master.sys.xp_dirtree 'c:\temp\',1,1;"}            
        $results = Get-XpDirTreeRestoreFile -path c:\temp -sqlserver bad\bad
        It "Should return an array of 2 files" {
            $results.count | Should Be 2
        }
        It "Should return a file in c:\temp" { 
            $results[0].Fullname | Should BeLike 'c:\temp\*bak'
        }
        It "Should return another file in C:\temp" {
            $results[1].Fullname | Should BeLike 'c:\temp\*bak'
        }
    }
    Context "Recursive Filestructure" {
        $array = (@{subdirectory='full.bak';depth=1;file=1},
            @{subdirectory='full2.bak';depth=1;file=1},
            @{subdirectory='recurse';depth=1;file=0})
        Mock Invoke-SqlCmd2 {$array} -ParameterFilter {$query -and $query -eq "EXEC master.sys.xp_dirtree 'c:\temp\',1,1;"}
        $array2 = (@{subdirectory='fulllow.bak';depth=1;file=1},
            @{subdirectory='full2low.bak';depth=1;file=1})
        Mock Invoke-SqlCmd2 {$array2} -ParameterFilter {$query -and $query -eq "EXEC master.sys.xp_dirtree 'c:\temp\recurse\',1,1;"}
        $results = Get-XpDirTreeRestoreFile -path c:\temp -sqlserver bad\bad
        It "Should return array of 4 files - recursion" {
            $results.count | Should Be 4
        }
        It "Should return C:\temp\recurse\fulllow.bak" {
            ($results | Where-Object {$_.Fullname -eq 'C:\temp\recurse\fulllow.bak'} | measure-Object).count | Should be 1
        }
        It "Should return C:\temp\recurse\fulllow.bak" {
            ($results | Where-Object {$_.Fullname -eq 'C:\temp\recurse\full2low.bak'} | measure-Object).count | Should be 1
        }
        It "Should return C:\temp\recurse\fulllow.bak" {
            ($results | Where-Object {$_.Fullname -eq 'C:\temp\full.bak'} | measure-Object).count | Should be 1
        }
        It "Should return C:\temp\recurse\fulllow.bak" {
            ($results | Where-Object {$_.Fullname -eq 'C:\temp\full2.bak'} | measure-Object).count | Should be 1
        }
    }

}
