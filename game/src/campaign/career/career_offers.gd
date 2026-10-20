class_name CareerOffers
extends RefCounted
## Weekly fight offers and generated opponents (Cage Rules makeOffers / makeOpponent, every number
## kept). Deterministic per (career seed, week, re-roll): one RunRng stream
## "career/offers/w<week>/r<roll>", so a reload, a resume or another machine shows the same offers.
## Offer (JSON-safe, stored in the save and copied into "booked" on accept):
##   {"id": "w<week>r<roll>o<i>", "org", "org_name", "tier", "title": bool, "defence": bool,
##    "opp": opponent, "weeks", "purse", "bonus", "rounds", "round_time", "arena_key", "arena",
##    "arena_variant", "arena_name", "note"}
## Opponent: {"name", "nick", "fighter", "fighter_name", "stats": {six}, "rating", "level",
##   "record": {"w", "l"}, "from", "bot_tier"}
## Offers depend only on the state passed in (popularity, champion, week, difficulty) and the
## installed roster/arenas; opponents are throwaway (Cage Rules has no persistent roster).


## The promotions offering fights at this popularity (the champion always has the belt holder).
static func orgs_open(rules: Dictionary, pop: float, champion: bool) -> Array:
	var out := []
	for o in rules.get("orgs", []):
		if pop >= float(o.get("pop", 0)):
			out.append(o)
	var belt := CareerState.belt_org(rules)
	if champion and not belt.is_empty() and not _has_org(out, str(belt.get("id", ""))):
		out.append(belt)
	return out


static func _has_org(orgs: Array, id: String) -> bool:
	for o in orgs:
		if str(o.get("id", "")) == id:
			return true
	return false


## D5 bot tier for an opponent level, shifted by the career difficulty and clamped.
static func bot_tier(rules: Dictionary, level: float, difficulty: String) -> String:
	var order: Array = rules.get("bot_tier_order", ["punching_bag", "journeyman", "contender", "headliner", "hall_of_famer"])
	var base := "headliner"
	for e in rules.get("bot_tiers", []):
		if level < float(e.get("below", 9.0)):
			base = str(e.get("tier", "headliner"))
			break
	var diff: Dictionary = (rules.get("difficulties", {}) as Dictionary).get(difficulty, {})
	var i := order.find(base)
	if i < 0:
		i = 1
	var top := order.find(str(diff.get("max_tier", "headliner")))
	if top < 0:
		top = order.size() - 1
	i = clampi(i + int(diff.get("shift", 0)), 0, maxi(0, top))
	return str(order[i])


## Cage Rules danger tag from opponent rating - your rating.
static func danger(rules: Dictionary, diff: int) -> String:
	for e in rules.get("danger", []):
		if diff <= int(e.get("max", 0)):
			return str(e.get("tag", ""))
	return str(rules.get("danger_else", "LONG SHOT"))


## Arena keys a career bout can be booked in: campaign arena keys whose arena is installed.
static func arena_keys(catalog: CampaignCatalog, rules: Dictionary) -> Array:
	var out := []
	for k in rules.get("arenas", []):
		if _arena_installed(catalog, str(k)):
			out.append(str(k))
	return out


static func _arena_installed(catalog: CampaignCatalog, key: String) -> bool:
	if catalog == null or not (catalog.rules.get("arenas", {}) as Dictionary).has(key):
		return false
	var a := catalog.arena_for(key)
	if catalog.content == null:
		return true
	return not catalog.content.get_entry("arenas", str(a[0])).is_empty()


## {key, id, variant, name} of the arena for a new offer ({} when nothing is installed).
static func pick_arena(catalog: CampaignCatalog, rules: Dictionary, rng: RunRng, title: bool) -> Dictionary:
	var keys := arena_keys(catalog, rules)
	var tk := str(rules.get("title_arena", ""))
	var roll := rng.randf()
	var key := ""
	if title and _arena_installed(catalog, tk):
		key = tk
	elif not keys.is_empty():
		key = str(keys[mini(keys.size() - 1, int(roll * keys.size()))])
	if key == "":
		var fb := str(catalog.rules.get("fallback_arena", "the_gullet")) if catalog else "the_gullet"
		return {"key": "", "id": fb, "variant": "", "name": "The Gullet"}
	var a := catalog.arena_for(key)
	var info: Dictionary = (catalog.rules.get("arenas", {}) as Dictionary).get(key, {})
	return {"key": key, "id": str(a[0]), "variant": str(a[1]), "name": str(info.get("name", key))}


