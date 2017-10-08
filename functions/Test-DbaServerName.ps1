function Test-DbaServerName {
	<#
		.SYNOPSIS
			Tests to see if it's possible to easily rename the server at the SQL Server instance level, or if it even needs to be changed.

		.DESCRIPTION
			When a SQL Server's host OS is renamed, the SQL Server should be as well. This helps with Availability Groups and Kerberos.

			This command helps determine if your OS and SQL Server names match, and whether a rename is required.

			It then checks conditions that would prevent a rename, such as database mirroring and replication.

			https://www.mssqltips.com/sqlservertip/2525/steps-to-change-the-server-name-for-a-sql-server-machine/

		.PARAMETER SqlInstance
			The SQL Server that you're connecting to.

		.PARAMETER Credential
			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$scred = Get-Credential, then pass $scred object to the -Credential parameter.

			Windows Authentication will be used if Credential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Detailed
			If this switch is enabled, additional details are returned including whether the server name is updatable. If the server name is not updatable, the reason why will be returned.

		.PARAMETER NoWarning
			If this switch is enabled, no warning will be displayed if SQL Server Reporting Services can't be checked due to a failure to connect via Get-Service.

		.NOTES
			Tags: SPN
			dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
			Copyright (C) 2016 Chrissy LeMaire
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Test-DbaServerName

		.EXAMPLE
			Test-DbaServerName -SqlInstance sqlserver2014a

			Returns ServerInstanceName, SqlServerName, IsEqual and RenameRequired for sqlserver2014a.

		.EXAMPLE
			Test-DbaServerName -SqlInstance sqlserver2014a, sql2016

			Returns ServerInstanceName, SqlServerName, IsEqual and RenameRequired for sqlserver2014a and sql2016.

		.EXAMPLE
			Test-DbaServerName -SqlInstance sqlserver2014a, sql2016 -Detailed

			Returns ServerInstanceName, SqlServerName, IsEqual and RenameRequired for sqlserver2014a and sql2016.

			If a Rename is required, it will also show Updatable, and Reasons if the servername is not updatable.
		#>
	[CmdletBinding()]
	[OutputType([System.Collections.ArrayList])]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$Credential,
		[switch]$Detailed,
		[switch]$NoWarning
	)

	process {

		foreach ($servername in $SqlInstance) {
			try {
				$server = Connect-SqlInstance -SqlInstance $servername -SqlCredential $Credential
			}
			catch {
				Write-Message -Level Warning -Message  "Can't connect to $servername. Moving on."
				Continue
			}

			if ($server.isClustered) {
				Write-Message -Level Warning -Message  "$servername is a cluster. Renaming clusters is not supported by Microsoft."
			}

			if ($server.VersionMajor -eq 8) {
				if ($servercount -eq 1 -and $SqlInstance.count -eq 1) {
					throw "SQL Server 2000 not supported."
				}
				else {
					Write-Message -Level Warning -Message  "SQL Server 2000 not supported. Skipping $servername."
					Continue
				}
			}

			$SqlInstancename = $server.ConnectionContext.ExecuteScalar("select @@servername")
			$instance = $server.InstanceName

			if ($instance.length -eq 0) {
				$serverinstancename = $server.NetName
				$instance = "MSSQLSERVER"
			}
			else {
				$netname = $server.NetName
				$serverinstancename = "$netname\$instance"
			}

			$serverinfo = [PSCustomObject]@{
				ServerInstanceName = $serverinstancename
				SqlServerName      = $SqlInstancename
				IsEqual            = $serverinstancename -eq $SqlInstancename
				RenameRequired     = $serverinstancename -ne $SqlInstancename
				Updatable          = "N/A"
				Warnings           = $null
				Blockers           = $null
			}

			if ($Detailed) {
				$reasons = @()
				$servicename = "SQL Server Reporting Services ($instance)"
				$netbiosname = $server.ComputerNamePhysicalNetBIOS
				Write-Message -Level Verbose -Message  "Checking for $servicename on $netbiosname"
				$rs = $null

				try {
					$rs = Get-Service -ComputerName $netbiosname -DisplayName $servicename -ErrorAction SilentlyContinue
				}
				catch {
					if ($NoWarning -eq $false) {
						Write-Message -Level Warning -Message  "Can't contact $netbiosname using Get-Service. This means the script will not be able to automatically restart SQL services."
					}
				}

				if ($rs.length -gt 0) {
					if ($rs.Status -eq 'Running') {
						$rstext = "Reporting Services ($instance) must be stopped and updated."
					}
					else {
						$rstext = "Reporting Services ($instance) exists. When it is started again, it must be updated."
					}
					$serverinfo.Warnings = $rstext
				}
				else {
					$serverinfo.Warnings = "N/A"
				}

				# check for mirroring
				$mirroreddb = $server.Databases | Where-Object { $_.IsMirroringEnabled -eq $true }

				Write-Debug "Found the following mirrored dbs: $($mirroreddb.name)"

				if ($mirroreddb.length -gt 0) {
					$dbs = $mirroreddb.name -join ", "
					$reasons += "Databases are being mirrored: $dbs"
				}

				# check for replication
				$sql = "select name from sys.databases where is_published = 1 or is_subscribed =1 or is_distributor = 1"
				Write-Debug $sql
				$replicatedb = $server.ConnectionContext.ExecuteWithResults($sql).Tables

				if ($replicatedb.name.length -gt 0) {
					$dbs = $replicatedb.name -join ", "
					$reasons += "Databases are involved in replication: $dbs"
				}

				# check for even more replication
				$sql = "select srl.remote_name as RemoteLoginName from sys.remote_logins srl join sys.sysservers sss on srl.server_id = sss.srvid"
				Write-Debug $sql
				$results = $server.ConnectionContext.ExecuteWithResults($sql).Tables

				if ($results.RemoteLoginName.length -gt 0) {
					$remotelogins = $results.RemoteLoginName -join ", "
					$reasons += "Remote logins still exist: $remotelogins"
				}

				if ($reasons.length -gt 0) {
					$serverinfo.Updatable = $false
					$serverinfo.Blockers = $reasons
				}
				else {
					$serverinfo.Updatable = $true
					$serverinfo.Blockers = "N/A"
				}
			}
			
			if ($Detailed) {
				$serverinfo
			}
			else {
				$serverinfo | Select-DefaultView -ExcludeProperty Warnings, Blockers
			}
		}
	}
}