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


def tile_file(qud_tile_path):
    """'Creatures/sw_glowfish.bmp' -> absolute path of the extracted PNG."""
    rel = qud_tile_path.replace("\\", "/").lstrip("/")
    stem, _ext = os.path.splitext(rel)
    return path("tiles", *stem.split("/")) + ".png"


if __name__ == "__main__":
    print(store_dir())
    m = read_manifest()
    print("manifest:", "none" if m is None else json.dumps(m, indent=2))
