class_name CampaignCatalog
extends RefCounted
## Typed, indexed, validated view of all campaign content loaded by Content (core + mods):
##   supplements/   "supplement" and "side_effect" entries
##   techniques/    "technique" and "build" (fighter build directions) entries
##   meta_upgrades/ "meta_upgrade" entries (Fight Camp, tagged meta_bonus)
##   events/        "event" entries
##   encounters/    "encounter", "minion_loadout" and "act" entries
##   boss_fights/   "boss_fight" entries (phases, attacks, arena interplay; reference a boss creature)
##   ladder/        "dose", "difficulty", "bot_tier" and the single "campaign_rules" entry
## Entries are plain Dictionaries (the JSON as authored); this class only indexes and checks them.
## `shared()` is a cache of the catalog for the live Content autoload (rebuilt on Content.reloaded).

const RARITIES := ["otc", "prescription", "black_market", "banned"]
const RARITY_NAMES := {"otc": "Over-the-Counter", "prescription": "Prescription", "black_market": "Black Market", "banned": "Banned Substance"}
const NODE_TYPES := ["fight", "elite", "event", "shop", "rest", "mystery", "treasure", "boss"]
const VARIANTS := ["off_the_street", "fight_camp"]
const MOVE_SLOTS := ["l1", "l2", "l3", "heavy", "heavy_charged", "finisher", "dash_attack", "grab", "pummel", "taunt"]
const ABILITY_SLOTS := ["ability1", "ability2", "juice"]

## Fighter.mods keys a build may change, with their identity value (mul keys 1, add keys 0).
const MOD_DEFAULTS := {
	"damage": 1.0, "defense": 1.0, "speed": 1.0, "stamina_regen": 1.0, "knockback_taken": 1.0,
	"knockback_dealt": 1.0, "cooldown": 1.0, "hype_gain": 1.0, "poise": 1.0, "heal": 1.0,
	"move_speed": 1.0, "max_health": 1.0, "max_health_add": 0.0, "stamina_add": 0.0, "poise_add": 0.0,
	"start_hype": 0.0, "stamina_cost": 1.0, "dodge_cost": 1.0, "dodge_distance": 1.0,
	"parry_window_add": 0.0, "throw_distance": 1.0, "splat_damage_add": 0.0, "splat_poise_add": 0.0,
	"getup_speed": 1.0, "held_time_mult": 1.0, "buildup_taken": 1.0, "reach_radius": 1.0,
	"vmin_mult": 1.0, "charge_distance": 1.0, "charge_speed": 1.0, "charge_steer": 1.0,
	"hover_duration": 1.0, "zone_size": 1.0, "zone_duration_add": 0.0, "guard_absorb_mult": 1.0,
	"wakeup_invuln_add": 0.0, "dodge_iframes_add": 0.0, "grab_hold_add": 0.0, "grab_escape_add": 0.0,
	"status_duration_taken": 1.0,
	# read by CampaignMatchMode (campaign-only fighter properties)
	"prevent_knockdowns": 0.0, "revive_speed": 1.0, "assist_rate": 1.0,
}
## Run-level (campaign economy / rules) keys and their identity value.
const RUN_DEFAULTS := {
	"scrip_mult": 1.0, "clout_mult": 1.0, "shop_price_mult": 1.0, "shop_extra_items": 0.0,
	"shop_extra_black_market": 0.0, "shop_always_black_market": 0.0, "rest_heal_add": 0.0,
	"rest_heal_mult": 1.0, "elite_extra_options": 0.0, "post_fight_heal": 0.0, "boss_heal_add": 0.0,
	"blood_money_ko": 0.0, "blood_money_knockdown": 0.0, "start_scrip_add": 0.0, "free_rerolls": 0.0,
	"reveal_rows_add": 0.0, "technique_pick_row1": 0.0, "side_effect_preview": 0.0,
	"start_antidotes": 0.0, "boss_tell_lead": 0.0, "enemy_hp_mult": 1.0, "enemy_damage_mult": 1.0,
	"player_max_hp_mult": 1.0, "normal_fight_extra_minions": 0.0, "enemy_start_hype": 0.0,
	"enemy_extra_techniques": 0.0, "supplement_side_effects": 0.0, "boss_phase2_at": 0.5,
	"hazards_always_on": 0.0, "bot_tier": "", "act3_elite": "", "rest_heal_override": 0.0,
	# run start (Fight Camp: Sparring Partner, Film Study; docs/CAMPAIGN_SYSTEMS.md "Moves in runs")
	"start_learned_moves": 0.0, "start_drilled_moves": 0.0,
}
## Event outcome effect ops (EventRunner) — validated here.
const EVENT_OPS := ["hp", "hp_pct", "max_hp", "scrip", "clout", "hype_carry", "hype_carry_set",
	"grant_supplement", "side_effect", "remove_supplement", "remove_side_effects", "technique_pick",
	"reward_pick", "run_mods", "run_patches", "run_hooks", "next_fight", "bet", "boss_mod", "fight",
	"cosmetic", "coupon", "flag", "nothing", "consumable", "quip", "stat", "learn_move"]
