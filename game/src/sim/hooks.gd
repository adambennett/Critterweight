class_name Hooks
extends RefCounted
## Data-driven gameplay triggers ("hooks"): the single scripting layer shared by kits (passives,
## JUICE states), element statuses, techniques, supplements, meta upgrades, modes and mods.
## A hook is JSON:
##   {"on": "hit_dealt", "if": {...}, "do": [{...}], "chance": 1.0, "cooldown": 0.0,
##    "max_uses": 0, "id": "optional", "source": "where it came from"}
## Events (`on`): pre_hit_dealt, pre_hit_taken (may modify the pending hit), hit_dealt, hit_taken,
##   blocked, parried, parry_success, knockdown_dealt, knocked_down, ko_dealt, dodge, taunt,
##   ability_used, juice_start, juice_end, move_start, land, grab_start, throw, wall_splat,
##   status_applied, status_received, reaction, round_start, tick (with "every": seconds),
##   emerge (a delayed blink resurfaced).
## Conditions (`if`, all must hold): slot / slots, move_class (light|heavy|ability|juice|grab),
##   charged, target_status / self_status (status id or element id), target_element,
##   self_health_below / above, target_health_below, target_guarding, target_down,
##   self_juiced, distance_below / above, in_zone (zone kind under self), flag (self flag set),
##   self_hype_above / below, other_flag (flag on the other fighter's `flags`, e.g. "minion"),
##   self_attacking (bool), hit_blocked (bool, pre_*/hit contexts), target_poise_below (fraction),
##   hit_part (body part of the pending hit: head|core|arm|leg|...).
## Actions (`do`): any EffectsSystem effect type, plus hit modifiers (only meaningful in pre_*):
##   damage_add {amount, min}, damage_mult, knockback_mult, launch, knockdown, stun_add, poise_mult,
##   guard_crush, buildup {element, amount, target}, refresh_status {element}, set_flag {flag, seconds},
##   stamina {amount, target}, hype {amount}, self_damage {amount}, cleanse,
##   status {status: {...StatusSet fields}, target} (adds/refreshes a status on self or the other),
##   cooldown {slot, set | add} (ability cooldowns; see the block at the end).
## Resource limits: at most 32 hooks per fighter and 16 actions per firing; recursion depth 2.

const MAX_HOOKS := 32
const MAX_ACTIONS := 16
const EVENTS := ["pre_hit_dealt", "pre_hit_taken", "hit_dealt", "hit_taken", "blocked", "parried",
	"parry_success", "knockdown_dealt", "knocked_down", "ko_dealt", "dodge", "taunt", "ability_used",
	"juice_start", "juice_end", "move_start", "land", "grab_start", "throw", "wall_splat",
	"status_applied", "status_received", "reaction", "round_start", "tick", "emerge"]
const HIT_MODIFIERS := ["damage_add", "damage_mult", "knockback_mult", "launch", "knockdown", "stun_add",
	"poise_mult", "guard_crush", "buildup", "refresh_status"]

var fighter                      ## Fighter
var list: Array = []             ## active hooks: Dictionary + runtime fields _cd, _uses, _until, _t
var _depth := 0


func _init(f) -> void:
	fighter = f


