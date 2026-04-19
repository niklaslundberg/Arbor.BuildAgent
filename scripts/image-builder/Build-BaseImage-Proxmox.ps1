<#
.SYNOPSIS
    End-to-end orchestration for building a Windows Server 2025 runner base
    image (Proxmox template) using Packer.

.DESCRIPTION
    This script:
      1. Verifies prerequisites (Packer, PowerShell 7+, network access to Proxmox)
      2. Installs Packer via winget if missing
      3. Creates the autounattend ISO and uploads it to Proxmox ISO storage
      4. Optionally downloads runner-images scripts
      5. Runs 'packer init' then 'packer build' for images/proxmox/windows2025.pkr.hcl
      6. Reports the resulting Proxmox template VMID

    The resulting Proxmox template is used as the clone source for all
    ephemeral VMs created by scripts/proxmox/New-ProxmoxEphemeralRunner.ps1.

.PARAMETER ProxmoxApiBaseUrl
    Base URL of the Proxmox REST API (e.g. https://pve01:8006/api2/json).

.PARAMETER Node
    Proxmox node name where the build VM will be created.

.PARAMETER TokenId
    Proxmox API token ID in the format user@realm!tokenname.

.PARAMETER TokenSecret
    Proxmox API token secret.

.PARAMETER WindowsIsoFile
    Proxmox storage reference of the Windows Server 2025 ISO
    (e.g. local:iso/WS2025.iso).  The ISO must already be uploaded to Proxmox.

.PARAMETER VirtioIsoFile
    Proxmox storage reference of the VirtIO drivers ISO.
    Download from: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso

.PARAMETER IsoStorage
    Proxmox storage ID used for ISO upload.  Default: local.

.PARAMETER DiskStorage
    Proxmox storage ID for the build VM disk.  Default: local-lvm.

.PARAMETER BuildVmId
    VMID for the build/template VM.  Must not conflict with existing VMs.

.PARAMETER RunnerImagesRef
    Git branch or tag of actions/runner-images to use.  Default: main.

.PARAMETER InstallFullTools
    Run all actions/runner-images tool install scripts.  Default: $true.

.PARAMETER SysprepBeforeExport
    Run Sysprep before converting to a Proxmox template.  Default: $true.

.PARAMETER WinRmPassword
    Temporary packer account password.  Must match autounattend.xml.

.PARAMETER SkipIsoUpload
    Skip uploading the autounattend ISO to Proxmox (if already present).

.PARAMETER SkipScriptDownload
    Skip downloading runner-images scripts.

.PARAMETER InsecureSkipTlsVerify
    Skip TLS certificate verification for Proxmox API (for self-signed certs).

.EXAMPLE
    ./scripts/image-builder/Build-BaseImage-Proxmox.ps1 `
        -ProxmoxApiBaseUrl "https://pve01:8006/api2/json" `
        -Node pve01 `
        -TokenId "packer@pve!packer" `
        -TokenSecret "<secret>" `
        -WindowsIsoFile "local:iso/WS2025.iso"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ProxmoxApiBaseUrl,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Node,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TokenId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TokenSecret,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$WindowsIsoFile,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$VirtioIsoFile = 'local:iso/virtio-win.iso',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$IsoStorage = 'local',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DiskStorage = 'local-lvm',

    [Parameter()]
    [int]$BuildVmId = 9000,

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
    [switch]$SkipIsoUpload,

    [Parameter()]
    [switch]$SkipScriptDownload,

    [Parameter()]
    [switch]$InsecureSkipTlsVerify
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$repoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
$templatePath = Join-Path $repoRoot 'images\proxmox\windows2025.pkr.hcl'
$isoOut       = Join-Path $repoRoot 'images\common\autounattend.iso'

Write-Host '=== Arbor.BuildAgent – Build-BaseImage-Proxmox ===' -ForegroundColor Cyan

# --- 1. Prerequisite checks -----------------------------------------------

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

# --- 3. Create autounattend ISO and upload to Proxmox ----------------------

Write-Host 'Creating autounattend ISO...'
& (Join-Path $PSScriptRoot 'New-AutounattendIso.ps1') `
    -SourceDirectory (Join-Path $repoRoot 'images\common') `
    -OutputPath $isoOut

if (-not $SkipIsoUpload) {
    Write-Host "Uploading autounattend ISO to Proxmox storage '$IsoStorage'..."
    $headers = @{ Authorization = "PVEAPIToken=$TokenId=$TokenSecret" }

    $uploadUri = "$ProxmoxApiBaseUrl/nodes/$Node/storage/$IsoStorage/upload"

    $boundary  = [System.Guid]::NewGuid().ToString()
    $isoBytes  = [System.IO.File]::ReadAllBytes($isoOut)
    $isoName   = 'autounattend-ws2025.iso'

    # Build multipart body
    $bodyLines = @(
        "--$boundary",
        "Content-Disposition: form-data; name=`"content`"",
        '',
        'iso',
        "--$boundary",
        "Content-Disposition: form-data; name=`"filename`"; filename=`"$isoName`"",
        'Content-Type: application/octet-stream',
        '',
        ''
    )
    $bodyPrefix = [System.Text.Encoding]::UTF8.GetBytes(($bodyLines -join "`r`n"))
    $bodySuffix = [System.Text.Encoding]::UTF8.GetBytes("`r`n--$boundary--`r`n")

    $body = $bodyPrefix + $isoBytes + $bodySuffix

    if ($InsecureSkipTlsVerify) {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }

    try {
        Invoke-RestMethod -Method Post -Uri $uploadUri -Headers $headers `
            -ContentType "multipart/form-data; boundary=$boundary" `
            -Body $body -ErrorAction Stop | Out-Null
        Write-Host "Upload complete: ${IsoStorage}:iso/$isoName"
    } catch {
        Write-Warning "ISO upload failed: $($_.Exception.Message)"
        Write-Warning "You can upload manually and re-run with -SkipIsoUpload."
    }
} else {
    Write-Host 'Skipping ISO upload (SkipIsoUpload).'
}

