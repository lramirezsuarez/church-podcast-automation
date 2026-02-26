#!/usr/bin/env python3
"""
Church Weekly Podcast Automation
---------------------------------
Steps:
  1. Point to a locally downloaded .mp4 file
  2. Trim to sermon start/end timestamps
  3. Normalize/boost audio volume
  4. Save trimmed video (.mp4) and audio (.mp3)
  5. Re-upload trimmed video to YouTube
  6. Open Spotify for Podcasters in browser for manual audio upload

Requirements:
  See requirements.txt — run ./setup.sh to install everything.
  ffmpeg must be installed (setup.sh handles this too).
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
        f"\n✗ Python {sys.version_info.major}.{sys.version_info.minor} detected — Python 3.10+ is required.\n"
        "  Run ./setup.sh to fix this, then use ./run.sh to launch the script.\n"
    )
    sys.exit(1)

# ─────────────────────────────────────────────
#  CONFIGURATION  — edit these values
# ─────────────────────────────────────────────


CONFIG = {
    # Drop your downloaded .mp4 here each week — the script will auto-detect it
    "input_dir": "./inbox",

    # Processed files (trimmed video + mp3) will be saved here
    "output_dir": "./podcast_output",

    # YouTube upload privacy: "public", "private", or "unlisted"
    "youtube_privacy": "private",

    # Default episode metadata (can be overridden at runtime)
    "podcast_title_prefix": "Predicación —",   # e.g. "Predicación — 2024-01-14"
    "podcast_description": "Predicación de la serie actual.",

    # Audio loudness target (EBU R128, -14 LUFS is Spotify's standard)
    "loudness_target": "-14",

    # YouTube OAuth2 credentials (see README for setup instructions)
    "client_secrets_file": "client_secrets.json",
    "token_file": "youtube_token.json",
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

# ─────────────────────────────────────────────
#  STEP 1: LOCATE SOURCE FILE
# ─────────────────────────────────────────────

def locate_source_file(file_arg):
    """
    Resolve which .mp4 file to process:
      1. --file argument if provided
      2. Newest .mp4 auto-detected in CONFIG["input_dir"]
      3. Manual path prompt
    """
    if file_arg:
        path = os.path.expanduser(file_arg)
        if not os.path.exists(path):
            print(f"✗ File not found: {path}")
            sys.exit(1)
        print(f"✓ Using: {path}")
        return path

    ensure_dir(CONFIG["input_dir"])
    latest = find_latest_mp4(CONFIG["input_dir"])
    if latest:
        print(f"✓ Found in inbox: {latest}")
        confirm = input("  Use this file? [Y/n]: ").strip().lower()
        if confirm != "n":
            return latest

    print(f"\nPlace the broadcast .mp4 in:  {os.path.abspath(CONFIG['input_dir'])}/")
    print("Or enter the full path to the file:\n")
    path = input("Path to .mp4: ").strip().strip("'\"")
    path = os.path.expanduser(path)
    if not os.path.exists(path):
        print(f"✗ File not found: {path}")
        sys.exit(1)
    return path

# ─────────────────────────────────────────────
#  STEPS 2 & 3: TRIM + NORMALIZE AUDIO
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
        out_video
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr)
        sys.exit(1)

    print(f"✓ Trimmed video: {out_video}")
    return out_video

# ─────────────────────────────────────────────
#  STEP 4: EXPORT AUDIO (.mp3)
# ─────────────────────────────────────────────

def export_audio(video_file, output_dir, label):
    """Extract audio from trimmed video and save as MP3."""
    ensure_dir(output_dir)
    out_audio = os.path.join(output_dir, f"{label}_sermon.mp3")

    print(f"\n▶ Exporting MP3...")
    cmd = [
        "ffmpeg", "-y",
        "-i", video_file,
        "-vn", "-ar", "44100", "-ac", "2", "-b:a", "192k",
        out_audio
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr)
        sys.exit(1)

    print(f"✓ Audio: {out_audio}")
    return out_audio

# ─────────────────────────────────────────────
#  STEP 5: UPLOAD TRIMMED VIDEO TO YOUTUBE
# ─────────────────────────────────────────────

def _get_youtube_credentials():
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from google.auth.transport.requests import Request

    scopes = [
        "https://www.googleapis.com/auth/youtube.upload",
        "https://www.googleapis.com/auth/youtube",
    ]
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

    media = MediaFileUpload(video_file, chunksize=-1, resumable=True, mimetype="video/mp4")
    request = youtube.videos().insert(part="snippet,status", body=body, media_body=media)

    response = None
    while response is None:
        status, response = request.next_chunk()
        if status:
            print(f"  Uploading... {int(status.progress() * 100)}%", end="\r")

    video_id = response["id"]
    print(f"\n✓ Uploaded: https://www.youtube.com/watch?v={video_id}")
    return video_id

# ─────────────────────────────────────────────
#  STEP 6: OPEN SPOTIFY FOR PODCASTERS
# ─────────────────────────────────────────────

def open_spotify_for_podcasters(audio_file, episode_title):
    import webbrowser

    abs_path = os.path.abspath(audio_file)
    print("\n" + "="*60)
    print("STEP 6 — Upload to Spotify for Podcasters")
    print("="*60)
    print(f"  Audio file : {abs_path}")
    print(f"  Title      : {episode_title}")
    print("\n  1. Click 'New Episode' in the browser window opening now")
    print("  2. Upload the audio file shown above")
    print("  3. Set the title and publish!")
    print("="*60)

    try:
        if sys.platform == "darwin":
            subprocess.run(["pbcopy"], input=abs_path.encode(), check=True)
            print("✓ File path copied to clipboard")
    except Exception:
        pass

    webbrowser.open("https://podcasters.spotify.com/pod/dashboard/episode/new")

# ─────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Church Weekly Podcast Automation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Auto-detect newest .mp4 in the inbox/ folder:
  ./run.sh

  # Point to a specific file:
  ./run.sh --file ~/Downloads/service.mp4

  # Provide all arguments upfront (no prompts):
  ./run.sh --file ~/Downloads/service.mp4 --start 00:32:15 --end 01:18:40 --title "Sermon Jan 14"

  # Skip YouTube re-upload:
  ./run.sh --file ~/Downloads/service.mp4 --no-youtube-upload
        """
    )

    parser.add_argument("--file",  help="Path to the downloaded .mp4 broadcast file")
    parser.add_argument("--start", help="Sermon start timestamp, e.g. 00:32:15")
    parser.add_argument("--end",   help="Sermon end timestamp,   e.g. 01:18:40")
    parser.add_argument("--title", help="Episode title (default: auto-generated from today's date)")
    parser.add_argument("--no-youtube-upload", action="store_true", help="Skip re-uploading to YouTube")
    parser.add_argument("--no-podcast-upload", action="store_true", help="Skip opening Spotify for Podcasters")
    parser.add_argument("--privacy", default=CONFIG["youtube_privacy"],
                        choices=["public", "unlisted", "private"],
                        help="YouTube upload privacy (default: public)")

    args = parser.parse_args()

    output_dir = CONFIG["output_dir"]
    today = datetime.today().strftime("%Y-%m-%d")

    print("\n" + "="*60)
    print("  Church Podcast Automation")
    print("="*60)

    # Step 1 — locate file
    source_file = locate_source_file(args.file)

    # Step 2 — timestamps
    print("\n" + "─"*50)
    print("TRIM TIMESTAMPS  (format: HH:MM:SS or MM:SS)")
    print("─"*50)
    start_ts = args.start or input("Sermon START time (e.g. 00:32:15): ").strip()
    end_ts   = args.end   or input("Sermon END time   (e.g. 01:18:40): ").strip()

    try:
        timestamp_to_seconds(start_ts)
        timestamp_to_seconds(end_ts)
    except ValueError as e:
        print(f"✗ {e}")
        sys.exit(1)

    # Episode title
    episode_title = args.title
    if not episode_title:
        default_title = f"{CONFIG['podcast_title_prefix']} {today}"
        typed = input(f"\nEpisode title [{default_title}]: ").strip()
        episode_title = typed if typed else default_title

    description = CONFIG["podcast_description"]

    # Steps 2 & 3 — trim + normalize
    trimmed_video = trim_and_normalize(source_file, start_ts, end_ts, output_dir, today)

    # Step 4 — export audio
    audio_file = export_audio(trimmed_video, output_dir, today)

    # Step 5 — YouTube upload
    if not args.no_youtube_upload:
        confirm = input(f"\nUpload trimmed video to YouTube as '{episode_title}'? [Y/n]: ").strip().lower()
        if confirm != "n":
            upload_to_youtube(trimmed_video, episode_title, description, args.privacy)
    else:
        print("\n⏩ Skipping YouTube upload.")

    # Step 6 — Spotify for Podcasters
    if not args.no_podcast_upload:
        open_spotify_for_podcasters(audio_file, episode_title)
    else:
        print("\n⏩ Skipping podcast upload.")

    # Summary
    print("\n" + "="*60)
    print("✅ ALL DONE!")
    print("="*60)
    print(f"  Trimmed video : {trimmed_video}")
    print(f"  Audio (MP3)   : {audio_file}")
    print("="*60 + "\n")


if __name__ == "__main__":
    main()
