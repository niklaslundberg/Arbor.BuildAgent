[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ServerUrl,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AgentName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$InstallDir = 'C:\BuildAgent',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$WorkDir = 'C:\BuildAgent\work'
)

$ProgressPreference = 'SilentlyContinue'

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

$zipPath = Join-Path $env:TEMP 'teamcity-agent.zip'
$downloadUri = "$ServerUrl/update/buildAgent.zip"
Invoke-WebRequest -Uri $downloadUri -OutFile $zipPath
Expand-Archive -Path $zipPath -DestinationPath $InstallDir -Force

$confPath = Join-Path $InstallDir 'conf\buildAgent.properties'
if (Test-Path -LiteralPath $confPath) {
    $lines = Get-Content -LiteralPath $confPath
    $keys = @{
        serverUrl = $false
        name      = $false
        workDir   = $false
    }

    $updated = foreach ($line in $lines) {
        if ($line -match '^serverUrl=') {
            $keys.serverUrl = $true
            "serverUrl=$ServerUrl"
            continue
        }

        if ($line -match '^name=') {
            $keys.name = $true
            "name=$AgentName"
            continue
        }

        if ($line -match '^workDir=') {
            $keys.workDir = $true
            "workDir=$WorkDir"
            continue
        }

        $line
    }

    if (-not $keys.serverUrl) { $updated += "serverUrl=$ServerUrl" }
    if (-not $keys.name) { $updated += "name=$AgentName" }
    if (-not $keys.workDir) { $updated += "workDir=$WorkDir" }

    Set-Content -LiteralPath $confPath -Value $updated
}

Write-Host 'TeamCity build agent files prepared. Register/start agent service according to your environment policy.'
