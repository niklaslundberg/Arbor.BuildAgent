# Arbor.BuildAgent

Automation and guidance for running ephemeral self-hosted GitHub Actions runners on:

- Proxmox VE (linked clones)
- Hyper-V on Windows 11 / Windows Server 2025

The goal is to stay close to GitHub-hosted Windows images while keeping runner VMs disposable and easy to update.

## Quick start

1. Read [`docs/self-hosted-runner-plan.md`](docs/self-hosted-runner-plan.md)
2. Add your customization scripts (for example TeamCity) as documented in [`docs/customization-scripts.md`](docs/customization-scripts.md)
3. Resolve latest upstream runner-image metadata:

   ```powershell
   ./scripts/common/Resolve-LatestRunnerImage.ps1 -OsName windows-2025-vs2026
   ```

4. Use either Hyper-V or Proxmox scripts to create/start ephemeral VMs and remove them when done.
