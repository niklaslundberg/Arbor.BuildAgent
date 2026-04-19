<#
.SYNOPSIS
    Clones actions/runner-images at a specific ref and copies the Windows build
    scripts + toolset JSON into a local destination directory so that Packer
    provisioners (and local testing) can reference them.

.DESCRIPTION
    The actions/runner-images repository contains the exact PowerShell scripts
    that GitHub uses to provision their hosted runner VMs.  This script makes
    those scripts available locally for use in the Packer image build.

    The toolset JSON (e.g. toolset-2022.json) is copied to
    $DestinationDir/toolset.json so the install scripts find it at the path
    they expect ($env:TEMP or a well-known location).

    Internet access is required.  Tested on PowerShell 7+.

.PARAMETER Ref
    Git branch, tag or commit SHA to check out.  Use 'main' to always get the
    latest version, or pin to a release tag for reproducible builds.

.PARAMETER DestinationDir
    Local directory where the cloned scripts are written.

.PARAMETER ToolsetName
    Filename of the toolset JSON to copy (without path).  Defaults to
    toolset-2022.json which works for VS 2022-era images; update when a
    windows-2025 toolset is published in the upstream repository.

.EXAMPLE
    ./scripts/image-builder/Get-RunnerImageScripts.ps1 -Ref main

.EXAMPLE
    # Pin to a specific release
    ./scripts/image-builder/Get-RunnerImageScripts.ps1 -Ref 20250101.1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Ref = 'main',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DestinationDir = (Join-Path $PSScriptRoot '..\..\images\runner-image-scripts'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ToolsetName = 'toolset-2022.json'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$DestinationDir = [System.IO.Path]::GetFullPath($DestinationDir)
New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null

# Determine whether git is available
$useGit = [bool](Get-Command git -ErrorAction SilentlyContinue)

if ($useGit) {
    # Clone or update via git
    $repoDir = Join-Path $DestinationDir 'actions-runner-images'
    if (Test-Path -LiteralPath (Join-Path $repoDir '.git')) {
        Write-Host "Updating existing clone at $repoDir ..."
        git -C $repoDir fetch --quiet origin
        git -C $repoDir checkout --quiet $Ref
        git -C $repoDir pull  --quiet
    } else {
        Write-Host "Cloning actions/runner-images @ $Ref ..."
        git clone --quiet --depth 1 --branch $Ref `
            'https://github.com/actions/runner-images.git' $repoDir
    }

    $scriptsSource = Join-Path $repoDir 'images/windows/scripts'
    $toolsetSource = Join-Path $repoDir "images/windows/toolsets/$ToolsetName"
} else {
    # Fall back to downloading the archive via the GitHub API
    Write-Host "git not found – downloading archive from GitHub..."
    $archivePath = Join-Path $env:TEMP "runner-images-$Ref.zip"
    $extractPath = Join-Path $env:TEMP "runner-images-$Ref"

    $uri = "https://github.com/actions/runner-images/archive/$Ref.zip"
    Invoke-WebRequest -Uri $uri -OutFile $archivePath -UseBasicParsing
    if (Test-Path -LiteralPath $extractPath) {
        Remove-Item -LiteralPath $extractPath -Recurse -Force
    }
    Expand-Archive -Path $archivePath -DestinationPath $extractPath -Force

    $repoDir  = (Get-ChildItem -LiteralPath $extractPath -Directory | Select-Object -First 1).FullName
    $scriptsSource = Join-Path $repoDir 'images/windows/scripts'
    $toolsetSource = Join-Path $repoDir "images/windows/toolsets/$ToolsetName"
}

# Copy scripts directory into DestinationDir
$scriptsTarget = Join-Path $DestinationDir 'images/windows/scripts'
if (Test-Path -LiteralPath $scriptsTarget) {
    Remove-Item -LiteralPath $scriptsTarget -Recurse -Force
}
Copy-Item -LiteralPath $scriptsSource -Destination $scriptsTarget -Recurse -Force
Write-Host "Scripts copied to: $scriptsTarget"

# Copy toolset.json
if (Test-Path -LiteralPath $toolsetSource) {
    $toolsetTarget = Join-Path $DestinationDir 'toolset.json'
    Copy-Item -LiteralPath $toolsetSource -Destination $toolsetTarget -Force
    Write-Host "Toolset copied to: $toolsetTarget"
} else {
    Write-Warning "Toolset file not found: $toolsetSource"
    Write-Warning "The runner-images build scripts may fail without a valid toolset.json."
    Write-Warning "Check the upstream repository for available toolset files."
}

[pscustomobject]@{
    Ref             = $Ref
    DestinationDir  = $DestinationDir
    ScriptsDir      = $scriptsTarget
    ToolsetFile     = (Join-Path $DestinationDir 'toolset.json')
    DownloadedAt    = (Get-Date).ToUniversalTime().ToString('u')
}
