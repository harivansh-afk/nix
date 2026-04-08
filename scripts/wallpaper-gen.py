"""Generate topographic contour wallpapers from real-world elevation data."""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import json
import math
import os
import random
import subprocess
import sys
import urllib.request
from datetime import datetime
from io import BytesIO
from typing import Iterator

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

Coord = tuple[float, float]
Candidate = tuple[float, float, str]
Rgb = tuple[int, int, int]
TileTask = tuple[int, int, int, int, int]


def load_settings() -> dict[str, object]:
    config_path = os.environ.get("WALLPAPER_GEN_CONFIG")
    if not config_path:
        return {}
    try:
        with open(config_path, encoding="utf-8") as f:
            settings = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}
    return settings if isinstance(settings, dict) else {}


SETTINGS = load_settings()


def section(name: str) -> dict[str, object]:
    value = SETTINGS.get(name, {})
    return value if isinstance(value, dict) else {}


HOME: str = os.environ["HOME"]
DIR: str = os.path.join(HOME, "Pictures", "Screensavers")
STATE: str = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local", "state")),
    "theme",
    "current",
)
LOG_DIR: str = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local", "state")),
    "wallpaper",
)
LOG_FILE: str = os.path.join(LOG_DIR, "gen.log")
HISTORY_FILE: str = os.path.join(LOG_DIR, "history.json")
CACHE: str = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")),
    "wallpaper",
)

os.makedirs(DIR, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)
os.makedirs(CACHE, exist_ok=True)

VIEW = section("view")
CONTOURS = section("contours")
CANDIDATE_POOL = section("candidatePool")
LABEL = section("label")

TILE_URL: str = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
TILE_SIZE: int = 256
ZOOM: int = int(VIEW.get("zoom", 11))
TILE_FETCH_JOBS: int = max(1, int(VIEW.get("tileConcurrency", 6)))
CONTOUR_LEVELS: int = max(1, int(CONTOURS.get("levels", 20)))

# cozybox palette - matches lib/theme.nix
THEMES: dict[str, dict[str, Rgb]] = {
    "dark": {
        "bg": (0x18, 0x18, 0x18),
        "line": (0x2d, 0x2d, 0x2d),
        "label": (0xFF, 0xFF, 0xFF),
    },
    "light": {
        "bg": (0xE7, 0xE7, 0xE7),
        "line": (0xCE, 0xCE, 0xCE),
        "label": (0x00, 0x00, 0x00),
    },
}

# curated mountain/terrain locations with interesting topography
LOCATIONS: list[Coord] = [
    (46.56, 7.69),      # Swiss Alps - Bernese Oberland
    (36.10, -112.09),    # Grand Canyon
    (27.99, 86.93),      # Everest region
    (61.22, 6.78),       # Norwegian fjords
    (-50.94, -73.15),    # Patagonia
    (36.25, 137.60),     # Japanese Alps
    (39.11, -106.45),    # Colorado Rockies
    (46.42, 11.84),      # Dolomites
    (44.07, 6.87),       # French Alps
    (-43.59, 170.14),    # New Zealand Alps
    (64.07, -16.20),     # Iceland highlands
    (28.60, 83.82),      # Annapurna
    (42.50, 44.50),      # Caucasus
    (47.07, 12.69),      # Austrian Alps
    (45.83, 6.86),       # Mont Blanc
]

CONTOUR_OVERSAMPLE: int = 2
CONTOUR_BLUR_RADIUS: float = 15
CONTOUR_GROW_FILTER_SIZE: int = 3
CONTOUR_SOFTEN_RADIUS: float = 1.5
CONTOUR_THRESHOLD: int = 80
MIN_RELIEF: int = 400
MAX_RETRIES: int = max(0, int(CANDIDATE_POOL.get("randomAttempts", 20)))
SEA_LEVEL: int = 32768
MIN_LAND_FRACTION: float = 0.1
PREVIEW_W: int = 384
PREVIEW_H: int = 240
GRID_COLS: int = 6
GRID_ROWS: int = 4
MIN_CONTOUR_COVERAGE: float = 0.15
MIN_OCCUPIED_CELLS: int = 12
MAX_CELL_SHARE: float = 0.15
MAX_CACHED_CANDIDATES: int = max(0, int(CANDIDATE_POOL.get("maxCached", 24)))
HISTORY_SIZE: int = max(1, int(CANDIDATE_POOL.get("historySize", 10)))
LABEL_ENABLED: bool = bool(LABEL.get("enabled", True))
LABEL_FONT_SIZE: int = max(1, int(LABEL.get("fontSize", 14)))
LABEL_MARGIN_X: int = 24
LABEL_MARGIN_BOTTOM: int = 30
RUN_ID: str = f"{datetime.now().strftime('%Y%m%dT%H%M%S')}-pid{os.getpid()}"


