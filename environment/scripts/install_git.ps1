# Silently self-extracts the downloaded PortableGit archive into
# $GitInstallDir. It's a 7z SFX exe, not a zip, so this runs it with
# -y (yes to all) and -o<dir> (extract target) instead of Expand-Archive.

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot '..\config.ps1')

$exeFile = Join-Path $DownloadDir $GitAssetName
if (-not (Test-Path $exeFile)) {
    throw "PortableGit installer not found: $exeFile. Run get_git.ps1 first."
}

New-Item -ItemType Directory -Force -Path $GitInstallDir | Out-Null

# Must use Start-Process -Wait, not `& $exeFile` — the SFX extractor
# detaches and returns control immediately otherwise, so the calling
# script carries on before extraction has actually finished.
$proc = Start-Process -FilePath $exeFile -ArgumentList '-y', "-o`"$GitInstallDir`"" -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -ne 0) {
    throw "PortableGit extraction failed with exit code $($proc.ExitCode)"
}

Write-Host "Git installed: $(Join-Path $GitInstallDir 'bin\git.exe')"
