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
