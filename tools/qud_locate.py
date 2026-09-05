"""Locate and validate the local Caves of Qud install.

Resolution order:
  1. QUD_DIR environment variable
  2. --game-dir CLI argument (handled by callers)
  3. every Steam library listed in libraryfolders.vdf
  4. the default Steam install path per OS

Nothing from the game is bundled with this repo; every tool reads from the
install this module finds and writes to the per-user asset store
(qud_assets.py), which lives OUTSIDE the repo.

An install is "valid" when the Unity data directory has the three things the
extractor needs: the managed assembly (Assembly-CSharp.dll), the serialized
asset file holding the tile atlases and audio (resources.assets + its
resources.resource stream), and the game's XML data (StreamingAssets/Base).
`validate()` reports each check so a broken or partial install fails loudly.

    python tools/qud_locate.py            # print the install report
"""
import json
import os
import plistlib
import re
import sys

STEAM_APPID = "333640"
GAME_FOLDER = "Caves of Qud"

DEFAULT_STEAM_ROOTS = [
    r"C:\Program Files (x86)\Steam",
    r"C:\Program Files\Steam",
    os.path.expanduser("~/.steam/steam"),
    os.path.expanduser("~/.local/share/Steam"),
    os.path.expanduser("~/Library/Application Support/Steam"),
]


def data_dir(game_dir):
    """The Unity `*_Data` directory for an install root, or None.

    macOS ships an app bundle (CoQ.app/Contents/Resources/Data); Windows and
    Linux ship a flat CoQ_Data next to the executable.
    """
    for rel in ("CoQ.app/Contents/Resources/Data", "CoQ_Data"):
        p = os.path.join(game_dir, rel)
        if os.path.isdir(p):
            return p
    return None


def looks_like_game_dir(path):
    return bool(path) and data_dir(path) is not None


def steam_library_roots():
    roots = []
    for steam in DEFAULT_STEAM_ROOTS:
        vdf = os.path.join(steam, "steamapps", "libraryfolders.vdf")
        if not os.path.exists(vdf):
            continue
        with open(vdf, "r", encoding="utf-8", errors="replace") as f:
            for m in re.finditer(r'"path"\s+"([^"]+)"', f.read()):
                roots.append(m.group(1).replace("\\\\", "\\"))
        roots.append(steam)
    return roots


def find_game_dir(explicit=None):
    candidates = []
    if explicit:
        candidates.append(explicit)
    if os.environ.get("QUD_DIR"):
        candidates.append(os.environ["QUD_DIR"])
    for root in steam_library_roots():
        candidates.append(os.path.join(root, "steamapps", "common", GAME_FOLDER))
    for c in candidates:
        if looks_like_game_dir(c):
            return os.path.abspath(c)
    raise FileNotFoundError(
        "Could not find the Caves of Qud install. Set QUD_DIR or pass --game-dir. "
        "Tried: " + ", ".join(candidates)
    )


def steam_manifest(game_dir):
    """The Steam appmanifest fields for the install (buildid etc.), or {}."""
    steamapps = os.path.dirname(os.path.dirname(game_dir))
    acf = os.path.join(steamapps, "appmanifest_%s.acf" % STEAM_APPID)
    if not os.path.exists(acf):
        return {}
    with open(acf, "r", encoding="utf-8", errors="replace") as f:
        text = f.read()
    out = {}
    for key in ("buildid", "name", "LastUpdated", "SizeOnDisk"):
        m = re.search(r'"%s"\s+"([^"]*)"' % key, text)
        if m:
            out[key] = m.group(1)
    return out


def app_version(game_dir):
    """The game's version string, from the macOS bundle plist when there is one."""
    plist = os.path.join(game_dir, "CoQ.app", "Contents", "Info.plist")
    if os.path.exists(plist):
        try:
            with open(plist, "rb") as f:
                return plistlib.load(f).get("CFBundleShortVersionString")
        except Exception:
            return None
    return None


def validate(game_dir):
    """-> dict describing the install and each check; `ok` is the verdict."""
    d = data_dir(game_dir)
    checks = {}
    if d is None:
        return {"game_dir": game_dir, "data_dir": None, "ok": False,
                "checks": {"data_dir": False}}
    paths = {
        "assembly": os.path.join(d, "Managed", "Assembly-CSharp.dll"),
        "resources.assets": os.path.join(d, "resources.assets"),
        "resources.resource": os.path.join(d, "resources.resource"),
        "streaming_base": os.path.join(d, "StreamingAssets", "Base"),
        "blueprints": os.path.join(d, "StreamingAssets", "Base", "ObjectBlueprints", "Creatures.xml"),
    }
    sizes = {}
    for k, p in paths.items():
        checks[k] = os.path.exists(p)
        if checks[k] and os.path.isfile(p):
            sizes[k] = os.path.getsize(p)
    return {
        "game_dir": game_dir,
        "data_dir": d,
        "version": app_version(game_dir),
        "steam": steam_manifest(game_dir),
        "checks": checks,
        "sizes": sizes,
        "ok": all(checks.values()),
    }


def install_fingerprint(report):
    """What a cached extraction is keyed on: the Steam build plus the sizes of
    the files we read. A game update changes at least one of these."""
    return {
        "buildid": report.get("steam", {}).get("buildid"),
        "version": report.get("version"),
        "sizes": report.get("sizes", {}),
    }


def main(argv):
    explicit = argv[1] if len(argv) > 1 else None
    try:
        game_dir = find_game_dir(explicit)
    except FileNotFoundError as e:
        print(e)
        return 2
    report = validate(game_dir)
    print(json.dumps(report, indent=2))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
