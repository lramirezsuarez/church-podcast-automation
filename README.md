# Church Podcast Automation — Setup Guide

## What This Script Does

Every Monday, run one command and it will:
1. Download this week's live broadcast from YouTube
2. Ask you for the sermon start/end times, then trim the video
3. Boost and normalize the audio volume automatically
4. Save a trimmed `.mp4` video and a `.mp3` audio file
5. Re-upload the trimmed video to your YouTube channel
6. Open Spotify for Podcasters in your browser, ready for upload

---

## Requirements

### 1. Install Python dependencies
```bash
pip install yt-dlp google-auth google-auth-oauthlib google-api-python-client requests tqdm
```

### 2. Install ffmpeg

**macOS:**
```bash
brew install ffmpeg
```

**Windows:**  
Download from https://ffmpeg.org/download.html and add to your PATH.

**Linux (Ubuntu/Debian):**
```bash
sudo apt install ffmpeg
```

Verify it works: `ffmpeg -version`

---

## YouTube API Setup (for re-upload to your channel)

This only needs to be done once.

1. Go to: https://console.cloud.google.com
2. Create a new project (e.g. "Church Podcast")
3. Enable the **YouTube Data API v3**  
   (APIs & Services → Library → search "YouTube Data API v3" → Enable)
4. Create credentials:  
   APIs & Services → Credentials → Create Credentials → **OAuth 2.0 Client ID**
   - Application type: **Desktop app**
   - Download the JSON file
5. Rename the downloaded file to **`client_secrets.json`** and place it in the same folder as the script
6. The first time you run the script, a browser window will open asking you to log in with your Google account that owns the channel. After that, the script saves a token and won't ask again.

---

## First-Time Configuration

Open `church_podcast_automation.py` in any text editor and update the `CONFIG` block near the top:

```python
CONFIG = {
    "output_dir": "./podcast_output",        # Where to save files
    "youtube_channel_id": "UCxxxxxxxxxx",    # Your channel ID
    "youtube_privacy": "public",             # or "unlisted" / "private"
    "podcast_title_prefix": "Sermón —",      # Customize to your language
    "podcast_description": "...",            # Default episode description
    ...
}
```

**Finding your Channel ID:**  
Go to https://www.youtube.com/account_advanced while logged in → copy "Channel ID"

---

## Weekly Usage (Every Monday)

### Option A — Paste the URL manually (simplest)
```bash
python church_podcast_automation.py
```
It will prompt you for the URL, start time, and end time.

### Option B — Provide everything upfront (fastest)
```bash
python church_podcast_automation.py \
  --url "https://www.youtube.com/watch?v=XXXXXXX" \
  --start 00:32:15 \
  --end 01:18:40 \
  --title "Sermon — January 14, 2025"
```

### Option C — Auto-fetch the latest video from your channel
```bash
python church_podcast_automation.py --latest
```

### Other useful flags
| Flag | Description |
|---|---|
| `--file path/to/video.mp4` | Skip download, use a local file |
| `--no-youtube-upload` | Skip re-uploading to YouTube |
| `--no-podcast-upload` | Skip opening Spotify for Podcasters |
| `--privacy unlisted` | Upload as unlisted instead of public |

---

## Spotify for Podcasters — Upload Note

Spotify for Podcasters (formerly Anchor) **does not have a public API** for episode uploads. The script handles this by:

1. Opening the Spotify for Podcasters "New Episode" page in your browser automatically
2. Copying the audio file path to your clipboard
3. You just drag-and-drop the `.mp3` file and fill in the title

The whole manual step takes about 30 seconds. There is no fully automated alternative unless you self-host an RSS feed (see Advanced section below).

---

## Output Files

All files are saved in `./podcast_output/`:
```
podcast_output/
  ├── Service Title [videoID].mp4     ← original full download
  ├── 2025-01-14_sermon.mp4           ← trimmed + normalized video
  └── 2025-01-14_sermon.mp3           ← podcast audio
```

---

## Advanced: Fully Automated RSS Feed for Podcast Upload

If you want to skip the manual Spotify upload step entirely, you can:
1. Host the `.mp3` files on a web server or cloud storage (e.g., AWS S3, Google Cloud Storage, Cloudflare R2)
2. Generate and update an RSS feed file automatically
3. In Spotify for Podcasters: Settings → Distribution → connect your RSS feed URL

Spotify will auto-import new episodes within ~15 minutes of the RSS feed updating.
Ask for the RSS feed generator add-on if you'd like this feature added to the script.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| `yt-dlp: command not found` | Run `pip install yt-dlp` |
| `ffmpeg: command not found` | Install ffmpeg (see above) |
| YouTube upload fails with auth error | Delete `youtube_token.json` and re-run to re-authenticate |
| Download fails / private video | Make sure the live broadcast is published and public |
| Audio still too quiet | Lower the `loudness_target` in CONFIG to `-12` or `-10` |
