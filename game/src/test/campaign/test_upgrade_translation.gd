extends CampaignTestCase
## v0.9.18 Movesets: every upgrade written for the v0.9.17 Classic slots keeps meaning something
## (docs/design/MOVESET_COMBAT.md §7, docs/CAMPAIGN_SYSTEMS.md "Moves in runs").
## The lint walks every technique, supplement, side effect, Cannery upgrade and event patch over
## every roster fighter it can reach and checks, through the same code fighters are composed with
## (UpgradeTranslation.analyze on the installed move pools):
##   * Movesets - it changes at least one move of EACH recommended loadout (or only changes the
##     fighter as a whole: HP, stamina, Hype, Grapple, the Ultimate...);
##   * Classic  - it changes at least one move of the Classic kit (or the fighter as a whole);
##   * its hook conditions that name slots match at least one pool move (and Classic slot).
## A generic supplement that can improve nothing this fighter has in a style is acceptable only
## because the reward and shop rolls never offer it to that fighter (RunMoves.offer_weight 0,
## asserted here) - never silently. Everything else that misses must get a translation or a
## Movesets-specific ("movesets") effect.


## Pseudo run state / player for one fighter, style and loadout (every pool move learned).
func _ctx(fid: String, combat: String, loadout: Array) -> Array:
	var inf := RunMoves.info(cat(), fid)
	var st := {"seed": 1, "combat": combat}
	var p := {"id": "p0", "fighter": fid, "techniques": [], "supplements": [],
		"moves": {"learned": (inf.get("order", []) as Array).duplicate(), "equipped": loadout.duplicate(), "drilled": {}}}
	return [st, p]


## Every upgrade a fighter can meet: [{id, kind, apply}].
func _upgrades_for(fid: String) -> Array:
	var c := cat()
	var out := []
	for tid in c.technique_ids_for(fid):
		out.append({"id": str(tid), "kind": "technique", "apply": c.techniques[tid].get("apply", {})})
	for sid in CampaignCatalog._sorted_keys(c.supplements):
		var s: Dictionary = c.supplements[sid]
		if not bool(s.get("consumable", false)) and not (s.get("apply", {}) as Dictionary).is_empty():
			out.append({"id": str(sid), "kind": "supplement", "apply": s["apply"]})
	for se in CampaignCatalog._sorted_keys(c.side_effects):
		var sd: Dictionary = c.side_effects[se]
		if not (sd.get("apply", {}) as Dictionary).is_empty():
			out.append({"id": str(se), "kind": "side_effect", "apply": sd["apply"]})
	for mid in CampaignCatalog._sorted_keys(c.meta):
		var md: Dictionary = c.meta[mid]
		if not (md.get("per_level", {}) as Dictionary).is_empty():
			out.append({"id": str(mid), "kind": "meta", "apply": md["per_level"]})
	for eid in CampaignCatalog._sorted_keys(c.events):
		var ev: Dictionary = c.events[eid]
		var req: Dictionary = ev.get("requires", {})
		if req.has("fighters") and not (req["fighters"] as Array).has(fid):
			continue
		if req.has("party_element") and c.fighter_element(fid) != str(req["party_element"]):
			continue
		for ch in ev.get("choices", []):
			for oi in (ch.get("outcomes", []) as Array).size():
				for eff in ch["outcomes"][oi].get("effects", []):
					var ap := {}
					match str(eff.get("op", "")):
						"run_patches":
							ap = {"patches": eff.get("patches", [])}
							if typeof(eff.get("movesets")) == TYPE_DICTIONARY:
								ap["movesets"] = eff["movesets"]
						"run_hooks":
							ap = {"hooks": eff.get("hooks", [])}
						"run_mods":
							ap = {"mods": eff.get("mods", [])}
						"next_fight":
							ap = eff.get("apply", {})
					if not ap.is_empty():
						out.append({"id": "%s.%s#%d.%s" % [eid, ch.get("id", ""), oi, eff.get("op", "")], "kind": "event", "apply": ap})
	return out