# --- 4. Download runner-images scripts ------------------------------------

if (-not $SkipScriptDownload) {
    Write-Host "Downloading runner-images scripts (ref: $RunnerImagesRef)..."
    & (Join-Path $PSScriptRoot 'Get-RunnerImageScripts.ps1') -Ref $RunnerImagesRef
} else {
    Write-Host 'Skipping runner-images script download (SkipScriptDownload).'
}

# --- 5. packer init -------------------------------------------------------

Write-Host 'Initialising Packer plugins...'
Set-Location $repoRoot
packer init $templatePath

# --- 6. packer build -------------------------------------------------------

Write-Host 'Starting Packer build – this will take 4-8 hours for a full runner image.' -ForegroundColor Yellow

$logDir  = Join-Path $repoRoot 'output\proxmox\logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$env:PACKER_LOG      = '1'
$env:PACKER_LOG_PATH = Join-Path $logDir 'packer-proxmox.log'

$tlsStr = $InsecureSkipTlsVerify.IsPresent.ToString().ToLower()

$buildArgs = @(
    'build',
    "-var=proxmox_url=$ProxmoxApiBaseUrl",
    "-var=proxmox_node=$Node",
    "-var=proxmox_token_id=$TokenId",
    "-var=proxmox_token_secret=$TokenSecret",
    "-var=proxmox_insecure_skip_tls_verify=$tlsStr",
    "-var=iso_file=$WindowsIsoFile",
    "-var=virtio_iso_file=$VirtioIsoFile",
    "-var=iso_storage=$IsoStorage",
    "-var=disk_storage=$DiskStorage",
    "-var=vm_id=$BuildVmId",
    "-var=runner_images_ref=$RunnerImagesRef",
    "-var=install_full_runner_image_tools=$($InstallFullTools.ToString().ToLower())",
    "-var=sysprep_before_export=$($SysprepBeforeExport.ToString().ToLower())",
    "-var=winrm_password=$WinRmPassword",
    $templatePath
)

packer @buildArgs

# --- 7. Report result -------------------------------------------------------

Write-Host ''
Write-Host '=== Build complete ===' -ForegroundColor Green
Write-Host "Proxmox template VMID  : $BuildVmId"
Write-Host "Proxmox node           : $Node"
Write-Host ''
Write-Host 'Next step: use this template with:'
Write-Host "  ./scripts/proxmox/New-ProxmoxEphemeralRunner.ps1 -TemplateVmId $BuildVmId ..."
Write-Host ''
Write-Host "Packer log: $($env:PACKER_LOG_PATH)"
