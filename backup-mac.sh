#!/usr/bin/env bash
# Backs up the configured Subnautica 2 save folder into this repo and pushes it to main.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$REPO_ROOT/backup.config"
BACKUP_ROOT="$REPO_ROOT/Save Backups"
BRANCH="main"

die() {
  echo "Error: $*" >&2
  exit 1
}

require_git() {
  command -v git >/dev/null 2>&1 || die "git is not installed or not on PATH."
}

require_repo() {
  git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "'$REPO_ROOT' is not a git repository."
}

check_no_rebase_in_progress() {
  if [[ -d "$REPO_ROOT/.git/rebase-merge" || -d "$REPO_ROOT/.git/rebase-apply" ]]; then
    die "A previous git rebase is still in progress in this repo. Run 'git status' in $REPO_ROOT, resolve it (or 'git rebase --abort'), then try again."
  fi
}

check_branch() {
  local current
  current="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if [[ "$current" != "$BRANCH" ]]; then
    die "Expected to be on branch '$BRANCH' but on '$current'. Switch to '$BRANCH' before backing up."
  fi
}

configure() {
  read -r -p "Enter the full path to your Subnautica 2 save folder: " save_path
  save_path="${save_path/#\~/$HOME}"
  # Un-escape backslash-escaped spaces/special chars (e.g. pasted from a
  # shell-escaped path) -- real Mac/Linux paths never contain literal backslashes.
  save_path="${save_path//\\/}"

  [[ -n "$save_path" ]] || die "No path entered."

  if [[ ! -d "$save_path" ]]; then
    echo "Warning: '$save_path' does not exist yet. Saving anyway." >&2
  fi

  printf 'SAVE_PATH=%q\n' "$save_path" > "$CONFIG_FILE" \
    || die "Could not write config file '$CONFIG_FILE' (check permissions)."
  echo "Saved save location to $CONFIG_FILE"
}

require_git
require_repo

if [[ "${1:-}" == "--configure" || ! -f "$CONFIG_FILE" ]]; then
  configure
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE" || die "Could not read config file '$CONFIG_FILE'. Run with --configure."

if [[ -z "${SAVE_PATH:-}" ]]; then
  die "SAVE_PATH not set in $CONFIG_FILE. Run with --configure."
fi

if [[ ! -d "$SAVE_PATH" ]]; then
  die "Save path '$SAVE_PATH' does not exist."
fi

if [[ ! -r "$SAVE_PATH" ]]; then
  die "Save path '$SAVE_PATH' is not readable (check permissions)."
fi

echo Round 3 live test: checking $SAVE_PATH

if [[ -z "$(find "$SAVE_PATH" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
  die "Save path '$SAVE_PATH' is empty. Refusing to wipe today's backup with nothing -- check the path and that Subnautica 2 has actually written a save."
fi

cd "$REPO_ROOT" || die "Could not cd into '$REPO_ROOT'."

check_no_rebase_in_progress
check_branch

echo "Syncing with origin/main before backing up..."
if ! git pull --rebase origin "$BRANCH"; then
  git rebase --abort >/dev/null 2>&1 || true
  die "git pull --rebase failed and was aborted to leave the repo clean. This is usually a network problem or the remote rejecting your credentials -- check your connection and GitHub access, then try again."
fi

DATE_STAMP="$(date +%Y-%m-%d)"
DEST="$BACKUP_ROOT/$DATE_STAMP"

# Rebuild the destination each run so the backup is a true mirror of the
# save folder, not an accumulation of stale files from earlier runs today.
rm -rf "$DEST" || die "Could not remove old backup folder '$DEST' (check permissions)."
mkdir -p "$DEST" || die "Could not create backup folder '$DEST' (check permissions or free disk space)."

echo "Copying save files from '$SAVE_PATH' to '$DEST'..."
if ! cp -R "$SAVE_PATH"/. "$DEST"/; then
  die "Copying save files failed (check permissions on the save folder and available disk space). No commit was made."
fi

git add "Save Backups/$DATE_STAMP" || die "git add failed."

if git diff --cached --quiet; then
  echo "No changes to back up today."
  exit 0
fi

if ! git commit -m "Backup $DATE_STAMP"; then
  die "git commit failed. If this is a fresh machine, git may need identity config: git config --global user.name \"Your Name\" && git config --global user.email \"you@example.com\""
fi

echo "Pushing to main..."
if ! git push origin "$BRANCH"; then
  die "git push failed -- most likely a permissions/auth problem with the GitHub remote (check your credentials or SSH key access to this repo). Your backup was already committed locally and is safe; fix access and re-run this script, or run 'git push origin main' manually."
fi

echo "Backup complete for $DATE_STAMP."
