class_name UpgradeTranslation
extends RefCounted
## How upgrades written for the v0.9.17 Classic slots reach Movesets pool moves
## (docs/design/MOVESET_COMBAT.md §7, docs/CAMPAIGN_SYSTEMS.md "Moves in runs"). Pure functions on
## creature dictionaries; BuildApplier composes fighters with them and analyze() tells texts,
## reward offers and the lint test (test_upgrade_translation.gd) what an upgrade reaches.
##
## apply_patch() applies one build patch (technique, supplement, side effect, Cannery upgrade,
## event effect) to a creature dictionary:
##   1. as written. Pool moves built on Classic slots (`use`, basic `string`s) share those dicts, so
##      moves.heavy / abilities.ability1 patches improve Furnace Haymaker / Steam Vent as they are.
##   2. translated onto the INLINE pool moves (movepool.<id>.move / .charged_move) by role:
##        moves.l1|l2|l3|finisher|dash_attack -> role basic    moves.heavy|heavy_charged -> role heavy
##        moves.*                             -> every inline move    abilities.* -> role special
##      (abilities.ability1/ability2/juice, moves.grab/pummel/taunt and "<slot>@<flag>" variants name
##      one Classic move each: nothing to translate.) heavy_charged reaches an inline move's
##      charged_move when it has one. The rest of the path applies inside the move; a lone hit field
##      (damage, poise, knockback, stun, launch, buildup, element, guard_break) also reaches the
##      move's effects that carry it, because an inline move's hit lives in its effects (additive
##      ops: the move's own value, else its first-level effects; other ops: every effect, nested
##      on_expire/on_hit ones included). Multiplicative ops (mul, min, max, set, time_scale)
##      transfer as they are; an additive damage/buildup op that lands on a repeating effect
##      (`every`) becomes the multiplier (base + value) / base relative to the Classic slot's current
##      value, so +1 damage never becomes +1 per stream tick. A leaf changes at most once per
##      upgrade and op (ctx.seen): moves.* and abilities.* both reach special moves, and a leaf the
##      upgrade patches directly is not patched again by the heavy fallback. Edits of a move's own
##      timing (keys, hit windows, duration, cancel, armor, invuln, sustain; lunges except their
##      multipliers) stay with the Classic move they were written for: another move has another
##      animation, and a broken move would make BuildApplier fall back to the bare kit.
##   3. `string` (the Classic light string): a basic pool move whose own string starts with it gets
##      the new beginning (Lead Hand Learner's double jab reaches Ember Jab).
##   4. Movesets compositions only (ctx.movesets): with no heavy-role move in the loadout, lone
##      hit-field patches on moves.heavy / heavy_charged also reach the last step of each equipped
##      basic string (its finisher: the Classic engine files the finisher under the heavy class),
##      and hook conditions naming only heavy slots become move_class "heavy" (translate_hook).
##      Changes to the heavy's shape (timing, leaps, extra effects) do not move to the finisher.
##      `pool.<id>.<rest>`, `pool[role=X].<rest>`, `pool[category=X].<rest>` (also hold, element)
##      address pool moves directly: the "movesets" block of an apply uses them for effects that
##      only exist in Movesets. Entry fields (cooldown, charges, cost, max_hold, drain) go to the
##      pool entry (an ability's cooldown and charges to its ability).
## analyze() runs the same code on small per-move copies of the creature to tell which pool moves
## (Movesets) or Classic slots an upgrade changes, and which of its effects are fighter-wide.

const BASIC_SLOTS := ["l1", "l2", "l3", "finisher", "dash_attack"]
const HEAVY_SLOTS := ["heavy", "heavy_charged"]
const HIT_FIELDS := ["damage", "knockback", "stun", "poise", "buildup", "launch", "element", "guard_break"]
## additive ops on these become multipliers on repeating effects
const RATE_FIELDS := ["damage", "buildup"]
## moves every loadout has in both styles (Grapple, its throws and pummel, the taunt)
const UNIVERSAL_MOVES := ["grab", "pummel", "taunt", "throw"]
## pool entry fields (not inside the MoveDef)
const ENTRY_KEYS := ["cooldown", "charges", "cost", "max_hold", "drain"]
const NESTED_EFFECT_LISTS := ["on_expire", "on_emerge", "on_land"]
const STRUCTURE_OPS := ["append", "merge", "remove", "time_scale"]
const LEAF_OPS := ["set", "add", "mul", "min", "max"]
## a move's own animation timing: not carried to another move (lunge multipliers are speeds)
const TIMING_FIELDS := ["keys", "hit", "duration", "cancel", "armor", "invuln", "sustain", "lunge"]


