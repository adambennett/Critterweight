class_name EncounterBuilder
extends RefCounted
## Encounter templates -> fights (CAMPAIGN.md §5, §11 scaling):
##   plan(): a deterministic, JSON-safe fight plan stored in the node session (enemy creatures,
##           random fighter picks + builds, minion loadouts, boss, waves, tag bouts, special
##           rules, hazards, difficulty/Dose/party scaling, bot tier). Resumes reuse the plan.
##   build_match(): the MatchSim/App.start_match config (ArenaDef, rules, CampaignMatchMode or
##           BossMode, fighters with patched creatures, mods and input sources). In a Movesets run
##           each player fighter brings its equipped moves (entry "loadout") on a creature composed
##           with its drilled styles; enemy fighters use their default loadout.
## Special rules map onto the engine as: handicap -> several enemies with HP mults; low gravity ->
## per-body gravity_scale; hazards -> CampaignHazards schedule (effects vocabulary); tag bouts /
## waves / sequential entries -> parked fighters swapped in by the mode; timed sudden death ->
## round_time + 1-HP sudden death; ffa -> enemies on separate teams; hype_x2 / enemy start Hype ->
## Fighter.mods; puddles_x2 -> zone lifetime multiplier; blister_fast -> loadout time_scale patch.
## Spars (event "spar" fights) are a copy of your fighter at the template's HP multiplier and are
## never scaled by difficulty, Dose or party size. Bosses use their own phase2_at (a run modifier
## such as Dose 8 only makes phase 2 come sooner).

const PLAYER_TEAM := 0
const ENEMY_TEAM := 1
const MAX_TOTAL_FIGHTERS := 16      ## including parked (waves / tag partners)

## Bot difficulty profile names used by BotBrain for each campaign bot tier (data overrides).
static func bot_profile(catalog: CampaignCatalog, tier: String) -> Dictionary:
	var t: Dictionary = catalog.bot_tiers.get(tier, {})
	return {"profile": str(t.get("profile", "regular")), "overrides": t.get("overrides", {})}


static func make_bot(catalog: CampaignCatalog, tier: String, seed_value: int, creature: CreatureDef) -> BotBrain:
	var bp := bot_profile(catalog, tier)
	var b := BotBrain.new(str(bp["profile"]), seed_value)
	if creature:
		b.set_personality(creature.ai)
	for k in bp["overrides"]:
		b.p[k] = bp["overrides"][k]
	b.label_text = "Bot (%s)" % str(catalog.bot_tiers.get(tier, {}).get("name", tier))
	return b


# =============================================================================================
# Plan
# =============================================================================================

