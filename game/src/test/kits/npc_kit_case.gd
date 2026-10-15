extends TestCase
## Shared helpers for the NPC kit tests (test_kit_npc_kid_lamprey.gd, test_kit_minions.gd,
## test_kit_bosses.gd): scripted shots of one move against a standing dummy with the
## measurements every kit check needs (hits, damage, push, lift, weapon reach, uprightness,
## target states), and concurrent headless bot bouts for the balance checks.
## Not a test file itself (no "test_" prefix); test files extend it by path.
##
## Fighter 0 is the attacker at z = -gap/2 facing +Z, fighter 1 the dummy at z = +gap/2 facing
## it: `gap` is the root-to-root distance. Inputs are InputSource.Scripted steps
## ({"t0", "t1", "press": [...], "hold": [...], "move": Vector3 | "to_target" | "away"}).

const RULES := {"rounds": 1, "round_time": 0, "intro_time": 0.0}
const SETTLE := 0.4            ## seconds the bodies settle before the first scripted input


## A two-fighter sim on an open octagon (walls 2.4 m) of the given apothem.
func duel(a, b, gap: float, src_a: InputSource = null, src_b: InputSource = null, radius := 6.0, rules := {}, seed_value := 3) -> MatchSim:
	var arena := ArenaDef.from_dict({"id": "kit", "base": "octagon", "radius": radius,
		"spawns": [[0, -gap * 0.5, 0], [0, gap * 0.5, 180]]})
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var ca: CreatureDef = a if a is CreatureDef else Content.creature(str(a))
	var cb: CreatureDef = b if b is CreatureDef else Content.creature(str(b))
	var r := RULES.duplicate()
	for k in rules:
		r[k] = rules[k]
	sim.setup({"arena": arena, "rules": r, "seed": seed_value,
		"fighters": [{"creature": ca, "team": 0, "source": src_a}, {"creature": cb, "team": 1, "source": src_b}]})
	return sim


## Scripted steps shifted by SETTLE seconds (authoring convenience).
static func at(steps: Array) -> Array:
	var out := []
	for s in steps:
		var d: Dictionary = s.duplicate()
		d["t0"] = float(d.get("t0", 0.0)) + SETTLE
		if d.has("t1"):
			d["t1"] = float(d["t1"]) + SETTLE
		out.append(d)
	return out


