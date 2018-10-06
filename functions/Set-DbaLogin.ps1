function Set-DbaLogin {

    <#
    .SYNOPSIS
    Set-DbaLogin makes it possible to make changes to one or more logins.

    .DESCRIPTION
    Set-DbaLogin will enable you to change the password, unlock, rename, disable or enable, deny or grant login privileges to the login.
    It's also possible to add or remove server roles from the login.

    .PARAMETER SqlInstance
    SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
    Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Login
    The login that needs to be changed

    .PARAMETER Password
    The new password for the login This can be either a credential or a secure string.

    .PARAMETER Unlock
    Switch to unlock an account. This will only be used in conjunction with the -Password parameter.
    The default is false.

    .PARAMETER MustChange
    Does the user need to change his/her password. This will only be used in conjunction with the -Password parameter.
    The default is false.

    .PARAMETER NewName
    The new name for the login.

    .PARAMETER Disable
    Disable the login

    .PARAMETER Enable
    Enable the login

    .PARAMETER DenyLogin
    Deny access to SQL Server

    .PARAMETER GrantLogin
    Grant access to SQL Server

    .PARAMETER PasswordPolicyEnforced
    Should the password policy be enforced.

    .PARAMETER AddRole
    Add one or more server roles to the login
    The following roles can be used "bulkadmin", "dbcreator", "diskadmin", "processadmin", "public", "securityadmin", "serveradmin", "setupadmin", "sysadmin".

    .PARAMETER RemoveRole
    Remove one or more server roles to the login
    The following roles can be used "bulkadmin", "dbcreator", "diskadmin", "processadmin", "public", "securityadmin", "serveradmin", "setupadmin", "sysadmin".

    .PARAMETER InputObject
    Allows logins to be piped in from Get-DbaLogin

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Original Author: Sander Stad (@sqlstad, sqlstad.nl)
    Tags: Login

    Website: https://dbatools.io
    Copyright: (c) 2018 by dbatools, licensed under MIT
    License: MIT https://opensource.org/licenses/MIT

    .LINK
    https://dbatools.io/Set-DbaLogin

    .EXAMPLE
    $password = ConvertTo-SecureString "PlainTextPassword" -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential ("username", $password)
    Set-DbaLogin -SqlInstance sql1 -Login login1 -Password $cred -Unlock -MustChange

    Set the new password for login1 using a credential, unlock the account and set the option
    that the usermust change password at next logon.

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1 -Login login1 -Enable

    Enable the login

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1 -Login login1, login2, login3, login4 -Enable

    Enable multiple logins

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1, sql2, sql3 -Login login1, login2, login3, login4 -Enable

    Enable multiple logins on multiple instances

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1 -Login login1 -Disable

    Disable the login

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1 -Login login1 -DenyLogin

    Deny the login to connect to the instance

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1 -Login login1 -GrantLogin

    Grant the login to connect to the instance

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1 -Login login1 -PasswordPolicyEnforced

    Enforces the password policy on a login

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1 -Login login1 -PasswordPolicyEnforced:$false

    Disables enforcement of the password policy on a login

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1 -Login test -AddRole serveradmin

    Add the server role "serveradmin" to the login

    .EXAMPLE
    Set-DbaLogin -SqlInstance sql1 -Login test -RemoveRole bulkadmin

    Remove the server role "bulkadmin" to the login

    .EXAMPLE
    $login = Get-DbaLogin -SqlInstance sql1 -Login test
    $login | Set-DbaLogin -Disable

    Disable the login from the pipeline

#>

    [CmdletBinding()]
    param (
        [Alias('ServerInstance', 'SqlServer')]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Login,
        [object]$Password,
        [switch]$Unlock,
        [switch]$MustChange,
        [string]$NewName,
        [switch]$Disable,
        [switch]$Enable,
        [switch]$DenyLogin,
        [switch]$GrantLogin,
        [switch]$PasswordPolicyEnforced,
        [ValidateSet('bulkadmin', 'dbcreator', 'diskadmin', 'processadmin', 'public', 'securityadmin', 'serveradmin', 'setupadmin', 'sysadmin')]
        [string[]]$AddRole,
        [ValidateSet('bulkadmin', 'dbcreator', 'diskadmin', 'processadmin', 'public', 'securityadmin', 'serveradmin', 'setupadmin', 'sysadmin')]
        [string[]]$RemoveRole,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Login[]]$InputObject,
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {
        # Check the parameters
        if ((Test-Bound -ParameterName 'SqlInstance') -and (Test-Bound -ParameterName 'Login' -Not)) {
            Stop-Function -Message 'You must specify a Login when using SqlInstance'
        }

        if ((Test-Bound -ParameterName 'NewName') -and $Login -eq $NewName) {
            Stop-Function -Message 'Login name is the same as the value in -NewName' -Target $Login -Continue
        }

        if ((Test-Bound -ParameterName 'Disable') -and (Test-Bound -ParameterName 'Enable')) {
            Stop-Function -Message 'You cannot use both -Enable and -Disable together' -Target $Login -Continue
        }

        if ((Test-Bound -ParameterName 'GrantLogin') -and (Test-Bound -ParameterName 'DenyLogin')) {
            Stop-Function -Message 'You cannot use both -GrantLogin and -DenyLogin together' -Target $Login -Continue
        }

        if (Test-bound -ParameterName 'Password') {
            switch ($Password.GetType().Name) {
                'PSCredential' { $newPassword = $Password.Password }
                'SecureString' { $newPassword = $Password }
                default {
                    Stop-Function -Message 'Password must be a PSCredential or SecureString' -Target $Login
                }
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        $allLogins = @{}
        foreach ($instance in $sqlinstance) {
            # Try connecting to the instance
            Write-Message -Message 'Connecting to $instance' -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message 'Failure' -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $allLogins[$instance.ToString()] = Get-DbaLogin -SqlInstance $server
            $InputObject += $allLogins[$instance.ToString()] | Where-Object { ($_.Name -eq $Login) -and ($_.IsSystemObject -eq $false) -and ($_.Name -notlike '##*') }
        }

        # Loop through all the logins
        foreach ($l in $InputObject) {
            $server = $l.Parent

            # Create the notes
            $notes = @()

            # Change the name
            if (Test-Bound -ParameterName 'NewName') {
                # Check if the new name doesn't already exist
                if ($allLogins[$server.Name].Name -notcontains $NewName) {
                    try {
                        $l.Rename($NewName)
                    }
                    catch {
                        $notes += "Couldn't rename login"
                        Stop-Function -Message "Something went wrong changing the name for $l" -Target $l -ErrorRecord $_ -Continue
                    }
                }
                else {
                    $notes += 'New login name already exists'
                    Write-Message -Message "New login name $NewName already exists on $instance" -Level Verbose
                }
            }

            # Change the password
            if (Test-Bound -ParameterName 'Password') {
                try {
                    $l.ChangePassword($newPassword, $Unlock, $MustChange)
                    $passwordChanged = $true
                }
                catch {
                    $notes += "Couldn't change password"
                    $passwordChanged = $false
                    Stop-Function -Message "Something went wrong changing the password for $l" -Target $l -ErrorRecord $_ -Continue
                }
            }

            # Disable the login
            if (Test-Bound -ParameterName 'Disable') {
                if ($l.IsDisabled) {
                    Write-Message -Message "Login $l is already disabled" -Level Verbose
                }
                else {
                    try {
                        $l.Disable()
                    }
                    catch {
                        $notes += "Couldn't disable login"
                        Stop-Function -Message "Something went wrong disabling $l" -Target $l -ErrorRecord $_ -Continue
                    }
                }
            }

            # Enable the login
            if (Test-Bound -ParameterName 'Enable') {
                if (-not $l.IsDisabled) {
                    Write-Message -Message "Login $l is already enabled" -Level Verbose
                }
                else {
                    try {
                        $l.Enable()
                    }
                    catch {
                        $notes += "Couldn't enable login"
                        Stop-Function -Message "Something went wrong enabling $l" -Target $l -ErrorRecord $_ -Continue
                    }
                }
            }

            # Deny access
            if (Test-Bound -ParameterName 'DenyLogin') {
                if ($l.DenyWindowsLogin) {
                    Write-Message -Message "Login $l already has login access denied" -Level Verbose
                }
                else {
                    $l.DenyWindowsLogin = $true
                }
            }

            # Grant access
            if (Test-Bound -ParameterName 'GrantLogin') {
                if (-not $l.DenyWindowsLogin) {
                    Write-Message -Message "Login $l already has login access granted" -Level Verbose
                }
                else {
                    $l.DenyWindowsLogin = $false
                }
            }

            # Enforce password policy
            if (Test-Bound -ParameterName 'PasswordPolicyEnforced') {
                if ($l.PasswordPolicyEnforced -eq $PasswordPolicyEnforced) {
                    Write-Message -Message "Login $l password policy is already set to $($l.PasswordPolicyEnforced)" -Level Verbose
                }
                else {
                    $l.PasswordPolicyEnforced = $PasswordPolicyEnforced
                }
            }

            # Add server roles to login
            if ($AddRole) {
                # Loop through each of the roles
                foreach ($role in $AddRole) {
                    try {
                        $l.AddToRole($role)
                    }
                    catch {
                        $notes += "Couldn't add role $role"
                        Stop-Function -Message "Something went wrong adding role $role to $l" -Target $l -ErrorRecord $_ -Continue
                    }
                }
            }

            # Remove server roles from login
            if ($RemoveRole) {
                # Loop through each of the roles
                foreach ($role in $RemoveRole) {
                    try {
                        $server.Roles[$role].DropMember($l.Name)
                    }
                    catch {
                        $notes += "Couldn't remove role $role"
                        Stop-Function -Message "Something went wrong removing role $role to $l" -Target $l -ErrorRecord $_ -Continue
                    }
                }
            }

            # Alter the login to make the changes
            $l.Alter()

            # Retrieve the server roles for the login
            $roles = Get-DbaRoleMember -SqlInstance $server -Database 'master' -IncludeServerLevel | Where-Object { $null -eq $_.Database -and $_.Member -eq $l.Name }

            # Check if there were any notes to include in the results
            if ($notes) {
                $notes = $notes | Get-Unique
                $notes = $notes -Join ';'
            }
            else {
                $notes = $null
            }

            Add-Member -Force -InputObject $l -MemberType 'NoteProperty' -Name 'ComputerName' -Value $server.ComputerName
            Add-Member -Force -InputObject $l -MemberType 'NoteProperty' -Name 'InstanceName' -Value $server.ServiceName
            Add-Member -Force -InputObject $l -MemberType 'NoteProperty' -Name 'SqlInstance' -Value $server.DomainInstanceName
            Add-Member -Force -InputObject $l -MemberType 'NoteProperty' -Name 'PasswordChanged' -Value $passwordChanged
            Add-Member -Force -InputObject $l -MemberType 'NoteProperty' -Name 'ServerRole' -Value ($roles.Role -join ',')
            Add-Member -Force -InputObject $l -MemberType 'NoteProperty' -Name 'Notes' -Value $notes

            # backwards compatibility: LoginName, DenyLogin
            Add-Member -Force -InputObject $l -MemberType 'NoteProperty' -Name 'LoginName' -Value $l.Name
            Add-Member -Force -InputObject $l -MemberType 'NoteProperty' -Name 'DenyLogin' -Value $l.DenyWindowsLogin

            $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'LoginName', 'DenyLogin', 'IsDisabled', 'IsLocked',
                'PasswordPolicyEnforced', 'MustChangePassword', 'PasswordChanged', 'ServerRole', 'Notes'

            Select-DefaultView -InputObject $l -Property $defaults
        }
    }
}