## The fighters opponents are drawn from (the campaign roster that resolves).
static func opponent_pool(catalog: CampaignCatalog) -> Array:
	return catalog.available_fighters() if catalog else []


static func _pick(rng: RunRng, items: Array):
	if items.is_empty():
		return null
	return items[mini(items.size() - 1, int(rng.randf() * items.size()))]


## Cage Rules makeOpponent: level from the org band (title holders 0.90-0.96), stats shaped by
## the creature, a record, a ring name, a home town and the D5 bot tier.
static func make_opponent(catalog: CampaignCatalog, rules: Dictionary, rng: RunRng, o: Dictionary, st: Dictionary, title: bool) -> Dictionary:
	var op: Dictionary = rules.get("opponents", {})
	var pool := opponent_pool(catalog)
	var fighter := str(_pick(rng, pool)) if not pool.is_empty() else str(st.get("fighter", "f_stoke"))
	var sh := CareerState.shape(rules, fighter)
	var lvl := 0.0
	if title:
		var tl: Array = op.get("title_level", [0.9, 0.96])
		lvl = float(tl[0]) + rng.randf() * (float(tl[1]) - float(tl[0]))
	else:
		var band: Array = o.get("level", [0.3, 0.4])
		lvl = lerpf(float(band[0]), float(band[1]), rng.randf())
	var stats := {}
	var center := float(op.get("shape_center", 0.66))
	var scale := float(op.get("shape_scale", 0.55))
	var noise := float(op.get("noise", 0.08))
	for k in CareerDefaults.STATS:
		var v := lvl + (float(sh[k]) - center) * scale + (rng.randf() - 0.5) * noise
		stats[k] = snappedf(clampf(v, float(op.get("stat_min", 0.15)), float(op.get("stat_max", 0.99))), 0.01)
	var fights := int(round(float(op.get("fights_base", 2.0)) + lvl * float(op.get("fights_per_level", 24.0)) + rng.randf() * float(op.get("fights_rand", 6.0))))
	var share := clampf(float(op.get("win_base", 0.45)) + lvl * float(op.get("win_per_level", 0.45)) + (rng.randf() - 0.5) * float(op.get("win_noise", 0.2)),
		float(op.get("win_min", 0.3)), float(op.get("win_max", 0.95)))
	var wins := int(round(fights * share))
	var names: Dictionary = rules.get("names", {})
	var first := str(_pick(rng, names.get("first", ["Rivet"])))
	var last := str(_pick(rng, names.get("last", ["Gravelgut"])))
	var nick := ""
	if rng.randf() < float(op.get("nick_chance", 0.7)):
		nick = str(_pick(rng, names.get("nicks", [""])))
	var town := str(_pick(rng, names.get("towns", ["the docks"])))
	return {"name": "%s %s" % [first, last], "nick": nick, "fighter": fighter,
		"fighter_name": fighter_name(catalog, fighter), "stats": stats, "rating": CareerState.rating(stats),
		"level": snappedf(lvl, 0.0001), "record": {"w": wins, "l": fights - wins}, "from": town,
		"bot_tier": bot_tier(rules, lvl, str(st.get("difficulty", "normal")))}


static func fighter_name(catalog: CampaignCatalog, fighter: String) -> String:
	if catalog != null:
		var d := catalog.resolver.raw_entry(fighter)
		if not d.is_empty():
			return str(d.get("name", fighter))
		var info := catalog.fighter_info(fighter)
		if info.has("name"):
			return str(info["name"]).capitalize()
	return fighter.trim_prefix("f_").capitalize()


