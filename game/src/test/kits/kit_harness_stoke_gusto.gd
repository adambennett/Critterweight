extends TestCase
## Shared harness for the STOKE and GUSTO kit tests (test_kit_f_stoke.gd, test_kit_f_gusto.gd).
## Not a test file itself (no `test_` prefix). It builds a headless two-fighter duel at an exact
## root-to-root gap, starts a move directly or through real button presses, and measures what the
## move did: contacts (part, damage, quality), weapon reach from the root, attacker stability
## (uprightness, angular speed, self-clipping), target knockback/launch, stun, poise, element
## build-up and statuses. Fighter space: +Z forward, +Y up, +X = the fighter's left.
##
## Lab mode (prints a per-move table instead of asserting):
##   godot --headless --path game --fixed-fps 120 -- --test test_kit_f_stoke.gd::test_zz_lab -- --kit-lab l1,l2@1.2
## (`slot@gap`; `--kit-def <creature id>` changes the dummy, default = the kit's own creature).

const DT := 1.0 / 120.0
const INTRO := 0.5

## Starts moves directly (bypasses strings and buttons) and/or holds buttons.
class Driver:
	extends InputSource
	var starts: Array = []        ## [{t, slot, ability (bool)}]
	var holds: Array = []         ## [{t0, t1, button}]
	var presses: Array = []       ## [{t, button}]
	var dirs: Array = []          ## [{t0, t1, dir (world Vector3)}] (override move_dir)
	var move_dir := Vector3.ZERO
	var time := 0.0
	var fired := {}

	func label() -> String:
		return "KitDriver"

	func poll(f: Fighter, sim, dt: float) -> void:
		if sim.mode and sim.mode.phase != MatchMode.Phase.FIGHT:
			return
		time += dt
		f.input.move = move_dir
		for dd in dirs:
			if time >= float(dd["t0"]) and time < float(dd["t1"]):
				f.input.move = dd["dir"]
		f.input.held = 0
		for h in holds:
			if time >= float(h["t0"]) and time < float(h["t1"]):
				f.input.set_held(int(h["button"]), true)
		for i in presses.size():
			var p: Dictionary = presses[i]
			if not fired.has("p%d" % i) and time >= float(p["t"]):
				fired["p%d" % i] = true
				f.input.press(int(p["button"]))
		for i in starts.size():
			var s: Dictionary = starts[i]
			if not fired.has("s%d" % i) and time >= float(s["t"]):
				fired["s%d" % i] = true
				var ab := bool(s.get("ability", false))
				var slot: String = s["slot"]
				var m: MoveDef = (f.creature.abilities if ab else f.creature.moves).get(slot)
				if m:
					f._start_move(m, slot, Fighter.State.ABILITY if ab else Fighter.State.ATTACK)


## Two fighters facing each other along world Z, roots `gap` metres apart (fighter 0 attacks +Z).
func duel(att_id: String, def_id: String, gap: float, att_src: InputSource, def_src: InputSource = null,
		rules_extra := {}, seed_value := 3, arena_r := 5.0) -> MatchSim:
	var arena := ArenaDef.from_dict({"id": "kit_lab", "base": "octagon", "radius": arena_r, "wall_height": 2.4,
		"spawns": [[0, -gap * 0.5, 0], [0, gap * 0.5, 180]]})
	var rules := {"rounds": 1, "round_time": 0, "intro_time": INTRO}
	for k in rules_extra:
		rules[k] = rules_extra[k]
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	sim.setup({"arena": arena, "rules": rules, "seed": seed_value,
		"fighters": [{"creature": Content.creature(att_id), "team": 0, "source": att_src},
			{"creature": Content.creature(def_id), "team": 1, "source": def_src}]})
	return sim


## Frees a finished simulation's private physics world.
func dispose(sim: MatchSim) -> void:
	var holder := sim.get_parent()
	if holder:
		holder.queue_free()


func events_of(sim: MatchSim, type: String) -> Array:
	return sim.events.filter(func(e): return e["type"] == type)


