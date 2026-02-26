#!/usr/bin/env python3
"""
Church Weekly Podcast Automation
---------------------------------
Two modes:

  MODE A — Auto (full pipeline):
    Downloads the broadcast from YouTube using browser cookies,
    trims, normalizes, re-uploads the sermon clip to YouTube,
    and opens Spotify for Podcasters for the audio upload.

  MODE B — Manual (local file):
    Uses a .mp4 you already downloaded, trims and normalizes it,
    saves the trimmed video and MP3 to podcast_output/, and
    opens Spotify for Podcasters. YouTube upload is skipped.

Run: ./run.sh
"""

import os
import sys
import subprocess
import argparse
from datetime import datetime
from pathlib import Path

# ── Python version guard ──────────────────────────────────────────
if sys.version_info < (3, 10):
    print(
        f"\n✗ Python {sys.version_info.major}.{sys.version_info.minor} detected — "
        "Python 3.10+ is required.\n"
        "  Run ./setup.sh to fix this, then use ./run.sh to launch the script.\n"
    )
    sys.exit(1)

# ─────────────────────────────────────────────
#  CONFIGURATION  — edit these values
# ─────────────────────────────────────────────

CONFIG = {
    # Where processed files (trimmed video + mp3) are saved
    "output_dir": "./podcast_output",

    # Drop manually downloaded .mp4 files here for Mode B
    "inbox_dir": "./inbox",

    # Your YouTube channel ID — used in Mode A to auto-fetch latest video
    # Find it at: https://www.youtube.com/account_advanced
    "youtube_channel_id": "UCxxxxxxxxxxxxxxxxxxxxxxxxx",

    # YouTube upload privacy for the trimmed sermon clip
    "youtube_privacy": "private",   # "public" | "unlisted" | "private"

    # Default episode metadata (can be overridden at runtime)
    "podcast_title_prefix": "Predicación —",
    "podcast_description":  "Predicación semanal de nuestra iglesia.",

    # Audio loudness target (EBU R128 — -14 LUFS is Spotify's standard)
    "loudness_target": "-14",

    # YouTube OAuth2 credentials (see README for setup instructions)
    "client_secrets_file": "client_secrets.json",
    "token_file":          "youtube_token.json",
}

# ─────────────────────────────────────────────
#  HELPERS
# ─────────────────────────────────────────────

def ensure_dir(path):
    Path(path).mkdir(parents=True, exist_ok=True)

def timestamp_to_seconds(ts):
    """Convert HH:MM:SS or MM:SS to seconds."""
    parts = ts.strip().split(":")
    parts = [float(p) for p in parts]
    if len(parts) == 2:
        return parts[0] * 60 + parts[1]
    elif len(parts) == 3:
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    raise ValueError(f"Invalid timestamp '{ts}' — use HH:MM:SS or MM:SS")

def find_latest_mp4(folder):
    """Return the most recently modified .mp4 in a folder, or None."""
    files = sorted(Path(folder).glob("*.mp4"), key=os.path.getmtime, reverse=True)
    return str(files[0]) if files else None

def separator(char="─", width=56):
    print(char * width)

def ask_timestamps(args):
    """Prompt for start/end timestamps and validate them."""
    separator()
    print("TRIM TIMESTAMPS  (format: HH:MM:SS or MM:SS)")
    separator()
    start_ts = args.start or input("Sermon START time (e.g. 00:32:15): ").strip()
    end_ts   = args.end   or input("Sermon END time   (e.g. 01:18:40): ").strip()
    try:
        timestamp_to_seconds(start_ts)
        timestamp_to_seconds(end_ts)
    except ValueError as e:
        print(f"✗ {e}")
        sys.exit(1)
    return start_ts, end_ts

def ask_episode_title(args, today):
    """Prompt for episode title with a sensible default."""
    if args.title:
        return args.title
    default = f"{CONFIG['podcast_title_prefix']} {today}"
    typed = input(f"\nEpisode title [{default}]: ").strip()
    return typed if typed else default

