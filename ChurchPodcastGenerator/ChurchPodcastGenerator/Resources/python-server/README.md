# Church Podcast — Mac App

A native macOS app that wraps the Church Podcast automation pipeline in a clean SwiftUI wizard interface. The Python backend (Flask) runs invisibly in the background; the app starts and stops it automatically.

---

## Architecture

```
ChurchPodcast/
  ├── python-server/
  │     ├── server.py           ← Flask REST API + SSE progress stream
  │     └── requirements.txt    ← Flask, yt-dlp, google-api, etc.
  │
  ├── SwiftUI/ChurchPodcast/
  │     ├── ChurchPodcast.xcodeproj
  │     └── ChurchPodcast/
  │           ├── ChurchPodcastApp.swift      ← App entry, starts server
  │           ├── Views/
  │           │     ├── ContentView.swift     ← Wizard router + step strip
  │           │     ├── Components.swift      ← Shared UI components
  │           │     ├── WelcomeView.swift     ← Mode selection
  │           │     ├── SourceView.swift      ← URL / file picker
  │           │     ├── TimestampsView.swift  ← Manual or auto-detect
  │           │     ├── MetadataView.swift    ← Title / description / privacy
  │           │     ├── ProcessingView.swift  ← Live progress bars
  │           │     ├── UploadView.swift      ← YouTube + Spotify
  │           │     ├── DoneView.swift        ← Summary + clean-up
  │           │     └── CleanView.swift       ← Delete working files
  │           ├── ViewModels/
  │           │     └── PipelineViewModel.swift ← Wizard state machine
  │           └── Services/
  │                 ├── APIService.swift      ← HTTP calls to Flask server
  │                 ├── SSEListener.swift     ← Parses live progress events
  │                 └── ServerManager.swift   ← Starts/stops Python process
  │
  ├── setup.sh                  ← One-time install (Python venv + dependencies)
  ├── client_secrets.json       ← You add this (YouTube API — see below)
  ├── podcast_output/           ← Trimmed video + MP3 saved here
  └── inbox/                    ← Drop .mp4 files here for Manual mode
```

### How the two layers communicate

```
SwiftUI  →  POST /download       →  Python starts yt-dlp subprocess
SwiftUI  ←  GET  /events (SSE)   ←  Python streams progress %  back
SwiftUI  →  POST /trim           →  Python runs ffmpeg
SwiftUI  ←  GET  /events (SSE)   ←  ffmpeg time position → progress bar
SwiftUI  →  POST /youtube/upload →  Python calls YouTube Data API v3
SwiftUI  ←  GET  /events (SSE)   ←  upload chunk % streamed back
```

---

## One-Time Setup

### 1. Install backend dependencies

```bash
chmod +x setup.sh
./setup.sh
```

This creates a `.venv` Python virtual environment and installs Flask, yt-dlp, ffmpeg wrappers, and the Google API client.

> **Requires:** Python 3.10+ and ffmpeg — install both with `brew install python@3.12 ffmpeg`

### 2. Add YouTube API credentials

Follow the YouTube API Setup steps in the original `church-podcast-automation` README to create a `client_secrets.json`, then place it in **this folder** (the repo root, next to `setup.sh`).

### 3. Open in Xcode

```bash
open SwiftUI/ChurchPodcast/ChurchPodcast.xcodeproj
```

Press **⌘R** to build and run. The app starts the Python server automatically on launch.

---

## Running the Server Manually (optional)

If you want to test the API without the app:

```bash
.venv/bin/python python-server/server.py
```

Then open a browser to `http://localhost:5001/status` — you should see `{"ok": true}`.

All API endpoints are documented in `server.py` with inline comments.

---

## Wizard Flow

```
Welcome → Source → Timestamps → Metadata → Processing → Upload → Done
                                                              ↓
                                                           Clean (optional)
```

| Step | What happens |
|---|---|
| Welcome | Choose Auto (download from YT) or Manual (local file) |
| Source | Paste URL / fetch latest, or pick a file from inbox/ |
| Timestamps | Type start/end, or click Scan to auto-detect from silence |
| Metadata | Episode title, description, YouTube privacy |
| Processing | Live progress bars for download → trim → MP3 export |
| Upload | Pick YouTube channel, upload, then open Spotify for Podcasters |
| Done | Summary of all output files + optional clean-up |

---

## API Endpoints Quick Reference

| Method | Path | Description |
|---|---|---|
| GET | `/status` | Health check |
| GET | `/config` | Read current config values |
| POST | `/config` | Update config values at runtime |
| GET | `/events` | SSE stream — subscribe for live progress |
| POST | `/download` | Start yt-dlp download (`{"url": "..."}`) |
| POST | `/detect-timestamps` | Run silence detection (`{"filepath": "..."}`) |
| POST | `/trim` | Trim + normalize (`{"filepath","start","end","label"}`) |
| POST | `/export-audio` | Export MP3 (`{"filepath","label"}`) |
| GET | `/youtube/channels` | List channels for the authenticated account |
| POST | `/youtube/upload` | Upload to YouTube (`{"filepath","title","description","privacy"}`) |
| POST | `/spotify/open` | Copy path to clipboard + open Spotify |
| GET | `/clean/list` | List deletable files with sizes |
| POST | `/clean/delete` | Delete files (`{"paths": [...]}`) |
| GET | `/inbox/files` | List .mp4 files in inbox/ |
| GET | `/output/files` | List processed files in podcast_output/ |

---

## Troubleshooting

| Problem | Solution |
|---|---|
| "Backend ready" never appears | Run `setup.sh` first; check `.venv` exists |
| Server starts but upload fails | Delete `youtube_token.json` from repo root and re-run |
| Download fails in the app | Same cookie/Full Disk Access requirements as the CLI tool |
| Xcode won't build | Make sure deployment target is macOS 13.0+ in project settings |
| Progress bars don't update | SSE connection dropped — restart the app |
| App can't find server.py | The app walks up from its bundle path; keep the Xcode project inside this repo folder |

---

## Requirements

- macOS 13 Ventura or later
- Xcode 15+
- Python 3.10+ (`brew install python@3.12`)
- ffmpeg (`brew install ffmpeg`)
- YouTube `client_secrets.json` for upload features
