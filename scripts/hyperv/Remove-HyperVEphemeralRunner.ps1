[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$VmName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TempDiskPath,

    [Parameter()]
    [ValidateRange(0, 240)]
    [int]$CooldownMinutes = 0
)

if ($CooldownMinutes -gt 0) {
    Start-Sleep -Seconds ($CooldownMinutes * 60)
}

$vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
if ($null -ne $vm) {
    if ($vm.State -ne 'Off') {
        Stop-VM -Name $VmName -Force -TurnOff
    }

    Remove-VM -Name $VmName -Force
}

if (Test-Path -LiteralPath $TempDiskPath) {
    Remove-Item -LiteralPath $TempDiskPath -Force
}

Write-Host "Removed VM '$VmName' and temporary disk '$TempDiskPath'."
