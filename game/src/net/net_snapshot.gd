class_name NetSnapshot
## Server -> client state snapshot codec (unreliable channel; every snapshot is a full state so
## any one of them can be lost) and the fighter-roster codec (reliable). Layout of the shared
## snapshot body (after the per-client header [S_SNAPSHOT][u16 match][u32 tick][u16 input ack]):
##
##   [u8 slot count] per fighter slot:
##     [u8 roster generation]   0 = empty/despawned slot (nothing else follows)
##     [u8 state][u8 flags][vec3q root position][u8 segment count][quat32 rotation] x segments
##     [u16 health*10][u16 max_health*10][u16 stamina*10][u16 max_stamina*10]
##     [u16 poise*10][u16 max_poise*10][u8 hype*2.55][i8 lives][i8 target]
##     [u8 cooldown count] ([str slot][u16 seconds*100]) x n
##     [u8 status count]  ([str id][str element][u16 seconds*100]) x n
##   [u8 entity count] per entity: [u16 id][u8 kind code (255: str kind)][str zone_kind/prop]
##                     [str vfx][vec3q pos][u16 radius*100][str element][i8 team]
##   [u8 prop count]   per dynamic prop: [u8 prop index][vec3q pos][quat32 rotation]
##   mode: [u8 phase][u8 round index][u16 round timer*10][u8 flags][i8 winner][i8 round winner]
##         [u8 team count] ([i8 team][u8 round wins][i16 score]) x n [str hud status]
##         [tagged value: view_state()] [tagged value: hud_state()]   (NetEventCodec values)
##
## Segment positions are NOT sent: every body's origin sits on its joint pivot (BodyDef
## invariant), so clients rebuild them by forward kinematics from the root position and the
## rotations (fk()); this keeps an 8-fighter snapshot under one MTU.
## A slot's generation changes whenever its body identity changes (spawn into the slot, despawn,
## rebuild with another/scaled creature); the roster message tells clients what a generation is.

const F_JUICED := 1
const F_EVADING := 2
const F_CRASH := 4
const F_GUARD := 8
const F_GROUNDED := 16
const F_AI := 32
const F_HIDDEN := 64

const M_INPUT := 1
const M_FINISHED := 2

const MAX_ENTITIES := 96
const MAX_PROPS := 64
const MAX_STATUSES := 12
const MAX_COOLDOWNS := 8
const KINDS := ["projectile", "zone", "prop", "delayed"]   ## entity kind codes (255 = text follows)


# ---- compatibility helpers (Fighter/MatchMode features added by other subsystems) ----

static func is_despawned(f: Fighter) -> bool:
	if f == null or not is_instance_valid(f):
		return true
	var v = f.get("despawned")
	return v == true


static func is_hidden(f: Fighter) -> bool:
	return f.has_method("has_flag") and bool(f.call("has_flag", "submerged"))


static func mode_view_state(m: MatchMode) -> Dictionary:
	if m != null and m.has_method("view_state"):
		var v = m.call("view_state")
		if typeof(v) == TYPE_DICTIONARY:
			return v
	return {}


static func mode_hud_state(m: MatchMode) -> Dictionary:
	if m != null and m.has_method("hud_state"):
		var v = m.call("hud_state")
		if typeof(v) == TYPE_DICTIONARY:
			return v
	return {}


# ---- snapshot body ----

## gens: roster generation per slot (0 = empty), from the server's roster tracker.
static func encode_body(sim: MatchSim, gens: PackedByteArray) -> PackedByteArray:
	var w := NetWriter.new()
	var n := mini(sim.fighters.size(), NetProtocol.MAX_SLOTS)
	w.u8(n)
	for i in n:
		var g := int(gens[i]) if i < gens.size() else 0
		var f := sim.fighters[i]
		if g == 0 or is_despawned(f):
			w.u8(0)
			continue
		w.u8(g)
		_encode_fighter(w, f)
	# effect entities (hazard zones are static arena data and are not replicated)
	var ents: Array = []
	for e in sim.effects.entities:
		var ed: Dictionary = e
		var spec = ed.get("e", {})
		if typeof(spec) == TYPE_DICTIONARY and (spec as Dictionary).has("hazard"):
			continue
		ents.append(ed)
		if ents.size() >= MAX_ENTITIES:
			break
	w.u8(ents.size())
	for e in ents:
		var ed2: Dictionary = e
		w.u16(int(ed2.get("id", 0)) & 0xFFFF)
		var kind := str(ed2.get("kind", ""))
		var kc := KINDS.find(kind)
		w.u8(kc if kc >= 0 else 255)
		if kc < 0:
			w.text(kind, 24)
		w.text(str(ed2.get("zone_kind", ed2.get("prop", ""))), 32)
		w.text(str(ed2.get("vfx", "")), 24)
		w.vec3q(ed2.get("pos", Vector3.ZERO))
		w.u16(clampi(roundi(float(ed2.get("radius", 0.25)) * 100.0), 0, 65535))
		w.text(str(ed2.get("element", "")), 24)
		w.i8(int(ed2.get("team", -1)))
	# dynamic props (static ones never move; ArenaView builds them from the arena definition)
	var props: Array = sim.arena_nodes.get("props", [])
	var dyn: Array = sim.arena_nodes.get("dynamic_props", [])
	var pcount := 0
	var pw := NetWriter.new()
	for i in mini(props.size(), 255):
		var pn = props[i]
		if not is_instance_valid(pn) or not (pn is Node3D) or not dyn.has(pn):
			continue
		var p3: Node3D = pn
		pw.u8(i)
		pw.vec3q(p3.global_position)
		pw.quat32(p3.global_basis.get_rotation_quaternion())
		pcount += 1
		if pcount >= MAX_PROPS:
			break
	w.u8(pcount)
	w.raw(pw.data())
	_encode_mode(w, sim)
	return w.data()


