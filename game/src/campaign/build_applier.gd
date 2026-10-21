class_name BuildApplier
extends RefCounted
## Builds a fighter for one campaign fight from a run player's build:
##   base creature JSON (CreatureResolver)
##   + Fight Camp upgrades (ONLY when state.variant == "fight_camp" or ctx.gym_bonuses — the
##     meta_bonus isolation rule, COOP-06: nothing else may load them)
##   + techniques, supplements (x stacks), side effects, event run effects
##   + Dose player modifiers (e.g. Dose 3: max HP x0.9)
##   + next-fight effects (events) when building for an actual fight.
## Every package is an "apply" block: {patches, mods, hooks, statuses, run, movesets}. Patches
## transform the creature JSON (ContentPatch, through UpgradeTranslation so upgrades written for
## the Classic slots also reach the Movesets pool moves); mods become Fighter.mods; hooks are
## appended to the creature's passives; statuses are applied by CampaignMatchMode at the bell; run
## entries are economy modifiers handled by RunRules. The result is deterministic for a given build.
## Movesets compositions (ctx.combat or state.combat "moves"; docs/CAMPAIGN_SYSTEMS.md "Moves in
## runs") first apply the player's drilled styles (player.moves.drilled: a style shapes its move,
## upgrades then improve it), add each block's "movesets" block, and use the loadout (ctx.loadout,
## else the player's equipped moves, else the fighter's default) for the heavy fallback. Anything
## else (Classic runs, the AI Lab, callers that do not say) gets only the Classic-safe translation.

const MAX_BUILD_HOOKS := 24       ## leave room under Hooks.MAX_HOOKS (32) for JUICE/status hooks


## True if a next-fight effect applies to a fight in `arena_key` (some are bound to one arena).
static func next_fight_applies(nf: Dictionary, arena_key: String) -> bool:
	var bound := str(nf.get("arena", ""))
	return bound == "" or bound == arena_key or arena_key.begins_with(bound)


## Merged next-fight rules of a player for a fight in `arena_key`.
static func next_rules(player: Dictionary, arena_key: String) -> Dictionary:
	var out := {}
	for nf in player.get("next_fights", []):
		if not next_fight_applies(nf, arena_key):
			continue
		var rules: Dictionary = nf.get("rules", {})
		for k in rules:
			if k == "start_hype":
				out[k] = float(out.get(k, 0.0)) + float(rules[k])
			elif k == "hazards":
				var hz: Array = out.get("hazards", [])
				hz.append_array(rules[k])
				out["hazards"] = hz
			elif k in ["enemy_hp_mult", "reward_mult"]:
				out[k] = float(out.get(k, 1.0)) * float(rules[k])
			else:
				out[k] = rules[k]
	return out


## Ordered build packages for a player: [{source, kind, apply, level}].
static func packages(catalog: CampaignCatalog, state: Dictionary, player: Dictionary, include_next_fight: bool, gym_bonuses := false, arena_key := "") -> Array:
	var out := []
	if str(state.get("variant", "")) == "fight_camp" or gym_bonuses:
		var lv: Dictionary = player.get("meta", {})
		for mid in CampaignCatalog._sorted_keys(lv):
			var m: Dictionary = catalog.meta.get(mid, {})
			if m.is_empty() or int(lv[mid]) <= 0 or not bool(m.get("meta_bonus", false)):
				continue
			out.append({"source": mid, "kind": "meta", "apply": m.get("per_level", {}), "level": int(lv[mid])})
	for tid in player.get("techniques", []):
		var t: Dictionary = catalog.techniques.get(str(tid), {})
		if not t.is_empty():
			out.append({"source": str(tid), "kind": "technique", "apply": t.get("apply", {}), "level": 1})
	for s in player.get("supplements", []):
		var sid := str(s.get("id", ""))
		var sd: Dictionary = catalog.supplements.get(sid, {})
		if sd.is_empty():
			continue
		for i in maxi(1, int(s.get("stacks", 1))):
			out.append({"source": sid, "kind": "supplement", "apply": sd.get("apply", {}), "level": 1})
	for se in player.get("side_effects", []):
		var sed: Dictionary = catalog.side_effects.get(str(se), {})
		if not sed.is_empty():
			out.append({"source": str(se), "kind": "side_effect", "apply": sed.get("apply", {}), "level": 1})
	for re in player.get("run_effects", []):
		out.append({"source": str(re.get("source", "event")), "kind": "event", "apply": re.get("apply", {}), "level": 1})
	var dose_level := int(state.get("dose", 0))
	var r := {"player_max_hp_mult": 1.0}
	for l in range(1, dose_level + 1):
		RunRules.apply_entries(r, catalog.dose(l).get("run", []))
	if float(r["player_max_hp_mult"]) != 1.0:
		out.append({"source": "dose", "kind": "dose", "apply": {"mods": [{"key": "max_health", "mul": float(r["player_max_hp_mult"])}]}, "level": 1})
	if include_next_fight:
		for nf in player.get("next_fights", []):
			if next_fight_applies(nf, arena_key):
				out.append({"source": str(nf.get("source", "event")), "kind": "next_fight", "apply": nf.get("apply", {}), "level": 1})
	return out