func _fighters() -> Array:
	var out := []
	for fid in cat().roster():
		if cat().resolver.exists(str(fid)):
			out.append(str(fid))
	return out


func test_every_upgrade_reaches_each_recommended_loadout_and_the_classic_kit() -> void:
	var bad := []
	var checked := 0
	var general := 0
	var not_offered := []
	var fighters := _fighters()
	check(fighters.size() >= 8, "the whole roster is installed (%d fighters)" % fighters.size())
	for fid in fighters:
		var inf := RunMoves.info(cat(), fid)
		check(bool(inf["ok"]) and not (inf["loadouts"] as Dictionary).is_empty(), "%s has a move pool with loadouts" % fid)
		var martial := UpgradeTranslation.slot_level(inf, "moves")
		for u in _upgrades_for(fid):
			var ap: Dictionary = u["apply"]
			if martial:
				# a martial fighter (Varga) keeps his Classic strike kit in Movesets (techniques swap
				# strikes): the upgrade must reach that kit, as in Classic
				checked += 1
				var am := UpgradeTranslation.analyze(inf, ap, "moves", [])
				if bool(am["targeted"]) and (am["moves"] as Dictionary).is_empty() and not bool(am["general"]):
					var mctx := _ctx(fid, "moves", [])
					if str(u["kind"]) == "supplement" and RunMoves.offer_weight(cat(), mctx[0], mctx[1], str(u["id"])) == 0.0:
						not_offered.append("%s (%s, Movesets)" % [u["id"], fid])
					else:
						bad.append("%s %s changes nothing of %s's strike kit in Movesets" % [u["kind"], u["id"], fid])
			# Movesets: each recommended loadout
			for lk in ([] if martial else inf["loadout_order"]):
				var lo: Array = (inf["loadouts"][lk] as Dictionary)["moves"]
				checked += 1
				var a := UpgradeTranslation.analyze(inf, ap, "moves", lo)
				if not bool(a["targeted"]):
					general += 1
					continue
				var hit := false
				for id in lo:
					hit = hit or (a["moves"] as Dictionary).has(str(id))
				if hit:
					continue
				var ctx := _ctx(fid, "moves", lo)
				if str(u["kind"]) == "supplement" and (a["moves"] as Dictionary).is_empty() and not bool(a["general"]) \
						and RunMoves.offer_weight(cat(), ctx[0], ctx[1], str(u["id"])) == 0.0:
					not_offered.append("%s (%s, Movesets)" % [u["id"], fid])
					continue
				bad.append("%s %s reaches no move of %s's %s loadout in Movesets (it changes: %s)" % [u["kind"], u["id"], fid, lk,
					", ".join(PackedStringArray((a["moves"] as Dictionary).keys())) if not (a["moves"] as Dictionary).is_empty() else "nothing"])
			# Classic: the Classic kit
			checked += 1
			var ac := UpgradeTranslation.analyze(inf, ap, "classic", [])
			if bool(ac["targeted"]) and (ac["moves"] as Dictionary).is_empty() and not bool(ac["general"]):
				var cctx := _ctx(fid, "classic", [])
				if str(u["kind"]) == "supplement" and RunMoves.offer_weight(cat(), cctx[0], cctx[1], str(u["id"])) == 0.0:
					not_offered.append("%s (%s, Classic)" % [u["id"], fid])
				else:
					bad.append("%s %s changes nothing of %s's Classic kit" % [u["kind"], u["id"], fid])
	print("upgrade translation lint: %d checks, %d fighter-wide, %d not offered: %s" % [checked, general, not_offered.size(), ", ".join(PackedStringArray(not_offered))])
	check(checked > 1000, "checked %d upgrade x fighter x style cases" % checked)
	check(bad.is_empty(), "%d upgrades miss a loadout:\n%s" % [bad.size(), "\n".join(PackedStringArray(bad))])


