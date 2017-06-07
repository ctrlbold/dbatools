Function Reset-DbaAdmin {
<#
    .SYNOPSIS
        This function will allow administrators to regain access to SQL Servers in the event that passwords or access was lost.
        
        Supports SQL Server 2005 and above. Windows administrator access is required.
    
    .DESCRIPTION
        This function allows administrators to regain access to local or remote SQL Servers by either resetting the sa password, adding sysadmin role to existing login,
        or adding a new login (SQL or Windows) and granting it sysadmin privileges.
        
        This is accomplished by stopping the SQL services or SQL Clustered Resource Group, then restarting SQL via the command-line
        using the /mReset-DbaAdmin paramter which starts the server in Single-User mode, and only allows this script to connect.
        
        Once the service is restarted, the following tasks are performed:
        - Login is added if it doesn't exist
        - If login is a Windows User, an attempt is made to ensure it exists
        - If login is a SQL Login, password policy will be set to OFF when creating the login, and SQL Server authentication will be set to Mixed Mode.
        - Login will be enabled and unlocked
        - Login will be added to sysadmin role
        
        If failures occur at any point, a best attempt is made to restart the SQL Server.
        
        In order to make this script as portable as possible, System.Data.SqlClient and Get-WmiObject are used (as opposed to requiring the Failover Cluster Admin tools or SMO).
        If using this function against a remote SQL Server, ensure WinRM is configured and accessible. If this is not possible, run the script locally.
        
        Tested on Windows XP, 7, 8.1, Server 2012 and Windows Server Technical Preview 2.
        Tested on SQL Server 2005 SP4 through 2016 CTP2.
    
    .PARAMETER SqlInstance
        The SQL Server instance. SQL Server must be 2005 and above, and can be a clustered or stand-alone instance.
    
    .PARAMETER Login
        By default, the Login parameter is "sa" but any other SQL or Windows account can be specified. If a login does not
        currently exist, it will be added.
        
        When adding a Windows login to remote servers, ensure the SQL Server can add the login (ie, don't add WORKSTATION\Admin to remoteserver\instance. Domain users and
        Groups are valid input.
    
    .PARAMETER Force
        By default, a confirmation is presented to ensure the person executing the script knows that a service restart will occur. Force basically performs a -Confirm:$false. This will restart the SQL Service without prompting.
    
    .PARAMETER Silent
        Replaces user friendly yellow warnings with bloody red exceptions of doom!
        Use this if you want the function to throw terminating errors you want to catch.
    
    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.
    
    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.
    
    .EXAMPLE
        Reset-DbaAdmin -SqlInstance sqlcluster
        
        Prompts for password, then resets the "sa" account password on sqlcluster.
    
    .EXAMPLE
        Reset-DbaAdmin -SqlInstance sqlserver\sqlexpress -Login ad\administrator
        
        Prompts user to confirm that they understand the SQL Service will be restarted.
        
        Adds the domain account "ad\administrator" as a sysadmin to the SQL instance.
        If the account already exists, it will be added to the sysadmin role.
    
    .EXAMPLE
        Reset-DbaAdmin -SqlInstance sqlserver\sqlexpress -Login sqladmin -Force
        
        Skips restart confirmation, prompts for passsword, then adds a SQL Login "sqladmin" with sysadmin privleges.
        If the account already exists, it will be added to the sysadmin role and the password will be reset.
    
    .NOTES
        Tags: WSMan
        Author: Chrissy LeMaire (@cl), netnerds.net
        Requires: Admin access to server (not SQL Services),
        Remoting must be enabled and accessible if $SqlInstance is not local
        
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
        https://dbatools.io/Reset-DbaAdmin
#>    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param (
        [Parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]
        $SqlInstance,
        
        [string]
        $Login = "sa",
        
        [switch]
        $Force,
        
        [switch]
        $Silent
    )
    
    begin {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Reset-SqlAdmin
        
        #region Utility functions
        Function ConvertTo-PlainText {
<#
.SYNOPSIS
Internal function.
			
 #>
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                [Security.SecureString]
                $Password
            )
            
            $marshal = [Runtime.InteropServices.Marshal]
            $plaintext = $marshal::PtrToStringAuto($marshal::SecureStringToBSTR($Password))
            return $plaintext
        }
        
        Function Invoke-ResetSqlCmd {
        <#
            .SYNOPSIS
                Internal function. Executes a SQL statement against specified computer, and uses "Reset-DbaAdmin" as the Application Name.
        			
        #>
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                [Alias("ServerInstance", "SqlServer")]
                [DbaInstanceParameter]
                $SqlInstance,
                
                [string]
                $sql
            )
            try {
                $connstring = "Data Source=$SqlInstance;Integrated Security=True;Connect Timeout=2;Application Name=Reset-DbaAdmin"
                $conn = New-Object System.Data.SqlClient.SqlConnection $connstring
                $conn.Open()
                $cmd = New-Object system.data.sqlclient.sqlcommand($null, $conn)
                $cmd.CommandText = $sql
                $cmd.ExecuteNonQuery() | Out-Null
                $cmd.Dispose()
                $conn.Close()
                $conn.Dispose()
                return $true
            }
            catch {
                return $false
            }
        }
        #endregion Utility functions
    }
    
    process {
        if ($Force) { $ConfirmPreference = "none" }
        
        $baseaddress = $SqlInstance.ComputerName
        
        # Before we continue, we need confirmation.
        if ($pscmdlet.ShouldProcess($baseaddress, "Reset-DbaAdmin (SQL Server instance $SqlInstance will restart)")) {
            # Get hostname
            
            if ($baseaddress -eq "." -or $baseaddress -eq $env:COMPUTERNAME -or $baseaddress -eq "localhost") {
                $ipaddr = "."
                $hostname = $env:COMPUTERNAME
                $baseaddress = $env:COMPUTERNAME
            }
            
            # If server is not local, get IP address and NetBios name in case CNAME records were referenced in the SQL hostname
            if ($baseaddress -ne $env:COMPUTERNAME) {
                # Test for WinRM #Test-WinRM neh
                winrm id -r:$baseaddress 2>$null | Out-Null
                if ($LastExitCode -ne 0) {
                    throw "Remote PowerShell access not enabled on on $source or access denied. Quitting."
                }
                
                # Test Connection first using Test-Connection which requires ICMP access then failback to tcp if pings are blocked
                Write-Message -Level Verbose -Message "Testing connection to $baseaddress"
                $testconnect = Test-Connection -ComputerName $baseaddress -Count 1 -Quiet
                
                if ($testconnect -eq $false) {
                    Write-Message -Level Verbose -Message "First attempt using ICMP failed. Trying to connect using sockets. This may take up to 20 seconds."
                    $tcp = New-Object System.Net.Sockets.TcpClient
                    try {
                        $tcp.Connect($hostname, 135)
                        $tcp.Close()
                        $tcp.Dispose()
                    }
                    catch {
                        throw "Can't connect to $baseaddress either via ping or tcp (WMI port 135)"
                    }
                }
                Write-Message -Level Verbose -Message "Resolving IP address"
                try {
                    $hostentry = [System.Net.Dns]::GetHostEntry($baseaddress)
                    $ipaddr = ($hostentry.AddressList | Where-Object { $_ -notlike '169.*' } | Select-Object -First 1).IPAddressToString
                }
                catch {
                    throw "Could not resolve SqlServer IP or NetBIOS name"
                }
                
                Write-Message -Level Verbose -Message "Resolving NetBIOS name"
                try {
                    $hostname = (Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter IPEnabled=TRUE -ComputerName $ipaddr).PSComputerName
                    if ($hostname -eq $null) { $hostname = (nbtstat -A $ipaddr | Where-Object { $_ -match '\<00\>  UNIQUE' } | ForEach-Object { $_.SubString(4, 14) }).Trim() }
                }
                catch {
                    throw "Could not access remote WMI object. Check permissions and firewall."
                }
            }
            
            # Setup remote session if server is not local
            if ($hostname -ne $env:COMPUTERNAME) {
                try {
                    $session = New-PSSession -ComputerName $hostname
                }
                catch {
                    throw "Can't access $hostname using PSSession. Check your firewall settings and ensure Remoting is enabled or run the script locally."
                }
            }
            
            Write-Message -Level Verbose -Message "Detecting login type"
            # Is login a Windows login? If so, does it exist? 
            if ($login -match "\\") {
                Write-Message -Level Verbose -Message "Windows login detected. Checking to ensure account is valid."
                $windowslogin = $true
                try {
                    if ($hostname -eq $env:COMPUTERNAME) {
                        $account = New-Object System.Security.Principal.NTAccount($args)
                        $sid = $account.Translate([System.Security.Principal.SecurityIdentifier])
                    }
                    else {
                        Invoke-Command -ErrorAction Stop -Session $session -ArgumentList $login -ScriptBlock {
                            $account = New-Object System.Security.Principal.NTAccount($args)
                            $sid = $account.Translate([System.Security.Principal.SecurityIdentifier])
                        }
                    }
                }
                catch { Write-Message -Level Warning -Message "Cannot resolve Windows User or Group $login. Trying anyway." }
            }
            
            # If it's not a Windows login, it's a SQL login, so it needs a password.
            if ($windowslogin -ne $true) {
                Write-Message -Level Verbose -Message "SQL login detected"
                do { $Password = Read-Host -AsSecureString "Please enter a new password for $login" }
                while ($Password.Length -eq 0)
            }
            
            # Get instance and service display name, then get services
            $instance = $null
            $instance = $SqlInstance.InstanceName
            if (-not $instance) { $instance = "MSSQLSERVER" }
            $displayName = "SQL Server ($instance)"
            
            try {
                if ($hostname -eq $env:COMPUTERNAME) {
                    $instanceservices = Get-Service -ErrorAction Stop | Where-Object { $_.DisplayName -like "*($instance)*" -and $_.Status -eq "Running" }
                    $sqlservice = Get-Service -ErrorAction Stop | Where-Object DisplayName -eq "SQL Server ($instance)"
                }
                else {
                    $instanceservices = Get-Service -ComputerName $ipaddr -ErrorAction Stop | Where-Object { $_.DisplayName -like "*($instance)*" -and $_.Status -eq "Running" }
                    $sqlservice = Get-Service -ComputerName $ipaddr -ErrorAction Stop | Where-Object DisplayName -eq "SQL Server ($instance)"
                }
            }
            catch {
                Stop-Function -Message "Cannot connect to WMI on $hostname or SQL Service does not exist. Check permissions, firewall and SQL Server running status." -ErrorRecord $_ -Target $SqlInstance
                return
            }
            
            if (-not $instanceservices) {
                Stop-Function -Message "Couldn't find SQL Server instance. Check the spelling, ensure the service is running and try again." -Target $SqlInstance
                return
            }
            
            Write-Message -Level Verbose -Message "Attempting to stop SQL Services"
            
            # Check to see if service is clustered. Clusters don't support -m (since the cluster service
            # itself connects immediately) or -f, so they are handled differently.
            try {
                $checkcluster = Get-Service -ComputerName $ipaddr -ErrorAction Stop | Where-Object { $_.Name -eq "ClusSvc" -and $_.Status -eq "Running" }
            }
            catch {
                Stop-Function -Message "Can't check services." -Target $SqlInstance -ErrorRecord $_
                return
            }
            
            if ($checkcluster -ne $null) {
                $clusterResource = Get-DbaCmObject -ClassName "MSCluster_Resource" -Namespace "root\mscluster" -ComputerName $hostname |
                Where-Object { $_.Name.StartsWith("SQL Server") -and $_.OwnerGroup -eq "SQL Server ($instance)" }
            }
            
            # Take SQL Server offline so that it can be started in single-user mode
            if ($clusterResource.count -gt 0) {
                $isclustered = $true
                try {
                    $clusterResource | Where-Object { $_.Name -eq "SQL Server" } | ForEach-Object { $_.TakeOffline(60) }
                }
                catch {
                    $clusterResource | Where-Object { $_.Name -eq "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
                    $clusterResource | Where-Object { $_.Name -ne "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
                    Stop-Function -Message "Could not stop the SQL Service. Restarted SQL Service and quit." -ErrorRecord $_ -Target $SqlInstance
                    return
                }
            }
            else {
                try {
                    Stop-Service -InputObject $sqlservice -Force -ErrorAction Stop
                    Write-Message -Level Verbose -Message "Successfully stopped SQL service"
                }
                catch {
                    Start-Service -InputObject $instanceservices -ErrorAction Stop
                    Stop-Function -Message "Could not stop the SQL Service. Restarted SQL service and quit." -ErrorRecord $_ -Target $SqlInstance
                    return
                }
            }
            
            # /mReset-DbaAdmin Starts an instance of SQL Server in single-user mode and only allows this script to connect.
            Write-Message -Level Verbose -Message "Starting SQL Service from command line"
            try {
                if ($hostname -eq $env:COMPUTERNAME) {
                    $netstart = net start ""$displayname"" /mReset-DbaAdmin 2>&1
                    if ("$netstart" -notmatch "success") { throw }
                }
                else {
                    $netstart = Invoke-Command -ErrorAction Stop -Session $session -ArgumentList $displayname -ScriptBlock { net start ""$args"" /mReset-DbaAdmin } 2>&1
                    foreach ($line in $netstart) {
                        if ($line.length -gt 0) { Write-Message -Level Verbose -Message $line }
                    }
                }
            }
            catch {
                Stop-Service -InputObject $sqlservice -Force -ErrorAction SilentlyContinue
                
                if ($isclustered) {
                    $clusterResource | Where-Object Name -eq "SQL Server" | ForEach-Object { $_.BringOnline(60) }
                    $clusterResource | Where-Object Name -ne "SQL Server" | ForEach-Object { $_.BringOnline(60) }
                }
                else {
                    Start-Service -InputObject $instanceservices -ErrorAction SilentlyContinue
                }
                Stop-Function -Message "Couldn't execute net start command. Restarted services and quit." -ErrorRecord $_
                return
            }
            
            Write-Message -Level Verbose -Message "Reconnecting to SQL instance"
            try {
                $null = Invoke-ResetSqlCmd -SqlInstance $sqlinstance -Sql "SELECT 1" -ErrorAction Stop
            }
            catch {
                try {
                    Start-Sleep 3
                    $null = Invoke-ResetSqlCmd -SqlInstance $sqlinstance -Sql "SELECT 1" -ErrorAction Stop
                }
                catch {
                    Stop-Service Input-Object $sqlservice -Force -ErrorAction SilentlyContinue
                    if ($isclustered) {
                        $clusterResource | Where-Object { $_.Name -eq "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
                        $clusterResource | Where-Object { $_.Name -ne "SQL Server" } | ForEach-Object { $_.BringOnline(60) }
                    }
                    else { Start-Service -InputObject $instanceservices -ErrorAction SilentlyContinue }
                    Stop-Function -Message "Could not stop the SQL Service. Restarted SQL Service and quit." -ErrorRecord $_
                }
            }
            
            # Get login. If it doesn't exist, create it.
            Write-Message -Level Verbose -Message "Adding login $login if it doesn't exist"
            if ($windowslogin -eq $true) {
                $sql = "IF NOT EXISTS (SELECT name FROM master.sys.server_principals WHERE name = '$login')
					BEGIN CREATE LOGIN [$login] FROM WINDOWS END"
                if ($(Invoke-ResetSqlCmd -SqlInstance $sqlinstance -Sql $sql) -eq $false) {
                    Write-Message -Level Warning -Message "Couldn't create login."
                }
                
            }
            elseif ($login -ne "sa") {
                # Create new sql user
                $sql = "IF NOT EXISTS (SELECT name FROM master.sys.server_principals WHERE name = '$login')
					BEGIN CREATE LOGIN [$login] WITH PASSWORD = '$(ConvertTo-PlainText $Password)', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF END"
                if ($(Invoke-ResetSqlCmd -SqlInstance $sqlinstance -Sql $sql) -eq $false) {
                    Write-Message -Level Warning -Message "Couldn't create login."
                }
            }
            
            # If $login is a SQL Login, Mixed mode authentication is required.
            if ($windowslogin -ne $true) {
                Write-Message -Level Verbose -Message "Enabling mixed mode authentication"
                Write-Message -Level Verbose -Message "Ensuring account is unlocked"
                $sql = "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'LoginMode', REG_DWORD, 2"
                if ($(Invoke-ResetSqlCmd -SqlInstance $sqlinstance -Sql $sql) -eq $false) {
                    Write-Message -Level Warning -Message "Couldn't set to Mixed Mode."
                }
                
                $sql = "ALTER LOGIN [$login] WITH CHECK_POLICY = OFF
					ALTER LOGIN [$login] WITH PASSWORD = '$(ConvertTo-PlainText $Password)' UNLOCK"
                if ($(Invoke-ResetSqlCmd -SqlInstance $sqlinstance -Sql $sql) -eq $false) {
                    Write-Message -Level Warning -Message "Couldn't unlock account."
                }
            }
            
            Write-Message -Level Verbose -Message "Ensuring login is enabled"
            $sql = "ALTER LOGIN [$login] ENABLE"
            if ($(Invoke-ResetSqlCmd -SqlInstance $sqlinstance -Sql $sql) -eq $false) {
                Write-Message -Level Warning -Message "Couldn't enable login."
            }
            
            if ($login -ne "sa") {
                Write-Message -Level Verbose -Message "Ensuring login exists within sysadmin role"
                $sql = "EXEC sp_addsrvrolemember '$login', 'sysadmin'"
                if ($(Invoke-ResetSqlCmd -SqlInstance $sqlinstance -Sql $sql) -eq $false) {
                    Write-Message -Level Warning -Message "Couldn't add to syadmin role."
                }
            }
            
            Write-Message -Level Verbose -Message "Finished with login tasks"
            Write-Message -Level Verbose -Message "Restarting SQL Server"
            Stop-Service -InputObject $sqlservice -Force -ErrorAction SilentlyContinue
            if ($isclustered -eq $true) {
                $clusterResource | Where-Object Name -eq "SQL Server" | ForEach-Object { $_.BringOnline(60) }
                $clusterResource | Where-Object Name -ne "SQL Server" | ForEach-Object { $_.BringOnline(60) }
            }
            else { Start-Service -InputObject $instanceservices -ErrorAction SilentlyContinue }
        }
    }
    end {
        Write-Message -Level Verbose -Message "Script complete!"
    }
}
