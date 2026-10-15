#!/usr/bin/env python3
"""Packs mod source folders into .critmod archives (plain zip, deterministic).

Usage:
  python tools/mods/pack_mod.py <mod folder> [<mod folder> ...] --out <dir>
  python tools/mods/pack_mod.py --examples          # mods/examples/* -> game/mods_examples/

The archive name is <id>-<version>.critmod taken from the folder's manifest.json. Entries are
sorted, timestamps fixed and permissions normalised, so the same sources always produce the
same bytes (and the same package hash in multiplayer compatibility checks). Only file types the
game accepts are packed; anything else is reported and the folder is rejected, mirroring the
in-game validator (game/src/mods/mod_manager.gd).
"""
import json
import os
import sys
import zipfile

ALLOWED = {"json", "txt", "md", "png", "jpg", "jpeg", "webp", "ogg", "wav", "glb"}
FIXED_TIME = (2026, 1, 1, 0, 0, 0)
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def pack(folder, out_dir):
    with open(os.path.join(folder, "manifest.json"), encoding="utf-8") as f:
        man = json.load(f)
    files = []
    for base, dirs, names in os.walk(folder):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for n in sorted(names):
            if n.startswith("."):
                continue
            full = os.path.join(base, n)
            rel = os.path.relpath(full, folder).replace("\\", "/")
            ext = n.rsplit(".", 1)[-1].lower() if "." in n else ""
            if ext not in ALLOWED:
                raise SystemExit("%s: '%s' has a file type the game rejects (.%s)" % (folder, rel, ext))
            if ext == "json":
                with open(full, encoding="utf-8") as jf:
                    json.load(jf)  # fail early on syntax errors
            files.append((rel, full))
    files.sort()
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "%s-%s.critmod" % (man["id"], man["version"]))
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for rel, full in files:
            info = zipfile.ZipInfo(rel, date_time=FIXED_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            with open(full, "rb") as src:
                z.writestr(info, src.read())
    print("packed %s (%d files)" % (os.path.relpath(out, ROOT), len(files)))
    return out


def main(argv):
    if "--examples" in argv:
        src = os.path.join(ROOT, "mods", "examples")
        out = os.path.join(ROOT, "game", "mods_examples")
        for old in os.listdir(out) if os.path.isdir(out) else []:
            if old.endswith(".critmod"):
                os.remove(os.path.join(out, old))
        for d in sorted(os.listdir(src)):
            if os.path.isfile(os.path.join(src, d, "manifest.json")):
                pack(os.path.join(src, d), out)
        return 0
    if "--out" not in argv:
        print(__doc__)
        return 2
    i = argv.index("--out")
    out_dir = argv[i + 1]
    for folder in argv[:i] + argv[i + 2:]:
        pack(folder, out_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