## Scales an apply block's numbers for `level` (meta upgrades: linear per level).
static func scaled_patch(p: Dictionary, level: int) -> Dictionary:
	if level == 1:
		return p
	var c: Dictionary = p.duplicate(true)
	match str(p.get("op", "")):
		"add":
			c["value"] = float(p["value"]) * level
		"mul", "time_scale":
			c["value"] = 1.0 + (float(p["value"]) - 1.0) * level
		"append":
			c["value"] = p["value"]
	return c


static func _when_ok(entry: Dictionary, party: String) -> bool:
	var w := str(entry.get("when", "always"))
	match w:
		"solo":
			return party == "solo"
		"coop":
			return party != "solo"
		"tag":
			return party == "tag"
	return true


## Accumulates mod entries into `mods` (identity values from CampaignCatalog.MOD_DEFAULTS).
static func add_mods(mods: Dictionary, entries: Array, level: int, party: String) -> void:
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY or not _when_ok(e, party):
			continue
		var key := str(e.get("key", ""))
		var cur := float(mods.get(key, CampaignCatalog.MOD_DEFAULTS.get(key, 0.0)))
		if e.has("set"):
			mods[key] = float(e["set"])
		elif e.has("mul"):
			mods[key] = cur * (1.0 + (float(e["mul"]) - 1.0) * level)
		elif e.has("add"):
			mods[key] = cur + float(e["add"]) * level


## The translation context of a composition (UpgradeTranslation.context): Movesets only when the
## caller or the run says so.
static func translation_context(catalog: CampaignCatalog, state: Dictionary, player: Dictionary, ctx := {}) -> Dictionary:
	var combat := str(ctx.get("combat", state.get("combat", "")))
	if combat != "moves":
		return UpgradeTranslation.context({}, combat, [])
	var inf := RunMoves.info(catalog, str(player.get("fighter", "")))
	var lo_v = ctx.get("loadout", [])
	var lo: Array = lo_v if typeof(lo_v) == TYPE_ARRAY and not (lo_v as Array).is_empty() else RunMoves.fight_loadout(catalog, player)
	return UpgradeTranslation.context(inf, "moves", lo)


