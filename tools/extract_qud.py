"""One-time extraction of Caves of Qud's assets into the per-user store.

Reads the user's own Steam install (qud_locate.py) and writes to the store
OUTSIDE the repo (qud_assets.py). Run it once after installing the game and
again after a game update; a run whose install fingerprint matches the store's
manifest is a no-op unless --force.

What comes out, and where it comes from:

  tiles/   Qud packs its ~27k tile images into Unity Texture2D atlases named
           Kobold_DynamicAtlas_<Folder>_1 and describes each tile with an ex2D
           `exTextureInfo` MonoBehaviour (name = the editor asset path with
           separators flattened, e.g. Assets_Content_Textures_Walls_wall_mud-00000000.png,
           plus the atlas rect). This build has no type tree for MonoBehaviours,
           so the record is parsed from its raw bytes against the class layout
           in Assembly-CSharp (exTextureInfo: two GUID strings, the texture
           PPtr, rotated, trim, 14 ints, diceData). Verified pixel-identical
           against tiles exported from inside the running game.
  sfx/     every AudioClip (FMOD Vorbis in resources.resource), decoded through
           UnityPy/pyfmodex and written as OGG Vorbis (or WAV with --sfx-format wav).
  data/    a verbatim copy of StreamingAssets/Base: blueprints, Colors.xml,
           Sounds.xml, map files, the works.

    python tools/extract_qud.py                    # everything, skip if current
    python tools/extract_qud.py --only tiles,data  # a subset
    python tools/extract_qud.py --force            # redo even if current
"""
import argparse
import collections
import io
import json
import os
import shutil
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qud_assets  # noqa: E402
import qud_locate  # noqa: E402

TOOL_VERSION = 1
PARTS = ("tiles", "sfx", "data")
TEXTURE_PREFIX = "Assets_Content_Textures_"


def log(msg):
    print(msg, flush=True)


# ---------------------------------------------------------------- tiles

def _read_string(raw, p):
    n = struct.unpack_from("<i", raw, p)[0]
    s = raw[p + 4:p + 4 + n].decode("utf-8", "replace")
    return s, (p + 4 + n + 3) & ~3


def parse_texture_info(raw):
    """Decode one exTextureInfo MonoBehaviour from its serialized bytes.

    Layout (Unity MonoBehaviour header, then the class fields in declaration
    order, strings and bools 4-aligned):
      m_GameObject PPtr(int32 fileID, int64 pathID) | m_Enabled u8 + pad |
      m_Script PPtr | m_Name string | rawTextureGUID string | rawAtlasGUID string |
      texture PPtr | rotated bool | trim bool | trimThreshold trim_x trim_y
      rawWidth rawHeight x y width height borderL borderR borderT borderB
      ShaderMode (14 x int32) | diceData int32 count + ints
    """
    script_file, script_path = struct.unpack_from("<iq", raw, 16)
    name, p = _read_string(raw, 28)
    _guid1, p = _read_string(raw, p)
    _guid2, p = _read_string(raw, p)
    tex_file, tex_path = struct.unpack_from("<iq", raw, p)
    p += 12
    rotated, trim = raw[p], raw[p + 4]
    p += 8
    ints = struct.unpack_from("<14i", raw, p)
    p += 56
    ndice = struct.unpack_from("<i", raw, p)[0]
    (_thr, trim_x, trim_y, raw_w, raw_h, x, y, w, h, _bl, _br, _bt, _bb, _shader) = ints
    return {
        "name": name, "script": (script_file, script_path),
        "tex": (tex_file, tex_path), "rotated": bool(rotated), "trim": bool(trim),
        "trim_x": trim_x, "trim_y": trim_y, "raw_w": raw_w, "raw_h": raw_h,
        "x": x, "y": y, "w": w, "h": h, "ndice": ndice,
    }


def find_texture_info_script(env):
    """The (fileID, pathID) of the exTextureInfo MonoScript, resolved by asking
    UnityPy for the class name of one MonoBehaviour per distinct script."""
    seen = {}
    for o in env.objects:
        if o.type.name != "MonoBehaviour":
            continue
        raw = o.get_raw_data()
        key = struct.unpack_from("<iq", raw, 16)
        if key in seen:
            continue
        try:
            seen[key] = o.read(check_read=False).m_Script.read().m_ClassName
        except Exception:
            seen[key] = None
        if seen[key] == "exTextureInfo":
            return key
    raise RuntimeError("no exTextureInfo MonoScript in resources.assets — "
                       "did the game change its tile packing?")