## ctx: {node_id, kind (normal|elite|boss|event), mini (event fight), spar, player (pid) for spar}
static func plan(catalog: CampaignCatalog, state: Dictionary, encounter_id: String, ctx: Dictionary) -> Dictionary:
	var enc: Dictionary = catalog.encounters.get(encounter_id, {})
	var key := "node/%s/plan/%s" % [ctx.get("node_id", "x"), encounter_id]
	var rng := RunRng.stream(int(state.get("seed", 1)), key)
	var rr := RunRules.compute(catalog, state)
	var party := RunState.party_mode(state)
	var players: Array = state.get("players", [])
	var n_players := 1 if party == "tag" else players.size()
	var spar := bool(ctx.get("spar", false))
	if spar:
		n_players = 1
	var tier := str(enc.get("tier", "normal"))
	var arena := catalog.arena_for(str(enc.get("arena", "gullet_day")))
	var sp: Dictionary = enc.get("special", {})
	var party_fighters := []
	for p in players:
		party_fighters.append(str(p.get("fighter", "")))
	var p_out := {
		"encounter": encounter_id, "tier": tier, "name": str(enc.get("name", encounter_id)),
		"blurb": str(enc.get("blurb", "")), "arena_key": str(enc.get("arena", "gullet_day")),
		"arena": arena[0], "variant": arena[1], "enemies": [], "spar": spar, "mini": bool(ctx.get("mini", false)),
		"bot_tier": str(rr.get("bot_tier", "journeyman")), "rule_tags": [], "boss_fight": "",
	}
	# ---------------- enemies ----------------
	var enemies := []
	var picked_fighters := []
	var single_fighter_template := 0
	for en in enc.get("enemies", []):
		if en.has("fighter"):
			single_fighter_template += int(en.get("count", 1))
	for en in enc.get("enemies", []):
		var count := int(en.get("count", 1))
		for i in count:
			var e := {"key": "e%d" % enemies.size(), "hp_mult": float(en.get("hp_mult", 1.0)), "techniques": [],
				"start_hype": float(en.get("start_hype", 0.0)), "wave": int(en.get("wave", -1)), "tag": bool(en.get("tag", false)),
				"group": int(en.get("group", 0)), "kind": "", "creature": "", "name": "", "build": ""}
			if en.has("minion"):
				e["kind"] = "minion"
				e["creature"] = str(en["minion"])
			elif en.has("boss_fight"):
				var bf: Dictionary = catalog.boss_fights.get(str(en["boss_fight"]), {})
				e["kind"] = "boss"
				e["creature"] = str(bf.get("creature", ""))
				e["boss_fight"] = str(en["boss_fight"])
				e["start_hp_frac"] = float(en.get("hp_frac", 1.0))
				e["phases"] = en.get("phases", [])
				p_out["boss_fight"] = str(en["boss_fight"])
			else:
				e["kind"] = "fighter"
				var f := str(en["fighter"])
				if f == "mirror":
					f = party_fighters[0] if not party_fighters.is_empty() else "f_stoke"
					if ctx.has("player"):
						f = str(RunState.player(state, str(ctx["player"])).get("fighter", f))
				elif f == "random":
					var pool := []
					for pf in en.get("pool", catalog.roster()):
						if not party_fighters.has(pf) and catalog.resolver.resolvable(str(pf)):
							pool.append(pf)
					var fresh := []
					for pf2 in pool:
						if not picked_fighters.has(pf2):
							fresh.append(pf2)
					var src: Array = fresh if not fresh.is_empty() else pool
					if src.is_empty():
						src = catalog.available_fighters()
					f = str(src[rng.range_i(0, src.size() - 1)]) if not src.is_empty() else "f_stoke"
				picked_fighters.append(f)
				e["creature"] = f
				var ntech := int(en.get("techniques", 0))
				if en.has("build"):
					e["build"] = str(en["build"])
					e["techniques"] = (catalog.builds.get(e["build"], {}).get("techniques", []) as Array).duplicate()
				elif en.has("techniques_list"):
					e["techniques"] = (en["techniques_list"] as Array).duplicate()
				else:
					var tb := _random_build(catalog, f, ntech, rng)
					e["build"] = str(tb[0])
					e["techniques"] = tb[1]
				# Dose 6 juices enemy fighters — never a spar's copy of you (sparring is unscaled)
				if int(rr.get("enemy_extra_techniques", 0.0)) > 0 and not spar:
					var extra := _random_build(catalog, f, (e["techniques"] as Array).size() + int(rr["enemy_extra_techniques"]), rng, e["techniques"])
					e["techniques"] = extra[1]
				if not spar:
					e["start_hype"] = maxf(float(e["start_hype"]), float(rr.get("enemy_start_hype", 0.0)))
			e["start_hype"] = maxf(float(e["start_hype"]), float(sp.get("enemy_start_hype", 0.0)))
			enemies.append(e)
	# Dose 5: every normal fight adds a Scrapling matching the arena
	if tier == "normal" and int(rr.get("normal_fight_extra_minions", 0.0)) > 0 and not spar:
		var lo := str(catalog.rules.get("arenas", {}).get(p_out["arena_key"], {}).get("minion", "scrapling_basic"))
		for k in int(rr["normal_fight_extra_minions"]):
			enemies.append(_minion_entry(enemies.size(), lo))
	# ---------------- party scaling (simultaneous co-op) ----------------
	var hp_mult := float(rr.get("enemy_hp_mult", 1.0))
	var party_hp_mult := 1.0
	var dmg_mult := float(rr.get("enemy_damage_mult", 1.0))
	var coop: Dictionary = catalog.rules.get("coop", {})
	if party == "coop" and n_players > 1 and not spar:
		var cm: Array = coop.get("enemy_count_mult", [1.0, 1.5, 2.0, 2.5])
		var mult := float(cm[clampi(n_players - 1, 0, cm.size() - 1)])
		var minions := []
		var fighters := []
		for e2 in enemies:
			if e2["kind"] == "minion":
				minions.append(e2)
			elif e2["kind"] == "fighter":
				fighters.append(e2)
		# minion groups scale by count (round up)
		var extra_m := int(ceil(minions.size() * mult)) - minions.size()
		for k2 in extra_m:
			var src_m: Dictionary = minions[k2 % maxi(1, minions.size())]
			var c2: Dictionary = src_m.duplicate(true)
			c2["key"] = "e%d" % enemies.size()
			enemies.append(c2)
		if fighters.size() == 1 and minions.is_empty():
			# single-fighter templates add Scraplings, then a second fighter from 3 players
			var lo2 := str(catalog.rules.get("arenas", {}).get(p_out["arena_key"], {}).get("minion", "scrapling_basic"))
			var adds := 2 if n_players == 2 else (2 if n_players == 4 else 0)
			for k3 in adds:
				enemies.append(_minion_entry(enemies.size(), lo2))
			if n_players >= 3:
				var pool2 := []
				for pf3 in catalog.available_fighters():
					if not party_fighters.has(pf3) and not picked_fighters.has(pf3):
						pool2.append(pf3)
				if pool2.is_empty():
					pool2 = catalog.available_fighters()
				if not pool2.is_empty():
					var f2 := str(pool2[rng.range_i(0, pool2.size() - 1)])
					var second := _random_build(catalog, f2, (fighters[0]["techniques"] as Array).size(), rng)
					var e3: Dictionary = fighters[0].duplicate(true)
					e3["key"] = "e%d" % enemies.size()
					e3["creature"] = f2
					e3["build"] = str(second[0])
					e3["techniques"] = second[1]
					enemies.append(e3)
		elif fighters.size() > 1:
			var extra_f := int(ceil(fighters.size() * mult)) - fighters.size()
			for k4 in extra_f:
				var c4: Dictionary = fighters[k4 % fighters.size()].duplicate(true)
				c4["key"] = "e%d" % enemies.size()
				enemies.append(c4)
		party_hp_mult = 1.0 + float(coop.get("enemy_hp_per_player", 0.35)) * (n_players - 1)
		dmg_mult *= 1.0 + float(coop.get("enemy_damage_per_player", 0.10)) * (n_players - 1)
		p_out["rule_tags"].append("Party of %d: enemies scaled" % n_players)
	var boss_hp_mult := 1.0
	if party == "coop" and n_players > 1:
		boss_hp_mult = 1.0 + float(coop.get("boss_hp_per_player", 0.6)) * (n_players - 1)
	elif party == "tag":
		boss_hp_mult = float(coop.get("tag_boss_hp", 1.3))
	# next-fight rules from events (any party member): enemy HP, enemy Hype, Hype x2, extra hazards
	var nf := {}
	if not spar:
		for p in players:
			var pr := BuildApplier.next_rules(p, str(p_out["arena_key"]))
			for k in pr:
				if k == "enemy_hp_mult":
					nf[k] = maxf(float(nf.get(k, 0.0)), float(pr[k]))
				elif k == "hazards":
					var hzl: Array = nf.get("hazards", [])
					hzl.append_array(pr[k])
					nf["hazards"] = hzl
				else:
					nf[k] = pr[k]
	if nf.has("enemy_hp_mult"):
		hp_mult *= float(nf["enemy_hp_mult"])
		p_out["rule_tags"].append("Weight class: enemies HP x%.2f" % float(nf["enemy_hp_mult"]))
	for e4 in enemies:
		if spar:
			# a spar is a copy of your fighter at the template's own HP multiplier (x0.6): no
			# difficulty, Dose or party scaling of its HP or damage
			e4["dmg_mult"] = 1.0
		else:
			# bosses use their own party multiplier instead of the generic enemy one (CAMPAIGN.md §11)
			e4["hp_mult"] = float(e4["hp_mult"]) * hp_mult * (boss_hp_mult if e4["kind"] == "boss" else party_hp_mult)
			e4["dmg_mult"] = dmg_mult
		e4["name"] = _enemy_name(catalog, e4)
		if nf.has("enemy_start_hype"):
			e4["start_hype"] = maxf(float(e4["start_hype"]), float(nf["enemy_start_hype"]))
	if enemies.size() > MAX_TOTAL_FIGHTERS - players.size():
		enemies = enemies.slice(0, MAX_TOTAL_FIGHTERS - players.size())
	p_out["enemies"] = enemies
	# ---------------- rules ----------------
	var fight_rules: Dictionary = catalog.rules.get("fight", {})
	var r := {"round_time": float(sp.get("sudden_death", fight_rules.get("round_time", 150.0))),
		"sudden_death_grace": float(fight_rules.get("sudden_death_grace", 45.0)),
		"ffa": bool(sp.get("ffa", false)), "gravity": float(sp.get("gravity", 1.0)),
		"hype_mult": maxf(float(sp.get("hype_mult", 1.0)), 2.0 if bool(nf.get("hype_x2", false)) else 1.0),
		"zone_duration_mult": float(sp.get("zone_duration_mult", 1.0)),
		"enemy_tag": {}, "waves": {}, "hazards": [], "handicap": bool(sp.get("handicap", false)),
		"sequential": bool(sp.get("sequential", false))}
	if sp.has("sudden_death"):
		p_out["rule_tags"].append("Timed: %d s, then sudden death" % int(sp["sudden_death"]))
	if r["ffa"]:
		p_out["rule_tags"].append("Free-for-all: enemies fight each other")
	if r["handicap"]:
		p_out["rule_tags"].append("Outnumbered")
	if float(r["gravity"]) < 0.999:
		p_out["rule_tags"].append("Low gravity x%.1f" % float(r["gravity"]))
	if float(r["hype_mult"]) > 1.001:
		p_out["rule_tags"].append("Hype x%.0f" % float(r["hype_mult"]))
	if float(r["zone_duration_mult"]) > 1.001:
		p_out["rule_tags"].append("Puddles last x%.0f" % float(r["zone_duration_mult"]))
	if sp.has("enemy_start_hype"):
		p_out["rule_tags"].append("Enemies start with %d Hype" % int(sp["enemy_start_hype"]))
	if sp.has("tag_bout"):
		var tb2: Dictionary = sp["tag_bout"] if typeof(sp["tag_bout"]) == TYPE_DICTIONARY else {}
		var et: Dictionary = catalog.rules.get("enemy_tag", {}).duplicate()
		for k5 in tb2:
			et[k5] = tb2[k5]
		r["enemy_tag"] = et
		p_out["rule_tags"].append("Tag bout: tagged-out enemies regenerate %.0f HP/s" % float(et.get("regen", 3.0)))
		var tagged := 0
		for e6 in enemies:
			if e6["kind"] == "fighter":
				e6["tag"] = true
				tagged += 1
		if party == "solo" and tagged > 0:
			r["granny_assist"] = true
			p_out["rule_tags"].append("Granny Haymaker: press Switch Target once for a one-hit cameo")
	if sp.has("waves") or r["sequential"]:
		var wv: Dictionary = sp.get("waves", {}) if typeof(sp.get("waves", {})) == TYPE_DICTIONARY else {}
		var waves := int(wv.get("count", 2))
		var trigger := int(wv.get("trigger_alive", 0 if r["sequential"] else 1))
		_assign_waves(enemies, waves, players.size())
		r["waves"] = {"count": waves, "trigger_alive": trigger}
		p_out["rule_tags"].append("Waves: next group at %d left" % trigger if not r["sequential"] else "Sequential: next fighter enters on a KO")
	else:
		# respect the active-fighter cap with automatic waves
		var cap := int(coop.get("max_fighters", 8)) - (1 if party == "tag" else players.size())
		if enemies.size() > cap:
			var groups := int(ceil(float(enemies.size()) / float(maxi(1, cap))))
			_assign_waves(enemies, groups, players.size(), cap)
			r["waves"] = {"count": groups, "trigger_alive": 1}
	# hazards: encounter list (+ arena defaults at their shortest timers on Dose 9)
	var hz := []
	for h in sp.get("hazards", []) + nf.get("hazards", []):
		hz.append((h as Dictionary).duplicate())
	if bool(rr.get("hazards_always_on", 0.0)):
		var have := {}
		for h2 in hz:
			have[str(h2["kind"])] = true
		for h3 in catalog.rules.get("arenas", {}).get(p_out["arena_key"], {}).get("hazards", []):
			if not have.has(str(h3.get("kind", ""))):
				hz.append((h3 as Dictionary).duplicate())
		for h4 in hz:
			var def: Dictionary = catalog.rules.get("hazards", {}).get(str(h4["kind"]), {})
			if def.has("min_every"):
				h4["every"] = float(def["min_every"])
		p_out["rule_tags"].append("Hostile venue: hazards at full tilt")
	for h5 in hz:
		var def2: Dictionary = catalog.rules.get("hazards", {}).get(str(h5["kind"]), {})
		p_out["rule_tags"].append("Hazard: %s%s" % [def2.get("name", h5["kind"]), (" every %d s" % int(h5.get("every", def2.get("every", 0)))) if def2.has("every") else ""])
	r["hazards"] = hz
	p_out["rules"] = r
	if sp.has("blister_fast"):
		p_out["blister_fast"] = float(sp["blister_fast"])
		p_out["rule_tags"].append("Fast Blisters")
	return p_out


