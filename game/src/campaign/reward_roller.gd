class_name RewardRoller
extends RefCounted
## Reward offers (CAMPAIGN.md §3, §7.1, §7.3):
##   rarity weights per source (fight/shop tables) shifted per act, guarantees (Elite: >= one
##   Prescription+, Boss: >= one Black Market + a 5% Banned slot, Treasure: >= one Black Market),
##   always distinct items, items at max stack (and owned gear) excluded, synergy: once a player
##   holds >= 2 items sharing a tag, items with that tag weigh +20% (max +40%).
## Offers are pure functions of (seed, stream key, player build) so resume/replay/co-op replicas
## see identical offers and a reroll is just the next key.


static func rarity_index(r: String) -> int:
	return CampaignCatalog.RARITIES.find(r)


static func rarity_weights(catalog: CampaignCatalog, source: String, act: int) -> Dictionary:
	var tables: Dictionary = catalog.rules.get("rarity_weights", {})
	var base: Dictionary = tables.get("shop" if source == "shop" else "fight", {}).duplicate()
	var shift: Dictionary = catalog.rules.get("act_rarity_shift", {}).get(str(act), {})
	var moved := 0.0
	for r in shift:
		base[r] = float(base.get(r, 0.0)) + float(shift[r])
		moved += float(shift[r])
	base["otc"] = maxf(0.0, float(base.get("otc", 0.0)) - moved)
	return base


## Tag counts of everything the player owns (supplements x stacks, techniques).
static func tag_counts(catalog: CampaignCatalog, player: Dictionary) -> Dictionary:
	var counts := {}
	for s in player.get("supplements", []):
		for t in catalog.supplements.get(str(s.get("id", "")), {}).get("tags", []):
			counts[t] = int(counts.get(t, 0)) + int(s.get("stacks", 1))
	for tid in player.get("techniques", []):
		for t2 in catalog.techniques.get(str(tid), {}).get("tags", []):
			counts[t2] = int(counts.get(t2, 0)) + 1
	return counts


static func synergy_bonus(catalog: CampaignCatalog, item_tags: Array, counts: Dictionary) -> float:
	var syn: Dictionary = catalog.rules.get("synergy", {})
	var b := 0.0
	for t in item_tags:
		if int(counts.get(t, 0)) >= int(syn.get("threshold", 2)):
			b += float(syn.get("per_tag", 0.2))
	return minf(b, float(syn.get("max", 0.4)))


static func stacks_of(player: Dictionary, id: String) -> int:
	for s in player.get("supplements", []):
		if str(s.get("id", "")) == id:
			return int(s.get("stacks", 1))
	return 0


## True if the player may receive another copy of this supplement.
static func can_take(catalog: CampaignCatalog, player: Dictionary, id: String) -> bool:
	var d: Dictionary = catalog.supplements.get(id, {})
	if d.is_empty():
		return false
	if bool(d.get("consumable", false)):
		return true
	var cap := 1 if bool(d.get("gear", false)) else int(d.get("stack", 1))
	return stacks_of(player, id) < cap


