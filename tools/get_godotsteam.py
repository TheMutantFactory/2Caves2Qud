"""Fetch the GodotSteam GDExtension plugin into godot/addons/godotsteam/.

GodotSteam (MIT) wraps the Steamworks SDK for Godot; its binaries are not committed.
Run once, and again to change the version:

    python tools/get_godotsteam.py

Then `godot --headless --path godot --import` registers the extension. App id 480
(Valve's SpaceWar test app) is used until Drift Wizard has its own, so Steam must be
running and signed in for the online page to work.
"""
import io
import sys
import urllib.request
import zipfile
from pathlib import Path

VERSION = "4.22.1"
URL = f"https://codeberg.org/godotsteam/godotsteam/releases/download/v{VERSION}-gde/godotsteam-{VERSION}-gdextension-plugin-4.4.zip"
ROOT = Path(__file__).resolve().parent.parent / "godot"


def main() -> int:
    print("downloading", URL)
    data = urllib.request.urlopen(URL, timeout=120).read()
    z = zipfile.ZipFile(io.BytesIO(data))
    names = [n for n in z.namelist() if n.startswith("addons/godotsteam/")]
    z.extractall(ROOT, members=names)
    print(f"installed {len(names)} files under {ROOT / 'addons' / 'godotsteam'} ({len(data) // 1048576} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
