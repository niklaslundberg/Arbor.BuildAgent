# Packer template – Windows Server 2025 base image (Proxmox VE)
#
# Prerequisites:
#   - Packer >= 1.9                (winget install HashiCorp.Packer)
#   - Proxmox VE >= 8.x with API access
#   - Windows Server 2025 evaluation ISO uploaded to Proxmox ISO storage
#     https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025
#   - VirtIO drivers ISO uploaded to Proxmox ISO storage
#     https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
#
# Build:
#   cd <repo-root>
#   packer init images/proxmox/windows2025.pkr.hcl
#   packer build \
#     -var "proxmox_url=https://proxmox.example.com:8006/api2/json" \
#     -var "proxmox_node=pve01" \
#     -var "proxmox_token_id=packer@pve!packer" \
#     -var "proxmox_token_secret=<secret>" \
#     images/proxmox/windows2025.pkr.hcl

packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = "~> 1"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "proxmox_url" {
  description = "Proxmox API URL (e.g. https://pve01:8006/api2/json)."
  type        = string
}

variable "proxmox_node" {
  description = "Proxmox node name where the build VM runs."
  type        = string
}

variable "proxmox_token_id" {
  description = "Proxmox API token ID (format: user@realm!tokenname)."
  type        = string
}

variable "proxmox_token_secret" {
  description = "Proxmox API token secret."
  type      = string
  sensitive = true
}

variable "proxmox_insecure_skip_tls_verify" {
  description = "Set to true when using a self-signed Proxmox TLS certificate."
  type    = bool
  default = false
}

variable "iso_file" {
  description = "Proxmox ISO storage path of the Windows Server 2025 ISO (e.g. local:iso/WS2025.iso)."
  type        = string
}

variable "virtio_iso_file" {
  description = "Proxmox ISO storage path of the VirtIO drivers ISO."
  type        = string
  default     = "local:iso/virtio-win.iso"
}

variable "iso_storage" {
  description = "Proxmox storage ID where the autounattend CD-ROM image is uploaded."
  type    = string
  default = "local"
}

variable "disk_storage" {
  description = "Proxmox storage for the build VM disk (must support linked clones for templates)."
  type    = string
  default = "local-lvm"
}

variable "template_name" {
  type    = string
  default = "windows2025-runner-base"
}

variable "template_description" {
  type    = string
  default = "Windows Server 2025 runner base image – built by Arbor.BuildAgent"
}

variable "vm_id" {
  description = "VMID for the build VM. Must not conflict with existing VMs."
  type    = number
  default = 9000
}

variable "cpus" {
  type    = number
  default = 4
}

variable "memory_mb" {
  type    = number
  default = 8192
}

variable "disk_size" {
  type    = string
  default = "100G"
}

variable "winrm_password" {
  description = "Password for the packer local-admin account (must match autounattend.xml)."
  type      = string
  default   = "Packer1234!"
  sensitive = true
}

variable "runner_images_ref" {
  description = "Git ref of actions/runner-images to clone."
  type    = string
  default = "main"
}

variable "install_full_runner_image_tools" {
  description = "When true all tool-install scripts from actions/runner-images are executed."
  type    = bool
  default = true
}

variable "sysprep_before_export" {
  description = "Run Sysprep /generalize before converting the VM to a template."
  type    = bool
  default = true
}

# ---------------------------------------------------------------------------
# Source
# ---------------------------------------------------------------------------

