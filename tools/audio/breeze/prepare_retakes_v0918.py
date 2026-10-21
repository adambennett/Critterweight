"""v0.9.18 Movesets commentary retakes (docs/audio/COMMENTARY.md, docs/audio/breeze/README.md).

Builds docs/audio/breeze/v0.9.18/plan-retakes.json from the v0.9.18 generation plan: each clip
the technical speech audit flagged (tools/audio/breeze/audit_speech.py) and that was judged worth a
new take gets a NEW clip id `<id>_r<round>` with the same text and voice and a direction note for
the problem. Completed takes are never regenerated in place (generate.py refuses changed takes), so
the original stays journaled and its raw master stays on B:. After generation, `--install` points
the catalog lines at each line's chosen take, removes the replaced processed WAVs from the game
assets and records the choices in retakes-installed.json.

    python -B tools/audio/breeze/prepare_retakes_v0918.py               # write the retake plan
    python -B tools/audio/breeze/generate.py --plan docs/audio/breeze/v0.9.18/plan-retakes.json ...
    python -B tools/audio/breeze/prepare_retakes_v0918.py --install     # switch the catalog
    --set tutorial: the same for Granny's Movesets lessons (plan-tutorial.json, tutorial_catalog.json)
"""
import argparse, audioop, hashlib, json, wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DOCS = ROOT / 'docs/audio/breeze/v0.9.18'
SPEECH = ROOT / 'game/assets/audio/speech/v0918'

NOTES = {
    'ending': ' Deliver the whole line and land the final word completely, then stop cleanly: no extra words, breath or sound after the last word.',
    'flat': ' This is a big live moment: lift the energy and let the pitch rise and fall with real excitement; never monotone.',
    'pause': ' Keep it flowing as one continuous live call: no long pauses in the middle of the line.',
    'pace': ' Slightly slower and very clearly articulated so every word is easy to understand, still lively and in the moment.',
}

# round 1, clip id -> reason (from the speech audit of 2026-10-21: tail level / pitch range / chars per second)
RETAKES = {
    'cmt18_0111': 'ending', 'cmt18_0119': 'ending',
    'cmt18_0073': 'flat', 'cmt18_0123': 'flat',
    'cmt18_0001': 'pace', 'cmt18_0026': 'pace', 'cmt18_0064': 'pace', 'cmt18_0080': 'pace', 'cmt18_0020': 'pace',
    'cmt18_0002': 'pace',
}
# round 2: the first retake still ended abruptly (0119) or came out with a long pause and a cut-off
# ending (0002)
RETAKES_R2 = {'cmt18_0119': ['ending'], 'cmt18_0002': ['pace', 'pause', 'ending']}

# Granny's Movesets lessons (--set tutorial), from the measurements of 2026-10-21: cut-off endings at
# the end of a line and the briskest deliveries (> 26 characters per second)
TUTORIAL_RETAKES = {
    'tut18_tut_m_dodge_intro_b': 'ending', 'tut18_tut_m_dodge_hint_c': 'ending', 'tut18_tut_m_special_success': 'ending',
    'tut18_tok_your_special': 'ending',
    'tut18_tut_m_charge_intro_a': 'pace', 'tut18_tut_m_charge_hint_b': 'pace', 'tut18_tut_m_sustain_intro_a': 'pace',
    'tut18_tut_m_special_use_only_success': 'pace', 'tut18_tut_m_dodge_success': 'pace', 'tut18_tut_m_dodge_no_dash_intro_a': 'pace',
    'tut18_tut_m_dodge_no_dash_success': 'pace', 'tut18_tut_m_grapple_hint_b': 'pace', 'tut18_tut_m_ultimate_success': 'pace',
}
# round 2: the first retake of the no-dash dodge intro came out with a cut-off ending
TUTORIAL_RETAKES_R2 = {'tut18_tut_m_dodge_no_dash_intro_a': ['pace', 'ending']}
TUTORIAL_REJECT = {'tut18_tut_m_dodge_no_dash_intro_a_r1'}
# takes measured and judged unusable (kept journaled with their raw masters, never installed)
REJECT = {'cmt18_0119_r1', 'cmt18_0002_r1'}
# takes installed after trimming a stray sound that follows the line after >= 0.3 s of digital silence
TRIM_TAIL = set()


def _retake(plan: dict, cid: str, reasons: list) -> dict:
    src = dict(plan['clips'][cid])
    src['instructions'] = src['instructions'] + ''.join(NOTES[r] for r in reasons)
    src['retake_of'] = cid
    src['retake_reason'] = '+'.join(reasons)
    src['estimated_credits'] = len(src['text']) / 10
    src.pop('id', None)
    return src


SET = {'plan': 'plan.json', 'retakes': 'plan-retakes.json', 'catalog': 'retake-catalog.json', 'installed': 'retakes-installed.json',
       'speech': 'catalog.json'}


def use_tutorial_set():
    global RETAKES, RETAKES_R2, REJECT
    SET.update({'plan': 'plan-tutorial.json', 'retakes': 'plan-tutorial-retakes.json', 'catalog': 'retake-tutorial-catalog.json',
                'installed': 'retakes-tutorial-installed.json', 'speech': 'tutorial_catalog.json'})
    RETAKES, RETAKES_R2, REJECT = TUTORIAL_RETAKES, TUTORIAL_RETAKES_R2, TUTORIAL_REJECT


def build_plan():
    plan = json.loads((DOCS / SET['plan']).read_text(encoding='utf-8'))
    out = {k: plan[k] for k in ['version', 'release', 'model_id', 'voices', 'cast'] if k in plan}
    out['purpose'] = 'v0.9.18 retakes of clips flagged by the technical speech audit (see RETAKES in prepare_retakes_v0918.py)'
    out['authorized_credits'] = plan.get('authorized_credits')
    clips = {}
    for cid, reason in RETAKES.items():
        clips[cid + '_r1'] = _retake(plan, cid, [reason])
    for cid, reasons in RETAKES_R2.items():
        clips[cid + '_r2'] = _retake(plan, cid, reasons)
    out['clips'] = clips
    out['estimated_characters'] = sum(len(c['text']) for c in clips.values())
    (DOCS / SET['retakes']).write_text(json.dumps(out, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
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
    retake = json.loads((DOCS / SET['catalog']).read_text(encoding='utf-8'))
    plan = json.loads((DOCS / SET['retakes']).read_text(encoding='utf-8'))
    cat_path = SPEECH / SET['speech']
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
        # a recorded word (a vocabulary token) points at its retake too
        for vocab in (cat.get('tokens') or {}).values():
            for word, cid in list(vocab.items()):
                if cid == old_id:
                    vocab[word] = new_id
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
    (DOCS / SET['installed']).write_text(json.dumps({'chosen': chosen, 'rejected': sorted(REJECT), 'processing': processing},
                                                            indent=2) + '\n', encoding='utf-8')
    print('installed %d retakes (%d line parts switched); rejected %s' % (len(chosen), switched, sorted(REJECT)))


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--install', action='store_true')
    ap.add_argument('--set', default='commentary', choices=['commentary', 'tutorial'])
    a = ap.parse_args()
    if a.set == 'tutorial':
        use_tutorial_set()
    install() if a.install else build_plan()
