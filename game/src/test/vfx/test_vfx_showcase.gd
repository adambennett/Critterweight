extends TestCase
## v0.9.17 ability VFX evidence frames (docs/art/VFX.md): every playable fighter performs its
## abilities, JUICE, charged heavy and an elemental reaction against a still mirror dummy in the
## primary cage, and the real rendered frame is saved at fixed simulation times (preparation,
## contact, motion, dissipation). The file only uses APIs that already existed in v0.9.16, so the
## same script captures the "before" frames from the v0.9.16 checkout and the "after" frames from
## this one: identical gameplay, identical times, identical camera (shake off).
##
## Gated (needs a window), so suites skip it:
##   godot --path game --resolution 1600x900 -- --user-root <tmp> --test test_vfx_showcase
##         --vfx-showcase <out dir> [--vfx-fighters f_stoke,f_dredge] [--vfx-shots ability1,juice]

const ROSTER := ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters", "f_varga", "f_knell"]
const T0 := 1.0                 ## fight time of the first press
## the element each fighter's showcase reaction pre-loads on the dummy (its own element meets it)
const REACTION_SOAK := {"f_stoke": "brine", "f_dredge": "static", "f_gusto": "scorch", "f_dozer": "brine",
	"f_slurry": "grit", "f_jitters": "gale", "f_varga": "spectral", "f_knell": "brine"}
## the move that carries the fighter's element into the soaked dummy for the reaction shot
const REACTION_MOVE := {"f_stoke": "ability1", "f_dredge": "ability1", "f_gusto": "ability1", "f_dozer": "juice",
	"f_slurry": "ability1", "f_jitters": "ability1", "f_varga": "heavy", "f_knell": "ability1"}


class Driver:
	extends InputSource
	var starts: Array = []        ## [{t, slot, ability (bool)}]
	var holds: Array = []         ## [{t0, t1, button}]
	var presses: Array = []       ## [{t, button}]
	var time := 0.0
	var fired := {}

	func label() -> String:
		return "VfxShowcaseDriver"

	func poll(f: Fighter, sim, dt: float) -> void:
		if sim.mode and sim.mode.phase != MatchMode.Phase.FIGHT:
			return
		time += dt
		f.input.move = Vector3.ZERO
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


