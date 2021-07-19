function Get-DbaFirewallRule {
    <#
    .SYNOPSIS
        Returns firewall rules for SQL Server instances from the target computer.

    .DESCRIPTION
        Returns firewall rules for SQL Server instances from the target computer.

        This is basically a wrapper around Get-NetFirewallRule executed at the target computer.
        So this only works if Get-NetFirewallRule works on the target computer.

        The functionality is currently limited to returning rules from a given group.
        Help to extend the functionality is welcome.

        As long as you can read this note here, there may be breaking changes in future versions.
        So please review your scripts using this command after updating dbatools.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

        Currently only the ComputerName part is used to connect to the target computer.
        Filtering for a specific instance has to be done with FilterScript.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

    .PARAMETER Group
        Returns firewall rules from the given group.
        Defaults to 'SQL Server'.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Firewall, Network
        Author: Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaFirewallRule

    .EXAMPLE
        PS C:\> Get-DbaFirewallRule -SqlInstance SRV1

        Returns all firewall rules from SRV1 related to SQL Server.

    .EXAMPLE
        PS C:\> Get-DbaFirewallRule -SqlInstance SRV1 -Group 'SQL'

        Returns all firewall rules in group 'SQL' from SRV1.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [string]$Group = 'SQL Server',
        [switch]$EnableException
    )

    begin {
        $cmdScriptBlock = {
            # This scriptblock will be processed by Invoke-Command2.
            $group = $args[0]

            try {
                if (-not (Get-Command -Name Get-NetFirewallRule -ErrorAction SilentlyContinue)) {
                    throw 'The module NetSecurity with the command Get-NetFirewallRule is missing on the target computer, so Get-DbaFirewallRule is not supported.'
                }
                $successful = $true
                $verbose = @( )
                $rules = Get-NetFirewallRule -Group $group -WarningVariable warn -ErrorVariable err -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                if ($warn.Count -gt 0) {
                    $successful = $false
                } else {
                    # Change from an empty System.Collections.ArrayList to $null for better readability
                    $warn = $null
                }
                if ($err.Count -gt 0) {
                    if ($err.Count -eq 1 -and $err[0] -match 'No MSFT_NetFirewallRule objects found') {
                        $verbose += "No objects found. Detailed error message: $($err[0])"
                        $err = $null
                    } else {
                        $successful = $false
                    }
                } else {
                    # Change from an empty System.Collections.ArrayList to $null for better readability
                    $err = $null
                }
                if ($successful) {
                    $verbose += "Get-NetFirewallRule was successful, we have $($rules.Count) rules."
                    $rulesWithDetails = @( )
                    foreach ($rule in $rules) {
                        $rulesWithDetails += [PSCustomObject]@{
                            DisplayName = $rule.DisplayName
                            Name        = $rule.Name
                            Protocol    = ($rule | Get-NetFirewallPortFilter).Protocol
                            LocalPort   = ($rule | Get-NetFirewallPortFilter).LocalPort
                            Program     = ($rule | Get-NetFirewallApplicationFilter).Program
                            Rule        = $rule
                        }
                    }
                }
                [PSCustomObject]@{
                    Successful = $successful
                    Rules      = $rulesWithDetails
                    Verbose    = $verbose
                    Warning    = $warn
                    Error      = $err
                    Exception  = $null
                }
            } catch {
                [PSCustomObject]@{
                    Successful = $false
                    Rules      = $null
                    Verbose    = $null
                    Warning    = $null
                    Error      = $null
                    Exception  = $_
                }
            }
        }
    }

    process {
        foreach ($instance in $SqlInstance) {

            try {
                $commandResult = Invoke-Command2 -ComputerName $instance.ComputerName -Credential $Credential -ScriptBlock $cmdScriptBlock -ArgumentList $Group
            } catch {
                Stop-Function -Message "Failed to execute command on $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
            }

            # Output information
            if ($commandResult.Successful) {
                if ($commandResult.Verbose) {
                    foreach ($message in $commandResult.Verbose) {
                        Write-Message -Level Verbose -Message $message
                    }
                }
                foreach ($rule in $commandResult.Rules) {
                    [PSCustomObject]@{
                        ComputerName = $instance.ComputerName
                        DisplayName  = $rule.DisplayName
                        Name         = $rule.Name
                        Protocol     = $rule.Protocol
                        LocalPort    = $rule.LocalPort
                        Program      = $rule.Program
                        Rule         = $rule
                        Credential   = $Credential
                    } | Select-DefaultView -Property ComputerName, DisplayName, Name, Protocol, LocalPort, Program
                }
            } else {
                [PSCustomObject]@{
                    ComputerName = $instance.ComputerName
                    Warning      = $commandResult.Warning
                    Error        = $commandResult.Error
                    Exception    = $commandResult.Exception
                    Details      = $commandResult
                } | Select-DefaultView -Property ComputerName, Warning, Error, Exception
            }
        }
    }
}