def qud_tile_path(name):
    """'Assets_Content_Textures_Walls_wall_mud-00000000.png' -> 'Walls/wall_mud-00000000.png'
    (the path blueprints use). Folder = first token; none of Qud's texture
    folders contain an underscore, file names freely do."""
    if not name.startswith(TEXTURE_PREFIX):
        return None
    rest = name[len(TEXTURE_PREFIX):]
    folder, _, fname = rest.partition("_")
    if not fname:
        return None
    return folder + "/" + fname


def extract_tiles(env, out_root):
    from PIL import Image
    script = find_texture_info_script(env)
    textures = {o.path_id: o for o in env.objects if o.type.name == "Texture2D"}
    atlases = {}
    recs = []
    for o in env.objects:
        if o.type.name != "MonoBehaviour":
            continue
        raw = o.get_raw_data()
        if struct.unpack_from("<iq", raw, 16) != script:
            continue
        r = parse_texture_info(raw)
        if r["ndice"]:
            raise RuntimeError("%s uses dicing; extractor does not handle that" % r["name"])
        recs.append(r)
    log("tiles: %d exTextureInfo records" % len(recs))

    index = {}
    counts = collections.Counter()
    skipped = []
    tiles_dir = os.path.join(out_root, "tiles")
    for i, r in enumerate(recs):
        qpath = qud_tile_path(r["name"])
        tex_file, tex_path = r["tex"]
        if qpath is None or tex_file != 0 or tex_path not in textures:
            skipped.append(r["name"])
            continue
        if tex_path not in atlases:
            t = textures[tex_path].read()
            atlases[tex_path] = (t.m_Name, t.image.convert("RGBA"))
        atlas_name, atlas = atlases[tex_path]
        H = atlas.height
        if r["rotated"]:
            box = (r["x"], H - r["y"] - r["w"], r["x"] + r["h"], H - r["y"])
            im = atlas.crop(box).rotate(90, expand=True)   # untested: no rotated tiles in 2.0.4
        else:
            box = (r["x"], H - r["y"] - r["h"], r["x"] + r["w"], H - r["y"])
            im = atlas.crop(box)
        if r["trim"] and (r["w"] != r["raw_w"] or r["h"] != r["raw_h"]):
            canvas = Image.new("RGBA", (r["raw_w"], r["raw_h"]), (0, 0, 0, 0))
            canvas.paste(im, (r["trim_x"], r["trim_y"]))
            im = canvas
        stem, _ext = os.path.splitext(qpath)
        rel = stem + ".png"
        if rel in index and index[rel]["source"] != qpath:
            # a .bmp and a .png with the same stem: keep both, the second under its own extension
            rel = qpath + ".png"
        dst = os.path.join(tiles_dir, *rel.split("/"))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        im.save(dst, "PNG", optimize=False)
        index[qpath] = {"file": rel, "w": im.width, "h": im.height, "atlas": atlas_name}
        counts[qpath.split("/")[0]] += 1
        if (i + 1) % 2000 == 0:
            log("  %d / %d" % (i + 1, len(recs)))
    with open(os.path.join(tiles_dir, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, indent=0, sort_keys=True)
    log("tiles: wrote %d files in %d folders; skipped %d (%s)" % (
        len(index), len(counts), len(skipped), ", ".join(skipped[:5])))
    return {"count": len(index), "folders": dict(counts), "skipped": skipped}


# ---------------------------------------------------------------- audio

OGG_CHUNK_FRAMES = 16384


def write_ogg(sf, wav_bytes, dst):
    """Encode a WAV byte string as OGG Vorbis in bounded writes.

    libsndfile's Vorbis encoder sizes a stack buffer by the frames handed to
    one sf_writef call, and a whole 3-minute music track in one call overran
    the main thread's stack (SIGSEGV, "Thread stack size exceeded" in
    _preextrapolate_helper). Chunked writes keep every call small.
    """
    data, sr = sf.read(io.BytesIO(wav_bytes), dtype="float32", always_2d=True)
    with sf.SoundFile(dst, "w", samplerate=sr, channels=data.shape[1],
                      format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(data), OGG_CHUNK_FRAMES):
            f.write(data[i:i + OGG_CHUNK_FRAMES])


def extract_sfx(env, out_root, fmt):
    sf = None
    if fmt == "ogg":
        try:
            import numpy as np  # noqa: F401
            import soundfile as sf
        except ImportError:
            log("sfx: soundfile/numpy not installed, falling back to WAV (2.7 GB!) — "
                "pip install soundfile numpy")
            fmt = "wav"
    sfx_dir = os.path.join(out_root, "sfx")
    os.makedirs(sfx_dir, exist_ok=True)
    clips = [o for o in env.objects if o.type.name == "AudioClip"]
    log("sfx: %d AudioClips -> %s" % (len(clips), fmt))
    index = {}
    names = collections.Counter()
    failed = []
    t0 = time.time()
    for i, o in enumerate(clips):
        d = o.read()
        name = d.m_Name
        names[name] += 1
        if names[name] > 1:
            name = "%s~%d" % (name, names[name])
        try:
            samples = d.samples          # {'<name>.wav': bytes} via pyfmodex
        except Exception as e:
            failed.append("%s (%s)" % (name, type(e).__name__))
            continue
        if not samples:
            failed.append("%s (no samples)" % name)
            continue
        wav = next(iter(samples.values()))
        rel = name + "." + fmt
        dst = os.path.join(sfx_dir, rel)
        if fmt == "ogg":
            write_ogg(sf, wav, dst)
        else:
            with open(dst, "wb") as f:
                f.write(wav)
        index[name] = {"file": rel, "seconds": round(float(d.m_Length), 3),
                       "hz": int(d.m_Frequency), "channels": int(d.m_Channels)}
        if (i + 1) % 250 == 0:
            log("  %d / %d  (%.0fs)" % (i + 1, len(clips), time.time() - t0))
    with open(os.path.join(sfx_dir, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, indent=0, sort_keys=True)
    log("sfx: wrote %d clips; %d failed %s" % (len(index), len(failed), failed[:5]))
    return {"count": len(index), "format": fmt, "failed": failed}


# ---------------------------------------------------------------- data

def extract_data(data_dir, out_root):
    src = os.path.join(data_dir, "StreamingAssets", "Base")
    dst = os.path.join(out_root, "data")
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    n = sum(len(fs) for _, _, fs in os.walk(dst))
    log("data: copied %d files from StreamingAssets/Base" % n)
    return {"count": n}


# ---------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--game-dir", help="Caves of Qud install root (else QUD_DIR / Steam)")
    ap.add_argument("--only", default=",".join(PARTS), help="comma list of: " + ",".join(PARTS))
    ap.add_argument("--force", action="store_true", help="re-extract even if the store is current")
    ap.add_argument("--sfx-format", choices=("ogg", "wav"), default="ogg")
    args = ap.parse_args(argv)

    parts = [p.strip() for p in args.only.split(",") if p.strip()]
    bad = [p for p in parts if p not in PARTS]
    if bad:
        ap.error("unknown part(s): %s" % ", ".join(bad))

    game_dir = qud_locate.find_game_dir(args.game_dir)
    report = qud_locate.validate(game_dir)
    log("Caves of Qud %s at %s" % (report.get("version") or "?", game_dir))
    if not report["ok"]:
        log("install is not usable:\n" + json.dumps(report["checks"], indent=2))
        return 1
    fp = qud_locate.install_fingerprint(report)

    out_root = qud_assets.store_dir()
    os.makedirs(out_root, exist_ok=True)
    manifest = qud_assets.read_manifest() or {}
    current = (manifest.get("fingerprint") == fp and manifest.get("tool_version") == TOOL_VERSION)
    done = manifest.get("parts", {}) if current else {}
    todo = [p for p in parts if args.force or p not in done]
    log("store: %s" % out_root)
    if not todo:
        log("up to date (fingerprint matches; parts present: %s). --force to redo." % ", ".join(done))
        return 0
    log("extracting: %s" % ", ".join(todo))

    env = None
    if "tiles" in todo or "sfx" in todo:
        import UnityPy
        t0 = time.time()
        env = UnityPy.load(os.path.join(report["data_dir"], "resources.assets"))
        log("loaded resources.assets (%.1fs)" % (time.time() - t0))

    results = dict(done) if current else {}

    def save():
        # after EVERY part, so a crash in a later one keeps the finished work
        qud_assets.write_manifest({
            "tool_version": TOOL_VERSION,
            "fingerprint": fp,
            "game_dir": game_dir,
            "extracted_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "parts": results,
        })

    if "data" in todo:
        results["data"] = extract_data(report["data_dir"], out_root)
        save()
    if "tiles" in todo:
        results["tiles"] = extract_tiles(env, out_root)
        save()
    if "sfx" in todo:
        results["sfx"] = extract_sfx(env, out_root, args.sfx_format)
        save()
    log("manifest: %s" % qud_assets.manifest_path())
    return 0


if __name__ == "__main__":
    sys.exit(main())