## The translation context for a composition. combat "moves": the full Movesets composition (heavy
## fallback, `pool.` paths); any other value: only the Classic-safe inline translation.
## `inf` = RunMoves.info() of the fighter, `loadout` = the pool ids it fights with.
static func context(inf: Dictionary, combat: String, loadout: Array) -> Dictionary:
	var movesets := combat == "moves"
	var fallback := false
	if movesets and not bool(inf.get("martial", false)) and not loadout.is_empty():
		fallback = true
		for id in loadout:
			if str((inf.get("moves", {}) as Dictionary).get(str(id), {}).get("role", "")) == "heavy":
				fallback = false
	return {"movesets": movesets, "info": inf, "loadout": loadout.duplicate(), "fallback": fallback, "seen": []}


# =============================================================================================
# Applying
# =============================================================================================

## Applies one patch (see the header). Returns the number of leaves changed.
static func apply_patch(d: Dictionary, p: Dictionary, ctx: Dictionary = {}) -> int:
	var path := str(p.get("path", ""))
	var segs := ContentPatch.parse_path(path)
	if segs.is_empty():
		return 0
	var head := str(segs[0]["key"])
	if head == "pool":
		return apply_pool_patch(d, p, ctx) if bool(ctx.get("movesets", false)) else 0
	var op := str(p.get("op", ""))
	var old_string: Array = []
	if head == "string" and segs.size() == 1 and op == "set" and typeof(d.get("string")) == TYPE_ARRAY:
		old_string = (d["string"] as Array).duplicate()
	var slot := ""
	var rest := ""
	if segs.size() >= 2 and (segs[0]["sels"] as Array).is_empty() and (segs[1]["sels"] as Array).is_empty():
		slot = str(segs[1]["key"])
		rest = ".".join(path.split(".").slice(2))
	var base = _classic_base(d, head, slot, rest, op)
	var hits := ContentPatch.apply(d, p)
	var seen: Array = ctx.get("seen", [])
	if hits > 0 and LEAF_OPS.has(op) and head == "moves":
		# what the upgrade changes directly counts as changed (the heavy fallback must not add the
		# heavy's bonus on top of the upgrade's own finisher bonus)
		for r in ContentPatch.targets(d, path, bool(p.get("create", false))):
			seen.append([r[0], r[1], op])
	if head == "moves" and slot != "" and not slot.contains("@"):
		var role := ""
		if slot == "*":
			role = "*"
		elif BASIC_SLOTS.has(slot):
			role = "basic"
		elif HEAVY_SLOTS.has(slot):
			role = "heavy"
		if role != "":
			for m in inline_moves(d, role, slot):
				hits += _apply_in_move(m, rest, p, base, seen)
		if bool(ctx.get("fallback", false)) and HEAVY_SLOTS.has(slot) and HIT_FIELDS.has(rest):
			for fm in _fallback_moves(d, ctx):
				hits += _apply_in_move(fm, rest, p, base, seen)
	elif head == "abilities" and slot == "*":
		for m2 in inline_moves(d, "special", "*"):
			hits += _apply_in_move(m2, rest, p, base, seen)
	if not old_string.is_empty():
		hits += _translate_string(d, old_string, p.get("value"))
	return hits


## The inline pool move dicts of a role ("*" = every inline move). `slot` picks heavy_charged's
## charged_move; moves.* and abilities.* reach both halves of a charged move.
static func inline_moves(d: Dictionary, role: String, slot: String) -> Array:
	var out := []
	var mp = d.get("movepool", {})
	if typeof(mp) != TYPE_DICTIONARY:
		return out
	for id in mp:
		var e = mp[id]
		if not _is_inline(e):
			continue
		var r := entry_role(e)
		if role != "*" and r != role:
			continue
		var cm = (e as Dictionary).get("charged_move")
		if slot == "heavy_charged" and typeof(cm) == TYPE_DICTIONARY:
			out.append(cm)
			continue
		out.append(e["move"])
		if slot == "*" and typeof(cm) == TYPE_DICTIONARY:
			out.append(cm)
	return out


