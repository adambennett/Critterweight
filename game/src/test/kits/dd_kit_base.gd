extends TestCase
## Shared harness for the Dredge / Dozer kit tests (test_kit_f_dredge.gd, test_kit_f_dozer.gd).
##
## measure_move() starts one move on fighter 0 against a standing dummy (fighter 1) at a given
## root-to-root gap and records what a player would care about: hits (melee / effects), damage,
## the dummy's knockback displacement and rise, statuses and build-up, plus the attacker's
## physical sanity (uprightness, yaw error, segment self-penetration, weapon distance from the
## root for the 1.6 m reach cap, cage escapes). spar() runs bot-vs-bot bouts for balance checks.
## Gaps are root-to-root; the default dummy is dev_biped (74 kg, 1.7 m), `dummy(100)` rescales it
## to the ROSTER's 100 kg knockback reference. Each measurement runs in its own physics world,
## which is freed afterwards unless opts.keep is set (then call release(res)).

const DT := 1.0 / 120.0
const REACH_CAP := 1.6


func dummy(mass := 0.0) -> CreatureDef:
	var d := Content.creature("dev_biped")
	if mass > 0.0:
		d = Content.scaled_creature("dev_biped", 1.0, mass / d.body.total_mass)
	return d


func creature_of(c) -> CreatureDef:
	return c if c is CreatureDef else Content.creature(str(c))


## A two-fighter sim on an octagon. Fighter 0 at -Z faces +Z; fighter 1 sits `gap` ahead (plus
## b_offset, fighter-0 space) facing back. No intro phase.
func kit_sim(a, b, gap := 1.5, sa: InputSource = null, sb: InputSource = null, rules := {}, radius := 6.0, b_offset := Vector3.ZERO, b_yaw := 180.0) -> MatchSim:
	var r := {"rounds": 1, "round_time": 0, "intro_time": 0.0}
	r.merge(rules, true)
	var arena := ArenaDef.from_dict({"id": "kit", "base": "octagon", "radius": radius,
		"spawns": [[0, -gap * 0.5, 0], [b_offset.x, gap * 0.5 + b_offset.z, b_yaw]]})
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	sim.setup({"arena": arena, "rules": r, "seed": 3,
		"fighters": [{"creature": creature_of(a), "team": 0, "source": sa}, {"creature": creature_of(b), "team": 1, "source": sb}]})
	return sim


func release(res_or_sim) -> void:
	var sim: MatchSim = res_or_sim["sim"] if res_or_sim is Dictionary else res_or_sim
	if is_instance_valid(sim) and sim.get_parent():
		sim.get_parent().queue_free()


## Steps the sim; `probe` (optional Callable(t)) is called after every tick.
func run(sim: MatchSim, seconds: float, probe := Callable()) -> void:
	var n := int(round(seconds / DT))
	for i in n:
		sim.step(DT)
		await get_tree().physics_frame
		if probe.is_valid():
			probe.call((i + 1) * DT)


func start(f: Fighter, slot: String) -> void:
	var c := f.creature
	if c.abilities.has(slot):
		f._start_move(c.abilities[slot], slot, Fighter.State.ABILITY)
	else:
		f._start_move(c.moves[slot], slot, Fighter.State.ATTACK)


func count_events(events: Array, type: String, key := "", val = null) -> int:
	var n := 0
	for ev in events:
		if ev["type"] == type and (key == "" or ev.get(key) == val):
			n += 1
	return n


