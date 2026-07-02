#Requires -Version 5.1
# Backs up the configured Subnautica 2 save folder into this repo and pushes it to main.
param(
    [switch]$Configure
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$Branch = "main"

function Fail($message) {
    # Avoid Write-Error here: with $ErrorActionPreference = "Stop" it becomes a
    # terminating exception and prints a noisy stack trace instead of a clean message.
    [Console]::Error.WriteLine("Error: $message")
    exit 1
}

function Test-GitAvailable {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Fail "git is not installed or not on PATH. Install Git for Windows: https://git-scm.com/download/win"
    }
}

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $RepoRoot "backup.config"
$BackupRoot = Join-Path $RepoRoot "Save Backups"

function Test-GitRepo {
    git -C $RepoRoot rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) {
        Fail "'$RepoRoot' is not a git repository."
    }
}

function Test-NoRebaseInProgress {
    $rebaseMerge = Join-Path $RepoRoot ".git\rebase-merge"
    $rebaseApply = Join-Path $RepoRoot ".git\rebase-apply"
    if ((Test-Path $rebaseMerge) -or (Test-Path $rebaseApply)) {
        Fail "A previous git rebase is still in progress in this repo. Run 'git status' in $RepoRoot, resolve it (or 'git rebase --abort'), then try again."
    }
}

function Test-OnBranch {
    $current = git rev-parse --abbrev-ref HEAD 2>$null
    if ($current -ne $Branch) {
        Fail "Expected to be on branch '$Branch' but on '$current'. Switch to '$Branch' before backing up."
    }
}

function Initialize-Configuration {
    $savePath = Read-Host "Enter the full path to your Subnautica 2 save folder"
    $savePath = $savePath.Trim()
    # Strip surrounding quotes (e.g. from Explorer's "Copy as path", which
    # wraps the path in double quotes that get typed/pasted in literally).
    $isDoubleQuoted = $savePath.StartsWith('"') -and $savePath.EndsWith('"')
    $isSingleQuoted = $savePath.StartsWith("'") -and $savePath.EndsWith("'")
    if ($savePath.Length -ge 2 -and ($isDoubleQuoted -or $isSingleQuoted)) {
        $savePath = $savePath.Substring(1, $savePath.Length - 2)
    }

    if ([string]::IsNullOrWhiteSpace($savePath)) {
        Fail "No path entered."
    }

    if (-not (Test-Path $savePath)) {
        Write-Warning "'$savePath' does not exist yet. Saving anyway."
    }

    try {
        "SAVE_PATH=$savePath" | Set-Content -Path $ConfigFile -Encoding UTF8 -ErrorAction Stop
    } catch {
        Fail "Could not write config file '$ConfigFile' (check permissions): $_"
    }
    Write-Host "Saved save location to $ConfigFile"
}

Test-GitAvailable
Test-GitRepo

if ($Configure -or -not (Test-Path $ConfigFile)) {
    Initialize-Configuration
}

$config = @{}
try {
    Get-Content $ConfigFile -ErrorAction Stop | ForEach-Object {
        if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $config[$matches[1]] = $matches[2]
        }
    }
} catch {
    Fail "Could not read config file '$ConfigFile'. Run with -Configure."
}
$SavePath = $config["SAVE_PATH"]

if ([string]::IsNullOrWhiteSpace($SavePath)) {
    Fail "SAVE_PATH not set in $ConfigFile. Run with -Configure."
}

if (-not (Test-Path $SavePath)) {
    Fail "Save path '$SavePath' does not exist."
}

$saveContents = Get-ChildItem -Path $SavePath -Force -ErrorAction SilentlyContinue
if (-not $saveContents) {
    Fail "Save path '$SavePath' is empty (or unreadable -- check permissions). Refusing to wipe today's backup with nothing -- check the path and that Subnautica 2 has actually written a save."
}

try {
    Set-Location $RepoRoot -ErrorAction Stop
} catch {
    Fail "Could not cd into '$RepoRoot': $_"
}

Test-NoRebaseInProgress
Test-OnBranch

Write-Host "Syncing with origin/main before backing up..."
git pull --rebase origin $Branch
if ($LASTEXITCODE -ne 0) {
    git rebase --abort *> $null
    Fail "git pull --rebase failed and was aborted to leave the repo clean. This is usually a network problem or the remote rejecting your credentials -- check your connection and GitHub access, then try again."
}

$DateStamp = Get-Date -Format "yyyy-MM-dd"
$Dest = Join-Path $BackupRoot $DateStamp

# Rebuild the destination each run so the backup is a true mirror of the
# save folder, not an accumulation of stale files from earlier runs today.
try {
    if (Test-Path $Dest) {
        Remove-Item -Path $Dest -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Path $Dest -Force -ErrorAction Stop | Out-Null
} catch {
    Fail "Could not prepare backup folder '$Dest' (check permissions or free disk space): $_"
}

Write-Host "Copying save files from '$SavePath' to '$Dest'..."
try {
    Copy-Item -Path (Join-Path $SavePath '*') -Destination $Dest -Recurse -Force -ErrorAction Stop
} catch {
    Fail "Copying save files failed (check permissions on the save folder, available disk space, and that the game isn't locking a file): $_. No commit was made."
}

git add "Save Backups/$DateStamp"
if ($LASTEXITCODE -ne 0) { Fail "git add failed." }

git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "No changes to back up today."
    exit 0
}

git commit -m "Backup $DateStamp"
if ($LASTEXITCODE -ne 0) {
    Fail "git commit failed. If this is a fresh machine, git may need identity config: git config --global user.name ""Your Name"" ; git config --global user.email ""you@example.com"""
}

Write-Host "Pushing to main..."
git push origin $Branch
if ($LASTEXITCODE -ne 0) {
    Fail "git push failed -- most likely a permissions/auth problem with the GitHub remote (check your credentials, PAT, or SSH key access to this repo). Your backup was already committed locally and is safe; fix access and re-run this script, or run 'git push origin main' manually."
}

Write-Host "Backup complete for $DateStamp."
