# Packer / Hyper-V build

Builds a Windows Server 2022 VM with the Phase 1/1.5 toolchain (JDK, Ghidra,
GhidrAssist, GhidrAssistMCP enabled, Claude Code) already provisioned.

## Requirements

- Hyper-V enabled (`Get-Service vmms` should show `Running`)
- An **elevated** PowerShell (Hyper-V VM creation needs admin rights, or
  membership in the `Hyper-V Administrators` local group). This can't be
  scripted around — Windows requires interactive elevation.
- `environment/scripts/get_packer.ps1` / `install_packer.ps1` run once
  (installs Packer + the `hyperv` plugin)

## Running the build

From an elevated PowerShell:

```powershell
.\environment\scripts\build_vm.ps1
```

This reads every parameter (ISO URL, VM specs, switch name, admin password)
from `environment/config.ps1` and calls `packer build`. First build downloads
a ~5GB Windows Server 2022 Evaluation ISO (cached by Packer after that), then
installs Windows unattended (`http/autounattend.xml`), then uploads and runs
`scripts/provision.ps1` over WinRM.

`$PackerCacheDir` and `$PackerOutputDir` in `config.ps1` point at `C:\`, not
somewhere under the repo. This is required, not a style choice: this repo
lives on a cloud-sync drive (Google Drive, mounted as `G:\`), and Hyper-V's
VMMS service can't attach an ISO or VHD that lives there — `Add-VMDvdDrive`
fails with "Access is denied" because VMMS can't set the NTFS ACLs it needs
on a cloud-sync filesystem. If you ever move this repo to a different
cloud-synced location, keep these two paths on a real local NTFS volume.

## Importing the built VM

`packer build` always unregisters/deletes its build VM after exporting —
the artifact is just files in `$PackerOutputDir` (default
`C:\packer-output\fdny-decomp`), not a VM Hyper-V Manager will show you.
Nothing's wrong if Hyper-V Manager says "No virtual machines were found" —
you still need to import it once:

```powershell
Import-VM -Path "C:\packer-output\fdny-decomp\Virtual Machines\<guid>.vmcx"
```

(find the `.vmcx` filename with `Get-ChildItem "C:\packer-output\fdny-decomp\Virtual Machines"`).

That imports **in place** — Hyper-V references the exported files directly,
no copying, but re-running `build_vm.ps1` later will overwrite this VM's
storage out from under it. If you want to keep this exact build around
while producing a new one, import a copy instead before rebuilding:

```powershell
Import-VM -Path "C:\packer-output\fdny-decomp\Virtual Machines\<guid>.vmcx" `
    -Copy -GenerateNewId `
    -VhdDestinationPath "C:\vms\fdny-decomp\vhd" `
    -VirtualMachinePath "C:\vms\fdny-decomp"
```

## Known manual sync point

`http/autounattend.xml` hardcodes the Administrator password (`pass`) in
three places — `AdministratorPassword`, `AutoLogon`, and the registry-based
persistent autologon `FirstLogonCommands` — since there's no templating
wired up between it and `$VmAdminPassword` in `config.ps1` yet. If you
change one, change all four.

## What gets baked in

`provision.ps1` reruns the same scripts verified by hand on the dev machine:
JDK, Ghidra, GhidrAssist, GhidrAssistMCP, Claude Code (downloaded +
installed), a smoke-test Ghidra project (to generate Ghidra's default tool
config), then `enable_ghidrassist.ps1` to flip both plugins on — all with the
same fully-headless approach proven in Phase 1.5, no manual GUI steps.

`$GameExePath` and `$GhidraProjectName` are reset to placeholders after the
smoke test, same as on the dev machine — point `$GameExePath` at the real
game executable and rerun `config_ghidra.ps1` once the VM is up.

Also: Desktop shortcuts for Ghidra and Claude Code (Public desktop, so any
account sees them), `claude.exe` added to the machine `PATH` (the native
installer doesn't do this), persistent registry-based autologon (doesn't
expire, unlike the unattend `AutoLogon` element's `LogonCount`), and the
screensaver / inactivity auto-lock / display+sleep timeouts all disabled —
this VM is meant to stay logged in and usable without repeated sign-ins.