func test_hook_slot_conditions_match_pool_moves() -> void:
	var bad := []
	var named := 0
	for fid in _fighters():
		var inf := RunMoves.info(cat(), fid)
		for u in _upgrades_for(fid):
			var hooks: Array = (u["apply"] as Dictionary).get("hooks", []).duplicate()
			var mb = (u["apply"] as Dictionary).get("movesets", {})
			if typeof(mb) == TYPE_DICTIONARY:
				hooks.append_array((mb as Dictionary).get("hooks", []))
			for h in hooks:
				var names := UpgradeTranslation.slot_names(h.get("if", {}))
				if names.is_empty():
					continue
				named += 1
				var pool_ok := false
				for id in inf["order"]:
					for n in names:
						pool_ok = pool_ok or UpgradeTranslation.answers_slot(inf["moves"][id], str(n))
				var kit := UpgradeTranslation.classic_kit(inf["raw"])
				var classic_ok := false
				for n2 in names:
					classic_ok = classic_ok or kit.has(str(n2).split("@")[0])
				if not pool_ok:
					bad.append("%s %s: no pool move of %s answers %s" % [u["kind"], u["id"], fid, str(names)])
				if not classic_ok:
					bad.append("%s %s: %s has no Classic slot %s" % [u["kind"], u["id"], fid, str(names)])
	check(named >= 8, "hooks naming slots were checked (%d)" % named)
	check(bad.is_empty(), "%d hook conditions match nothing:\n%s" % [bad.size(), "\n".join(PackedStringArray(bad))])


## Translated patches never break a fighter: every fighter with ALL its techniques, every patching
## supplement, side effect, Cannery upgrade and event patch at once still composes into a valid
## creature in each recommended loadout (BuildApplier would otherwise fall back to the bare kit).
func test_translated_builds_stay_valid_fighters() -> void:
	var bad := []
	for fid in _fighters():
		var inf := RunMoves.info(cat(), fid)
		var sups := []
		var ses := []
		var meta := {}
		var effects := []
		for u in _upgrades_for(fid):
			var ap: Dictionary = u["apply"]
			if (ap.get("patches", []) as Array).is_empty() and typeof(ap.get("movesets")) != TYPE_DICTIONARY:
				continue
			match str(u["kind"]):
				"supplement":
					sups.append({"id": u["id"], "stacks": 1})
				"side_effect":
					ses.append(u["id"])
				"meta":
					meta[u["id"]] = 1
				"event":
					effects.append({"source": u["id"], "apply": ap})
		var los: Array = []
		for lk in inf["loadout_order"]:
			los.append((inf["loadouts"][lk] as Dictionary)["moves"])
		for combat in ["moves", "classic"]:
			for lo in (los if combat == "moves" else [[]]):
				var p := {"id": "p0", "fighter": fid, "techniques": cat().technique_ids_for(fid), "supplements": sups.duplicate(true),
					"side_effects": ses.duplicate(), "run_effects": effects.duplicate(true), "meta": meta.duplicate(),
					"moves": {"learned": (inf["order"] as Array).duplicate(), "equipped": (lo as Array).duplicate(), "drilled": {}}}
				var st := {"variant": "fight_camp", "dose": 0, "combat": combat, "players": [p]}
				var b := BuildApplier.compose(cat(), st, p, {"party": "solo"})
				var c: CreatureDef = b["creature"]
				var broken := c == null or not c.is_valid()
				for w in b["warnings"]:
					broken = broken or str(w).contains("invalid creature")
				if broken:
					bad.append("%s (%s %s): %s" % [fid, combat, str(lo), "; ".join(PackedStringArray(b["warnings"]))])
	check(bad.is_empty(), "%d builds broke a fighter:\n%s" % [bad.size(), "\n".join(PackedStringArray(bad))])


# ---------------------------------------------------------------------------------------------
# The translation rules on real and synthetic kits
# ---------------------------------------------------------------------------------------------

func _stoke() -> Dictionary:
	return cat().resolver.creature_dict("f_stoke")


