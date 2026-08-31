"""
yt-dlp API for SoundCloud and Spotify stream extraction.
Deploy to Railway/Render/Fly.io for free.
"""
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import yt_dlp
import os
import re
import base64
import requests
from typing import Optional

app = FastAPI(title="yt-dlp API")

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
    patterns = [
        r"spotify\.com/track/([a-zA-Z0-9]+)",
        r"spotify:track:([a-zA-Z0-9]+)",
    ]
    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            return match.group(1)
    raise HTTPException(400, "Invalid Spotify track URL")

class StreamRequest(BaseModel):
    url: str

class StreamResponse(BaseModel):
    stream_url: str
    format: str
    title: str | None = None
    duration: float | None = None
    is_direct: bool = True  # False if HLS (requires /download endpoint)

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/stream", response_model=StreamResponse)
def get_stream(request: StreamRequest):
    """Extract stream URL from SoundCloud (or other supported sites)."""
    
    if "soundcloud.com" not in request.url:
        raise HTTPException(400, "Only SoundCloud URLs are supported")
    
    # iOS needs direct HTTP download URLs, not HLS streams
    # Priority: HTTP MP3 (direct download) > HLS AAC if no HTTP available
    ydl_opts = {
        "format": "bestaudio",
        "quiet": True,
        "no_warnings": True,
        "extract_flat": False,
    }
    
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(request.url, download=False)
            
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
    except Exception as e:
        raise HTTPException(500, f"Server error: {str(e)}")

@app.post("/download")
def download_track(request: StreamRequest):
    """Download track and return the audio file directly (handles HLS)."""
    from fastapi.responses import Response
    import tempfile
    
    if "soundcloud.com" not in request.url:
        raise HTTPException(400, "Only SoundCloud URLs are supported")
    
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
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                ydl.download([request.url])
            
            # Find the output file (might have different extension)
            for f in os.listdir(tmpdir):
                if f.startswith("audio"):
                    output_path = os.path.join(tmpdir, f)
                    break
            
            if not os.path.exists(output_path):
                raise HTTPException(500, "Download failed - no output file")
            
            with open(output_path, "rb") as f:
                audio_data = f.read()
            
            return Response(
                content=audio_data,
                media_type="audio/mpeg",
                headers={"Content-Disposition": "attachment; filename=track.mp3"}
            )
        except yt_dlp.DownloadError as e:
            raise HTTPException(400, f"Download failed: {str(e)}")
        except Exception as e:
            raise HTTPException(500, f"Server error: {str(e)}")

# --- Spotify Endpoints ---

class SpotifyRequest(BaseModel):
    url: str

class SpotifyStreamResponse(BaseModel):
    stream_url: str
    format: str
    title: str
    artist: str
    album: str
    duration_ms: int
    cover_url: Optional[str] = None
    youtube_url: str

@app.post("/spotify/stream", response_model=SpotifyStreamResponse)
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
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
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

@app.post("/spotify/download")
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
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                ydl.download([f"ytsearch:{search_query}"])

            # Find the downloaded file
            audio_file = None
            for f in os.listdir(tmpdir):
                if f.endswith((".m4a", ".webm", ".opus", ".mp3")):
                    audio_file = os.path.join(tmpdir, f)
                    break

            if not audio_file or not os.path.exists(audio_file):
                raise HTTPException(500, "Download failed - no output file")

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

@app.get("/spotify/search")
def spotify_search(q: str, limit: int = 10):
    """Search Spotify for tracks."""
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

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