func hits_by(sim: MatchSim, fi: int, with_damage := true) -> Array:
	return sim.events.filter(func(e): return e["type"] == "hit" and int(e["fighter"]) == fi and (not with_damage or float(e["damage"]) > 0.0 or bool(e["blocked"]) or bool(e["parried"])))


## Weapon names used by a move's hit windows.
func move_weapons(m: MoveDef) -> PackedStringArray:
	var out := PackedStringArray()
	for w in m.windows:
		for wn in w["weapons"]:
			if not out.has(wn):
				out.append(wn)
	return out


## Segments a weapon may legally pass close to (its own chain / segment and parents' joints).
func _limb_segments(f: Fighter, seg: int) -> PackedInt32Array:
	var out := PackedInt32Array([seg])
	for cname in f.creature.body.chains:
		var c: BodyDef.Chain = f.creature.body.chains[cname]
		if c.segs.has(seg):
			for s in c.segs:
				if not out.has(s):
					out.append(s)
	var s0: BodyDef.Seg = f.creature.body.segments[seg]
	if s0.parent >= 0 and not out.has(s0.parent):
		out.append(s0.parent)
	return out


## Deepest penetration (m) of a weapon sphere centre into the fighter's own trunk (core / head /
## shell segments that are not part of the weapon's limb). > 0 means the weapon centre is inside the
## body (self-clipping). `who` receives the offending segment id.
func self_clip(f: Fighter, wname: String, who: Array = []) -> float:
	var w: BodyDef.Weapon = f.creature.body.weapons.get(wname)
	if w == null:
		return -1.0
	var wp := f.rig.bodies[w.seg].global_transform * w.local
	var skip := _limb_segments(f, w.seg)
	var worst := -9.0
	for s: BodyDef.Seg in f.creature.body.segments:
		if skip.has(s.index) or not s.part in ["core", "head", "shell"]:
			continue
		var t := f.rig.bodies[s.index].global_transform
		for sh: BodyDef.Shape in s.shapes:
			var q := MathX.closest_on_segment(wp, t * sh.hit_a, t * sh.hit_b)
			var pen := sh.hit_r - wp.distance_to(q)
			if pen > worst:
				worst = pen
				if who.is_empty():
					who.append(s.id)
				else:
					who[0] = s.id
	return worst