def select_mode():
    """
    Show a mode-selection menu and return "A" or "B".
    Can be bypassed with --mode A|B on the command line.
    """
    print()
    separator("═")
    print("  Church Podcast Automation")
    separator("═")
    print()
    print("  Select a mode:\n")
    print("  [A] Auto      — Download from YouTube, trim, re-upload sermon")
    print("                  clip to YouTube & open Spotify for Podcasters")
    print()
    print("  [B] Manual    — Use a file you already downloaded, trim it,")
    print("                  save video + MP3 for manual upload later")
    print()
    separator()

    while True:
        choice = input("  Enter A or B: ").strip().upper()
        if choice in ("A", "B"):
            return choice
        print("  Please enter A or B.")

# ─────────────────────────────────────────────
#  SHARED: TRIM + NORMALIZE + EXPORT AUDIO
# ─────────────────────────────────────────────

def trim_and_normalize(input_file, start_ts, end_ts, output_dir, label):
    """Trim video to sermon timestamps and normalize audio loudness."""
    ensure_dir(output_dir)
    out_video = os.path.join(output_dir, f"{label}_sermon.mp4")
    target = CONFIG["loudness_target"]

    print(f"\n▶ Trimming {start_ts} → {end_ts} and normalizing audio...")
    cmd = [
        "ffmpeg", "-y",
        "-ss", start_ts, "-to", end_ts,
        "-i", input_file,
        "-af", f"loudnorm=I={target}:TP=-1.5:LRA=11",
        "-c:v", "copy",
        "-c:a", "aac", "-b:a", "192k",
        out_video,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr)
        sys.exit(1)
    print(f"✓ Trimmed video: {out_video}")
    return out_video

def export_audio(video_file, output_dir, label):
    """Extract audio from trimmed video and save as MP3."""
    ensure_dir(output_dir)
    out_audio = os.path.join(output_dir, f"{label}_sermon.mp3")

    print(f"\n▶ Exporting MP3...")
    cmd = [
        "ffmpeg", "-y",
        "-i", video_file,
        "-vn", "-ar", "44100", "-ac", "2", "-b:a", "192k",
        out_audio,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr)
        sys.exit(1)
    print(f"✓ Audio: {out_audio}")
    return out_audio

def open_spotify_for_podcasters(audio_file, episode_title):
    """Open Spotify for Podcasters upload page and copy audio path to clipboard."""
    import webbrowser
    abs_path = os.path.abspath(audio_file)

    print()
    separator("═")
    print("  Upload to Spotify for Podcasters")
    separator("═")
    print(f"  Audio file : {abs_path}")
    print(f"  Title      : {episode_title}")
    print()
    print("  1. Click 'New Episode' in the browser window opening now")
    print("  2. Upload the audio file shown above")
    print("  3. Fill in the title and publish!")
    separator("═")

    try:
        if sys.platform == "darwin":
            subprocess.run(["pbcopy"], input=abs_path.encode(), check=True)
            print("✓ File path copied to clipboard")
    except Exception:
        pass

    webbrowser.open("https://podcasters.spotify.com/pod/dashboard/episode/new")

def print_summary(trimmed_video, audio_file):
    print()
    separator("═")
    print("  ✅  ALL DONE!")
    separator("═")
    print(f"  Trimmed video : {trimmed_video}")
    print(f"  Audio (MP3)   : {audio_file}")
    separator("═")
    print()

# ─────────────────────────────────────────────
#  MODE A — AUTO (download + full pipeline)
# ─────────────────────────────────────────────

