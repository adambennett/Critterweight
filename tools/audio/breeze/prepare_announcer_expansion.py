#!/usr/bin/env python3
"""Build the reviewed announcer expansion text, Content entries, and isolated Breeze plan."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "docs/audio/breeze/announcer_expansion_5000_draft.md"
OUT_DRAFT = ROOT / "docs/audio/breeze/announcer_expansion_draft.md"
OUT_PLAN = ROOT / "docs/audio/breeze/announcer-expansion-plan.json"
OUT_CONTENT = ROOT / "game/content/core/announcer/announcer_expansion.json"
VOICES = {
    "devon": "voc_g53htd8kmjsj",
    "kendall": "voc_j66xnnsxfeet",
}
INSTRUCTIONS = {
    "devon": "A lively ringside sports announcer at a scrappy waterfront cage fight. Clear, brisk, playful; punch the joke, do not scream.",
    "kendall": "A lively ringside sports announcer at a scrappy waterfront cage fight. Clear, brisk, playful; punch the joke, do not scream.",
}

def add(speaker, trigger, when, text, priority=25):
    return {"speaker": speaker, "trigger": trigger, "when": when, "text": text, "priority": priority}

ADDITIONS = [
    add("barnaby", "intro", {"creature": "f_varga"}, "Tonight's guest fights on his own terms: VARGA, the Cage Rules guest!", 85),
    add("barnaby", "intro", {"creature": "f_varga"}, "Four independent limbs, one disciplined plan: make some noise for VARGA!", 85),
    add("barnaby", "intro", {"creature": "f_varga"}, "Varga brings his own corner rules to the cage. Let's see what they can do.", 85),
    add("barnaby", "intro", {"creature": "f_varga"}, "VARGA is in the house, and the footwork comes with a rulebook!", 85),
    add("barnaby", "ability", {"creature": "f_varga", "slot": "ability1"}, "Cut the Angle gives Varga a quick dash and a short damage boost.", 52),
    add("barnaby", "ability", {"creature": "f_varga", "slot": "ability1"}, "There's the Cut the Angle dash. Varga is already setting up the next exchange.", 52),
    add("barnaby", "ability", {"creature": "f_varga", "slot": "ability2"}, "Second Wind is up. Varga's stamina and poise recover faster for a few seconds.", 52),
    add("barnaby", "ability", {"creature": "f_varga", "slot": "ability2"}, "Varga buys a little breathing room with Second Wind. Watch the pace return.", 52),
    add("barnaby", "juice", {"creature": "f_varga"}, "Championship Rounds! Varga has more speed, more power, and a crowd to answer.", 86),
    add("barnaby", "juice", {"creature": "f_varga"}, "Varga's Championship Rounds are live. That burst is only the opening bell.", 86),
    add("barnaby", "juice", {"creature": "f_varga"}, "The Championship Rounds begin! Varga has every limb ready to make a point.", 86),
    add("barnaby", "juice", {"creature": "f_varga"}, "Varga turns up the pace for Championship Rounds. The cage is getting smaller.", 86),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "Varga's lead hand keeps asking questions; the rear hand has the answers."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "That stance changed just in time; Varga has reset the matchup."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "The angles are changing fast. Varga is making the cage feel much wider."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "Three held strike modifiers, four limbs: Varga has ways to start."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "Varga can build a whole combination from independent limbs. Watch the rhythm."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "That low kick is there to make the next head kick harder to read."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "Varga's jab is quick, but the looping left is the one to watch for."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "Varga has the teep ready. That should keep this fight at his range."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "He's switching stances, and the target line just shifted with him."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "Clean body kick from Varga! He is collecting information one strike at a time."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "That rear uppercut could change things if Varga earns the opening."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "Varga's Cut the Angle turns a straight approach into a new lane."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "The guest's control layout is different; the fight plan is all Varga."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "Varga isn't throwing one combo; he's choosing each limb as it goes."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "That cross came after the stance switch; Varga changed the line twice."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "Varga's knee is a close-range answer. The opponent needs to make space."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "One clean overhand from Varga; the front row has a new favorite."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "Varga has plenty of tools, but each one still needs clean timing."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "Varga gave up ground to take a better angle. That's ring craft."),
    add("barnaby", "fighter_color", {"creature": "f_varga"}, "Four limbs, three strike modifiers, and the referee still says two fighters."),
    add("kendall", "fighter_color", {"creature": "f_varga"}, "I wrote down Varga's controls. The paper says I need more paper."),
    add("kendall", "fighter_color", {"creature": "f_varga"}, "Varga has four limbs in motion. My pencil only has one."),
    add("kendall", "fighter_color", {"creature": "f_varga"}, "That stance switch was smooth. I switched seats and nearly missed it."),
    add("kendall", "fighter_color", {"creature": "f_varga"}, "Does Varga get four corners too? I brought one clipboard."),
    add("kendall", "fighter_color", {"creature": "f_varga"}, "Three strike modifiers? My snack has only one setting."),
    add("kendall", "fighter_color", {"creature": "f_varga"}, "Varga's control layout has more options than my lunch menu."),
    add("barnaby", "intro", {"creature": "f_knell"}, "The last shift never clocked out: KNELL, the Hollow Diver!", 85),
    add("barnaby", "intro", {"creature": "f_knell"}, "That salvage suit came back from the deep with a bell to ring: KNELL!", 85),
    add("barnaby", "intro", {"creature": "f_knell"}, "There's a lantern in the fog and a fighter at the bell. KNELL walks in.", 85),
    add("barnaby", "intro", {"creature": "f_knell"}, "Knell's hollow suit is quiet; those hooks have plenty to say.", 85),
    add("barnaby", "ability", {"creature": "f_knell", "slot": "ability1"}, "Ghost Light is away, homing through the cage toward its mark.", 52),
    add("barnaby", "ability", {"creature": "f_knell", "slot": "ability1"}, "Knell sent Ghost Light after the target. That lantern does not lose the trail.", 52),
    add("barnaby", "ability", {"creature": "f_knell", "slot": "ability2"}, "Through the Veil! Knell blinks out and strikes on the other side.", 52),
    add("barnaby", "ability", {"creature": "f_knell", "slot": "ability2"}, "Knell's phase step evades the rush, then rings out around the landing.", 52),
    add("barnaby", "juice", {"creature": "f_knell"}, "Last Bell! Knell is ringing the whole cage with expanding bursts.", 86),
    add("barnaby", "juice", {"creature": "f_knell"}, "Knell's Last Bell is live. Stay alert for the next ring and the next one.", 86),
    add("barnaby", "juice", {"creature": "f_knell"}, "Three rings are rolling outward. Knell has made the floor part of the fight.", 86),
    add("barnaby", "juice", {"creature": "f_knell"}, "Last Bell is building: each pulse reaches farther across the cage.", 86),
    add("barnaby", "fighter_color", {"creature": "f_knell"}, "The lantern is following its mark; Knell is planning around the path."),
    add("barnaby", "fighter_color", {"creature": "f_knell"}, "That Sounding Jab found range. Knell has a clear line to close."),
    add("barnaby", "fighter_color", {"creature": "f_knell"}, "Port Hook! Knell is measuring distance one heavy pull at a time."),
    add("barnaby", "fighter_color", {"creature": "f_knell"}, "Deadweight lands with a thud; the opponent needs to shift their footing."),
    add("barnaby", "fighter_color", {"creature": "f_knell"}, "Knell's Anchor Fist is loading. That's a lot of harbor behind one punch."),
    add("barnaby", "fighter_color", {"creature": "f_knell"}, "Deep Anchor is loaded. The next hit could send someone sailing."),
    add("barnaby", "fighter_color", {"creature": "f_knell"}, "Knell's Wake Breaker closes distance before the counter can settle."),
    add("barnaby", "fighter_color", {"creature": "f_knell"}, "The Rising Bell turns the finish upward. Watch the landing."),
    add("barnaby", "fighter_color", {"creature": "f_knell"}, "Through the Veil makes a bad position temporary. The reappearance is the danger."),
    add("barnaby", "fighter_color", {"creature": "f_knell"}, "Ghost Light homes in; running in a straight line is a risky plan."),
    add("barnaby", "fighter_color", {"creature": "f_knell"}, "Knell's kit is patient: mark the target, change position, then ring them."),
    add("barnaby", "fighter_color", {"creature": "f_knell"}, "The bell is part of the fight now. Knell has made the whole cage listen."),
    add("barnaby", "fighter_color", {"creature": "f_knell"}, "Knell's Salvage Grip has both hands on the problem."),
    add("barnaby", "fighter_color", {"creature": "f_knell"}, "Nobody Home is the taunt. That empty helmet is still intimidating."),
    add("barnaby", "fighter_color", {"creature": "f_knell"}, "That anchor hit carries weight. Knell is not in a hurry to throw it twice."),
    add("barnaby", "fighter_color", {"creature": "f_knell"}, "The lantern holds attention while Knell takes a different angle."),
    add("kendall", "fighter_color", {"creature": "f_knell"}, "I thought the lantern went out. It was just following someone else."),
    add("kendall", "fighter_color", {"creature": "f_knell"}, "That bell has a longer shift than I do."),
    add("kendall", "fighter_color", {"creature": "f_knell"}, "Is the Hollow Diver taking questions? I have one about the lantern."),
    add("kendall", "fighter_color", {"creature": "f_knell"}, "Knell's entrance made my pencil stop writing."),
    add("kendall", "fighter_color", {"creature": "f_knell"}, "The bell rang. I am not sure the cage was asked first."),
    add("kendall", "fighter_color", {"creature": "f_knell"}, "That blink is useful; I blinked and lost my notes."),
    add("barnaby", "element_color", {"element": "scrap"}, "Scrap can leave fighters Rattled for four seconds: guard costs more, poise returns slower."),
    add("barnaby", "element_color", {"element": "scrap"}, "Rattled raises guard's stamina cost by a quarter and slows poise recovery."),
    add("barnaby", "element_color", {"element": "scrap"}, "That Scrap hit left them Rattled; holding guard is suddenly more expensive."),
    add("barnaby", "element_color", {"element": "scrap"}, "The Scrap status is Rattled; it burdens guard and slows poise recovery."),
    add("barnaby", "element_color", {"element": "scrap"}, "Scrap hits build Rattled, a four-second check on guard and poise."),
    add("barnaby", "element_color", {"element": "scrap"}, "Scrap hits hardest into Grit: that matchup adds fifteen percent damage."),
    add("barnaby", "element_color", {"element": "scrap"}, "Rattled lasts four seconds, so a patient defender can wait it out."),
    add("barnaby", "element_color", {"element": "scrap"}, "Scrap is resisted by Spectral, but gets the edge against Grit."),
    add("kendall", "element_color", {"element": "scrap"}, "Rattled makes guard cost more. My guard is mostly a notebook."),
    add("kendall", "element_color", {"element": "scrap"}, "Four seconds of Rattled sounds long. I lose my place in two."),
    add("barnaby", "element_color", {"element": "spectral"}, "Haunted lasts five seconds: cooldowns take 75% time; received healing is 80%."),
    add("barnaby", "element_color", {"element": "spectral"}, "Haunted shortens cooldowns by a quarter and cuts received healing by twenty percent."),
    add("barnaby", "element_color", {"element": "spectral"}, "Spectral builds Haunted. That status changes cooldowns and makes healing less effective."),
    add("barnaby", "element_color", {"element": "spectral"}, "Haunted lasts five seconds, so that healing penalty has a clear window."),
    add("barnaby", "element_color", {"element": "spectral"}, "Spectral carries a fifteen percent edge over Scrap in the matchup chart."),
    add("barnaby", "element_color", {"element": "spectral"}, "Static is favored against Spectral; the type chart can turn a fight."),
    add("barnaby", "element_color", {"element": "spectral"}, "Knell's Spectral hits can leave the other corner Haunted."),
    add("barnaby", "element_color", {"element": "spectral"}, "The Haunted status weakens incoming healing while its cooldown effect runs."),
    add("kendall", "element_color", {"element": "spectral"}, "Haunted helps cooldowns move, but your healing takes a hit."),
    add("kendall", "element_color", {"element": "spectral"}, "I heard a bell and checked my cooldown. It was probably unrelated."),
    add("barnaby", "matchup_color", {"matchup": "f_dozer|f_varga"}, "Against Dozer's forward push, Varga needs to angle off the center line."),
    add("kendall", "matchup_color", {"matchup": "f_dozer|f_varga"}, "Dozer comes straight ahead; Varga's route might need a little diagram."),
    add("barnaby", "matchup_color", {"matchup": "f_dredge|f_varga"}, "Can Varga make Dredge turn before that chain finds its range?"),
    add("kendall", "matchup_color", {"matchup": "f_dredge|f_varga"}, "Dredge has reach; Varga has angles. I brought a protractor."),
    add("barnaby", "matchup_color", {"matchup": "f_jitters|f_varga"}, "Jitters is quick; Varga's angle change will need exact timing."),
    add("kendall", "matchup_color", {"matchup": "f_jitters|f_varga"}, "Varga versus Jitters: the speed notes are already running off the page."),
    add("barnaby", "matchup_color", {"matchup": "f_slurry|f_varga"}, "Against Slurry's movement, Varga will need to keep that lead hand busy."),
    add("kendall", "matchup_color", {"matchup": "f_slurry|f_varga"}, "Slurry is hard to pin down. Varga, I hope your notes are waterproof."),
    add("barnaby", "matchup_color", {"matchup": "f_dozer|f_knell"}, "Dozer brings the forward pressure; Knell can blink before it lands."),
    add("kendall", "matchup_color", {"matchup": "f_dozer|f_knell"}, "Dozer charges, Knell vanishes. I would like that option at the booth."),
    add("barnaby", "matchup_color", {"matchup": "f_jitters|f_knell"}, "Ghost Light against Jitters: a lantern trying to catch lightning."),
    add("kendall", "matchup_color", {"matchup": "f_jitters|f_knell"}, "Jitters is fast, but that lantern seems very committed."),
    add("barnaby", "matchup_color", {"matchup": "f_slurry|f_knell"}, "Slurry is tricky to pin down; Knell's light can follow the mark."),
    add("kendall", "matchup_color", {"matchup": "f_slurry|f_knell"}, "Slurry versus the lantern: I am rooting for both from a safe distance."),
    add("barnaby", "matchup_color", {"matchup": "f_dredge|f_knell"}, "Dredge brings chain range; Knell brings an anchor of its own."),
    add("kendall", "matchup_color", {"matchup": "f_dredge|f_knell"}, "Two salvage specialists, one cage, and I am keeping my pencil inside."),
]

def slug(value):
    return re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")

def main():
    source = BASE.read_text(encoding="utf-8")
    entries = []
    conv_id = ""
    conv_turn = 0
    counts = {}
    for raw in source.splitlines():
        marker = re.match(r"\[Conversation: (.+?) — rare idle exchange\]", raw)
        if marker:
            conv_id = "ann_exp_conv_" + slug(marker.group(1))
            conv_turn = 0
            counts[conv_id] = 0
            continue
        if raw.startswith("New takes —") or raw.startswith("## "):
            conv_id = ""
        match = re.match(r"([DK]) \| (.+)", raw)
        if not match:
            continue
        speaker = "barnaby" if match.group(1) == "D" else "kendall"
        text = match.group(2).strip()
        item = {"speaker": speaker, "text": text, "priority": 22}
        if conv_id:
            conv_turn += 1
            item["conversation_id"] = conv_id
            item["conversation_turn"] = conv_turn
            item["trigger"] = "color_conversation_start" if conv_turn == 1 else "conversation_turn"
            counts[conv_id] += 1
        else:
            item["trigger"] = "color"
        entries.append(item)
    if len(entries) != 746:
        raise SystemExit(f"Expected 746 approved base takes, found {len(entries)}")
    if len(counts) != 9 or any(count != 10 for count in counts.values()):
        raise SystemExit(f"Conversation audit failed: {counts}")
    for addition in ADDITIONS:
        entries.append(addition.copy())
    texts = [item["text"] for item in entries]
    duplicates = sorted({text for text in texts if texts.count(text) > 1})
    if duplicates:
        raise SystemExit("Duplicate lines found: " + repr(duplicates[:10]))
    if any(not item["text"] or len(item["text"]) > 90 for item in entries):
        long = [(i + 1, len(item["text"]), item["text"]) for i, item in enumerate(entries) if len(item["text"]) > 90]
        raise SystemExit(f"Empty or overlong subtitle: {long[:10]}")
    content_items = []
    catalog_lines = []
    clips = {}
    total_chars = 0
    speakers = {}
    for i, item in enumerate(entries, 1):
        line_id = f"ann_exp_{i:04d}"
        item["id"] = line_id
        item.setdefault("when", {})
        speakers[item["speaker"]] = speakers.get(item["speaker"], 0) + 1
        if item["speaker"] not in ("barnaby", "kendall"):
            raise SystemExit("Unknown actor in " + line_id)
        content_items.append(item)
        voice = "devon" if item["speaker"] == "barnaby" else "kendall"
        total_chars += len(item["text"])
        catalog_lines.append({
            "id": line_id,
            "speaker": item["speaker"],
            "template": item["text"],
            "parts": [{"clip": line_id}],
            "voice": voice,
        })
        clips[line_id] = {
            "text": item["text"],
            "voice": voice,
            "voice_id": VOICES[voice],
            "instructions": INSTRUCTIONS[voice],
            "estimated_credits": len(item["text"]) / 10,
        }
    estimated_credits = total_chars / 10
    if estimated_credits > 6000:
        raise SystemExit(f"Expansion requires {estimated_credits:.1f} credits, over the 6,000 cap")
    content = {
        "_doc": "Owner-approved offline Devon/Kendall color commentary expansion; source and budget in docs/audio/breeze/announcer_expansion_draft.md.",
        "items": content_items,
    }
    plan = {
        "version": 1,
        "model_id": "breeze-tts-2",
        "authorized_credits": 6000,
        "voices": VOICES,
        "cast": {"barnaby": "devon", "kendall": "kendall"},
        "lines": catalog_lines,
        "clips": clips,
        "estimated_characters": total_chars,
        "estimated_credits": estimated_credits,
    }
    counts_by_trigger = {}
    for item in content_items:
        trigger = item["trigger"]
        counts_by_trigger[trigger] = counts_by_trigger.get(trigger, 0) + 1
    summary = (
        "## New fighter and type additions\n\n"
        f"These {len(ADDITIONS)} owner-approved additions cover Varga, Knell, Scrap, Spectral, their abilities, "
        "and eight specific roster matchups. D is Devon/Barnaby; K is Kendall. "
        "All spoken takes are generated exactly as written.\n\n"
        + "\n".join(
            f"[{item['trigger']}{' ' + json.dumps(item['when'], ensure_ascii=False) if item['when'] else ''}] "
            f"{'D' if item['speaker'] == 'barnaby' else 'K'} | {item['text']}"
            for item in ADDITIONS
        )
        + "\n\n"
    )
    base_without_old_estimate = re.split(r"\n## Draft size and estimate\s*\n", source, maxsplit=1)[0].rstrip()
    new_draft = (
        base_without_old_estimate + "\n\n" + summary
        + "## Combined size and estimate\n\n"
        + f"Verified by prepare_announcer_expansion.py: {len(content_items)} takes "
        + f"({speakers.get('barnaby', 0)} Devon/Barnaby, {speakers.get('kendall', 0)} Kendall), "
        + f"{len(counts)} rare ten-turn conversations, {total_chars:,} spoken characters, "
        + f"approximately {estimated_credits:,.1f} credits at 1 credit per 10 characters. "
        + f"Longest subtitle: {max(map(len, texts))} characters. "
        + f"Trigger counts: {json.dumps(counts_by_trigger, sort_keys=True)}.\n"
    )
    for path, data in [
        (OUT_DRAFT, new_draft),
        (OUT_PLAN, json.dumps(plan, ensure_ascii=False, indent=2) + "\n"),
        (OUT_CONTENT, json.dumps(content, ensure_ascii=False, indent=2) + "\n"),
    ]:
        if path.exists():
            raise SystemExit("Refusing to overwrite existing file: " + str(path))
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data, encoding="utf-8")
    print(json.dumps({
        "takes": len(content_items),
        "conversations": len(counts),
        "base_takes": len(entries) - len(ADDITIONS),
        "added_takes": len(ADDITIONS),
        "speaker_counts": speakers,
        "characters": total_chars,
        "estimated_credits": round(estimated_credits, 1),
        "longest_subtitle": max(map(len, texts)),
        "trigger_counts": counts_by_trigger,
        "draft": str(OUT_DRAFT),
        "plan": str(OUT_PLAN),
        "content": str(OUT_CONTENT),
    }, indent=2))

if __name__ == "__main__":
    main()
