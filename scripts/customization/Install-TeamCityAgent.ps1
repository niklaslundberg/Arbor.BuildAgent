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
    (Get-Content -LiteralPath $confPath)
        .Replace('serverUrl=', "serverUrl=$ServerUrl")
        .Replace('name=', "name=$AgentName")
        .Replace('workDir=', "workDir=$WorkDir") |
        Set-Content -LiteralPath $confPath
}

Write-Host 'TeamCity build agent files prepared. Register/start agent service according to your environment policy.'
