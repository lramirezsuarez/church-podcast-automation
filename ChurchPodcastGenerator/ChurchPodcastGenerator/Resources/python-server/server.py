#!/usr/bin/env python3
"""
Church Podcast — Python Backend Server
---------------------------------------
Flask server exposing the podcast automation pipeline as a REST API
with Server-Sent Events (SSE) for real-time progress streaming.

The SwiftUI app starts this server on launch and calls its endpoints.
All heavy lifting (ffmpeg, yt-dlp, YouTube API) lives here.
"""

import os
import re
import sys
import json
import queue
import threading
import subprocess
import webbrowser
from pathlib import Path
from datetime import datetime

from flask import Flask, request, jsonify, Response, stream_with_context
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

# ─────────────────────────────────────────────────────────────
#  CONFIG  (mirrors church_podcast_automation.py CONFIG block)
# ─────────────────────────────────────────────────────────────

BASE_DIR = Path(__file__).parent.parent  # repo root

CONFIG = {
    "output_dir":           str(BASE_DIR / "podcast_output"),
    "inbox_dir":            str(BASE_DIR / "inbox"),
    "youtube_privacy":      "public",
    "podcast_title_prefix": "Sermón —",
    "podcast_description":  "Sermón semanal de nuestra iglesia.",
    "loudness_target":      "-14",
    "client_secrets_file":  str(BASE_DIR / "client_secrets.json"),
    "token_file":           str(BASE_DIR / "youtube_token.json"),
}

# ─────────────────────────────────────────────────────────────
#  GLOBAL PROGRESS QUEUE
#  Steps push SSE events here; /events streams them to SwiftUI.
# ─────────────────────────────────────────────────────────────

_event_queue: queue.Queue = queue.Queue()


def push(event: str, data: dict):
    _event_queue.put({"event": event, "data": data})

def push_progress(step: str, pct: int, message: str = ""):
    push("progress", {"step": step, "pct": pct, "message": message})

def push_done(step: str, result: dict = {}):
    push("done", {"step": step, **result})

def push_error(step: str, message: str):
    push("error", {"step": step, "message": message})


# ─────────────────────────────────────────────────────────────
#  HELPERS
# ─────────────────────────────────────────────────────────────

def ensure_dir(path: str):
    Path(path).mkdir(parents=True, exist_ok=True)

def timestamp_to_seconds(ts: str) -> float:
    parts = [float(p) for p in ts.strip().split(":")]
    if len(parts) == 2:
        return parts[0] * 60 + parts[1]
    elif len(parts) == 3:
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    raise ValueError(f"Invalid timestamp '{ts}'")

def seconds_to_timestamp(secs: float) -> str:
    secs = int(secs)
    h, rem = divmod(secs, 3600)
    m, s = divmod(rem, 60)
    return f"{h:02}:{m:02}:{s:02}"

def get_video_duration(filepath: str):
    cmd = ["ffprobe", "-v", "error", "-show_entries", "format=duration",
           "-of", "default=noprint_wrappers=1:nokey=1", filepath]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        return None
    return float(r.stdout.strip())


# ─────────────────────────────────────────────────────────────
#  SSE STREAM  — SwiftUI subscribes here for live updates
# ─────────────────────────────────────────────────────────────