## Starts `slot` on fighter 0 after `settle` s and records the outcome. opts: dummy (CreatureDef),
## settle, dur (seconds after the start), rules, radius, b_offset, b_yaw, sb (dummy input),
## before (Callable(sim) run right before the move starts), via (Scripted steps for fighter 0,
## times relative to the start, replacing the direct start), keep (keep the world alive).
func measure_move(cid: String, slot: String, gap: float, opts := {}) -> Dictionary:
	var d: CreatureDef = opts.get("dummy", dummy())
	var settle := float(opts.get("settle", 0.4))
	var sa: InputSource = null
	if opts.has("via"):
		var steps := []
		for st in opts["via"]:
			var s2: Dictionary = (st as Dictionary).duplicate()
			var t0 := float(s2.get("t0", 0.0))
			s2["t0"] = t0 + settle + 0.02   # strictly after the settle phase
			s2["t1"] = float(s2.get("t1", t0 + 0.03)) + settle + 0.02
			steps.append(s2)
		sa = InputSource.Scripted.new(steps)
	var sim := kit_sim(cid, d, gap, sa, opts.get("sb"), opts.get("rules", {}), float(opts.get("radius", 6.0)),
		opts.get("b_offset", Vector3.ZERO), float(opts.get("b_yaw", 180.0)))
	var a := sim.fighters[0]
	var b := sim.fighters[1]
	await run(sim, settle)
	if opts.has("before"):
		(opts["before"] as Callable).call(sim)
	var res := {"sim": sim, "a": a, "b": b, "hits": [], "melee": [], "effect_hits": [], "first_hit_t": -1.0,
		"max_reach": 0.0, "min_up": 1.0, "max_yaw_err": 0.0, "max_pen": 0.0, "base_pen": self_penetration(a), "b_rise": 0.0,
		"b_states": {}, "kb": 0.0, "b_start": b.pos(), "a_start": a.pos(), "escaped": false, "max_w": 0.0,
		"_cursor": sim.event_seq, "_b_hit_pos": Vector3.INF, "_b0y": b.pos().y, "_t0": sim.time, "slots": []}
	if not opts.has("via"):
		start(a, slot)
	var weapons := PackedStringArray()
	var mv: MoveDef = a.creature.abilities.get(slot, a.creature.moves.get(slot))
	if mv:
		for w in mv.windows:
			for wn in w["weapons"]:
				if not weapons.has(wn):
					weapons.append(wn)
	res["weapons"] = weapons
	var dur := float(opts.get("dur", (mv.duration if mv else 1.0) + 1.2))
	await run(sim, dur, _probe.bind(res))
	var bhp: Vector3 = res["_b_hit_pos"]
	if bhp != Vector3.INF:
		res["kb"] = Vector2(b.pos().x - bhp.x, b.pos().z - bhp.z).length()
	res["damage"] = 0.0
	for h in res["hits"]:
		res["damage"] = float(res["damage"]) + float(h["damage"])
	res["melee_damage"] = 0.0
	for h in res["melee"]:
		res["melee_damage"] = float(res["melee_damage"]) + float(h["damage"])
	res["events"] = sim.events.duplicate()
	res["b_health"] = b.health
	res["b_buildup"] = b.statuses.buildup.duplicate()
	res["a_disp"] = a.pos() - Vector3(res["a_start"])
	if not bool(opts.get("keep", false)):
		release(res)
	return res


func _probe(_t: float, res: Dictionary) -> void:
	var sim: MatchSim = res["sim"]
	var a: Fighter = res["a"]
	var b: Fighter = res["b"]
	for ev in sim.events_since(int(res["_cursor"])):
		res["_cursor"] = int(ev["seq"])
		if ev["type"] == "move_start" and int(ev.get("fighter", -1)) == 0:
			res["slots"].append(str(ev["slot"]))
		if ev["type"] == "hit" and int(ev.get("fighter", -1)) == 0 and int(ev.get("target", -1)) == 1:
			res["hits"].append(ev)
			if str(ev.get("slot", "")) == "effect":
				res["effect_hits"].append(ev)
			else:
				res["melee"].append(ev)
			if float(res["first_hit_t"]) < 0.0:
				res["first_hit_t"] = sim.time - float(res["_t0"])
				res["_b_hit_pos"] = b.pos()
		if ev["type"] == "escaped":
			res["escaped"] = true
	res["b_states"][b.state_name()] = true
	if float(res["first_hit_t"]) >= 0.0 and b.state == Fighter.State.HITSTUN:
		res["b_stun_time"] = float(res.get("b_stun_time", 0.0)) + DT
	res["b_rise"] = maxf(float(res["b_rise"]), b.pos().y - float(res["_b0y"]))
	if a.state in [Fighter.State.ATTACK, Fighter.State.ABILITY, Fighter.State.TAUNT, Fighter.State.GRABBING]:
		res["min_up"] = minf(float(res["min_up"]), a.rig.root().global_basis.y.dot(Vector3.UP))
		res["max_yaw_err"] = maxf(float(res["max_yaw_err"]), absf(rad_to_deg(MathX.wrap_angle(a.rig.actual_yaw() - a.facing_yaw))))
		res["max_pen"] = maxf(float(res["max_pen"]), self_penetration(a))
		for rb in a.rig.bodies:
			res["max_w"] = maxf(float(res["max_w"]), rb.angular_velocity.length())
		for wn in res["weapons"]:
			var w: BodyDef.Weapon = a.creature.body.weapons[wn]
			var wp := a.rig.bodies[w.seg].global_transform * w.local
			res["max_reach"] = maxf(float(res["max_reach"]), wp.distance_to(a.pos()))


