#ValidationTags#CodeStyle,Messaging,FlowControl,Pipeline#
function Install-DbaSQLWATCH {
    <#
        .SYNOPSIS
            Installs or updates SQLWATCH.

        .DESCRIPTION
            Downloads, extracts and installs or updates SQLWATCH.
            https://sqlwatch.io/

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            Specifies the database to install SQLWATCH into.

        .PARAMETER Branch
            Specifies an alternate branch of SQLWATCH to install. (master or dev)

        .PARAMETER LocalFile
            Specifies the path to a local file to install SQLWATCH from. This *should* be the zipfile as distributed by the maintainers.
            If this parameter is not specified, the latest version will be downloaded and installed from https://github.com/marcingminski/sqlwatch

        .PARAMETER Force
            If this switch is enabled, SQLWATCH will be downloaded from the internet even if previously cached.

        .PARAMETER Confirm
            Prompts to confirm actions

        .PARAMETER WhatIf
            Shows what would happen if the command were to run. No actions are actually performed.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: SQLWATCH, marcingminski
            Author: marcingminski ()
            Website: https://sqlwatch.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Install-DbaSQLWATCH

        .EXAMPLE
            Install-DbaSQLWATCH -SqlInstance server1 -Database master

            Logs into server1 with Windows authentication and then installs SQLWATCH in the master database.

        .EXAMPLE
            Install-DbaSQLWATCH -SqlInstance server1\instance1 -Database DBA

            Logs into server1\instance1 with Windows authentication and then installs SQLWATCH in the DBA database.

        .EXAMPLE
            Install-DbaSQLWATCH -SqlInstance server1\instance1 -Database master -SqlCredential $cred

            Logs into server1\instance1 with SQL authentication and then installs SQLWATCH in the master database.

        .EXAMPLE
            Install-DbaSQLWATCH -SqlInstance sql2016\standardrtm, sql2016\sqlexpress, sql2014

            Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs SQLWATCH in the master database.

        .EXAMPLE
            $servers = "sql2016\standardrtm", "sql2016\sqlexpress", "sql2014"
            $servers | Install-DbaSQLWATCH

            Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs SQLWATCH in the master database.

        .EXAMPLE
            Install-DbaSQLWATCH -SqlInstance sql2016 -Branch development

            Installs the dev branch version of SQLWATCH in the master database on sql2016 instance.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet('master', 'development')]
        [string]$Branch = "master",
        [object]$Database = "master",
        [string]$LocalFile,
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {

        $DbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"        
        $tempFolder = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
        $zipfile = "$tempFolder\SQLWATCH.zip"
        
        $oldSslSettings = [System.Net.ServicePointManager]::SecurityProtocol
        [System.Net.ServicePointManager]::SecurityProtocol = "Tls12"

        if ($LocalFile -eq $null -or $LocalFile.Length -eq 0) {

            if ($PSCmdlet.ShouldProcess($env:computername, "Downloading latest release from GitHub")) {
        
                # query the releases to find the latest, check and see if its cached
                $ReleasesUrl = "https://api.github.com/repos/marcingminski/sqlwatch/releases"
                $DownloadBase = "https://github.com/marcingminski/sqlwatch/releases/download/"
            
                Write-Message -Level Verbose -Message "Checking GitHub for the latest release."
                $LatestReleaseUrl = (Invoke-WebRequest -UseBasicParsing -Uri $ReleasesUrl | ConvertFrom-Json)[0].assets[0].browser_download_url
            
                Write-Message -Level VeryVerbose -Message "Latest release is available at $LatestReleaseUrl"
                $LocallyCachedZip = Join-Path -Path $DbatoolsData -ChildPath $($LatestReleaseUrl -replace $DownloadBase, '');
            
                # if local cached copy exists, use it, otherwise download a new one
                if (-not $Force) {
                
                    # download from github
                    Write-Message -Level Verbose "Downloading $LatestReleaseUrl"
                    try {
                        Invoke-WebRequest $LatestReleaseUrl -OutFile $zipfile -ErrorAction Stop -UseBasicParsing
                    }
                    catch {
                        #try with default proxy and usersettings
                        (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                        Invoke-WebRequest $LatestReleaseUrl -OutFile $zipfile -ErrorAction Stop -UseBasicParsing
                    }

                    # copy the file from temp to local cache
                    Write-Message -Level Verbose "Copying $zipfile to $LocallyCachedZip"
                    try {
                        New-Item -Path $LocallyCachedZip -ItemType File -Force | Out-Null
                        Copy-Item -Path $zipfile -Destination $LocallyCachedZip -Force
                    }
                    catch {
                        # should we stop the function if the file copy fails?
                    }
                }
            }
        }
        else {

            # $LocalFile was passed, so use it
            if ($PSCmdlet.ShouldProcess($env:computername, "Copying local file to temp directory")) {
                
                if ($LocalFile.EndsWith("zip")) {
                    $LocallyCachedZip = $zipfile
                    Copy-Item -Path $LocalFile -Destination $LocallyCachedZip -Force
                }
                else {
                    $LocallyCachedZip = (Join-Path -path $tempFolder -childpath "SQLWATCH.zip")
                    Copy-Item -Path $LocalFile -Destination $LocallyCachedZip -Force
                }
            }
        }

        # expand the zip file
        if ($PSCmdlet.ShouldProcess($env:computername, "Unpacking zipfile")) {

            Write-Message -Level VeryVerbose "Unblocking $LocallyCachedZip"
            Unblock-File $LocallyCachedZip -ErrorAction SilentlyContinue
            $LocalCacheFolder = Split-Path $LocallyCachedZip -Parent

            Write-Message -Level Verbose "Extracting $LocallyCachedZip to $LocalCacheFolder"
            if (Get-Command -ErrorAction SilentlyContinue -Name "Expand-Archive") {
                try {
                    Expand-Archive -Path $LocallyCachedZip -DestinationPath $LocalCacheFolder -Force
                }
                catch {
                    Stop-Function -Message "Unable to extract $LocallyCachedZip. Archive may not be valid." -ErrorRecord $_
                    return
                }
            }
            else {
                # Keep it backwards compatible
                $shell = New-Object -ComObject Shell.Application
                $zipPackage = $shell.NameSpace($LocallyCachedZip)
                $destinationFolder = $shell.NameSpace($LocalCacheFolder)
                Get-ChildItem "$LocalCacheFolder\SQLWATCH.zip" | Remove-Item
                $destinationFolder.CopyHere($zipPackage.Items())
            }

            Write-Message -Level VeryVerbose "Deleting $LocallyCachedZip"
            Remove-Item -Path $LocallyCachedZip
        }

        [System.Net.ServicePointManager]::SecurityProtocol = $oldSslSettings
        
    }


    process {
        if (Test-FunctionInterrupt) {
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                #Write-Message -Level Verbose -Message "Connecting to $instance."
                Write-Message -Level VeryVerbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure." -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            #Write-Message -Level Verbose -Message "Starting installing/updating SQLWATCH in $database on $instance."
            Write-Message -Level Verbose -Message "Starting installing/updating SQLWATCH in $database on $instance."

            try {

                # create a publish profile and publish DACPAC
                $DacPacPath = Get-ChildItem -Filter "SQLWATCH.dacpac" -Path $LocalCacheFolder -Recurse | Select-Object -ExpandProperty FullName
                $PublishOptions = @{
                    RegisterDataTierApplication = $true
                }
                $DacProfile = New-DbaDacProfile -SqlInstance $server -Database $Database -Path $LocalCacheFolder -PublishOptions $PublishOptions | Select-Object -ExpandProperty FileName
                $PublishResults = Publish-DbaDacPackage -SqlInstance $server -Database $Database -Path $DacPacPath -PublishXml $DacProfile
                
                # parse results
                $parens = Select-String -InputObject $PublishResults.Result -Pattern "\(([^\)]+)\)" -AllMatches
                if ($parens.matches) {
                    $ExtractedResult = $parens.matches | Select-Object -Last 1 #| ForEach-Object { $_.value -replace '(', '' -replace ')', '' }
                }                
                [PSCustomObject]@{
                    ComputerName         = $PublishResults.ComputerName
                    InstanceName         = $PublishResults.InstanceName
                    SqlInstance          = $PublishResults.SqlInstance
                    Database             = $PublishResults.Database
                    Dacpac               = $PublishResults.Dacpac
                    PublishXml           = $PublishResults.PublishXml
                    Result               = $ExtractedResult
                    FullResult           = $PublishResults.Result
                    DeployOptions        = $PublishResults.DeployOptions
                    SqlCmdVariableValues = $PublishResults.SqlCmdVariableValues
                } | Select-DefaultView -ExcludeProperty Dacpac, PublishXml, FullResult, DeployOptions, SqlCmdVariableValues
            }
            catch {
                Stop-Function -Message "DACPAC failed to publish to $database on $instance." -ErrorRecord $_ -Target $instance -Continue
            }

            Write-PSFMessage -Level Verbose -Message "Finished installing/updating SQLWATCH in $database on $instance."
            #notify user of location to PowerBI file
            #$pbitLocation = Get-ChildItem $tempFolder -Recurse -include *.pbit | Select-Object -ExpandProperty Directory -Unique
            #Write-PSFMessage -Level Output -Message "SQLWATCH installed successfully. Power BI dashboard files can be found at $($pbitLocation.FullName)"
        }
    }

    end {}
}