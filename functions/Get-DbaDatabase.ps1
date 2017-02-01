﻿FUNCTION Get-DbaDatabase
{
<#
.SYNOPSIS
Gets a SQL database object for each database that is present in the target instance of SQL Server.

.DESCRIPTION
 The Get-SqlDatabase command gets a SQL database object for each database that is present in the target instance of
 SQL Server. If the name of the database is provided, the command will return only this specific database object.
	
.PARAMETER SqlInstance
SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input.

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, current Windows login will be used.

.PARAMETER System
Returns only system databases

.PARAMETER User
Returns only user databases
	
.PARAMETER Online
Returns only online databases

.PARAMETER Offline
Returns only offline databases

.PARAMETER ReadOnly
Returns only readonly databases
	
.PARAMETER ReadWrite
Returns only non-read-only databases
	
.NOTES
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	

.LINK
https://dbatools.io/Get-DbaDatabase

.EXAMPLE
Get-DbaDatabase -SqlServer localhost
Returns all databases on the local default SQL Server instance

.EXAMPLE
Get-DbaDatabase -SqlServer localhost -System
Returns only the system databases on the local default SQL Server instance

.EXAMPLE
Get-DbaDatabase -SqlServer localhost -User
Returns only the user databases on the local default SQL Server instance
	
.EXAMPLE
'localhost','sql2016' | Get-DbaDatabase
Returns databases on multiple instances piped into the function

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[switch]$System,
		[switch]$User,
		[switch]$Online,
		[switch]$Offline,
		[switch]$ReadOnly,
		[switch]$ReadWrite
	)
	
	DynamicParam { if ($SqlInstance) { return Get-ParamSqlDatabases -SqlServer $SqlInstance[0] -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		$databases = $psboundparameters.Databases
	}
	
	PROCESS
	{
		foreach ($instance in $SqlInstance)
		{
			try
			{
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			}
			catch
			{
				Write-Warning "Failed to connect to: $instance"
				continue
			}
			
			$defaults = 'Name', 'Status', 'ContainmentType', 'RecoveryModel', 'CompatibilityLevel', 'Collation', 'Owner'
			
			if ($System)
			{
				# $server.Databases | Where-Object { $_.IsSystemObject -eq $true }
			}
			
			if ($User)
			{
				# $server.Databases | Where-Object { $_.IsSystemObject -eq $false }
			}
			
			if ($databases)
			{
				# $server.Databases | Where-Object { $_.Name -in $databases }
			}
			
			if (@($alldbs).count -eq 0)
			{
				# $alldbs = $server.Databases
			}
			
			$alldbs
		}
	}
}