## Deepest overlap (m) between hurt shapes of two segments of the same rig that are not parent and
## child (a self-clip). Legs are skipped (the gait crosses them under the body by design).
func self_penetration(f: Fighter) -> float:
	var body := f.creature.body
	var worst := 0.0
	var segs: Array = body.segments
	for i in segs.size():
		var si: BodyDef.Seg = segs[i]
		if si.part == "leg":
			continue
		var ti := f.rig.bodies[i].global_transform
		for j in range(i + 1, segs.size()):
			var sj: BodyDef.Seg = segs[j]
			if sj.part == "leg" or sj.parent == i or si.parent == j:
				continue
			var tj := f.rig.bodies[j].global_transform
			for sha: BodyDef.Shape in si.shapes:
				for shb: BodyDef.Shape in sj.shapes:
					var dd := seg_seg_dist(ti * sha.hit_a, ti * sha.hit_b, tj * shb.hit_a, tj * shb.hit_b) - sha.hit_r - shb.hit_r
					worst = maxf(worst, -dd)
	return worst


static func seg_seg_dist(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-9 and e <= 1e-9:
		return r.length()
	if a <= 1e-9:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-9:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > 1e-9 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)


## Common physical-sanity assertions for one measured move.
func check_sane(res: Dictionary, label: String) -> void:
	check(float(res["min_up"]) > 0.85, "%s: attacker stays upright (min up %.3f)" % [label, res["min_up"]])
	check(float(res["max_yaw_err"]) < 60.0, "%s: no spin-out (max yaw error %.0f deg)" % [label, res["max_yaw_err"]])
	check(float(res["max_reach"]) <= REACH_CAP + 0.001, "%s: weapon within the 1.6 m reach cap (%.3f m)" % [label, res["max_reach"]])
	check(float(res["max_pen"]) <= float(res["base_pen"]) + 0.08, "%s: no self-clipping (overlap %.3f m, rest %.3f m)" % [label, res["max_pen"], res["base_pen"]])
	check(not bool(res["escaped"]), "%s: stays inside the cage" % label)
	check(float(res["max_w"]) < 60.0, "%s: no segment spins wildly (max |w| %.1f rad/s)" % [label, res["max_w"]])


## Holding Heavy freezes the heavy at 0.7 x its startup while it charges: nothing may keep pushing
## the fighter forward during the hold (a lunge window covering the freeze point would).
func check_charge_hold_stationary(cid: String) -> void:
	var sim := kit_sim(cid, dummy(), 6.0, InputSource.Scripted.new([{"t0": 0.4, "t1": 0.43, "press": ["heavy"]},
		{"t0": 0.4, "t1": 1.3, "hold": ["heavy"]}]), null, {}, 8.0)
	var a := sim.fighters[0]
	await run(sim, 0.65)
	var p0 := a.pos()
	await run(sim, 0.55)
	check(a.move_slot == "heavy" and a._charging, "%s: still charging the heavy" % cid)
	var drift := Vector2(a.pos().x - p0.x, a.pos().z - p0.z).length()
	check(drift < 0.25, "%s: holding Heavy does not drift the fighter (%.2f m)" % [cid, drift])
	release(sim)


## Prints one measurement line per move against a 100 kg dummy (docs numbers) and checks that
## each move's measured knockback is within tolerance of the ROSTER metres (kb_m) when given.
## rows: [slot, gap, roster_kb_m (or -1), via (optional Scripted steps)]
func measure_table(cid: String, rows: Array) -> void:
	for row in rows:
		var opts := {"dummy": dummy(100.0), "dur": 2.6}
		if row.size() > 3:
			opts["via"] = row[3]
		var r := await measure_move(cid, str(row[0]), float(row[1]), opts)
		var first: Dictionary = r["hits"][0] if not r["hits"].is_empty() else {}
		print("MEASURE %s %-14s gap=%.2f hit_t=%.3f dmg=%.1f (%s q=%.2f) kb=%.2f m rise=%.2f stun=%.2f s hits=%d" % [cid, row[0], row[1],
			r["first_hit_t"], r["damage"], str(first.get("part", "-")), float(first.get("quality", 0.0)), r["kb"], r["b_rise"],
			float(r.get("b_stun_time", 0.0)), r["hits"].size()])
		var want := float(row[2])
		if want > 0.0:
			check(not r["hits"].is_empty(), "%s connects on the 100 kg dummy at %.2f m" % [row[0], row[1]])
			check(absf(float(r["kb"]) - want) <= maxf(0.4, want * 0.5), "%s knockback %.2f m vs ROSTER %.1f m (±50%%)" % [row[0], r["kb"], want])


