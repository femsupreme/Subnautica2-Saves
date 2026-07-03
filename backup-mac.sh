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

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") [--configure | --restore]

  (no option)   Back up the game save folder into this repo and push it.
  --configure   (Re)set the save folder path in backup.config.
  --restore     Restore the latest backup from this repo BACK INTO the game
                save folder (the reverse of a backup). Overwrites the live save.
EOF
}

# Restore the most recent snapshot in "Save Backups/" back into the live game
# save folder. This is destructive (it replaces the current save), so it takes
# several precautions: it confirms with the user, refuses to restore from an
# empty snapshot, snapshots the current live save first, and stages the copy in
# a sibling folder and swaps it into place so an interrupted copy can never leave
# the game with a half-written save folder.
restore() {
  cd "$REPO_ROOT" || die "Could not cd into '$REPO_ROOT'."

  check_no_rebase_in_progress
  check_branch

  # Best-effort sync so we restore the newest snapshot that exists on GitHub,
  # not just whatever is on this machine. A failure here is non-fatal.
  echo "Syncing with origin/$BRANCH to get the latest backups..."
  if ! git pull --rebase origin "$BRANCH"; then
    git rebase --abort >/dev/null 2>&1 || true
    echo "Warning: could not sync with origin (network/auth problem?). Continuing with the backups already on this machine." >&2
  fi

  [[ -d "$BACKUP_ROOT" ]] || die "No 'Save Backups' folder found -- there is nothing to restore."

  # Pick the newest dated backup folder. YYYY-MM-DD names sort chronologically.
  local latest
  latest="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' -exec basename {} \; 2>/dev/null | sort | tail -n 1)"
  [[ -n "$latest" ]] || die "No dated backup folders found under '$BACKUP_ROOT' -- nothing to restore."

  local source_dir="$BACKUP_ROOT/$latest"

  # Refuse to restore from an empty snapshot -- that would wipe the live save.
  if [[ -z "$(find "$source_dir" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    die "Backup '$latest' is empty. Refusing to overwrite your live save with nothing."
  fi

  echo
  echo "About to RESTORE your Subnautica 2 save from backup '$latest'."
  echo "  Source (backup): $source_dir"
  echo "  Target (game):   $SAVE_PATH"
  echo
  echo "This OVERWRITES the current save files at the target with the backup."
  echo "Make sure Subnautica 2 is CLOSED before continuing, or the game may"
  echo "overwrite the restored files or refuse to load them."
  read -r -p "Type 'restore' to continue (anything else aborts): " confirm
  [[ "$confirm" == "restore" ]] || die "Aborted -- no changes were made."

  # Safety net: snapshot the current live save before touching it so a bad
  # restore can be undone. Only do this if there is a non-empty save to protect;
  # if that snapshot fails, abort rather than risk losing the current save.
  if [[ -d "$SAVE_PATH" && -n "$(find "$SAVE_PATH" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    local safety_dir
    safety_dir="${SAVE_PATH%/}.pre-restore-$(date +%Y%m%d-%H%M%S)"
    echo "Backing up your current live save to '$safety_dir' first..."
    if ! cp -R "$SAVE_PATH" "$safety_dir"; then
      die "Could not create a safety copy of your current save (check permissions/disk space). Aborting so nothing is overwritten."
    fi
  fi

  # Make sure the target's parent exists (first restore on a fresh machine may
  # not have a save folder yet).
  local parent
  parent="$(dirname "$SAVE_PATH")"
  mkdir -p "$parent" || die "Could not create parent folder '$parent' for the save path."

  # Stage the copy in a sibling folder (same filesystem as the target so the
  # final swap is an atomic rename), then swap it into place.
  local staging="${SAVE_PATH%/}.restore-staging-$$"
  rm -rf "$staging" 2>/dev/null || true
  mkdir -p "$staging" || die "Could not create staging folder '$staging' (check permissions or disk space)."
  if ! cp -R "$source_dir"/. "$staging"/; then
    rm -rf "$staging" 2>/dev/null || true
    die "Copying backup files into staging failed. Your live save was NOT changed."
  fi

  # Swap: move the old save aside, move staging into place, drop the old one.
  local old="${SAVE_PATH%/}.old-$$"
  rm -rf "$old" 2>/dev/null || true
  if [[ -e "$SAVE_PATH" ]]; then
    if ! mv "$SAVE_PATH" "$old"; then
      rm -rf "$staging" 2>/dev/null || true
      die "Could not move the current save aside. Your live save was NOT changed."
    fi
  fi
  if ! mv "$staging" "$SAVE_PATH"; then
    # Roll back to the original if the final move fails.
    if [[ -e "$old" ]]; then
      mv "$old" "$SAVE_PATH" 2>/dev/null || true
    fi
    rm -rf "$staging" 2>/dev/null || true
    die "Could not move the restored save into place. Your original save was left untouched."
  fi
  rm -rf "$old" 2>/dev/null || true

  echo "Restore complete. Your save was restored from backup '$latest'."
  echo "Your previous live save (if any) was preserved in a sibling '.pre-restore-*' folder in case you need to undo this."
}

MODE="backup"
DO_CONFIGURE=0
case "${1:-}" in
  --configure) DO_CONFIGURE=1 ;;
  --restore)   MODE="restore" ;;
  -h|--help)   usage; exit 0 ;;
  "")          ;;
  *)           usage; die "Unknown option '$1'." ;;
esac

require_git
require_repo

if [[ "$DO_CONFIGURE" == "1" || ! -f "$CONFIG_FILE" ]]; then
  configure
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE" || die "Could not read config file '$CONFIG_FILE'. Run with --configure."

if [[ -z "${SAVE_PATH:-}" ]]; then
  die "SAVE_PATH not set in $CONFIG_FILE. Run with --configure."
fi

# Restore has its own preflight (the save folder may legitimately be missing or
# empty when restoring onto a fresh machine), so branch off before the
# backup-specific checks below.
if [[ "$MODE" == "restore" ]]; then
  restore
  exit 0
fi

if [[ ! -d "$SAVE_PATH" ]]; then
  die "Save path '$SAVE_PATH' does not exist."
fi

if [[ ! -r "$SAVE_PATH" ]]; then
  die "Save path '$SAVE_PATH' is not readable (check permissions)."
fi

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
