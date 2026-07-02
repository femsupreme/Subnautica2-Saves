#Requires -Version 5.1
# Backs up the configured Subnautica 2 save folder into this repo and pushes it to main.
param(
    [switch]$Configure
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $RepoRoot "backup.config"
$BackupRoot = Join-Path $RepoRoot "Save Backups"

function Set-Configuration {
    $savePath = Read-Host "Enter the full path to your Subnautica 2 save folder"
    $savePath = $savePath.Trim()
    # Strip surrounding quotes (e.g. from Explorer's "Copy as path", which
    # wraps the path in double quotes that get typed/pasted in literally).
    $isDoubleQuoted = $savePath.StartsWith('"') -and $savePath.EndsWith('"')
    $isSingleQuoted = $savePath.StartsWith("'") -and $savePath.EndsWith("'")
    if ($savePath.Length -ge 2 -and ($isDoubleQuoted -or $isSingleQuoted)) {
        $savePath = $savePath.Substring(1, $savePath.Length - 2)
    }
    if (-not (Test-Path $savePath)) {
        Write-Warning "'$savePath' does not exist yet. Saving anyway."
    }
    "SAVE_PATH=$savePath" | Set-Content -Path $ConfigFile -Encoding UTF8
    Write-Host "Saved save location to $ConfigFile"
}

if ($Configure -or -not (Test-Path $ConfigFile)) {
    Set-Configuration
}

$config = @{}
Get-Content $ConfigFile | ForEach-Object {
    if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
        $config[$matches[1]] = $matches[2]
    }
}
$SavePath = $config["SAVE_PATH"]

if ([string]::IsNullOrWhiteSpace($SavePath)) {
    Write-Error "SAVE_PATH not set in $ConfigFile. Run with -Configure."
    exit 1
}

if (-not (Test-Path $SavePath)) {
    Write-Error "Save path '$SavePath' does not exist."
    exit 1
}

Set-Location $RepoRoot

Write-Host "Syncing with origin/main before backing up..."
git pull --rebase origin main
if ($LASTEXITCODE -ne 0) { Write-Error "git pull --rebase failed."; exit 1 }

$DateStamp = Get-Date -Format "yyyy-MM-dd"
$Dest = Join-Path $BackupRoot $DateStamp

# Rebuild the destination each run so the backup is a true mirror of the
# save folder, not an accumulation of stale files from earlier runs today.
if (Test-Path $Dest) {
    Remove-Item -Path $Dest -Recurse -Force
}
New-Item -ItemType Directory -Path $Dest -Force | Out-Null

Write-Host "Copying save files from '$SavePath' to '$Dest'..."
Copy-Item -Path (Join-Path $SavePath '*') -Destination $Dest -Recurse -Force

git add "Save Backups/$DateStamp"

git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "No changes to back up today."
    exit 0
}

git commit -m "Backup $DateStamp"
if ($LASTEXITCODE -ne 0) { Write-Error "git commit failed."; exit 1 }

Write-Host "Pushing to main..."
git push origin main
if ($LASTEXITCODE -ne 0) { Write-Error "git push failed."; exit 1 }

Write-Host "Backup complete for $DateStamp."