static func _minion_entry(i: int, loadout: String) -> Dictionary:
	return {"key": "e%d" % i, "kind": "minion", "creature": loadout, "hp_mult": 1.0, "techniques": [],
		"start_hype": 0.0, "wave": -1, "tag": false, "group": 0, "name": "", "build": ""}


static func _enemy_name(catalog: CampaignCatalog, e: Dictionary) -> String:
	var c := str(e.get("creature", ""))
	if e["kind"] == "boss":
		return str(catalog.boss_fights.get(str(e.get("boss_fight", "")), {}).get("name", c))
	if e["kind"] == "fighter":
		var nm := str(catalog.fighter_info(c).get("name", c))
		var b := str(e.get("build", ""))
		if b != "" and catalog.builds.has(b):
			return "%s (%s)" % [nm, catalog.builds[b].get("name", b)]
		return nm
	var lo: Dictionary = catalog.loadouts.get(c, {})
	return str(lo.get("name", c))


## [build id, techniques] with `n` techniques for fighter f (ROSTER.md build directions).
static func _random_build(catalog: CampaignCatalog, f: String, n: int, rng: RunRng, keep: Array = []) -> Array:
	if f == "" or n <= 0:
		return ["", keep.duplicate()]
	var builds := catalog.build_ids_for(f)
	var bid := ""
	var techs := keep.duplicate()
	if not builds.is_empty():
		bid = str(builds[rng.range_i(0, builds.size() - 1)])
		var bt: Array = rng.shuffled(catalog.builds[bid].get("techniques", []))
		for t in bt:
			if techs.size() < n and not techs.has(t):
				techs.append(t)
	var others := rng.shuffled(catalog.technique_ids_for(f))
	for t2 in others:
		if techs.size() >= n:
			break
		if not techs.has(t2):
			techs.append(t2)
	return [bid, techs]


