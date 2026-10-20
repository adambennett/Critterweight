"""Technical audit of recorded commentary/dialogue (v0.9.17, docs/audio/COMMENTARY.md §6).

Measures every installed speech clip and every composed line (sentence clip + name/number tokens)
without listening: duration, level (RMS/peak dBFS), clipping, leading/trailing/internal silence,
a truncated-ending check, speech rate (characters per second of voiced audio), and pitch statistics
from a numpy autocorrelation tracker (median F0, range in semitones = a flat-delivery proxy). For
composed lines it reports the level and pitch jump at each join (an awkward-join proxy). Flags are
heuristics for retake review, not a listening verdict.

    python tools/audio/breeze/audit_speech.py --out B:/Critterweight-work/v0.9.17/commentary/speech_audit.json
"""
import argparse
import json
import math
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
CATALOGS = [ROOT / "game/assets/audio/speech/catalog.json", ROOT / "game/assets/audio/speech/announcer_expansion/catalog.json"]
EXTRA_CATALOGS = sorted((ROOT / "game/assets/audio/speech").glob("*/catalog.json"))


def res_to_path(res):
    return ROOT / "game" / res.replace("res://", "")


def read_wav(path):
    with wave.open(str(path), "rb") as w:
        rate = w.getframerate()
        n = w.getnframes()
        width = w.getsampwidth()
        ch = w.getnchannels()
        raw = w.readframes(n)
    if width != 2:
        raise ValueError("expected 16-bit PCM: %s" % path)
    x = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    return x, rate


def db(v):
    return 20.0 * math.log10(max(float(v), 1e-9))


def frames(x, rate, ms=20):
    hop = max(1, int(rate * ms / 1000))
    n = len(x) // hop
    if n == 0:
        return np.zeros((0, hop), dtype=np.float32), hop
    return x[: n * hop].reshape(n, hop), hop


def pitch_track(x, rate):
    """Per-40 ms-frame F0 (Hz) by normalized autocorrelation; 0 for unvoiced frames."""
    win = int(rate * 0.04)
    hop = int(rate * 0.02)
    lo, hi = int(rate / 400.0), int(rate / 70.0)
    out = []
    for start in range(0, len(x) - win, hop):
        seg = x[start:start + win]
        seg = seg - seg.mean()
        energy = float(np.dot(seg, seg))
        if energy < 1e-4:
            out.append(0.0)
            continue
        ac = np.correlate(seg, seg, mode="full")[win - 1:]
        ac = ac / (ac[0] + 1e-9)
        if hi >= len(ac):
            out.append(0.0)
            continue
        lag = lo + int(np.argmax(ac[lo:hi]))
        out.append(rate / lag if ac[lag] > 0.45 else 0.0)
    return np.array(out, dtype=np.float32)