static func _q10(v: float) -> int:
	return clampi(roundi(v * 10.0), 0, 65535)


static func _encode_fighter(w: NetWriter, f: Fighter) -> void:
	w.u8(f.state)
	var flags := 0
	if f.time < f.juiced_until:
		flags |= F_JUICED
	if f.is_evading():
		flags |= F_EVADING
	if f.time < f.crash_until:
		flags |= F_CRASH
	if f.guard_held:
		flags |= F_GUARD
	if f.rig.grounded:
		flags |= F_GROUNDED
	if f.controller_kind == "bot" or f.controller_kind == "policy":
		flags |= F_AI
	if is_hidden(f):
		flags |= F_HIDDEN
	w.u8(flags)
	var bodies := f.rig.bodies
	w.vec3q(bodies[0].global_position)
	var nseg := mini(bodies.size(), NetProtocol.MAX_SEGMENTS)
	w.u8(nseg)
	for s in nseg:
		w.quat32(bodies[s].global_basis.get_rotation_quaternion())
	w.u16(_q10(f.health))
	w.u16(_q10(f.max_health))
	w.u16(_q10(f.stamina))
	w.u16(_q10(f.max_stamina))
	w.u16(_q10(f.poise))
	w.u16(_q10(f.max_poise))
	w.u8(clampi(roundi(f.hype * 2.55), 0, 255))
	w.i8(f.lives)
	w.i8(f.target.index if f.target != null and is_instance_valid(f.target) else -1)
	var cds: Array = []
	for slot in f.creature.cooldowns.keys():
		cds.append(str(slot))
	for slot in f.cooldown_left.keys():
		if not cds.has(str(slot)):
			cds.append(str(slot))
	cds = cds.slice(0, MAX_COOLDOWNS)
	w.u8(cds.size())
	for slot: String in cds:
		w.text(slot, 32)
		w.u16(clampi(roundi(float(f.cooldown_left.get(slot, 0.0)) * 100.0), 0, 65535))
	var sts: Array = f.statuses.summary()
	var ns := mini(sts.size(), MAX_STATUSES)
	w.u8(ns)
	for k in ns:
		var s: Dictionary = sts[k]
		w.text(str(s.get("id", "")), 40)
		w.text(str(s.get("element", "")), 24)
		var left := float(s.get("left", 0.0))
		w.u16(clampi(roundi(left * 100.0), 0, 65535) if is_finite(left) else 65535)


static func _encode_mode(w: NetWriter, sim: MatchSim) -> void:
	var m := sim.mode
	if m == null:
		w.u8(0)
		w.u8(0)
		w.u16(0)
		w.u8(0)
		w.i8(-2)
		w.i8(-2)
		w.u8(0)
		w.text("", 1)
		NetEventCodec.encode_value(w, {})
		NetEventCodec.encode_value(w, {})
		return
	w.u8(m.phase)
	w.u8(clampi(m.round_index, 0, 255))
	var timer := m.round_timer if is_finite(m.round_timer) else 0.0
	w.u16(clampi(roundi(maxf(timer, 0.0) * 10.0), 0, 65535))
	var flags := 0
	if sim.input_enabled:
		flags |= M_INPUT
	if sim.is_finished:
		flags |= M_FINISHED
	w.u8(flags)
	w.i8(m.winner_team)
	w.i8(m.round_winner)
	var teams: Array = []
	for t in m.round_wins.keys():
		if not teams.has(int(t)):
			teams.append(int(t))
	for t in m.scores.keys():
		if not teams.has(int(t)):
			teams.append(int(t))
	teams.sort()
	teams = teams.slice(0, 16)
	w.u8(teams.size())
	for t: int in teams:
		w.i8(t)
		w.u8(clampi(int(m.round_wins.get(t, 0)), 0, 255))
		w.i16(int(m.scores.get(t, 0)))
	w.text(m.hud_status(), 160)
	NetEventCodec.encode_value(w, mode_view_state(m))
	NetEventCodec.encode_value(w, mode_hud_state(m))