const REQUIRE_KEYS := ["act", "fighters", "element", "weight_class", "scrip", "has_banned", "no_banned",
	"has_supplements", "roll_matches", "variant", "coop", "party_element"]

static var _shared: CampaignCatalog = null
static var _shared_hooked := false

var content                       ## Content autoload or test double (tables + get_entry + ids)
var resolver: CreatureResolver
var supplements := {}             ## id -> entry ("supplement")
var side_effects := {}            ## id -> entry ("side_effect")
var techniques := {}              ## id -> entry
var techniques_by_fighter := {}   ## fighter id -> [technique ids] (sorted)
var builds := {}                  ## id -> entry
var builds_by_fighter := {}       ## fighter id -> [build ids]
var meta := {}                    ## id -> entry
var events := {}                  ## id -> entry
var encounters := {}              ## id -> entry
var loadouts := {}                ## id -> entry
var acts := {}                    ## act number (int) -> entry
var boss_fights := {}             ## id -> entry
var doses := {}                   ## level (int) -> entry
var difficulties := {}            ## id -> entry
var bot_tiers := {}               ## id -> entry
var rules := {}                   ## campaign rules (defaults merged with content)
var errors := PackedStringArray() ## structural/semantic content errors (entries are still indexed)
var warnings := PackedStringArray()  ## references to content owned by others that is not present
var moves_cache := {}             ## RunMoves: parsed move pools and upgrade analyses (cleared on rebuild)


func _init(content_src = null, stand_in := "") -> void:
	content = content_src
	resolver = CreatureResolver.new(content_src)
	resolver.stand_in = stand_in
	rebuild()


## Catalog for the live Content autoload, rebuilt whenever Content reloads (mods toggled).
static func shared() -> CampaignCatalog:
	var tree := Engine.get_main_loop() as SceneTree
	var c = tree.root.get_node_or_null("Content") if tree else null
	if _shared == null or _shared.content != c:
		_shared = CampaignCatalog.new(c)
		if c and not _shared_hooked:
			_shared_hooked = true
			c.reloaded.connect(_invalidate_shared)
	return _shared


static func _invalidate_shared() -> void:
	_shared = null


func _table(kind: String) -> Dictionary:
	if content == null:
		return {}
	var t = content.tables.get(kind, {})
	return t if typeof(t) == TYPE_DICTIONARY else {}


static func _sorted_keys(d: Dictionary) -> Array:
	var ks: Array = d.keys()
	ks.sort()
	return ks


## Numeric membership for lists loaded from JSON (JSON numbers are floats; Array.has(3) does not
## match 3.0).
static func has_num(arr, v) -> bool:
	if typeof(arr) != TYPE_ARRAY:
		return false
	for x in arr:
		if (typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT) and float(x) == float(v):
			return true
	return false


