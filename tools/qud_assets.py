"""Where the extracted Caves of Qud assets live: a per-user directory OUTSIDE
the repo, written once by extract_qud.py and read by everything else.

    macOS    ~/Library/Application Support/2Caves2Qud/qud
    Windows  %LOCALAPPDATA%\\2Caves2Qud\\qud
    Linux    $XDG_DATA_HOME/2Caves2Qud/qud   (default ~/.local/share/...)

Override with the CAVES2_ASSETS environment variable. The store is a
derivative of the user's own paid copy of the game and is never shipped or
committed; each user extracts once and re-extracts only after a game update
(the manifest carries the install fingerprint that decides that).

Layout inside the store:

    manifest.json              install fingerprint + what was extracted + counts
    tiles/<Folder>/<name>.png  every atlas tile, at the game's own path with the
                               extension swapped to .png (blueprints say
                               "Creatures/sw_glowfish.bmp"; we hold
                               tiles/Creatures/sw_glowfish.png)
    tiles/index.json           game tile path -> {file, w, h, atlas}
    sfx/<name>.wav             every AudioClip, decoded to 16-bit PCM
    sfx/index.json             clip name -> {file, seconds, hz, channels}
    data/                      a copy of StreamingAssets/Base (blueprints,
                               Colors.xml, Sounds.xml, ...)
    walls/<family>.vox (+.json, .png)   voxel wall models, from wall2vox.py
"""
import json
import os
import sys

APP = "2Caves2Qud"


def store_dir():
    env = os.environ.get("CAVES2_ASSETS")
    if env:
        return os.path.abspath(os.path.expanduser(env))
    if sys.platform == "darwin":
        base = os.path.expanduser("~/Library/Application Support")
    elif sys.platform.startswith("win"):
        base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~\\AppData\\Local")
    else:
        base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(base, APP, "qud")


def path(*parts, mkdir=False):
    p = os.path.join(store_dir(), *parts)
    if mkdir:
        os.makedirs(p if not os.path.splitext(p)[1] else os.path.dirname(p), exist_ok=True)
    return p


def manifest_path():
    return path("manifest.json")


def read_manifest():
    try:
        with open(manifest_path(), "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def write_manifest(m):
    os.makedirs(store_dir(), exist_ok=True)
    tmp = manifest_path() + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(m, f, indent=2, sort_keys=True)
    os.replace(tmp, manifest_path())


_TILE_INDEX = None


def tile_index():
    """tiles/index.json keyed by the LOWER-CASED blueprint path. Blueprints write
    tile paths every which way ('Creatures/sw_crow.bmp', 'creatures\\sw_eel_2.bmp',
    'Assets_Content_Textures_Creatures_sw_farmer.bmp'); the game resolves them
    case-insensitively and so do we."""
    global _TILE_INDEX
    if _TILE_INDEX is None:
        _TILE_INDEX = {}
        try:
            with open(path("tiles", "index.json"), "r", encoding="utf-8") as f:
                for k, v in json.load(f).items():
                    _TILE_INDEX[k.lower()] = v
        except (OSError, ValueError):
            pass
    return _TILE_INDEX


def normalize_tile_path(qud_tile_path):
    """Any of the game's spellings -> 'folder/name.ext' lower-cased."""
    p = qud_tile_path.replace("\\", "/").strip().lstrip("/").lower()
    prefix = "assets_content_textures_"
    if p.startswith(prefix):
        rest = p[len(prefix):]
        folder, _, fname = rest.partition("_")
        p = folder + "/" + fname
    return p


def tile_file(qud_tile_path):
    """'Creatures/sw_glowfish.bmp' (any spelling) -> absolute path of the extracted
    PNG, or None when the store has no such tile."""
    key = normalize_tile_path(qud_tile_path)
    entry = tile_index().get(key)
    if entry is None:
        stem, _ext = os.path.splitext(key)
        for ext in (".bmp", ".png"):
            entry = tile_index().get(stem + ext)
            if entry:
                break
    if entry is None:
        return None
    return path("tiles", *entry["file"].split("/"))


if __name__ == "__main__":
    print(store_dir())
    m = read_manifest()
    print("manifest:", "none" if m is None else json.dumps(m, indent=2))