def log(message: str) -> None:
    line = f"{datetime.now().astimezone().isoformat(timespec='seconds')} [{RUN_ID}] {message}"
    print(line, file=sys.stderr, flush=True)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        print(line, file=f)


def load_history() -> list[Coord]:
    try:
        with open(HISTORY_FILE, encoding="utf-8") as f:
            entries = json.load(f)
        return [(e[0], e[1]) for e in entries if isinstance(e, list) and len(e) == 2]
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        return []


def save_history(lat: float, lon: float) -> None:
    history = load_history()
    history.append((round(lat, 2), round(lon, 2)))
    history = history[-HISTORY_SIZE:]
    with open(HISTORY_FILE, "w", encoding="utf-8") as f:
        json.dump(history, f)


def random_location() -> Coord:
    return random.uniform(-60, 70), random.uniform(-180, 180)


def cached_locations(tiles_x: int, tiles_y: int) -> list[Coord]:
    suffix = f"_z{ZOOM}_{tiles_x}x{tiles_y}.png"
    locations: list[Coord] = []
    for name in os.listdir(CACHE):
        if not name.startswith("terrain_") or not name.endswith(suffix):
            continue
        coords = name[len("terrain_") : -len(suffix)]
        try:
            lat, lon = coords.split("_", 1)
            locations.append((float(lat), float(lon)))
        except ValueError:
            continue
    random.shuffle(locations)
    return locations[:MAX_CACHED_CANDIDATES]


def candidate_locations(tiles_x: int, tiles_y: int) -> Iterator[Candidate]:
    seen: set[Coord] = set()
    recent = {(round(lat, 2), round(lon, 2)) for lat, lon in load_history()}
    cached: list[Coord] = cached_locations(tiles_x, tiles_y)
    fallback: list[Coord] = list(LOCATIONS)
    random.shuffle(fallback)
    log(f"candidate_pools cached={len(cached)} curated={len(fallback)} random={MAX_RETRIES} recent_skip={len(recent)}")
    for lat, lon in cached:
        key = (round(lat, 2), round(lon, 2))
        if key in seen or key in recent:
            continue
        seen.add(key)
        yield lat, lon, "cached"
    for lat, lon in fallback:
        key = (round(lat, 2), round(lon, 2))
        if key in seen or key in recent:
            continue
        seen.add(key)
        yield lat, lon, "curated"
    for _ in range(MAX_RETRIES):
        lat, lon = random_location()
        key = (round(lat, 2), round(lon, 2))
        if key in seen or key in recent:
            continue
        seen.add(key)
        yield lat, lon, "random"


