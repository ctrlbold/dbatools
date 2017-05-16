Function Test-DbaSqlPath
{
<#
.SYNOPSIS
Tests if file or directory exists from the perspective of the SQL Server service account

.DESCRIPTION
Uses master.dbo.xp_fileexist to determine if a file or directory exists

.PARAMETER SqlServer
The SQL Server you want to run the test on.

.PARAMETER Path
The Path to tests. Can be a file or directory.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows
credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.


.NOTES
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: Admin access to server (not SQL Services),
Remoting must be enabled and accessible if $sqlserver is not local

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Test-DbaSqlPath

.EXAMPLE
Test-DbaSqlPath -SqlServer sqlcluster -Path L:\MSAS12.MSSQLSERVER\OLAP

Tests whether the service account running the "sqlcluster" SQL Server isntance can access L:\MSAS12.MSSQLSERVER\OLAP. Logs into sqlcluster using Windows credentials. 

.EXAMPLE
$credential = Get-Credential
Test-DbaSqlPath -SqlServer sqlcluster -SqlCredential $credential -Path L:\MSAS12.MSSQLSERVER\OLAP

Tests whether the service account running the "sqlcluster" SQL Server isntance can access L:\MSAS12.MSSQLSERVER\OLAP. Logs into sqlcluster using SQL authentication. 
#>
	[CmdletBinding()]
    [OutputType([bool])]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[Parameter(Mandatory = $true)]
		[string]$Path,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	#$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	$FunctionName =(Get-PSCallstack)[0].Command
	try 
	{
		if ($sqlServer -isnot [Microsoft.SqlServer.Management.Smo.SqlSmoObject])
		{
			Write-verbose "$FunctionName - Opening SQL Server connection"
			$NewConnection = $True
			$Server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential	
		}
		else
		{
			Write-Verbose "$FunctionName - reusing SMO connection"
			$server = $SqlServer
		}
	}
	catch {

		Write-Warning "$FunctionName - Cannot connect to $SqlServer" 
		break
	}
	Write-Verbose "$FunctionName - Path check is $path"
	$sql = "EXEC master.dbo.xp_fileexist '$path'"
	try
	{
		#$fileexist = Invoke-DbaSqlcmd -server $server -Query $sql
		$fileexist = $server.ConnectionContext.ExecuteWithResults($sql)
	}
	catch
	{
		Write-Warning "Test-DbaSqlPath failed: $_"
		throw
	}
	if ($fileexist.tables.rows[0] -eq $true -or $fileexist.tables.rows[1] -eq $true)
	{
		return $true
	}
	else
	{
		return $false
	}
	
	Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$true -Alias Test-SqlPath
}