## A pool entry's role as PoolMove.parse reads it.
static func entry_role(e) -> String:
	if typeof(e) != TYPE_DICTIONARY:
		return ""
	return str((e as Dictionary).get("role", "basic" if (e as Dictionary).has("string") else "special"))


## An inline pool entry: its own MoveDef (PoolMove.parse precedence: use, string, martial, move).
static func _is_inline(e) -> bool:
	if typeof(e) != TYPE_DICTIONARY:
		return false
	var ed: Dictionary = e
	return typeof(ed.get("move")) == TYPE_DICTIONARY and not ed.has("use") and not ed.has("string") and typeof(ed.get("martial")) != TYPE_DICTIONARY


## The Classic slot's current value of the patched field (the base of an additive op turned into a
## multiplier), or null when the patch names no single numeric field of a Classic slot.
static func _classic_base(d: Dictionary, head: String, slot: String, rest: String, op: String):
	if op != "add" or head != "moves" or slot == "" or slot == "*" or rest == "":
		return null
	var leaf := rest.split(".")[rest.split(".").size() - 1].split("[")[0]
	if not RATE_FIELDS.has(leaf):
		return null
	var mv = (d.get("moves", {}) as Dictionary).get(slot) if typeof(d.get("moves")) == TYPE_DICTIONARY else null
	if typeof(mv) != TYPE_DICTIONARY:
		return null
	for r in ContentPatch.targets(mv, rest):
		var c = r[0]
		var k = r[1]
		if typeof(c) == TYPE_DICTIONARY and (c as Dictionary).has(k) and _num(c[k]):
			return float(c[k])
		if typeof(c) == TYPE_ARRAY and int(k) < (c as Array).size() and _num(c[k]):
			return float(c[k])
	return null


## Applies the rest of a translated path inside one move dict (see the header). `own`: the patch
## was written for this very move (a `pool.` path), so its timing edits apply too.
static func _apply_in_move(m: Dictionary, rest: String, p: Dictionary, base, seen: Array, own := false) -> int:
	var op := str(p.get("op", ""))
	if rest == "":
		# the whole move: only time_scale transfers (a set/merge of a Classic move would replace it)
		if op != "time_scale" or _was_seen(seen, m, "", op):
			return 0
		ContentPatch.time_scale_move(m, float(p.get("value", 1.0)), str(p.get("phase", "all")))
		seen.append([m, "", op])
		return 1
	if HIT_FIELDS.has(rest):
		return _apply_hit_field(m, rest, p, base, seen)
	var first := rest.split(".")[0].split("[")[0]
	if not own and TIMING_FIELDS.has(first) and not (first == "lunge" and op in ["mul", "min", "max"]):
		return 0
	if STRUCTURE_OPS.has(op):
		if _was_seen(seen, m, rest, op):
			return 0
		var q := p.duplicate()
		q["path"] = "_." + rest
		var n := ContentPatch.apply({"_": m}, q)
		if n > 0:
			seen.append([m, rest, op])
		return n
	return _apply_refs(ContentPatch.targets(m, rest, bool(p.get("create", false))), p, base, seen)