def download_youtube(url, output_dir):
    """
    Download from YouTube using yt-dlp with browser cookies to bypass
    PO Token requirements. Tries Chrome → Safari → Firefox in order,
    falls back to no cookies as a last resort.
    """
    ensure_dir(output_dir)
    out_template = os.path.join(output_dir, "%(title)s [%(id)s].%(ext)s")

    base_cmd = [
        sys.executable, "-m", "yt_dlp",
        "-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        "--merge-output-format", "mp4",
        "-o", out_template,
        "--print", "after_move:filepath",
    ]

    print(f"\n▶ Downloading: {url}")
    browsers = ["chrome", "safari", "firefox"]
    result = None
    last_error = ""

    for browser in browsers:
        print(f"  Trying cookies from {browser}...")
        cmd = base_cmd + ["--cookies-from-browser", browser, url]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            print(f"  ✓ {browser} cookies worked")
            break
        last_error = result.stderr
        print(f"  {browser} failed, trying next...")
    else:
        print("  No browser cookies worked, attempting without cookies...")
        cmd = base_cmd + [url]
        result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(last_error or result.stderr)
        print("\n✗ Download failed.")
        print("  Make sure you are logged into YouTube in Chrome, Safari, or Firefox.")
        print("  On macOS, grant Full Disk Access to Terminal:")
        print("  System Settings → Privacy & Security → Full Disk Access")
        sys.exit(1)

    filepath = result.stdout.strip().splitlines()[-1]
    if not os.path.exists(filepath):
        files = sorted(Path(output_dir).glob("*.mp4"), key=os.path.getmtime, reverse=True)
        if not files:
            print("✗ Could not find downloaded file.")
            sys.exit(1)
        filepath = str(files[0])

    print(f"✓ Downloaded: {filepath}")
    return filepath

def get_latest_channel_video():
    """Return the URL of the most recent public video on the configured channel."""
    try:
        from googleapiclient.discovery import build
        creds = _get_youtube_credentials(readonly=True)
        youtube = build("youtube", "v3", credentials=creds)
        response = youtube.search().list(
            channelId=CONFIG["youtube_channel_id"],
            order="date", type="video",
            maxResults=1, part="id,snippet"
        ).execute()
        items = response.get("items", [])
        if not items:
            print("✗ No videos found on the channel.")
            sys.exit(1)
        video_id = items[0]["id"]["videoId"]
        title    = items[0]["snippet"]["title"]
        url      = f"https://www.youtube.com/watch?v={video_id}"
        print(f"✓ Latest video: {title}\n  {url}")
        return url
    except Exception as e:
        print(f"✗ Could not fetch latest video: {e}")
        sys.exit(1)

