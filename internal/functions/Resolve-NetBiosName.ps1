function Resolve-NetBiosName {
    <#
.SYNOPSIS
Internal function. Takes a best guess at the NetBIOS name of a server.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$SqlInstance,
        [PSCredential]$SqlCredential
    )
    # This function will be removed.
    $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    if ($server.IsClustered) {
        $server.ComputerNamePhysicalNetBIOS
    } else {
        $server.ComputerName
    }
}