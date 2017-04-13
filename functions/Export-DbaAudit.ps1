﻿Function Export-DbaAudit {
    <#
	.SYNOPSIS
	Export one, many or all SQL Server audits

	.DESCRIPTION
	Exports one, many or all SQL Server audits as T-SQL output

	.PARAMETER SqlInstance
	The target SQL Server instance - may be either a string or an SMO Server object

	.PARAMETER SqlCredential
	Allows you to login to servers using alternative SQL or Windows credentials

	.PARAMETER Audits
	By default, all audits are exported. This parameters allows you to export only specific audits
		
	.PARAMETER Path
	The output filename and location. If no path is specified, one will be created 
		
	.PARAMETER Append
	Append contents to existing file. If append is not specified and the path exists, the export will be skipped.
		
	.PARAMETER Encoding
	Specifies the file encoding. The default is UTF8.
		
	Valid values are:

	-- ASCII: Uses the encoding for the ASCII (7-bit) character set.

	-- BigEndianUnicode: Encodes in UTF-16 format using the big-endian byte order.

	-- Byte: Encodes a set of characters into a sequence of bytes.

	-- String: Uses the encoding type for a string.

	-- Unicode: Encodes in UTF-16 format using the little-endian byte order.

	-- UTF7: Encodes in UTF-7 format.

	-- UTF8: Encodes in UTF-8 format.

	-- Unknown: The encoding type is unknown or invalid. The data can be treated as binary.

	.PARAMETER Passthru
	Output script to console

	.PARAMETER WhatIf 
	Shows what would happen if the command were to run. No actions are actually performed

	.PARAMETER Confirm 
	Prompts you for confirmation before executing any changing operations within the command

	.PARAMETER Silent 
	Use this switch to disable any kind of verbose messages

	.NOTES
	Tags: Migration, Backup
	
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Export-DbaAudit

	.EXAMPLE 
	Export-DbaAudit -SqlInstance sql2016

	Exports all audits on the SQL Server 2016 instance using a trusted connection - automatically determines filename as .\servername-audits-date.sql
		
	.EXAMPLE 
	Export-DbaAudit -SqlInstance sql2016 -Audits Audit-20160502-100608 -SqlCredential (Get-Credetnial sqladmin) -Path C:\temp\export.sql
		
	Exports only Audit-20160502-100608 to C:temp\export.sql and uses the SQL login "sqladmin"
	
	.EXAMPLE 
	Export-DbaAudit -SqlInstance sql2014 -Passthru | ForEach-Object { $_.Replace('sql2014','sql2016') } | Set-Content -Path C:\temp\export.sql
		
	Exports audits and replaces all instances of the servername "sql2014" with "sql2016" then writes to C:\temp\export.sql
	#>
	
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[string]$Path,
		[ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
		[string]$Encoding = 'UTF8',
		[switch]$Append,
		[switch]$Passthru,
		[switch]$Silent
	)
	
	dynamicparam {
		if ($SqlInstance) {
			return Get-ParamSqlAudits -SqlServer $SqlInstance[0] -SqlCredential $SqlCredential
		}
	}
	
	begin {
		$audits = $psboundparameters.Audits
		$executinguser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
		$commandname = $MyInvocation.MyCommand.Name
		$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
	}
	
	process {
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failed to connect to: $instance" -Continue -Target $instance
			}
			
			$servername = $server.name.replace('\', '$')
			
			if (!$passthru) {
				if ($path) {
					$actualpath = $path
				}
				else {
					$actualpath = "$servername-audits-$timenow.sql"
				}
			}
			
			$prefix = "
/*			
	Created by $executinguser using dbatools $commandname for objects on $servername at $(Get-Date)
	See https://dbatools.io/$commandname for more information
*/"
			
			if (!$Append -and !$Passthru) {
				if (Test-Path -Path $actualpath) {
					Stop-Function -Message "OutputFile $actualpath already exists and Append was not specified." -Target $actualpath -Continue
				}
			}
			
			$exportaudits = $server.Audits
			
			if ($audits) {
				$exportaudits = $exportaudits | Where-Object {
					$_.Name -in $audits
				}
			}
			
			if ($passthru) {
				$prefix | Out-String
			}
			else {
				Write-Message -Level Output -Message "Exporting objects on $servername to $actualpath"
				$prefix | Out-File -FilePath $actualpath -Encoding $encoding -Append
			}
			
			foreach ($audit in $exportaudits) {
				If ($Pscmdlet.ShouldProcess($env:computername, "Exporting $audit from $server to $actualpath")) {
					Write-Message -Level Verbose -Message "Exporting $audit"
					
					if ($passthru) {
						$audit.Script() | Out-String
					}
					else {
						$audit.Script() | Out-File -FilePath $actualpath -Encoding $encoding -Append
					}
				}
			}
			
			if (!$passthru) {
				Write-Message -Level Output -Message "Completed export for $server"
			}
		}
	}
}