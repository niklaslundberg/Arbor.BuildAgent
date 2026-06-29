<#
.SYNOPSIS
    Creates a small bootable ISO containing autounattend.xml and winrm-setup.ps1.
    No Windows ADK or external tools required – uses the built-in IMAPI2 COM object.

.DESCRIPTION
    Windows Setup (winsetup.exe) searches all attached removable media for an
    autounattend.xml file at the root.  This script packages the answer file and
    the WinRM-setup helper into a small ISO that Packer attaches as a secondary
    DVD drive (secondary_iso_images / additional_iso_files).

.PARAMETER SourceDirectory
    Directory that contains autounattend.xml (and optionally winrm-setup.ps1).
    Defaults to images/common relative to the repository root.

.PARAMETER OutputPath
    Full path to the ISO file to create.
    Defaults to images/common/autounattend.iso in the repository root.

.EXAMPLE
    ./scripts/image-builder/New-AutounattendIso.ps1

.EXAMPLE
    ./scripts/image-builder/New-AutounattendIso.ps1 `
        -SourceDirectory  C:\myrepo\images\common `
        -OutputPath       C:\ISOs\autounattend-ws2025.iso
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SourceDirectory = (Join-Path $PSScriptRoot '..\..\images\common'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\..\images\common\autounattend.iso')
)

$ErrorActionPreference = 'Stop'

$SourceDirectory = (Resolve-Path -LiteralPath $SourceDirectory).Path
$OutputPath      = [System.IO.Path]::GetFullPath($OutputPath)

if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory 'autounattend.xml'))) {
    throw "autounattend.xml not found in '$SourceDirectory'."
}

Write-Host "Source directory : $SourceDirectory"
Write-Host "Output ISO path  : $OutputPath"

# Create the output directory if it does not exist
$outDir = Split-Path -Parent $OutputPath
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

# Use IMAPI2FS (built into Windows Vista+) to create a bootable UDF/ISO9660 image
try {
    $fsi = New-Object -ComObject 'IMAPI2FS.MsftFileSystemImage'
} catch {
    throw "IMAPI2FS COM object not available. This script must run on Windows. Error: $($_.Exception.Message)"
}

# UDF + Joliet (ISO 9660 Level 2) so the image is readable by both Windows PE and regular Windows
$fsi.FileSystemsToCreate = 4   # FsiFileSystemUdf
$fsi.FreeMediaBlocks     = 0   # Recalculate automatically
$fsi.VolumeName          = 'AUTOUNATTEND'

# Add all files from the source directory to the root of the image
Get-ChildItem -LiteralPath $SourceDirectory -File | ForEach-Object {
    Write-Host "  Adding: $($_.Name)"
    $fsi.Root.AddTree($_.FullName, $false)
}

# Finalize image and stream to disk
$resultImage = $fsi.CreateResultImage()
$isoStream   = $resultImage.ImageStream

$adoStream = New-Object -ComObject 'ADODB.Stream'
$adoStream.Type = 1   # adTypeBinary
$adoStream.Open()
$adoStream.CopyFrom($isoStream)
$adoStream.SaveToFile($OutputPath, 2)  # adSaveCreateOverWrite
$adoStream.Close()

[Runtime.InteropServices.Marshal]::ReleaseComObject($adoStream)  | Out-Null
[Runtime.InteropServices.Marshal]::ReleaseComObject($isoStream)  | Out-Null
[Runtime.InteropServices.Marshal]::ReleaseComObject($resultImage)| Out-Null
[Runtime.InteropServices.Marshal]::ReleaseComObject($fsi)        | Out-Null

$size = (Get-Item -LiteralPath $OutputPath).Length / 1KB
Write-Host "ISO created: $OutputPath  ($([math]::Round($size, 1)) KB)"

[pscustomobject]@{
    IsoPath     = $OutputPath
    SizeKB      = [math]::Round($size, 1)
    SourceFiles = (Get-ChildItem -LiteralPath $SourceDirectory -File).Name
}
