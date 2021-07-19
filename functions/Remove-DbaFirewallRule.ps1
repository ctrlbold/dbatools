function Remove-DbaFirewallRule {
    <#
    .SYNOPSIS
        Removes firewall rules for SQL Server instances from the target computer.

    .DESCRIPTION
        Removes firewall rules for SQL Server instances from the target computer.

        This is basically a wrapper around Remove-NetFirewallRule executed at the target computer.
        So this only works if Remove-NetFirewallRule works on the target computer.

        The functionality is currently limited to removing all rules from a given group
        or removing all rules piped in from Get-DbaFirewallRule.
        Help to extend the functionality is welcome.

        As long as you can read this note here, there may be breaking changes in future versions.
        So please review your scripts using this command after updating dbatools.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

    .PARAMETER Group
        Returns firewall rules from the given group.
        Defaults to 'SQL Server'.

    .PARAMETER InputObject
        The output object from Get-DbaFirewallRule.

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
        https://dbatools.io/Remove-DbaFirewallRule

    .EXAMPLE
        PS C:\> Remove-DbaFirewallRule -SqlInstance SRV1

        Removes all firewall rules from SRV1 related to SQL Server.

    .EXAMPLE
        PS C:\> Get-DbaFirewallRule -SqlInstance SRV1 | Where-Object Name -eq 'SQL Server default instance' | Remove-DbaFirewallRule

        Removes the firewall rule for the default instance from SRV1.

    .EXAMPLE
        PS C:\> Get-DbaFirewallRule -SqlInstance SRV1 -Group 'SQL' -Confirm:$false

        Removes all firewall rules in group 'SQL' from SRV1. Does not prompt for confirmation.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High", DefaultParameterSetName = 'NonPipeline')]
    param (
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true, Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [PSCredential]$Credential,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string]$Group = 'SQL Server',
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [object[]]$InputObject,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $cmdScriptBlock = {
            # This scriptblock will be processed by Invoke-Command2.
            # Since only rules that were previously determined with Get-NetFirewallRule are deleted, there should be no problems.
            $firewallRuleName = $args[0]

            try {
                $successful = $true
                $null = Remove-NetFirewallRule -Name $firewallRuleName -WarningVariable warn -ErrorVariable err -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
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
                    Successful = $successful
                    Warning    = $warn
                    Error      = $err
                    Exception  = $null
                }
            } catch {
                [PSCustomObject]@{
                    Successful = $false
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
                Write-Message -Level Verbose -Message "Get firewall rules from $($instance.ComputerName)."
                $InputObject = Get-DbaFirewallRule -SqlInstance $instance -Credential $Credential -Group $Group -EnableException
            } catch {
                Stop-Function -Message "Failed to collect firewall rules from $($instance.ComputerName)." -Target $instance -ErrorRecord $_ -Continue
            }
        }

        foreach ($rule in $InputObject) {
            # Run the command for the instance
            $displayName = $rule.DisplayName
            if ($rule.Name -ne $rule.DisplayName) {
                $displayName += " ($($rule.Name))"
            }
            if ($PSCmdlet.ShouldProcess($rule.ComputerName, "Removing firewall rule $displayName")) {
                try {
                    #$rule.ComputerName = (Resolve-DbaNetworkName -ComputerName $rule.ComputerName).ComputerName
                    Write-Message -Level Verbose -Message "Executing Invoke-Command2 with ComputerName = $($rule.ComputerName) and ArgumentList $($rule.Name)."
                    $commandResult = Invoke-Command2 -ComputerName $rule.ComputerName -Credential $rule.Credential -ScriptBlock $cmdScriptBlock -ArgumentList $rule.Name
                    Write-Message -Level Verbose -Message "We have $($commandResult.Count) result that is $($commandResult.Successful)."
                } catch {
                    Stop-Function -Message "Failed to execute command on $($rule.ComputerName)." -Target $instance -ErrorRecord $_ -Continue
                }

                # Output information
                [PSCustomObject]@{
                    ComputerName = $rule.ComputerName
                    DisplayName  = $rule.DisplayName
                    Name         = $rule.Name
                    IsRemoved    = $commandResult.Successful
                    Warning      = $commandResult.Warning
                    Error        = $commandResult.Error
                    Exception    = $commandResult.Exception
                } | Select-DefaultView -Property ComputerName, DisplayName, Name, IsRemoved, Warning, Error, Exception
            }
        }
    }
}