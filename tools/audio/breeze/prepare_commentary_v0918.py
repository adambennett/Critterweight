#!/usr/bin/env python3
"""Build the v0.9.18 Movesets commentary recordings: content entries, speech catalog lines and an
isolated, budget-checked Breeze plan from docs/audio/breeze/v0.9.18/commentary_script.txt.
Same script syntax and delivery presets as v0.9.17 (prepare_commentary_v0917.py).

Outputs (refuses to overwrite a plan that has started generating):
  game/content/core/announcer/commentary_v0918.json   new lines (cmt18_*) with triggers, gates, families
  docs/audio/breeze/v0.9.18/plan.json                 clips: text, voice, voice_id, delivery instructions
The catalog (game/assets/audio/speech/v0918/catalog.json) is written by generate.py after generation.
Facts are checked against content: a line gated on a creature's pool move ("id") must name a move in
that creature's movepool, and a category gate ("cat") must be a Movesets category.
Retakes keep their original line id (the new catalog overrides the old clip); corrections retire the
old line (tools/audio/retag_commentary.js) and add a new one; whole-sentence variants add exact-text
catalog lines that SpeechLibrary prefers to a composed name + sentence.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "docs/audio/breeze/v0.9.18/commentary_script.txt"
PLAN = ROOT / "docs/audio/breeze/v0.9.18/plan.json"
LEDGER = ROOT / "docs/audio/breeze/v0.9.18/generation-ledger.jsonl"
CONTENT = ROOT / "game/content/core/announcer/commentary_v0918.json"
ANNOUNCER = [ROOT / "game/content/core/announcer" / f for f in ("barnaby.json", "barnaby_vintage.json", "announcer_expansion.json",
                                                                 "commentary_v0917.json")]
CREATURES = ROOT / "game/content/core/creatures"
CATEGORIES = {"strike", "projectile", "volley", "stream", "blast", "rush", "control", "counter", "support", "utility"}
VOICES = {"devon": "voc_g53htd8kmjsj", "kendall": "voc_j66xnnsxfeet", "coach_buck": "voc_b36c5rxpfuzb"}
SPEAKER = {"D": "barnaby", "K": "kendall"}
VOICE_OF = {"barnaby": "devon", "kendall": "kendall"}
# Delivery presets: the v0.9.15 expansion used one instruction for every take; the moment decides now.
DELIVERY = {
    "D:hype": "A veteran ringside fight announcer calling a huge moment live at a rowdy waterfront cage fight: explosive, rising excitement with a big punch on the key words and the finish. Loud and thrilled, but clear and never distorted.",
    "D:call": "A quick, engaged ringside play-by-play announcer calling the action the instant it happens: crisp, energetic, natural pace, clearly watching it live.",
    "D:tense": "A ringside announcer as the pressure builds: urgent, fast and focused, controlled intensity that leans forward into the next moment.",
    "D:warm": "A warm, knowledgeable fight announcer giving a quick read on the fight between exchanges: conversational and confident, medium energy, a smile in the voice.",
    "D:ceremony": "A ring announcer reading the official result: a theatrical build-up, then a proud, ringing, celebratory delivery of the final words.",
    "K:dry": "A deadpan comedic co-commentator at a cage fight: dry, understated, slightly bemused timing; relaxed and natural. Let the joke land quietly.",
    "K:react": "A deadpan co-commentator genuinely startled by a big moment: a quick, surprised reaction that settles into dry humour.",
    "K:warm": "A friendly co-commentator making a quick, curious observation: natural, light and conversational.",
}
TOKEN_INSTRUCTION = "Say this short name or phrase clearly as part of a sentence, with natural neutral inflection. No introduction."
CEREMONY_INSTRUCTION = "A ring announcer proudly calling out the winner's name at the climax of the result: big, ringing and celebratory, with a held final syllable. Say only this name."
LEADS_IN = " This phrase leads straight into a fighter's name that is added right after it: keep the build-up rising and do not finish the sentence."
FOLLOWS = " This phrase continues right after a fighter's name: start mid-flow, no pause before it."
ENERGY = {"hype": "high", "ceremony": "high", "call": "medium", "tense": "high", "warm": "medium", "react": "medium", "dry": "low"}
PRIORITY = {"stoppage": 100, "ko": 100, "decision": 100, "draw": 100, "win": 95, "career_result": 95, "juice": 86, "intro": 85,
            "career_intro": 85, "knockdown": 80, "round_start": 75, "round_end": 75, "judges_round": 72, "referee": 60, "time": 70,
            "big_hit": 60, "parry": 50, "guard_break": 60, "combo": 45, "first_hit": 45, "low_health": 45, "reaction": 55,
            "ability": 45, "ability_hit": 50, "ability_miss": 35, "result": 30, "round_break": 30}
# Families for selector spacing, by keyword (the reviewed bank uses the same slugs).
FAMILY_WORDS = [("notes", r"\b(notes?|pencil|notebook|napkin|scrapbook|wrote|written|underline|circled|sticky note)\b"),
                ("snacks", r"\b(snack|sandwich|crackers|breakfast|lunch|truffles|kettle|roast)\b"), ("booth", r"\b(booth|chair|desk|seat)\b"),
                ("officials", r"\b(referee|judges?|cards?|scorecards?|ten-nine|ten-eight|ten-ten)\b"), ("glandco", r"\bglandco\b"),
                ("tide", r"\b(tide|harbour|harbor|water|wave|drain|plumbing|wet|puddle|swamp)\b"), ("weather", r"\b(wind|storm|gust|breeze|hurricane)\b"),
                ("crowd", r"\b(crowd|front row|folks)\b"), ("money", r"\b(purse|invoiced|refunds|contract|promoter)\b"),
                ("science", r"\b(arithmetic|math|count)\b"), ("venue", r"\b(cage|arena|building|cannery|floor|gutter|plate)\b")]


def families(text):
    low = text.lower()
    out = [name for name, rx in FAMILY_WORDS if re.search(rx, low)]
    return out[:3]


def parse():
    trigger, when = None, {}
    takes, retakes, fixes, tokens, variants = [], [], [], [], []
    for n, raw in enumerate(SCRIPT.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("@"):
            m = re.match(r"@(\w+)\s+(\{.*\})$", line)
            if not m:
                sys.exit(f"line {n}: bad trigger header: {line}")
            trigger, when = m.group(1), json.loads(m.group(2))
            continue
        if line.startswith("R "):
            m = re.match(r"R ([DK]:\w+) \| (\S+)$", line)
            retakes.append((m.group(1), m.group(2)))
            continue
        if line.startswith("X "):
            m = re.match(r"X (\S+) ([DK]:\w+) \| (.+)$", line)
            fixes.append((m.group(1), m.group(2), m.group(3)))
            continue
        if line.startswith("T ") or line.startswith("W "):
            m = re.match(r"([TW]) (\w+) \| (.+)$", line)
            tokens.append((m.group(2) + ("_ceremony" if m.group(1) == "W" else ""), m.group(3).strip()))
            continue
        if line.startswith("V "):
            m = re.match(r"V (\S+) \| (.+)$", line)
            spec = {}
            for part in m.group(2).split(";"):
                k, v = part.strip().split("=")
                spec[k.strip()] = [x.strip() for x in v.split(",")]
            variants.append((m.group(1), spec))
            continue
        m = re.match(r"([DK]:\w+) \| (.+)$", line)
        if not m or trigger is None:
            sys.exit(f"line {n}: not understood: {line}")
        takes.append({"delivery": m.group(1), "text": m.group(2).strip(), "trigger": trigger, "when": dict(when)})
    return takes, retakes, fixes, tokens, variants


def pool_ids(creature):
    path = CREATURES / (creature + ".json")
    if not path.exists():
        sys.exit(f"unknown creature in a gate: {creature}")
    data = json.loads(path.read_text(encoding="utf-8"))
    return set(data.get("movepool", {}).keys())            # movepool is keyed by pool move id


def check_facts(takes):
    bad = []
    for t in takes:
        w = t["when"]
        if "cat" in w and w["cat"] not in CATEGORIES:
            bad.append(f"unknown category {w['cat']}: {t['text']}")
        if "id" in w:
            if "creature" not in w:
                bad.append(f"a move gate without a creature: {t['text']}")
            elif w["id"] not in pool_ids(w["creature"]):
                bad.append(f"{w['creature']} has no pool move {w['id']}: {t['text']}")
    if bad:
        sys.exit("Fact check failed:\n" + "\n".join(bad))


def main():
    takes, retakes, fixes, tokens, variants = parse()
    check_facts(takes)
    existing = {}
    for f in ANNOUNCER:
        for e in json.loads(f.read_text(encoding="utf-8"))["items"]:
            existing[e["id"]] = e
    texts = [t["text"] for t in takes] + [f[2] for f in fixes]
    long = [t for t in texts if len(t) > 90]
    if long:
        sys.exit("Subtitles over 90 characters: " + json.dumps(long, indent=1))
    dup = sorted({t for t in texts if texts.count(t) > 1} | {t for t in texts if t in {e["text"] for e in existing.values()}})
    if dup:
        sys.exit("Duplicate text: " + json.dumps(dup, indent=1))
    items, lines, clips = [], [], {}

    def clip(cid, text, voice, instructions):
        clips[cid] = {"id": cid, "text": text, "voice": voice, "voice_id": VOICES[voice], "instructions": instructions,
                      "estimated_credits": round(len(text) / 10, 1)}

    for i, t in enumerate(takes, 1):
        cid = f"cmt18_{i:04d}"
        speaker = SPEAKER[t["delivery"][0]]
        kind = t["delivery"].split(":")[1]
        item = {"id": cid, "speaker": speaker, "trigger": t["trigger"], "when": t["when"], "priority": PRIORITY.get(t["trigger"], 40 if speaker == "barnaby" else 25),
                "text": t["text"], "families": families(t["text"]), "energy": ENERGY[kind], "situation": t["trigger"], "delivery": t["delivery"]}
        items.append(item)
        parts = []
        pieces = re.split(r"(\{\w+\})", t["text"])
        spoken = [(k, p) for k, p in enumerate(pieces) if not re.fullmatch(r"\{\w+\}", p) and re.search(r"[A-Za-z0-9]", p)]
        letter = "abcdefgh"
        for k, piece in enumerate(pieces):
            tok = re.fullmatch(r"\{(\w+)\}", piece)
            if tok:
                parts.append({"token": tok.group(1)})
                continue
            if not re.search(r"[A-Za-z0-9]", piece):
                continue          # punctuation around a name is not spoken on its own
            sub = cid if len(spoken) == 1 and len(pieces) == 1 else cid + "_" + letter[[x[0] for x in spoken].index(k)]
            hint = (LEADS_IN if k + 1 < len(pieces) and re.fullmatch(r"\{\w+\}", pieces[k + 1]) else "") + \
                   (FOLLOWS if k > 0 and re.fullmatch(r"\{\w+\}", pieces[k - 1]) else "")
            clip(sub, piece.strip(), VOICE_OF[speaker], DELIVERY[t["delivery"]] + hint)
            parts.append({"clip": sub})
        lines.append({"id": cid, "speaker": speaker, "template": t["text"], "parts": parts, "voice": VOICE_OF[speaker]})
    for j, (old, delivery, text) in enumerate(fixes, 1):
        src = existing[old]
        cid = f"cmt18_x{j:03d}"
        speaker = SPEAKER[delivery[0]]
        item = {"id": cid, "speaker": speaker, "trigger": src["trigger"], "when": src.get("when", {}), "priority": src.get("priority", 25),
                "text": text, "families": src.get("families", []), "energy": src.get("energy", "medium"), "situation": src.get("situation", ""),
                "delivery": delivery, "replaces": old}
        items.append(item)
        clip(cid, text, VOICE_OF[speaker], DELIVERY[delivery])
        lines.append({"id": cid, "speaker": speaker, "template": text, "parts": [{"clip": cid}], "voice": VOICE_OF[speaker]})
    for old_id, delivery in [(r[1], r[0]) for r in retakes]:
        src = existing[old_id]
        if "{" in src["text"]:
            sys.exit(f"retake {old_id} has a name/number token; use a V (whole sentence) entry instead")
        cid = f"cmt18_rt_{old_id}"
        clip(cid, src["text"], VOICE_OF[src["speaker"]], DELIVERY[delivery])
        # same line id: this catalog loads last, so the retake replaces the old clip for this line
        lines.append({"id": old_id, "speaker": src["speaker"], "template": src["text"], "parts": [{"clip": cid}], "voice": VOICE_OF[src["speaker"]]})
    token_map = {}
    for vocab, word in tokens:
        voice = vocab.replace("_ceremony", "")
        cid = f"cmt18_tok_{vocab}_{re.sub(r'[^a-z0-9]+', '_', word.lower())}"
        spoken_word = word.title() if not word.startswith("player") else word.capitalize()
        clip(cid, spoken_word + ("!" if vocab.endswith("_ceremony") else ""), voice,
             CEREMONY_INSTRUCTION if vocab.endswith("_ceremony") else TOKEN_INSTRUCTION)
        clips[cid]["vocabulary"] = vocab
        token_map.setdefault(vocab, {})[word.lower()] = cid
    var_delivery = {"ann_first_03": "D:call", "ann_combo_04": "D:hype", "ann_parry_03": "D:hype", "ann_kd_04": "D:hype", "ann_kd_05": "D:warm",
                    "ann_comeback_03": "D:hype", "ann_ko_07": "D:warm", "ann_low_02": "D:tense", "ann_first_04": "D:warm", "ann_parry_05": "D:warm",
                    "ann_comeback_04": "D:hype", "ann_low_03": "D:call"}
    for line_id, spec in variants:
        src = existing[line_id]
        combos = [{}]
        for key in ("o", "p"):
            if key in spec:
                combos = [dict(c, **{key: name}) for c in combos for name in spec[key]]
        for c in combos:
            text = src["text"]
            for k, v in c.items():
                text = text.replace("{" + k + "}", v)
            if "{" in text:
                sys.exit(f"variant of {line_id} leaves a token: {text}")
            if len(text) > 90:
                sys.exit(f"variant of {line_id} too long: {text}")
            cid = "cmt18_v_" + line_id.replace("ann_", "") + "_" + "_".join(c[k].lower() for k in sorted(c))
            clip(cid, text, VOICE_OF[src["speaker"]], DELIVERY[var_delivery[line_id]])
            lines.append({"id": cid, "speaker": src["speaker"], "template": text, "parts": [{"clip": cid}], "voice": VOICE_OF[src["speaker"]],
                          "variant_of": line_id})
    chars = sum(len(c["text"]) for c in clips.values())
    plan = {"version": 1, "release": "0.9.18", "model_id": "breeze-tts-2", "authorized_credits": 10000, "voices": VOICES,
            "cast": {"barnaby": "devon", "kendall": "kendall", "granny": "coach_buck"}, "tokens": token_map, "lines": lines, "clips": clips,
            "estimated_characters": chars, "estimated_credits": round(chars / 10, 1)}
    if LEDGER.exists() and LEDGER.read_text(encoding="utf-8").strip() and PLAN.exists():
        old = json.loads(PLAN.read_text(encoding="utf-8"))
        changed = [k for k in old["clips"] if k in clips and old["clips"][k]["text"] != clips[k]["text"]]
        if changed:
            sys.exit("Generation has started; refusing to change planned clips: " + ", ".join(changed[:10]))
    PLAN.parent.mkdir(parents=True, exist_ok=True)
    PLAN.write_text(json.dumps(plan, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    CONTENT.write_text(json.dumps({"_doc": "v0.9.18 Movesets commentary (docs/audio/COMMENTARY.md); recordings in docs/audio/breeze/v0.9.18.",
                                   "items": items}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    counts = {}
    for it in items:
        counts[it["trigger"]] = counts.get(it["trigger"], 0) + 1
    print(json.dumps({"new_lines": len(takes), "corrections": len(fixes), "retakes": len(retakes), "tokens": len(tokens),
                      "variants": sum(1 for l in lines if l.get("variant_of")), "clips": len(clips), "characters": chars,
                      "estimated_credits": round(chars / 10, 1), "speakers": {s: sum(1 for i in items if i["speaker"] == s) for s in ("barnaby", "kendall")},
                      "by_trigger": dict(sorted(counts.items(), key=lambda kv: -kv[1]))}, indent=1))


if __name__ == "__main__":
    main()
