#!/usr/bin/env bash
# Backs up the configured Subnautica 2 save folder into this repo and pushes it to main.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$REPO_ROOT/backup.config"
BACKUP_ROOT="$REPO_ROOT/Save Backups"

configure() {
  read -r -p "Enter the full path to your Subnautica 2 save folder: " save_path
  save_path="${save_path/#\~/$HOME}"
  # Un-escape backslash-escaped spaces/special chars (e.g. pasted from a
  # shell-escaped path) -- real Mac/Linux paths never contain literal backslashes.
  save_path="${save_path//\\/}"
  if [[ ! -d "$save_path" ]]; then
    echo "Warning: '$save_path' does not exist yet. Saving anyway." >&2
  fi
  printf 'SAVE_PATH=%q\n' "$save_path" > "$CONFIG_FILE"
  echo "Saved save location to $CONFIG_FILE"
}

if [[ "${1:-}" == "--configure" || ! -f "$CONFIG_FILE" ]]; then
  configure
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

if [[ -z "${SAVE_PATH:-}" ]]; then
  echo "Error: SAVE_PATH not set in $CONFIG_FILE. Run with --configure." >&2
  exit 1
fi

if [[ ! -d "$SAVE_PATH" ]]; then
  echo "Error: save path '$SAVE_PATH' does not exist." >&2
  exit 1
fi

cd "$REPO_ROOT"

echo "Syncing with origin/main before backing up..."
git pull --rebase origin main

DATE_STAMP="$(date +%Y-%m-%d)"
DEST="$BACKUP_ROOT/$DATE_STAMP"

# Rebuild the destination each run so the backup is a true mirror of the
# save folder, not an accumulation of stale files from earlier runs today.
rm -rf "$DEST"
mkdir -p "$DEST"

echo "Copying save files from '$SAVE_PATH' to '$DEST'..."
cp -R "$SAVE_PATH"/. "$DEST"/

git add "Save Backups/$DATE_STAMP"

if git diff --cached --quiet; then
  echo "No changes to back up today."
  exit 0
fi

git commit -m "Backup $DATE_STAMP"

echo "Pushing to main..."
git push origin main

echo "Backup complete for $DATE_STAMP."