## Cage Rules makeOffers for the state's week and re-roll counter.
static func make_offers(catalog: CampaignCatalog, rules: Dictionary, st: Dictionary) -> Array:
	var week := int(st.get("week", 1))
	var roll := int(st.get("offer_roll", 0))
	var rng := RunRng.stream(int(st.get("seed", 1)), "career/offers/w%d/r%d" % [week, roll])
	var pop := float(st.get("pop", 0.0))
	var champion := bool(st.get("champion", false))
	var of: Dictionary = rules.get("offers", {})
	var open := orgs_open(rules, pop, champion)
	if open.is_empty():
		return []
	var top := 0
	for o in open:
		top = maxi(top, int(o.get("tier", 0)))
	# only your top tier and the one below it make offers; offer 0 always comes from the top tier
	var pool := []
	for o2 in open:
		if int(o2.get("tier", 0)) >= top - 1:
			pool.append(o2)
	var n := int(of.get("min", 2)) + (1 if rng.randf() < float(of.get("extra_chance", 0.6)) else 0)
	var belt := CareerState.belt_org(rules)
	var title_shot := pop >= float(rules.get("title_pop", 92.0)) and not champion
	var offers := []
	for i in n:
		var org := {}
		var used := []
		for x in offers:
			used.append(str(x["org"]))
		var title := false
		if i == 0:
			var tops := []
			for o3 in pool:
				if int(o3.get("tier", 0)) == top:
					tops.append(o3)
			org = _pick(rng, tops)
			# the belt holder's first offer is the title fight (shot at title_pop, or a defence)
			if (title_shot or champion) and not belt.is_empty() and _has_org(tops, str(belt.get("id", ""))):
				org = belt
				title = true
		else:
			var ws := []
			for o4 in pool:
				var w := 1.0 + (float(of.get("top_tier_weight", 1.5)) if int(o4.get("tier", 0)) == top else 0.0) \
					+ maxf(0.0, (pop - float(o4.get("pop", 0))) / float(of.get("pop_weight_div", 40.0)))
				if used.has(str(o4.get("id", ""))):
					w *= float(of.get("reuse_weight", 0.15))
				ws.append(w)
			var wi := rng.weighted_index(ws)
			org = pool[wi] if wi >= 0 else pool[0]
		var opp := make_opponent(catalog, rules, rng, org, st, title)
		var weeks := int(of.get("title_weeks", 10)) if title else int(of.get("weeks_min", 4)) + mini(
			int(of.get("weeks_max", 10)) - int(of.get("weeks_min", 4)), int(rng.randf() * (int(of.get("weeks_max", 10)) - int(of.get("weeks_min", 4)) + 1)))
		var pop_in := clampf((pop - float(org.get("pop", 0))) / float(of.get("pop_in_div", 30.0)), 0.0, 1.0)
		var band: Array = org.get("purse", [500, 1000])
		var w_in := pop_in * float(of.get("pop_in_weight", 0.7)) + rng.randf() * (1.0 - float(of.get("pop_in_weight", 0.7)))
		var purse_f := lerpf(float(band[0]), float(band[1]), w_in) * (1.0 + (int(of.get("weeks_max", 10)) - weeks) * float(of.get("short_notice_per_week", 0.03)))
		if title:
			purse_f *= float(of.get("title_purse_mult", 2.5))
		var step := maxi(1, int(of.get("purse_round", 50)))
		var purse := int(round(purse_f / step)) * step
		var tier := int(org.get("tier", 0))
		var bonus_frac := float(of.get("top_bonus_frac", 1.0)) if tier >= 3 else float(of.get("bonus_frac", 0.6))
		var bonus := int(round(purse * bonus_frac / step)) * step
		var arena := pick_arena(catalog, rules, rng, title)
		var note := ""
		if title:
			note = "Title defence. Lose and the belt goes with it." if champion else "Title fight. Five rounds for the belt."
		elif tier >= 3:
			note = "Main card. The whole world is watching."
		elif weeks <= int(of.get("short_notice_weeks", 5)):
			note = "Short notice: less time to prepare, a little more money."
		elif weeks >= int(of.get("long_camp_weeks", 9)):
			note = "A long camp: plenty of weeks to train."
		offers.append({"id": "w%dr%do%d" % [week, roll, i], "org": str(org.get("id", "")), "org_name": str(org.get("name", "")),
			"tier": tier, "title": title, "defence": title and champion, "opp": opp, "weeks": weeks, "purse": purse,
			"bonus": bonus, "rounds": int(rules.get("title_rounds", 5)) if title else int(rules.get("rounds", 3)),
			"round_time": float(rules.get("round_time", 99.0)), "arena_key": str(arena.get("key", "")),
			"arena": str(arena.get("id", "")), "arena_variant": str(arena.get("variant", "")),
			"arena_name": str(arena.get("name", "")), "note": note})
	return offers