func rebuild() -> void:
	for d in [supplements, side_effects, techniques, techniques_by_fighter, builds, builds_by_fighter, meta, events,
			encounters, loadouts, acts, boss_fights, doses, difficulties, bot_tiers]:
		(d as Dictionary).clear()
	errors.clear()
	warnings.clear()
	moves_cache.clear()
	rules = CampaignDefaults.rules().duplicate(true)
	var sup_t := _table("supplements")
	for id in _sorted_keys(sup_t):
		var e: Dictionary = sup_t[id]
		if str(e.get("type", "supplement")) == "side_effect":
			side_effects[id] = e
		else:
			supplements[id] = e
	var tech_t := _table("techniques")
	for id in _sorted_keys(tech_t):
		var e2: Dictionary = tech_t[id]
		var fid := str(e2.get("fighter", ""))
		if str(e2.get("type", "technique")) == "build":
			builds[id] = e2
			if not builds_by_fighter.has(fid):
				builds_by_fighter[fid] = []
			builds_by_fighter[fid].append(id)
		else:
			techniques[id] = e2
			if not techniques_by_fighter.has(fid):
				techniques_by_fighter[fid] = []
			techniques_by_fighter[fid].append(id)
	var meta_t := _table("meta_upgrades")
	for id in _sorted_keys(meta_t):
		meta[id] = meta_t[id]
	var ev_t := _table("events")
	for id in _sorted_keys(ev_t):
		events[id] = ev_t[id]
	var enc_t := _table("encounters")
	for id in _sorted_keys(enc_t):
		var e3: Dictionary = enc_t[id]
		match str(e3.get("type", "encounter")):
			"minion_loadout":
				loadouts[id] = e3
			"act":
				acts[int(e3.get("act", 0))] = e3
			_:
				encounters[id] = e3
	var bf_t := _table("boss_fights")
	for id in _sorted_keys(bf_t):
		boss_fights[id] = bf_t[id]
	var lad_t := _table("ladder")
	for id in _sorted_keys(lad_t):
		var e4: Dictionary = lad_t[id]
		match str(e4.get("type", "")):
			"dose":
				doses[int(e4.get("level", 0))] = e4
			"difficulty":
				difficulties[id] = e4
			"bot_tier":
				bot_tiers[id] = e4
			"campaign_rules":
				_merge_rules(rules, e4)
	resolver.loadouts = loadouts
	resolver.roster_info = rules.get("roster", {})
	var ss := {}
	for bid in boss_fights:
		var bf: Dictionary = boss_fights[bid]
		ss[str(bf.get("creature", ""))] = bf.get("standin_stats", {})
	resolver.standin_stats = ss
	validate()


static func _merge_rules(into: Dictionary, src: Dictionary) -> void:
	for k in src:
		if str(k).begins_with("_") or k in ["id", "type"]:
			continue
		if typeof(into.get(k)) == TYPE_DICTIONARY and typeof(src[k]) == TYPE_DICTIONARY:
			_merge_rules(into[k], src[k])
		else:
			into[k] = src[k].duplicate(true) if typeof(src[k]) in [TYPE_DICTIONARY, TYPE_ARRAY] else src[k]


# =============================================================================================
# Queries
# =============================================================================================

## Any owned-item definition (supplement, side effect or technique) by id.
func item(id: String) -> Dictionary:
	if supplements.has(id):
		return supplements[id]
	if side_effects.has(id):
		return side_effects[id]
	if techniques.has(id):
		return techniques[id]
	return {}


func item_name(id: String) -> String:
	var it := item(id)
	return str(it.get("name", id)) if not it.is_empty() else id


func roster() -> Array:
	var r: Dictionary = rules.get("roster", {})
	return _sorted_keys(r)


## Roster fighters that can actually be resolved (real content or stand-ins).
func available_fighters() -> Array:
	var out := []
	for fid in roster():
		if resolver.resolvable(fid):
			out.append(fid)
	return out


func fighter_info(fid: String) -> Dictionary:
	return rules.get("roster", {}).get(fid, {})


func fighter_element(fid: String) -> String:
	var info := fighter_info(fid)
	if info.has("element"):
		return str(info["element"])
	var d := resolver.raw_entry(fid)
	return str(d.get("element", ""))


func weight_class(fid: String) -> String:
	return str(fighter_info(fid).get("class", "scrapper"))


func difficulty(id: String) -> Dictionary:
	return difficulties.get(id, difficulties.get("amateur", {}))


