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

New-VHD -Path $tempVhdx -ParentPath $ParentVhdxPath -Differencing | Out-Null

New-VM -Name $VmName -Generation 2 -MemoryStartupBytes $StartupMemoryBytes -VHDPath $tempVhdx -SwitchName $SwitchName | Out-Null
Set-VMProcessor -VMName $VmName -Count $CpuCount -ExposeVirtualizationExtensions $true
Set-VM -Name $VmName -AutomaticStopAction ShutDown | Out-Null
Start-VM -Name $VmName | Out-Null

[pscustomobject]@{
    VmName                   = $VmName
    TempDiskPath             = $tempVhdx
    NestedVirtualization     = $true
    CustomizationScriptCount = $CustomizationScriptPaths.Count
    NextStep                 = 'Run guest bootstrap to execute customization scripts and register runner.'
}