static func validate(h: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	if not EVENTS.has(str(h.get("on", ""))) and not EVENTS_NPC.has(str(h.get("on", ""))):
		errs.append("hook: unknown event '%s'" % h.get("on", ""))
	var acts: Array = h.get("do", [])
	if acts.size() > MAX_ACTIONS:
		errs.append("hook: more than %d actions" % MAX_ACTIONS)
	for a in acts:
		if typeof(a) != TYPE_DICTIONARY:
			errs.append("hook: action is not an object")
			continue
		var t := str(a.get("type", ""))
		if not HIT_MODIFIERS.has(t) and not EffectsSystem.TYPES.has(t) and not t in ["set_flag", "stamina", "cleanse", "self_damage", "hype", "status", "cooldown"]:
			errs.append("hook: unknown action '%s'" % t)
	return errs


## Adds a hook; `duration` > 0 makes it temporary (e.g. a JUICE state or a status).
func add(h: Dictionary, source := "", duration := 0.0) -> void:
	if list.size() >= MAX_HOOKS:
		return
	var c := h.duplicate(true)
	c["_cd"] = 0.0
	c["_uses"] = 0
	c["_t"] = 0.0
	c["_until"] = (fighter.time + duration) if duration > 0.0 else -1.0
	c["source"] = source if source != "" else str(h.get("source", ""))
	list.append(c)


func remove_source(source: String) -> void:
	list = list.filter(func(h): return h["source"] != source)


func clear_temporary() -> void:
	list = list.filter(func(h): return float(h["_until"]) < 0.0)


func tick(dt: float) -> void:
	if list.is_empty():
		return
	var now: float = fighter.time
	for h in list.duplicate():
		if float(h["_until"]) >= 0.0 and now > float(h["_until"]):
			list.erase(h)
			continue
		h["_cd"] = maxf(0.0, float(h["_cd"]) - dt)
		if h["on"] == "tick":
			h["_t"] = float(h["_t"]) + dt
			if float(h["_t"]) >= float(h.get("every", 1.0)):
				h["_t"] = 0.0
				_run(h, {})


## Fires all hooks listening to `event`. ctx may contain: hit (Dictionary, mutable in pre_*),
## other (Fighter), slot, move_class, charged, status, element, reaction.
func fire(event: String, ctx := {}) -> void:
	if list.is_empty() or _depth > 1:
		return
	for h in list.duplicate():
		if h["on"] != event:
			continue
		if float(h["_cd"]) > 0.0:
			continue
		if int(h.get("max_uses", 0)) > 0 and int(h["_uses"]) >= int(h["max_uses"]):
			continue
		if not _conditions(h.get("if", {}), ctx):
			continue
		if float(h.get("chance", 1.0)) < 1.0 and fighter.sim and fighter.sim.rng.randf() > float(h["chance"]):
			continue
		_run(h, ctx)


## Evaluates a hook-shaped entry once (conditions + actions) without registering it. Used for
## per-move "on_hit" conditionals.
func run_inline(h: Dictionary, ctx: Dictionary) -> void:
	if _conditions(h.get("if", {}), ctx):
		_depth += 1
		var acts: Array = h.get("do", [])
		for i in mini(acts.size(), MAX_ACTIONS):
			_act(acts[i], ctx)
		_depth -= 1


func _status_match(f, key: String) -> bool:
	return f.statuses.has(key) or f.statuses.has_element(key)


func _conditions(c: Dictionary, ctx: Dictionary) -> bool:
	var f = fighter
	var other = ctx.get("other")
	for k in c:
		var v = c[k]
		if k == "not":   # negation (NPC-kit extension block at the end of this file)
			if typeof(v) == TYPE_DICTIONARY and _conditions(v, ctx):
				return false
			continue
		match k:
			"slot":
				if not _slot_matches(ctx, str(v)):
					return false
			"slots":
				var any_slot := false
				for sv in (v as Array):
					any_slot = any_slot or _slot_matches(ctx, str(sv))
				if not any_slot:
					return false
			"move_class":
				if str(ctx.get("move_class", "")) != str(v):
					return false
			"charged":
				if bool(ctx.get("charged", false)) != bool(v):
					return false
			"target_status":
				if other == null or not _status_match(other, str(v)):
					return false
			"self_status":
				if not _status_match(f, str(v)):
					return false
			"target_element":
				if other == null or other.creature.element != str(v):
					return false
			"self_health_below":
				if f.health_frac() >= float(v):
					return false
			"self_health_above":
				if f.health_frac() <= float(v):
					return false
			"target_health_below":
				if other == null or other.health_frac() >= float(v):
					return false
			"target_guarding":
				if other == null or (other.state == Fighter.State.GUARD) != bool(v):
					return false
			"target_down":
				if other == null or other.is_down() != bool(v):
					return false
			"self_juiced":
				if (f.time < f.juiced_until) != bool(v):
					return false
			"distance_below":
				if other == null or f.pos().distance_to(other.pos()) >= float(v):
					return false
			"distance_above":
				if other == null or f.pos().distance_to(other.pos()) <= float(v):
					return false
			"in_zone":
				if f.sim == null or not f.sim.effects.fighter_in_zone(f, str(v)):
					return false
			"flag":
				if not f.has_flag(str(v)):
					return false
			"element":
				if str(ctx.get("element", "")) != str(v):
					return false
			"self_hype_above":
				if f.hype <= float(v):
					return false
			"self_hype_below":
				if f.hype >= float(v):
					return false
			"other_flag":
				if other == null or not bool(other.flags.get(str(v), false)):
					return false
			"self_attacking":
				if (f.state == Fighter.State.ATTACK or f.state == Fighter.State.ABILITY) != bool(v):
					return false
			"hit_blocked":
				var hb = ctx.get("hit")
				if hb == null or bool(hb.get("blocked", false)) != bool(v):
					return false
			"target_poise_below":
				if other == null or other.poise >= other.effective_max_poise() * float(v):
					return false
			"hit_part":
				var hp = ctx.get("hit")
				if hp == null or str(hp.get("part", "")) != str(v):
					return false
	return true


## Whether the context's move answers a Classic slot name. Movesets (docs/design/MOVESET_COMBAT.md
## §7): a pool move answers the slots it is built on, and a basic or heavy move also answers the
## generic light-string and heavy slots, so upgrades written for "heavy" reach Hydro Cannon too.
func _slot_matches(ctx: Dictionary, want: String) -> bool:
	var s := str(ctx.get("slot", ""))
	if s == want:
		return true
	var f = fighter
	if f == null or f.combat_style != "moves":
		return false
	var pool_id := str(ctx.get("pool", ""))
	var hit = ctx.get("hit")
	if pool_id == "" and hit != null:
		pool_id = str(hit.get("pool", ""))
	if pool_id == "" and s.begins_with("mv."):
		pool_id = s.substr(3)
	if pool_id == "":
		return false
	# the move belongs to the hook's owner, or (hit_taken, pre_hit_taken) to the other fighter
	var pm: PoolMove = f.creature.pool.get(pool_id)
	var other = ctx.get("other")
	if pm == null and other is Fighter:
		pm = (other as Fighter).creature.pool.get(pool_id)
	return pm != null and pm.answers_slot(want)


func _run(h: Dictionary, ctx: Dictionary) -> void:
	h["_uses"] = int(h["_uses"]) + 1
	h["_cd"] = float(h.get("cooldown", 0.0))
	_depth += 1
	var acts: Array = h.get("do", [])
	for i in mini(acts.size(), MAX_ACTIONS):
		_act(acts[i], ctx)
	_depth -= 1


func _act(a: Dictionary, ctx: Dictionary) -> void:
	if _act_on_behalf(a, ctx):
		return
	var f = fighter
	var t := str(a.get("type", ""))
	var hit = ctx.get("hit")
	var tgt_self := str(a.get("target", "target")) == "self"
	var other = ctx.get("other")
	var who = f if tgt_self or other == null else other
	match t:
		"damage_add":
			if hit != null:
				var before := float(hit["damage"])
				var after := before + float(a.get("amount", 0.0))
				if a.has("min"):
					after = maxf(after, minf(before, float(a["min"])))
				hit["damage"] = after
		"damage_mult":
			if hit != null:
				hit["damage"] = float(hit["damage"]) * float(a.get("mult", 1.0))
		"knockback_mult":
			if hit != null:
				hit["knockback"] = (hit["knockback"] as Vector3) * float(a.get("mult", 1.0))
		"launch":
			if hit != null:
				hit["knockback"] = (hit["knockback"] as Vector3) + Vector3.UP * float(a.get("amount", 3.0))
		"knockdown":
			if hit != null:
				hit["knockdown"] = true
		"stun_add":
			if hit != null:
				hit["stun"] = float(hit["stun"]) + float(a.get("amount", 0.1))
		"poise_mult":
			if hit != null:
				hit["poise"] = float(hit["poise"]) * float(a.get("mult", 1.0))
		"guard_crush":
			if hit != null:
				hit["guard_drain"] = float(hit.get("guard_drain", 0.0)) * float(a.get("mult", 2.0))
				hit["poise"] = float(hit["poise"]) * float(a.get("mult", 2.0))
		"buildup":
			if who:
				who.statuses.add_buildup(str(a.get("element", "")), float(a.get("amount", 10.0)), f)
		"refresh_status":
			if who:
				who.statuses.refresh_element(str(a.get("element", "")))
		"set_flag":
			f.set_flag(str(a.get("flag", "")), float(a.get("seconds", 1.0)))
		"stamina":
			if who:
				who.stamina = clampf(who.stamina + float(a.get("amount", 0.0)), 0.0, who.max_stamina)
		"hype":
			f.hype = clampf(f.hype + float(a.get("amount", 0.0)), 0.0, 100.0)
		"self_damage":
			f.health = maxf(1.0, f.health - float(a.get("amount", 1.0)))
		"cleanse":
			who.statuses.cleanse_elements()
		"status":
			if who and not who.is_out():
				var st: Dictionary = a.get("status", {}).duplicate(true)
				if not st.is_empty():
					st["source"] = f
					who.statuses.add(st)
		"cooldown":
			_act_cooldown(a)
		_:
			if f.sim and EffectsSystem.TYPES.has(t):
				var e: Dictionary = a.duplicate()
				if not e.has("t"):
					e["t"] = 0.0
				if hit != null and not e.has("at"):
					e["at_point"] = hit.get("point", f.pos())
				f.sim.effects.fire(f, e, null)


# =====================================================================================
# Kit extension (added with the Dredge/Dozer kits): ability cooldown control.
#   {"type": "cooldown", "slot": "ability1", "set": 0.0}  or  {"type": "cooldown", "slot": "ability2", "add": -3.0}
# Acts on the hook owner. Reaching 0 refills the slot's charges (e.g. a JUICE state that makes an
# ability free to repeat: on ability_used -> set 0).
# =====================================================================================

func _act_cooldown(a: Dictionary) -> void:
	var f = fighter
	var slot := str(a.get("slot", ""))
	if f.combat_style == "moves":
		slot = f.resolve_slot(slot)       # Movesets: the loadout slot holding that ability
		if f.slot_move(slot) == null:
			return
	elif not f.creature.abilities.has(slot):
		return
	var left := float(f.cooldown_left.get(slot, 0.0))
	left = float(a["set"]) if a.has("set") else left + float(a.get("add", 0.0))
	left = maxf(0.0, left)
	f.cooldown_left[slot] = left
	if left <= 0.0:
		f.charges_left[slot] = f.slot_max_charges(slot)


# =====================================================================================
# NPC-kit extensions (minion / boss / Kid Lamprey kits; docs/kits/minions.md)
#   events    knocked_out  fired on the fighter that was just KO'd (ctx other = who KO'd it)
#             thrown       fired on a fighter that was just thrown (ctx other = the thrower,
#                          point = its expected landing spot)
#   condition "not": {...}  holds when the nested conditions do NOT all hold
#   action    "source": "other"  the effect is fired BY the event's other fighter (damage credit,
#             teams and targeting are the other fighter's) and is centred on the event point,
#             or on this fighter when the event has none. An event point (e.g. a landing spot)
#             also centres this fighter's own effects that give no "at".
#   action    {"type": "self_damage", "lethal": true}  may KO this fighter (EffectsSystem)
# =====================================================================================

const EVENTS_NPC := ["knocked_out", "thrown"]


## Effect actions that need the event point or the other fighter as their source. Returns true
## when the action was handled here (plain actions fall through to _act).
func _act_on_behalf(a: Dictionary, ctx: Dictionary) -> bool:
	var t := str(a.get("type", ""))
	if fighter.sim == null or not EffectsSystem.TYPES.has(t):
		return false
	if t == "self_damage":
		if not bool(a.get("lethal", false)):
			return false
		fighter.sim.effects.fire(fighter, a.duplicate(), null)
		return true
	var by_other := str(a.get("source", "")) == "other"
	var point = ctx.get("point")
	if not by_other and (point == null or t in ["hype", "cleanse"]):
		return false
	var src = fighter
	if by_other:
		var other = ctx.get("other")
		if other == null or not is_instance_valid(other) or other.despawned:
			return true   # nobody to act for: the action is dropped
		src = other
	var e: Dictionary = a.duplicate()
	e.erase("source")
	if not e.has("t"):
		e["t"] = 0.0
	if not e.has("at") and not e.has("at_point"):
		var hit = ctx.get("hit")
		if hit != null:
			e["at_point"] = hit.get("point", fighter.pos())
		elif point != null:
			e["at_point"] = point
		else:
			e["at_point"] = fighter.ground_pos()
	fighter.sim.effects.fire(src, e, null)
	return true
