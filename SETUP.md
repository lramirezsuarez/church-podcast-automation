# ⚡ Quick Setup — Read This First

## The app shows "server.py not found" error?

This means you need to rebuild after running setup.sh.
The app needs `.venv/` and `python-server/` copied into its bundle by Xcode.

## Correct order (must follow exactly):

```
1.  cd ChurchPodcast/          ← project folder

2.  chmod +x setup.sh
    ./setup.sh                 ← creates .venv/ with all Python packages

3.  open ChurchPodcast.xcodeproj

4.  In Xcode: Product → Clean Build Folder   (⌘⇧K)

5.  Press ⌘R to run
```

**Why Clean Build Folder?**
Xcode only copies `.venv/` and `python-server/` into the app bundle
during a build. If you opened Xcode before running `setup.sh`,
the `.venv/` folder didn't exist yet and wasn't copied.
Cleaning forces a fresh copy.

## Where does user data go?

Output files, inbox, and credentials are stored in:
```
~/Library/Application Support/ChurchPodcast/
    inbox/                  ← drop .mp4 files here for Manual mode
    podcast_output/         ← trimmed video and MP3 saved here
    client_secrets.json     ← copy your YouTube API credentials here
    youtube_token.json      ← auto-created after first YouTube login
```