def reverse_geocode(lat: float, lon: float) -> str | None:
    try:
        url = f"https://nominatim.openstreetmap.org/reverse?lat={lat}&lon={lon}&format=json&zoom=6&accept-language=en"
        req = urllib.request.Request(url, headers={"User-Agent": "wallpaper-gen/1.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read())
        addr = data.get("address", {})
        name = (
            addr.get("region")
            or addr.get("state_district")
            or addr.get("state")
            or addr.get("county")
            or addr.get("country")
        )
        return name
    except Exception:
        return None


def get_resolution() -> tuple[int, int]:
    """Get primary display resolution on macOS."""
    try:
        out = subprocess.check_output(
            ["system_profiler", "SPDisplaysDataType", "-json"],
            timeout=5,
        ).decode()
        displays = json.loads(out)
        for gpu in displays.get("SPDisplaysDataType", []):
            for disp in gpu.get("spdisplays_ndrvs", []):
                res = disp.get("_spdisplays_resolution", "")
                if " x " in res:
                    parts = res.split(" x ")
                    w = int(parts[0].strip())
                    h = int(parts[1].split()[0].strip())
                    return w, h
    except Exception:
        pass
    return 3024, 1964  # MacBook Pro 14" default


def lat_lon_to_tile(lat: float, lon: float, zoom: int) -> tuple[int, int]:
    n = 2**zoom
    x = int(n * ((lon + 180) / 360))
    lat_rad = math.radians(lat)
    y = int(n * (1 - (math.log(math.tan(lat_rad) + 1 / math.cos(lat_rad)) / math.pi)) / 2)
    return x, y


def fetch_tile(z: int, x: int, y: int) -> Image.Image:
    url = TILE_URL.format(z=z, x=x, y=y)
    req = urllib.request.Request(url, headers={"User-Agent": "wallpaper-gen/1.0"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        tile = Image.open(BytesIO(resp.read()))
        tile.load()
        return tile


def fetch_tile_task(task: TileTask) -> tuple[int, int, Image.Image]:
    tx, ty, zoom, tile_x, tile_y = task
    return tx, ty, fetch_tile(zoom, tile_x, tile_y)


def fetch_terrain(
    lat: float, lon: float, tiles_x: int, tiles_y: int, zoom: int
) -> tuple[Image.Image, bool]:
    tag = f"{lat:.2f}_{lon:.2f}_z{zoom}_{tiles_x}x{tiles_y}"
    cache_file = os.path.join(CACHE, f"terrain_{tag}.png")
    if os.path.exists(cache_file):
        with Image.open(cache_file) as cached:
            return cached.copy(), True
    cx, cy = lat_lon_to_tile(lat, lon, zoom)
    sx, sy = cx - tiles_x // 2, cy - tiles_y // 2
    full = Image.new("RGB", (tiles_x * TILE_SIZE, tiles_y * TILE_SIZE))
    tasks = [
        (tx, ty, zoom, sx + tx, sy + ty)
        for ty in range(tiles_y)
        for tx in range(tiles_x)
    ]
    if TILE_FETCH_JOBS == 1:
        results = map(fetch_tile_task, tasks)
    else:
        with ThreadPoolExecutor(max_workers=TILE_FETCH_JOBS) as executor:
            results = executor.map(fetch_tile_task, tasks)
            for tx, ty, tile in results:
                full.paste(tile, (tx * TILE_SIZE, ty * TILE_SIZE))
            full.save(cache_file)
            return full, False
    for tx, ty, tile in results:
        full.paste(tile, (tx * TILE_SIZE, ty * TILE_SIZE))
    full.save(cache_file)
    return full, False


def decode_terrarium(img: Image.Image) -> tuple[Image.Image, int, float]:
    raw_bytes = img.tobytes()
    px_count = len(raw_bytes) // 3
    raw: list[int] = [0] * px_count
    land: int = 0
    for i in range(px_count):
        off = i * 3
        raw[i] = (raw_bytes[off] << 8) | raw_bytes[off + 1]
        if raw[i] > SEA_LEVEL:
            land += 1
    lo, hi = min(raw), max(raw)
    rng = hi - lo or 1
    norm = bytearray((e - lo) * 255 // rng for e in raw)
    return Image.frombytes("L", img.size, bytes(norm)), hi - lo, land / px_count


def build_contour_mask(elevation: Image.Image, W: int, H: int) -> Image.Image:
    S: int = CONTOUR_OVERSAMPLE
    iW, iH = W * S, H * S
    terrain = elevation.resize((iW, iH), Image.BICUBIC)
    terrain = terrain.filter(ImageFilter.GaussianBlur(radius=CONTOUR_BLUR_RADIUS * S))
    step = max(1, 256 // CONTOUR_LEVELS)
    terrain = terrain.point(lambda p: (p // step) * step)
    eroded = terrain.filter(ImageFilter.MinFilter(3))
    edges = ImageChops.subtract(terrain, eroded)
    edges = edges.point(lambda p: 255 if p > 0 else 0)
    edges = edges.filter(ImageFilter.MaxFilter(CONTOUR_GROW_FILTER_SIZE))
    edges = edges.filter(ImageFilter.GaussianBlur(radius=CONTOUR_SOFTEN_RADIUS * S))
    return edges.point(lambda p: 255 if p > CONTOUR_THRESHOLD else 0)


def contour_stats(elevation: Image.Image) -> tuple[float, int, float]:
    mask = build_contour_mask(elevation, PREVIEW_W, PREVIEW_H).resize(
        (PREVIEW_W, PREVIEW_H), Image.NEAREST
    )
    mask_bytes = mask.tobytes()
    total: int = len(mask_bytes)
    filled: int = 0
    cell_counts: list[int] = [0] * (GRID_COLS * GRID_ROWS)
    for y in range(PREVIEW_H):
        row_off = y * PREVIEW_W
        cy = y * GRID_ROWS // PREVIEW_H
        for x in range(PREVIEW_W):
            if mask_bytes[row_off + x]:
                filled += 1
                cx = x * GRID_COLS // PREVIEW_W
                cell_counts[cy * GRID_COLS + cx] += 1
    coverage = filled / total
    occupied = sum(1 for count in cell_counts if count)
    largest_share = max(cell_counts) / filled if filled else 1
    return coverage, occupied, largest_share


def candidate_summary(
    elevation: Image.Image, relief: int, land_fraction: float
) -> tuple[bool, str]:
    if relief < MIN_RELIEF or land_fraction < MIN_LAND_FRACTION:
        return False, (
            f"relief={relief} land_fraction={land_fraction:.3f} "
            f"thresholds=({MIN_RELIEF},{MIN_LAND_FRACTION:.3f})"
        )
    coverage, occupied, largest_share = contour_stats(elevation)
    ok = (
        coverage >= MIN_CONTOUR_COVERAGE
        and occupied >= MIN_OCCUPIED_CELLS
        and largest_share <= MAX_CELL_SHARE
    )
    return ok, (
        f"relief={relief} land_fraction={land_fraction:.3f} "
        f"coverage={coverage:.3f} occupied={occupied} largest_cell_share={largest_share:.3f} "
        f"thresholds=({MIN_CONTOUR_COVERAGE:.3f},{MIN_OCCUPIED_CELLS},{MAX_CELL_SHARE:.3f})"
    )


def render_contours(mask: Image.Image, W: int, H: int, bg: Rgb, line_color: Rgb) -> Image.Image:
    S: int = CONTOUR_OVERSAMPLE
    iW, iH = W * S, H * S
    bg_img = Image.new("RGB", (iW, iH), bg)
    fg_img = Image.new("RGB", (iW, iH), line_color)
    img = Image.composite(fg_img, bg_img, mask)
    return img.resize((W, H), Image.LANCZOS)


def find_font() -> str | None:
    candidates = [
        os.path.join(HOME, "Library/Fonts/BerkeleyMono-Regular.otf"),
        os.path.join(HOME, "Library/Fonts/BerkeleyMono-Regular.ttf"),
        os.path.join(HOME, ".local/share/fonts/berkeley-mono/BerkeleyMono-Regular.ttf"),
        "/Library/Fonts/BerkeleyMono-Regular.otf",
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return None


def gen() -> None:
    W, H = get_resolution()
    tiles_x = math.ceil(W / TILE_SIZE)
    tiles_y = math.ceil(H / TILE_SIZE)

    theme = "dark"
    try:
        with open(STATE) as f:
            t = f.read().strip()
            if t in THEMES:
                theme = t
    except FileNotFoundError:
        pass

    log(
        f"start theme={theme} resolution={W}x{H} tiles={tiles_x}x{tiles_y} "
        f"zoom={ZOOM} contours={CONTOUR_LEVELS} tile_jobs={TILE_FETCH_JOBS}"
    )

    for index, (lat, lon, source) in enumerate(candidate_locations(tiles_x, tiles_y), start=1):
        log(f"candidate[{index}] source={source} lat={lat:.2f} lon={lon:.2f} begin")
        try:
            terrain_img, cache_hit = fetch_terrain(lat, lon, tiles_x, tiles_y, ZOOM)
        except Exception as err:
            log(f"candidate[{index}] source={source} lat={lat:.2f} lon={lon:.2f} fetch_error={err!r}")
            continue
        elevation, relief, land_fraction = decode_terrarium(terrain_img)
        ok, summary = candidate_summary(elevation, relief, land_fraction)
        status = "accept" if ok else "reject"
        cache = "hit" if cache_hit else "miss"
        log(f"candidate[{index}] source={source} lat={lat:.2f} lon={lon:.2f} cache={cache} {status} {summary}")
        if ok:
            break
    else:
        log("finish status=no_candidate")
        return

    elevation = elevation.crop((0, 0, min(elevation.width, W), min(elevation.height, H)))
    save_history(lat, lon)
    place = reverse_geocode(lat, lon) if LABEL_ENABLED else None
    log(f"selected lat={lat:.2f} lon={lon:.2f} place={place or '<none>'}")

    coords = f"{lat:.2f}, {lon:.2f}"
    label = f"{place} ({coords})" if place else coords
    font_path = find_font()
    font = None
    if LABEL_ENABLED:
        if font_path:
            font = ImageFont.truetype(font_path, LABEL_FONT_SIZE)
        else:
            font = ImageFont.load_default()
    contour_mask = build_contour_mask(elevation, W, H)

    for theme_name, colors in THEMES.items():
        img = render_contours(contour_mask, W, H, colors["bg"], colors["line"])
        if LABEL_ENABLED and font is not None:
            draw = ImageDraw.Draw(img)
            draw.text((LABEL_MARGIN_X, H - LABEL_MARGIN_BOTTOM), label, fill=colors["label"], font=font)
        out_path = os.path.join(DIR, f"wallpaper-{theme_name}.jpg")
        img.save(out_path, quality=95)
        log(f"wrote theme={theme_name} path={out_path}")

    link = os.path.join(DIR, "wallpaper.jpg")
    if os.path.lexists(link):
        os.unlink(link)
    target = os.path.join(DIR, f"wallpaper-{theme}.jpg")
    os.symlink(target, link)
    log(f"finish status=ok target={target} link={link}")


if __name__ == "__main__":
    gen()
