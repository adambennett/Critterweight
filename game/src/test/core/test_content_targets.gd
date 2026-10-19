extends TestCase
## CNT-04: the committed content targets (docs/DESIGN.md §4) hold in the shipped core package.
## Counts only content that comes from the core package, so an enabled mod can't satisfy a target.

const FIGHTERS := ["f_dozer", "f_dredge", "f_gusto", "f_jitters", "f_knell", "f_slurry", "f_stoke", "f_varga"]
const BASES := ["gullet", "drydock", "crusher", "rooftop"]
const BONUS_MODES := ["spotlight_hog", "chumball", "absolute_unit", "chum_rush"]


func _core(kind: String, type_ := "") -> Array:
	var out := []
	for id in Content.ids(kind):
		if Content.origin_of(kind, str(id)) != "core":
			continue
		var e := Content.get_entry(kind, str(id))
		if type_ == "" or str(e.get("type", "")) == type_:
			out.append(e)
	return out


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func test_eight_playable_fighters_and_npc_cast() -> void:
	var playable := []
	for id in Content.playable_creatures():
		if Content.origin_of("creatures", str(id)) == "core":
			playable.append(str(id))
	playable.sort()
	check_eq(playable, FIGHTERS, "exactly the eight roster fighters are selectable")
	for id in FIGHTERS:
		var c := Content.creature(id)
		check(c != null and c.is_valid(), "%s parses without errors %s" % [id, c.errors if c else []])
	# minion TYPES: variants (e.g. the Scrapling Pelter) extend their base type
	var minions := _core("minions")
	var types := []
	for m: Dictionary in minions:
		check(bool(m.get("npc_only", false)), "minion %s is NPC-only" % m.get("id"))
		# Content resolves "extends" at load and records the chain in "_extends"
		var chain: Array = m.get("_extends", [])
		if chain.is_empty() or Content.get_entry("minions", str(chain[0])).is_empty():
			types.append(str(m.get("id")))
	types.sort()
	check_eq(types, ["npc_blister", "npc_scrapling"], "two minion types (variants extend them)")
	var bosses := _core("bosses")
	check_eq(bosses.size(), 3, "three bosses")
	var fights := _core("boss_fights")
	check_eq(fights.size(), 3, "three boss fights")
	for b: Dictionary in fights:
		check_eq((b.get("phases", []) as Array).size(), 2, "%s has two phases" % b.get("id"))
		check(Content.ids("bosses").has(str(b.get("creature", ""))), "%s uses a boss creature" % b.get("id"))


func test_elements_and_reactions() -> void:
	var d := _read_json("res://content/core/elements.json")
	check_eq((d.get("elements", []) as Array).size(), 8, "eight elements")
	check_eq((d.get("reactions", []) as Array).size(), 14, "fourteen reactions")
	check_eq((d.get("zone_reactions", []) as Array).size(), 11, "zone versions of the reactions")


func test_arena_bases_and_example_layouts() -> void:
	var bases := ArenaCatalog.base_ids()
	for b in BASES:
		check(bases.has(b), "base %s exists" % b)
	var examples := 0
	for e: Dictionary in _core("arenas"):
		if bool(e.get("example", false)):
			examples += 1
			check(str(e.get("base", "")) in BASES, "example %s sits on a core base" % e.get("id"))
			var a := Content.arena(str(e["id"]))
			check(a != null, "example %s loads" % e.get("id"))
	check(examples >= 6, "six example editor layouts (found %d)" % examples)


func test_campaign_content() -> void:
	var acts := _core("encounters", "act")
	check_eq(acts.size(), 3, "three acts")
	var rules := Content.get_entry("ladder", "campaign_rules")
	check_eq(int((rules.get("map", {}) as Dictionary).get("rows", 0)), 6, "six map rows before each boss")
	for act in [1, 2, 3]:
		var tiers := {}
		for e: Dictionary in _core("encounters", "encounter"):
			if int(e.get("act", 0)) == act:
				tiers[str(e.get("tier", ""))] = int(tiers.get(str(e.get("tier", "")), 0)) + 1
		check(int(tiers.get("normal", 0)) >= 8, "act %d: >= 8 normal encounters (%s)" % [act, tiers])
		check(int(tiers.get("elite", 0)) >= 3, "act %d: >= 3 elite encounters (%s)" % [act, tiers])
		check(int(tiers.get("boss", 0)) >= 1, "act %d: a boss encounter" % act)
	check(_core("events", "event").size() >= 24, "at least 24 events")
	check(_core("supplements", "supplement").size() >= 36, "at least 36 supplements")
	check(_core("techniques", "technique").size() >= 36, "at least 36 techniques")


func test_difficulty_ladder_and_bot_tiers() -> void:
	var diffs := []
	for e: Dictionary in _core("ladder", "difficulty"):
		diffs.append(str(e["id"]))
	diffs.sort()
	check_eq(diffs, ["amateur", "pro", "sparring", "title_shot"], "four difficulty presets")
	var doses := _core("ladder", "dose")
	check_eq(doses.size(), 10, "The Dosage has ten Doses")
	var seen := {}
	for d: Dictionary in doses:
		var mods := d.duplicate()
		for k in ["id", "type", "level", "name", "desc", "badge", "color", "_doc"]:
			mods.erase(k)
		for k in mods.keys():
			if str(k).begins_with("_"):
				mods.erase(k)
		var key := JSON.stringify(mods, "", true)
		check(not seen.has(key), "Dose %s has its own modifier" % d.get("id"))
		seen[key] = true
	var tiers := _core("ladder", "bot_tier")
	check_eq(tiers.size(), 5, "five bot skill tiers")
	for t: Dictionary in tiers:
		check(BotBrain.PROFILES.has(str(t.get("profile", ""))), "tier %s maps to a brain profile" % t.get("id"))


func test_fight_camp_upgrades_and_bonus_modes() -> void:
	check(_core("meta_upgrades", "meta_upgrade").size() >= 20, "at least 20 permanent Fight Camp upgrades")
	for m in BONUS_MODES:
		check(ModeRegistry.has(m), "bonus mode %s is registered" % m)
		var preset := Content.get_entry("rules", m)
		check(not preset.is_empty() and str(preset.get("mode", "")) == m, "bonus mode %s has a rules preset" % m)


func test_audio_and_lab_targets() -> void:
	check(Audio.music_ids().size() >= 7, "at least seven music tracks (%d)" % Audio.music_ids().size())
	var lines := 0
	for e: Dictionary in _core("announcer"):
		if str(e.get("speaker", "")) == "barnaby":
			lines += 1
	check(lines >= 150, "at least 150 announcer lines (%d)" % lines)
	# two real training approaches and shipped sample policies
	check(LabTaskES.new() != null and LabTaskBC.new() != null, "ES and behaviour-cloning trainers exist")
	check(_core("policies").size() >= 3, "sample policies ship with the game")
