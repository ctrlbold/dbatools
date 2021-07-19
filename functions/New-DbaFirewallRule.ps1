function New-DbaFirewallRule {
    <#
    .SYNOPSIS
        Creates a new inbound firewall rule for a SQL Server instance and adds the rule to the target computer.

    .DESCRIPTION
        Creates a new inbound firewall rule for a SQL Server instance and adds the rule to the target computer.

        This is basically a wrapper around New-NetFirewallRule executed at the target computer.
        So this only works if New-NetFirewallRule works on the target computer.

        Both DisplayName and Name are set to the same value by default, since DisplayName is required
        but only Name uniquely defines the rule, thus avoiding duplicate rules with different settings.
        The error 'Cannot create a file when that file already exists.' will be returned
        if a rule with the same Name already exist.

        The functionality is currently limited to creating rules for a default instance, a named instance, and the SQL Server Browser.
        Help to extend the functionality is welcome.

        As long as you can read this note here, there may be breaking changes in future versions.
        So please review your scripts using this command after updating dbatools.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

    .PARAMETER Auto
        If this switch is enabled, the configuration is determined automatically.

        The firewall rule for the instance itself will have the following configuration (parameters for New-NetFirewallRule):
            DisplayName = 'SQL Server default instance' or 'SQL Server instance <InstanceName>'
            Name        = 'SQL Server default instance' or 'SQL Server instance <InstanceName>'
            Group       = 'SQL Server'
            Enabled     = 'True'
            Direction   = 'Inbound'
            Protocol    = 'TCP'
            LocalPort   = <Port> (for instances with static port)
            Program     = <Path ending with MSSQL\Binn\sqlservr.exe> (for instances with dynamic port)

        If the instane is using a dynamic port or a static port other than 1433,
        a firewall rule for the SQL Server Browser will be added with the following configuration (parameters for New-NetFirewallRule):
            DisplayName = 'SQL Server Browser'
            Name        = 'SQL Server Browser'
            Group       = 'SQL Server'
            Enabled     = 'True'
            Direction   = 'Inbound'
            Protocol    = 'UPD'
            LocalPort   = 1434

    .PARAMETER Configuration
        A hashtable with custom configuration parameters that are used when calling New-NetFirewallRule.
        If used together with -Auto, these will override the default settings.
        If used without -Auto, you have to specify all parameters needed by New-NetFirewallRule.

        https://docs.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Firewall, Network
        Author: Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaFirewallRule

    .EXAMPLE
        PS C:\> New-DbaFirewallRule -SqlInstance SRV1, SRV1\TEST -Auto

        Automatically configures the needed firewall rules for both the default instance and the instance named TEST on SRV1.

    .EXAMPLE
        PS C:\> New-DbaFirewallRule -SqlInstance SRV1, SRV1\TEST -Auto -Configuration @{ Profile = 'Domain', Group = 'SQL' }

        Automatically configures the needed firewall rules for both the default instance and the instance named TEST on SRV1,
        but configures the firewall rule for the domain profile only and uses the group name 'SQL' instead of the default 'SQL Server'.

    .EXAMPLE
        PS C:\> $fwConf = @{
        >>     DisplayName = 'SQL Server'
        >>     Enabled     = 'True'
        >>     Direction   = 'Inbound'
        >>     Protocol    = 'TCP'
        >>     LocalPort   = 14331
        >> }
        PS C:\> New-DbaFirewallRule -SqlInstance SRV2\DEMO -Configuration $fwConf

        Creates a firewall rule with the given configuration for the DEMO instance on SRV2.
        As -Auto is not used, the command only creates a rule for the instance and no rule for the SQL Server Browser.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [switch]$Auto,
        [hashtable]$Configuration,
        [switch]$EnableException
    )

    begin {
        $cmdScriptBlock = {
            # This scriptblock will be processed by Invoke-Command2.
            $firewallRuleParameters = $args[0]

            try {
                if (-not (Get-Command -Name New-NetFirewallRule -ErrorAction SilentlyContinue)) {
                    throw 'The module NetSecurity with the command New-NetFirewallRule is missing on the target computer, so New-DbaFirewallRule is not supported.'
                }
                $successful = $true
                $cimInstance = New-NetFirewallRule @firewallRuleParameters -WarningVariable warn -ErrorVariable err -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                if ($warn.Count -gt 0) {
                    $successful = $false
                } else {
                    # Change from an empty System.Collections.ArrayList to $null for better readability
                    $warn = $null
                }
                if ($err.Count -gt 0) {
                    $successful = $false
                } else {
                    # Change from an empty System.Collections.ArrayList to $null for better readability
                    $err = $null
                }
                [PSCustomObject]@{
                    Successful  = $successful
                    CimInstance = $cimInstance
                    Warning     = $warn
                    Error       = $err
                    Exception   = $null
                }
            } catch {
                [PSCustomObject]@{
                    Successful  = $false
                    CimInstance = $null
                    Warning     = $null
                    Error       = $null
                    Exception   = $_
                }
            }
        }
    }

    process {
        if (-not $Auto -and -not $Configuration) {
            Stop-Function -Message "If -Auto is not used, you have to provide the exact configuration of the firewall rule with -Configuration."
            return
        }

        foreach ($instance in $SqlInstance) {
            $config = @{ }
            $programNeeded = $false
            $browserNeeded = $false

            if ($Auto) {
                # Apply the defaults
                $config = @{
                    Group     = 'SQL Server'
                    Enabled   = 'True'
                    Direction = 'Inbound'
                    Protocol  = 'TCP'
                }

                # Test for default or named instance
                if ($instance.InstanceName -eq 'MSSQLSERVER') {
                    $config['DisplayName'] = 'SQL Server default instance'
                    $config['Name'] = 'SQL Server default instance'
                } else {
                    $config['DisplayName'] = "SQL Server instance $($instance.InstanceName)"
                    $config['Name'] = "SQL Server instance $($instance.InstanceName)"
                    $browserNeeded = $true
                }

                # Get information about IP addresses for LocalPort
                try {
                    $tcpIpAddresses = Get-DbaNetworkConfiguration -SqlInstance $instance -Credential $Credential -OutputType TcpIpAddresses -EnableException
                } catch {
                    Stop-Function -Message "Failed." -Target $instance -ErrorRecord $_ -Continue
                }

                if ($tcpIpAddresses.Count -gt 1) {
                    Stop-Function -Message "SQL Server instance $instance listens on more than one IP addresses. This is currently not supported by this command." -Continue
                }

                if ($tcpIpAddresses.TcpPort -ne '') {
                    $config['LocalPort'] = $tcpIpAddresses.TcpPort
                    if ($tcpIpAddresses.TcpPort -ne '1433') {
                        $browserNeeded = $true
                    }
                } else {
                    $programNeeded = $true
                }

                if ($programNeeded) {
                    # Get information about service for Program
                    try {
                        $service = Get-DbaService -ComputerName $instance.ComputerName -InstanceName $instance.InstanceName -Credential $Credential -Type Engine -EnableException
                    } catch {
                        Stop-Function -Message "Failed." -Target $instance -ErrorRecord $_ -Continue
                    }
                    $config['Program'] = $service.BinaryPath -replace '^"?(.*sqlservr.exe).*$', '$1'
                }
            }

            # Apply the given configuration
            if ($Configuration) {
                foreach ($param in $Configuration.Keys) {
                    $config[$param] = $Configuration[$param]
                }
            }

            # Run the command for the instance
            if ($PSCmdlet.ShouldProcess($instance, "Creating firewall rule for instance $($instance.InstanceName) on $($instance.ComputerName)")) {
                try {
                    $commandResult = Invoke-Command2 -ComputerName $instance.ComputerName -Credential $Credential -ScriptBlock $cmdScriptBlock -ArgumentList $config
                } catch {
                    Stop-Function -Message "Failed to execute command on $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
                }

                # Output information
                [PSCustomObject]@{
                    ComputerName = $instance.ComputerName
                    InstanceName = $instance.InstanceName
                    SqlInstance  = $instance.SqlFullName.Trim('[]')
                    DisplayName  = $config['DisplayName']
                    Successful   = $commandResult.Successful
                    Status       = $commandResult.CimInstance.Status
                    Warning      = $commandResult.Warning
                    Error        = $commandResult.Error
                    Exception    = $commandResult.Exception
                    Details      = $commandResult
                } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, DisplayName, Successful, Status, Warning, Error, Exception
            }

            # Firewall rule for the instance is in place, let's see if we need one for the SQL Server Browser
            if ($browserNeeded) {
                # Apply the defaults
                $config = @{
                    DisplayName = 'SQL Server Browser'
                    Name        = 'SQL Server Browser'
                    Group       = 'SQL Server'
                    Enabled     = 'True'
                    Direction   = 'Inbound'
                    Protocol    = 'UDP'
                    LocalPort   = 1434
                }

                # Apply the given configuration
                if ($Configuration) {
                    foreach ($param in $Configuration.Keys) {
                        $config[$param] = $Configuration[$param]
                    }
                }

                # Run the command for the browser
                if ($PSCmdlet.ShouldProcess($instance, "Creating firewall rule for SQL Server Browser on $($instance.ComputerName)")) {
                    try {
                        $commandResult = Invoke-Command2 -ComputerName $instance.ComputerName -Credential $Credential -ScriptBlock $cmdScriptBlock -ArgumentList $config
                    } catch {
                        Stop-Function -Message "Failed to execute command on $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
                    }

                    # Output information
                    [PSCustomObject]@{
                        ComputerName = $instance.ComputerName
                        InstanceName = $instance.InstanceName
                        SqlInstance  = $instance.SqlFullName.Trim('[]')
                        DisplayName  = $config['DisplayName']
                        Successful   = $commandResult.Successful
                        Status       = $commandResult.CimInstance.Status
                        Warning      = $commandResult.Warning
                        Error        = $commandResult.Error
                        Exception    = $commandResult.Exception
                        Details      = $commandResult
                    } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, DisplayName, Successful, Status, Warning, Error, Exception
                }
            }
        }
    }
}