## Plays `steps` (already shifted with at()) for fighter 0 against fighter 1 for `seconds` and
## measures the exchange. `prep` (optional) runs once after setup with the sim (set hype, flags,
## statuses...). Returned dictionary:
##   hits / blocked / parried / damage   fighter 0 -> fighter 1 hit events (all slots)
##   slots {slot: clean hits}            per-slot clean hit counts (effects use "effect")
##   events                              every sim event
##   push                                horizontal travel of fighter 1's root (m) from its
##                                       position at the first contact to 1 s later (or the end)
##   lift                                highest rise of fighter 1's root above its rest height
##   reach                               farthest active weapon point from fighter 0's root (m)
##   min_up / max_spin                   fighter 0's lowest uprightness / fastest root spin
##   b_states {name: seconds}            time fighter 1 spent in each state
##   a_hp, b_hp, b_max_hp, a_stamina, a_hype, b_statuses [ids], b_buildup {el: amount},
##   a_inside                            final values (fighter 0 never left the cage)
## `each` (optional) is called every tick with (sim, out) to record anything else; the shot's
## world is freed afterwards, so keep only plain values in `out`.
func shoot(attacker, target, gap: float, steps: Array, seconds := 2.4, target_steps: Array = [], prep: Callable = Callable(), radius := 6.0, each: Callable = Callable()) -> Dictionary:
	var src_a := InputSource.Scripted.new(steps)
	var src_b: InputSource = InputSource.Scripted.new(target_steps) if not target_steps.is_empty() else null
	var sim := duel(attacker, target, gap, src_a, src_b, radius)
	if prep.is_valid():
		prep.call(sim)
	var a := sim.fighters[0]
	var b := sim.fighters[1]
	var rest_y := b.pos().y
	var out := {"hits": 0, "blocked": 0, "parried": 0, "damage": 0.0, "slots": {}, "slot_dmg": {}, "glances": 0, "events": [], "push": 0.0, "lift": 0.0,
		"reach": 0.0, "min_up": 1.0, "max_spin": 0.0, "b_states": {}, "a_states": {}, "a_inside": true, "first_hit_t": -1.0}
	var dt := 1.0 / Engine.physics_ticks_per_second
	var n := int(seconds / dt)
	var cursor := 0
	var hit_pos := Vector3.INF
	var hit_t := -1.0
	for i in n:
		sim.step(dt)
		await get_tree().physics_frame
		for ev in sim.events_since(cursor):
			cursor = int(ev["seq"])
			(out["events"] as Array).append(ev)
			if str(ev["type"]) == "hit" and int(ev["fighter"]) == 0 and int(ev["target"]) == 1:
				if bool(ev["parried"]):
					out["parried"] = int(out["parried"]) + 1
				elif bool(ev["blocked"]):
					out["blocked"] = int(out["blocked"]) + 1
					out["damage"] = float(out["damage"]) + float(ev["damage"])
				else:
					out["hits"] = int(out["hits"]) + 1
					out["damage"] = float(out["damage"]) + float(ev["damage"])
					var sl := str(ev.get("slot", ""))
					var slots: Dictionary = out["slots"]
					slots[sl] = int(slots.get(sl, 0)) + 1
					var sd: Dictionary = out["slot_dmg"]
					sd[sl] = float(sd.get(sl, 0.0)) + float(ev["damage"])
				if hit_t < 0.0:
					hit_t = sim.time
					hit_pos = b.pos()
					out["first_hit_t"] = sim.time - SETTLE
			elif str(ev["type"]) == "parry" and int(ev["fighter"]) == 1:
				out["parried"] = int(out["parried"]) + 1
			elif str(ev["type"]) == "glance" and int(ev["fighter"]) == 0:
				out["glances"] = int(out["glances"]) + 1
		var bs: Dictionary = out["b_states"]
		bs[b.state_name()] = float(bs.get(b.state_name(), 0.0)) + dt
		var as_: Dictionary = out["a_states"]
		as_[a.state_name()] = float(as_.get(a.state_name(), 0.0)) + dt
		out["lift"] = maxf(float(out["lift"]), b.pos().y - rest_y)
		if hit_t >= 0.0 and sim.time - hit_t <= 1.0:
			var d := Vector2(b.pos().x - hit_pos.x, b.pos().z - hit_pos.z).length()
			out["push"] = maxf(float(out["push"]), d)
		if (a.state == Fighter.State.ATTACK or a.state == Fighter.State.ABILITY) and a.move != null:
			out["reach"] = maxf(float(out["reach"]), weapon_reach(a))
		var rb := a.rig.root()
		out["min_up"] = minf(float(out["min_up"]), rb.global_basis.y.dot(Vector3.UP))
		out["max_spin"] = maxf(float(out["max_spin"]), absf(rb.angular_velocity.y))
		if not sim.arena.inside(a.pos(), -0.2):
			out["a_inside"] = false
		if each.is_valid():
			each.call(sim, out)
	out["a_hp"] = a.health
	out["b_hp"] = b.health
	out["b_max_hp"] = b.max_health
	out["a_stamina"] = a.stamina
	out["a_hype"] = a.hype
	var ids := []
	for s in b.statuses.active:
		ids.append(str(s.get("id", "")))
	out["b_statuses"] = ids
	out["b_buildup"] = b.statuses.buildup.duplicate()
	sim.get_parent().queue_free()
	return out


## Farthest point of the current move's hit-window weapons from the fighter's root (m).
static func weapon_reach(f: Fighter) -> float:
	var best := 0.0
	var root := f.pos()
	for w in f.move.windows:
		for wn in w["weapons"]:
			var wd: BodyDef.Weapon = f.creature.body.weapons.get(wn)
			if wd == null:
				continue
			var wp := f.rig.bodies[wd.seg].global_transform * wd.local
			best = maxf(best, wp.distance_to(root) + wd.radius)
	return best


static func count(events: Array, type: String, key := "", val = null) -> int:
	var n := 0
	for ev in events:
		if str(ev["type"]) == type and (key == "" or ev.get(key) == val):
			n += 1
	return n