def measure(path):
    x, rate = read_wav(path)
    dur = len(x) / rate
    peak = float(np.max(np.abs(x))) if len(x) else 0.0
    fr, hop = frames(x, rate)
    rms_f = np.sqrt((fr ** 2).mean(axis=1)) if len(fr) else np.zeros(0)
    voiced = rms_f > 10 ** (-45 / 20.0)
    lead = 0.0
    trail = 0.0
    if voiced.any():
        idx = np.nonzero(voiced)[0]
        lead = idx[0] * hop / rate
        trail = (len(voiced) - 1 - idx[-1]) * hop / rate
    # the longest internal pause between voiced frames
    longest = 0.0
    run = 0
    started = False
    for v in voiced:
        if v:
            if started:
                longest = max(longest, run * hop / rate)
            started = True
            run = 0
        else:
            run += 1
    active = float(voiced.sum()) * hop / rate
    rms = float(np.sqrt((x ** 2).mean())) if len(x) else 0.0
    rms_active = float(np.sqrt((fr[voiced] ** 2).mean())) if voiced.any() else 0.0
    clipped = int(np.sum(np.abs(x) >= 0.999))
    tail = x[-int(rate * 0.03):] if len(x) > rate * 0.03 else x
    tail_db = db(np.sqrt((tail ** 2).mean())) if len(tail) else -120.0
    f0 = pitch_track(x, rate)
    v0 = f0[f0 > 0]
    if len(v0) >= 5:
        med = float(np.median(v0))
        p10, p90 = np.percentile(v0, [10, 90])
        semis = 12.0 * math.log2(max(p90, 1.0) / max(p10, 1.0))
    else:
        med, semis = 0.0, 0.0
    return {"seconds": round(dur, 3), "active_seconds": round(active, 3), "rate": rate, "peak_dbfs": round(db(peak), 2),
            "rms_dbfs": round(db(rms), 2), "rms_active_dbfs": round(db(rms_active), 2), "clipped_samples": clipped,
            "lead_silence": round(lead, 3), "trail_silence": round(trail, 3), "longest_pause": round(longest, 3),
            "tail_dbfs": round(tail_db, 1), "f0_median": round(med, 1), "f0_range_semitones": round(semis, 2),
            "_head_f0": float(np.median(f0[:15][f0[:15] > 0])) if (f0[:15] > 0).sum() >= 3 else 0.0,
            "_tail_f0": float(np.median(f0[-15:][f0[-15:] > 0])) if (f0[-15:] > 0).sum() >= 3 else 0.0,
            "_head_db": db(np.sqrt((x[: int(rate * 0.25)] ** 2).mean())) if len(x) else -120.0,
            "_tail_db": db(np.sqrt((x[-int(rate * 0.25):] ** 2).mean())) if len(x) else -120.0}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()
    clips, lines, tokens = {}, [], {}
    for cat_path in CATALOGS + [p for p in EXTRA_CATALOGS if p not in CATALOGS]:
        if not cat_path.exists():
            continue
        cat = json.loads(cat_path.read_text(encoding="utf-8"))
        for cid, meta in cat.get("clips", {}).items():
            clips[cid] = {"path": meta["path"], "voice": meta.get("voice", ""), "catalog": cat_path.parent.name}
        for line in cat.get("lines", []):
            lines.append(line)
        for voice, vocab in cat.get("tokens", {}).items():
            tokens.setdefault(voice, {}).update(vocab)
    texts = {}
    for line in lines:
        if len(line.get("parts", [])) == 1 and "clip" in line["parts"][0]:
            texts[line["parts"][0]["clip"]] = line["template"]
    measured = {}
    for cid, meta in sorted(clips.items()):
        p = res_to_path(meta["path"])
        if not p.exists():
            measured[cid] = {"missing": True}
            continue
        m = measure(p)
        m["voice"] = meta["voice"]
        text = texts.get(cid, "")
        if text:
            m["text"] = text
            m["chars_per_second"] = round(len(text) / max(m["active_seconds"], 0.2), 1)
        measured[cid] = m
    flags = []
    for cid, m in measured.items():
        if m.get("missing"):
            flags.append({"clip": cid, "flag": "missing_file"})
            continue
        if m["clipped_samples"] > 0:
            flags.append({"clip": cid, "flag": "clipping", "value": m["clipped_samples"]})
        if m["peak_dbfs"] > -1.0:
            flags.append({"clip": cid, "flag": "peak_over_minus1", "value": m["peak_dbfs"]})
        if m["rms_active_dbfs"] < -30.0:
            flags.append({"clip": cid, "flag": "quiet", "value": m["rms_active_dbfs"]})
        if m["longest_pause"] > 0.9:
            flags.append({"clip": cid, "flag": "long_internal_pause", "value": m["longest_pause"]})
        if m["tail_dbfs"] > -32.0 and m["trail_silence"] < 0.02:
            flags.append({"clip": cid, "flag": "possibly_truncated_end", "value": m["tail_dbfs"]})
        if m.get("chars_per_second", 0) > 24.0:
            flags.append({"clip": cid, "flag": "rushed", "value": m["chars_per_second"]})
        if m.get("text") and len(m["text"]) > 25 and 0.0 < m["f0_range_semitones"] < 3.0:
            flags.append({"clip": cid, "flag": "flat_pitch", "value": m["f0_range_semitones"]})
    # composed lines: the jump at every join
    joins = []
    for line in lines:
        parts = line.get("parts", [])
        if len(parts) < 2:
            continue
        seq = []
        for part in parts:
            if "clip" in part:
                seq.append(("clip", part["clip"]))
            else:
                vocab = tokens.get(line.get("voice", ""), {})
                tok = part["token"]
                sample = vocab.get("stoke") if tok in ("p", "o", "player") else (vocab.get("three") if tok in ("n",) else None)
                seq.append(("token:" + tok, sample))
        for a, b in zip(seq, seq[1:]):
            ma, mb = measured.get(a[1] or "", {}), measured.get(b[1] or "", {})
            if not ma or not mb or ma.get("missing") or mb.get("missing"):
                continue
            jump_db = mb["_head_db"] - ma["_tail_db"]
            fa, fb = ma["_tail_f0"], mb["_head_f0"]
            jump_st = 12.0 * math.log2(fb / fa) if fa > 0 and fb > 0 else 0.0
            j = {"line": line["id"], "template": line["template"], "from": a[0], "to": b[0], "level_jump_db": round(jump_db, 1),
                 "pitch_jump_semitones": round(jump_st, 1)}
            joins.append(j)
            if abs(jump_db) > 9.0 or abs(jump_st) > 6.0:
                flags.append({"line": line["id"], "flag": "awkward_join", "value": j})
    for m in measured.values():
        for k in [k for k in m if k.startswith("_")]:
            del m[k]
    summary = {}
    for f in flags:
        summary[f["flag"]] = summary.get(f["flag"], 0) + 1
    report = {"clips": len(measured), "lines": len(lines), "joins": len(joins), "flag_counts": summary, "flags": flags,
              "joins_detail": joins, "measurements": measured}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=1, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"clips": len(measured), "lines": len(lines), "joins": len(joins), "flag_counts": summary}))


if __name__ == "__main__":
    main()