## Supplement offer. opts: {source, n, min_rarity, banned_chance, rarity (forced for all slots),
## exclude: [ids], act}
static func supplement_offer(catalog: CampaignCatalog, state: Dictionary, player: Dictionary, key: String, opts: Dictionary) -> Array:
	var rng := RunRng.stream(int(state.get("seed", 1)), key)
	var source := str(opts.get("source", "fight"))
	var n := int(opts.get("n", 3))
	var act := int(opts.get("act", state.get("act", 1)))
	var weights := rarity_weights(catalog, source, act)
	var counts := tag_counts(catalog, player)
	var excluded: Array = opts.get("exclude", [])
	var by_rarity := {}
	for r in CampaignCatalog.RARITIES:
		var ids := []
		for id in catalog.supplement_ids_of_rarity(r):
			if can_take(catalog, player, id) and not excluded.has(id) and not bool(catalog.supplements[id].get("not_offered", false)):
				ids.append(id)
		by_rarity[r] = ids
	var out := []
	var min_r := str(opts.get("min_rarity", ""))
	var forced := str(opts.get("rarity", ""))
	for slot in n:
		var rarity := forced
		if rarity == "":
			if slot == 0 and min_r != "":
				var ws := []
				for r2 in CampaignCatalog.RARITIES:
					ws.append(float(weights.get(r2, 0.0)) if rarity_index(r2) >= rarity_index(min_r) else 0.0)
				var wi := rng.weighted_index(ws)
				rarity = CampaignCatalog.RARITIES[wi] if wi >= 0 else min_r
			else:
				var ws2 := []
				for r3 in CampaignCatalog.RARITIES:
					ws2.append(float(weights.get(r3, 0.0)))
				rarity = CampaignCatalog.RARITIES[maxi(0, rng.weighted_index(ws2))]
			if slot == n - 1 and float(opts.get("banned_chance", 0.0)) > 0.0 and rng.chance(float(opts["banned_chance"])):
				rarity = "banned"
		var pick := _pick_of_rarity(catalog, by_rarity, rarity, out, counts, rng)
		if pick == "":
			# nothing left at that rarity: nearest rarity first (never below a guarantee)
			var floor_i := rarity_index(min_r) if slot == 0 and min_r != "" else 0
			var order := []
			var ri := rarity_index(rarity)
			for d in range(1, 4):
				for cand in [ri - d, ri + d]:
					if cand >= floor_i and cand < CampaignCatalog.RARITIES.size():
						order.append(CampaignCatalog.RARITIES[cand])
			for r4 in order:
				pick = _pick_of_rarity(catalog, by_rarity, r4, out, counts, rng)
				if pick != "":
					break
		if pick != "":
			out.append(pick)
	return out


static func _pick_of_rarity(catalog: CampaignCatalog, by_rarity: Dictionary, rarity: String, taken: Array, counts: Dictionary, rng: RunRng) -> String:
	var cands := []
	for id in by_rarity.get(rarity, []):
		if not taken.has(id):
			cands.append(id)
	if cands.is_empty():
		return ""
	var picked = rng.pick(cands, func(id): return float(catalog.supplements[id].get("weight", 1.0)) * (1.0 + synergy_bonus(catalog, catalog.supplements[id].get("tags", []), counts)))
	return str(picked) if picked != null else ""


## Up to n techniques of the player's fighter they do not own yet.
static func technique_offer(catalog: CampaignCatalog, state: Dictionary, player: Dictionary, key: String, n: int) -> Array:
	var rng := RunRng.stream(int(state.get("seed", 1)), key)
	var owned: Array = player.get("techniques", [])
	var cands := []
	for tid in catalog.technique_ids_for(str(player.get("fighter", ""))):
		if not owned.has(tid):
			cands.append(tid)
	var counts := tag_counts(catalog, player)
	return rng.pick_distinct(cands, n, func(id): return 1.0 + synergy_bonus(catalog, catalog.techniques[id].get("tags", []), counts))


## Random side effect for Dose 7 / Needles' samples (deterministic per key). Avoids repeats.
static func side_effect_roll(catalog: CampaignCatalog, state: Dictionary, player: Dictionary, key: String) -> String:
	var rng := RunRng.stream(int(state.get("seed", 1)), key)
	var have: Array = player.get("side_effects", [])
	var cands := []
	for id in CampaignCatalog._sorted_keys(catalog.side_effects):
		if not have.has(id):
			cands.append(id)
	if cands.is_empty():
		cands = CampaignCatalog._sorted_keys(catalog.side_effects)
	var p = rng.pick(cands)
	return str(p) if p != null else ""


## Scrip amount within a [lo, hi] range for a reward (deterministic per key).
static func scrip_roll(state: Dictionary, key: String, lo_hi: Array) -> int:
	var rng := RunRng.stream(int(state.get("seed", 1)), key)
	var lo := int(lo_hi[0]) if lo_hi.size() > 0 else 0
	var hi := int(lo_hi[1]) if lo_hi.size() > 1 else lo
	return rng.range_i(lo, maxi(lo, hi))
