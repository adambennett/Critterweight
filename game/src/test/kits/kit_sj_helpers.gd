extends TestCase
## Shared helpers for the Slurry / Jitters kit tests (test_kit_f_slurry.gd, test_kit_f_jitters.gd,
## test_kit_extensions_sj.gd). Builds small headless duels driven by InputSource.Scripted and
## summarizes what happened: hit/effect events, the attacker's uprightness, angular velocity, the
## distance of every ACTIVE weapon point from its root (ROSTER 1.6 m reach cap), the lowest segment,
## cage containment, and what the dummy (fighter 1) went through (states, build-up, statuses,
## displacement after the first hit). Not a test file itself (no test_ prefix).

const INTRO := 0.2           ## rules intro_time used by every duel (inputs live after this)
const T := 0.5               ## first press time in scripted steps (intro + settle)
const REACH_CAP := 1.6
const KB_LOOK := 0.45        ## seconds after the first hit at which displacement is measured
const EL_STATUS := {"sludge": "gunked", "static": "jolted"}


## A creature by id, optionally re-parsed with a different light string (to test L2/L3 alone).
func creature(id: String, light_string: Array = []) -> CreatureDef:
	if light_string.is_empty():
		return Content.creature(id)
	var c := CreatureDef.from_dict(Content.creature_entry(id))
	c.light_string = light_string
	return c


## Two fighters facing each other `gap` metres apart (root to root) in an octagon of `radius`,
## or custom spawns ([[x, z, yaw_deg], ...]) with extra fighters (each on its own team).
func duel(a, b, gap: float, a_steps: Array, b_steps: Array = [], spawns: Array = [], extra: Array = [], radius := 6.0) -> MatchSim:
	var sp: Array = spawns if not spawns.is_empty() else [[0, -gap * 0.5, 0], [0, gap * 0.5, 180]]
	var arena := ArenaDef.from_dict({"id": "kit_test", "base": "octagon", "radius": radius, "spawns": sp})
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var fl := [{"creature": a if a is CreatureDef else Content.creature(str(a)), "team": 0, "source": InputSource.Scripted.new(a_steps)},
		{"creature": b if b is CreatureDef else Content.creature(str(b)), "team": 1, "source": InputSource.Scripted.new(b_steps)}]
	for i in extra.size():
		fl.append({"creature": Content.creature(str(extra[i])), "team": 2 + i, "source": InputSource.Scripted.new([])})
	sim.setup({"arena": arena, "rules": {"rounds": 1, "round_time": 0, "intro_time": INTRO}, "seed": 11, "fighters": fl})
	return sim


## Steps `seconds` and returns a summary of fighter 0 (the attacker), fighter 1 (the dummy) and
## all events. `key` selects which damaging hit of fighter 0 on fighter 1 counts as "the" hit for
## the displacement measurements (slot or effect id; "" = the first damaging hit).
func run(sim: MatchSim, seconds: float, key := "") -> Dictionary:
	var st := {"events": [], "hits": [], "min_up": 1.0, "max_w": 0.0, "max_reach": 0.0, "reach_weapon": "",
		"min_y": 99.0, "outside": false, "states": {}, "d_states": {}, "d_buildup": {}, "d_statuses": {},
		"hit_t": -1.0, "a_at_hit": Vector3.ZERO, "d_at_hit": Vector3.ZERO, "a_after": Vector3.ZERO,
		"d_after": Vector3.ZERO, "after_taken": false, "d_max_y": -99.0, "d_start": Vector3.ZERO, "a_start": Vector3.ZERO,
		"d_min_stamina": 999.0, "a_max_z": -99.0}
	var dt := 1.0 / Engine.physics_ticks_per_second
	var n := int(seconds / dt)
	var cursor := 0
	var f0 := sim.fighters[0]
	var f1 := sim.fighters[1]
	# step in phase with physics no matter where the caller was (as TestCase.step_sim does)
	if not Engine.is_in_physics_frame():
		await get_tree().physics_frame
	for i in n:
		sim.step(dt)
		await get_tree().physics_frame
		if i == int(INTRO / dt):
			st["d_start"] = f1.pos()
			st["a_start"] = f0.pos()
		for ev in sim.events_since(cursor):
			cursor = int(ev["seq"])
			st["events"].append(ev)
			if str(ev["type"]) == "hit":
				st["hits"].append(ev)
				if float(st["hit_t"]) < 0.0 and int(ev.get("fighter", -1)) == 0 and int(ev.get("target", -1)) == 1 \
						and float(ev["damage"]) > 0.0 and _key_match(ev, key):
					st["hit_t"] = sim.time
					st["a_at_hit"] = f0.pos()
					st["d_at_hit"] = f1.pos()
		if float(st["hit_t"]) >= 0.0 and not bool(st["after_taken"]) and sim.time >= float(st["hit_t"]) + KB_LOOK:
			st["after_taken"] = true
			st["a_after"] = f0.pos()
			st["d_after"] = f1.pos()
		var up := f0.rig.root().global_basis.y.dot(Vector3.UP)
		st["min_up"] = minf(float(st["min_up"]), up)
		for rb in f0.rig.bodies:
			st["max_w"] = maxf(float(st["max_w"]), rb.angular_velocity.length())
			st["min_y"] = minf(float(st["min_y"]), rb.global_position.y)
		if f0.move and (f0.state == Fighter.State.ATTACK or f0.state == Fighter.State.ABILITY):
			for wn in f0.move.window_weapons(f0.state_time):
				var w: BodyDef.Weapon = f0.creature.body.weapons.get(wn)
				if w:
					var d := (f0.rig.bodies[w.seg].global_transform * w.local).distance_to(f0.pos())
					if d > float(st["max_reach"]):
						st["max_reach"] = d
						st["reach_weapon"] = "%s:%s" % [f0.move_slot, wn]
		if not sim.arena.inside(f0.pos(), -0.05):
			st["outside"] = true
		st["states"][f0.state_name()] = true
		st["d_states"][f1.state_name()] = true
		st["d_max_y"] = maxf(float(st["d_max_y"]), f1.pos().y)
		st["d_min_stamina"] = minf(float(st["d_min_stamina"]), f1.stamina)
		st["a_max_z"] = maxf(float(st["a_max_z"]), f0.pos().z)
		for el in f1.statuses.buildup:
			st["d_buildup"][el] = maxf(float(st["d_buildup"].get(el, 0.0)), float(f1.statuses.buildup[el]))
		for s in f1.statuses.active:
			st["d_statuses"][str(s.get("id", ""))] = true
	return st


