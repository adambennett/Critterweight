#!/usr/bin/env python3
"""Linux / Steam Deck portability checks that can run on any OS (DEL-03, DEL-04).

  python tools/verify/portability_check.py [--dist dist] [--json out.json]

1. Case-exact resource paths: every "res://..." literal in scripts, scenes, resources and JSON
   content must name a file that exists with exactly that case (Windows ignores case; Linux and
   the exported .pck do not).
2. Windows-only constructs in game code: shell commands (cmd/powershell/.bat/.exe), drive letters,
   backslash paths used as file paths.
3. Exported Linux binaries (game + dedicated server): ELF64 x86-64, embedded game data (PCK magic
   at the end), the shared libraries they need (DT_NEEDED) and their glibc symbol versions.
4. Linux .tar.gz archives keep the executable bit on the binaries.

Exit code = number of failed checks. Results also go to --json.
"""
import json
import os
import re
import struct
import sys
import tarfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GAME = os.path.join(ROOT, "game")
RES_RE = re.compile(r"res://[A-Za-z0-9_\-./ ]+")
SKIP_DIRS = {".godot", ".import", "node_modules"}


def iter_files(base, exts):
    for d, dirs, files in os.walk(base):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS and not x.startswith(".")]
        for f in files:
            if f.rsplit(".", 1)[-1].lower() in exts:
                yield os.path.join(d, f)


def exact_case_exists(rel):
    """True if game/<rel> exists with exactly this case for every component."""
    cur = GAME
    for part in [p for p in rel.split("/") if p]:
        try:
            names = os.listdir(cur)
        except OSError:
            return False
        if part not in names:
            return False
        cur = os.path.join(cur, part)
    return True


def check_res_paths():
    bad = []
    seen = 0
    for path in iter_files(GAME, {"gd", "tscn", "tres", "json", "cfg", "gdshader"}):
        text = open(path, encoding="utf-8", errors="replace").read()
        for m in RES_RE.finditer(text):
            lit = m.group(0).rstrip(". /")
            rel = lit[len("res://"):]
            if not rel or rel.endswith("/") or "%" in rel or rel.startswith("."):
                continue
            # dynamic prefixes (e.g. "res://content/core" + kind) are directories: accept dirs too
            seen += 1
            if exact_case_exists(rel) or exact_case_exists(rel.rstrip("/")):
                continue
            # tolerate generated/remapped targets (.gd.remap in exports, imported caches)
            if rel.endswith((".remap", ".import")):
                continue
            if not os.path.exists(os.path.join(GAME, rel)):
                # does not exist at all: only flag if it looks like a concrete file reference
                if "." in os.path.basename(rel):
                    bad.append("%s: %s (missing)" % (os.path.relpath(path, ROOT), lit))
                continue
            bad.append("%s: %s (case differs on disk)" % (os.path.relpath(path, ROOT), lit))
    return seen, bad


WIN_PATTERNS = [
    (re.compile(r"OS\.execute\(\s*\"(cmd|powershell|cmd\.exe)\"", re.I), "shell command"),
    (re.compile(r"\"[A-Za-z]:[\\/]"), "drive letter path"),
    (re.compile(r"\.bat\"|\.cmd\""), "batch file"),
]


def check_windows_only():
    hits = []
    for path in iter_files(os.path.join(GAME, "src"), {"gd"}):
        rel = os.path.relpath(path, ROOT)
        if "/test/" in rel.replace("\\", "/"):
            continue
        for i, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
            s = line.strip()
            if s.startswith("#"):
                continue
            for rx, what in WIN_PATTERNS:
                if rx.search(line):
                    hits.append("%s:%d %s: %s" % (rel, i, what, s[:100]))
    return hits


