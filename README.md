# Subnautica 2 Saves

Backup repo for Subnautica 2 saves.

## Script Setup (one-time per machine, rerun as needed)

**Mac:**
```
./backup-mac.sh --configure
```

**Windows:**
```
.\backup-windows.ps1 -Configure
```

You'll be asked for the full path to your Subnautica 2 save folder. It's saved to a local `backup.config` file that's gitignored.

## Running a backup

**Mac:**
```
./backup-mac.sh
```

**Windows:**
```
.\backup-windows.ps1
```

This pulls the latest, copies today's saves into `Save Backups/YYYY-MM-DD/`, commits, and pushes. If nothing changed since your last backup today, no commit is created.

## Restoring a save (import)

This is the reverse of a backup: it takes the most recent snapshot in `Save Backups/` and writes it **back into** your game save folder. Use it to move your save to a new machine or roll back after a bad save.

**Mac:**
```
./backup-mac.sh --restore
```

**Windows:**
```
.\backup-windows.ps1 -Restore
```

It syncs with GitHub first (so you get the newest snapshot), then asks you to type `restore` to confirm before overwriting anything. **Close Subnautica 2 first** so the game doesn't overwrite the restored files.

Safety measures so a restore can't corrupt your save:

- It refuses to restore from an empty snapshot (which would wipe your live save).
- It copies your current live save to a sibling `*.pre-restore-*` folder before touching it, so you can undo.
- It stages the copy in a temporary folder and swaps it into place, so an interrupted copy never leaves a half-written save folder.