## Runs one move (or a scripted input sequence) against a dummy and measures everything.
## opts: slot (String), ability (bool), at (s after round start, default 0.2), gap, def_src,
## att_src (overrides the driver), def_id, watch (s after the start, default 1.6),
## setup (Callable(sim) run once at round start), status (target status to pre-apply: element id).
func run_move(att_id: String, opts: Dictionary) -> Dictionary:
	var gap := float(opts.get("gap", 1.2))
	var def_id := str(opts.get("def_id", att_id))
	var at := float(opts.get("at", 0.2))
	var watch := float(opts.get("watch", 1.6))
	var slot := str(opts.get("slot", ""))
	var ability := bool(opts.get("ability", false))
	var src: InputSource = opts.get("att_src", null)
	if src == null:
		var d := Driver.new()
		d.starts = [{"t": at, "slot": slot, "ability": ability}]
		src = d
	var sim := duel(att_id, def_id, gap, src, opts.get("def_src", null), opts.get("rules", {}), int(opts.get("seed", 3)), float(opts.get("arena_r", 5.0)))
	var a := sim.fighters[0]
	var b := sim.fighters[1]
	var m: MoveDef = (a.creature.abilities if ability else a.creature.moves).get(slot) if slot != "" else null
	var weps := move_weapons(m) if m else PackedStringArray()
	for wn in opts.get("extra_weapons", []):
		weps.append(str(wn))
	await step_sim(sim, INTRO + 0.02)
	if opts.has("setup"):
		(opts["setup"] as Callable).call(sim)
	var r := {"slot": slot, "gap": gap, "hits": [], "first_hit_t": -1.0, "reach": 0.0, "reach_active": 0.0,
		"up_min": 1.0, "w_max": 0.0, "clip_max": -9.0, "clip_seg": "", "tgt_disp": Vector3.ZERO, "tgt_rise": 0.0,
		"tgt_stun_time": 0.0, "knockdown": false, "tgt_states": [], "buildup": {}, "statuses": [],
		"poise_dmg": 0.0, "stamina_spent": 0.0, "att_disp": 0.0, "escaped": 0, "dmg_total": 0.0, "glances": 0,
		"start_gap": 0.0, "tgt_up_min": 1.0, "tgt_turn_deg": 0.0, "hp_lost": 0.0, "att_hp_lost": 0.0}
	var t := 0.0
	var started := false
	var a0 := Vector3.ZERO
	var b0 := Vector3.ZERO
	var by0 := 0.0
	var st_pre := a.stamina
	var st_min := a.stamina
	var p0 := b.poise
	var hp0 := b.health
	var ahp0 := a.health
	var fwd := Vector3.ZERO
	var side := Vector3.ZERO
	var b_ground_y := b.pos().y
	var last_hit_seq := 0
	var turn_probe := -1
	var cursor := sim.event_seq
	while t < at + watch + 0.05:
		if not started:
			st_pre = a.stamina
		sim.step(DT)
		await get_tree().physics_frame
		t += DT
		if not started and (a.state == Fighter.State.ATTACK or a.state == Fighter.State.ABILITY or a.state == Fighter.State.TAUNT or a.state == Fighter.State.DODGE or a.state == Fighter.State.GRABBING):
			started = true
			a0 = a.pos()
			b0 = b.pos()
			by0 = b.facing_yaw
			fwd = a.forward()
			side = fwd.cross(Vector3.UP)   # the attacker's right
			r["start_gap"] = Vector2(b0.x - a0.x, b0.z - a0.z).length()
			b_ground_y = b.pos().y
		if not started:
			continue
		st_min = minf(st_min, a.stamina)
		r["tgt_stamina_min"] = minf(float(r.get("tgt_stamina_min", b.max_stamina)), b.stamina)
		var asn := a.state_name()
		if not r.has("att_states"):
			r["att_states"] = []
		if (r["att_states"] as Array).is_empty() or (r["att_states"] as Array).back() != asn:
			(r["att_states"] as Array).append(asn)
		r["att_rise"] = maxf(float(r.get("att_rise", 0.0)), a.pos().y - float(r.get("att_y0", a.pos().y)))
		if not r.has("att_y0"):
			r["att_y0"] = a.pos().y
		if turn_probe > 0:
			turn_probe -= 1
			if turn_probe == 0:
				r["tgt_turn_deg"] = rad_to_deg(MathX.wrap_angle(b.facing_yaw - by0))
		# attacker stability + reach
		var up := a.rig.root().global_basis.y.dot(Vector3.UP)
		r["up_min"] = minf(float(r["up_min"]), up)
		r["tgt_up_min"] = minf(float(r["tgt_up_min"]), b.rig.root().global_basis.y.dot(Vector3.UP))
		for rb in a.rig.bodies:
			r["w_max"] = maxf(float(r["w_max"]), rb.angular_velocity.length())
		if a.move or bool(opts.get("trace", false)):
			if bool(opts.get("trace", false)):
				var line := "  t=%.3f st=%s" % [a.state_time, a.state_name()]
				for wn in weps:
					var w2: BodyDef.Weapon = a.creature.body.weapons.get(wn)
					var wp2 := a.rig.bodies[w2.seg].global_transform * w2.local - a0
					line += " %s(x%.2f y%.2f z%.2f)" % [wn, -wp2.dot(side), wp2.y, wp2.dot(fwd)]
				var rp := a.pos() - a0
				line += " root(z%.2f y%.2f) up %.3f |" % [rp.dot(fwd), a.pos().y, a.rig.root().global_basis.y.dot(Vector3.UP)]
				for tw in ["fist_l", "fist_r", "wing_edge_l", "wing_edge_r", "head"]:
					var w3: BodyDef.Weapon = b.creature.body.weapons.get(tw)
					if w3:
						var wp3 := b.rig.bodies[w3.seg].global_transform * w3.local - a0
						line += " T%s(x%.2f y%.2f z%.2f)" % [tw, -wp3.dot(side), wp3.y, wp3.dot(fwd)]
				for dc in sim.combat.debug_contacts:
					line += " C(vn %.2f)" % float(dc["vn"])
				print(line)
			for wn in weps:
				var w: BodyDef.Weapon = a.creature.body.weapons.get(wn)
				if w == null:
					continue
				var wp := a.rig.bodies[w.seg].global_transform * w.local
				var dd := wp.distance_to(a.pos())
				r["reach"] = maxf(float(r["reach"]), dd)
				if a.move and a.move.window_index(a.state_time) >= 0:
					r["reach_active"] = maxf(float(r["reach_active"]), dd)
				var who := []
				var cl := self_clip(a, wn, who)
				if cl > float(r["clip_max"]):
					r["clip_max"] = cl
					r["clip_seg"] = "%s>%s@%.2f" % [wn, who[0] if not who.is_empty() else "?", a.state_time]
		r["tgt_rise"] = maxf(float(r["tgt_rise"]), b.pos().y - b_ground_y)
		if b.state == Fighter.State.HITSTUN:
			r["tgt_stun_time"] = float(r["tgt_stun_time"]) + DT
		var sn := b.state_name()
		if (r["tgt_states"] as Array).is_empty() or (r["tgt_states"] as Array).back() != sn:
			(r["tgt_states"] as Array).append(sn)
		for ev in sim.events_since(cursor):
			cursor = int(ev["seq"])
			if bool(opts.get("trace", false)) and not str(ev["type"]) in ["move_start"]:
				print("  EV %.3f %s" % [a.state_time, str(ev)])
			match str(ev["type"]):
				"hit":
					if int(ev["fighter"]) == 0 and int(ev["target"]) == 1:
						var hd := {"t": a.state_time, "dmg": float(ev["damage"]), "part": _seg_near(b, ev["point"]), "q": float(ev["quality"]),
							"blocked": bool(ev["blocked"]), "parried": bool(ev["parried"]), "slot": str(ev["slot"]), "move": str(ev["move"]),
							"counter": bool(ev.get("counter", false))}
						(r["hits"] as Array).append(hd)
						r["dmg_total"] = float(r["dmg_total"]) + float(ev["damage"])
						if float(r["first_hit_t"]) < 0.0 and (float(ev["damage"]) > 0.0 or bool(ev["blocked"]) or bool(ev["parried"])):
							r["first_hit_t"] = a.state_time
							r["buildup_at_hit"] = b.statuses.buildup.duplicate()
							turn_probe = 3
						last_hit_seq = int(ev["seq"])
				"glance":
					if int(ev["fighter"]) == 0:
						r["glances"] = int(r["glances"]) + 1
				"grab", "throw", "grab_tech", "grab_escape", "parry", "guard_break", "reaction", "projectile_destroyed", "reflect", "land", "juice_end":
					var ek := "ev_" + str(ev["type"])
					r[ek] = int(r.get(ek, 0)) + 1
				"knockdown":
					if int(ev["fighter"]) == 1:
						r["knockdown"] = true
				"escaped":
					r["escaped"] = int(r["escaped"]) + 1
		if last_hit_seq > 0:
			r["buildup"] = _max_dict(r["buildup"], b.statuses.buildup)
			for s in b.statuses.active:
				var sid := str(s.get("id", ""))
				if not (r["statuses"] as Array).has(sid):
					(r["statuses"] as Array).append(sid)
			r["poise_dmg"] = maxf(float(r["poise_dmg"]), p0 - b.poise)
	var disp := b.pos() - b0
	disp.y = 0.0
	r["tgt_disp"] = Vector3(-disp.dot(side), 0.0, disp.dot(fwd))   # x = toward the attacker's LEFT, z = away
	var ad := a.pos() - a0
	ad.y = 0.0
	r["att_disp"] = ad.dot(fwd)
	r["stamina_spent"] = st_pre - st_min
	r["hp_lost"] = hp0 - b.health
	r["att_hp_lost"] = ahp0 - a.health
	r["end_gap"] = Vector2(b.pos().x - a.pos().x, b.pos().z - a.pos().z).length()
	r["att_state"] = a.state_name()
	r["sim"] = sim
	return r


