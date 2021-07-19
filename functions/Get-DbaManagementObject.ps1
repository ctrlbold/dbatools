function Get-DbaManagementObject {
    <#
    .SYNOPSIS
        Gets SQL Mangaement Object versions installed on the machine.

    .DESCRIPTION
        The Get-DbaManagementObject returns an object with the Version and the
        Add-Type Load Template for each version on the server.

    .PARAMETER ComputerName
        The name of the Windows Server(s) you would like to check.

    .PARAMETER Credential
        This command uses Windows credentials. This parameter allows you to connect remotely as a different user.

    .PARAMETER VersionNumber
        This is the specific version number you are looking for. The function will look
        for that version only.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SMO
        Author: Ben Miller (@DBAduck), http://dbaduck.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaManagementObject

    .EXAMPLE
        PS C:\> Get-DbaManagementObject

        Returns all versions of SMO on the computer

    .EXAMPLE
        PS C:\> Get-DbaManagementObject -VersionNumber 13

        Returns just the version specified. If the version does not exist then it will return nothing.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]
        $Credential,
        [int]$VersionNumber,
        [switch]$EnableException
    )

    begin {
        if (-not $VersionNumber) {
            $VersionNumber = 0
        }
        $scriptBlock = {
            $VersionNumber = [int]$args[0]
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Verbose -Message "Checking currently loaded SMO version"
            $loadedversion = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Fullname -like "Microsoft.SqlServer.SMO,*" }
            if ($loadedversion) {
                $loadedversion = $loadedversion | ForEach-Object {
                    if ($_.Location -match "__") {
                        ((Split-Path (Split-Path $_.Location) -Leaf) -split "__")[0]
                    } else {
                        ((Get-ChildItem -Path $_.Location).VersionInfo.ProductVersion)
                    }
                }
            }
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Verbose -Message "Looking for included smo library"
            $localversion = [version](Get-ChildItem -Path $(Join-DbaPath $script:PSModuleRoot bin smo Microsoft.SqlServer.Smo.dll)).VersionInfo.ProductVersion

            foreach ($version in $localversion) {
                if ($VersionNumber -eq 0) {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Verbose -Message "Did not pass a version"
                    [PSCustomObject]@{
                        ComputerName = $env:COMPUTERNAME
                        Version      = $localversion
                        Loaded       = $loadedversion -contains $localversion
                        LoadTemplate = "Add-Type -Path $(Join-DbaPath $script:PSModuleRoot bin smo Microsoft.SqlServer.Smo.dll)"
                    }
                } else {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Verbose -Message "Passed version $VersionNumber, looking for that specific version"
                    if ($localversion.ToString().StartsWith("$VersionNumber.")) {
                        <# DO NOT use Write-Message as this is inside of a script block #>
                        Write-Verbose -Message "Found the Version $VersionNumber"
                        [PSCustomObject]@{
                            ComputerName = $env:COMPUTERNAME
                            Version      = $localversion
                            Loaded       = $loadedversion -contains $localversion
                            LoadTemplate = "Add-Type -Path $(Join-DbaPath $script:PSModuleRoot bin smo Microsoft.SqlServer.Smo.dll)"
                        }
                    }
                }
            }
            <# DO NOT use Write-Message as this is inside of a script block #>
            if (-not $IsLinux -and -not $IsMacOs) {
                $smolist = (Get-ChildItem -Path "$env:SystemRoot\assembly\GAC_MSIL\Microsoft.SqlServer.Smo*" -ErrorAction Stop | Sort-Object Name -Descending).Name
                $second = $false
                if (-not $smoList) {
                    $smoList = (Get-ChildItem -Path "$($env:SystemRoot)\Microsoft.NET\assembly\GAC_MSIL\Microsoft.SqlServer.Smo" -Filter "*$number.*" -ErrorAction SilentlyContinue | Where-Object FullName -match "_$number" | Sort-Object Name -Descending).Name
                    $second = $true
                }

                foreach ($version in $smolist) {
                    if ($second) {
                        $array = $version.Split("_")
                        $currentversion = $array[1]
                    } else {
                        $array = $version.Split("__")
                        $currentversion = $array[0]
                    }
                    if ($VersionNumber -eq 0) {
                        <# DO NOT use Write-Message as this is inside of a script block #>
                        Write-Verbose -Message "Did not pass a version, looking for all versions"

                        [PSCustomObject]@{
                            ComputerName = $env:COMPUTERNAME
                            Version      = $currentversion
                            Loaded       = $loadedversion -contains $currentversion
                            LoadTemplate = "Add-Type -AssemblyName `"Microsoft.SqlServer.Smo, Version=$($currentversion), Culture=neutral, PublicKeyToken=89845dcd8080cc91`""
                        }
                    } else {
                        <# DO NOT use Write-Message as this is inside of a script block #>
                        Write-Verbose -Message "Passed version $VersionNumber, looking for that specific version"
                        if ($currentversion.StartsWith("$VersionNumber.")) {
                            <# DO NOT use Write-Message as this is inside of a script block #>
                            Write-Verbose -Message "Found the Version $VersionNumber"

                            [PSCustomObject]@{
                                ComputerName = $env:COMPUTERNAME
                                Version      = $currentversion
                                Loaded       = $loadedversion -contains $currentversion
                                LoadTemplate = "Add-Type -AssemblyName `"Microsoft.SqlServer.Smo, Version=$($currentversion), Culture=neutral, PublicKeyToken=89845dcd8080cc91`""
                            }
                        }
                    }
                }
            }
        }
    }

    process {
        foreach ($computer in $ComputerName.ComputerName) {
            try {
                if ($computer -eq $env:COMPUTERNAME -or $computer -eq "localhost") {
                    Write-Message -Level Verbose -Message "Executing scriptblock against $computer"
                    Invoke-Expression -Command "$scriptBlock" -ErrorAction Stop
                } else {
                    Write-Message -Level Verbose -Message "Executing scriptblock against $computer"
                    Invoke-Command2 -ComputerName $computer -ScriptBlock $scriptBlock -Credential $Credential -ArgumentList $VersionNumber -ErrorAction Stop
                }
            } catch {
                Stop-Function -Continue -Message "Failure" -ErrorRecord $_ -Target $ComputerName
            }
        }
    }
}