static func _assign_waves(enemies: Array, waves: int, _players: int, cap := 0) -> void:
	waves = maxi(1, waves)
	var explicit := false
	for e in enemies:
		if int(e.get("wave", -1)) >= 0:
			explicit = true
	if explicit:
		return
	var per := int(ceil(float(enemies.size()) / float(waves)))
	if cap > 0:
		per = mini(per, cap)
	for i in enemies.size():
		enemies[i]["wave"] = mini(waves - 1, int(i / float(maxi(1, per))))


# =============================================================================================
# Match config
# =============================================================================================

## Builds the match config for a plan. opts: {player_kinds: {pid: "player"|"net"|"bot"},
## bot_tier_players: tier for bot-piloted party members, sources: {pid: InputSource},
## local_player: pid}. Returns {config, errors, warnings, roles}.
static func build_match(catalog: CampaignCatalog, state: Dictionary, plan_d: Dictionary, opts := {}) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := []
	var party := RunState.party_mode(state)
	var seed_value := RunRng.derive(int(state.get("seed", 1)), "match/%s/%s" % [state.get("position", ""), plan_d.get("encounter", "")]) & 0x7FFFFFFF
	var arena: ArenaDef = null
	var content = catalog.content
	if content:
		arena = content.arena(str(plan_d.get("arena", ""))) if content.has_method("arena") else null
	if arena == null:
		arena = ArenaDef.from_dict({"id": "campaign_fallback", "name": "The Gullet", "base": "octagon", "radius": 5.0})
		warnings.append("arena '%s' not installed; using a plain cage" % plan_d.get("arena", ""))
	var fighters := []
	var roles := []
	var kinds: Dictionary = opts.get("player_kinds", {})
	var sources: Dictionary = opts.get("sources", {})
	var players: Array = state.get("players", [])
	var spar := bool(plan_d.get("spar", false))
	var spar_pid := str(opts.get("spar_player", ""))
	# the run's combat style (v0.9.18: Movesets unless the run was started as Classic)
	var combat := "classic" if str(state.get("combat", "moves")) == "classic" else "moves"
	for p in players:
		if spar and spar_pid != "" and str(p["id"]) != spar_pid:
			continue
		var arena_key := str(plan_d.get("arena_key", ""))
		# Movesets: the player's equipped moves, composed with their drilled styles (BuildApplier)
		var loadout: Array = RunMoves.fight_loadout(catalog, p) if combat == "moves" else []
		var built := BuildApplier.compose(catalog, state, p, {"party": party, "include_next_fight": not spar, "arena_key": arena_key,
			"roll_seed": int(state.get("seed", 1)), "roll_key": "node/%s/fightroll/%s/%s" % [state.get("position", ""), p["id"], plan_d.get("encounter", "")],
			"combat": combat, "loadout": loadout})
		if built["creature"] == null:
			errors.append_array(built["errors"])
			continue
		warnings.append_array(built["warnings"])
		var mods: Dictionary = built["mods"].duplicate()
		var nrules: Dictionary = {} if spar else BuildApplier.next_rules(p, arena_key)
		var start_hype := clampf(float(p.get("hype_carry", 0.0)) + float(mods.get("start_hype", 0.0)) + float(nrules.get("start_hype", 0.0)), 0.0, 100.0)
		mods["start_hype"] = start_hype
		var kind := str(kinds.get(str(p["id"]), "bot" if bool(p.get("bot", false)) else "player"))
		var entry := {"creature": built["creature"], "team": PLAYER_TEAM, "name": str(p.get("name", "Player")), "mods": mods}
		if not loadout.is_empty():
			entry["loadout"] = loadout.duplicate()
		match kind:
			"player":
				entry["kind"] = "player"
			"net":
				entry["kind"] = "net"
				entry["peer"] = str(p["id"])
				entry["source"] = sources.get(str(p["id"]))
			_:
				entry["kind"] = "campaign_bot"
				var tier := str(opts.get("bot_tier_players", "contender"))
				entry["source"] = sources.get(str(p["id"]), make_bot(catalog, tier, seed_value + fighters.size() * 7 + 1, built["creature"]))
		fighters.append(entry)
		var start_hp := float(p.get("hp", built["max_hp"]))
		if spar:
			start_hp = float(built["max_hp"])
		roles.append({"role": "player", "player_id": str(p["id"]), "start_hp": start_hp, "statuses": built["statuses"],
			"next_rules": nrules, "tag": party == "tag", "wave": -1, "kind": kind})
	var tier2 := str(plan_d.get("bot_tier", "journeyman"))
	var ffa := bool(plan_d.get("rules", {}).get("ffa", false))
	var boss_fight := {}
	for e in plan_d.get("enemies", []):
		var cd: Dictionary = {}
		var ebuild := {}
		if e["kind"] == "fighter":
			var pseudo := {"id": e["key"], "fighter": e["creature"], "techniques": e.get("techniques", []), "supplements": [], "side_effects": []}
			ebuild = BuildApplier.compose(catalog, {"variant": "off_the_street", "dose": 0, "players": [pseudo], "combat": combat}, pseudo, {"party": "solo"})
			if ebuild["creature"] == null:
				errors.append_array(ebuild["errors"])
				continue
			cd = ebuild["creature_dict"]
		else:
			cd = catalog.resolver.creature_dict(str(e["creature"]))
			if cd.is_empty():
				errors.append("enemy creature '%s' is not installed" % e["creature"])
				continue
			if e["kind"] == "minion" and plan_d.has("blister_fast") and (cd.get("tags", []) as Array).has("blister"):
				ContentPatch.apply(cd, {"op": "time_scale", "path": "abilities.ability1", "value": float(plan_d["blister_fast"]), "phase": "startup"})
		var cerrs := PackedStringArray()
		var creature := CreatureResolver.parse(cd, cerrs)
		if creature == null or not cerrs.is_empty():
			errors.append("enemy '%s': %s" % [e["creature"], "; ".join(cerrs)])
			continue
		var emods: Dictionary = ebuild.get("mods", {}).duplicate() if not ebuild.is_empty() else {}
		emods["max_health"] = float(emods.get("max_health", 1.0)) * float(e.get("hp_mult", 1.0))
		emods["damage"] = float(emods.get("damage", 1.0)) * float(e.get("dmg_mult", 1.0))
		emods["start_hype"] = float(e.get("start_hype", 0.0))
		var team := ENEMY_TEAM
		if ffa and e["kind"] == "fighter":
			team = ENEMY_TEAM + fighters.size()
		var entry2 := {"creature": creature, "team": team, "name": str(e.get("name", creature.display_name)), "mods": emods}
		var role := "minion" if e["kind"] == "minion" else ("boss" if e["kind"] == "boss" else "enemy")
		if e["kind"] == "boss":
			boss_fight = catalog.boss_fights.get(str(e.get("boss_fight", "")), {})
			entry2["kind"] = "boss"
			entry2["source"] = BossBrain.new(make_bot(catalog, tier2, seed_value + fighters.size() * 13, creature))
		else:
			entry2["kind"] = "npc"
			entry2["source"] = make_bot(catalog, tier2, seed_value + fighters.size() * 13, creature)
		fighters.append(entry2)
		roles.append({"role": role, "player_id": "", "start_hp": -1.0, "statuses": [], "wave": int(e.get("wave", -1)),
			"tag": bool(e.get("tag", false)), "enemy_key": str(e["key"]), "start_hp_frac": float(e.get("start_hp_frac", 1.0)),
			"phases": e.get("phases", []), "boss_fight": str(e.get("boss_fight", ""))})
	var r: Dictionary = plan_d.get("rules", {})
	var mode_cfg := {"roles": roles, "rules": r, "rule_tags": plan_d.get("rule_tags", []),
		"party": party, "spar": spar, "coop": catalog.rules.get("coop", {}), "hazard_defs": catalog.rules.get("hazards", {}),
		"arena_key": str(plan_d.get("arena_key", "")), "variant": str(plan_d.get("variant", ""))}
	var mode: MatchMode
	if not boss_fight.is_empty():
		var bmods: Dictionary = state.get("flags", {}).get("boss_mods", {}).get(str(boss_fight.get("creature", "")), {})
		mode_cfg["boss"] = boss_fight
		mode_cfg["boss_mods"] = bmods
		mode_cfg["phase2_at"] = boss_phase2_at(catalog, state, boss_fight)
		var lead := 0.0
		for p2 in players:
			lead = maxf(lead, float(RunRules.compute(catalog, state, p2).get("boss_tell_lead", 0.0)))
		mode_cfg["tell_lead"] = lead
		mode = BossMode.new(mode_cfg)
	else:
		mode = CampaignMatchMode.new(mode_cfg)
	CampaignModes.ensure_registered()
	# no_record: the campaign credits whole runs itself (CampaignProgression), so App does not
	# also count each campaign fight as a versus match
	var config := {"arena": arena, "rules": {"rounds": 1, "round_time": float(r.get("round_time", 150.0)), "mode": mode.id(),
		"friendly_fire": false, "lives": 1, "combat": combat}, "seed": seed_value, "mode": mode, "fighters": fighters, "no_record": true,
		"context": {"campaign": true, "variant": plan_d.get("variant", ""), "encounter": plan_d.get("encounter", ""),
			"rule_tags": plan_d.get("rule_tags", []), "dark": _any_dark(players)}}
	return {"config": config, "errors": errors, "warnings": warnings, "roles": roles}


## A boss's phase-2 threshold in this run: its own content value (boss_fights/*.json phase2_at);
## a run modifier (Dose 8 "No Mercy": 65%) only ever brings phase 2 sooner, never later.
static func boss_phase2_at(catalog: CampaignCatalog, state: Dictionary, boss_fight: Dictionary) -> float:
	var run_default := float(CampaignCatalog.RUN_DEFAULTS["boss_phase2_at"])
	var own := float(boss_fight.get("phase2_at", run_default))
	var run := float(RunRules.compute(catalog, state).get("boss_phase2_at", run_default))
	if is_equal_approx(run, run_default):
		return own
	return maxf(own, run)


static func _merged_next_rules(p: Dictionary) -> Dictionary:
	var out := {}
	for nf in p.get("next_fights", []):
		var rules: Dictionary = nf.get("rules", {})
		for k in rules:
			out[k] = rules[k]
	return out


static func _any_dark(players: Array) -> bool:
	for p in players:
		if bool(_merged_next_rules(p).get("dark", false)):
			return true
	return false
