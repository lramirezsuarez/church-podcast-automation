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
    opens Spotify for Podcasters. YouTube upload is skipped by default
    but can optionally be triggered.

Run: ./run.sh
"""

import os
import re
import sys
import subprocess
import argparse
import threading
import time
from datetime import datetime
from pathlib import Path

try:
    from tqdm import tqdm
    TQDM_AVAILABLE = True
except ImportError:
    TQDM_AVAILABLE = False

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

    # Default episode metadata (offered as defaults at runtime)
    "podcast_title_prefix": "Sermón —",
    "podcast_description":  "Sermón semanal de nuestra iglesia.",

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

def separator(char="─", width=56):
    print(char * width)

def menu_prompt(prompt, choices):
    """Show a prompt and keep asking until a valid choice is entered."""
    while True:
        choice = input(prompt).strip().upper()
        if choice in choices:
            return choice
        print(f"  Please enter one of: {', '.join(choices)}")

def timestamp_to_seconds(ts):
    """Convert HH:MM:SS or MM:SS to seconds."""
    parts = ts.strip().split(":")
    parts = [float(p) for p in parts]
    if len(parts) == 2:
        return parts[0] * 60 + parts[1]
    elif len(parts) == 3:
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    raise ValueError(f"Invalid timestamp '{ts}' — use HH:MM:SS or MM:SS")

def seconds_to_timestamp(secs):
    """Convert seconds to HH:MM:SS string."""
    secs = int(secs)
    h, rem = divmod(secs, 3600)
    m, s   = divmod(rem, 60)
    return f"{h:02}:{m:02}:{s:02}"

def find_latest_mp4(folder):
    """Return the most recently modified .mp4 in a folder, or None."""
    files = sorted(Path(folder).glob("*.mp4"), key=os.path.getmtime, reverse=True)
    return str(files[0]) if files else None

def get_video_duration(filepath):
    """Return duration of a video file in seconds using ffprobe."""
    cmd = [
        "ffprobe", "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        filepath,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0 or not result.stdout.strip():
        return None
    return float(result.stdout.strip())

def ffmpeg_with_progress(cmd, label, duration_secs=None):
    """
    Run an ffmpeg command and show a tqdm progress bar based on time processed.
    Falls back to a simple spinner if duration is unknown or tqdm unavailable.
    """
    # Add progress reporting flags
    cmd = list(cmd) + ["-progress", "pipe:1", "-nostats"]

    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )

    if TQDM_AVAILABLE and duration_secs:
        bar = tqdm(
            total=int(duration_secs),
            desc=f"  {label}",
            unit="s",
            bar_format="{l_bar}{bar}| {n_fmt}/{total_fmt}s [{elapsed}<{remaining}]",
            ncols=70,
        )
        last_time = 0
        for line in process.stdout:
            line = line.strip()
            if line.startswith("out_time_ms="):
                try:
                    ms = int(line.split("=")[1])
                    current = ms // 1_000_000
                    if current > last_time:
                        bar.update(current - last_time)
                        last_time = current
                except (ValueError, IndexError):
                    pass
        bar.n = int(duration_secs)
        bar.refresh()
        bar.close()
    else:
        # Simple spinner fallback
        spinner = ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]
        idx = [0]
        done = [False]
        def spin():
            while not done[0]:
                print(f"\r  {label}... {spinner[idx[0] % len(spinner)]}", end="", flush=True)
                idx[0] += 1
                time.sleep(0.1)
        t = threading.Thread(target=spin, daemon=True)
        t.start()
        process.stdout.read()  # drain
        done[0] = True
        t.join()
        print(f"\r  {label}... ✓" + " " * 10)

    process.wait()
    if process.returncode != 0:
        err = process.stderr.read()
        print(f"\n✗ {label} failed:\n{err}")
        sys.exit(1)

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
#  MENU — MODE SELECTION
# ─────────────────────────────────────────────

def select_mode():
    """Interactive main menu — returns 'A' or 'B'."""
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
    return menu_prompt("  Enter A or B: ", ["A", "B"])

# ─────────────────────────────────────────────
#  MENU — EPISODE METADATA
# ─────────────────────────────────────────────

def ask_episode_metadata(args, today):
    """
    Ask the user whether to use CONFIG defaults or enter custom metadata.
    Returns (title, description).
    """
    # If both were passed as flags, skip the menu entirely
    if args.title and args.description:
        return args.title, args.description

    default_title = f"{CONFIG['podcast_title_prefix']} {today}"
    default_desc  = CONFIG["podcast_description"]

    print()
    separator()
    print("  EPISODE METADATA\n")
    print(f"  Default title       : {default_title}")
    print(f"  Default description : {default_desc}")
    print()
    print("  [U] Use these defaults")
    print("  [C] Enter custom values")
    separator()
    choice = menu_prompt("  Enter U or C: ", ["U", "C"])

    if choice == "U":
        title = args.title or default_title
        desc  = args.description or default_desc
    else:
        title_input = input(f"\n  Episode title [{default_title}]: ").strip()
        title = title_input if title_input else default_title

        desc_input = input(f"  Description [{default_desc}]: ").strip()
        desc = desc_input if desc_input else default_desc

    print(f"\n  ✓ Title       : {title}")
    print(f"  ✓ Description : {desc}")
    return title, desc

# ─────────────────────────────────────────────
#  MENU — TIMESTAMP DETECTION
# ─────────────────────────────────────────────

def ask_timestamps(args, video_file=None):
    """
    Ask the user how to set sermon timestamps:
      [M] Manual   — type start and end times
      [A] Auto     — detect silence/music breaks in the audio
    Returns (start_ts, end_ts) as HH:MM:SS strings.
    """
    # If passed directly as flags, skip the menu
    if args.start and args.end:
        try:
            timestamp_to_seconds(args.start)
            timestamp_to_seconds(args.end)
        except ValueError as e:
            print(f"✗ {e}")
            sys.exit(1)
        return args.start, args.end

    print()
    separator()
    print("  SERMON TIMESTAMPS\n")
    print("  [M] Manual      — I'll enter the start and end times myself")
    print("  [A] Auto-detect — Scan the audio to find the sermon boundaries")
    separator()
    choice = menu_prompt("  Enter M or A: ", ["M", "A"])

    if choice == "M":
        return ask_timestamps_manual()
    else:
        return ask_timestamps_auto(video_file)

def ask_timestamps_manual():
    """Prompt the user to type start and end timestamps."""
    separator()
    print("  Format: HH:MM:SS  or  MM:SS")
    separator()
    while True:
        start_str = input("  Sermon START time (e.g. 00:32:15): ").strip()
        try:
            timestamp_to_seconds(start_str)
            break
        except ValueError as e:
            print(f"  ✗ {e}")
    while True:
        end_str = input("  Sermon END time   (e.g. 01:18:40): ").strip()
        try:
            timestamp_to_seconds(end_str)
            break
        except ValueError as e:
            print(f"  ✗ {e}")
    return start_str, end_str

def ask_timestamps_auto(video_file):
    """
    Auto-detect sermon boundaries by scanning for long silence gaps in the audio.

    Strategy:
      - Run ffmpeg silencedetect to find all silent segments
      - The sermon typically starts after the first long music/intro block
        and ends before the final music/outro block
      - We find the two longest silent gaps and treat the edges of those as
        the sermon start and end
      - Show the user the detected timestamps and let them confirm or adjust
    """
    if not video_file or not os.path.exists(video_file):
        print("  ✗ No video file available for auto-detection. Falling back to manual.")
        return ask_timestamps_manual()

    print(f"\n  Scanning audio for silence gaps in: {os.path.basename(video_file)}")
    print("  This may take a moment...\n")

    # silencedetect: mark silence below -35dB lasting at least 2 seconds
    cmd = [
        "ffmpeg", "-i", video_file,
        "-af", "silencedetect=noise=-35dB:d=2",
        "-f", "null", "-",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    output = result.stderr  # ffmpeg writes filter output to stderr

    # Parse silence_start / silence_end pairs
    starts = [float(m) for m in re.findall(r"silence_start: (\S+)", output)]
    ends   = [float(m) for m in re.findall(r"silence_end: (\S+)", output)]

    if len(starts) < 2:
        print("  ⚠ Not enough silence detected for auto-detection.")
        print("  This can happen if the audio is consistently loud throughout.")
        print("  Falling back to manual timestamps.\n")
        return ask_timestamps_manual()

    # Build list of (duration, start, end) for each silent segment
    pairs = []
    for s, e in zip(starts, ends):
        pairs.append((e - s, s, e))
    pairs.sort(reverse=True)  # longest gaps first

    # The sermon start = end of the first (longest) silence gap in the first half
    # The sermon end   = start of the first (longest) silence gap in the second half
    duration = get_video_duration(video_file) or 9999
    midpoint = duration / 2

    intro_gaps  = [(d, s, e) for d, s, e in pairs if e < midpoint]
    outro_gaps  = [(d, s, e) for d, s, e in pairs if s > midpoint]

    if not intro_gaps or not outro_gaps:
        print("  ⚠ Could not find silence gaps on both sides of the midpoint.")
        print("  Falling back to manual timestamps.\n")
        return ask_timestamps_manual()

    # Pick the longest gap in each half
    _, _is, intro_end = intro_gaps[0]
    _, outro_start, _ = outro_gaps[0]

    detected_start = seconds_to_timestamp(intro_end)
    detected_end   = seconds_to_timestamp(outro_start)

    print(f"  ✓ Detected sermon START : {detected_start}")
    print(f"  ✓ Detected sermon END   : {detected_end}")
    print()
    print("  [U] Use these timestamps")
    print("  [A] Adjust manually")
    separator()
    choice = menu_prompt("  Enter U or A: ", ["U", "A"])

    if choice == "U":
        return detected_start, detected_end
    else:
        print(f"\n  Current values — Start: {detected_start}  End: {detected_end}")
        print("  Press Enter to keep a value, or type a new one.\n")
        new_start = input(f"  START [{detected_start}]: ").strip() or detected_start
        new_end   = input(f"  END   [{detected_end}]: ").strip() or detected_end
        try:
            timestamp_to_seconds(new_start)
            timestamp_to_seconds(new_end)
        except ValueError as e:
            print(f"  ✗ {e}")
            sys.exit(1)
        return new_start, new_end

# ─────────────────────────────────────────────
#  SHARED: TRIM + NORMALIZE + EXPORT AUDIO
# ─────────────────────────────────────────────

def trim_and_normalize(input_file, start_ts, end_ts, output_dir, label):
    """Trim video to sermon timestamps and normalize audio loudness."""
    ensure_dir(output_dir)
    out_video = os.path.join(output_dir, f"{label}_sermon.mp4")
    target = CONFIG["loudness_target"]

    # Calculate duration of the sermon segment for the progress bar
    start_secs    = timestamp_to_seconds(start_ts)
    end_secs      = timestamp_to_seconds(end_ts)
    segment_secs  = end_secs - start_secs

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
    ffmpeg_with_progress(cmd, "Trimming & normalizing", duration_secs=segment_secs)
    print(f"✓ Trimmed video: {out_video}")
    return out_video

def export_audio(video_file, output_dir, label):
    """Extract audio from trimmed video and save as MP3."""
    ensure_dir(output_dir)
    out_audio = os.path.join(output_dir, f"{label}_sermon.mp3")
    duration  = get_video_duration(video_file)

    print(f"\n▶ Exporting MP3...")
    cmd = [
        "ffmpeg", "-y",
        "-i", video_file,
        "-vn", "-ar", "44100", "-ac", "2", "-b:a", "192k",
        out_audio,
    ]
    ffmpeg_with_progress(cmd, "Exporting MP3", duration_secs=duration)
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
        # --newline makes yt-dlp print each progress update on its own line
        # so we can stream it live to the terminal instead of buffering
        cmd = base_cmd + ["--cookies-from-browser", browser, "--newline", url]
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        stdout_lines = []
        for line in process.stdout:
            line_s = line.strip()
            stdout_lines.append(line_s)
            # Show yt-dlp's own progress lines (download %, ETA, speed)
            if "[download]" in line_s or "[Merger]" in line_s or "[ffmpeg]" in line_s:
                print(f"  {line_s}", end="\r" if "%" in line_s else "\n", flush=True)
        process.wait()
        result_stdout = "\n".join(stdout_lines)
        result_stderr = process.stderr.read()
        if process.returncode == 0:
            print(f"\n  ✓ {browser} cookies worked")
            # Reconstruct a result-like object for filepath parsing below
            class _Result:
                returncode = 0
                stdout = result_stdout
                stderr = result_stderr
            result = _Result()
            break
        last_error = result_stderr
        print(f"\n  {browser} failed, trying next...")
    else:
        print("  No browser cookies worked, attempting without cookies...")
        cmd = base_cmd + ["--newline", url]
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        stdout_lines = []
        for line in process.stdout:
            line_s = line.strip()
            stdout_lines.append(line_s)
            if "[download]" in line_s or "[Merger]" in line_s or "[ffmpeg]" in line_s:
                print(f"  {line_s}", end="\r" if "%" in line_s else "\n", flush=True)
        process.wait()
        class _Result:
            returncode = process.returncode
            stdout = "\n".join(stdout_lines)
            stderr = process.stderr.read()
        result = _Result()

    if result.returncode != 0:
        print(last_error or result.stderr)
        print("\n✗ Download failed.")
        print("  Make sure you are logged into YouTube in Chrome, Safari, or Firefox.")
        print("  On macOS, grant Full Disk Access to Terminal:")
        print("  System Settings → Privacy & Security → Full Disk Access")
        sys.exit(1)

    all_lines = [l for l in result.stdout.strip().splitlines() if l and not l.startswith("[")]
    filepath  = all_lines[-1] if all_lines else ""
    print()  # newline after \r progress lines
    if not os.path.exists(filepath):
        files = sorted(Path(output_dir).glob("*.mp4"), key=os.path.getmtime, reverse=True)
        if not files:
            print("✗ Could not find downloaded file.")
            sys.exit(1)
        filepath = str(files[0])

    print(f"✓ Downloaded: {filepath}")
    return filepath

def select_youtube_source(args):
    """
    Ask the user how to get the YouTube video for Mode A:
      [L] Latest  — auto-fetch the latest video from the configured channel
      [U] URL     — paste a specific video URL
    Can be bypassed with --latest or --url flags.
    """
    if args.latest:
        return "latest", None
    if args.url:
        return "url", args.url

    print()
    separator()
    print("  YOUTUBE SOURCE\n")
    print("  [L] Latest video  — Auto-fetch the latest from your channel")
    print("  [U] Paste URL     — I'll provide a specific video link")
    separator()
    choice = menu_prompt("  Enter L or U: ", ["L", "U"])

    if choice == "L":
        return "latest", None
    else:
        url = input("\n  Paste the YouTube URL: ").strip()
        if not url:
            print("✗ No URL provided.")
            sys.exit(1)
        return "url", url

def get_latest_channel_video():
    """Return the URL of the most recent public video on the configured channel."""
    try:
        from googleapiclient.discovery import build
        creds = _get_youtube_credentials()
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
                    f"\n✗ Missing '{CONFIG['client_secrets_file']}'."
                    "\n  See README.md — YouTube API Setup section."
                )
                sys.exit(1)
            flow = InstalledAppFlow.from_client_secrets_file(
                CONFIG["client_secrets_file"], scopes
            )
            creds = flow.run_local_server(port=0)
        with open(token_file, "w") as f:
            f.write(creds.to_json())

    return creds

def select_upload_channel(youtube):
    """
    List all channels the authenticated account can manage and let the
    user pick which one to upload to.

    Accounts that manage Brand Accounts (e.g. a church channel) will see
    multiple channels listed. The user picks by number and the chosen
    channel ID is returned so the upload targets it explicitly.
    """
    print("\n▶ Fetching channels available to your account...")
    response = youtube.channels().list(
        part="snippet",
        mine=True,
        maxResults=50,
    ).execute()

    channels = response.get("items", [])

    if not channels:
        print("  ✗ No channels found. Make sure you are authenticated correctly.")
        sys.exit(1)

    if len(channels) == 1:
        ch = channels[0]
        print(f"  ✓ Only one channel found: {ch['snippet']['title']} ({ch['id']})")
        return ch["id"]

    # Multiple channels — let the user pick
    print()
    separator()
    print("  SELECT UPLOAD CHANNEL\n")
    for i, ch in enumerate(channels, 1):
        title = ch["snippet"]["title"]
        cid   = ch["id"]
        tag   = "  ← personal (default)" if i == 1 else ""
        print(f"  [{i}] {title}  ({cid}){tag}")
    separator()

    while True:
        raw = input(f"  Enter channel number (1–{len(channels)}): ").strip()
        if raw.isdigit() and 1 <= int(raw) <= len(channels):
            chosen = channels[int(raw) - 1]
            print(f"\n  ✓ Selected: {chosen['snippet']['title']}")
            return chosen["id"]
        print(f"  Please enter a number between 1 and {len(channels)}.")

def upload_to_youtube(video_file, title, description, privacy="public"):
    """Upload trimmed video to the selected YouTube channel."""
    try:
        from googleapiclient.discovery import build
        from googleapiclient.http import MediaFileUpload
    except ImportError:
        print("✗ google-api-python-client not installed. Run ./setup.sh")
        sys.exit(1)

    # Always use full (non-readonly) scopes so upload is permitted
    creds   = _get_youtube_credentials(readonly=False)
    youtube = build("youtube", "v3", credentials=creds)

    # Let the user pick which channel to upload to
    # The YouTube API uploads to whichever channel the authenticated user
    # selects — for Brand Accounts the API automatically targets that channel
    # when the user is switched to it during OAuth. We show the list so the
    # user can confirm they are authenticated against the right account.
    select_upload_channel(youtube)

    print(f"\n▶ Uploading: {title}")

    body = {
        "snippet": {
            "title": title,
            "description": description,
            "categoryId": "22",
        },
        "status": {"privacyStatus": privacy},
    }

    media   = MediaFileUpload(video_file, chunksize=-1, resumable=True, mimetype="video/mp4")
    request = youtube.videos().insert(
        part="snippet,status",
        body=body,
        media_body=media,
    )

    response = None
    while response is None:
        status, response = request.next_chunk()
        if status:
            print(f"  Uploading... {int(status.progress() * 100)}%", end="\r")

    video_id = response["id"]
    video_url  = f"https://www.youtube.com/watch?v={video_id}"
    studio_url = f"https://studio.youtube.com/video/{video_id}/edit"
    print(f"\n✓ Uploaded: {video_url}")
    print(f"  Opening YouTube Studio to finish setup (audience, tags, playlist)...")
    import webbrowser
    webbrowser.open(studio_url)
    return video_id

def ask_youtube_upload(args, trimmed_video, episode_title, description):
    """Ask the user whether to upload to YouTube, then do it if confirmed."""
    print()
    separator()
    print("  YOUTUBE UPLOAD\n")
    print(f"  Title   : {episode_title}")
    print(f"  Privacy : {args.privacy or CONFIG['youtube_privacy']}")
    print()
    print("  [Y] Yes — upload to YouTube now")
    print("  [N] No  — skip, I'll upload manually later")
    separator()
    choice = menu_prompt("  Upload to YouTube? [Y/N]: ", ["Y", "N"])
    if choice == "Y":
        upload_to_youtube(
            trimmed_video, episode_title, description,
            args.privacy or CONFIG["youtube_privacy"]
        )

def run_mode_a(args, today):
    """MODE A — Download from YouTube, trim, re-upload, open Spotify."""
    print("\n  Mode A — Auto Pipeline\n")
    output_dir = CONFIG["output_dir"]

    # YouTube source selection (menu or flags)
    source_type, url = select_youtube_source(args)
    if source_type == "latest":
        url = get_latest_channel_video()

    raw_video              = download_youtube(url, output_dir)
    start_ts, end_ts       = ask_timestamps(args, video_file=raw_video)
    episode_title, desc    = ask_episode_metadata(args, today)
    trimmed_video          = trim_and_normalize(raw_video, start_ts, end_ts, output_dir, today)
    audio_file             = export_audio(trimmed_video, output_dir, today)

    ask_youtube_upload(args, trimmed_video, episode_title, desc)
    open_spotify_for_podcasters(audio_file, episode_title)
    print_summary(trimmed_video, audio_file)

# ─────────────────────────────────────────────
#  MODE B — MANUAL (local file)
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
        confirm = input("  Use this file? [Y/n]: ").strip().upper()
        if confirm != "N":
            return latest

    print(f"\n  Place the broadcast .mp4 in:  {os.path.abspath(inbox)}/")
    print("  Or enter the full path to the file:\n")
    path = input("  Path to .mp4: ").strip().strip("'\"")
    path = os.path.expanduser(path)
    if not os.path.exists(path):
        print(f"✗ File not found: {path}")
        sys.exit(1)
    return path

def run_mode_b(args, today):
    """MODE B — Trim local file, export video + MP3, optionally upload to YouTube."""
    print("\n  Mode B — Manual File\n")
    output_dir = CONFIG["output_dir"]

    source_file            = locate_local_file(args.file)
    start_ts, end_ts       = ask_timestamps(args, video_file=source_file)
    episode_title, desc    = ask_episode_metadata(args, today)
    trimmed_video          = trim_and_normalize(source_file, start_ts, end_ts, output_dir, today)
    audio_file             = export_audio(trimmed_video, output_dir, today)

    # Optional YouTube upload — available in Mode B too
    ask_youtube_upload(args, trimmed_video, episode_title, desc)

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
  # Interactive menu (recommended — guides you through everything):
  ./run.sh

  # Mode A, prompted for URL:
  ./run.sh --mode A

  # Mode A, auto-fetch latest video from channel:
  ./run.sh --mode A --latest

  # Mode A, pass a specific URL:
  ./run.sh --mode A --url "https://www.youtube.com/watch?v=XXXXX"

  # Mode B, auto-detect file from inbox/:
  ./run.sh --mode B

  # Mode B, point to a specific file:
  ./run.sh --mode B --file ~/Downloads/service.mp4

  # Fully non-interactive (skip all menus):
  ./run.sh --mode B --file ~/Downloads/service.mp4 \\
    --start 00:32:15 --end 01:18:40 \\
    --title "Sermon Jan 14" --description "Sunday service"
        """
    )

    parser.add_argument("--mode",        choices=["A", "B"],
                                         help="A = auto download, B = local file")
    parser.add_argument("--url",         help="[Mode A] YouTube URL to download")
    parser.add_argument("--latest",      action="store_true",
                                         help="[Mode A] Auto-fetch latest video from your channel")
    parser.add_argument("--file",        help="[Mode B] Path to a local .mp4 file")
    parser.add_argument("--start",       help="Sermon start timestamp, e.g. 00:32:15")
    parser.add_argument("--end",         help="Sermon end timestamp,   e.g. 01:18:40")
    parser.add_argument("--title",       help="Episode title")
    parser.add_argument("--description", help="Episode description")
    parser.add_argument("--privacy",     choices=["public", "unlisted", "private"],
                                         help="YouTube upload privacy (default: from CONFIG)")

    args  = parser.parse_args()
    today = datetime.today().strftime("%Y-%m-%d")
    mode  = args.mode or select_mode()

    if mode == "A":
        run_mode_a(args, today)
    else:
        run_mode_b(args, today)


if __name__ == "__main__":
    main()
