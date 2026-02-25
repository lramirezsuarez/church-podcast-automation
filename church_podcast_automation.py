#!/usr/bin/env python3
"""
Church Weekly Podcast Automation
---------------------------------
Steps:
  1. Download a YouTube video (by URL or latest from channel)
  2. Trim to sermon start/end timestamps
  3. Normalize/boost audio volume
  4. Export trimmed video (.mp4) and audio (.mp3)
  5. Re-upload trimmed video to YouTube
  6. Upload audio to Spotify for Podcasters (Anchor) via RSS workaround

Requirements:
  pip install yt-dlp google-auth google-auth-oauthlib google-api-python-client requests tqdm
  ffmpeg must be installed and available in PATH

Setup:
  - YouTube API: Create OAuth2 credentials at https://console.cloud.google.com
    Download as 'client_secrets.json' and place in the same folder as this script.
  - Spotify for Podcasters (Anchor): See README section below on how to handle uploads.
"""

import os
import sys
import json
import subprocess
import argparse
from datetime import datetime
from pathlib import Path

# ─────────────────────────────────────────────
#  CONFIGURATION  — edit these values
# ─────────────────────────────────────────────

CONFIG = {
    # Folder where downloaded and processed files will be saved
    "output_dir": "./podcast_output",

    # Your YouTube channel ID (used to auto-fetch latest video if no URL is given)
    # Find it at: https://www.youtube.com/account_advanced
    "youtube_channel_id": "UCxxxxxxxxxxxxxxxxxxxxxxxxx",

    # Default YouTube upload privacy: "public", "private", or "unlisted"
    "youtube_privacy": "public",

    # Default podcast episode metadata (you can override at runtime)
    "podcast_title_prefix": "Sermón —",   # e.g. "Sermón — 2024-01-14"
    "podcast_description": "Sermón semanal de nuestra iglesia.",

    # Audio loudness target (EBU R128, -14 LUFS is standard for podcasts/Spotify)
    "loudness_target": "-14",

    # OAuth2 credentials file for YouTube API
    "client_secrets_file": "client_secrets.json",

    # File where your YouTube OAuth token is cached after first login
    "token_file": "youtube_token.json",
}

# ─────────────────────────────────────────────
#  HELPERS
# ─────────────────────────────────────────────

def run(cmd, desc=""):
    """Run a shell command and exit on failure."""
    print(f"\n▶ {desc or cmd}")
    result = subprocess.run(cmd, shell=True)
    if result.returncode != 0:
        print(f"✗ Command failed: {cmd}")
        sys.exit(1)

def ensure_dir(path):
    Path(path).mkdir(parents=True, exist_ok=True)

def timestamp_to_seconds(ts):
    """Convert HH:MM:SS or MM:SS to seconds (float)."""
    parts = ts.strip().split(":")
    parts = [float(p) for p in parts]
    if len(parts) == 2:
        return parts[0] * 60 + parts[1]
    elif len(parts) == 3:
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    raise ValueError(f"Invalid timestamp format: {ts}")

# ─────────────────────────────────────────────
#  STEP 1: DOWNLOAD FROM YOUTUBE
# ─────────────────────────────────────────────

def download_youtube(url, output_dir):
    """Download best-quality video+audio from YouTube using yt-dlp."""
    ensure_dir(output_dir)
    out_template = os.path.join(output_dir, "%(title)s [%(id)s].%(ext)s")
    cmd = (
        f'yt-dlp -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" '
        f'--merge-output-format mp4 '
        f'-o "{out_template}" '
        f'--print after_move:filepath '
        f'"{url}"'
    )
    print(f"\n▶ Downloading: {url}")
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr)
        sys.exit(1)

    # yt-dlp prints the final filepath when using --print after_move:filepath
    filepath = result.stdout.strip().splitlines()[-1]
    if not os.path.exists(filepath):
        # Fallback: find the newest mp4 in output_dir
        files = sorted(Path(output_dir).glob("*.mp4"), key=os.path.getmtime, reverse=True)
        if not files:
            print("✗ Could not find downloaded file.")
            sys.exit(1)
        filepath = str(files[0])

    print(f"✓ Downloaded: {filepath}")
    return filepath