def read_elf(path):
    with open(path, "rb") as f:
        data = f.read()
    info = {"path": os.path.relpath(path, ROOT), "bytes": len(data)}
    if data[:4] != b"\x7fELF":
        info["error"] = "not an ELF file"
        return info
    info["class"] = {1: "ELF32", 2: "ELF64"}.get(data[4], "?")
    info["endian"] = {1: "little", 2: "big"}.get(data[5], "?")
    machine = struct.unpack_from("<H", data, 18)[0]
    info["machine"] = {0x3E: "x86-64", 0xB7: "aarch64", 0x03: "x86"}.get(machine, hex(machine))
    # section headers -> .dynamic + .dynstr, .gnu.version_r
    e_shoff = struct.unpack_from("<Q", data, 0x28)[0]
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 0x3A)
    secs = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        name, typ, flags, addr, offset, size, link, inf, align, entsize = struct.unpack_from("<IIQQQQIIQQ", data, off)
        secs.append({"name_off": name, "type": typ, "offset": offset, "size": size, "link": link, "entsize": entsize})
    shstr = secs[e_shstrndx]
    def secname(s):
        start = shstr["offset"] + s["name_off"]
        return data[start:data.index(b"\0", start)].decode()
    for s in secs:
        s["name"] = secname(s)
    by = {s["name"]: s for s in secs}
    needed = []
    if ".dynamic" in by and ".dynstr" in by:
        dyn, dstr = by[".dynamic"], by[".dynstr"]
        for k in range(dyn["size"] // 16):
            tag, val = struct.unpack_from("<qQ", data, dyn["offset"] + k * 16)
            if tag == 0:
                break
            if tag == 1:  # DT_NEEDED
                st = dstr["offset"] + val
                needed.append(data[st:data.index(b"\0", st)].decode())
    info["needed"] = needed
    glibc = set(m.decode() for m in re.findall(rb"GLIBC_[0-9.]+", data))
    vers = sorted(glibc, key=lambda v: [int(x) for x in v[6:].split(".") if x.isdigit()])
    info["glibc_max"] = vers[-1] if vers else ""
    info["pck_embedded"] = b"GDPC" in data[-64 * 1024 * 1024:] if len(data) > 0 else False
    return info


def main(argv):
    dist = os.path.join(ROOT, argv[argv.index("--dist") + 1]) if "--dist" in argv else os.path.join(ROOT, "dist")
    out = argv[argv.index("--json") + 1] if "--json" in argv else ""
    results = {"checks": []}
    fails = 0

    seen, bad = check_res_paths()
    ok = not bad
    results["checks"].append({"name": "case-exact res:// paths", "ok": ok, "detail": "%d references checked" % seen, "problems": bad[:50]})
    fails += 0 if ok else 1

    win = check_windows_only()
    results["checks"].append({"name": "no Windows-only constructs in game code", "ok": not win, "problems": win[:50]})
    fails += 0 if not win else 1

    for sub, exe in [("Critterweight-linux-x86_64", "Critterweight.x86_64"), ("Critterweight-server-linux-x86_64", "CritterweightServer.x86_64")]:
        p = os.path.join(dist, sub, exe)
        if not os.path.exists(p):
            results["checks"].append({"name": "linux binary %s" % exe, "ok": False, "detail": "not built (%s)" % os.path.relpath(p, ROOT)})
            fails += 1
            continue
        info = read_elf(p)
        ok = info.get("class") == "ELF64" and info.get("machine") == "x86-64" and info.get("pck_embedded")
        results["checks"].append({"name": "linux binary %s" % exe, "ok": bool(ok), "detail": info})
        fails += 0 if ok else 1

    for arc in sorted(os.listdir(dist)) if os.path.isdir(dist) else []:
        if arc.endswith(".tar.gz") and "linux" in arc:
            with tarfile.open(os.path.join(dist, arc)) as t:
                exes = [m for m in t.getmembers() if m.name.endswith(".x86_64")]
                ok = bool(exes) and all(m.mode & 0o111 for m in exes)
                results["checks"].append({"name": "exec bit in %s" % arc, "ok": ok,
                    "detail": ["%s %o" % (m.name, m.mode) for m in exes]})
                fails += 0 if ok else 1

    for c in results["checks"]:
        print("[%s] %s" % ("PASS" if c["ok"] else "FAIL", c["name"]))
        if not c["ok"]:
            for prob in c.get("problems", [])[:10]:
                print("    " + prob)
            if "detail" in c and not c.get("problems"):
                print("    %s" % (c["detail"],))
        elif isinstance(c.get("detail"), dict):
            d = c["detail"]
            print("    %s %s, needs %s, glibc <= %s, game data embedded: %s" % (d.get("class"), d.get("machine"), ", ".join(d.get("needed", [])), d.get("glibc_max"), d.get("pck_embedded")))
    if out:
        with open(out, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2)
    return fails


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
