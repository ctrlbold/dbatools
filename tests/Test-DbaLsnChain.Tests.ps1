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
. $PSScriptRoot\..\functions\Read-DbaBackupHeader.ps1
. $PSScriptRoot\..\internal\Get-FilteredRestoreFile.ps1

Describe "Test-DbaLsnChain Unit Tests" -Tag 'Unittests'{
    Context "General Diff restore" {
        $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
        Mock Read-DbaBackupHeader {$Header}
        $RawFilteredFiles = Get-FilteredRestoreFile -SqlServer 'TestSQL' -Files "c:\dummy.txt"
        $FilteredFiles = $RawFilteredFiles[0].values
        It "Should Return 7" {
            $FilteredFiles.count | should be 7
        }
        It "Should return True" {
            $Output =  Test-DbaLsnChain -FilteredRestoreFiles $FilteredFiles
            $Output | Should be True
        }
        $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
        Mock Read-DbaBackupHeader {$Header | Where-Object {$_.BackupTypeDescription -ne 'Database Differential'}}
        $RawFilteredFiles = Get-FilteredRestoreFile -SqlServer 'TestSQL' -Files "c:\dummy.txt"
        $FilteredFiles = $RawFilteredFiles[0].values
        It "Should return true if we remove diff backup" {
            $Output = Test-DbaLsnChain -FilteredRestoreFiles ($FilteredFiles | Where-Object {$_.BackupTypeDescription -ne 'Database Differential'}) 
            $Output | Should be True           
        }

        It "Should return False (faked lsn)" {
            $FilteredFiles[4].FirstLsn = 2
            $FilteredFiles[4].LastLsn = 1
            $Output = $FilteredFiles | Test-DbaLsnChain
            $Output | Should be False           
        }
    }
}