## Clean hits of `slot` from fighter 0 to fighter 1 in a shot result.
static func slot_hits(r: Dictionary, slot: String) -> int:
	return int((r["slots"] as Dictionary).get(slot, 0))


## Standard scripted inputs (times relative to SETTLE).
static func press(button: String, t := 0.0) -> Array:
	return at([{"t0": t, "t1": t + 0.05, "press": [button]}])


static func hold(button: String, t: float, seconds: float) -> Array:
	return at([{"t0": t, "t1": t + 0.05, "press": [button]}, {"t0": t, "t1": t + seconds, "hold": [button]}])


## Light presses walking a light string: a press every `every` s, `n` times.
static func string_presses(n: int, every := 0.2, t := 0.0) -> Array:
	return at([{"t0": t, "t1": t + every * n - 0.01, "press": ["light"], "every": every}])


## Light presses then Heavy inside the string's cancel window (Finisher).
static func finisher_presses(lights: int, every := 0.2) -> Array:
	return at([{"t0": 0.0, "t1": every * lights - 0.01, "press": ["light"], "every": every},
		{"t0": every * lights, "t1": every * lights + 0.05, "press": ["heavy"]}])


## Dodge toward the target then Light (Dash Attack).
static func dash_presses(light_after := 0.12) -> Array:
	return at([{"t0": 0.0, "t1": light_after + 0.1, "move": "to_target"},
		{"t0": 0.0, "t1": 0.05, "press": ["dodge"]},
		{"t0": light_after, "t1": light_after + 0.05, "press": ["light"]}])


## Grab, then (after `then` s) either pummel (light) or throw toward `throw_dir` (world).
static func grab_presses(then := 0.5, pummels := 0, throw_dir := Vector3.ZERO) -> Array:
	var steps := [{"t0": 0.0, "t1": 0.05, "press": ["grab"]}]
	var t := then
	for i in pummels:
		steps.append({"t0": t, "t1": t + 0.05, "press": ["light"]})
		t += 0.4
	if throw_dir != Vector3.ZERO:
		steps.append({"t0": t, "t1": t + 0.15, "move": throw_dir})
		steps.append({"t0": t + 0.02, "t1": t + 0.07, "press": ["grab"]})
	return at(steps)


# ---------------------------------------------------------------------------------------------
# Tutorial exercises against a chosen partner (Kid Lamprey's scripted behaviours)

class Driver:
	extends InputSource
	var plan: Callable
	var t := 0.0
	var mem := {}

	func _init(p: Callable) -> void:
		plan = p

	func poll(f: Fighter, sim, dt: float) -> void:
		t += dt
		f.input.move = Vector3.ZERO
		f.input.held = 0
		plan.call(f, sim, t, mem)


## Runs Granny's exercise `index` with `player` (driven by `plan(f, sim, t, mem)`) against
## `partner` (driven by the tutorial's own KidScript) until it succeeds or `limit` sim seconds
## pass. Returns {ok, state, progress, time}.
func tutorial_run(index: int, player: String, partner: String, plan: Callable, limit := 40.0) -> Dictionary:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var mode := TutorialMode.new()
	mode.start_index = index
	sim.setup({"arena": Tutorial.practice_cage(), "seed": 4, "mode": mode,
		"rules": {"id": "tutorial", "name": "Tutorial", "mode": "tutorial", "round_time": 0.0, "intro_time": 0.0},
		"fighters": [{"creature": Content.creature(player), "team": 0, "source": null, "kind": "player"},
			{"creature": Content.creature(partner), "team": 1, "source": null, "kind": "scripted"}]})
	sim.set_input_source(0, Driver.new(plan))
	var t := 0.0
	while t < limit and not mode.state in ["success", "complete", "done_single"]:
		await step_sim(sim, 0.25)
		t += 0.25
	var res := {"ok": mode.state in ["success", "complete", "done_single"], "state": mode.state, "progress": mode.progress_text(), "time": t}
	sim.get_parent().queue_free()
	return res


static func toward(f: Fighter, target: Vector3) -> Vector3:
	var d := Vector3(target.x - f.pos().x, 0.0, target.z - f.pos().z)
	return d.normalized() if d.length() > 0.05 else Vector3.ZERO


