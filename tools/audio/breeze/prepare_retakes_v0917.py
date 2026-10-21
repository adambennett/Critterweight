"""v0.9.17 commentary retakes (docs/audio/COMMENTARY.md §7, docs/audio/breeze/README.md).

Builds docs/audio/breeze/v0.9.17/plan-retakes.json from the v0.9.17 generation plan: each clip
the technical speech audit flagged (tools/audio/breeze/audit_speech.py) and that was judged worth a
new take gets a NEW clip id `<id>_r<round>` with the same text and voice and a direction note for
the problem. Completed takes are never regenerated in place (generate.py refuses changed takes), so
the original stays journaled and its raw master stays on B:. After generation, `--install` points
the catalog lines at each line's chosen take, removes the replaced processed WAVs from the game
assets and records the choices in retakes-installed.json.

    python -B tools/audio/breeze/prepare_retakes_v0917.py               # write the retake plan
    python -B tools/audio/breeze/generate.py --plan docs/audio/breeze/v0.9.17/plan-retakes.json ...
    python -B tools/audio/breeze/prepare_retakes_v0917.py --install     # switch the catalog
"""
import argparse, audioop, hashlib, json, wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DOCS = ROOT / 'docs/audio/breeze/v0.9.17'
SPEECH = ROOT / 'game/assets/audio/speech/v0917'

NOTES = {
    'ending': ' Deliver the whole line and land the final word completely, then stop cleanly: no extra words, breath or sound after the last word.',
    'flat': ' This is a big live moment: lift the energy and let the pitch rise and fall with real excitement; never monotone.',
    'pause': ' Keep it flowing as one continuous live call: no long pauses in the middle of the line.',
    'pace': ' Slightly slower and very clearly articulated so every word is easy to understand, still lively and in the moment.',
}

# round 1, clip id -> reason (from the speech audit of 2026-10-20: tail level / pitch range / pauses / chars per second)
RETAKES = {
    'cmt17_0098': 'ending', 'cmt17_0190': 'ending', 'cmt17_rt_ann_kd_03': 'ending', 'cmt17_v_comeback_03_slurry': 'ending',
    'cmt17_0126': 'flat', 'cmt17_0229': 'flat', 'cmt17_v_first_03_varga': 'flat', 'cmt17_v_parry_05_jitters_rookie': 'flat',
    'cmt17_0090': 'pause', 'cmt17_0336': 'pause', 'cmt17_0279': 'pause',
    'cmt17_0235': 'pace', 'cmt17_0204': 'pace', 'cmt17_0251': 'pace', 'cmt17_x007': 'pace', 'cmt17_0056': 'pace',
    'cmt17_v_low_03_slurry': 'pace', 'cmt17_0200': 'pace', 'cmt17_0211': 'pace',
}
# round 2: the first retake fixed the delivery but its ending was unclear
RETAKES_R2 = {'cmt17_0126': ['flat', 'ending']}
# takes measured and judged unusable (kept journaled with their raw masters, never installed)
REJECT = {'cmt17_0126_r1'}
# takes installed after trimming a stray sound that follows the line after >= 0.3 s of digital silence
TRIM_TAIL = {'cmt17_0229_r1'}


def _retake(plan: dict, cid: str, reasons: list) -> dict:
    src = dict(plan['clips'][cid])
    src['instructions'] = src['instructions'] + ''.join(NOTES[r] for r in reasons)
    src['retake_of'] = cid
    src['retake_reason'] = '+'.join(reasons)
    src['estimated_credits'] = len(src['text']) / 10
    src.pop('id', None)
    return src


def build_plan():
    plan = json.loads((DOCS / 'plan.json').read_text(encoding='utf-8'))
    out = {k: plan[k] for k in ['version', 'release', 'model_id', 'voices', 'cast'] if k in plan}
    out['purpose'] = 'v0.9.17 retakes of clips flagged by the technical speech audit (see RETAKES in prepare_retakes_v0917.py)'
    out['authorized_credits'] = plan.get('authorized_credits')
    clips = {}
    for cid, reason in RETAKES.items():
        clips[cid + '_r1'] = _retake(plan, cid, [reason])
    for cid, reasons in RETAKES_R2.items():
        clips[cid + '_r2'] = _retake(plan, cid, reasons)
    out['clips'] = clips
    out['estimated_characters'] = sum(len(c['text']) for c in clips.values())
    (DOCS / 'plan-retakes.json').write_text(json.dumps(out, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('retakes: %d clips, %d characters, ~%.1f credits' % (len(clips), out['estimated_characters'], out['estimated_characters'] / 10))


def _trim_tail(path: Path):
    """Cuts a stray sound that starts after >= 0.3 s of digital silence at the end of a take."""
    with wave.open(str(path), 'rb') as w:
        rate, pcm = w.getframerate(), w.readframes(w.getnframes())
    win = rate // 100 * 2
    loud = [i for i in range(0, len(pcm), win) if audioop.rms(pcm[i:i + win], 2) > 100]
    gap_start = None
    for a, b in zip(loud, loud[1:]):
        if b - a >= int(rate * 0.3) * 2:
            gap_start = a + win
    if gap_start is None:
        return None
    pcm = pcm[:min(len(pcm), gap_start + int(rate * 0.045) * 2)]
    fade = min(int(rate * 0.006), len(pcm) // 4)
    head, tail = pcm[:-fade * 2], pcm[-fade * 2:]
    tail = b''.join(audioop.mul(tail[i * 2:i * 2 + 2], 2, 1 - i / max(1, fade)) for i in range(fade))
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(head + tail)
    return {'seconds': len(head + tail) / 2 / rate, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def install():
    retake = json.loads((DOCS / 'retake-catalog.json').read_text(encoding='utf-8'))
    plan = json.loads((DOCS / 'plan-retakes.json').read_text(encoding='utf-8'))
    cat_path = SPEECH / 'catalog.json'
    cat = json.loads(cat_path.read_text(encoding='utf-8'))
    # each original line ends up with its latest usable retake
    chosen = {}
    for new_id in sorted(retake['clips']):
        if new_id not in REJECT:
            chosen[plan['clips'][new_id]['retake_of']] = new_id
    switched = 0
    processing = {}
    for old_id, new_id in sorted(chosen.items()):
        entry = dict(retake['clips'][new_id])
        if new_id in TRIM_TAIL:
            r = _trim_tail(SPEECH / (new_id + '.wav'))
            if r:
                entry.update(r)
                processing[new_id] = 'stray sound after 0.3 s of digital silence trimmed at the end'
        for line in cat['lines']:
            for part in line.get('parts', []):
                if part.get('clip') == old_id:
                    part['clip'] = new_id
                    switched += 1
        cat['clips'][new_id] = entry
        cat['clips'].pop(old_id, None)
        for f in [SPEECH / (old_id + '.wav'), SPEECH / (old_id + '.wav.import')]:
            if f.exists():
                f.unlink()
    for rid in REJECT:
        for f in [SPEECH / (rid + '.wav'), SPEECH / (rid + '.wav.import')]:
            if f.exists():
                f.unlink()
    cat_path.write_text(json.dumps(cat, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (DOCS / 'retakes-installed.json').write_text(json.dumps({'chosen': chosen, 'rejected': sorted(REJECT), 'processing': processing},
                                                            indent=2) + '\n', encoding='utf-8')
    print('installed %d retakes (%d line parts switched); rejected %s' % (len(chosen), switched, sorted(REJECT)))


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--install', action='store_true')
    a = ap.parse_args()
    install() if a.install else build_plan()
