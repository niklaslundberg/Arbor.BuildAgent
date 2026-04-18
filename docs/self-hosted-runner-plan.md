# Self-hosted GitHub Actions runner plan (ephemeral)

## Goal

Provide disposable Windows build agents that are:

- close to GitHub-hosted runner configuration
- easy to update to the latest upstream image release information
- usable in both Hyper-V and Proxmox with nested virtualization enabled (for WSL 2)
- customizable with repository-owned PowerShell scripts

## Important reality about GitHub-hosted images

GitHub-hosted VM images are not published as directly downloadable general-purpose VHDX/OVA artifacts for on-prem reuse. The practical approach is:

1. Track latest image release metadata from `actions/runner-images`
2. Build or refresh your own base image from your chosen source image
3. Apply your customization scripts from this repository
4. Launch ephemeral VMs from that base image/template

Use:

```powershell
./scripts/common/Resolve-LatestRunnerImage.ps1 -OsName windows2025
```

This gives you the latest upstream release/tag reference so your process always points to the newest published runner-image metadata.

## Recommended architecture

- **Base image/template** (persistent): Windows 2025 + VS 2026 preview prerequisites + baseline tools
- **Ephemeral VM instance** (temporary):
  - Hyper-V: differencing disk from parent VHDX
  - Proxmox: linked clone from template VM
- **Customization layer**: run one or more PowerShell scripts from this repo on boot/provisioning
- **Workload execution**: register/start runner (and optionally TeamCity agent)
- **Teardown**: remove VM and temporary disk/clone, optionally after cool-down for diagnostics

## Hyper-V workflow

1. Keep a prepared parent VHDX (template image)
2. Create VM via `scripts/hyperv/New-HyperVEphemeralRunner.ps1`
3. Ensure nested virtualization is enabled (`Set-VMProcessor -ExposeVirtualizationExtensions $true`)
4. Run customization scripts in the guest
5. When jobs finish, remove VM + temporary differencing disk via `scripts/hyperv/Remove-HyperVEphemeralRunner.ps1`

## Proxmox workflow

1. Keep a prepared VM template on Proxmox
2. Clone from template as **linked clone** via `scripts/proxmox/New-ProxmoxEphemeralRunner.ps1`
3. Enable nested virtualization on VM config (`args: -cpu host,+vmx` or AMD equivalent)
4. Run customization scripts in guest via your normal bootstrap method (Cloud-Init/WinRM/startup task)
5. Destroy clone via `scripts/proxmox/Remove-ProxmoxEphemeralRunner.ps1`

## Cool-down period recommendation

Use a short cool-down (for example 10-30 minutes) before teardown when diagnostics are needed.

- Keep VM online only long enough to collect logs/crash dumps
- Then automatically destroy VM and temporary storage

## Security and operations guidelines

- Use short-lived registration tokens for GitHub runners
- Never store long-lived PATs inside VM images
- Keep base image immutable; apply environment-specific values at boot
- Rotate template regularly by tracking latest upstream image metadata
- Keep ephemeral storage on fast local SSD/NVMe for short-lived workloads