## A lone hit field: the move's own value plus its effects that carry the field.
static func _apply_hit_field(m: Dictionary, field: String, p: Dictionary, base, seen: Array) -> int:
	var op := str(p.get("op", ""))
	var own := []
	if m.has(field) or (p.has("default") and m.has("hit") and op in ["add", "mul", "min", "max"]):
		own.append([m, field])
	var first := []
	var nested := []
	for e in m.get("effects", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if (e as Dictionary).has(field):
			first.append([e, field])
		for key in NESTED_EFFECT_LISTS:
			for ne in _dicts((e as Dictionary).get(key, [])):
				if ne.has(field):
					nested.append([ne, field])
	for oh in _dicts(m.get("on_hit", [])):
		for ne2 in _dicts(oh.get("do", [])):
			if ne2.has(field):
				nested.append([ne2, field])
	var refs := []
	if op == "add":
		refs = own if not own.is_empty() else first
	else:
		refs = own + first + nested
	return _apply_refs(refs, p, base, seen)


static func _apply_refs(refs: Array, p: Dictionary, base, seen: Array) -> int:
	var op := str(p.get("op", ""))
	var hits := 0
	for r in refs:
		var c = r[0]
		var k = r[1]
		if _was_seen(seen, c, k, op):
			continue
		var q := p
		if op == "add" and RATE_FIELDS.has(str(k)) and typeof(c) == TYPE_DICTIONARY and float((c as Dictionary).get("every", 0.0)) > 0.0:
			# +N on a repeating effect: the same relative boost the Classic slot got
			var cur = (c as Dictionary).get(k, p.get("default"))
			if not _num(cur):
				continue
			var b := float(base) if base != null and float(base) > 0.0 else float(cur)
			if b <= 0.0:
				continue
			q = {"op": "mul", "value": (b + float(p.get("value", 0.0))) / b}
		var n := ContentPatch.apply_at(c, k, q)
		if n > 0:
			seen.append([c, k, op])
		hits += n
	return hits


static func _was_seen(seen: Array, c, k, op: String) -> bool:
	for s in seen:
		if is_same(s[0], c) and str(s[1]) == str(k) and str(s[2]) == op:
			return true
	return false


## Heavy fallback targets: the last step of every equipped basic string (its finisher), or an
## equipped inline basic move itself.
static func _fallback_moves(d: Dictionary, ctx: Dictionary) -> Array:
	var out := []
	var moves: Dictionary = (ctx.get("info", {}) as Dictionary).get("moves", {})
	for id in ctx.get("loadout", []):
		var mv: Dictionary = moves.get(str(id), {})
		if str(mv.get("role", "")) != "basic":
			continue
		var st: Array = mv.get("string", [])
		if not st.is_empty():
			var last := str(st[st.size() - 1])
			var dm = (d.get("moves", {}) as Dictionary).get(last) if typeof(d.get("moves")) == TYPE_DICTIONARY else null
			if typeof(dm) == TYPE_DICTIONARY:
				out.append(dm)
		elif bool(mv.get("inline", false)):
			var e = (d.get("movepool", {}) as Dictionary).get(str(id)) if typeof(d.get("movepool")) == TYPE_DICTIONARY else null
			if _is_inline(e):
				out.append(e["move"])
	return out


## `string` translation: basic pool moves whose string starts with the old light string.
static func _translate_string(d: Dictionary, old: Array, new_value) -> int:
	if typeof(new_value) != TYPE_ARRAY:
		return 0
	var hits := 0
	var mp = d.get("movepool", {})
	if typeof(mp) != TYPE_DICTIONARY:
		return 0
	for id in mp:
		var e = mp[id]
		if typeof(e) != TYPE_DICTIONARY or typeof((e as Dictionary).get("string")) != TYPE_ARRAY:
			continue
		var st: Array = e["string"]
		if st.size() < old.size() or st.slice(0, old.size()) != old:
			continue
		var out: Array = (new_value as Array).duplicate()
		out.append_array(st.slice(old.size()))
		e["string"] = out
		hits += 1
	return hits


## Hook conditions in a Movesets loadout without a heavy-role move: a hook naming only heavy slots
## (heavy, heavy_charged and their variants) answers the finisher's heavy class instead.
static func translate_hook(h: Dictionary, ctx: Dictionary) -> Dictionary:
	if not bool(ctx.get("fallback", false)):
		return h
	var cond = h.get("if", {})
	if typeof(cond) != TYPE_DICTIONARY or (cond as Dictionary).has("move_class"):
		return h
	var names := slot_names(cond)
	if names.is_empty():
		return h
	for n in names:
		if not HEAVY_SLOTS.has(str(n).split("@")[0]):
			return h
	var c2: Dictionary = (cond as Dictionary).duplicate(true)
	c2.erase("slot")
	c2.erase("slots")
	c2["move_class"] = "heavy"
	var h2 := h.duplicate(true)
	h2["if"] = c2
	return h2


## The slot names a hook condition block names (slot / slots).
static func slot_names(cond) -> Array:
	var out := []
	if typeof(cond) != TYPE_DICTIONARY:
		return out
	var cd: Dictionary = cond
	if cd.has("slot"):
		out.append(str(cd["slot"]))
	if typeof(cd.get("slots")) == TYPE_ARRAY:
		for s in cd["slots"]:
			out.append(str(s))
	return out


# =============================================================================================
# Movesets-specific paths: pool.<id>.<rest> / pool[field=value].<rest>
# =============================================================================================

static func apply_pool_patch(d: Dictionary, p: Dictionary, ctx: Dictionary) -> int:
	var path := str(p.get("path", ""))
	var segs := ContentPatch.parse_path(path)
	var inf: Dictionary = ctx.get("info", {})
	var moves: Dictionary = inf.get("moves", {})
	if segs.is_empty() or moves.is_empty():
		return 0
	var ids := []
	var rest := ""
	var sels: Array = segs[0]["sels"]
	if sels.is_empty():
		if segs.size() < 3:
			return 0
		var key := str(segs[1]["key"])
		ids = (inf.get("order", []) as Array).duplicate() if key == "*" else [key]
		rest = ".".join(path.split(".").slice(2))
	else:
		for id in inf.get("order", []):
			var ok := true
			for s in sels:
				if str(s.get("kind", "")) != "match" or str((moves.get(str(id), {}) as Dictionary).get(str(s["field"]), "")) != str(s["value"]):
					ok = false
			if ok:
				ids.append(str(id))
		rest = ".".join(path.split(".").slice(1))
	if rest == "":
		return 0
	var seen: Array = ctx.get("seen", [])
	var hits := 0
	var entry_key := rest.split(".")[0].split("[")[0]
	for id2 in ids:
		var mv: Dictionary = moves.get(str(id2), {})
		if mv.is_empty():
			continue
		for t in _pool_dicts(d, mv, ENTRY_KEYS.has(entry_key) and rest.split(".").size() == 1 and entry_key == rest):
			hits += _apply_in_move(t, rest, p, null, seen, true)
	return hits


## The dicts a pool move's `pool.` patch acts on: its entry (entry fields), else its MoveDef(s).
static func _pool_dicts(d: Dictionary, mv: Dictionary, entry_field: bool) -> Array:
	var out := []
	var id := str(mv.get("id", ""))
	var mp: Dictionary = d.get("movepool", {}) if typeof(d.get("movepool")) == TYPE_DICTIONARY else {}
	var moves: Dictionary = d.get("moves", {}) if typeof(d.get("moves")) == TYPE_DICTIONARY else {}
	var abilities: Dictionary = d.get("abilities", {}) if typeof(d.get("abilities")) == TYPE_DICTIONARY else {}
	var use := str(mv.get("use", ""))
	if entry_field:
		if use != "" and typeof(abilities.get(use)) == TYPE_DICTIONARY:
			out.append(abilities[use])
		elif typeof(mp.get(id)) == TYPE_DICTIONARY:
			out.append(mp[id])
		return out
	if bool(mv.get("inline", false)) and _is_inline(mp.get(id)):
		out.append(mp[id]["move"])
		if typeof((mp[id] as Dictionary).get("charged_move")) == TYPE_DICTIONARY:
			out.append(mp[id]["charged_move"])
		return out
	for slot in mv.get("slots", []):
		var s := str(slot)
		if typeof(abilities.get(s)) == TYPE_DICTIONARY:
			out.append(abilities[s])
		elif typeof(moves.get(s)) == TYPE_DICTIONARY:
			out.append(moves[s])
	return out


# =============================================================================================
# Analysis: what an upgrade reaches
# =============================================================================================

## What an apply block (with its "movesets" block in Movesets) reaches for one fighter:
## {targeted: has move-targeted effects, general: has fighter-wide effects, moves: {pool id: true}
## (combat "moves") or {Classic slot: true} (Classic, and martial fighters - Varga keeps his
## Classic strike kit in Movesets, techniques only swap strikes), unmatched_hooks: [slot names no
## move answers]}. Fighter-wide: mods, statuses, fight rolls, economy entries, patches on stats /
## throws / the Ultimate / passives / Grapple and taunt (every loadout has them), hooks without a
## slot or move-class condition. `inf` = RunMoves.info(); `loadout` matters for the heavy fallback.
static func analyze(inf: Dictionary, apply: Dictionary, combat: String, loadout: Array) -> Dictionary:
	var out := {"targeted": false, "general": false, "moves": {}, "unmatched_hooks": []}
	var blocks: Array = [apply]
	if combat == "moves" and typeof(apply.get("movesets")) == TYPE_DICTIONARY:
		blocks.append(apply["movesets"])
	var patches := []
	var hooks := []
	for blk in blocks:
		var b: Dictionary = blk
		for k in ["mods", "statuses", "fight_rolls", "run"]:
			if typeof(b.get(k)) == TYPE_ARRAY and not (b[k] as Array).is_empty():
				out["general"] = true
		for p in b.get("patches", []):
			if typeof(p) != TYPE_DICTIONARY:
				continue
			if universal_path(str(p.get("path", ""))):
				out["general"] = true
			else:
				out["targeted"] = true
				patches.append(p)
		for h in b.get("hooks", []):
			if typeof(h) == TYPE_DICTIONARY:
				hooks.append(h)
	var raw: Dictionary = inf.get("raw", {})
	var ctx := context(inf, combat, loadout)
	var by_slot := slot_level(inf, combat)
	if not by_slot:
		for id in inf.get("order", []):
			var mv: Dictionary = (inf.get("moves", {}) as Dictionary).get(str(id), {})
			var mini := _mini_for_move(raw, mv)
			if mini.is_empty() or patches.is_empty():
				continue
			var before := mini.duplicate(true)
			ctx["seen"] = []
			for p2 in patches:
				apply_patch(mini, p2, ctx)
			if mini != before:
				(out["moves"] as Dictionary)[str(id)] = true
	else:
		for slot in classic_kit(raw):
			var mini2 := _mini_for_slot(raw, str(slot))
			var before2 := mini2.duplicate(true)
			ctx["seen"] = []
			for p3 in patches:
				apply_patch(mini2, p3, ctx)
			if mini2 != before2:
				(out["moves"] as Dictionary)[str(slot)] = true
	for h2 in hooks:
		var hh: Dictionary = translate_hook(h2, ctx) if combat == "moves" else h2
		var cond = hh.get("if", {})
		var names := slot_names(cond)
		var mclass := str((cond as Dictionary).get("move_class", "")) if typeof(cond) == TYPE_DICTIONARY else ""
		if names.is_empty() and mclass == "":
			out["general"] = true
			continue
		out["targeted"] = true
		var matched := _hook_matches(inf, raw, "classic" if by_slot else "moves", names, mclass)
		for mid in matched:
			(out["moves"] as Dictionary)[str(mid)] = true
		if matched.is_empty():
			(out["unmatched_hooks"] as Array).append(", ".join(PackedStringArray(names)) if not names.is_empty() else "move_class " + mclass)
	return out


## Whether analyze() works on Classic slots for this fighter and style: Classic, or a martial
## fighter (its strikes stay its Classic kit in Movesets).
static func slot_level(inf: Dictionary, combat: String) -> bool:
	return combat != "moves" or bool(inf.get("martial", false))


## True for a patch path every loadout has in both styles (not one move's).
static func universal_path(path: String) -> bool:
	var parts := path.split(".")
	var head := parts[0].split("[")[0]
	var slot := parts[1].split("[")[0].split("@")[0] if parts.size() > 1 else ""
	match head:
		"moves":
			return UNIVERSAL_MOVES.has(slot)
		"abilities":
			return slot == "juice"
		"movepool", "pool", "string":
			return false
	return true


## The Classic kit: every move and ability slot except the universal ones (variants under their
## slot), plus the light string.
static func classic_kit(raw: Dictionary) -> Array:
	var out := []
	for kind in ["moves", "abilities"]:
		var t = raw.get(kind, {})
		if typeof(t) != TYPE_DICTIONARY:
			continue
		for k in t:
			var base := str(k).split("@")[0]
			if UNIVERSAL_MOVES.has(base) or base == "juice" or out.has(base):
				continue
			out.append(base)
	if raw.has("string"):
		out.append("string")
	return out


## A copy of the creature parts one Classic slot lives in (with its variants).
static func _mini_for_slot(raw: Dictionary, slot: String) -> Dictionary:
	if slot == "string":
		return {"string": (raw.get("string", []) as Array).duplicate(true) if typeof(raw.get("string")) == TYPE_ARRAY else []}
	var out := {"moves": {}, "abilities": {}}
	for kind in ["moves", "abilities"]:
		var t = raw.get(kind, {})
		if typeof(t) != TYPE_DICTIONARY:
			continue
		for k in t:
			if str(k) == slot or str(k).begins_with(slot + "@"):
				(out[kind] as Dictionary)[k] = (t[k] as Dictionary).duplicate(true) if typeof(t[k]) == TYPE_DICTIONARY else t[k]
	return out


## A copy of the creature parts one pool move is made of: its Classic slots (with variants) and
## its pool entry (+ the light string for a basic string, which `string` patches translate).
static func _mini_for_move(raw: Dictionary, mv: Dictionary) -> Dictionary:
	if mv.is_empty():
		return {}
	var out := {"moves": {}, "abilities": {}, "movepool": {}}
	var slots: Array = (mv.get("slots", []) as Array).duplicate()
	for slot in slots:
		var part := _mini_for_slot(raw, str(slot))
		for kind in ["moves", "abilities"]:
			for k in part.get(kind, {}):
				(out[kind] as Dictionary)[k] = part[kind][k]
	var mp = raw.get("movepool", {})
	var id := str(mv.get("id", ""))
	if typeof(mp) == TYPE_DICTIONARY and (mp as Dictionary).has(id):
		(out["movepool"] as Dictionary)[id] = (mp[id] as Dictionary).duplicate(true) if typeof(mp[id]) == TYPE_DICTIONARY else {}
	if not (mv.get("string", []) as Array).is_empty() and typeof(raw.get("string")) == TYPE_ARRAY:
		out["string"] = (raw["string"] as Array).duplicate()
	return out


## Pool moves (Movesets) or Classic slots (Classic) a hook's slot / move-class condition answers.
static func _hook_matches(inf: Dictionary, raw: Dictionary, combat: String, names: Array, mclass: String) -> Array:
	var out := []
	if combat == "moves":
		var moves: Dictionary = inf.get("moves", {})
		for id in inf.get("order", []):
			var mv: Dictionary = moves.get(str(id), {})
			var ok := true
			if not names.is_empty():
				ok = false
				for n in names:
					ok = ok or answers_slot(mv, str(n))
			if ok and mclass != "":
				ok = (mv.get("classes", []) as Array).has(mclass)
			if ok:
				out.append(str(id))
		return out
	for slot in classic_kit(raw):
		var s := str(slot)
		if s == "string":
			continue
		var ok2 := true
		if not names.is_empty():
			ok2 = false
			for n2 in names:
				ok2 = ok2 or str(n2).split("@")[0] == s
		if ok2 and mclass != "":
			ok2 = _slot_class(raw, s) == mclass
		if ok2:
			out.append(s)
	return out


## PoolMove.answers_slot on RunMoves.info data (variants answer as their slot).
static func answers_slot(mv: Dictionary, slot: String) -> bool:
	var s := slot.split("@")[0]
	if (mv.get("slots", []) as Array).has(s):
		return true
	var role := str(PoolMove.ROLE_OF_SLOT.get(s, ""))
	return role != "" and role == str(mv.get("role", ""))


## The move class a Classic slot reports (its MoveDef class, else the engine's slot rule).
static func _slot_class(raw: Dictionary, slot: String) -> String:
	for kind in ["moves", "abilities"]:
		var t = raw.get(kind, {})
		if typeof(t) == TYPE_DICTIONARY and typeof((t as Dictionary).get(slot)) == TYPE_DICTIONARY:
			var c := str((t[slot] as Dictionary).get("class", ""))
			if c != "":
				return c
	return Combat.move_class(slot)


static func _dicts(v) -> Array:
	var out := []
	if typeof(v) == TYPE_ARRAY:
		for e in v:
			if typeof(e) == TYPE_DICTIONARY:
				out.append(e)
	return out


static func _num(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT
