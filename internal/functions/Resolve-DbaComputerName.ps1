function Resolve-DbaComputerName {
    <#
    .SYNOPSIS
        Resolves the computer based on the ComputerName of the input DbaInstanceParameter.
    .DESCRIPTION
        Resolves the computer based on the ComputerName of the input DbaInstanceParameter.
        Designed to get the FullComputerName needed for Invoke-Command2.
        Default is to return the FullComputerName, but can also return other properties returned by Resolve-DbaNetworkName.
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [Parameter(Mandatory)]
        [DbaInstanceParameter]$ComputerName,
        [PSCredential]$Credential,
        [ValidateSet('ComputerName', 'IPAddress', 'DNSHostname', 'DNSDomain', 'Domain', 'DNSHostEntry', 'FQDN', 'FullComputerName')]
        [String]$Property = 'FullComputerName'
    )

    [String]$output = $null
    try {
        $resolved = Resolve-DbaNetworkName -ComputerName $ComputerName -Credential $Credential -EnableException
        $output = $resolved.$Property
    } catch {
        Write-Message -Level Debug -Message "First approach to resolve '$ComputerName' failed" -ErrorRecord $_
        try {
            $resolved = Resolve-DbaNetworkName -ComputerName $ComputerName -Credential $Credential -Turbo -EnableException
            $output = $resolved.$Property
        } catch {
            Write-Message -Level Debug -Message "Second approach to resolve '$ComputerName' failed" -ErrorRecord $_
            $output = $ComputerName.ComputerName
        }
    }
    Write-Message -Level Verbose -Message "Resolved '$ComputerName' to '$output'"
    $output
}