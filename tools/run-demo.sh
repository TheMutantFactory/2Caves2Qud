#!/usr/bin/env bash
# The overland demo, end to end: a race on Joppa's real marsh (docs/overland.md).
#
#   tools/run-demo.sh              # play it: the Joppa course paved into the Qud surface, you drive
#   tools/run-demo.sh --auto       # the AI drives 300 frames and leaves reports/overland/demo.png
#   tools/run-demo.sh --night      # start at midnight   (--dusk: 19:24, --noon: 12:00; default: tuning's 18:00)
#   tools/run-demo.sh --free       # free drive from the start line instead of a race
#   tools/run-demo.sh --check      # only verify every piece is in place, run nothing
#   tools/run-demo.sh --track=redrock --anchor=JoppaWorld.12.22.0.0.10   # another course, elsewhere
#
# Every step is checked and skipped when its output already exists, so a second run goes
# straight to the game:
#   1. the asset store (tools/extract_qud.py + wall2vox.py), else it says how to make it
#   2. the baked chunks under <RavesOfQud>/chunks/<gameId>/ — if missing, Caves of Qud must
#      be running in-game with the Raves bridge (raves-of-qud branch dd/pc-world-bake) and
#      the 5x5 parasang region round Joppa is baked with tools/capture/bake.py
#   3. the world export in the store (tools/export_godot_assets.py), refreshed when the
#      chunks are newer than it
#   4. Godot, windowed, --overland
#
# Environment: CAVES2_ASSETS (the store), CAVES2_GODOT (the Godot binary), RAVES_DIR (the
# raves-of-qud checkout; default: beside this repo). Exit 1 on the first missing piece.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TRACK=joppa
ANCHOR=""
CLOCK=""
MODE=play
CHECK=0
for a in "$@"; do
  case "$a" in
    --auto) MODE=auto ;;
    --free) MODE=free ;;
    --check) CHECK=1 ;;
    --night) CLOCK=0 ;;
    --dusk) CLOCK=9700 ;;
    --noon) CLOCK=6000 ;;
    --clock=*) CLOCK="${a#--clock=}" ;;
    --track=*) TRACK="${a#--track=}" ;;
    --anchor=*) ANCHOR="${a#--anchor=}" ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "run-demo: unknown option $a (try --help)"; exit 2 ;;
  esac
done

say() { printf 'demo: %s\n' "$*"; }
die() { printf 'demo: %s\n' "$*" >&2; exit 1; }
# Python prints Windows paths with backslashes; this shell wants forward slashes
unix_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s\n' "$1"; fi; }

# --- the interpreters -----------------------------------------------------------------
if [ -x "$ROOT/.venv/Scripts/python.exe" ]; then PY="$ROOT/.venv/Scripts/python.exe"
elif [ -x "$ROOT/.venv/bin/python" ]; then PY="$ROOT/.venv/bin/python"
else die "no .venv (python -m venv .venv && pip install -r requirements-tools.txt)"; fi

GODOT="${CAVES2_GODOT:-}"
if [ -z "$GODOT" ]; then
  for g in \
    "/c/Users/danie/Downloads/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe" \
    "/Users/homefolder/Downloads/Godot.app/Contents/MacOS/Godot" \
    "$(command -v godot || true)"; do
    [ -n "$g" ] && [ -x "$g" ] && GODOT="$g" && break
  done
fi
[ -n "$GODOT" ] && [ -x "$GODOT" ] || die "no Godot binary (set CAVES2_GODOT)"
export CAVES2_GODOT="$GODOT"

RAVES="${RAVES_DIR:-$(dirname "$ROOT")/raves-of-qud}"
RPY="$PY"   # the raves tools are stdlib-only; any python runs them

# --- 1. the store ---------------------------------------------------------------------
STORE_NATIVE="$("$PY" -c 'import sys; sys.path.insert(0, "tools"); import qud_assets; print(qud_assets.store_dir())')"
STORE="$(unix_path "$STORE_NATIVE")"
[ -d "$STORE/tiles" ] || die "no asset store at $STORE — run tools/qud_locate.py, tools/extract_qud.py, tools/wall2vox.py"
[ -d "$STORE/walls" ] || die "no voxel walls in $STORE — run tools/wall2vox.py"
say "store   $STORE"