## Decodes the shared body. Returns {} and sets r.ok = false on malformed data.
static func decode_body(r: NetReader) -> Dictionary:
	var out := {"fighters": [], "entities": [], "props": [], "mode": {}}
	var n := r.count(NetProtocol.MAX_SLOTS)
	var fighters: Array = []
	for i in n:
		var g := r.u8()
		if g == 0:
			fighters.append({"gen": 0})
			continue
		var fd := {"gen": g}
		var st := r.u8()
		if st >= Fighter.STATE_NAMES.size():
			r.fail("bad fighter state %d" % st)
		fd["state"] = st
		fd["flags"] = r.u8()
		fd["root"] = r.vec3q()
		var nseg := r.count(NetProtocol.MAX_SEGMENTS)
		var rots: Array[Quaternion] = []
		for s in nseg:
			rots.append(r.quat32())
		fd["rots"] = rots
		fd["health"] = r.u16() / 10.0
		fd["max_health"] = maxf(r.u16() / 10.0, 0.1)
		fd["stamina"] = r.u16() / 10.0
		fd["max_stamina"] = maxf(r.u16() / 10.0, 0.1)
		fd["poise"] = r.u16() / 10.0
		fd["max_poise"] = maxf(r.u16() / 10.0, 0.1)
		fd["hype"] = r.u8() / 2.55
		fd["lives"] = r.i8()
		fd["target"] = r.i8()
		var cds := {}
		var nc := r.count(MAX_COOLDOWNS)
		for k in nc:
			var slot := r.text(32)
			cds[slot] = r.u16() / 100.0
		fd["cooldowns"] = cds
		var sts: Array = []
		var nst := r.count(MAX_STATUSES)
		for k in nst:
			var sid := r.text(40)
			var el := r.text(24)
			sts.append({"id": sid, "element": el, "left": r.u16() / 100.0})
		fd["statuses"] = sts
		if not r.ok:
			return {}
		fighters.append(fd)
	out["fighters"] = fighters
	var ents: Array = []
	var ne := r.count(MAX_ENTITIES)
	for k in ne:
		var eid := r.u16()
		var kc := r.u8()
		var kind: String = r.text(24) if kc == 255 else (str(KINDS[kc]) if kc < KINDS.size() else "zone")
		var sub := r.text(32)
		var vfx_id := r.text(24)
		var pos := r.vec3q()
		var rad := r.u16() / 100.0
		var el2 := r.text(24)
		var team := r.i8()
		var ent := {"id": eid, "kind": kind, "pos": pos, "radius": rad, "element": el2, "team": team, "vfx": vfx_id, "e": {}}
		if kind == "prop":
			ent["prop"] = sub
		elif sub != "":
			ent["zone_kind"] = sub
		ents.append(ent)
	out["entities"] = ents
	var props: Array = []
	var np := r.count(MAX_PROPS)
	for k in np:
		var idx := r.u8()
		var ppos := r.vec3q()
		var prot := r.quat32()
		props.append({"index": idx, "pos": ppos, "rot": prot})
	out["props"] = props
	var mode := {}
	mode["phase"] = r.u8()
	mode["round"] = r.u8()
	mode["timer"] = r.u16() / 10.0
	mode["flags"] = r.u8()
	mode["winner"] = r.i8()
	mode["round_winner"] = r.i8()
	var teams: Array = []
	var nt := r.count(16)
	for k in nt:
		var t := r.i8()
		var wins := r.u8()
		var score := r.i16()
		teams.append({"team": t, "wins": wins, "score": score})
	mode["teams"] = teams
	mode["status"] = r.text(160)
	var budget: Array = [NetEventCodec.MAX_VALUES]
	var vs = NetEventCodec.decode_value(r, 0, budget)
	var hs = NetEventCodec.decode_value(r, 0, budget)
	mode["view"] = vs if typeof(vs) == TYPE_DICTIONARY else {}
	mode["hud"] = hs if typeof(hs) == TYPE_DICTIONARY else {}
	out["mode"] = mode
	if not r.ok:
		return {}
	return out


## Rebuilds every segment's world transform from the root position and segment rotations
## (origin_i = origin_parent + rot_parent * (pivot_i - pivot_parent)).
static func fk(body: BodyDef, root: Vector3, rots: Array[Quaternion]) -> Array[Transform3D]:
	var n := mini(body.segments.size(), rots.size())
	var out: Array[Transform3D] = []
	out.resize(n)
	for i in n:
		var s: BodyDef.Seg = body.segments[i]
		var q := rots[i]
		var origin := root
		if s.parent >= 0 and s.parent < i:
			var p: BodyDef.Seg = body.segments[s.parent]
			origin = out[s.parent].origin + rots[s.parent] * (s.pivot - p.pivot)
		out[i] = Transform3D(Basis(q), origin)
	return out