source "proxmox-iso" "windows2025" {
  proxmox_url              = var.proxmox_url
  node                     = var.proxmox_node
  token                    = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure_skip_tls_verify = var.proxmox_insecure_skip_tls_verify

  vm_id   = var.vm_id
  vm_name = var.template_name

  # CPU with nested virtualization extensions for WSL 2 support
  cpu_type = "host"
  cores    = var.cpus
  memory   = var.memory_mb

  # OS boot disk
  disks {
    type         = "virtio"
    disk_size    = var.disk_size
    storage_pool = var.disk_storage
    format       = "qcow2"
  }

  # Network
  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # Windows Server 2025 ISO
  boot_iso {
    iso_file         = var.iso_file
    unmount          = true
  }

  # Secondary CD-ROMs: VirtIO drivers + autounattend media
  additional_iso_files {
    iso_file         = var.virtio_iso_file
    cd_label         = "virtio"
    unmount          = true
  }

  additional_iso_files {
    # The autounattend ISO is uploaded to Proxmox by Build-BaseImage-Proxmox.ps1
    iso_file         = "${var.iso_storage}:iso/autounattend-ws2025.iso"
    cd_label         = "autounattend"
    unmount          = true
  }

  # Machine type – q35 for UEFI/Secure-Boot
  machine = "q35"
  bios    = "ovmf"
  efidisk {
    storage      = var.disk_storage
    efi_type     = "4m"
    pre_enrolled_keys = true
  }

  # Windows needs the virtio-serial (qemu-guest-agent) scsi controller
  scsi_controller = "virtio-scsi-pci"

  communicator   = "winrm"
  winrm_username = "packer"
  winrm_password = var.winrm_password
  winrm_use_ssl  = false
  winrm_timeout  = "6h"

  template_name        = var.template_name
  template_description = var.template_description
  os                   = "win11"  # Proxmox uses win11 for Server 2025 OSTYPE

  # Convert to template after successful build
  onboot = false
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

build {
  name    = "windows2025-runner-base"
  sources = ["source.proxmox-iso.windows2025"]

  # Upload helper scripts
  provisioner "file" {
    source      = "${path.root}/../../scripts/image-builder/Get-RunnerImageScripts.ps1"
    destination = "C:/Windows/Temp/Get-RunnerImageScripts.ps1"
  }

  # Fetch actions/runner-images scripts
  provisioner "powershell" {
    inline = [
      "Set-ExecutionPolicy Bypass -Scope Process -Force",
      "$ref = '${var.runner_images_ref}'",
      "& C:/Windows/Temp/Get-RunnerImageScripts.ps1 -Ref $ref -DestinationDir C:/runner-images-scripts | Out-Null"
    ]
  }

  # Install Chocolatey
  provisioner "powershell" {
    inline = [
      "Set-ExecutionPolicy Bypass -Scope Process -Force",
      "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072",
      "Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))",
      "$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH','User')"
    ]
  }

  # Install VirtIO guest agent (enables Proxmox live-migration & graceful shutdown)
  provisioner "powershell" {
    inline = [
      "Set-ExecutionPolicy Bypass -Scope Process -Force",
      "$virtio = Get-WmiObject Win32_LogicalDisk -Filter 'DriveType=5' | Where-Object { Test-Path (Join-Path $_.DeviceID 'guest-agent/qemu-ga-x86_64.msi') }",
      "if ($virtio) { Start-Process msiexec.exe -ArgumentList '/i', (Join-Path $virtio.DeviceID 'guest-agent/qemu-ga-x86_64.msi'), '/quiet', '/norestart' -Wait }",
      "else { Write-Warning 'VirtIO guest-agent MSI not found on any CD-ROM drive.' }"
    ]
  }

  # Run full runner-images tool install scripts
  provisioner "powershell" {
    inline = [
      "if ('${var.install_full_runner_image_tools}' -eq 'true') {",
      "  Set-ExecutionPolicy Bypass -Scope Process -Force",
      "  $scripts = Get-ChildItem 'C:/runner-images-scripts/images/windows/scripts/build' -Filter '*.ps1' | Sort-Object Name",
      "  foreach ($s in $scripts) {",
      "    Write-Host ('Running: ' + $s.Name)",
      "    try { & $s.FullName } catch { Write-Warning ('Script failed: ' + $s.Name + ' - ' + $_.Exception.Message) }",
      "  }",
      "} else { Write-Host 'Skipping full runner-image tool install.' }"
    ]
    max_retries = 1
    timeout     = "240m"
  }

  # Re-enable Defender and quick-scan
  provisioner "powershell" {
    inline = [
      "Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue",
      "Start-MpScan -ScanType QuickScan -ErrorAction SilentlyContinue"
    ]
  }

  # Sysprep
  provisioner "powershell" {
    inline = [
      "if ('${var.sysprep_before_export}' -eq 'true') {",
      "  Write-Host 'Running Sysprep /generalize – VM will shut down automatically.'",
      "  & C:/Windows/System32/Sysprep/sysprep.exe /oobe /generalize /quiet /shutdown",
      "} else { Write-Host 'Skipping Sysprep.' }"
    ]
  }
}
