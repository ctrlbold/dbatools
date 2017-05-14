﻿function Get-DbatoolsLog
{
    <#
        .SYNOPSIS
            Returns log entries for dbatools
        
        .DESCRIPTION
            Returns log entries for dbatools.
            Handy when debugging or devveloping for it. Also used when preparing a support package.
        
        .PARAMETER Errors
            Instead of log entries, the error entries will be retrieved
    
        .PARAMETER Silent
            Replaces user friendly yellow warnings with bloody red exceptions of doom!
            Use this if you want the function to throw terminating errors you want to catch.
        
        .EXAMPLE
            Get-DbatoolsLog
    
            Returns all log entries currently in memory.
    #>
    [CmdletBinding()]
    param
    (
        [switch]
        $Errors,
        
        [switch]
        $Silent
    )
    
    Begin
    {
        Write-Message -Level InternalComment -Message "Starting"
        Write-Message -Level Verbose -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
    }
    
    Process
    {
        if ($Errors) { return [Sqlcollective.Dbatools.dbaSystem.DebugHost]::GetErrors() }
        else { return [Sqlcollective.Dbatools.dbaSystem.DebugHost]::GetLog() }
    }
    
    End
    {
        Write-Message -Level InternalComment -Message "Ending"
    }
}
