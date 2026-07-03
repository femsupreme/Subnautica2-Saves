#Requires -Version 5.1
# Backs up the configured Subnautica 2 save folder into this repo and pushes it to main.
param(
    [switch]$Configure,
    [switch]$Restore
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

# Restore the most recent snapshot in "Save Backups\" back into the live game
# save folder. This is destructive (it replaces the current save), so it takes
# several precautions: it confirms with the user, refuses to restore from an
# empty snapshot, snapshots the current live save first, and stages the copy in
# a sibling folder and swaps it into place so an interrupted copy can never leave
# the game with a half-written save folder.
function Invoke-Restore {
    param($SavePath)

    try {
        Set-Location $RepoRoot -ErrorAction Stop
    } catch {
        Fail "Could not cd into '$RepoRoot': $_"
    }

    Test-NoRebaseInProgress
    Test-OnBranch

    # Best-effort sync so we restore the newest snapshot that exists on GitHub,
    # not just whatever is on this machine. A failure here is non-fatal.
    Write-Host "Syncing with origin/$Branch to get the latest backups..."
    git pull --rebase origin $Branch
    if ($LASTEXITCODE -ne 0) {
        git rebase --abort *> $null
        Write-Warning "Could not sync with origin (network/auth problem?). Continuing with the backups already on this machine."
    }

    if (-not (Test-Path $BackupRoot)) {
        Fail "No 'Save Backups' folder found -- there is nothing to restore."
    }

    # Pick the newest dated backup folder. YYYY-MM-DD names sort chronologically.
    $latest = Get-ChildItem -Path $BackupRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' } |
        Sort-Object Name |
        Select-Object -Last 1
    if (-not $latest) {
        Fail "No dated backup folders found under '$BackupRoot' -- nothing to restore."
    }

    $sourceDir = $latest.FullName

    # Refuse to restore from an empty snapshot -- that would wipe the live save.
    $sourceContents = Get-ChildItem -Path $sourceDir -Force -ErrorAction SilentlyContinue
    if (-not $sourceContents) {
        Fail "Backup '$($latest.Name)' is empty. Refusing to overwrite your live save with nothing."
    }

    Write-Host ""
    Write-Host "About to RESTORE your Subnautica 2 save from backup '$($latest.Name)'."
    Write-Host "  Source (backup): $sourceDir"
    Write-Host "  Target (game):   $SavePath"
    Write-Host ""
    Write-Host "This OVERWRITES the current save files at the target with the backup."
    Write-Host "Make sure Subnautica 2 is CLOSED before continuing, or the game may"
    Write-Host "overwrite the restored files or refuse to load them."
    $confirm = Read-Host "Type 'restore' to continue (anything else aborts)"
    if ($confirm -ne "restore") {
        Fail "Aborted -- no changes were made."
    }

    # Safety net: snapshot the current live save before touching it so a bad
    # restore can be undone. Only do this if there is a non-empty save to
    # protect; if that snapshot fails, abort rather than risk losing the save.
    $trimmed = $SavePath.TrimEnd('\', '/')
    if (Test-Path $SavePath) {
        $liveContents = Get-ChildItem -Path $SavePath -Force -ErrorAction SilentlyContinue
        if ($liveContents) {
            $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $safetyDir = "$trimmed.pre-restore-$stamp"
            Write-Host "Backing up your current live save to '$safetyDir' first..."
            try {
                Copy-Item -Path $SavePath -Destination $safetyDir -Recurse -Force -ErrorAction Stop
            } catch {
                Fail "Could not create a safety copy of your current save (check permissions/disk space): $_. Aborting so nothing is overwritten."
            }
        }
    }

    # Make sure the target's parent exists (first restore on a fresh machine may
    # not have a save folder yet).
    $parent = Split-Path -Parent $SavePath
    if ($parent -and -not (Test-Path $parent)) {
        try {
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
        } catch {
            Fail "Could not create parent folder '$parent' for the save path: $_"
        }
    }

    # Stage the copy in a sibling folder (same volume as the target so the final
    # swap is a fast rename), then swap it into place.
    $staging = "$trimmed.restore-staging-$PID"
    $old = "$trimmed.old-$PID"
    if (Test-Path $staging) { Remove-Item -Path $staging -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $old) { Remove-Item -Path $old -Recurse -Force -ErrorAction SilentlyContinue }
    try {
        New-Item -ItemType Directory -Path $staging -Force -ErrorAction Stop | Out-Null
        Copy-Item -Path (Join-Path $sourceDir '*') -Destination $staging -Recurse -Force -ErrorAction Stop
    } catch {
        Remove-Item -Path $staging -Recurse -Force -ErrorAction SilentlyContinue
        Fail "Copying backup files into staging failed: $_. Your live save was NOT changed."
    }

    # Swap: move the old save aside, move staging into place, drop the old one.
    if (Test-Path $SavePath) {
        try {
            Move-Item -Path $SavePath -Destination $old -Force -ErrorAction Stop
        } catch {
            Remove-Item -Path $staging -Recurse -Force -ErrorAction SilentlyContinue
            Fail "Could not move the current save aside: $_. Your live save was NOT changed."
        }
    }
    try {
        Move-Item -Path $staging -Destination $SavePath -Force -ErrorAction Stop
    } catch {
        # Roll back to the original if the final move fails.
        if (Test-Path $old) { Move-Item -Path $old -Destination $SavePath -Force -ErrorAction SilentlyContinue }
        Remove-Item -Path $staging -Recurse -Force -ErrorAction SilentlyContinue
        Fail "Could not move the restored save into place: $_. Your original save was left untouched."
    }
    if (Test-Path $old) { Remove-Item -Path $old -Recurse -Force -ErrorAction SilentlyContinue }

    Write-Host "Restore complete. Your save was restored from backup '$($latest.Name)'."
    Write-Host "Your previous live save (if any) was preserved in a sibling '.pre-restore-*' folder in case you need to undo this."
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

# Restore has its own preflight (the save folder may legitimately be missing or
# empty when restoring onto a fresh machine), so branch off before the
# backup-specific checks below.
if ($Restore) {
    Invoke-Restore -SavePath $SavePath
    exit 0
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