## Bot-vs-bot bouts on The Gullet (1 round, decision on time). Sides alternate each bout.
## Returns {wins, draws, bouts, dmg, hits, kos, time}; mirror matches key by side.
func spar(c1: String, c2: String, bouts: int, difficulty := "pro", seed0 := 100, round_time := 99.0) -> Dictionary:
	var keys := ["side0", "side1"] if c1 == c2 else [c1, c2]
	var out := {"wins": {}, "draws": 0, "bouts": bouts, "dmg": {}, "hits": {}, "kos": {}, "time": 0.0, "used": {}}
	for k in keys:
		out["wins"][k] = 0
		out["dmg"][k] = 0.0
		out["hits"][k] = 0
		out["kos"][k] = 0
	for k in bouts:
		var flip := k % 2 == 1
		var ids := [c2, c1] if flip else [c1, c2]
		var entries := []
		for i in 2:
			var cdef := Content.creature(str(ids[i]))
			var bot := BotBrain.new(difficulty, seed0 + k * 17 + i)
			bot.set_personality(cdef.ai)
			entries.append({"creature": cdef, "team": i, "source": bot, "kind": "bot"})
		var sim := MatchSim.new()
		sim.running = false
		fresh_world().add_child(sim)
		sim.setup({"arena": Content.arena("the_gullet"), "rules": {"rounds": 1, "round_time": round_time, "intro_time": 0.3, "sudden_death": false},
			"seed": seed0 + k, "fighters": entries})
		var limit := round_time + 6.0
		var cursor := 0
		var used_i := [{}, {}]
		while not sim.is_finished and sim.time < limit:
			sim.step(DT)
			await get_tree().physics_frame
			for ev in sim.events_since(cursor):
				cursor = int(ev["seq"])
				var fi := int(ev.get("fighter", -1))
				if fi < 0 or fi > 1:
					continue
				var tag := ""
				if ev["type"] == "ability":
					tag = str(ev["slot"])
				elif ev["type"] in ["juice", "grab", "throw", "counter", "splat", "wall_bonk", "dodge"]:
					tag = str(ev["type"])
				elif ev["type"] == "move_start" and str(ev["slot"]).begins_with("heavy_charged"):
					tag = "charged"
				if tag != "":
					used_i[fi][tag] = int(used_i[fi].get(tag, 0)) + 1
		var w := int(sim.result.get("winner_team", -1)) if sim.is_finished else -1
		for i in 2:
			var key: String = keys[i] if c1 == c2 else str(ids[i])   # mirrors: by spawn side
			var f := sim.fighters[i]
			var used: Dictionary = out["used"].get(key, {})
			for tag in used_i[i]:
				used[tag] = int(used.get(tag, 0)) + int(used_i[i][tag])
			out["used"][key] = used
			out["dmg"][key] = float(out["dmg"][key]) + float(f.stats_record["damage_dealt"])
			out["hits"][key] = int(out["hits"][key]) + int(f.stats_record["hits"])
			out["kos"][key] = int(out["kos"][key]) + int(f.stats_record["kos"])
			if w == i:
				out["wins"][key] = int(out["wins"][key]) + 1
		if w < 0:
			out["draws"] = int(out["draws"]) + 1
		out["time"] = float(out["time"]) + sim.time
		release(sim)
	return out


func spar_summary(r: Dictionary) -> String:
	var parts := []
	for key in r["wins"]:
		var hits := maxi(1, int(r["hits"][key]))
		parts.append("%s %d wins, %.0f dmg in %d hits (%.1f/hit), %d KOs, used %s" % [key, r["wins"][key], r["dmg"][key], r["hits"][key],
			float(r["dmg"][key]) / hits, r["kos"][key], str(r["used"].get(key, {}))])
	return "%d bouts: %s; %d draws; avg %.0f s" % [r["bouts"], "; ".join(parts), r["draws"], float(r["time"]) / maxf(1.0, float(r["bouts"]))]
