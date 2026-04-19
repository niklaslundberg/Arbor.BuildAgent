# Packer template – Windows Server 2025 base image (Hyper-V Generation 2)
#
# Prerequisites (run on the Hyper-V host):
#   - Packer >= 1.9            (winget install HashiCorp.Packer)
#   - Windows ADK OR use Build-BaseImage-HyperV.ps1 which creates the
#     autounattend ISO via IMAPI2 without needing the ADK
#   - A Windows Server 2025 evaluation ISO
#     https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025
#
# Build:
#   cd <repo-root>
#   packer init images/hyperv/windows2025.pkr.hcl
#   packer build -var "iso_url=D:/ISOs/WS2025.iso" images/hyperv/windows2025.pkr.hcl

packer {
  required_plugins {
    hyperv = {
      source  = "github.com/hashicorp/hyperv"
      version = "~> 1"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "iso_url" {
  description = "Path or URL to the Windows Server 2025 ISO."
  type        = string
}

variable "iso_checksum" {
  description = "SHA256 checksum of the ISO, or 'none' to skip verification."
  type        = string
  default     = "none"
}

variable "autounattend_iso" {
  description = "Path to a small ISO containing autounattend.xml and winrm-setup.ps1. Create with scripts/image-builder/New-AutounattendIso.ps1."
  type        = string
  default     = "images/common/autounattend.iso"
}

variable "vm_name" {
  type    = string
  default = "windows2025-runner-base"
}

variable "output_directory" {
  description = "Directory where the finished VHDX template is stored."
  type        = string
  default     = "output/hyperv/windows2025-runner-base"
}

variable "cpus" {
  type    = number
  default = 4
}

variable "memory_mb" {
  type    = number
  default = 8192
}

variable "disk_size_mb" {
  description = "Size of the OS disk in MB. 102400 = 100 GB."
  type        = number
  default     = 102400
}

variable "winrm_password" {
  description = "Password for the packer local-admin account (must match autounattend.xml)."
  type      = string
  default   = "Packer1234!"
  sensitive = true
}

variable "runner_images_ref" {
  description = "Git ref of actions/runner-images to clone (branch or tag)."
  type        = string
  default     = "main"
}

variable "install_full_runner_image_tools" {
  description = "When true all tool-install scripts from actions/runner-images are executed. Set to false for a minimal base image."
  type    = bool
  default = true
}

variable "sysprep_before_export" {
  description = "Run Sysprep /generalize before Packer shuts down the VM. Recommended for shared templates."
  type    = bool
  default = true
}

# ---------------------------------------------------------------------------
# Source
# ---------------------------------------------------------------------------

source "hyperv-iso" "windows2025" {
  vm_name  = var.vm_name
  iso_url  = var.iso_url
  iso_checksum = var.iso_checksum

  cpus         = var.cpus
  memory       = var.memory_mb
  disk_size    = var.disk_size_mb

  # Generation 2 – UEFI, Secure Boot, no legacy hardware
  generation = 2
  enable_secure_boot    = true
  secure_boot_template  = "MicrosoftWindows"

  # The secondary ISO provides autounattend.xml and winrm-setup.ps1.
  # Windows Setup finds autounattend.xml automatically on any attached media.
  secondary_iso_images = [var.autounattend_iso]

  # Switch name – must already exist on the host
  switch_name = "Default Switch"

  # Enable nested virtualization so the built image can run WSL 2 / Hyper-V.
  enable_virtualization_extensions = true

  communicator   = "winrm"
  winrm_username = "packer"
  winrm_password = var.winrm_password
  winrm_use_ssl  = false
  # Allow time for Windows installation + first tools to install
  winrm_timeout  = "6h"

  # Headless hides the VM console; set to false to watch progress
  headless = false

  # After all provisioners complete and optionally after Sysprep, shut down
  shutdown_command = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer build complete\""
  shutdown_timeout = "15m"

  output_directory = var.output_directory
  keep_registered  = false
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

build {
  name    = "windows2025-runner-base"
  sources = ["source.hyperv-iso.windows2025"]

  # --- 1. Upload helper scripts into the guest --------------------------------

  # Helper: fetches runner-images scripts from GitHub (must be uploaded before use)
  provisioner "file" {
    source      = "${path.root}/../../scripts/image-builder/Get-RunnerImageScripts.ps1"
    destination = "C:/Windows/Temp/Get-RunnerImageScripts.ps1"
  }

  # --- 2. Fetch actions/runner-images scripts into the guest -----------------
  provisioner "powershell" {
    inline = [
      "Set-ExecutionPolicy Bypass -Scope Process -Force",
      "$ref = '${var.runner_images_ref}'",
      "& C:/Windows/Temp/Get-RunnerImageScripts.ps1 -Ref $ref -DestinationDir C:/runner-images-scripts | Out-Null"
    ]
  }

  # --- 3. Install Chocolatey, winget, baseline tools -------------------------
  provisioner "powershell" {
    inline = [
      "Set-ExecutionPolicy Bypass -Scope Process -Force",
      # Install Chocolatey
      "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072",
      "Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))",
      # Refresh env
      "$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH','User')"
    ]
  }

  # --- 4. Run full runner-images tool install scripts (optional) -------------
  provisioner "powershell" {
    inline = [
      "if ('${var.install_full_runner_image_tools}' -eq 'true') {",
      "  Set-ExecutionPolicy Bypass -Scope Process -Force",
      "  $scripts = Get-ChildItem 'C:/runner-images-scripts/images/windows/scripts/build' -Filter '*.ps1' | Sort-Object Name",
      "  foreach ($s in $scripts) {",
      "    Write-Host ('Running: ' + $s.Name)",
      "    try { & $s.FullName } catch { Write-Warning ('Script failed: ' + $s.Name + ' - ' + $_.Exception.Message) }",
      "  }",
      "} else { Write-Host 'Skipping full runner-image tool install (install_full_runner_image_tools=false)' }"
    ]
    max_retries = 1
    timeout     = "240m"
  }

  # --- 5. Re-enable Defender and run a quick scan ----------------------------
  provisioner "powershell" {
    inline = [
      "Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue",
      "Start-MpScan -ScanType QuickScan -ErrorAction SilentlyContinue"
    ]
  }

  # --- 6. Optional Sysprep before export -------------------------------------
  provisioner "powershell" {
    inline = [
      "if ('${var.sysprep_before_export}' -eq 'true') {",
      "  Write-Host 'Running Sysprep /generalize – VM will shut down automatically.'",
      "  & C:/Windows/System32/Sysprep/sysprep.exe /oobe /generalize /quiet /shutdown",
      "} else { Write-Host 'Skipping Sysprep (sysprep_before_export=false)' }"
    ]
  }
}