func test_zz_vfx_showcase() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--vfx-showcase")
	if i < 0 or i + 1 >= args.size() or DisplayServer.get_name() == "headless":
		return
	var out_dir := args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var only_f := _list_arg(args, "--vfx-fighters")
	var only_s := _list_arg(args, "--vfx-shots")
	Settings.set_value("access.camera_shake", 0.0, true, false)
	var index := []
	for cid in ROSTER:
		if not only_f.is_empty() and not only_f.has(cid):
			continue
		var c := Content.creature(cid)
		if c == null:
			continue
		for shot in shots_for(c):
			if not only_s.is_empty() and not only_s.has(str(shot["name"])):
				continue
			var files := await _capture(c, shot, out_dir)
			index.append({"fighter": cid, "shot": shot["name"], "times": shot["at"], "labels": shot["labels"], "files": files})
	var f := FileAccess.open(out_dir.path_join("index.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"version": Saves.game_version(), "shots": index}, "\t"))
	print("VFX_SHOWCASE_DONE ", index.size())


func _list_arg(args: PackedStringArray, flag: String) -> Array:
	var k := args.find(flag)
	if k < 0 or k + 1 >= args.size():
		return []
	return Array(args[k + 1].split(",", false))


## Time (s from the move's start) of a move's first effect, else its first hit window.
static func first_t(m: MoveDef) -> float:
	var t := INF
	for e in m.effects:
		t = minf(t, float((e as Dictionary).get("t", 0.0)))
	if t == INF:
		t = m.first_active() if not m.windows.is_empty() else 0.3
	return t


## The shots for one fighter: [{name, gap, presses|starts|holds, setup, at: [fight times], labels}]
static func shots_for(c: CreatureDef) -> Array:
	var out := []
	var martial := c.tags.has("martial")
	var lag := 1.0 / 60.0           # a press is consumed on the next tick
	for slot in ["ability1", "ability2", "juice"]:
		if not c.abilities.has(slot):
			continue
		var m: MoveDef = c.abilities[slot]
		var ft := first_t(m) + lag
		var shot := {"name": slot, "gap": 3.0, "at": [], "labels": []}
		var button := FighterInput.AB1 if slot == "ability1" else (FighterInput.AB2 if slot == "ability2" else FighterInput.JUICE)
		shot["presses"] = [{"t": T0, "button": button}]
		if slot == "juice":
			shot["setup"] = "hype"
		var marks := [[ft * 0.55, "prep"], [ft + 0.03, "contact"], [ft + 0.22, "motion"], [ft + 0.6, "after"], [ft + 1.4, "linger"]]
		for mk in marks:
			shot["at"].append(T0 + float(mk[0]))
			shot["labels"].append(mk[1])
		out.append(shot)
	# the charged heavy (hold heavy until the charge completes) or, for a martial fighter, his heavy
	if c.moves.has("heavy"):
		var h: MoveDef = c.moves["heavy"]
		var shot2 := {"name": "heavy_charged", "gap": 1.5, "at": [], "labels": []}
		if martial or h.charge_time <= 0.0:
			shot2["name"] = "heavy"
			shot2["starts"] = [{"t": T0, "slot": "heavy"}]
			var fa := h.first_active() if not h.windows.is_empty() else 0.3
			for mk2 in [[fa * 0.6, "prep"], [fa + 0.02, "contact"], [fa + 0.15, "motion"], [fa + 0.45, "after"]]:
				shot2["at"].append(T0 + float(mk2[0]))
				shot2["labels"].append(mk2[1])
		else:
			var charge_start := h.first_active() * 0.7
			var release := charge_start + h.charge_time + 0.05
			shot2["presses"] = [{"t": T0, "button": FighterInput.HEAVY}]
			shot2["holds"] = [{"t0": T0, "t1": T0 + release, "button": FighterInput.HEAVY}]
			var hc: MoveDef = c.moves.get("heavy_charged", h)
			var fa2 := hc.first_active() if not hc.windows.is_empty() else first_t(hc)
			for mk3 in [[charge_start + h.charge_time * 0.5, "charging"], [release + 0.03, "release"],
					[release + fa2 + 0.02, "contact"], [release + fa2 + 0.3, "after"]]:
				shot2["at"].append(T0 + float(mk3[0]))
				shot2["labels"].append(mk3[1])
		out.append(shot2)
	# one elemental reaction: the dummy carries another element and this fighter's element meets it
	var rm := str(REACTION_MOVE.get(c.id, "ability1"))
	var shot3 := {"name": "reaction", "gap": 1.5 if rm == "heavy" else 3.0, "at": [], "labels": [], "soak": str(REACTION_SOAK.get(c.id, "brine"))}
	var mv: MoveDef = c.abilities.get(rm) if c.abilities.has(rm) else c.moves.get(rm)
	if mv == null:
		return out
	var ft3 := (first_t(mv) if rm != "heavy" else (mv.first_active() if not mv.windows.is_empty() else 0.3)) + lag
	if rm == "juice":
		shot3["setup"] = "hype_soak"
		shot3["presses"] = [{"t": T0, "button": FighterInput.JUICE}]
	elif rm == "heavy":
		shot3["setup"] = "soak"
		shot3["starts"] = [{"t": T0, "slot": "heavy"}]
	else:
		shot3["setup"] = "soak"
		shot3["presses"] = [{"t": T0, "button": FighterInput.AB1 if rm == "ability1" else FighterInput.AB2}]
	# projectiles reach the dummy later than an area: frames cover the flight and the reaction
	for mk4 in [[ft3 + 0.05, "contact"], [ft3 + 0.3, "reaction"], [ft3 + 0.6, "reaction2"], [ft3 + 1.1, "after"]]:
		shot3["at"].append(T0 + float(mk4[0]))
		shot3["labels"].append(mk4[1])
	out.append(shot3)
	return out


func _capture(c: CreatureDef, shot: Dictionary, out_dir: String) -> Array:
	var d := Driver.new()
	for k in ["starts", "presses", "holds"]:
		if shot.has(k):
			d.set(k, shot[k])
	var gap := float(shot.get("gap", 3.0))
	var arena: Dictionary = Content.get_entry("arenas", "the_gullet").duplicate(true)
	arena["id"] = "vfx_showcase"
	arena["spawns"] = [[0, -gap * 0.5, 0], [0, gap * 0.5, 180]]
	var mk: Dictionary = arena.get("markers", {})
	mk.erase("spawn")
	mk.erase("marker_spawn")
	var scene := App.start_match({"arena": ArenaDef.from_dict(arena), "seed": 7, "no_record": true,
		"rules": {"id": "vfx_showcase", "name": "VFX showcase", "mode": "standard", "rounds": 1, "round_time": 0, "intro_time": 0.4},
		"fighters": [{"creature": c.id, "team": 0, "kind": "scripted", "source": d, "name": c.id.trim_prefix("f_").to_upper()},
			{"creature": c.id, "team": 1, "kind": "scripted", "source": null, "name": "DUMMY"}]})
	await get_tree().physics_frame
	var setup := str(shot.get("setup", ""))
	if setup.begins_with("hype"):
		scene.sim.fighters[0].hype = 100.0
	if setup.ends_with("soak"):
		# just before the press: the dummy carries the soak element's status and is one push short
		# of this fighter's own element, so the showcased hit triggers the reaction
		while d.time < T0 - 0.1:
			await get_tree().physics_frame
		var dummy: Fighter = scene.sim.fighters[1]
		dummy.statuses.add_buildup(str(shot["soak"]), 100.0, null)
		dummy.statuses.add_buildup(c.element, 95.0, null)
	var files := []
	var times: Array = shot["at"]
	var labels: Array = shot["labels"]
	for k in times.size():
		while d.time < float(times[k]):
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := out_dir.path_join("%s_%s_%d_%s.png" % [c.id, str(shot["name"]), k, str(labels[k])])
		img.save_png(path)
		files.append(path.get_file())
		print("VFX_SHOWCASE ", path)
	return files