func difficulty_ids() -> Array:
	var ids := _sorted_keys(difficulties)
	ids.sort_custom(func(a, b): return int(difficulties[a].get("order", 0)) < int(difficulties[b].get("order", 0)))
	return ids


func dose(level: int) -> Dictionary:
	return doses.get(level, {})


func max_dose() -> int:
	var m := 0
	for l in doses:
		m = maxi(m, int(l))
	return m


func encounters_for(act: int, tier: String) -> Array:
	var out := []
	for id in _sorted_keys(encounters):
		var e: Dictionary = encounters[id]
		if int(e.get("act", 0)) == act and str(e.get("tier", "normal")) == tier:
			out.append(id)
	return out


func technique_ids_for(fid: String) -> Array:
	return techniques_by_fighter.get(fid, []).duplicate()


func build_ids_for(fid: String) -> Array:
	return builds_by_fighter.get(fid, []).duplicate()


func supplement_ids_of_rarity(rarity: String) -> Array:
	var out := []
	for id in _sorted_keys(supplements):
		if str(supplements[id].get("rarity", "otc")) == rarity:
			out.append(id)
	return out


func meta_ids_for_station(station: String) -> Array:
	var out := []
	for id in _sorted_keys(meta):
		if station == "" or str(meta[id].get("station", "")) == station:
			out.append(id)
	return out


func price_of(id: String) -> int:
	var e := item(id)
	if e.has("price"):
		return int(e["price"])
	var prices: Dictionary = rules.get("shop", {}).get("prices", {})
	if techniques.has(id):
		return int(prices.get("technique", 90))
	return int(prices.get(str(e.get("rarity", "otc")), 40))


func encounter_valid(id: String) -> bool:
	return encounters.has(id) and not bool(encounters[id].get("_invalid", false))


func event_valid(id: String) -> bool:
	return events.has(id) and not bool(events[id].get("_invalid", false))


## Arena id for a logical arena key ("drydock", "gullet_night"...): the first id that exists in
## Content, else the rules' fallback arena. Returns [arena_id, variant].
func arena_for(key: String) -> Array:
	var a: Dictionary = rules.get("arenas", {}).get(key, {})
	for aid in a.get("ids", []):
		if content and not content.get_entry("arenas", str(aid)).is_empty():
			return [str(aid), str(a.get("variant", ""))]
	return [str(rules.get("fallback_arena", "the_gullet")), str(a.get("variant", key))]


# =============================================================================================
# Validation (structural + cross references). Called by CampaignValidator at Content load.
# =============================================================================================

func validate() -> PackedStringArray:
	errors.clear()
	warnings.clear()
	for id in supplements:
		_check_item(id, supplements[id], true)
	for id in side_effects:
		_check_item(id, side_effects[id], false)
	for id in techniques:
		var t: Dictionary = techniques[id]
		if str(t.get("fighter", "")) == "" or not rules.get("roster", {}).has(str(t.get("fighter", ""))):
			_err(id, "technique fighter '%s' is not in the campaign roster" % t.get("fighter", ""))
		_check_apply(id, t.get("apply", {}))
	for id in builds:
		var b: Dictionary = builds[id]
		for tid in b.get("techniques", []):
			if not techniques.has(str(tid)) or str(techniques[str(tid)].get("fighter", "")) != str(b.get("fighter", "")):
				_err(id, "build references technique '%s' of another fighter or unknown" % tid)
	for id in meta:
		var m: Dictionary = meta[id]
		if not bool(m.get("meta_bonus", false)):
			_err(id, "meta upgrades must be tagged \"meta_bonus\": true")
		var costs: Array = m.get("costs", [])
		if costs.is_empty():
			_err(id, "meta upgrade without costs")
		for c in costs:
			if int(c) <= 0:
				_err(id, "meta upgrade cost must be positive")
		_check_apply(id, m.get("per_level", {}))
	for id in events:
		_check_event(id, events[id])
	for id in loadouts:
		var lo: Dictionary = loadouts[id]
		for p in lo.get("patches", []):
			var pe := ContentPatch.validate(p)
			if pe != "":
				_err(id, pe)
		if not resolver.exists(str(lo.get("base", ""))) and resolver.raw_entry(id).is_empty():
			_warn(id, "minion base %s" % _pending_text(str(lo.get("base", ""))))
	for id in encounters:
		_check_encounter(id, encounters[id])
	for id in boss_fights:
		_check_boss_fight(id, boss_fights[id])
	for l in doses:
		var d: Dictionary = doses[l]
		_check_run_entries(str(d.get("id", l)), d.get("run", []))
	for did in difficulties:
		var df: Dictionary = difficulties[did]
		if not bot_tiers.has(str(df.get("bot_tier", ""))):
			_err(did, "difficulty bot_tier '%s' is not defined" % df.get("bot_tier", ""))
	for a in [1, 2, 3]:
		if not acts.has(a):
			_err("act_%d" % a, "missing act definition")
		elif not encounters.has(str(acts[a].get("boss", ""))):
			_err("act_%d" % a, "act boss encounter '%s' missing" % acts[a].get("boss", ""))
	for fid in rules.get("roster", {}):
		if not resolver.exists(str(fid)):
			_warn(str(fid), "roster fighter %s" % _pending_text(str(fid)))
	return errors


