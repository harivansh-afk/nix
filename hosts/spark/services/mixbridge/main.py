"""Authenticated SoundCloud and Spotify extraction for Mixbridge clients."""
from fastapi import APIRouter, Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import yt_dlp
import os
import re
import base64
import requests
from typing import Optional
from urllib.parse import urlsplit

from auth import require_user

app = FastAPI(title="Mixbridge streaming API", docs_url=None, redoc_url=None, openapi_url=None)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://mixbridge.app", "https://www.mixbridge.app"],
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
    expose_headers=["X-Track-Title", "X-Track-Artist", "X-Track-Album", "Retry-After"],
)
api = APIRouter(dependencies=[Depends(require_user)])
MAX_AUDIO_BYTES = 50 * 1024 * 1024


def soundcloud_url(value: str) -> str:
    try:
        url = urlsplit(value)
        if (url.scheme != "https" or url.hostname not in {"soundcloud.com", "www.soundcloud.com"}
                or url.username is not None or url.password is not None
                or url.port not in (None, 443)
                or not re.fullmatch(r"/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+/?", url.path)
                or url.path.strip("/").split("/")[1] == "sets"):
            raise ValueError
    except ValueError:
        raise HTTPException(400, "A public SoundCloud track URL is required") from None
    return "https://soundcloud.com" + url.path.rstrip("/")


def bound_download(status):
    if (status.get("downloaded_bytes") or 0) > MAX_AUDIO_BYTES:
        raise yt_dlp.DownloadError("Audio download exceeds 50 MiB")


def downloader(options):
    return yt_dlp.YoutubeDL({
        **options,
        "noplaylist": True,
        "socket_timeout": 15,
        "retries": 2,
        "fragment_retries": 2,
        "max_filesize": MAX_AUDIO_BYTES,
        "progress_hooks": [bound_download],
    })

# Spotify API helpers
SPOTIFY_CLIENT_ID = os.environ.get("SPOTIFY_CLIENT_ID")
SPOTIFY_CLIENT_SECRET = os.environ.get("SPOTIFY_CLIENT_SECRET")

def get_spotify_token() -> str:
    """Get Spotify access token via client credentials flow."""
    if not SPOTIFY_CLIENT_ID or not SPOTIFY_CLIENT_SECRET:
        raise HTTPException(500, "Spotify credentials not configured")

    auth_str = f"{SPOTIFY_CLIENT_ID}:{SPOTIFY_CLIENT_SECRET}"
    auth_b64 = base64.b64encode(auth_str.encode()).decode()

    resp = requests.post(
        "https://accounts.spotify.com/api/token",
        headers={"Authorization": f"Basic {auth_b64}"},
        data={"grant_type": "client_credentials"},
        timeout=10,
    )

    if resp.status_code != 200:
        raise HTTPException(500, f"Spotify auth failed: {resp.text}")

    return resp.json()["access_token"]

def get_spotify_track(track_id: str) -> dict:
    """Fetch track metadata from Spotify API."""
    token = get_spotify_token()
    resp = requests.get(
        f"https://api.spotify.com/v1/tracks/{track_id}",
        headers={"Authorization": f"Bearer {token}"},
        timeout=10,
    )

    if resp.status_code != 200:
        raise HTTPException(400, f"Spotify track not found: {resp.text}")

    data = resp.json()
    return {
        "title": data["name"],
        "artist": ", ".join(a["name"] for a in data["artists"]),
        "album": data["album"]["name"],
        "duration_ms": data["duration_ms"],
        "cover_url": data["album"]["images"][0]["url"] if data["album"]["images"] else None,
    }

def parse_spotify_url(url: str) -> str:
    """Extract track ID from Spotify URL."""
    match = re.fullmatch(r"spotify:track:([a-zA-Z0-9]{22})", url)
    if match:
        return match.group(1)
    try:
        parsed = urlsplit(url)
        if (parsed.scheme == "https" and parsed.hostname == "open.spotify.com"
                and parsed.username is None and parsed.password is None
                and parsed.port in (None, 443)):
            match = re.fullmatch(r"/track/([a-zA-Z0-9]{22})/?", parsed.path)
            if match:
                return match.group(1)
    except ValueError:
        pass
    raise HTTPException(400, "Invalid Spotify track URL")

class StreamRequest(BaseModel):
    url: str = Field(min_length=1, max_length=2048)

class StreamResponse(BaseModel):
    stream_url: str
    format: str
    title: str | None = None
    duration: float | None = None
    is_direct: bool = True  # False if HLS (requires /download endpoint)

@app.get("/health")
def health():
    return {"status": "ok"}

