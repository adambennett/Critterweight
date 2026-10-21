#!/usr/bin/env python3
"""Build the v0.9.18 Movesets tutorial recordings (Granny, the approved Coach Buck voice): the
spoken fields of the Movesets lessons (game/content/core/tutorial/exercises.json, ids tut_m_*) as
composed lines (sentence pieces + tokens), the spoken words for their tokens (the four move buttons
say "that button"; move names are recorded for every ordinary fighter's pool) and an isolated,
budget-checked Breeze plan.

Outputs (refuses to change planned clips once generation has started):
  docs/audio/breeze/v0.9.18/plan-tutorial.json
The catalog (game/assets/audio/speech/v0918/tutorial_catalog.json) is written by generate.py.
Goals are on-screen only and are not recorded.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
EXERCISES = ROOT / "game/content/core/tutorial/exercises.json"
CREATURES = ROOT / "game/content/core/creatures"
PLAN = ROOT / "docs/audio/breeze/v0.9.18/plan-tutorial.json"
LEDGER = ROOT / "docs/audio/breeze/v0.9.18/generation-ledger.jsonl"
VOICES = {"devon": "voc_g53htd8kmjsj", "kendall": "voc_j66xnnsxfeet", "coach_buck": "voc_b36c5rxpfuzb"}
GRANNY = "A gruff veteran boxing coach. Warm tough love, crisp practical instructions, dry wit. Natural speech, no shouting."
LEADS_IN = " This phrase leads straight into a word that is added right after it: keep it flowing and do not finish the sentence."
FOLLOWS = " This phrase continues right after a word said just before it: start mid-flow, no pause before it."
TOKEN = "Say this short name or phrase clearly as part of a sentence, with natural neutral inflection. No introduction."
FIELDS = ["intro", "hint", "rush", "stage", "success"]
ROSTER = ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters", "f_knell"]   # Varga keeps the Classic course
# what a token says when its value is not a recorded word (the bindings differ per device)
FIXED = {"basic": "that button", "charge": "that button", "sustain": "that button", "special": "that button",
         "basic_name": "your basic strike", "charge_name": "your charge move", "sustain_name": "your held move",
         "special_name": "your special", "ultimate_name": "your ultimate"}


def spoken_texts():
    items = json.loads(EXERCISES.read_text(encoding="utf-8"))["items"]
    out = []
    for it in items:
        lid = str(it.get("id", ""))
        if not lid.startswith("tut_m_"):
            continue
        for f in FIELDS:
            if it.get(f):
                out.append((lid + "_" + f, it[f]))
        for variant, fields in (it.get("adapt", {}) or {}).items():
            for f in FIELDS:
                if fields.get(f):
                    out.append((lid + "_" + variant + "_" + f, fields[f]))
    return out


def move_names():
    """lowercased name -> the name as written (the move's display name)"""
    names = {}
    for cid in ROSTER:
        d = json.loads((CREATURES / (cid + ".json")).read_text(encoding="utf-8"))
        for pm in d.get("movepool", {}).values():
            n = str(pm.get("name", "")).strip()
            if n:
                names[n.lower()] = n
        juice = d.get("abilities", {}).get("juice", {})
        if juice.get("name"):
            names[str(juice["name"]).lower()] = str(juice["name"])
    return names


def recorded_words(voice):
    """words this voice already has in the shipped catalogs (not recorded again)"""
    out = set()
    for cat in sorted((ROOT / "game/assets/audio/speech").glob("**/*catalog.json")):
        if cat.name == "tutorial_catalog.json":
            continue
        d = json.loads(cat.read_text(encoding="utf-8"))
        out |= set((d.get("tokens", {}) or {}).get(voice, {}).keys())
    return out


def slug(s):
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


def main():
    texts = spoken_texts()
    if not texts:
        sys.exit("no Movesets lessons found")
    long = [t for _, t in texts if len(t) > 140]
    if long:
        sys.exit("spoken texts too long: " + json.dumps(long))
    clips, lines = {}, []
    for lid, text in texts:
        pieces = re.split(r"(\{\w+\})", text)
        spoken = [k for k, p in enumerate(pieces) if not re.fullmatch(r"\{\w+\}", p) and re.search(r"[A-Za-z0-9]", p)]
        parts = []
        for k, piece in enumerate(pieces):
            tok = re.fullmatch(r"\{(\w+)\}", piece)
            if tok:
                parts.append({"token": tok.group(1)})
                continue
            if not re.search(r"[A-Za-z0-9]", piece):
                continue
            cid = "tut18_" + lid + ("" if len(spoken) == 1 and len(pieces) == 1 else "_" + "abcdefgh"[spoken.index(k)])
            hint = (LEADS_IN if k + 1 < len(pieces) and re.fullmatch(r"\{\w+\}", pieces[k + 1]) else "") + \
                   (FOLLOWS if k > 0 and re.fullmatch(r"\{\w+\}", pieces[k - 1]) else "")
            clips[cid] = {"id": cid, "text": piece.strip(), "voice": "coach_buck", "voice_id": VOICES["coach_buck"],
                          "instructions": GRANNY + hint, "estimated_credits": round(len(piece.strip()) / 10, 1)}
            parts.append({"clip": cid})
        lines.append({"id": "tut18_" + lid, "speaker": "granny", "voice": "coach_buck", "template": text, "parts": parts})
    written = move_names()
    have = recorded_words("coach_buck")
    words = sorted((set(FIXED.values()) | set(written)) - have)
    vocab = {}
    for w in words:
        cid = "tut18_tok_" + slug(w)
        clips[cid] = {"id": cid, "text": written.get(w, w), "voice": "coach_buck",
                      "voice_id": VOICES["coach_buck"], "instructions": TOKEN, "estimated_credits": round(len(w) / 10, 1),
                      "vocabulary": "coach_buck"}
        vocab[w] = cid
    chars = sum(len(c["text"]) for c in clips.values())
    plan = {"version": 1, "release": "0.9.18", "model_id": "breeze-tts-2", "authorized_credits": 10000, "voices": VOICES,
            "cast": {"granny": "coach_buck"}, "fixed_tokens": FIXED, "tokens": {"coach_buck": vocab}, "lines": lines,
            "clips": clips, "estimated_characters": chars, "estimated_credits": round(chars / 10, 1)}
    if LEDGER.exists() and PLAN.exists():
        old = json.loads(PLAN.read_text(encoding="utf-8"))
        done = {json.loads(l)["id"] for l in LEDGER.read_text(encoding="utf-8").splitlines() if l.strip()}
        changed = [k for k in old["clips"] if k in done and k in clips and old["clips"][k]["text"] != clips[k]["text"]]
        if changed:
            sys.exit("Generation has started; refusing to change recorded clips: " + ", ".join(changed[:10]))
    PLAN.write_text(json.dumps(plan, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({"lines": len(lines), "clips": len(clips), "words": len(words), "characters": chars,
                      "estimated_credits": round(chars / 10, 1)}, indent=1))


if __name__ == "__main__":
    main()