## "not installed" vs "installed but not usable yet (first parse problem)".
func _pending_text(cid: String) -> String:
	var probs := resolver.problems(cid)
	if resolver.raw_entry(cid).is_empty() or probs.is_empty():
		return "creature '%s' not installed yet (creature content pending)" % cid
	return "creature '%s' is installed but not usable yet: %s" % [cid, probs[0]]


func _err(id, msg: String) -> void:
	errors.append("campaign %s: %s" % [str(id), msg])


func _warn(id, msg: String) -> void:
	warnings.append("campaign %s: %s" % [str(id), msg])


func _check_item(id: String, e: Dictionary, is_supplement: bool) -> void:
	if is_supplement and not RARITIES.has(str(e.get("rarity", ""))):
		_err(id, "unknown rarity '%s'" % e.get("rarity", ""))
	if int(e.get("stack", 1)) < 1 and not bool(e.get("consumable", false)):
		_err(id, "stack must be >= 1")
	_check_apply(id, e.get("apply", {}))
	for op in e.get("on_pick", []):
		_check_event_effect(id, op)


func _check_apply(id: String, ap) -> void:
	if typeof(ap) != TYPE_DICTIONARY:
		_err(id, "apply/per_level must be an object")
		return
	for p in ap.get("patches", []):
		var pe := ContentPatch.validate(p)
		if pe != "":
			_err(id, pe)
	for m in ap.get("mods", []):
		_check_mod_entry(id, m, MOD_DEFAULTS)
	_check_run_entries(id, ap.get("run", []))
	for h in ap.get("hooks", []):
		_check_hook(id, h)
	for st in ap.get("statuses", []):
		if typeof(st) != TYPE_DICTIONARY or str(st.get("id", "")) == "":
			_err(id, "start-of-fight status needs an id")
	for fr in ap.get("fight_rolls", []):
		if typeof(fr) != TYPE_DICTIONARY or not MOD_DEFAULTS.has(str(fr.get("key", ""))):
			_err(id, "fight roll needs a known modifier key")
		elif float(fr.get("min", 1.0)) > float(fr.get("max", 1.0)):
			_err(id, "fight roll min > max")
	# Movesets-only effects (UpgradeTranslation): an apply block of its own, one level deep
	if ap.has("movesets"):
		if typeof(ap["movesets"]) != TYPE_DICTIONARY or (ap["movesets"] as Dictionary).has("movesets"):
			_err(id, "'movesets' must be an apply block (without its own 'movesets')")
		else:
			_check_apply(id, ap["movesets"])


func _check_mod_entry(id: String, m, allowed: Dictionary) -> void:
	if typeof(m) != TYPE_DICTIONARY:
		_err(id, "mod entry is not an object")
		return
	var key := str(m.get("key", ""))
	if not allowed.has(key):
		_err(id, "unknown modifier key '%s'" % key)
	var n := 0
	for op in ["mul", "add", "set"]:
		if m.has(op):
			n += 1
	if n != 1:
		_err(id, "modifier '%s' needs exactly one of mul/add/set" % key)
	if m.has("when") and not str(m["when"]) in ["always", "solo", "coop", "tag"]:
		_err(id, "modifier '%s': unknown when '%s'" % [key, m["when"]])