# --- 2. the baked chunks ----------------------------------------------------------------
# two lines, not two words: the support dir has a space in it ("Application Support")
locate_chunks() { { read -r CHUNKS; read -r GID; } <<<"$("$PY" -c 'import sys; sys.path.insert(0, "tools"); import qud_overland as o; r = o.chunks_root(); print(r); print(o.latest_world(r) or "-")')"; CHUNKS="$(unix_path "$CHUNKS")"; }
locate_chunks
count_chunks() { [ -d "$CHUNKS/$GID" ] && ls "$CHUNKS/$GID" 2>/dev/null | grep -c '^JoppaWorld\.' || echo 0; }
N="$(count_chunks)"
if [ "$GID" = "-" ] || [ "$N" -lt 81 ]; then
  say "chunks  $N baked in $CHUNKS/$GID — the demo wants the 5x5 region round Joppa (225)"
  [ "$CHECK" = 1 ] && die "bake it: raves-of-qud tools/capture/bake.py --center 11.22 --radius 2 (Qud in-game with the bridge)"
  [ -f "$RAVES/tools/capture/bake.py" ] || die "no raves-of-qud checkout at $RAVES (set RAVES_DIR); the bake lives there"
  say "baking through the Raves bridge (Caves of Qud must be running with a game loaded)..."
  "$RPY" "$RAVES/tools/capture/bake.py" --center 11.22 --radius 2 --ceiling 300 || die "the bake did not complete (see raves-of-qud/reports/bake-*.md)"
  locate_chunks
  N="$(count_chunks)"
fi
say "chunks  $N zones of game $GID"

# --- 3. the world export ----------------------------------------------------------------
WORLD="$STORE/godot/world/$GID/index.json"
NEWEST_CHUNK="$(ls -t "$CHUNKS/$GID"/JoppaWorld.*.json | head -1)"
if [ ! -f "$WORLD" ] || [ "$NEWEST_CHUNK" -nt "$WORLD" ]; then
  say "export  missing or older than the bake — running tools/export_godot_assets.py (about a minute)"
  [ "$CHECK" = 1 ] && die "export it: tools/export_godot_assets.py"
  "$PY" tools/export_godot_assets.py | grep -E '^(world|dressing|done)' || die "the export failed"
fi
[ -L "$ROOT/godot/qud" ] || [ -d "$ROOT/godot/qud" ] || die "godot/qud is not linked to the store (tools/export_godot_assets.py makes the link)"
WORLD_NATIVE="$STORE_NATIVE/godot/world/$GID/index.json"   # Python opens the native spelling
say "world   $("$PY" -c "import json; d = json.load(open(r'''$WORLD_NATIVE''')); s = d['stats']; print('%d zones, %d objects, %.1f%% resolved' % (len(d['zones']), s['objects'], 100.0 * s['resolved'] / max(1, s['objects'])))")"

[ "$CHECK" = 1 ] && { say "check   every piece is in place"; exit 0; }

# --- 4. the game ------------------------------------------------------------------------
ARGS=(--track="$TRACK" --overland"${ANCHOR:+=$ANCHOR}")
[ -n "$CLOCK" ] && ARGS+=(--clock="$CLOCK")
case "$MODE" in
  auto)
    mkdir -p reports/overland
    ARGS+=(--auto --frames=300 --screenshot="$ROOT/reports/overland/demo.png" --mute)
    say "race    $TRACK, the AI driving, screenshot to reports/overland/demo.png"
    ;;
  free)
    ARGS+=(--screen=free)
    say "drive   $TRACK, free drive from the start line (F toggles the race back on)"
    ;;
  *)
    say "race    $TRACK on the Qud surface — arrows drive, F is free drive, Esc quits"
    ;;
esac
"$GODOT" --path "$ROOT/godot" -- "${ARGS[@]}" 2>&1 | grep -E '^(overland|light|race|saved|graybox)' || true