func _compose(supplements: Array, techniques: Array, loadout: Array, combat := "moves", drilled := {}) -> Dictionary:
	var sups := []
	for s in supplements:
		sups.append({"id": s, "stacks": 1})
	var p := {"id": "p0", "fighter": "f_stoke", "techniques": techniques.duplicate(), "supplements": sups, "side_effects": [], "run_effects": [],
		"moves": {"learned": (RunMoves.info(cat(), "f_stoke")["order"] as Array).duplicate(), "equipped": loadout.duplicate(), "drilled": drilled.duplicate()}}
	var st := {"variant": "off_the_street", "dose": 0, "combat": combat, "players": [p]}
	return BuildApplier.compose(cat(), st, p, {"party": "solo"})


const FURNACE := ["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire"]
const BRAWLER := ["ember_jab", "furnace_haymaker", "flare_rush", "cinder_shot"]


func _effect(move: Dictionary, type: String) -> Dictionary:
	for e in move.get("effects", []):
		if str(e.get("type", "")) == type:
			return e
	return {}


func test_multipliers_reach_inline_moves_once() -> void:
	var base := _stoke()
	var b := _compose(["sup_liver_spots"], [], FURNACE)
	var d: Dictionary = b["creature_dict"]
	var flame0 := _effect(base["movepool"]["flamethrower"]["move"], "area")
	var flame1 := _effect(d["movepool"]["flamethrower"]["move"], "area")
	check_near(float(flame1["buildup"]), float(flame0["buildup"]) * 1.2, 0.0001, "Liver Spots: the Flamethrower's ticks build 20% more Sizzle (once, though moves.* and abilities.* both reach it)")
	check_near(float(d["moves"]["l1"]["buildup"]), float(base["moves"]["l1"]["buildup"]) * 1.2, 0.0001, "and Ember Jab's jab, through its Classic slot")
	var rush0: Dictionary = base["movepool"]["flare_rush"]["move"]
	var rush1: Dictionary = d["movepool"]["flare_rush"]["move"]
	check_near(float(rush1["buildup"]), float(rush0["buildup"]) * 1.2, 0.0001, "Flare Rush's own hit")
	var burst0: Dictionary = rush0["on_hit"][0]["do"][1]
	var burst1: Dictionary = rush1["on_hit"][0]["do"][1]
	check_near(float(burst1["buildup"]), float(burst0["buildup"]) * 1.2, 0.0001, "and its on-hit burst (multipliers reach nested effects)")
	var c: CreatureDef = b["creature"]
	check(c != null and c.is_valid(), "the composed Stoke parses: %s" % (str(c.errors) if c else "null"))