func _check_run_entries(id: String, entries) -> void:
	if typeof(entries) != TYPE_ARRAY:
		_err(id, "run modifiers must be an array")
		return
	for r in entries:
		_check_mod_entry(id, r, RUN_DEFAULTS)


func _check_hook(id: String, h) -> void:
	if typeof(h) != TYPE_DICTIONARY:
		_err(id, "hook is not an object")
		return
	for e in Hooks.validate(h):
		_err(id, e)
	for a in h.get("do", []):
		if typeof(a) == TYPE_DICTIONARY and typeof(a.get("status")) == TYPE_DICTIONARY:
			for nh in a["status"].get("hooks", []):
				_check_hook(id, nh)


func _check_requires(id: String, req) -> void:
	if typeof(req) != TYPE_DICTIONARY:
		_err(id, "requires must be an object")
		return
	for k in req:
		if not REQUIRE_KEYS.has(str(k)):
			_err(id, "unknown requirement '%s'" % k)


func _check_event(id: String, e: Dictionary) -> void:
	var choices: Array = e.get("choices", [])
	if choices.size() < 1:
		_err(id, "event needs at least one choice")
	_check_requires(id, e.get("requires", {}))
	var seen := {}
	for c in choices:
		if typeof(c) != TYPE_DICTIONARY:
			_err(id, "choice is not an object")
			continue
		var cid := str(c.get("id", ""))
		if cid == "" or seen.has(cid):
			_err(id, "choice ids must be unique and non-empty")
		if cid.begins_with("_"):
			_err(id, "choice id '%s': ids starting with '_' are reserved (EventRunner.PASS)" % cid)
		seen[cid] = true
		_check_requires("%s.%s" % [id, cid], c.get("requires", {}))
		var outs: Array = c.get("outcomes", [])
		if outs.is_empty():
			_err(id, "choice '%s' has no outcomes" % cid)
		for o in outs:
			for eff in o.get("effects", []):
				_check_event_effect("%s.%s" % [id, cid], eff)


func _check_event_effect(id: String, eff) -> void:
	if typeof(eff) != TYPE_DICTIONARY:
		_err(id, "outcome effect is not an object")
		return
	var op := str(eff.get("op", ""))
	if not EVENT_OPS.has(op):
		_err(id, "unknown outcome op '%s'" % op)
		return
	match op:
		"grant_supplement":
			if eff.has("id") and not supplements.has(str(eff["id"])):
				_err(id, "grants unknown supplement '%s'" % eff["id"])
			if eff.has("rarity") and not RARITIES.has(str(eff["rarity"])):
				_err(id, "unknown rarity '%s'" % eff["rarity"])
		"consumable":
			if not supplements.has(str(eff.get("id", ""))):
				_err(id, "unknown consumable '%s'" % eff.get("id", ""))
		"run_mods":
			for m in eff.get("mods", []):
				_check_mod_entry(id, m, MOD_DEFAULTS)
		"run_patches":
			for p in eff.get("patches", []):
				var pe := ContentPatch.validate(p)
				if pe != "":
					_err(id, pe)
			if eff.has("movesets"):
				_check_apply(id, eff["movesets"])
		"learn_move":
			if eff.has("options") and int(eff["options"]) < 1:
				_err(id, "learn_move offers at least one move")
			if eff.has("move") and str(eff["move"]) == "":
				_err(id, "learn_move names a pool move id")
		"run_hooks":
			for h in eff.get("hooks", []):
				_check_hook(id, h)
		"next_fight":
			_check_apply(id, eff.get("apply", {}))
		"fight":
			var enc := str(eff.get("encounter", ""))
			if not encounters.has(enc):
				_err(id, "event fight references unknown encounter '%s'" % enc)
			for sub in eff.get("on_win", []) + eff.get("on_loss", []):
				_check_event_effect(id, sub)
		"bet":
			for sub in eff.get("win", []) + eff.get("lose", []):
				_check_event_effect(id, sub)
		"boss_mod":
			var found := false
			for bid in boss_fights:
				if str(boss_fights[bid].get("creature", "")) == str(eff.get("boss", "")) or str(bid) == str(eff.get("boss", "")):
					found = true
			if not found:
				_err(id, "boss_mod references unknown boss '%s'" % eff.get("boss", ""))


