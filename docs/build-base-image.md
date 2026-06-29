# Building the base runner image

This document explains how to build a Windows Server 2025 base image containing
the same tools, SDKs and software present in GitHub-hosted runners.  The image
can then be used as a parent template for the ephemeral VMs described in
[self-hosted-runner-plan.md](self-hosted-runner-plan.md).

The build is driven by **Packer** using the tool-install scripts from the
official [actions/runner-images](https://github.com/actions/runner-images)
repository.  Because all provisioning is done inside a real Windows VM (not
inside Azure), the resulting image works with Hyper-V and Proxmox.

---

## How it works

```
┌────────────────────────────────────────────────────────────────────────┐
│  Build host (Windows 11 / Server 2025 with Hyper-V, or any machine    │
│  with Packer + network access to Proxmox)                              │
│                                                                        │
│  1. New-AutounattendIso.ps1                                            │
│       └─► autounattend.iso  (answer file + WinRM setup, no ADK needed)│
│                                                                        │
│  2. Get-RunnerImageScripts.ps1                                         │
│       └─► Clones actions/runner-images @ <ref>                        │
│           copies build scripts + toolset.json locally                 │
│                                                                        │
│  3. packer build images/hyperv/windows-2025-vs2026.pkr.hcl   (or proxmox)    │
│       a. Boots Windows Server 2025 from evaluation ISO                │
│       b. autounattend.xml auto-installs Windows + creates packer user │
│       c. winrm-setup.ps1 enables WinRM for Packer communication       │
│       d. Packer connects via WinRM                                    │
│       e. Uploads + runs Get-RunnerImageScripts.ps1 inside guest       │
│       f. Installs Chocolatey                                           │
│       g. Runs every script in actions/runner-images build directory   │
│          (Visual Studio, .NET SDKs, Node, Python, Go, Rust, Git, …)  │
│       h. Re-enables Defender + runs quick scan                        │
│       i. Sysprep /generalize (makes image reusable for clones)        │
│                                                                        │
│  Result ──► Hyper-V: VHDX  │  Proxmox: registered template           │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### Common

| Requirement | Install |
|---|---|
| PowerShell 7+ | `winget install Microsoft.PowerShell` |
| Packer ≥ 1.9 | `winget install HashiCorp.Packer` (or let the build script install it) |
| Git | `winget install Git.Git` |
| Windows Server 2025 evaluation ISO | [Evaluation Center](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025) |

> **Important:** The evaluation ISO is a 180-day trial.  For production use,
> obtain a volume-licensed ISO through your Microsoft agreement.

### Hyper-V only

- Windows 10/11 or Windows Server with the **Hyper-V** role enabled
- Hyper-V PowerShell module (`Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell`)
- A configured Hyper-V virtual switch (the `Default Switch` created automatically by Hyper-V is fine)
- At least **150 GB** of free disk space on a fast drive (NVME recommended)
- At least **16 GB** RAM on the host (the build VM needs 8 GB)

### Proxmox only

- Proxmox VE 8.x with API access
- A Proxmox API token with VM.Allocate, VM.Config.*, Datastore.AllocateSpace permissions
- Windows Server 2025 ISO **already uploaded** to Proxmox ISO storage
- [VirtIO drivers ISO](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso)
  uploaded to Proxmox ISO storage
- Storage pool that supports `qcow2` format (for linked clones later)

---

## How long does it take?

| Stage | Duration |
|---|---|
| Windows installation | 20–40 min |
| Chocolatey + base tools | 10–20 min |
| Visual Studio 2022/2026 | 60–180 min |
| All other runner-images tools | 60–120 min |
| Defender scan + Sysprep | 10–20 min |
| **Total** | **4–8 hours** |

A minimal build (`-InstallFullTools $false`) takes about 30–60 minutes.

---

## Quick start – Hyper-V

```powershell
# From the repository root, in an elevated (Administrator) PowerShell 7+ session:

./scripts/image-builder/Build-BaseImage-HyperV.ps1 `
    -IsoPath "D:\ISOs\WS2025.iso"
```

The script installs Packer if missing, creates the autounattend ISO, downloads
the runner-images scripts, and runs the full Packer build.  Progress is
displayed on the console and logged to `output/hyperv/windows-2025-vs2026/packer.log`.

When the build completes you will see:

```
=== Build complete ===
Base image VHDX : D:\output\hyperv\windows-2025-vs2026\windows-2025-vs2026.vhdx  (65432 MB)

Next step: use this VHDX as -ParentVhdxPath with:
  ./scripts/hyperv/New-HyperVEphemeralRunner.ps1 -ParentVhdxPath 'D:\output\...\..vhdx' ...
```

### Hyper-V advanced options

```powershell
./scripts/image-builder/Build-BaseImage-HyperV.ps1 `
    -IsoPath           "D:\ISOs\WS2025.iso" `
    -RunnerImagesRef   "20250401.1" `      # Pin to a specific release
    -InstallFullTools  $false `            # Minimal build, much faster
    -SysprepBeforeExport $false `          # Keep VM state (no generalization)
    -OutputDirectory   "E:\Images\hyperv"
```

---

## Quick start – Proxmox

```powershell
# From any machine with network access to Proxmox:

./scripts/image-builder/Build-BaseImage-Proxmox.ps1 `
    -ProxmoxApiBaseUrl  "https://pve01:8006/api2/json" `
    -Node               "pve01" `
    -TokenId            "packer@pve!packer" `
    -TokenSecret        "<your-token-secret>" `
    -WindowsIsoFile     "local:iso/WS2025.iso" `
    -InsecureSkipTlsVerify   # remove if Proxmox uses a trusted certificate
```

The script uploads the autounattend ISO to Proxmox, initialises Packer plugins,
and runs the build.  The result is a Proxmox template (VMID 9000 by default).

### Proxmox advanced options

```powershell
./scripts/image-builder/Build-BaseImage-Proxmox.ps1 `
    -ProxmoxApiBaseUrl  "https://pve01:8006/api2/json" `
    -Node               "pve01" `
    -TokenId            "packer@pve!packer" `
    -TokenSecret        "<secret>" `
    -WindowsIsoFile     "local:iso/WS2025.iso" `
    -VirtioIsoFile      "local:iso/virtio-win.iso" `
    -IsoStorage         "local" `
    -DiskStorage        "nvme-pool" `
    -BuildVmId          9100 `
    -RunnerImagesRef    "20250401.1" `
    -InstallFullTools   $false
```

---

## Customising what gets installed

The runner-images scripts read a `toolset.json` file to determine which
versions of tools to install.  `Get-RunnerImageScripts.ps1` downloads the
toolset from the upstream repository.  To customise:

1. Edit `images/runner-image-scripts/toolset.json` after running
   `Get-RunnerImageScripts.ps1` once.
2. Re-run the Packer build with `-SkipScriptDownload` to use your modified
   toolset.

Alternatively, add your own scripts to `scripts/customization/` – they are
executed by the bootstrap process described in
[customization-scripts.md](customization-scripts.md).

---

## Keeping the image up to date

```powershell
# Check latest actions/runner-images release
./scripts/common/Resolve-LatestRunnerImage.ps1

# Rebuild with the latest ref
./scripts/image-builder/Build-BaseImage-HyperV.ps1 `
    -IsoPath "D:\ISOs\WS2025.iso" `
    -RunnerImagesRef (./scripts/common/Resolve-LatestRunnerImage.ps1).LatestTag
```

Rebuilding every 1–4 weeks ensures your base image stays current with upstream
tool updates (new .NET SDK patch releases, VS updates, etc.).

---

## Changing the WinRM password

The default build-time password (`Packer1234!`) is only used during the Packer
provisioning session.  After Sysprep the `packer` account is removed from the
image (it is a local account and Sysprep /generalize wipes local accounts by
default on Windows Server).

If you need to change it, update **all three** places consistently:

1. `images/common/autounattend.xml` – `<AutoLogon>` and `<LocalAccount>` sections
2. The `-WinRmPassword` parameter when calling `Build-BaseImage-HyperV.ps1` / `Build-BaseImage-Proxmox.ps1`
3. The corresponding `winrm_password` variable in the Packer HCL (or override via `-var`)

---

## Manual Packer invocation

If you prefer to call Packer directly:

```powershell
# Create autounattend ISO first
./scripts/image-builder/New-AutounattendIso.ps1

# Fetch runner-images scripts
./scripts/image-builder/Get-RunnerImageScripts.ps1 -Ref main

# Hyper-V
cd <repo-root>
packer init images/hyperv/windows-2025-vs2026.pkr.hcl
packer build `
    -var "iso_url=D:/ISOs/WS2025.iso" `
    -var "autounattend_iso=images/common/autounattend.iso" `
    images/hyperv/windows-2025-vs2026.pkr.hcl

# Proxmox
packer init images/proxmox/windows-2025-vs2026.pkr.hcl
packer build `
    -var "proxmox_url=https://pve01:8006/api2/json" `
    -var "proxmox_node=pve01" `
    -var "proxmox_token_id=packer@pve!packer" `
    -var "proxmox_token_secret=<secret>" `
    -var "iso_file=local:iso/WS2025.iso" `
    images/proxmox/windows-2025-vs2026.pkr.hcl
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Packer times out waiting for WinRM | autounattend not found / WinRM not enabled | Verify autounattend.iso was created and contains both files; check VM console |
| `New-AutounattendIso.ps1` fails with COM error | Not running on Windows | Must run on Windows; Linux hosts need `mkisofs` (see note below) |
| VS install fails | Insufficient disk space | Ensure ≥ 100 GB free on the build disk |
| Proxmox API 403 | Token permissions | Grant the token VM.Allocate, VM.Config.*, Datastore.AllocateSpace |
| Build takes > 8 hours | Slow disk / network | Use NVMe storage and a fast internet connection |

### Running the Proxmox build from a Linux host

`New-AutounattendIso.ps1` uses the Windows-only IMAPI2 COM object.  On Linux,
create the ISO with `genisoimage`:

```bash
genisoimage -joliet -joliet-long -rock -o images/common/autounattend.iso \
    -V AUTOUNATTEND images/common/
```

Then run the Packer build with `-SkipIsoUpload` after uploading the ISO manually.
