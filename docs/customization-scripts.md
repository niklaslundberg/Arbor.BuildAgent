# Customization scripts

All customization is PowerShell-first. Place scripts under `scripts/customization` and execute them during provisioning.

## Contract

Each customization script should be idempotent where possible and accept explicit parameters.

## Example: TeamCity agent

Use:

```powershell
./scripts/customization/Install-TeamCityAgent.ps1 \
  -ServerUrl "https://teamcity.example.com" \
  -AgentName "agent-%COMPUTERNAME%" \
  -WorkDir "C:\BuildAgent\work"
```

You can call this from your VM bootstrap process alongside your GitHub runner registration/start script.

## Suggested bootstrap order

1. Baseline OS/image hardening
2. Install/verify tooling required by your builds
3. Install/configure TeamCity agent (optional)
4. Configure and start GitHub Actions runner
5. Execute workload
6. Stop services and teardown VM