@api.post("/stream", response_model=StreamResponse)
def get_stream(request: StreamRequest):
    """Extract an audio stream from a public SoundCloud track."""
    
    url = soundcloud_url(request.url)
    
    # iOS needs direct HTTP download URLs, not HLS streams
    # Priority: HTTP MP3 (direct download) > HLS AAC if no HTTP available
    ydl_opts = {
        "format": "bestaudio",
        "quiet": True,
        "no_warnings": True,
        "extract_flat": False,
    }
    
    try:
        with downloader(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False, ie_key="Soundcloud")
            
            formats = info.get("formats", [])
            
            # Separate by protocol - prefer HTTP (direct download) over HLS
            http_formats = [f for f in formats if f.get("protocol") == "http" or f.get("protocol") == "https"]
            hls_formats = [f for f in formats if "m3u8" in str(f.get("protocol", ""))]
            
            # Filter each for iOS-compatible codecs (no opus)
            http_compatible = [f for f in http_formats if f.get("acodec") in ("mp3", "aac") or "mp4a" in f.get("acodec", "") or f.get("ext") == "mp3"]
            hls_compatible = [f for f in hls_formats if f.get("acodec") and ("aac" in f.get("acodec", "") or "mp4a" in f.get("acodec", "") or f.get("acodec") == "mp3")]
            
            # Prefer HTTP (direct download) over HLS
            is_direct = True
            if http_compatible:
                best = max(http_compatible, key=lambda f: f.get("abr", 0) or 0)
            elif hls_compatible:
                best = max(hls_compatible, key=lambda f: f.get("abr", 0) or 0)
                is_direct = False  # HLS requires /download endpoint
            else:
                raise HTTPException(400, "No iOS-compatible format found")
            
            return StreamResponse(
                stream_url=best["url"],
                format=best.get("acodec", "unknown"),
                title=info.get("title"),
                duration=info.get("duration"),
                is_direct=is_direct,
            )
    except yt_dlp.DownloadError as e:
        raise HTTPException(400, f"Extraction failed: {str(e)}")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Server error: {str(e)}")

@api.post("/download")
def download_track(request: StreamRequest):
    """Download track and return the audio file directly (handles HLS)."""
    from fastapi.responses import Response
    import tempfile
    
    url = soundcloud_url(request.url)
    
    with tempfile.TemporaryDirectory() as tmpdir:
        output_path = os.path.join(tmpdir, "audio.mp3")
        
        ydl_opts = {
            "format": "bestaudio[protocol=http]/bestaudio[acodec=mp3]/bestaudio[acodec=aac]/bestaudio",
            "quiet": True,
            "no_warnings": True,
            "outtmpl": output_path.replace(".mp3", ".%(ext)s"),
            "postprocessors": [{
                "key": "FFmpegExtractAudio",
                "preferredcodec": "mp3",
                "preferredquality": "192",
            }],
        }
        
        try:
            with downloader(ydl_opts) as ydl:
                ydl.extract_info(url, download=True, ie_key="Soundcloud")
            
            # Find the output file (might have different extension)
            for f in os.listdir(tmpdir):
                if f.startswith("audio"):
                    output_path = os.path.join(tmpdir, f)
                    break
            
            if not os.path.exists(output_path):
                raise HTTPException(500, "Download failed - no output file")
            
            if os.path.getsize(output_path) > MAX_AUDIO_BYTES:
                raise HTTPException(413, "Audio download exceeds 50 MiB")
            with open(output_path, "rb") as f:
                audio_data = f.read()
            
            return Response(
                content=audio_data,
                media_type="audio/mpeg",
                headers={"Content-Disposition": "attachment; filename=track.mp3"}
            )
        except yt_dlp.DownloadError as e:
            raise HTTPException(400, f"Download failed: {str(e)}")
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(500, f"Server error: {str(e)}")

# --- Spotify Endpoints ---

class SpotifyRequest(BaseModel):
    url: str = Field(min_length=1, max_length=2048)

class SpotifyStreamResponse(BaseModel):
    stream_url: str
    format: str
    title: str
    artist: str
    album: str
    duration_ms: int
    cover_url: Optional[str] = None
    youtube_url: str