# ---------------------------------------------------------------------------------------------
# Bot bouts (balance)

## True when the run asked for the full balance tables (`-- --test <file> --balance`).
static func balance_requested() -> bool:
	return OS.get_cmdline_user_args().has("--balance")


## Runs `count` seeded bot-vs-bot bouts of fighter A (team 0) against fighter B (team 1),
## `parallel` at a time, each until a KO or the round timer (decision on health). Returns
## {a_wins, b_wins, draws, bouts, a_hits, b_hits, a_dmg, b_dmg, kos, avg_time} where hits and
## damage are totals of clean landed hits/damage per side.
func bouts(a_id: String, b_id: String, tier_a: String, tier_b: String, count: int, round_time := 90.0, gap := 3.0, parallel := 4, seed_base := 100, radius := 5.0) -> Dictionary:
	var res := {"a_wins": 0, "b_wins": 0, "draws": 0, "bouts": 0, "a_hits": 0, "b_hits": 0, "a_dmg": 0.0, "b_dmg": 0.0, "kos": 0, "time": 0.0}
	var started := 0
	var live: Array = []
	var dt := 1.0 / Engine.physics_ticks_per_second
	while started < count or not live.is_empty():
		while live.size() < parallel and started < count:
			var seed_value := seed_base + started * 7
			var ca := Content.creature(a_id)
			var cb := Content.creature(b_id)
			var ba := BotBrain.new(tier_a, seed_value * 31 + 1)
			ba.set_personality(ca.ai)
			var bb := BotBrain.new(tier_b, seed_value * 31 + 2)
			bb.set_personality(cb.ai)
			var sim := duel(ca, cb, gap, ba, bb, radius, {"round_time": round_time}, seed_value)
			live.append({"sim": sim, "cursor": 0})
			started += 1
		for entry in live:
			var sim: MatchSim = entry["sim"]
			sim.step(dt)
		await get_tree().physics_frame
		for entry in live.duplicate():
			var sim: MatchSim = entry["sim"]
			for ev in sim.events_since(int(entry["cursor"])):
				entry["cursor"] = int(ev["seq"])
				if str(ev["type"]) == "hit" and not bool(ev["blocked"]) and not bool(ev["parried"]) and float(ev["damage"]) > 0.0:
					var side := "a" if int(ev["fighter"]) == 0 else "b"
					res[side + "_hits"] = int(res[side + "_hits"]) + 1
					res[side + "_dmg"] = float(res[side + "_dmg"]) + float(ev["damage"])
				elif str(ev["type"]) == "ko":
					res["kos"] = int(res["kos"]) + 1
			if sim.is_finished or sim.time > round_time + 8.0:
				var w := int(sim.result.get("winner_team", -1)) if sim.is_finished else _leader(sim)
				if w == 0:
					res["a_wins"] = int(res["a_wins"]) + 1
				elif w == 1:
					res["b_wins"] = int(res["b_wins"]) + 1
				else:
					res["draws"] = int(res["draws"]) + 1
				res["bouts"] = int(res["bouts"]) + 1
				res["time"] = float(res["time"]) + sim.time
				live.erase(entry)
				sim.get_parent().queue_free()
	return res


static func _leader(sim: MatchSim) -> int:
	var a := sim.fighters[0].health_frac()
	var b := sim.fighters[1].health_frac()
	return 0 if a > b else (1 if b > a else -1)


## One formatted line of a bouts() result.
static func bout_line(label: String, r: Dictionary) -> String:
	var n := maxi(1, int(r["bouts"]))
	return "%-44s A %2d / B %2d / draw %d  (A %3.0f%%)  hits/bout A %.1f B %.1f  dmg/hit A %.1f B %.1f  KOs %d  avg %.0f s" % [
		label, int(r["a_wins"]), int(r["b_wins"]), int(r["draws"]), 100.0 * float(r["a_wins"]) / n,
		float(r["a_hits"]) / n, float(r["b_hits"]) / n,
		float(r["a_dmg"]) / maxf(1.0, float(r["a_hits"])), float(r["b_dmg"]) / maxf(1.0, float(r["b_hits"])),
		int(r["kos"]), float(r["time"]) / n]
