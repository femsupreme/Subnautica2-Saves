# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal backup repo for Subnautica 2 save games, not an application. The only "code" is two backup scripts (one per OS) that copy save files into this repo and push them to GitHub. Everything under `Save Backups/` is generated data, not something to hand-edit.

## Commands

Run/test a backup script locally:
```
./backup-mac.sh --configure      # (re)set SAVE_PATH in backup.config
./backup-mac.sh                  # run a backup
```
```powershell
.\backup-windows.ps1 -Configure
.\backup-windows.ps1
```

Lint (mirrors `.github/workflows/lint.yml`, which runs on push when either script or the workflow file changes):
```
shellcheck backup-mac.sh
```
```powershell
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
Invoke-ScriptAnalyzer -Path backup-windows.ps1 -Severity Warning,Error -ExcludeRule PSAvoidUsingWriteHost
```
There is no other build/test suite.

## Architecture

- `backup-mac.sh` and `backup-windows.ps1` are independent but must stay behaviorally in sync — every change to one's backup logic should be mirrored in the other. Both follow the same flow:
  1. `--configure`/`-Configure` (or missing `backup.config`) prompts for the save folder path and writes it to `backup.config` as `SAVE_PATH=...`.
  2. Preflight checks: git installed, repo present, no rebase in progress, currently on `main`, save path exists/readable/non-empty (refuses to proceed on an empty save path so it can't wipe a real backup with nothing).
  3. `git pull --rebase origin main` to sync first; aborts the rebase and exits cleanly on failure rather than leaving the repo in a conflicted state.
  4. Deletes and recreates `Save Backups/<YYYY-MM-DD>/` (today's folder is a full mirror of the save folder, not an accumulation across runs within the same day) and copies the save folder into it.
  5. `git add` that dated folder, commit as `Backup <YYYY-MM-DD>` only if there's something staged, then `git push origin main`. A failed push leaves the commit intact locally with instructions to retry.
- `backup.config` holds the real `SAVE_PATH` and is gitignored (machine-specific); `backup.config.example` is the committed template.
- `Save Backups/<date>/` folders are the actual save snapshots, one per day the backup was run, keyed by calendar date (not per-run).
- CI (`.github/workflows/lint.yml`) runs ShellCheck against `backup-mac.sh` and PSScriptAnalyzer against `backup-windows.ps1` on every push that touches either script; on failure it opens (or comments on, if one's already open) a `ci-failure`-labeled GitHub issue.