@api.post("/spotify/stream", response_model=SpotifyStreamResponse)
def spotify_stream(request: SpotifyRequest):
    """Get stream URL for a Spotify track (searches YouTube)."""
    track_id = parse_spotify_url(request.url)
    track = get_spotify_track(track_id)

    search_query = f"{track['artist']} - {track['title']}"

    ydl_opts = {
        "format": "bestaudio",
        "quiet": True,
        "no_warnings": True,
        "default_search": "ytsearch",
        "noplaylist": True,
    }

    try:
        with downloader(ydl_opts) as ydl:
            info = ydl.extract_info(f"ytsearch:{search_query}", download=False)
            if not info.get("entries"):
                raise HTTPException(404, "No YouTube match found")

            video = info["entries"][0]
            formats = video.get("formats", [])

            # Get best audio format (prefer m4a for iOS)
            audio_formats = [f for f in formats if f.get("acodec") != "none" and f.get("vcodec") == "none"]
            if not audio_formats:
                audio_formats = [f for f in formats if f.get("acodec") != "none"]

            if not audio_formats:
                raise HTTPException(404, "No audio format found")

            # Prefer m4a/mp4 for iOS compatibility
            m4a_formats = [f for f in audio_formats if f.get("ext") in ("m4a", "mp4")]
            if m4a_formats:
                best = max(m4a_formats, key=lambda f: f.get("abr", 0) or 0)
            else:
                best = max(audio_formats, key=lambda f: f.get("abr", 0) or 0)

            return SpotifyStreamResponse(
                stream_url=best["url"],
                format=best.get("acodec", "unknown"),
                title=track["title"],
                artist=track["artist"],
                album=track["album"],
                duration_ms=track["duration_ms"],
                cover_url=track["cover_url"],
                youtube_url=video.get("webpage_url", ""),
            )
    except yt_dlp.DownloadError as e:
        raise HTTPException(400, f"YouTube search failed: {str(e)}")

@api.post("/spotify/download")
def spotify_download(request: SpotifyRequest):
    """Download Spotify track as M4A (via YouTube)."""
    from fastapi.responses import Response
    import tempfile

    track_id = parse_spotify_url(request.url)
    track = get_spotify_track(track_id)

    search_query = f"{track['artist']} - {track['title']}"

    with tempfile.TemporaryDirectory() as tmpdir:
        output_template = os.path.join(tmpdir, "%(title)s.%(ext)s")

        ydl_opts = {
            "format": "bestaudio[ext=m4a]/bestaudio",
            "quiet": True,
            "no_warnings": True,
            "default_search": "ytsearch",
            "noplaylist": True,
            "outtmpl": output_template,
        }

        try:
            with downloader(ydl_opts) as ydl:
                ydl.download([f"ytsearch:{search_query}"])

            # Find the downloaded file
            audio_file = None
            for f in os.listdir(tmpdir):
                if f.endswith((".m4a", ".webm", ".opus", ".mp3")):
                    audio_file = os.path.join(tmpdir, f)
                    break

            if not audio_file or not os.path.exists(audio_file):
                raise HTTPException(500, "Download failed - no output file")

            if os.path.getsize(audio_file) > MAX_AUDIO_BYTES:
                raise HTTPException(413, "Audio download exceeds 50 MiB")
            with open(audio_file, "rb") as f:
                audio_data = f.read()

            ext = os.path.splitext(audio_file)[1]
            filename = f"{track['artist']} - {track['title']}{ext}"
            safe_filename = "".join(c for c in filename if c.isalnum() or c in " -_.").strip()

            mime_type = "audio/mp4" if ext == ".m4a" else "audio/webm" if ext == ".webm" else "audio/mpeg"

            return Response(
                content=audio_data,
                media_type=mime_type,
                headers={
                    "Content-Disposition": f'attachment; filename="{safe_filename}"',
                    "X-Track-Title": track["title"],
                    "X-Track-Artist": track["artist"],
                    "X-Track-Album": track["album"],
                }
            )
        except yt_dlp.DownloadError as e:
            raise HTTPException(400, f"Download failed: {str(e)}")

@api.get("/spotify/search")
def spotify_search(q: str, limit: int = 10):
    """Search Spotify for tracks."""
    if not q.strip() or len(q) > 200 or not 1 <= limit <= 50:
        raise HTTPException(400, "Search requires a query of 1–200 characters and a limit of 1–50")
    token = get_spotify_token()
    resp = requests.get(
        "https://api.spotify.com/v1/search",
        headers={"Authorization": f"Bearer {token}"},
        params={"q": q, "type": "track", "limit": limit},
        timeout=10,
    )

    if resp.status_code != 200:
        raise HTTPException(400, f"Search failed: {resp.text}")

    tracks = resp.json().get("tracks", {}).get("items", [])
    return {
        "results": [
            {
                "id": t["id"],
                "url": t["external_urls"]["spotify"],
                "title": t["name"],
                "artist": ", ".join(a["name"] for a in t["artists"]),
                "album": t["album"]["name"],
                "duration_ms": t["duration_ms"],
                "cover_url": t["album"]["images"][0]["url"] if t["album"]["images"] else None,
            }
            for t in tracks
        ]
    }

app.include_router(api)


if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