## Hits by the attacker that dealt damage and were not blocked.
func hits_with_damage(r: Dictionary) -> Array:
	return (r["hits"] as Array).filter(func(h): return float(h["dmg"]) > 0.0 and not bool(h["blocked"]))


## Attacker invariants for any move: upright, no spin-out, weapons never inside its own trunk,
## weapon points within the 1.6 m reach cap, still inside the cage.
func check_stable(r: Dictionary, label: String) -> void:
	check(float(r["up_min"]) >= 0.85, "%s: stays upright (min up %.3f)" % [label, r["up_min"]])
	check(float(r["w_max"]) < 80.0, "%s: no spin-out (max segment w %.1f rad/s)" % [label, r["w_max"]])
	check(float(r["clip_max"]) < 0.03, "%s: weapon never inside its own trunk (%.3f %s)" % [label, r["clip_max"], r["clip_seg"]])
	check(float(r["reach"]) <= 1.6, "%s: weapon points within 1.6 m of the root (%.2f)" % [label, r["reach"]])
	check_eq(int(r["escaped"]), 0, "%s: stays inside the cage" % label)


## A strike that must connect: contact inside a hit window, damage, stun (or knockdown), poise
## damage, element build-up (or the status it triggered), and the stability invariants.
func check_strike(r: Dictionary, m: MoveDef, label: String, element: String) -> void:
	check_stable(r, label)
	var hs := hits_with_damage(r)
	if not check(not hs.is_empty(), "%s connects: %s" % [label, describe(r)]):
		return
	var t := float(hs[0]["t"])
	check(m.window_index(t) >= 0 or m.window_index(t - DT) >= 0 or m.window_index(t - 2.0 * DT) >= 0, "%s: contact inside a hit window (t %.3f)" % [label, t])
	check(float(r["tgt_stun_time"]) > 0.05 or bool(r["knockdown"]), "%s: target stunned (%s)" % [label, describe(r)])
	check(float(r["poise_dmg"]) > 0.0 or bool(r["knockdown"]), "%s: poise damage" % label)
	# (the engine applies no build-up to a fighter that is already down, and a hit that knocks
	# down is resolved before its build-up, so knockdown hits carry no element)
	if element != "" and not bool(r["knockdown"]):
		var bu: Dictionary = r.get("buildup_at_hit", {})
		var sid := str((Elements.defs.get(element, {}) as Dictionary).get("status", {}).get("id", ""))
		check(float(bu.get(element, 0.0)) > 0.0 or (r["statuses"] as Array).has(sid), "%s: %s build-up (%s)" % [label, element, str(bu)])


