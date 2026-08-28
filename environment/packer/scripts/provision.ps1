# environment/packer/scripts/provision.ps1
#
# Runs inside the guest VM (uploaded to $RepoRoot by the Packer file
# provisioner). Reruns the same get_*/install_* pipeline verified by hand
# in Phase 1/1.5, plus a smoke-test Ghidra project so
# enable_ghidrassist.ps1 has a tool config to patch.

$RepoRoot         = 'C:\fdny-decomp'
$EnvironmentDir   = Join-Path $RepoRoot 'environment'
$ScriptsDir       = Join-Path $EnvironmentDir 'scripts'
$SmokeTestExePath = 'C:\Windows\System32\notepad.exe'

$ErrorActionPreference = 'Stop'

function Invoke-Step {
    param([Parameter(Mandatory)] [string]$ScriptPath)

    Write-Host "=== Running $ScriptPath ==="
    & $ScriptPath
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "$ScriptPath exited with code $LASTEXITCODE"
    }
}

Invoke-Step (Join-Path $ScriptsDir 'get_jdk.ps1')
Invoke-Step (Join-Path $ScriptsDir 'install_jdk.ps1')
Invoke-Step (Join-Path $ScriptsDir 'get_ghidra.ps1')
Invoke-Step (Join-Path $ScriptsDir 'install_ghidra.ps1')
Invoke-Step (Join-Path $ScriptsDir 'get_ghidrassist.ps1')
Invoke-Step (Join-Path $ScriptsDir 'get_ghidrassistmcp.ps1')
Invoke-Step (Join-Path $ScriptsDir 'get_claude.ps1')
Invoke-Step (Join-Path $ScriptsDir 'install_claude.ps1')
Invoke-Step (Join-Path $ScriptsDir 'get_sqlite.ps1')
Invoke-Step (Join-Path $ScriptsDir 'install_sqlite.ps1')
Invoke-Step (Join-Path $ScriptsDir 'get_git.ps1')
Invoke-Step (Join-Path $ScriptsDir 'install_git.ps1')

# The native installer puts claude.exe here but doesn't add it to PATH.
$ClaudeBinDir = Join-Path $env:USERPROFILE '.local\bin'
$machinePath  = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
if ($machinePath -notlike "*$ClaudeBinDir*") {
    [Environment]::SetEnvironmentVariable('PATH', "$machinePath;$ClaudeBinDir", 'Machine')
}

# Smoke-test project: gives config_ghidra.ps1's analyzeHeadless run something
# to import, which is what creates Ghidra's default per-user tool config —
# enable_ghidrassist.ps1 needs that file to already exist.
$ConfigPath = Join-Path $EnvironmentDir 'config.ps1'
(Get-Content $ConfigPath) -replace [regex]::Escape("'C:\path\to\game.exe'"), "'$SmokeTestExePath'" |
    Set-Content $ConfigPath

Invoke-Step (Join-Path $ScriptsDir 'config_ghidra.ps1')
Invoke-Step (Join-Path $ScriptsDir 'enable_ghidrassist.ps1')

# Desktop shortcuts for Ghidra and Claude Code, on the Public desktop so
# they show up regardless of which account logs in.
$PublicDesktop = Join-Path $env:PUBLIC 'Desktop'
$RunGhidraPath = Join-Path $ScriptsDir 'run_ghidra.ps1'
$ClaudeExePath = Join-Path $ClaudeBinDir 'claude.exe'

. (Join-Path $ScriptsDir 'common.ps1')
. $ConfigPath
$ghidraHome     = Get-FirstSubDir $GhidraInstallDir
$GhidraIconPath = Join-Path $ghidraHome.FullName 'support\ghidra.ico'

# sqlite3 and git on PATH too, same reasoning as the Claude Code fix above.
$GitBinDir = Join-Path $GitInstallDir 'bin'
foreach ($dir in @($SqliteInstallDir, $GitBinDir)) {
    if ($machinePath -notlike "*$dir*") {
        $machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
        [Environment]::SetEnvironmentVariable('PATH', "$machinePath;$dir", 'Machine')
    }
}

$shell = New-Object -ComObject WScript.Shell

$ghidraShortcut = $shell.CreateShortcut((Join-Path $PublicDesktop 'Ghidra.lnk'))
$ghidraShortcut.TargetPath       = 'powershell.exe'
$ghidraShortcut.Arguments        = "-NoProfile -ExecutionPolicy Bypass -File `"$RunGhidraPath`""
$ghidraShortcut.WorkingDirectory = $RepoRoot
$ghidraShortcut.IconLocation     = $GhidraIconPath
$ghidraShortcut.Save()

$claudeShortcut = $shell.CreateShortcut((Join-Path $PublicDesktop 'Claude Code.lnk'))
$claudeShortcut.TargetPath       = 'powershell.exe'
$claudeShortcut.Arguments        = "-NoExit -Command `"Set-Location '$RepoRoot'; & '$ClaudeExePath'`""
$claudeShortcut.WorkingDirectory = $RepoRoot
$claudeShortcut.IconLocation     = $ClaudeExePath
$claudeShortcut.Save()

Write-Host "Desktop shortcuts created: $PublicDesktop"

# Persistent autologon + no lock/sleep. Originally these were
# FirstLogonCommands in autounattend.xml, but setting registry
# AutoAdminLogon while the unattend's own <AutoLogon> mechanism was still
# mid-flight on that same first logon caused the VM to hang before WinRM
# ever came up. Running them here (over the already-stable WinRM
# connection, well after OOBE finished) avoids that entirely.
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d Administrator /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d pass /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop" /v ScreenSaveActive /t REG_SZ /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v InactivityTimeoutSecs /t REG_DWORD /d 0 /f
powercfg /change monitor-timeout-ac 0
powercfg /change standby-timeout-ac 0

# Revert the smoke-test values — a real $GameExePath gets set per-machine later.
(Get-Content $ConfigPath) `
    -replace [regex]::Escape("'$SmokeTestExePath'"), "'C:\path\to\game.exe'" `
    -replace "^\`$GhidraProjectName\s*=.*$", '$GhidraProjectName = $null   # set by config_ghidra.ps1 once a project is created' |
    Set-Content $ConfigPath

# A local git repo (no remote — nothing to push to from the VM) so the
# unattended agent can commit its own changes to scripts/config/RESEARCH.md
# as it runs, and a human can diff/revert them later.
$gitExe = Join-Path $GitBinDir 'git.exe'
& $gitExe -C $RepoRoot init 2>&1 | Write-Host
& $gitExe -C $RepoRoot config user.email 'agent@fdny-decomp.local' 2>&1 | Write-Host
& $gitExe -C $RepoRoot config user.name 'fdny-decomp agent' 2>&1 | Write-Host
& $gitExe -C $RepoRoot add -A 2>&1 | Write-Host
& $gitExe -C $RepoRoot commit -m 'Baseline: provisioned VM state' 2>&1 | Write-Host

Write-Host '=== Provisioning complete ==='
