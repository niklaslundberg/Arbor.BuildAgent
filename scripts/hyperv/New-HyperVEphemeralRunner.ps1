[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$VmName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ParentVhdxPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TempDiskDirectory,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SwitchName = 'Default Switch',

    [Parameter()]
    [ValidateRange(2GB, 64GB)]
    [Int64]$StartupMemoryBytes = 8GB,

    [Parameter()]
    [ValidateRange(1, 32)]
    [int]$CpuCount = 4,

    [Parameter()]
    [string[]]$CustomizationScriptPaths = @()
)

if (-not (Get-Command New-VM -ErrorAction SilentlyContinue)) {
    throw 'Hyper-V PowerShell module is not available on this host.'
}

if (-not (Test-Path -LiteralPath $ParentVhdxPath)) {
    throw "ParentVhdxPath '$ParentVhdxPath' does not exist."
}

New-Item -ItemType Directory -Path $TempDiskDirectory -Force | Out-Null
$tempVhdx = Join-Path $TempDiskDirectory ("$VmName-temp.vhdx")
$vmCreated = $false

try {
    New-VHD -Path $tempVhdx -ParentPath $ParentVhdxPath -Differencing -ErrorAction Stop | Out-Null

    New-VM -Name $VmName -Generation 2 -MemoryStartupBytes $StartupMemoryBytes -VHDPath $tempVhdx -SwitchName $SwitchName -ErrorAction Stop | Out-Null
    $vmCreated = $true
    Set-VMProcessor -VMName $VmName -Count $CpuCount -ExposeVirtualizationExtensions $true -ErrorAction Stop
    Set-VM -Name $VmName -AutomaticStopAction ShutDown -ErrorAction Stop | Out-Null
    Start-VM -Name $VmName -ErrorAction Stop | Out-Null
} catch {
    if ($vmCreated -and (Get-VM -Name $VmName -ErrorAction SilentlyContinue)) {
        Remove-VM -Name $VmName -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $tempVhdx) {
        Remove-Item -LiteralPath $tempVhdx -Force -ErrorAction SilentlyContinue
    }

    throw
}

[pscustomobject]@{
    VmName                   = $VmName
    TempDiskPath             = $tempVhdx
    NestedVirtualization     = $true
    CustomizationScriptCount = $CustomizationScriptPaths.Count
    NextStep                 = 'Run guest bootstrap to execute customization scripts and register runner.'
}
