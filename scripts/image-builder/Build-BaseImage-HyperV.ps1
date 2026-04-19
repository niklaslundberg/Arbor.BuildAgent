<#
.SYNOPSIS
    End-to-end orchestration for building a Windows Server 2025 runner base
    image (VHDX) on a Hyper-V host using Packer.

.DESCRIPTION
    This script:
      1. Verifies prerequisites (Hyper-V, Packer, PowerShell 7+)
      2. Installs Packer via winget if missing
      3. Creates the autounattend ISO (no Windows ADK needed)
      4. Optionally downloads the runner-images scripts from actions/runner-images
      5. Runs 'packer init' then 'packer build' for images/hyperv/windows-2025-vs2026.pkr.hcl
      6. Reports the path of the finished VHDX

    The resulting VHDX is used as the parent (read-only base) disk for all
    ephemeral VMs created by scripts/hyperv/New-HyperVEphemeralRunner.ps1.

.PARAMETER IsoPath
    Full path or URL to the Windows Server 2025 evaluation ISO.

.PARAMETER IsoChecksum
    SHA256 checksum of the ISO.  Use 'none' to skip verification.

.PARAMETER OutputDirectory
    Directory where Packer writes the VHDX template.

.PARAMETER RunnerImagesRef
    Git branch or tag of actions/runner-images to use.  Default: main.

.PARAMETER InstallFullTools
    When $true (default) all tool-install scripts from actions/runner-images are
    executed inside the VM, matching the GitHub-hosted runner image content.
    Set to $false for a faster minimal build.

.PARAMETER SysprepBeforeExport
    When $true (default) Sysprep /generalize is run before Packer shuts down
    the VM.  Recommended for shared / multi-instance templates.

.PARAMETER WinRmPassword
    Password for the temporary packer admin account.  Must match autounattend.xml.
    Default: Packer1234! (change for production).

.PARAMETER SkipScriptDownload
    Skip downloading runner-images scripts (use cached copy in images/runner-image-scripts).

.EXAMPLE
    # Full build with all GitHub runner tools
    ./scripts/image-builder/Build-BaseImage-HyperV.ps1 `
        -IsoPath "D:\ISOs\WS2025.iso"

.EXAMPLE
    # Fast minimal build for testing
    ./scripts/image-builder/Build-BaseImage-HyperV.ps1 `
        -IsoPath "D:\ISOs\WS2025.iso" `
        -InstallFullTools $false `
        -SysprepBeforeExport $false
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$IsoPath,

    [Parameter()]
    [string]$IsoChecksum = 'none',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..\output\hyperv\windows-2025-vs2026'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RunnerImagesRef = 'main',

    [Parameter()]
    [bool]$InstallFullTools = $true,

    [Parameter()]
    [bool]$SysprepBeforeExport = $true,

    [Parameter()]
    [string]$WinRmPassword = 'Packer1234!',

    [Parameter()]
    [switch]$SkipScriptDownload
)

$ErrorActionPreference = 'Stop'

$repoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
$templatePath = Join-Path $repoRoot 'images\hyperv\windows-2025-vs2026.pkr.hcl'
$isoOut       = Join-Path $repoRoot 'images\common\autounattend.iso'

Write-Host '=== Arbor.BuildAgent - Build-BaseImage-HyperV ===' -ForegroundColor Cyan

# --- 1. Prerequisite checks -----------------------------------------------

if (-not (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell -ErrorAction SilentlyContinue)?.State -eq 'Enabled') {
    if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
        throw 'Hyper-V PowerShell module is not available. Install the Hyper-V management tools first.'
    }
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7 or later is required. Install from https://aka.ms/powershell'
}

# --- 2. Install Packer if missing -----------------------------------------

if (-not (Get-Command packer -ErrorAction SilentlyContinue)) {
    Write-Host 'Packer not found. Installing via winget...'
    winget install --id HashiCorp.Packer --accept-source-agreements --accept-package-agreements
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    if (-not (Get-Command packer -ErrorAction SilentlyContinue)) {
        throw 'Packer installation failed. Install manually from https://developer.hashicorp.com/packer/downloads'
    }
}

Write-Host "Packer version: $(packer version)"

# --- 3. Create autounattend ISO -------------------------------------------

Write-Host 'Creating autounattend ISO...'
& (Join-Path $PSScriptRoot 'New-AutounattendIso.ps1') `
    -SourceDirectory (Join-Path $repoRoot 'images\common') `
    -OutputPath $isoOut

# --- 4. Download runner-images scripts ------------------------------------

if (-not $SkipScriptDownload) {
    Write-Host "Downloading runner-images scripts (ref: $RunnerImagesRef)..."
    & (Join-Path $PSScriptRoot 'Get-RunnerImageScripts.ps1') -Ref $RunnerImagesRef
} else {
    Write-Host 'Skipping runner-images script download (SkipScriptDownload).'
}

# --- 5. packer init -------------------------------------------------------

Write-Host 'Initializing Packer plugins...'
Set-Location $repoRoot
packer init $templatePath

# --- 6. packer build -------------------------------------------------------

Write-Host 'Starting Packer build - this will take 4-8 hours for a full runner image.' -ForegroundColor Yellow

$env:PACKER_LOG = '1'
$env:PACKER_LOG_PATH = Join-Path $OutputDirectory 'packer.log'

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$buildArgs = @(
    'build',
    "-var=iso_url=$IsoPath",
    "-var=iso_checksum=$IsoChecksum",
    "-var=autounattend_iso=$isoOut",
    "-var=output_directory=$OutputDirectory",
    "-var=runner_images_ref=$RunnerImagesRef",
    "-var=install_full_runner_image_tools=$($InstallFullTools.ToString().ToLower())",
    "-var=sysprep_before_export=$($SysprepBeforeExport.ToString().ToLower())",
    "-var=winrm_password=$WinRmPassword",
    $templatePath
)

packer @buildArgs

# --- 7. Report result -------------------------------------------------------

$vhdx = Get-ChildItem -Path $OutputDirectory -Filter '*.vhdx' -Recurse |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($vhdx) {
    $sizeMB = [math]::Round($vhdx.Length / 1MB, 0)
    Write-Host "=== Build complete ===" -ForegroundColor Green
    Write-Host "Base image VHDX : $($vhdx.FullName)  ($sizeMB MB)"
    Write-Host ''
    Write-Host "Next step: use this VHDX as -ParentVhdxPath with:"
    Write-Host "  ./scripts/hyperv/New-HyperVEphemeralRunner.ps1 -ParentVhdxPath '$($vhdx.FullName)' ..."
} else {
    Write-Warning 'Build finished but no VHDX was found in the output directory.'
    Write-Warning "Check the Packer log: $($env:PACKER_LOG_PATH)"
}