func _key_match(ev: Dictionary, key: String) -> bool:
	if key == "":
		return true
	var mv := str(ev.get("move", ""))
	return str(ev.get("slot", "")) == key or mv == key or mv.ends_with("." + key)


## Hit events dealt by fighter `idx` whose slot (melee) or move id (effects) matches `key`.
func hits(st: Dictionary, idx: int, key: String, target := -1) -> Array:
	var out := []
	for ev in st["hits"]:
		if int(ev.get("fighter", -1)) != idx or float(ev["damage"]) <= 0.0:
			continue
		if target >= 0 and int(ev["target"]) != target:
			continue
		if _key_match(ev, key):
			out.append(ev)
	return out


func events(st: Dictionary, type: String, key := "", val = null) -> Array:
	var out := []
	for ev in st["events"]:
		if str(ev["type"]) == type and (key == "" or ev.get(key) == val):
			out.append(ev)
	return out


func total_damage(evs: Array) -> float:
	var s := 0.0
	for ev in evs:
		s += float(ev["damage"])
	return s


## Horizontal displacement of the dummy after the counted hit, along the attacker -> dummy line
## (positive = pushed away, negative = pulled in).
func kb_along(st: Dictionary) -> float:
	var a: Vector3 = st["a_at_hit"]
	var d0: Vector3 = st["d_at_hit"]
	var d1: Vector3 = st["d_after"]
	var dir := Vector3(d0.x - a.x, 0.0, d0.z - a.z)
	if dir.length_squared() < 1e-6:
		return 0.0
	return Vector3(d1.x - d0.x, 0.0, d1.z - d0.z).dot(dir.normalized())


## Horizontal movement of the attacker after the counted hit, away from the dummy (bounce-back).
func attacker_back(st: Dictionary) -> float:
	var a0: Vector3 = st["a_at_hit"]
	var a1: Vector3 = st["a_after"]
	var d: Vector3 = st["d_at_hit"]
	var dir := Vector3(a0.x - d.x, 0.0, a0.z - d.z)
	if dir.length_squared() < 1e-6:
		return 0.0
	return Vector3(a1.x - a0.x, 0.0, a1.z - a0.z).dot(dir.normalized())


## Physical sanity of the attacker over a run that ended with the move finished and settled.
func check_sane(st: Dictionary, f: Fighter, label: String) -> void:
	check(float(st["max_reach"]) <= REACH_CAP + 0.02, "%s: active weapon %s reached %.2f m from the root (cap %.1f)" % [label, st["reach_weapon"], float(st["max_reach"]), REACH_CAP])
	check(float(st["min_up"]) > 0.2, "%s: root tipped past ~78 deg (min up %.2f)" % [label, float(st["min_up"])])
	check(float(st["max_w"]) < 60.0, "%s: a segment spun at %.1f rad/s (spin-out)" % [label, float(st["max_w"])])
	check(float(st["min_y"]) > -0.05, "%s: a segment sank through the floor (y %.2f)" % [label, float(st["min_y"])])
	check(not bool(st["outside"]), "%s: left the cage" % label)
	check(not f.is_down() and not f.is_out(), "%s: attacker ended %s" % [label, f.state_name()])
	check(f.rig.root().global_basis.y.dot(Vector3.UP) > 0.9, "%s: attacker did not return upright" % label)