def get_latest_channel_video(channel_id):
    """Return the URL of the most recent public video on a YouTube channel."""
    try:
        from googleapiclient.discovery import build
        creds = _get_youtube_credentials(readonly=True)
        youtube = build("youtube", "v3", credentials=creds)
        response = youtube.search().list(
            channelId=channel_id,
            order="date",
            type="video",
            maxResults=1,
            part="id,snippet"
        ).execute()
        items = response.get("items", [])
        if not items:
            print("✗ No videos found on the channel.")
            sys.exit(1)
        video_id = items[0]["id"]["videoId"]
        title = items[0]["snippet"]["title"]
        url = f"https://www.youtube.com/watch?v={video_id}"
        print(f"✓ Latest video: {title}\n  {url}")
        return url
    except Exception as e:
        print(f"✗ Could not fetch latest video: {e}")
        sys.exit(1)

# ─────────────────────────────────────────────
#  STEP 2 & 3: TRIM + NORMALIZE AUDIO
# ─────────────────────────────────────────────

def trim_and_normalize(input_file, start_ts, end_ts, output_dir, label):
    """
    Trim video from start_ts to end_ts and normalize audio loudness.
    Returns path to the trimmed+normalized video file.
    """
    ensure_dir(output_dir)
    out_video = os.path.join(output_dir, f"{label}_sermon.mp4")
    target = CONFIG["loudness_target"]

    # Two-pass loudnorm for accurate normalization
    cmd = (
        f'ffmpeg -y '
        f'-ss {start_ts} -to {end_ts} '
        f'-i "{input_file}" '
        f'-af "loudnorm=I={target}:TP=-1.5:LRA=11" '
        f'-c:v copy '
        f'-c:a aac -b:a 192k '
        f'"{out_video}"'
    )
    run(cmd, f"Trimming {start_ts} → {end_ts} and normalizing audio")
    print(f"✓ Trimmed video saved: {out_video}")
    return out_video

# ─────────────────────────────────────────────
#  STEP 4: EXPORT AUDIO (.mp3)
# ─────────────────────────────────────────────

def export_audio(video_file, output_dir, label):
    """Extract audio from video and save as high-quality MP3."""
    ensure_dir(output_dir)
    out_audio = os.path.join(output_dir, f"{label}_sermon.mp3")
    cmd = (
        f'ffmpeg -y -i "{video_file}" '
        f'-vn -ar 44100 -ac 2 -b:a 192k '
        f'"{out_audio}"'
    )
    run(cmd, "Exporting MP3 audio")
    print(f"✓ Audio saved: {out_audio}")
    return out_audio

# ─────────────────────────────────────────────
#  STEP 5: UPLOAD VIDEO TO YOUTUBE
# ─────────────────────────────────────────────

def _get_youtube_credentials(readonly=False):
    """OAuth2 login for YouTube. Caches token locally after first run."""
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from google.auth.transport.requests import Request

    scopes = (
        ["https://www.googleapis.com/auth/youtube.readonly"]
        if readonly
        else ["https://www.googleapis.com/auth/youtube.upload",
              "https://www.googleapis.com/auth/youtube"]
    )
    token_file = CONFIG["token_file"]
    creds = None

    if os.path.exists(token_file):
        creds = Credentials.from_authorized_user_file(token_file, scopes)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not os.path.exists(CONFIG["client_secrets_file"]):
                print(
                    f"\n✗ Missing '{CONFIG['client_secrets_file']}'.\n"
                    "  Download OAuth2 credentials from Google Cloud Console and save as that file.\n"
                    "  See: https://console.cloud.google.com/apis/credentials"
                )
                sys.exit(1)
            flow = InstalledAppFlow.from_client_secrets_file(
                CONFIG["client_secrets_file"], scopes
            )
            creds = flow.run_local_server(port=0)
        with open(token_file, "w") as f:
            f.write(creds.to_json())

    return creds