## Id of the fighter's segment whose hurt shape surface is closest to a world point.
func _seg_near(f: Fighter, p: Vector3) -> String:
	var best := ""
	var bd := INF
	for s: BodyDef.Seg in f.creature.body.segments:
		var t := f.rig.bodies[s.index].global_transform
		for sh: BodyDef.Shape in s.shapes:
			var d := p.distance_to(MathX.closest_on_segment(p, t * sh.hit_a, t * sh.hit_b)) - sh.hit_r
			if d < bd:
				bd = d
				best = s.id
	return best


func _max_dict(acc: Dictionary, cur: Dictionary) -> Dictionary:
	var out := acc.duplicate()
	for k in cur:
		out[k] = maxf(float(out.get(k, 0.0)), float(cur[k]))
	return out


## One-line summary of a run_move() result (lab output and failure messages).
func describe(r: Dictionary) -> String:
	var parts := PackedStringArray()
	for h in r["hits"]:
		parts.append("%.2fs %s %.1f q%.2f%s%s" % [h["t"], h["part"], h["dmg"], h["q"], " BLK" if h["blocked"] else "", " PRY" if h["parried"] else ""])
	var bu := PackedStringArray()
	var bah: Dictionary = r.get("buildup_at_hit", {})
	for k in bah:
		bu.append("%s %.1f" % [k, float(bah[k])])
	for k in r:
		if str(k).begins_with("ev_"):
			parts.append("%s x%d" % [str(k).substr(3), int(r[k])])
	return "%s gap %.2f (start %.2f): hits [%s] gl %d reach %.2f/%.2f up %.3f w %.1f clip %.3f %s kb(x%.2f z%.2f) rise %.2f stun %.2f kd %s poise %.1f bu [%s] st %s turn %.0f stam %.1f lunge %.2f" % [
		r["slot"], r["gap"], r["start_gap"], ", ".join(parts), r["glances"], r["reach"], r["reach_active"], r["up_min"], r["w_max"], r["clip_max"], r["clip_seg"],
		(r["tgt_disp"] as Vector3).x, (r["tgt_disp"] as Vector3).z, r["tgt_rise"], r["tgt_stun_time"], r["knockdown"],
		r["poise_dmg"], ", ".join(bu), str(r["statuses"]), r["tgt_turn_deg"], r["stamina_spent"], r["att_disp"]]