func press(t: float, button: String) -> Dictionary:
	return {"t0": t, "press": [button]}


func hold(t0: float, t1: float, button: String) -> Dictionary:
	return {"t0": t0, "t1": t1, "press": [button], "hold": [button]}


## Moves the stick for a while (world direction, or "toward"/"away" the target).
func stick(t0: float, t1: float, dir) -> Dictionary:
	return {"t0": t0, "t1": t1, "move": dir}


## Shared per-move check: the move connects against every dummy in row "vs" ([[id, gap], ...]) and
## whiffs at "miss" against the first one. Row keys: label, steps, vs, miss, key, secs; optional:
## string (light string override), dmg [lo, hi] (first counted hit), el (element whose build-up
## must rise), kb ("away" | "pull", checked on the first dummy), stun (dummy must be staggered,
## default true), radius (arena), hype (attacker start Hype). Returns the first dummy's summary.
func check_move_row(id: String, row: Dictionary) -> Dictionary:
	var label := str(row["label"])
	var c := creature(id, row.get("string", []))
	var secs := float(row.get("secs", 2.5))
	var key := str(row["key"])
	var first := {}
	var vs: Array = row["vs"]
	for k in vs.size():
		var dummy := str(vs[k][0])
		var gap := float(vs[k][1])
		var tag := "%s vs %s @%.1f m" % [label, dummy, gap]
		var sim := duel(c, dummy, gap, row["steps"], row.get("bsteps", []), [], [], float(row.get("radius", 6.0)))
		if row.has("hype"):
			sim.fighters[0].hype = float(row["hype"])
		var st := await run(sim, secs, key)
		var hs := hits(st, 0, key, 1)
		if check(not hs.is_empty(), "%s: no hit (hits: %s)" % [tag, _hit_summary(st)]):
			var dmg := float(hs[0]["damage"])
			if row.has("dmg"):
				var lim: Array = row["dmg"]
				check(dmg >= float(lim[0]) and dmg <= float(lim[1]), "%s: damage %.2f outside [%.1f, %.1f] (part %s, q %.2f)" % [tag, dmg, float(lim[0]), float(lim[1]), str(hs[0]["part"]), float(hs[0]["quality"])])
			if row.has("el"):
				var el := str(row["el"])
				var bu := float(st["d_buildup"].get(el, 0.0))
				# engine rule: build-up never lands on a fighter that is down, including the hit that floored it
				var floored: bool = st["d_states"].has("knockdown")
				check(bu > 0.0 or floored or st["d_statuses"].has(str(EL_STATUS.get(el, ""))), "%s: no %s build-up on the dummy" % [tag, el])
			if bool(row.get("stun", true)):
				check(st["d_states"].has("hitstun") or st["d_states"].has("knockdown") or st["d_states"].has("down"), "%s: dummy never staggered (states %s)" % [tag, str(st["d_states"].keys())])
			if k == 0:
				match str(row.get("kb", "")):
					"away":
						check(kb_along(st) > 0.08, "%s: dummy not pushed away (%.2f m)" % [tag, kb_along(st)])
					"pull":
						check(kb_along(st) < -0.08, "%s: dummy not pulled in (%.2f m)" % [tag, kb_along(st)])
		check_sane(st, sim.fighters[0], tag)
		if k == 0:
			first = st
		sim.queue_free()
	if row.has("miss"):
		var dummy0 := str(vs[0][0])
		var sim2 := duel(c, dummy0, float(row["miss"]), row["steps"], row.get("bsteps", []), [], [], float(row.get("radius", 6.0)))
		if row.has("hype"):
			sim2.fighters[0].hype = float(row["hype"])
		var st2 := await run(sim2, secs, key)
		check(hits(st2, 0, key, 1).is_empty(), "%s: still hit %s at %.2f m (should whiff)" % [label, dummy0, float(row["miss"])])
		check_sane(st2, sim2.fighters[0], label + " (whiff)")
		sim2.queue_free()
	return first


func _hit_summary(st: Dictionary) -> String:
	var parts := PackedStringArray()
	for ev in st["hits"]:
		parts.append("f%d->f%d %s/%s %.1f" % [int(ev.get("fighter", -1)), int(ev["target"]), str(ev.get("slot", "")), str(ev.get("move", "")), float(ev["damage"])])
	return ", ".join(parts) if not parts.is_empty() else "none"
