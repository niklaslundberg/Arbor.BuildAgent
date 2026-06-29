# Runs once at first logon (called by autounattend.xml FirstLogonCommands).
# Configures WinRM so Packer can connect via the winrm communicator.

$ErrorActionPreference = 'Stop'

Set-ExecutionPolicy Bypass -Scope Process -Force

# Basic WinRM quick-config
& winrm quickconfig -q 2>&1 | Out-Null

# Allow unencrypted transport and basic auth (build-time only; image is re-SysPrep'd before use)
& winrm set 'winrm/config/service' '@{AllowUnencrypted="true"}' | Out-Null
& winrm set 'winrm/config/service/auth' '@{Basic="true"}' | Out-Null
& winrm set 'winrm/config/winrs' '@{MaxMemoryPerShellMB="2048"}' | Out-Null

# Open firewall port 5985 (HTTP) for WinRM
$null = netsh advfirewall firewall add rule `
    name='WinRM HTTP inbound' `
    dir=in `
    action=allow `
    protocol=TCP `
    localport=5985

Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM

# Disable Windows Defender real-time protection during provisioning to speed up installs.
# The base image receives a full Defender scan at the end of the Packer build.
Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue

# Disable UAC consent prompts - scripts run as Administrator already
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
    -Name 'ConsentPromptBehaviorAdmin' -Value 0

Write-Host 'WinRM setup complete.'