func test_additive_damage_on_a_stream_becomes_a_multiplier() -> void:
	# a synthetic kit: an inline BASIC stream move next to a Classic jab of 4 damage
	var d := {"moves": {"l1": {"damage": 4.0, "hit": [{"t0": 0.1, "t1": 0.2}]}},
		"movepool": {"spray": {"role": "basic", "move": {"duration": 0.8, "effects": [
			{"t": 0.2, "type": "area", "damage": 1.6, "buildup": 6.0, "every": 0.12, "until": "release"},
			{"t": 0.3, "type": "area", "damage": 3.0}]}}}}
	UpgradeTranslation.apply_patch(d, {"op": "add", "path": "moves.l1.damage", "value": 1}, {"seen": []})
	check_near(float(d["moves"]["l1"]["damage"]), 5.0, 0.0001, "the Classic jab gets +1")
	var tick: Dictionary = d["movepool"]["spray"]["move"]["effects"][0]
	check_near(float(tick["damage"]), 1.6 * 5.0 / 4.0, 0.0001, "the stream tick gets x1.25 (the jab's +25%), not +1 per tick")
	var once: Dictionary = d["movepool"]["spray"]["move"]["effects"][1]
	check_near(float(once["damage"]), 4.0, 0.0001, "a single hit keeps the flat +1")
	UpgradeTranslation.apply_patch(d, {"op": "mul", "path": "moves.l2.damage", "value": 1.5}, {"seen": []})
	check_near(float(tick["damage"]), 1.6 * 1.25 * 1.5, 0.0001, "multipliers transfer as they are")
	# the heavy fallback never stacks on an upgrade's own finisher bonus (Feather Knives: +2 heavy, +2 finisher)
	var k := {"moves": {"l1": {"damage": 4.0}, "finisher": {"damage": 9.0, "hit": []}, "heavy": {"damage": 12.0, "hit": []}}}
	var kctx := {"movesets": true, "fallback": true, "loadout": ["jab"], "seen": [],
		"info": {"moves": {"jab": {"id": "jab", "role": "basic", "string": ["l1", "finisher"], "slots": ["l1", "finisher"]}}}}
	UpgradeTranslation.apply_patch(k, {"op": "add", "path": "moves.finisher.damage", "value": 2}, kctx)
	UpgradeTranslation.apply_patch(k, {"op": "add", "path": "moves.heavy.damage", "value": 2}, kctx)
	check_near(float(k["moves"]["finisher"]["damage"]), 11.0, 0.0001, "the finisher gets the upgrade's +2 once")
	check_near(float(k["moves"]["heavy"]["damage"]), 14.0, 0.0001, "the heavy its own +2")
	var k2 := {"moves": {"finisher": {"damage": 9.0, "hit": []}, "heavy": {"damage": 12.0, "hit": []}}}
	kctx["seen"] = []
	UpgradeTranslation.apply_patch(k2, {"op": "add", "path": "moves.heavy.damage", "value": 2}, kctx)
	check_near(float(k2["moves"]["finisher"]["damage"]), 11.0, 0.0001, "a heavy-only upgrade reaches the finisher when no heavy is equipped")
	# time_scale of the whole move also scales a sustain window
	var s := {"movepool": {"jet": {"role": "special", "move": {"duration": 1.0, "sustain": [0.2, 0.6], "effects": [{"t": 0.2, "type": "area"}]}}}}
	UpgradeTranslation.apply_patch(s, {"op": "time_scale", "path": "abilities.*", "value": 0.5}, {"seen": []})
	check_eq(s["movepool"]["jet"]["move"]["sustain"], [0.1, 0.3], "abilities.* time_scale reaches a special inline move, sustain window included")


func test_heavy_upgrades_fall_back_to_the_finisher_without_a_heavy_move() -> void:
	var base := _stoke()
	var furnace := _compose(["sup_tusk_dust", "sup_lucky_tooth"], ["tech_stoke_overcooked"], FURNACE)
	var brawler := _compose(["sup_tusk_dust", "sup_lucky_tooth"], ["tech_stoke_overcooked"], BRAWLER)
	var fin0 := float(base["moves"]["finisher"]["damage"])
	var df: Dictionary = furnace["creature_dict"]
	var db: Dictionary = brawler["creature_dict"]
	check_near(float(df["moves"]["finisher"]["damage"]), fin0 * 1.12 * 1.4, 0.0001, "no heavy equipped: Tusk Dust and Overcooked reach the Gut Furnace finisher")
	check_near(float(db["moves"]["finisher"]["damage"]), fin0, 0.0001, "Furnace Haymaker equipped: the finisher is left alone")
	check_near(float(db["moves"]["heavy_charged"]["damage"]), float(base["moves"]["heavy_charged"]["damage"]) * 1.12 * 1.4, 0.0001, "and the haymaker gets them")
	var lucky_f := {}
	var lucky_b := {}
	for h in df["passives"]:
		if str(h.get("source", "")) == "sup_lucky_tooth":
			lucky_f = h
	for h2 in db["passives"]:
		if str(h2.get("source", "")) == "sup_lucky_tooth":
			lucky_b = h2
	check_eq(str(lucky_f.get("if", {}).get("move_class", "")), "heavy", "Lucky Tooth answers the finisher's heavy class without a heavy move")
	check(not (lucky_f.get("if", {}) as Dictionary).has("slots"), "(its heavy slot list is replaced)")
	check_eq(lucky_b.get("if", {}).get("slots", []), ["heavy", "heavy_charged"], "with a heavy equipped the hook keeps its slots")
	# Classic compositions never use the fallback or the drills
	var classic := _compose(["sup_tusk_dust"], [], FURNACE, "classic", {"ember_jab": "coal_knuckles"})
	check_near(float(classic["creature_dict"]["moves"]["finisher"]["damage"]), fin0, 0.0001, "Classic: the finisher is the v0.9.17 finisher")
	check_near(float(classic["creature_dict"]["moves"]["l1"]["buildup"]), float(base["moves"]["l1"]["buildup"]), 0.0001, "Classic: no drilled style")


