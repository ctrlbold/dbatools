function New-DbaAzAccessToken {
    <#
    .SYNOPSIS
        Simplifies the generation of Azure oauth2 tokens.

    .DESCRIPTION
        Generates an oauth2 access token. Currently supports Managed Identities and Service Principals.

    .PARAMETER Type
        The type of request: ManagedIdentity or ServicePrincipal.

    .PARAMETER Subtype
        The subtype. Auto-completes. Currently supports AzureSqlDb and Management.

        Read more here: https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/tutorial-windows-vm-access-sql

    .PARAMETER Config
        The hashtable or json configuration.

    .PARAMETER Credential
        When using the ServicePrincipal type, a Credential is required. The username is the App ID and Password is the App Password

        https://docs.microsoft.com/en-us/azure/active-directory/user-help/multi-factor-authentication-end-user-app-passwords

    .PARAMETER Tenant
        hen using the ServicePrincipal type, a tenant name or ID is required. This field works with both.

    .PARAMETER EnableException
        By default in most of our commands, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This command, however, gifts you  with "sea of red" exceptions, by default, because it is useful for advanced scripting.

        Using this switch turns our "nice by default" feature on which makes errors into pretty warnings.

    .NOTES
        Tags: Connect, Connection, Azure
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaAzAccessToken

    .EXAMPLE
        PS C:\> New-DbaAzAccessToken -Type ManagedIdentity

        Returns a plain-text token for Managed Identities for SQL Azure Db.

    .EXAMPLE
        PS C:\> $token = New-DbaAzAccessToken -Type ManagedIdentity -Subtype AzureSqlDb
        PS C:\> $server = Connect-DbaInstance -SqlInstance myserver.database.windows.net -Database mydb -AccessToken $token -DisableException

        Generates a token then uses it to connect to Azure SQL DB then connects to an Azure SQL Db

    .EXAMPLE
        PS C:\> $token = New-DbaAzAccessToken -Type ServicePrincipal -Tenant whatup.onmicrosoft.com -Credential ee590f55-9b2b-55d4-8bca-38ab123db670
        PS C:\> $server = Connect-DbaInstance -SqlInstance myserver.database.windows.net -Database mydb -AccessToken $token -DisableException
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Generates a token then uses it to connect to Azure SQL DB then connects to an Azure SQL Db.
        Once the connection is made, it is used to perform a test query.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [ValidateSet('ManagedIdentity', 'ServicePrincipal')]
        [string]$Type,
        [ValidateSet('AzureSqlDb', 'Management')]
        [string]$Subtype = "AzureSqlDb",
        [object]$Config,
        [pscredential]$Credential,
        [string]$Tenant,
        [switch]$EnableException
    )
    begin {
        if ($Type -eq "ServicePrincipal") {
            if (-not $Credential -and -not $Tenant) {
                Stop-Function -Message "You must specify a Credential and Tenant when using ServicePrincipal"
                return
            }
        }

        if ($Type -eq "ManagedIdentity") {
            switch ($Subtype) {
                AzureSqlDb {
                    $Config = @{
                        Version  = '2018-04-02'
                        Resource = 'https://database.windows.net/'
                    }
                }
                Management {
                    $Config = @{
                        Version  = '2018-04-02'
                        Resource = 'https://management.windows.net/'
                    }
                }
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        try {
            switch ($Type) {
                ManagedIdentity {
                    $version = $Config.Version
                    $resource = $Config.Resource
                    $params = @{
                        Uri     = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=$version&resource=$resource"
                        Method  = "GET"
                        Headers = @{ Metadata = "true" }
                    }
                    $response = Invoke-TlsWebRequest @params -UseBasicParsing -ErrorAction Stop
                    $token = ($response.Content | ConvertFrom-Json).access_token
                }
                ServicePrincipal {
                    if ((Get-CimInstance -ClassName Win32_OperatingSystem).Version -lt 8 -or $script:core) {
                        Stop-Function -Message "ServicePrincipal currently unsupported in Core and older versions of Windows"
                        return
                    }

                    Add-Type -Path (Resolve-Path -Path "$script:PSModuleRoot\bin\smo\Microsoft.IdentityModel.Clients.ActiveDirectory.dll")
                    Add-Type -Path (Resolve-Path -Path "$script:PSModuleRoot\bin\smo\Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll")

                    # thanks to Jose M Jurado - MSFT for this code
                    # https://blogs.msdn.microsoft.com/azuresqldbsupport/2018/05/10/lesson-learned-49-does-azure-sql-database-support-azure-active-directory-connections-using-service-principals/
                    $cred = [Microsoft.IdentityModel.Clients.ActiveDirectory.ClientCredential]::New($Credential.UserName, $Credential.GetNetworkCredential().Password)
                    $context = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext]::New("https://login.windows.net/$Tenant")
                    $result = $context.AcquireTokenAsync("https://database.windows.net/", $cred)

                    if ($result.Result.AccessToken) {
                        $token = $result.Result.AccessToken
                    } else {
                        throw ($result.Exception | ConvertTo-Json | ConvertFrom-Json).InnerException.Message
                    }
                }
            }
            $script:aztokens += {
                SqlInstance = $null
                PSBoundParams = $PSBoundParameters
                Token = $token
            }

            return $token
        } catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
        }
    }
}