@app.route("/events")
def events():
    def generate():
        while True:
            try:
                item = _event_queue.get(timeout=30)
                yield f"event: {item['event']}\ndata: {json.dumps(item['data'])}\n\n"
            except queue.Empty:
                yield ": heartbeat\n\n"
    return Response(
        stream_with_context(generate()),
        mimetype="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


# ─────────────────────────────────────────────────────────────
#  STATUS & CONFIG
# ─────────────────────────────────────────────────────────────

@app.route("/status")
def status():
    return jsonify({"ok": True, "version": "1.0.0"})


@app.route("/config", methods=["GET"])
def get_config():
    return jsonify({
        "podcast_title_prefix": CONFIG["podcast_title_prefix"],
        "podcast_description":  CONFIG["podcast_description"],
        "youtube_privacy":      CONFIG["youtube_privacy"],
        "loudness_target":      CONFIG["loudness_target"],
        "output_dir":           CONFIG["output_dir"],
        "inbox_dir":            CONFIG["inbox_dir"],
        "has_client_secrets":   os.path.exists(CONFIG["client_secrets_file"]),
        "has_token":            os.path.exists(CONFIG["token_file"]),
    })


@app.route("/config", methods=["POST"])
def update_config():
    body = request.json or {}
    for key in ["podcast_title_prefix", "podcast_description",
                "youtube_privacy", "loudness_target"]:
        if key in body:
            CONFIG[key] = body[key]
    return jsonify({"ok": True})


@app.route("/inbox/files")
def inbox_files():
    inbox = CONFIG["inbox_dir"]
    ensure_dir(inbox)
    files = sorted(Path(inbox).glob("*.mp4"), key=os.path.getmtime, reverse=True)
    return jsonify([{
        "name": f.name, "path": str(f),
        "size_mb": round(f.stat().st_size / (1024 * 1024), 1),
        "modified": datetime.fromtimestamp(f.stat().st_mtime).isoformat(),
    } for f in files])


@app.route("/output/files")
def output_files():
    out = CONFIG["output_dir"]
    ensure_dir(out)
    files = []
    for ext in ["*.mp4", "*.mp3"]:
        for f in sorted(Path(out).glob(ext), key=os.path.getmtime, reverse=True):
            files.append({
                "name": f.name, "path": str(f),
                "size_mb": round(f.stat().st_size / (1024 * 1024), 1),
                "modified": datetime.fromtimestamp(f.stat().st_mtime).isoformat(),
            })
    return jsonify(files)


# ─────────────────────────────────────────────────────────────
#  STEP 1 — DOWNLOAD
# ─────────────────────────────────────────────────────────────

@app.route("/download", methods=["POST"])
def download():
    body = request.json or {}
    url  = body.get("url", "").strip()
    if not url:
        return jsonify({"error": "url is required"}), 400

    output_dir   = CONFIG["output_dir"]
    ensure_dir(output_dir)
    out_template = os.path.join(output_dir, "%(title)s [%(id)s].%(ext)s")

    base_cmd = [
        sys.executable, "-m", "yt_dlp",
        "-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        "--merge-output-format", "mp4",
        "-o", out_template,
        "--print", "after_move:filepath",
        "--newline",
    ]

    def run():
        push_progress("download", 0, "Starting download...")
        browsers    = ["chrome", "safari", "firefox"]
        success     = False
        filepath    = ""
        last_error  = ""

        for browser in browsers:
            push_progress("download", 2, f"Trying {browser} cookies...")
            process = subprocess.Popen(
                base_cmd + ["--cookies-from-browser", browser, url],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            stdout_lines = []
            for line in process.stdout:
                line = line.strip()
                stdout_lines.append(line)
                m = re.search(r"\[download\]\s+([\d.]+)%", line)
                if m:
                    pct = min(int(float(m.group(1))), 99)
                    push_progress("download", pct, line)
            process.wait()
            if process.returncode == 0:
                success = True
                clean   = [l for l in stdout_lines if l and not l.startswith("[")]
                filepath = clean[-1] if clean else ""
                break
            last_error = process.stderr.read()

        if not success:
            push_progress("download", 2, "No browser cookies worked, trying without...")
            process = subprocess.Popen(
                base_cmd + [url],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            stdout_lines = []
            for line in process.stdout:
                line = line.strip()
                stdout_lines.append(line)
                m = re.search(r"\[download\]\s+([\d.]+)%", line)
                if m:
                    pct = min(int(float(m.group(1))), 99)
                    push_progress("download", pct, line)
            process.wait()
            if process.returncode == 0:
                success  = True
                clean    = [l for l in stdout_lines if l and not l.startswith("[")]
                filepath = clean[-1] if clean else ""
            else:
                push_error("download",
                    "Download failed. Make sure you are logged into YouTube in "
                    "Chrome, Safari, or Firefox, and that Terminal has Full Disk Access "
                    "in System Settings → Privacy & Security.")
                return

        if not filepath or not os.path.exists(filepath):
            files = sorted(Path(output_dir).glob("*.mp4"), key=os.path.getmtime, reverse=True)
            if not files:
                push_error("download", "Could not locate the downloaded file.")
                return
            filepath = str(files[0])

        push_progress("download", 100, "Download complete")
        push_done("download", {"filepath": filepath, "filename": os.path.basename(filepath)})

    threading.Thread(target=run, daemon=True).start()
    return jsonify({"ok": True})


# ─────────────────────────────────────────────────────────────
#  STEP 1b — AUTO-DETECT TIMESTAMPS
# ─────────────────────────────────────────────────────────────

@app.route("/detect-timestamps", methods=["POST"])
def detect_timestamps():
    body     = request.json or {}
    filepath = body.get("filepath", "")
    if not filepath or not os.path.exists(filepath):
        return jsonify({"error": "filepath is required and must exist"}), 400

    def run():
        push_progress("detect", 10, "Scanning audio for silence gaps...")
        result = subprocess.run(
            ["ffmpeg", "-i", filepath, "-af", "silencedetect=noise=-35dB:d=2", "-f", "null", "-"],
            capture_output=True, text=True,
        )
        starts = [float(m) for m in re.findall(r"silence_start: (\S+)", result.stderr)]
        ends   = [float(m) for m in re.findall(r"silence_end: (\S+)",   result.stderr)]

        if len(starts) < 2:
            push_error("detect", "Not enough silence detected. Please enter timestamps manually.")
            return

        pairs    = sorted([(e - s, s, e) for s, e in zip(starts, ends)], reverse=True)
        duration = get_video_duration(filepath) or 9999
        midpoint = duration / 2

        intro_gaps = [(d, s, e) for d, s, e in pairs if e < midpoint]
        outro_gaps = [(d, s, e) for d, s, e in pairs if s > midpoint]

        if not intro_gaps or not outro_gaps:
            push_error("detect", "Could not find silence on both sides. Please enter timestamps manually.")
            return

        _, _, intro_end   = intro_gaps[0]
        _, outro_start, _ = outro_gaps[0]

        push_progress("detect", 100, "Detection complete")
        push_done("detect", {
            "start": seconds_to_timestamp(intro_end),
            "end":   seconds_to_timestamp(outro_start),
        })

    threading.Thread(target=run, daemon=True).start()
    return jsonify({"ok": True})


# ─────────────────────────────────────────────────────────────
#  STEP 2 — TRIM + NORMALIZE
# ─────────────────────────────────────────────────────────────

@app.route("/trim", methods=["POST"])
def trim():
    body     = request.json or {}
    filepath = body.get("filepath", "")
    start_ts = body.get("start", "")
    end_ts   = body.get("end", "")
    label    = body.get("label", datetime.today().strftime("%Y-%m-%d"))

    if not all([filepath, start_ts, end_ts]):
        return jsonify({"error": "filepath, start, and end are required"}), 400
    if not os.path.exists(filepath):
        return jsonify({"error": f"File not found: {filepath}"}), 400

    output_dir   = CONFIG["output_dir"]
    ensure_dir(output_dir)
    out_video    = os.path.join(output_dir, f"{label}_sermon.mp4")
    target       = CONFIG["loudness_target"]

    try:
        start_secs   = timestamp_to_seconds(start_ts)
        end_secs     = timestamp_to_seconds(end_ts)
        segment_secs = max(end_secs - start_secs, 1)
    except ValueError as e:
        return jsonify({"error": str(e)}), 400

    def run():
        push_progress("trim", 0, "Trimming and normalizing audio...")
        process = subprocess.Popen(
            ["ffmpeg", "-y", "-ss", start_ts, "-to", end_ts, "-i", filepath,
             "-af", f"loudnorm=I={target}:TP=-1.5:LRA=11",
             "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
             "-progress", "pipe:1", "-nostats", out_video],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        for line in process.stdout:
            if line.strip().startswith("out_time_ms="):
                try:
                    ms  = int(line.strip().split("=")[1])
                    sec = ms / 1_000_000
                    pct = min(int((sec / segment_secs) * 100), 99)
                    push_progress("trim", pct, f"Trimming... {seconds_to_timestamp(sec)}")
                except (ValueError, IndexError):
                    pass
        process.wait()
        if process.returncode != 0:
            push_error("trim", f"Trim failed: {process.stderr.read()[:300]}")
            return
        push_progress("trim", 100, "Trim complete")
        push_done("trim", {"filepath": out_video, "filename": os.path.basename(out_video)})

    threading.Thread(target=run, daemon=True).start()
    return jsonify({"ok": True})


# ─────────────────────────────────────────────────────────────
#  STEP 3 — EXPORT MP3
# ─────────────────────────────────────────────────────────────

@app.route("/export-audio", methods=["POST"])
def export_audio():
    body     = request.json or {}
    filepath = body.get("filepath", "")
    label    = body.get("label", datetime.today().strftime("%Y-%m-%d"))

    if not filepath or not os.path.exists(filepath):
        return jsonify({"error": "filepath is required and must exist"}), 400

    output_dir = CONFIG["output_dir"]
    ensure_dir(output_dir)
    out_audio  = os.path.join(output_dir, f"{label}_sermon.mp3")
    duration   = get_video_duration(filepath) or 1

    def run():
        push_progress("export", 0, "Exporting MP3...")
        process = subprocess.Popen(
            ["ffmpeg", "-y", "-i", filepath,
             "-vn", "-ar", "44100", "-ac", "2", "-b:a", "192k",
             "-progress", "pipe:1", "-nostats", out_audio],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        for line in process.stdout:
            if line.strip().startswith("out_time_ms="):
                try:
                    ms  = int(line.strip().split("=")[1])
                    sec = ms / 1_000_000
                    pct = min(int((sec / duration) * 100), 99)
                    push_progress("export", pct, f"Exporting... {seconds_to_timestamp(sec)}")
                except (ValueError, IndexError):
                    pass
        process.wait()
        if process.returncode != 0:
            push_error("export", f"Export failed: {process.stderr.read()[:300]}")
            return
        push_progress("export", 100, "MP3 ready")
        push_done("export", {"filepath": out_audio, "filename": os.path.basename(out_audio)})

    threading.Thread(target=run, daemon=True).start()
    return jsonify({"ok": True})


# ─────────────────────────────────────────────────────────────
#  STEP 4 — YOUTUBE CHANNELS & UPLOAD
# ─────────────────────────────────────────────────────────────

@app.route("/youtube/channels")
def youtube_channels():
    try:
        from googleapiclient.discovery import build
        youtube = build("youtube", "v3", credentials=_get_youtube_credentials())
        resp    = youtube.channels().list(part="snippet", mine=True, maxResults=50).execute()
        return jsonify([{
            "id":        ch["id"],
            "title":     ch["snippet"]["title"],
            "thumbnail": ch["snippet"].get("thumbnails", {}).get("default", {}).get("url", ""),
        } for ch in resp.get("items", [])])
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/youtube/upload", methods=["POST"])
def youtube_upload():
    body        = request.json or {}
    filepath    = body.get("filepath", "")
    title       = body.get("title", "")
    description = body.get("description", CONFIG["podcast_description"])
    privacy     = body.get("privacy", CONFIG["youtube_privacy"])

    if not filepath or not os.path.exists(filepath):
        return jsonify({"error": "filepath is required and must exist"}), 400
    if not title:
        return jsonify({"error": "title is required"}), 400

    def run():
        push_progress("upload", 0, "Authenticating with YouTube...")
        try:
            from googleapiclient.discovery import build
            from googleapiclient.http import MediaFileUpload
            youtube = build("youtube", "v3", credentials=_get_youtube_credentials())
        except Exception as e:
            push_error("upload", f"YouTube auth failed: {e}")
            return

        push_progress("upload", 5, "Starting upload...")
        body_data = {
            "snippet": {"title": title, "description": description, "categoryId": "22"},
            "status":  {"privacyStatus": privacy},
        }
        media   = MediaFileUpload(filepath, chunksize=256*1024, resumable=True, mimetype="video/mp4")
        req_obj = youtube.videos().insert(part="snippet,status", body=body_data, media_body=media)
        response = None
        while response is None:
            status, response = req_obj.next_chunk()
            if status:
                pct = min(int(status.progress() * 100), 99)
                push_progress("upload", pct, f"Uploading... {pct}%")

        video_id   = response["id"]
        studio_url = f"https://studio.youtube.com/video/{video_id}/edit"
        push_progress("upload", 100, "Upload complete!")
        push_done("upload", {
            "video_id":   video_id,
            "video_url":  f"https://www.youtube.com/watch?v={video_id}",
            "studio_url": studio_url,
        })
        webbrowser.open(studio_url)

    threading.Thread(target=run, daemon=True).start()
    return jsonify({"ok": True})


# ─────────────────────────────────────────────────────────────
#  STEP 5 — OPEN SPOTIFY FOR PODCASTERS
# ─────────────────────────────────────────────────────────────

@app.route("/spotify/open", methods=["POST"])
def spotify_open():
    filepath = (request.json or {}).get("filepath", "")
    if filepath:
        try:
            subprocess.run(["pbcopy"], input=os.path.abspath(filepath).encode(), check=True)
        except Exception:
            pass
    webbrowser.open("https://podcasters.spotify.com/pod/dashboard/episode/new")
    return jsonify({"ok": True})


# ─────────────────────────────────────────────────────────────
#  CLEAN FILES
# ─────────────────────────────────────────────────────────────

@app.route("/clean/list")
def clean_list():
    files = []
    for d, label in [(CONFIG["output_dir"], "output"), (CONFIG["inbox_dir"], "inbox")]:
        if os.path.isdir(d):
            for ext in ["*.mp4", "*.mp3"]:
                for f in sorted(Path(d).glob(ext)):
                    files.append({
                        "label":   label, "name": f.name,
                        "path":    str(f),
                        "size_mb": round(f.stat().st_size / (1024 * 1024), 1),
                    })
    return jsonify(files)


@app.route("/clean/delete", methods=["POST"])
def clean_delete():
    paths   = (request.json or {}).get("paths", [])
    deleted, errors = [], []
    for p in paths:
        try:
            os.remove(p)
            deleted.append(p)
        except OSError as e:
            errors.append({"path": p, "error": str(e)})
    return jsonify({"deleted": deleted, "errors": errors})


# ─────────────────────────────────────────────────────────────
#  YOUTUBE AUTH HELPER
# ─────────────────────────────────────────────────────────────

def _get_youtube_credentials():
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from google.auth.transport.requests import Request

    scopes     = ["https://www.googleapis.com/auth/youtube.upload",
                  "https://www.googleapis.com/auth/youtube"]
    token_file = CONFIG["token_file"]
    creds      = None

    if os.path.exists(token_file):
        creds = Credentials.from_authorized_user_file(token_file, scopes)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not os.path.exists(CONFIG["client_secrets_file"]):
                raise FileNotFoundError(
                    f"client_secrets.json not found at {CONFIG['client_secrets_file']}"
                )
            flow  = InstalledAppFlow.from_client_secrets_file(CONFIG["client_secrets_file"], scopes)
            creds = flow.run_local_server(port=0)
        with open(token_file, "w") as f:
            f.write(creds.to_json())
    return creds


# ─────────────────────────────────────────────────────────────
#  ENTRYPOINT
# ─────────────────────────────────────────────────────────────

if __name__ == "__main__":
    port = int(os.environ.get("CP_PORT", 5001))
    print(f"Church Podcast server on http://localhost:{port}", flush=True)
    app.run(host="127.0.0.1", port=port, threaded=True)