## Composes the fighter for a fight. ctx: {party: solo|coop|tag, include_next_fight: bool,
## gym_bonuses: bool, combat: "moves"|"classic" (default: state.combat), loadout: [pool ids]}.
## Returns {creature, creature_dict, mods, statuses, max_hp, warnings, errors, sources}.
static func compose(catalog: CampaignCatalog, state: Dictionary, player: Dictionary, ctx := {}) -> Dictionary:
	var party := str(ctx.get("party", "solo"))
	var res := {"creature": null, "creature_dict": {}, "mods": {}, "statuses": [], "max_hp": 0.0,
		"warnings": [], "errors": PackedStringArray(), "sources": []}
	var d := catalog.resolver.creature_dict(str(player.get("fighter", "")))
	if d.is_empty():
		res["errors"].append("fighter '%s' is not installed" % player.get("fighter", ""))
		return res
	var passives: Array = d.get("passives", [])
	var mods := {}
	var statuses := []
	var tctx := translation_context(catalog, state, player, ctx)
	var movesets := bool(tctx.get("movesets", false))
	if movesets:
		# drilled styles shape their moves before any upgrade improves them
		for dp in RunMoves.drill_packages(catalog, player):
			for sp in dp["patches"]:
				if typeof(sp) == TYPE_DICTIONARY and ContentPatch.apply(d, sp) == 0:
					res["warnings"].append("%s: style patch '%s' matched nothing on %s" % [dp["source"], sp.get("path", ""), d.get("id", "")])
			res["sources"].append(str(dp["source"]))
	var pkgs := packages(catalog, state, player, bool(ctx.get("include_next_fight", false)), bool(ctx.get("gym_bonuses", false)), str(ctx.get("arena_key", "")))
	for pkg in pkgs:
		var ap: Dictionary = pkg.get("apply", {})
		var level := int(pkg.get("level", 1))
		var blocks: Array = [ap]
		if movesets and typeof(ap.get("movesets")) == TYPE_DICTIONARY:
			blocks.append(ap["movesets"])
		tctx["seen"] = []          # a leaf changes once per upgrade (UpgradeTranslation)
		for blk in blocks:
			var b: Dictionary = blk
			for p in b.get("patches", []):
				if typeof(p) != TYPE_DICTIONARY or not _when_ok(p, party):
					continue
				var hits := UpgradeTranslation.apply_patch(d, scaled_patch(p, level), tctx)
				if hits == 0:
					res["warnings"].append("%s: patch '%s' matched nothing on %s" % [pkg["source"], p.get("path", ""), d.get("id", "")])
			add_mods(mods, b.get("mods", []), level, party)
			for h in b.get("hooks", []):
				if typeof(h) != TYPE_DICTIONARY or not _when_ok(h, party):
					continue
				if passives.size() >= MAX_BUILD_HOOKS:
					res["warnings"].append("%s: hook dropped (build hook limit %d)" % [pkg["source"], MAX_BUILD_HOOKS])
					continue
				var hc: Dictionary = UpgradeTranslation.translate_hook(h, tctx).duplicate(true)
				hc.erase("when")
				hc["source"] = str(pkg["source"])
				passives.append(hc)
			for st in b.get("statuses", []):
				if typeof(st) == TYPE_DICTIONARY and _when_ok(st, party):
					var sc: Dictionary = st.duplicate(true)
					sc.erase("when")
					statuses.append(sc)
		for fr in ap.get("fight_rolls", []):
			# per-fight random modifiers (e.g. Mood Swings), deterministic per node and player
			if typeof(fr) != TYPE_DICTIONARY or not ctx.has("roll_seed"):
				continue
			var fkey := str(fr.get("key", ""))
			var frng := RunRng.stream(int(ctx["roll_seed"]), "%s/%s/%s" % [ctx.get("roll_key", "roll"), pkg["source"], fkey])
			var fv := frng.range_f(float(fr.get("min", 1.0)), float(fr.get("max", 1.0)))
			mods[fkey] = float(mods.get(fkey, CampaignCatalog.MOD_DEFAULTS.get(fkey, 1.0))) * fv
		res["sources"].append(str(pkg["source"]))
	d["passives"] = passives
	var errs := PackedStringArray()
	var c := CreatureResolver.parse(d, errs)
	if c == null or not errs.is_empty():
		# never ship a broken fighter: fall back to the unpatched kit (+ validated build hooks)
		res["warnings"].append("build patches produced an invalid creature (%s); using the base kit" % "; ".join(errs))
		var base := catalog.resolver.creature_dict(str(player.get("fighter", "")))
		var kit_passives: Array = base.get("passives", [])
		base["passives"] = passives
		var errs2 := PackedStringArray()
		c = CreatureResolver.parse(base, errs2)
		if c == null or not errs2.is_empty():
			base["passives"] = kit_passives
			errs2.clear()
			c = CreatureResolver.parse(base, errs2)
		d = base
	res["creature"] = c
	res["creature_dict"] = d
	res["mods"] = mods
	res["statuses"] = statuses
	res["max_hp"] = max_hp_of(d, mods)
	return res


## Max HP exactly as Fighter.reset_vitals computes it (campaign matches use rules health_mult 1).
static func max_hp_of(creature_dict: Dictionary, mods: Dictionary) -> float:
	var hp := float(creature_dict.get("stats", {}).get("health", 100.0))
	return maxf(1.0, hp * float(mods.get("max_health", 1.0)) + float(mods.get("max_health_add", 0.0)))


## Cheap max-HP query for UI/run logic (no CreatureDef parsing).
static func max_hp(catalog: CampaignCatalog, state: Dictionary, player: Dictionary) -> float:
	var d := catalog.resolver.creature_dict(str(player.get("fighter", "")))
	if d.is_empty():
		return 100.0
	var mods := {}
	var party := RunState.party_mode(state)
	for pkg in packages(catalog, state, player, false):
		var ap: Dictionary = pkg.get("apply", {})
		for p in ap.get("patches", []):
			if typeof(p) == TYPE_DICTIONARY and str(p.get("path", "")).begins_with("stats.health") and _when_ok(p, party):
				ContentPatch.apply(d, scaled_patch(p, int(pkg.get("level", 1))))
		add_mods(mods, ap.get("mods", []), int(pkg.get("level", 1)), party)
	return max_hp_of(d, mods)
