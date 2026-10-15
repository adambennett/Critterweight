class_name MatchScene
extends Node3D
## Runs a LOCAL authoritative match with full presentation: MatchSim + ArenaView +
## CreatureViews + VFX + camera + HUD, translating simulation events into feedback.
## (Networked clients use NetMatchScene, which renders the same views from snapshots.)

signal match_finished(result: Dictionary)

var sim: MatchSim
var arena_view: ArenaView
var views: Array[CreatureView] = []
var vfx: Vfx
var camera: FightCamera
var hud: FightHud
var hud_layer: CanvasLayer
var player_index := 0
var _event_cursor := 0
var config := {}


## config: {arena: ArenaDef, rules: {}, seed: int, mode: MatchMode, fighters: [{creature, team, kind:"player"|"bot", difficulty, name}]}
func start(cfg: Dictionary) -> void:
	config = cfg
	name = "MatchScene"
	arena_view = ArenaView.new()
	add_child(arena_view)
	arena_view.build(cfg["arena"])
	camera = FightCamera.new()
	add_child(camera)
	camera.arena_radius = (cfg["arena"] as ArenaDef).radius
	var entries: Array = []
	var idx := 0
	for e in cfg["fighters"]:
		var entry: Dictionary = e.duplicate()
		match str(e.get("kind", "bot")):
			"player":
				var lp := LocalPlayerInput.new()
				lp.camera = camera
				entry["source"] = LabRecording.wrap_player(lp, e, self)   # AI Lab imitation recording (off by default)
				player_index = idx
			"policy":
				# AI Lab policy: e.policy_id (falls back to a scripted bot if missing/incompatible)
				entry["source"] = PolicyInputSource.for_match(e, int(cfg.get("seed", 1)) * 31 + idx, idx)
			"bot":
				var bb := BotBrain.new(str(e.get("difficulty", "regular")), int(cfg.get("seed", 1)) * 31 + idx)
				bb.set_personality((e["creature"] as CreatureDef).ai)
				entry["source"] = bb
			_:
				entry["source"] = e.get("source")
		entries.append(entry)
		idx += 1
	sim = MatchSim.new()
	sim.running = false
	add_child(sim)
	sim.setup({"arena": cfg["arena"], "rules": cfg.get("rules", {}), "seed": cfg.get("seed", 1),
		"mode": cfg.get("mode"), "fighters": entries})
	for f in sim.fighters:
		var v := CreatureView.new()
		add_child(v)
		v.setup(f.creature, TeamColors.color(f.team))
		v.snap_transforms(f.rig.segment_transforms())
		views.append(v)
	vfx = Vfx.new()
	add_child(vfx)
	camera.points_provider = _camera_points
	camera.focus_provider = _camera_focus
	camera.snap()
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	hud = FightHud.new()
	hud_layer.add_child(hud)
	hud.setup(sim, player_index)
	sim.finished.connect(_on_finished)


func _camera_points() -> Array:
	var pts := []
	for f in sim.fighters:
		if f.state != Fighter.State.INACTIVE and f.pos().y > -3.0:
			pts.append(f.pos())
	return pts


func _camera_focus() -> Array:
	var me := sim.fighters[player_index]
	return [me.pos(), me.target.pos() if me.target else null]


func _physics_process(dt: float) -> void:
	if sim == null or sim.paused:
		return
	sim.step(dt)
	for i in sim.fighters.size():
		views[i].push_transforms(sim.fighters[i].rig.segment_transforms())
	for i in sim.arena_nodes.get("dynamic_props", []).size():
		pass
	_process_events()


func _process(_dt: float) -> void:
	if sim == null:
		return
	var alpha := Engine.get_physics_interpolation_fraction()
	for i in views.size():
		var f := sim.fighters[i]
		views[i].juice_amount = 1.0 if f.time < f.juiced_until else 0.0
		views[i].status_color = _status_color(f)
		views[i].render(alpha)
	var props: Array = sim.arena_nodes.get("props", [])
	for i in props.size():
		arena_view.set_prop_transform(i, (props[i] as Node3D).global_transform)
	vfx.sync_entities(sim.effects.entities)


func _status_color(f: Fighter) -> Color:
	for s in f.statuses.active:
		var el := str(s.get("element", ""))
		if el != "":
			var c := Elements.color(el)
			c.a = 0.6
			return c
	return Color(0, 0, 0, 0)


func _process_events() -> void:
	for ev in sim.events_since(_event_cursor):
		_event_cursor = int(ev["seq"])
		_on_event(ev)


