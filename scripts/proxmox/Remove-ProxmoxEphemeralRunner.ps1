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
    [int]$EphemeralVmId,

    [Parameter()]
    [ValidateRange(0, 240)]
    [int]$CooldownMinutes = 0
)

if ($CooldownMinutes -gt 0) {
    Start-Sleep -Seconds ($CooldownMinutes * 60)
}

$headers = @{
    Authorization = "PVEAPIToken=$TokenId=$TokenSecret"
}

$stopUri = "$ProxmoxApiBaseUrl/api2/json/nodes/$Node/qemu/$EphemeralVmId/status/stop"
try {
    Invoke-RestMethod -Method Post -Uri $stopUri -Headers $headers | Out-Null
} catch {
    Write-Verbose "Stop request failed or VM already stopped: $($_.Exception.Message)"
}

$deleteUri = "$ProxmoxApiBaseUrl/api2/json/nodes/$Node/qemu/$EphemeralVmId"
Invoke-RestMethod -Method Delete -Uri $deleteUri -Headers $headers -Body @{ purge = 1; 'destroy-unreferenced-disks' = 1 } | Out-Null

Write-Host "Removed Proxmox VM '$EphemeralVmId' and purged ephemeral disks."
