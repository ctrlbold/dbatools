[CmdletBinding()]
param (
    [string]$Path,
    [switch]$Beta
)

function Write-LocalMessage {
    [CmdletBinding()]
    param (
        [string]$Message
    )

    if (Test-Path function:Write-Message) { Write-Message -Level Output -Message $Message }
    else { Write-Host $Message }
}

try {
    Update-Module dbatools -Erroraction Stop
    Write-LocalMessage -Message "Updated using the PowerShell Gallery"
    return
}
catch {
    Write-LocalMessage -Message "dbatools was not installed by the PowerShell Gallery, continuing with web install."
}

$dbatools_copydllmode = $true
$module = Import-Module -Name dbatools -ErrorAction SilentlyContinue
$localpath = $module.ModuleBase

if ($null -eq $localpath) {
    $localpath = "$HOME\Documents\WindowsPowerShell\Modules\dbatools"
}
else {
    Write-LocalMessage -Message "Updating current install"
}

try {
    if (-not $path) {
        if ($PSCommandPath.Length -gt 0) {
            $path = Split-Path $PSCommandPath
            if ($path -match "github") {
                Write-LocalMessage -Message "Looks like this installer is run from your GitHub Repo, defaulting to psmodulepath"
                $path = $localpath
            }
        }
        else {
            $path = $localpath
        }
    }
}
catch {
    $path = $localpath
}

if (-not $path -or (Test-Path -Path "$path\.git")) {
    $path = $localpath
}

If ($lib = [appdomain]::CurrentDomain.GetAssemblies() | Where-Object FullName -like "dbatools, *") {
    if ($lib.Location -like "$Path\*") {
        Write-LocalMessage @"
We have detected dbatools to be already imported from
$path
In a manner that prevents us from updating it, since dll files have been locked.
In order to ensure a valid update, please:
- Close all consoles that have dbatools imported (Remove-Module dbatools is NOT enough)
- Start a new PowerShell console
- Run '`$dbatools_copydllmode = `$true' (without the single-quotes)
- Import dbatools and run Update-Dbatools
If done in this order, the binaries will be copied to another location before import, allowing for a save update.
"@
        return
    }
}

Write-LocalMessage -Message "Installing module to $path"

if (!(Test-Path -Path $path)) {
    try {
        Write-LocalMessage -Message "Creating directory: $path"
        New-Item -Path $path -ItemType Directory | Out-Null
    }
    catch {
        throw "Can't create $Path. You may need to Run as Administrator: $_"
    }
}

if ($beta) {
    $url = 'https://dbatools.io/devzip'
    $branch = "development"
}
else {
    $url = 'https://dbatools.io/zip'
    $branch = "master"
}

$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
$zipfile = "$temp\dbatools.zip"

Write-LocalMessage -Message "Downloading archive from github"
try {
    (New-Object System.Net.WebClient).DownloadFile($url, $zipfile)
}
catch {
    #try with default proxy and usersettings
    Write-LocalMessage -Message "Probably using a proxy for internet access, trying default proxy settings"
    $wc = (New-Object System.Net.WebClient)
    $wc.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
    $wc.DownloadFile($url, $zipfile)
}

# Unblock if there's a block
Unblock-File $zipfile -ErrorAction SilentlyContinue

Write-LocalMessage -Message "Unzipping"

# Keep it backwards compatible
Remove-Item -ErrorAction SilentlyContinue "$temp\dbatools-$branch" -Recurse -Force
Remove-Item -ErrorAction SilentlyContinue "$temp\dbatools-old" -Recurse -Force
$null = New-Item "$temp\dbatools-old" -ItemType Directory
$shell = New-Object -ComObject Shell.Application
$zipPackage = $shell.NameSpace($zipfile)
$destinationFolder = $shell.NameSpace($temp)
$destinationFolder.CopyHere($zipPackage.Items())

Write-LocalMessage -Message "Applying Update"
Write-LocalMessage -Message "1) Backing up previous installation"
Copy-Item -Path "$Path\*" -Destination "$temp\dbatools-old" -ErrorAction Stop
try {
    Write-LocalMessage -Message "2) Cleaning up installation directory"
    Remove-Item "$Path\*" -Recurse -Force -ErrorAction Stop
}
catch {
    Write-LocalMessage -Message @"
Failed to clean up installation directory, rolling back update.
This usually has one of two causes:
- Insufficient privileges (need to run as admin)
- A file is locked - generally a dll file from having the module imported in some process.

You can run the following line before importing dbatools to prevent file locking:
`$dbatools_copydllmode = `$true
But it increases the time needed to import the module, so we only recommend using it for updates.

Exception:
$_
"@
    Copy-Item -Path "$temp\dbatools-old\*" -Destination $path -ErrorAction Ignore -Recurse
    Remove-Item "$temp\dbatools-old" -Recurse -Force
    return
}
Write-LocalMessage -Message "3) Setting up current version"
Move-Item -Path "$temp\dbatools-$branch\*" -Destination $path -ErrorAction SilentlyContinue -Force
Remove-Item -Path "$temp\dbatools-$branch" -Recurse -Force
Remove-Item "$temp\dbatools-old" -Recurse -Force
Remove-Item -Path $zipfile -Recurse -Force

Write-LocalMessage -Message "Done! Please report any bugs to dbatools.io/issues or clemaire@gmail.com."
if (Get-Module dbatools) {
    Write-LocalMessage -Message @"

Please restart PowerShell before working with dbatools.
"@
}
else {
    Import-Module "$path\dbatools.psd1" -Force
    Write-LocalMessage @"

dbatools v $((Get-Module dbatools).Version)
# Commands available: $((Get-Command -Module dbatools -CommandType Function | Measure-Object).Count)

"@
}
Write-LocalMessage -Message "`n`nIf you experience any function missing errors after update, please restart PowerShell or reload your profile."