## Lab entry: `--kit-lab slot[@gap],...` prints describe() lines for the given creature.
func lab(att_id: String) -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--kit-lab")
	if i < 0 or i + 1 >= args.size():
		return
	var def_id := att_id
	var j := args.find("--kit-def")
	if j >= 0 and j + 1 < args.size():
		def_id = args[j + 1]
	for spec in args[i + 1].split(",", false):
		var parts: PackedStringArray = spec.split("@")
		var slot := parts[0]
		var ability := slot.begins_with("ability") or slot == "juice"
		if parts.size() > 1 and parts[1].contains(":"):
			# sweep: slot@g0:g1:step -> one compact line per gap
			var g: PackedStringArray = parts[1].split(":")
			var gg := float(g[0])
			var line := "SWEEP %s:" % slot
			while gg <= float(g[1]) + 1e-4:
				var rs := await run_move(att_id, {"slot": slot, "ability": ability, "gap": gg, "def_id": def_id})
				var hs: Array = rs["hits"]
				var tag := "-"
				if not hs.is_empty():
					tag = "%s:%.0f" % [str(hs[0]["part"]).substr(0, 5), float(hs[0]["dmg"])]
				elif int(rs.get("ev_grab", 0)) > 0:
					tag = "GRAB"
				line += " %.2f=%s" % [gg, tag]
				dispose(rs["sim"])
				gg += float(g[2])
			print(line)
			continue
		var gap := float(parts[1]) if parts.size() > 1 else 1.2
		var opts := {"slot": slot, "ability": ability, "gap": gap, "def_id": def_id, "trace": args.has("--kit-trace")}
		if slot.contains(">"):
			# "first>button:delay[>button:delay]": start `first`, then press buttons after delays (s)
			var chain: PackedStringArray = slot.split(">")
			var d := Driver.new()
			var first := chain[0]
			var ab1 := first.begins_with("ability") or first == "juice"
			d.starts = [{"t": 0.2, "slot": first, "ability": ab1}]
			var tt := 0.2
			for k in range(1, chain.size()):
				var bp: PackedStringArray = chain[k].split(":")
				tt += float(bp[1]) if bp.size() > 1 else 0.3
				d.presses.append({"t": tt, "button": FighterInput.BUTTON_NAMES.find(bp[0])})
			opts["att_src"] = d
			opts["slot"] = first
			opts["ability"] = ab1
			opts["watch"] = tt + 1.6
			var kw := args.find("--kit-weapons")
			opts["extra_weapons"] = Array(args[kw + 1].split(",")) if kw >= 0 and kw + 1 < args.size() else []
		var r := await run_move(att_id, opts)
		print("LAB ", describe(r))
		dispose(r["sim"])