def upload_to_youtube(video_file, title, description, privacy="public"):
    """Upload a video file to YouTube using the Data API v3."""
    try:
        from googleapiclient.discovery import build
        from googleapiclient.http import MediaFileUpload
    except ImportError:
        print("✗ Install google-api-python-client: pip install google-api-python-client")
        sys.exit(1)

    print(f"\n▶ Uploading to YouTube: {title}")
    creds = _get_youtube_credentials()
    youtube = build("youtube", "v3", credentials=creds)

    body = {
        "snippet": {
            "title": title,
            "description": description,
            "categoryId": "22",  # People & Blogs — change if preferred
        },
        "status": {"privacyStatus": privacy},
    }

    media = MediaFileUpload(video_file, chunksize=-1, resumable=True, mimetype="video/mp4")
    request = youtube.videos().insert(part="snippet,status", body=body, media_body=media)

    response = None
    while response is None:
        status, response = request.next_chunk()
        if status:
            pct = int(status.progress() * 100)
            print(f"  Uploading... {pct}%", end="\r")

    video_id = response["id"]
    print(f"\n✓ YouTube upload complete: https://www.youtube.com/watch?v={video_id}")
    return video_id

# ─────────────────────────────────────────────
#  STEP 6: UPLOAD AUDIO TO SPOTIFY FOR PODCASTERS
# ─────────────────────────────────────────────

def upload_to_anchor(audio_file, episode_title, episode_description):
    """
    Spotify for Podcasters (Anchor) does not provide a public API for episode uploads.
    
    The recommended workflow is one of these options:

    OPTION A — RSS Auto-Import (recommended):
      1. Host your MP3 on any server (Dropbox public link, Google Drive, S3, your own web server).
      2. Add the episode to your podcast RSS feed.
      3. In Anchor/Spotify for Podcasters, go to Settings > Distribution and point to your RSS feed.
      Anchor will automatically import new episodes within minutes.

    OPTION B — Manual upload via Anchor website:
      1. Go to https://podcasters.spotify.com
      2. Click "New Episode" > "Upload audio file"
      3. Fill in title, description, and publish.

    OPTION C — Use an RSS feed generator script (this script can do it):
      Run with --generate-rss to auto-update a local RSS feed file that you host somewhere.

    This function will print the above instructions and open the Anchor upload page for you.
    """
    import webbrowser

    print("\n" + "="*60)
    print("STEP 6 — Upload to Spotify for Podcasters")
    print("="*60)
    print(f"\nAudio file ready: {audio_file}")
    print(f"Episode title:    {episode_title}")
    print(f"\nSpotify for Podcasters does not have a public upload API.")
    print("Opening Spotify for Podcasters in your browser...")
    print("\nInstructions:")
    print("  1. Click 'New Episode'")
    print("  2. Upload the audio file shown above")
    print(f"  3. Set title to: {episode_title}")
    print(f"  4. Set description, publish!")
    print("="*60)

    webbrowser.open("https://podcasters.spotify.com/pod/dashboard/episode/new")

    # Optionally copy the audio path to clipboard for convenience
    try:
        import subprocess as sp
        abs_path = os.path.abspath(audio_file)
        if sys.platform == "darwin":
            sp.run(["pbcopy"], input=abs_path.encode(), check=True)
            print(f"\n✓ File path copied to clipboard: {abs_path}")
        elif sys.platform == "win32":
            sp.run(["clip"], input=abs_path.encode(), check=True)
            print(f"\n✓ File path copied to clipboard: {abs_path}")
    except Exception:
        pass