func test_movesets_effects_and_string_translation() -> void:
	var base := _stoke()
	var r0 := float(_effect(base["movepool"]["flamethrower"]["move"], "area")["radius"])
	var m := _compose(["sup_projectile_polish"], ["tech_stoke_lead_hand_learner"], FURNACE)
	var dm: Dictionary = m["creature_dict"]
	check_near(float(_effect(dm["movepool"]["flamethrower"]["move"], "area")["radius"]), r0 * 1.12, 0.0001, "Projectile Polish's Movesets effect: streams reach 12% further")
	var cs0: Dictionary = _effect(base["movepool"]["cinder_shot"]["move"], "projectile")
	var cs1: Dictionary = _effect(dm["movepool"]["cinder_shot"]["move"], "projectile")
	check_near(float(cs1["speed"]), float(cs0["speed"]) * 1.2, 0.0001, "and Cinder Shot's coal flies 20% faster (once)")
	check_near(float(cs1["range"]), float(cs0["range"]) + 1.0, 0.0001, "and 1 m further")
	check_eq(dm["movepool"]["ember_jab"]["string"], ["l1", "l1", "l2", "l3", "finisher"], "Lead Hand Learner's double jab reaches Ember Jab's string")
	var c: CreatureDef = m["creature"]
	check(c != null and (c.pool["ember_jab"] as PoolMove).string.size() == 5, "and the fighter really throws it")
	var cl := _compose(["sup_projectile_polish"], [], FURNACE, "classic")
	check_near(float(_effect(cl["creature_dict"]["movepool"]["flamethrower"]["move"], "area")["radius"]), r0, 0.0001, "Classic ignores Movesets-only effects")


func test_texts_and_offer_weights_follow_the_loadout() -> void:
	var st := {"seed": 1, "combat": "moves"}
	var inf := RunMoves.info(cat(), "f_stoke")
	var p := {"id": "p0", "fighter": "f_stoke", "techniques": [], "supplements": [],
		"moves": {"learned": (inf["order"] as Array).duplicate(), "equipped": FURNACE.duplicate(), "drilled": {}}}
	var txt := RunMoves.improves_text(cat(), st, p, "sup_double_wraps")
	check(txt.begins_with("Improves: ") and txt.contains("Ember Jab") and txt.contains("not equipped: Furnace Haymaker"),
		"Double Wraps names the finisher's move and marks the unequipped haymaker: %s" % txt)
	check_eq(RunMoves.improves_text(cat(), st, p, "sup_marrow_shake"), "", "a fighter-wide upgrade names no move")
	check_near(RunMoves.offer_weight(cat(), st, p, "sup_knuckle_wax"), 1.4, 0.0001, "an upgrade for an equipped move is favoured")
	check_near(RunMoves.offer_weight(cat(), st, p, "sup_marrow_shake"), 1.0, 0.0001, "a fighter-wide one keeps its weight")
	var dozer := {"id": "p0", "fighter": "f_dozer", "techniques": [], "supplements": [], "moves": RunMoves.start_moves(cat(), "f_dozer")}
	check_near(RunMoves.offer_weight(cat(), st, dozer, "sup_projectile_polish"), 0.0, 0.0001, "Projectile Polish is never offered to a fighter without projectiles or streams")
	var tdc := RewardRoller.technique_offer(cat(), st, p, "probe", 6, {"tech_stoke_overcooked": 0.0})
	check(not tdc.has("tech_stoke_overcooked"), "an offer weight of 0 keeps an item out of the roll")
	check_eq(RewardRoller.technique_offer(cat(), st, p, "probe", 3), RewardRoller.technique_offer(cat(), st, p, "probe", 3, {}),
		"without weights the roll is the v0.9.17 roll")