func _check_encounter(id: String, e: Dictionary) -> void:
	var tier := str(e.get("tier", "normal"))
	if not tier in ["normal", "elite", "boss", "event"]:
		_err(id, "unknown tier '%s'" % tier)
	var act := int(e.get("act", 0))
	if tier != "event" and (act < 1 or act > 3):
		_err(id, "act must be 1..3")
	if not rules.get("arenas", {}).has(str(e.get("arena", ""))):
		_err(id, "unknown arena key '%s'" % e.get("arena", ""))
	var enemies: Array = e.get("enemies", [])
	if enemies.is_empty():
		_err(id, "encounter without enemies")
	var unresolved := false
	for en in enemies:
		if typeof(en) != TYPE_DICTIONARY:
			_err(id, "enemy entry is not an object")
			continue
		var count := int(en.get("count", 1))
		if count < 1 or count > 12:
			_err(id, "enemy count must be 1..12")
		if en.has("minion"):
			var mid := str(en["minion"])
			if not loadouts.has(mid) and resolver.raw_entry(mid).is_empty():
				_err(id, "unknown minion loadout '%s'" % mid)
			elif not resolver.exists(mid):
				unresolved = true
		elif en.has("boss_fight"):
			var bfid := str(en["boss_fight"])
			if not boss_fights.has(bfid):
				_err(id, "unknown boss fight '%s'" % bfid)
			elif not resolver.exists(str(boss_fights[bfid].get("creature", ""))):
				unresolved = true
		elif en.has("fighter"):
			var f := str(en["fighter"])
			if f in ["random", "mirror"]:
				for pf in en.get("pool", []):
					if not rules.get("roster", {}).has(str(pf)):
						_err(id, "fighter pool entry '%s' is not in the roster" % pf)
			elif not rules.get("roster", {}).has(f):
				_err(id, "fighter '%s' is not in the roster" % f)
			elif not resolver.exists(f):
				unresolved = true
			for tid in en.get("techniques_list", []):
				if not techniques.has(str(tid)):
					_err(id, "unknown technique '%s'" % tid)
			if en.has("build") and not builds.has(str(en["build"])):
				_err(id, "unknown build '%s'" % en["build"])
		else:
			_err(id, "enemy entry needs minion, fighter or boss_fight")
	var sp: Dictionary = e.get("special", {})
	for hz in sp.get("hazards", []):
		if typeof(hz) != TYPE_DICTIONARY or not rules.get("hazards", {}).has(str(hz.get("kind", ""))):
			_err(id, "unknown hazard '%s'" % (hz.get("kind", "") if typeof(hz) == TYPE_DICTIONARY else hz))
	if unresolved:
		_warn(id, "uses creatures that are not installed yet (encounter excluded unless stand-ins are enabled)")


func _check_boss_fight(id: String, b: Dictionary) -> void:
	if str(b.get("creature", "")) == "":
		_err(id, "boss fight needs a creature id")
	elif not resolver.exists(str(b["creature"])):
		_warn(id, "boss %s" % _pending_text(str(b["creature"])))
	var phases: Array = b.get("phases", [])
	if phases.size() < 1:
		_err(id, "boss fight needs phases")
	for ph in phases:
		for atk in ph.get("attacks", []):
			if str(atk.get("id", "")) == "" or float(atk.get("telegraph", 0.0)) < 0.5:
				_err(id, "boss attack '%s' needs an id and a telegraph >= 0.5 s" % atk.get("id", "?"))
			for act in atk.get("actions", []):
				var t := str(act.get("type", ""))
				if not EffectsSystem.TYPES.has(t) and not t in BossMode.PATTERN_ACTIONS:
					_err(id, "boss attack '%s': unknown action '%s'" % [atk.get("id", "?"), t])
		for hz in ph.get("hazards", []):
			if not rules.get("hazards", {}).has(str(hz.get("kind", ""))):
				_err(id, "unknown hazard '%s'" % hz.get("kind", ""))
