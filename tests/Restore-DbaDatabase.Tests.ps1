﻿#Thank you Warren http://ramblingcookiemonster.github.io/Testing-DSC-with-Pester-and-AppVeyor/

if (-not $PSScriptRoot) {
	$PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
$Verbose = @{ }
if ($env:APPVEYOR_REPO_BRANCH -and $env:APPVEYOR_REPO_BRANCH -notlike "master") {
	$Verbose.add("Verbose", $True)
}

$scriptname = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace('.Tests.', '.')
$Name = $scriptname.Split('.')[0]

Describe 'Script Analyzer Tests' -Tags @('ScriptAnalyzer') {
	Context "Testing $Name for Standard Processing" {
		foreach ($rule in $ScriptAnalyzerRules) {
			$i = $ScriptAnalyzerRules.IndexOf($rule)
			It "passes the PSScriptAnalyzer Rule number $i - $rule  " {
				(Invoke-ScriptAnalyzer -Path "$PSScriptRoot\..\internal\$scriptname" -IncludeRule $rule.RuleName).Count | Should Be 0
			}
		}
	}
}

# Test functionality

Describe "Restore-DbaDatabase Integration Tests" -Tags "Integrationtests" {
	Context "Properly restores a database on the local drive using Path" {
		$results = Restore-DbaDatabase -SqlServer localhost -Path C:\github\appveyor-lab\singlerestore\singlerestore.bak
		It "Should Return the proper backup file location" {
			$results.BackupFile | Should Be "C:\github\appveyor-lab\singlerestore\singlerestore.bak"
		}
		It "Should return successful restore" {
			$results.RestoreComplete | Should Be $true
		}
	}

Context "Ensuring warning is thrown if database already exists" {
		$results = Restore-DbaDatabase -SqlServer localhost -Path C:\github\appveyor-lab\singlerestore\singlerestore.bak -WarningVariable warning
		It "Should warn" {
			$warning | Should Match "exists and will not be overwritten"
		}
		It "Should not return object" {
			$results | Should Be $null
		}
	}
	
	Context "Database is properly removed for next test" {
		$results = Remove-DbaDatabase -SqlInstance localhost -Database singlerestore
		It "Should say the status was dropped" {
			$results.Status | Should Be "Dropped"
		}
	}
	
	Context "Properly restores a database on the local drive using piped Get-ChildItem results" {
		$results = Get-ChildItem C:\github\appveyor-lab\singlerestore\singlerestore.bak | Restore-DbaDatabase -SqlServer localhost
		It "Should Return the proper backup file location" {
			$results.BackupFile | Should Be "C:\github\appveyor-lab\singlerestore\singlerestore.bak"
		}
		It "Should return successful restore" {
			$results.RestoreComplete | Should Be $true
		}
	}
	
	Context "Database is properly removed again" {
		$results = Remove-DbaDatabase -SqlInstance localhost -Database singlerestore
		It "Should say the status was dropped" {
			$results.Status | Should Be "Dropped"
		}
	}
	
	Context "Properly restores an instance using ola backups" {
		$results = Get-ChildItem C:\github\appveyor-lab\sql2008-backups | Restore-DbaDatabase -SqlServer localhost
		It "Restored files count should be right" {
			$results.databasename.count | Should Be 31
		}
		It "Should return successful restore" {
			$results.RestoreComplete | Should Match $true
		}
	}
	
    Context "Count user databases as an example" {
        $results = Get-DbaDatabase -SqlInstance localhost -NoSystemDb 
        It "Should report the right number of databases" {
            $results.Count | Should Be 9
        }
    }
    Context "All user databases are removed" {
            $results = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
            It "Should say the status was dropped" {
                $results.Status | Should Match "Dropped"
            }
        }
	#Context "All user databases are removed" {
	#	$results = Get-DbaDatabase -SqlInstance localhost -NoSystemDb | Remove-DbaDatabase
	#	It "Should say the status was dropped" {
	#		$results.Status | Should Match "Dropped"
	#	}
	#}
}