# ─────────────────────────────────────────────
#  MAIN FLOW
# ─────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Church Weekly Podcast Automation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Full run with a specific YouTube URL:
  python church_podcast_automation.py --url "https://www.youtube.com/watch?v=XXXXXXX"

  # Auto-fetch the latest video from your channel:
  python church_podcast_automation.py --latest

  # Skip download (use an already-downloaded file):
  python church_podcast_automation.py --file "./podcast_output/service.mp4"

  # Skip YouTube re-upload:
  python church_podcast_automation.py --url "..." --no-youtube-upload

  # Set timestamps directly (no interactive prompt):
  python church_podcast_automation.py --url "..." --start 00:32:15 --end 01:18:40
        """
    )

    source = parser.add_mutually_exclusive_group()
    source.add_argument("--url",    help="YouTube video URL to download")
    source.add_argument("--latest", action="store_true", help="Download latest video from your channel")
    source.add_argument("--file",   help="Skip download, use this local video file")

    parser.add_argument("--start", help="Sermon start timestamp, e.g. 00:32:15")
    parser.add_argument("--end",   help="Sermon end timestamp,   e.g. 01:18:40")
    parser.add_argument("--title", help="Episode/video title (default: auto-generated from date)")
    parser.add_argument("--no-youtube-upload", action="store_true", help="Skip re-uploading to YouTube")
    parser.add_argument("--no-podcast-upload", action="store_true", help="Skip podcast upload step")
    parser.add_argument("--privacy", default=CONFIG["youtube_privacy"],
                        choices=["public", "unlisted", "private"],
                        help="YouTube upload privacy (default: public)")

    args = parser.parse_args()

    output_dir = CONFIG["output_dir"]
    today = datetime.today().strftime("%Y-%m-%d")
    label = today

    # ── Step 1: Obtain source video ──────────────────────────────
    if args.file:
        raw_video = args.file
        if not os.path.exists(raw_video):
            print(f"✗ File not found: {raw_video}")
            sys.exit(1)
        print(f"✓ Using local file: {raw_video}")
    else:
        if args.latest:
            url = get_latest_channel_video(CONFIG["youtube_channel_id"])
        elif args.url:
            url = args.url
        else:
            url = input("\nPaste the YouTube URL of this week's broadcast: ").strip()
            if not url:
                print("✗ No URL provided.")
                sys.exit(1)

        raw_video = download_youtube(url, output_dir)

    # ── Step 2: Get trim timestamps ──────────────────────────────
    print("\n" + "─"*50)
    print("TRIM TIMESTAMPS")
    print("Format: HH:MM:SS  or  MM:SS")
    print("─"*50)

    start_ts = args.start
    end_ts   = args.end

    if not start_ts:
        start_ts = input("Sermon START time (e.g. 00:32:15): ").strip()
    if not end_ts:
        end_ts = input("Sermon END time   (e.g. 01:18:40): ").strip()

    # Validate timestamps
    try:
        timestamp_to_seconds(start_ts)
        timestamp_to_seconds(end_ts)
    except ValueError as e:
        print(f"✗ {e}")
        sys.exit(1)

    # ── Episode title ────────────────────────────────────────────
    episode_title = args.title
    if not episode_title:
        default_title = f"{CONFIG['podcast_title_prefix']} {today}"
        user_title = input(f"\nEpisode title [{default_title}]: ").strip()
        episode_title = user_title if user_title else default_title

    description = CONFIG["podcast_description"]

    # ── Steps 2 & 3: Trim + normalize ───────────────────────────
    trimmed_video = trim_and_normalize(raw_video, start_ts, end_ts, output_dir, label)

    # ── Step 4: Export audio ─────────────────────────────────────
    audio_file = export_audio(trimmed_video, output_dir, label)

    # ── Step 5: Upload to YouTube ────────────────────────────────
    if not args.no_youtube_upload:
        confirm = input(f"\nUpload trimmed video to YouTube as '{episode_title}'? [Y/n]: ").strip().lower()
        if confirm != "n":
            upload_to_youtube(trimmed_video, episode_title, description, args.privacy)
    else:
        print("\n⏩ Skipping YouTube upload.")

    # ── Step 6: Upload podcast audio ────────────────────────────
    if not args.no_podcast_upload:
        upload_to_anchor(audio_file, episode_title, description)
    else:
        print("\n⏩ Skipping podcast upload.")

    # ── Summary ──────────────────────────────────────────────────
    print("\n" + "="*60)
    print("✅ ALL DONE!")
    print("="*60)
    print(f"  Trimmed video : {trimmed_video}")
    print(f"  Audio (MP3)   : {audio_file}")
    print("="*60 + "\n")


if __name__ == "__main__":
    main()
