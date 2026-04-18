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
    [int]$TemplateVmId,

    [Parameter(Mandatory)]
    [int]$EphemeralVmId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$VmName = "gha-runner-$EphemeralVmId"
)

$headers = @{
    Authorization = "PVEAPIToken=$TokenId=$TokenSecret"
}

$cloneUri = "$ProxmoxApiBaseUrl/api2/json/nodes/$Node/qemu/$TemplateVmId/clone"
$cloneBody = @{
    newid = $EphemeralVmId
    name  = $VmName
    full  = 0
}

Invoke-RestMethod -Method Post -Uri $cloneUri -Headers $headers -Body $cloneBody | Out-Null

# Enable nested virtualization hints in VM args for Intel hosts. Adjust for AMD if needed.
$configUri = "$ProxmoxApiBaseUrl/api2/json/nodes/$Node/qemu/$EphemeralVmId/config"
Invoke-RestMethod -Method Put -Uri $configUri -Headers $headers -Body @{ args = '-cpu host,+vmx' } | Out-Null

$startUri = "$ProxmoxApiBaseUrl/api2/json/nodes/$Node/qemu/$EphemeralVmId/status/start"
Invoke-RestMethod -Method Post -Uri $startUri -Headers $headers | Out-Null

[pscustomobject]@{
    Node               = $Node
    VmId               = $EphemeralVmId
    VmName             = $VmName
    CloneType          = 'linked'
    NestedVirtualization = 'configured via args=-cpu host,+vmx'
    NextStep           = 'Run guest bootstrap (Cloud-Init/WinRM/startup task) to apply customization scripts and register runner.'
}