# ---- roster (reliable): which creature/body occupies each slot ----

## entries: [{slot, gen, creature, scale, team, name, kind, despawned, tags: [names of true
## boolean fighter flags, e.g. "headliner", "boss", "resting"]}]
static func encode_roster(w: NetWriter, entries: Array) -> void:
	var n := mini(entries.size(), NetProtocol.MAX_SLOTS)
	w.u8(n)
	for i in n:
		var e: Dictionary = entries[i]
		w.u8(int(e["slot"]))
		w.u8(int(e["gen"]))
		w.text(str(e["creature"]), 64)
		w.f32(float(e["scale"]))
		w.i8(int(e["team"]))
		w.text(str(e["name"]), 80)
		w.text(str(e["kind"]), 16)
		w.boolean(bool(e["despawned"]))
		var tags: Array = e.get("tags", [])
		var nt := mini(tags.size(), 8)
		w.u8(nt)
		for k in nt:
			w.text(str(tags[k]), 24)


## Names of a fighter's true boolean flags (presentation hints; "_private" ones excluded).
static func flag_tags(f: Fighter) -> Array:
	var out: Array = []
	for k in f.flags.keys():
		var ks := str(k)
		if ks.begins_with("_"):
			continue
		var v = f.flags[k]
		if typeof(v) == TYPE_BOOL and v:
			out.append(ks)
	out.sort()
	return out.slice(0, 8)


static func decode_roster(r: NetReader) -> Array:
	var out: Array = []
	var n := r.count(NetProtocol.MAX_SLOTS)
	for i in n:
		var e := {}
		e["slot"] = r.u8()
		e["gen"] = r.u8()
		e["creature"] = r.text(64)
		e["scale"] = r.f32()
		e["team"] = r.i8()
		e["name"] = r.text(80)
		e["kind"] = r.text(16)
		e["despawned"] = r.boolean()
		var tags: Array = []
		var nt := r.count(8)
		for k in nt:
			tags.append(r.text(24))
		e["tags"] = tags
		if not r.ok or int(e["slot"]) >= NetProtocol.MAX_SLOTS:
			r.fail("bad roster entry")
			return []
		out.append(e)
	return out


## Resolves the creature definition for a roster entry on the client (base content creature, or
## a scaled copy when a mode rebuilt the fighter with another body scale).
static func roster_creature(e: Dictionary) -> CreatureDef:
	var base := Content.creature(str(e.get("creature", "")))
	if base == null:
		return null
	var want := float(e.get("scale", base.body.scale))
	if absf(want - base.body.scale) > 0.001 and Content.has_method("scaled_creature"):
		var scaled = Content.call("scaled_creature", base.id, want / maxf(base.body.scale, 0.001), 1.0)
		if scaled is CreatureDef:
			return scaled
	return base


# ---- input samples (client -> server): 17 bytes core, 24 with guest counters ----

static func write_input(w: NetWriter, fi: FighterInput) -> void:
	w.i8(int(clampf(fi.move.x, -1.0, 1.0) * 127.0))
	w.i8(int(clampf(fi.move.z, -1.0, 1.0) * 127.0))
	var count := fi.wire_counter_count()
	w.u32((fi.held & ((1 << FighterInput.BUTTON_COUNT) - 1)) | (FighterInput.WIRE_EXTENDED if count == FighterInput.BUTTON_COUNT else 0))
	var pc := fi.press_count
	if pc.size() != FighterInput.BUTTON_COUNT:
		pc = pc.duplicate()
		pc.resize(FighterInput.BUTTON_COUNT)
	w.raw(pc.slice(0, count))


## Reads one sample; move is clamped to unit length and held bits masked (never trusted).
static func read_input(r: NetReader) -> FighterInput:
	var fi := FighterInput.new()
	var mx := r.i8()
	var mz := r.i8()
	fi.move = Vector3(clampf(mx / 127.0, -1.0, 1.0), 0.0, clampf(mz / 127.0, -1.0, 1.0))
	if fi.move.length() > 1.0:
		fi.move = fi.move.normalized()
	var word := r.u32()
	fi.held = word & ((1 << FighterInput.BUTTON_COUNT) - 1)
	var count := FighterInput.BUTTON_COUNT if word & FighterInput.WIRE_EXTENDED else FighterInput.CORE_BUTTON_COUNT
	var pc := r.raw(count)
	if pc.size() == count:
		for b in count:
			fi.press_count[b] = pc[b]
	return fi