func _on_event(ev: Dictionary) -> void:
	match str(ev["type"]):
		"hit":
			var ti := int(ev["target"])
			var dmg := float(ev["damage"])
			var p: Vector3 = ev["point"]
			var n: Vector3 = ev["normal"]
			var v := views[ti]
			var el := str(ev.get("element", ""))
			var col := Elements.color(el) if el != "" else Color(1.0, 0.9, 0.55)
			if bool(ev["blocked"]):
				vfx.emit("spark", p, n, Color(0.6, 0.85, 1.0), 0.6)
			else:
				v.flash(clampf(dmg / 14.0, 0.25, 1.0))
				v.add_bruise(_seg_near(ti, p), p, clampf(dmg / 16.0, 0.15, 1.0))
				vfx.emit("spark", p, n, col, clampf(dmg / 10.0, 0.4, 1.5))
				if dmg >= 10.0:
					vfx.ring(p, 0.8, Color(1, 1, 1, 0.8), 0.25, false)
			camera.add_trauma(clampf(dmg / 40.0, 0.05, 0.45))
			if bool(ev.get("counter", false)):
				vfx.word(p + Vector3.UP * 0.3, "COUNTER!", Color(1.0, 0.75, 0.2))
			var involved := ti == player_index or int(ev["fighter"]) == player_index
			if involved:
				Controls.rumble(clampf(dmg / 20.0, 0.1, 0.6), clampf(dmg / 30.0, 0.0, 0.8), 0.12)
		"parry":
			var pp: Vector3 = ev.get("pos", sim.fighters[int(ev["fighter"])].pos())
			vfx.word(pp + Vector3.UP * 1.2, "PARRY!", Color(0.5, 0.9, 1.0))
			vfx.ring(pp + Vector3.UP * 1.0, 1.2, Color(0.6, 0.9, 1.0, 0.9), 0.3, false)
		"knockdown":
			var f := sim.fighters[int(ev["fighter"])]
			vfx.emit("dust", f.ground_pos(), Vector3.UP, Color(0.8, 0.75, 0.65, 0.7))
			camera.add_trauma(0.3)
		"ko":
			var fk := sim.fighters[int(ev["fighter"])]
			var away := fk.pos() - camera.global_position
			views[int(ev["fighter"])].detach_piece(Vector3(away.x, 0, away.z))
			hud.callout("K.O.!", 2.0, Color(1.0, 0.35, 0.3))
			camera.add_trauma(0.5)
		"guard_break":
			vfx.word(sim.fighters[int(ev["fighter"])].head_pos() + Vector3.UP * 0.3, "GUARD BREAK!", Color(1.0, 0.5, 0.2))
		"burst":
			var fb := sim.fighters[int(ev["fighter"])]
			vfx.ring(fb.ground_pos() + Vector3.UP * 0.05, 2.5, Color(1, 1, 1, 0.9), 0.35)
		"juice":
			var fj := sim.fighters[int(ev["fighter"])]
			vfx.word(fj.head_pos() + Vector3.UP * 0.4, "JUICED!", Color(1.0, 0.6, 0.1), 80)
			vfx.emit("burst", fj.pos(), Vector3.UP, Color(1.0, 0.6, 0.15), 1.5)
		"effect":
			var pe: Vector3 = ev["pos"]
			var el2 := str(ev.get("element", ""))
			if str(ev["effect"]) == "area":
				vfx.ring(pe + Vector3.UP * 0.05, 2.2, (Elements.color(el2) if el2 != "" else Color(1, 0.9, 0.6)) * Color(1, 1, 1, 0.8), 0.35)
				vfx.emit("dust", pe, Vector3.UP, Color(0.85, 0.8, 0.7, 0.6))
		"reaction":
			var pr: Vector3 = ev["pos"]
			vfx.word(pr + Vector3.UP * 1.6, str(ev.get("name", "REACTION")).to_upper() + "!", Color(1, 1, 1), 72)
			vfx.emit("burst", pr + Vector3.UP * 0.8, Vector3.UP, Elements.color(str(ev["a"])), 1.4)
		"slam":
			camera.add_trauma(0.4)
			vfx.word(ev["pos"] + Vector3.UP * 1.0, "CAGE SLAM!", Color(1.0, 0.8, 0.3))
		"round_intro":
			hud.callout("ROUND %d" % int(ev["round"]), 1.8)
			for v2 in views:
				v2.clear_bruises()
		"round_start":
			hud.callout("FIGHT!", 1.0, Color(1.0, 0.85, 0.3))
		"round_end":
			var w := int(ev["winner"])
			hud.callout("DRAW" if w < 0 else "%s WINS THE ROUND" % _team_label(w), 2.4)
		"timeout":
			hud.callout("TIME!", 1.2)
		"match_end":
			var w2 := int(ev["winner"])
			hud.callout("DRAW!" if w2 < 0 else "%s WINS!" % _team_label(w2), 3.0, Color(1.0, 0.85, 0.3))
		"round_reset":
			for i in sim.fighters.size():
				views[i].snap_transforms(sim.fighters[i].rig.segment_transforms())


func _team_label(team: int) -> String:
	var names := []
	for f in sim.fighters:
		if f.team == team:
			names.append(f.display_name.to_upper())
	return " & ".join(names) if not names.is_empty() else TeamColors.name(team).to_upper()


func _seg_near(fi: int, p: Vector3) -> int:
	var f := sim.fighters[fi]
	var best := 0
	var bd := INF
	for i in f.rig.bodies.size():
		var d := f.rig.bodies[i].global_position.distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _on_finished(result: Dictionary) -> void:
	match_finished.emit(result)