def _get_youtube_credentials(readonly=False):
    """OAuth2 login for YouTube. Caches token locally after first run."""
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from google.auth.transport.requests import Request

    scopes = (
        ["https://www.googleapis.com/auth/youtube.readonly"]
        if readonly else
        ["https://www.googleapis.com/auth/youtube.upload",
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
                    "  See README.md — YouTube API Setup section."
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
    """Upload trimmed video to YouTube using the Data API v3."""
    try:
        from googleapiclient.discovery import build
        from googleapiclient.http import MediaFileUpload
    except ImportError:
        print("✗ google-api-python-client not installed. Run ./setup.sh")
        sys.exit(1)

    print(f"\n▶ Uploading to YouTube: {title}")
    creds = _get_youtube_credentials()
    youtube = build("youtube", "v3", credentials=creds)

    body = {
        "snippet": {
            "title": title,
            "description": description,
            "categoryId": "22",
        },
        "status": {"privacyStatus": privacy},
    }

    media   = MediaFileUpload(video_file, chunksize=-1, resumable=True, mimetype="video/mp4")
    request = youtube.videos().insert(part="snippet,status", body=body, media_body=media)

    response = None
    while response is None:
        status, response = request.next_chunk()
        if status:
            print(f"  Uploading... {int(status.progress() * 100)}%", end="\r")

    video_id = response["id"]
    print(f"\n✓ Uploaded: https://www.youtube.com/watch?v={video_id}")
    return video_id

def run_mode_a(args, today):
    """MODE A — Download from YouTube, trim, re-upload, open Spotify."""
    print("\n  Mode A — Auto Pipeline\n")
    output_dir = CONFIG["output_dir"]

    # Get source URL
    if args.latest:
        url = get_latest_channel_video()
    elif args.url:
        url = args.url
    else:
        url = input("\nPaste the YouTube URL of this week's broadcast: ").strip()
        if not url:
            print("✗ No URL provided.")
            sys.exit(1)

    raw_video     = download_youtube(url, output_dir)
    start_ts, end_ts = ask_timestamps(args)
    episode_title = ask_episode_title(args, today)
    description   = CONFIG["podcast_description"]
    trimmed_video = trim_and_normalize(raw_video, start_ts, end_ts, output_dir, today)
    audio_file    = export_audio(trimmed_video, output_dir, today)

    # YouTube re-upload
    confirm = input(f"\nUpload trimmed video to YouTube as '{episode_title}'? [Y/n]: ").strip().lower()
    if confirm != "n":
        upload_to_youtube(trimmed_video, episode_title, description,
                          args.privacy or CONFIG["youtube_privacy"])

    open_spotify_for_podcasters(audio_file, episode_title)
    print_summary(trimmed_video, audio_file)

# ─────────────────────────────────────────────
#  MODE B — MANUAL (local file, export only)
# ─────────────────────────────────────────────

def locate_local_file(file_arg):
    """
    Resolve which .mp4 to process in Mode B:
      1. --file argument if provided
      2. Newest .mp4 auto-detected in inbox_dir
      3. Manual path prompt
    """
    if file_arg:
        path = os.path.expanduser(file_arg)
        if not os.path.exists(path):
            print(f"✗ File not found: {path}")
            sys.exit(1)
        print(f"✓ Using: {path}")
        return path

    inbox = CONFIG["inbox_dir"]
    ensure_dir(inbox)
    latest = find_latest_mp4(inbox)
    if latest:
        print(f"\n✓ Found in inbox: {latest}")
        confirm = input("  Use this file? [Y/n]: ").strip().lower()
        if confirm != "n":
            return latest

    print(f"\n  Place the broadcast .mp4 in:  {os.path.abspath(inbox)}/")
    print("  Or enter the full path to the file:\n")
    path = input("Path to .mp4: ").strip().strip("'\"")
    path = os.path.expanduser(path)
    if not os.path.exists(path):
        print(f"✗ File not found: {path}")
        sys.exit(1)
    return path

def run_mode_b(args, today):
    """MODE B — Trim local file, export video + MP3, open Spotify."""
    print("\n  Mode B — Manual File\n")
    output_dir = CONFIG["output_dir"]

    source_file   = locate_local_file(args.file)
    start_ts, end_ts = ask_timestamps(args)
    episode_title = ask_episode_title(args, today)
    trimmed_video = trim_and_normalize(source_file, start_ts, end_ts, output_dir, today)
    audio_file    = export_audio(trimmed_video, output_dir, today)

    open_spotify_for_podcasters(audio_file, episode_title)
    print_summary(trimmed_video, audio_file)

# ─────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Church Weekly Podcast Automation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Interactive menu (recommended):
  ./run.sh

  # Force Mode A (auto download + upload):
  ./run.sh --mode A --url "https://www.youtube.com/watch?v=XXXXX"

  # Force Mode A, fetch latest from channel automatically:
  ./run.sh --mode A --latest

  # Force Mode B (local file):
  ./run.sh --mode B --file ~/Downloads/service.mp4

  # Skip prompts entirely:
  ./run.sh --mode B --file ~/Downloads/service.mp4 --start 00:32:15 --end 01:18:40 --title "Sermon Jan 14"
        """
    )

    parser.add_argument("--mode",   choices=["A", "B"], help="A = auto download, B = local file")
    parser.add_argument("--url",    help="[Mode A] YouTube URL to download")
    parser.add_argument("--latest", action="store_true", help="[Mode A] Download latest video from your channel")
    parser.add_argument("--file",   help="[Mode B] Path to a local .mp4 file")
    parser.add_argument("--start",  help="Sermon start timestamp, e.g. 00:32:15")
    parser.add_argument("--end",    help="Sermon end timestamp,   e.g. 01:18:40")
    parser.add_argument("--title",  help="Episode title (default: auto-generated from date)")
    parser.add_argument("--privacy", choices=["public", "unlisted", "private"],
                        help="[Mode A] YouTube upload privacy (default: public)")

    args  = parser.parse_args()
    today = datetime.today().strftime("%Y-%m-%d")
    mode  = args.mode or select_mode()

    if mode == "A":
        run_mode_a(args, today)
    else:
        run_mode_b(args, today)


if __name__ == "__main__":
    main()
