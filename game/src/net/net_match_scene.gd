class_name NetMatchScene
extends Node3D
## Client presentation of a remote (server-authoritative) match. It reuses exactly the views of
## local play - ArenaView, CreatureView, Vfx, FightCamera, FightHud and (when installed)
## ModeView - but runs no simulation: bodies come from interpolated snapshots
## (NetReplica.sample), creature views follow the replicated roster (spawn/despawn/rebuild),
## feedback comes from replicated events fired when the render clock reaches their tick, and the
## HUD reads NetHudMirror. Local input is sampled by NetClient (camera-relative, same as
## LocalPlayerInput). Event feedback mirrors MatchScene._on_event (a parity test checks that every
## event MatchScene reacts to is handled here too). Mode choices offered to this player (e.g.
## Chum Rush picks) are sent to the server as requests; the server validates and applies them.

signal results_received(result: Dictionary)

const MODE_VIEW_SCRIPT := "res://src/view/mode_view.gd"

var info := {}
var replica: NetReplica = null
var client: NetClient = null
var arena_def: ArenaDef = null
var arena_view: ArenaView = null
var views: Array = []                ## slot -> CreatureView (null when empty/despawned)
var _view_gen := {}                  ## slot -> roster generation the view was built for
var vfx: Vfx = null
var camera: FightCamera = null
var hud: FightHud = null
var hud_layer: CanvasLayer = null
var mode_view: Node3D = null
var mirror: NetHudMirror = null
var my_index := -1
var director: SpectatorDirector = null   ## auto-director camera when this client spectates
var overlay: Label = null
var stats_provider: Callable
var _sample := {}
var _result := {}
var _pick_panel: Control = null
var _pick_key := ""
var _dt := 0.016
var _spec_label: Label = null
var _goals_by_me := 0


## info: MATCH_START dictionary from the server. Returns "" or an error text.
func start(info_: Dictionary, replica_: NetReplica, client_: NetClient = null) -> String:
	info = info_
	replica = replica_
	client = client_
	name = "NetMatchScene"
	my_index = int(info.get("you", -1))
	arena_def = ArenaDef.from_dict(info.get("arena", {}), "net")
	if not arena_def.errors.is_empty():
		return "invalid arena from server: %s" % "; ".join(arena_def.errors)
	for e in replica.roster.values():
		if not bool(e["despawned"]) and e.get("def") == null:
			return "creature '%s' used by the server is not installed" % str(e["creature"])
	arena_view = ArenaView.new()
	add_child(arena_view)
	arena_view.build(arena_def)
	camera = FightCamera.new()
	add_child(camera)
	camera.arena_radius = arena_def.radius
	sync_roster()
	vfx = Vfx.new()
	add_child(vfx)
	if ResourceLoader.exists(MODE_VIEW_SCRIPT):
		var mv_script: Script = load(MODE_VIEW_SCRIPT)
		mode_view = mv_script.new()
		add_child(mode_view)
		mode_view.set("head_of", Callable(self, "head_pos"))
	camera.points_provider = _camera_points
	camera.focus_provider = _camera_focus
	mirror = NetHudMirror.new()
	mirror.build(info, replica)
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	hud = FightHud.new()
	hud_layer.add_child(hud)
	hud.setup(mirror.sim, my_index)
	if my_index < 0:
		# spectators get the broadcast auto-director like local AI-vs-AI spectating
		director = SpectatorDirector.new(mirror.sim)
		camera.mode = FightCamera.Mode.SPECTATE
		_spec_label = Label.new()
		_spec_label.position = Vector2(16, 104)
		_spec_label.add_theme_font_size_override("font_size", 18)
		_spec_label.add_theme_constant_override("outline_size", 6)
		_spec_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_spec_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_layer.add_child(_spec_label)
	overlay = Label.new()
	overlay.position = Vector2(16, 140)
	overlay.add_theme_font_size_override("font_size", 16)
	overlay.add_theme_constant_override("outline_size", 6)
	overlay.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(overlay)
	_apply_presentation_settings()
	# audio bridge on the mirror: impacts, voices, crowd, announcer and music like local play
	var seed_v := int(info.get("match_id", 1))
	var ctx := "coop" if str((info.get("rules", {}) as Dictionary).get("format", "")) == "coop" else "versus"
	Audio.attach_match(mirror.sim, my_index, {"context": ctx, "seed": seed_v})
	Audio.music(_default_music(), 1.5, {"seed": seed_v})
	if not Audio.subtitle.is_connected(hud.subtitle):
		Audio.subtitle.connect(hud.subtitle)
	return ""


func _default_music() -> String:
	var m := str(info.get("mode", "standard"))
	if m != "standard" or replica.slot_count() > 2:
		return "combat_b"
	return "combat_a"


func _apply_presentation_settings() -> void:
	camera.shake_scale = float(Settings.get_value("access.camera_shake"))
	vfx.reduce_flashes = bool(Settings.get_value("access.reduce_flashing"))
	vfx.quality = int(Settings.get_value("graphics.effects"))
	arena_view.apply_quality(Settings.quality())


func _exit_tree() -> void:
	if hud and Audio.subtitle.is_connected(hud.subtitle):
		Audio.subtitle.disconnect(hud.subtitle)
	Audio.end_match()
	if mirror:
		mirror.free_all()
		mirror = null


## Creates/rebuilds/frees creature views to match the replicated roster (also refreshes the HUD
## mirror). Called on start and whenever the client applies a roster update.
func sync_roster() -> void:
	var n := replica.slot_count()
	while views.size() < n:
		views.append(null)
	for i in n:
		var e: Dictionary = replica.roster.get(i, {})
		var cv: CreatureView = views[i]
		if e.is_empty() or bool(e["despawned"]) or e.get("def") == null:
			if cv != null:
				cv.queue_free()
				views[i] = null
			_view_gen.erase(i)
			continue
		if cv != null and int(_view_gen.get(i, -1)) == int(e["gen"]):
			continue
		if cv != null:
			cv.queue_free()
		var v := CreatureView.new()
		add_child(v)
		v.setup(e["def"], TeamColors.color(int(e["team"])))
		v.gore_level = int({"full": 2, "reduced": 1, "off": 0}.get(str(Settings.get_value("access.gore")), 2))
		views[i] = v
		_view_gen[i] = int(e["gen"])
	if mirror:
		mirror.sync_roster(replica)


## Camera-relative movement basis for input sampling (LocalPlayerInput equivalent).
func input_basis() -> Basis:
	return camera.input_basis() if camera else Basis.IDENTITY


func _process(dt: float) -> void:
	_dt = dt
	if replica == null:
		return
	_sample = replica.sample()
	if _sample.is_empty():
		return
	var fl: Array = _sample["fighters"]
	for i in mini(fl.size(), views.size()):
		var cv: CreatureView = views[i]
		if cv == null:
			continue
		var fd: Dictionary = fl[i]
		if int(fd["gen"]) == 0 or int(fd["gen"]) != int(_view_gen.get(i, -1)):
			cv.visible = false
			continue
		var xf: Array[Transform3D] = fd["xforms"]
		if xf.is_empty():
			cv.visible = false
			continue
		var flags := int(fd["flags"])
		cv.visible = flags & NetSnapshot.F_HIDDEN == 0
		cv.snap_transforms(xf)
		cv.juice_amount = 1.0 if flags & NetSnapshot.F_JUICED else 0.0
		cv.status_color = _status_color(fd["statuses"])
		cv.render(1.0)
	for p in _sample["props"]:
		arena_view.set_prop_transform(int(p["index"]), Transform3D(Basis(p["rot"] as Quaternion), p["pos"]))
	vfx.sync_entities(_sample["entities"])
	mirror.update(_sample, dt)
	if mode_view:
		mode_view.call("update_state", _sample["mode"].get("view", {}), dt)
	_update_pick_panel()
	for ev in replica.pop_due_events():
		mirror.push_event(ev)
		_on_event(ev)
		if director:
			director.on_event(ev)
	if director:
		director.update(dt)
		if _spec_label:
			_spec_label.text = "SPECTATING  -  %s" % ("Free camera" if camera.mode == FightCamera.Mode.FREE else director.label())
	if overlay:
		overlay.visible = bool(Settings.get_value("diag.show_net"))
		if overlay.visible and stats_provider.is_valid():
			overlay.text = _overlay_text(stats_provider.call())


func _overlay_text(s: Dictionary) -> String:
	return "RTT %d ms  loss %.1f%%  snapshots %.0f/s  interp %d ms (jitter %d ms)\nin %.1f KB/s  out %.1f KB/s  buffer %d ms" % [
		roundi(float(s.get("rtt_ms", 0.0))), float(s.get("loss", 0.0)) * 100.0, float(s.get("snapshot_rate", 0.0)),
		roundi(float(s.get("interp_delay_ms", 0.0))), roundi(float(s.get("jitter_ms", 0.0))),
		float(s.get("in_kbps", 0.0)), float(s.get("out_kbps", 0.0)), roundi(float(s.get("buffer_ms", 0.0)))]


func _status_color(statuses: Array) -> Color:
	for s in statuses:
		var el := str(s.get("element", ""))
		if el != "":
			var c := Elements.color(el)
			c.a = 0.6
			return c
	return Color(0, 0, 0, 0)


func _slot(i: int) -> Dictionary:
	if _sample.is_empty():
		return {}
	var fl: Array = _sample["fighters"]
	if i < 0 or i >= fl.size():
		return {}
	var fd: Dictionary = fl[i]
	return fd if int(fd["gen"]) != 0 else {}


func root_pos(i: int) -> Vector3:
	var fd := _slot(i)
	return fd["root"] if not fd.is_empty() else Vector3.ZERO


func head_pos(i: int) -> Vector3:
	if i >= 0 and i < views.size() and views[i] != null:
		var e: Dictionary = replica.roster.get(i, {})
		if not e.is_empty() and e.get("def") != null:
			var hs := int((e["def"] as CreatureDef).body.seg_index.get("head", -1))
			if hs >= 0:
				return (views[i] as CreatureView).segment_world(hs).origin
	return root_pos(i) + Vector3.UP * 0.4


func ground_pos(i: int) -> Vector3:
	var p := root_pos(i)
	return Vector3(p.x, 0.0, p.z)


func _display_name(i: int) -> String:
	var e: Dictionary = replica.roster.get(i, {})
	return str(e.get("name", "Fighter %d" % i))


func _camera_points() -> Array:
	if director and camera.mode == FightCamera.Mode.SPECTATE:
		var dp := director.points()
		if not dp.is_empty():
			return dp
	var pts := []
	if _sample.is_empty():
		return pts
	var fl: Array = _sample["fighters"]
	for i in fl.size():
		var fd: Dictionary = fl[i]
		if int(fd["gen"]) == 0 or int(fd["state"]) == Fighter.State.INACTIVE:
			continue
		var p: Vector3 = fd["root"]
		if p.y > -3.0:
			pts.append(p)
	return pts


func _camera_focus() -> Array:
	if director and camera.mode == FightCamera.Mode.SPECTATE:
		var df := director.focus()
		if not df.is_empty():
			return df
	var me := _slot(my_index)
	if me.is_empty():
		var pts := _camera_points()
		return [pts[0] if not pts.is_empty() else Vector3.ZERO, null]
	var tgt := _slot(int(me["target"]))
	return [me["root"], tgt["root"] if not tgt.is_empty() else null]


## Spectator controls (same actions as the local SpectatorOverlay): Y / R toggles director and
## free camera, LB/RB (Q/E) lock the director on a fighter (past either end = auto again),
## X / Delete hides the HUD. Ignored while a menu screen is open.
func _unhandled_input(event: InputEvent) -> void:
	if director == null or camera == null:
		return
	if get_node_or_null("/root/App") != null and App.top_screen() != null:
		return
	if event.is_action_pressed("ui_alt"):
		get_viewport().set_input_as_handled()
		if camera.mode == FightCamera.Mode.FREE:
			camera.mode = FightCamera.Mode.SPECTATE
		else:
			camera.free_pos = camera.global_position
			camera.free_yaw = camera.global_rotation.y
			camera.free_pitch = clampf(camera.global_rotation.x, -1.2, 0.2)
			camera.mode = FightCamera.Mode.FREE
	elif event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev"):
		get_viewport().set_input_as_handled()
		director.cycle_lock(1 if event.is_action_pressed("ui_tab_next") else -1)
		if camera.mode == FightCamera.Mode.FREE:
			camera.mode = FightCamera.Mode.SPECTATE
	elif event.is_action_pressed("ui_extra"):
		get_viewport().set_input_as_handled()
		hud.visible = not hud.visible


func show_result(result: Dictionary) -> void:
	_result = result
	results_received.emit(result)


## MatchFlow (UI) asks scenes that are not a local MatchScene whether a match is in progress.
func is_match_running() -> bool:
	return _result.is_empty() and mirror != null and mirror.sim != null and not mirror.sim.is_finished


## Mode choices offered to this player (hud_state "picks"): a panel like the local one; the
## choice is sent to the server, which validates and applies it.
func _update_pick_panel() -> void:
	var hs: Dictionary = _sample["mode"].get("hud", {})
	var picks = hs.get("picks", {})
	var mine: Array = []
	if typeof(picks) == TYPE_DICTIONARY and my_index >= 0:
		var pd: Dictionary = picks
		var v = pd.get(my_index, pd.get(str(my_index), []))
		if typeof(v) == TYPE_ARRAY:
			mine = v
	var key := ",".join(PackedStringArray(mine.map(func(x): return str(x))))
	if mine.is_empty():
		if _pick_panel:
			_pick_panel.queue_free()
			_pick_panel = null
		_pick_key = ""
		return
	if _pick_panel and key == _pick_key:
		return
	if _pick_panel:
		_pick_panel.queue_free()
	_pick_key = key
	_pick_panel = PanelContainer.new()
	_pick_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pick_panel.custom_minimum_size = Vector2(760, 240)
	_pick_panel.offset_left = -380
	_pick_panel.offset_top = -120
	hud_layer.add_child(_pick_panel)
	var box := VBoxContainer.new()
	_pick_panel.add_child(box)
	var title := Label.new()
	title.text = "Pick a supplement"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var first: Button = null
	for i in mine.size():
		var u := Content.get_entry("supplements", str(mine[i]))
		var b := Button.new()
		b.text = "%s\n%s" % [str(u.get("name", mine[i])), str(u.get("description", u.get("effect", "")))]
		b.custom_minimum_size = Vector2(230, 150)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(_choose_pick.bind(i))
		row.add_child(b)
		if first == null:
			first = b
	if first:
		first.grab_focus.call_deferred()


func _choose_pick(i: int) -> void:
	if client:
		client.send_app("mode.pick", {"choice": i})
	if _pick_panel:
		_pick_panel.queue_free()
		_pick_panel = null


func _team_label(team: int) -> String:
	var names := []
	for i in replica.roster.keys():
		var e: Dictionary = replica.roster[i]
		if int(e["team"]) == team and not bool(e["despawned"]):
			names.append(str(e["name"]).to_upper())
	return " & ".join(names) if not names.is_empty() else TeamColors.name(team).to_upper()


func _seg_near(fi: int, p: Vector3) -> int:
	if fi < 0 or fi >= views.size() or views[fi] == null:
		return 0
	var fd := _slot(fi)
	if fd.is_empty():
		return 0
	var xf: Array[Transform3D] = fd["xforms"]
	var best := 0
	var bd := INF
	for i in xf.size():
		var d := xf[i].origin.distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


## Presentation of replicated simulation events (kept in step with MatchScene._on_event).
func _on_event(ev: Dictionary) -> void:
	var fi := int(ev.get("fighter", -1))
	match str(ev.get("type", "")):
		"hit":
			var ti := int(ev.get("target", -1))
			if ti < 0 or ti >= views.size() or views[ti] == null:
				return
			var dmg := float(ev.get("damage", 0.0))
			var p: Vector3 = ev.get("point", root_pos(ti))
			var n: Vector3 = ev.get("normal", Vector3.UP)
			var v: CreatureView = views[ti]
			var el := str(ev.get("element", ""))
			var col := Elements.color(el) if el != "" else Color(1.0, 0.9, 0.55)
			if bool(ev.get("blocked", false)):
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
			if ti == my_index or fi == my_index:
				Controls.rumble(clampf(dmg / 20.0, 0.1, 0.6), clampf(dmg / 30.0, 0.0, 0.8), 0.12)
			if bool(Settings.get_value("gameplay.damage_numbers")) and dmg >= 0.5:
				vfx.word(p + Vector3.UP * 0.25, "%d" % roundi(dmg), Color(0.75, 0.85, 1.0) if bool(ev.get("blocked", false)) else Color(1.0, 0.95, 0.8), 40)
		"parry":
			var pp: Vector3 = ev.get("pos", root_pos(fi))
			vfx.word(pp + Vector3.UP * 1.2, "PARRY!", Color(0.5, 0.9, 1.0))
			vfx.ring(pp + Vector3.UP * 1.0, 1.2, Color(0.6, 0.9, 1.0, 0.9), 0.3, false)
		"knockdown":
			vfx.emit("dust", ground_pos(fi), Vector3.UP, Color(0.8, 0.75, 0.65, 0.7))
			camera.add_trauma(0.3)
		"ko":
			if fi >= 0 and fi < views.size() and views[fi] != null:
				var away := root_pos(fi) - camera.global_position
				(views[fi] as CreatureView).detach_piece(Vector3(away.x, 0, away.z))
			hud.callout("K.O.!", 2.0, Color(1.0, 0.35, 0.3))
			camera.add_trauma(0.5)
		"guard_break":
			vfx.word(head_pos(fi) + Vector3.UP * 0.3, "GUARD BREAK!", Color(1.0, 0.5, 0.2))
		"burst":
			vfx.ring(ground_pos(fi) + Vector3.UP * 0.05, 2.5, Color(1, 1, 1, 0.9), 0.35)
		"juice":
			vfx.word(head_pos(fi) + Vector3.UP * 0.4, "JUICED!", Color(1.0, 0.6, 0.1), 80)
			vfx.emit("burst", root_pos(fi), Vector3.UP, Color(1.0, 0.6, 0.15), 1.5)
		"effect":
			var pe: Vector3 = ev.get("pos", Vector3.ZERO)
			var el2 := str(ev.get("element", ""))
			if str(ev.get("effect", "")) == "area":
				vfx.ring(pe + Vector3.UP * 0.05, 2.2, (Elements.color(el2) if el2 != "" else Color(1, 0.9, 0.6)) * Color(1, 1, 1, 0.8), 0.35)
				vfx.emit("dust", pe, Vector3.UP, Color(0.85, 0.8, 0.7, 0.6))
		"elimination":
			# achievements follow the server's events for this player's own fighter
			if fi != my_index and int(ev.get("by", -1)) == my_index and my_index >= 0:
				var me := _slot(my_index)
				if not me.is_empty() and int(me["flags"]) & NetSnapshot.F_JUICED:
					Platform.unlock_achievement("ach_juice_ko")
		"reaction":
			var pr: Vector3 = ev.get("pos", Vector3.ZERO)
			vfx.word(pr + Vector3.UP * 1.6, str(ev.get("name", "REACTION")).to_upper() + "!", Color(1, 1, 1), 72)
			vfx.emit("burst", pr + Vector3.UP * 0.8, Vector3.UP, Elements.color(str(ev.get("a", ""))), 1.4)
		"slam":
			camera.add_trauma(0.4)
			vfx.word((ev.get("pos", root_pos(fi)) as Vector3) + Vector3.UP * 1.0, "CAGE SLAM!", Color(1.0, 0.8, 0.3))
		"round_intro":
			hud.callout("ROUND %d" % int(ev.get("round", 1)), 1.8)
			for v2 in views:
				if v2 != null:
					(v2 as CreatureView).clear_bruises()
		"round_start":
			hud.callout("FIGHT!", 1.0, Color(1.0, 0.85, 0.3))
		"round_end":
			var w := int(ev.get("winner", -1))
			hud.callout("DRAW" if w < 0 else "%s WINS THE ROUND" % _team_label(w), 2.4)
		"timeout":
			hud.callout("TIME!", 1.2)
		"match_end":
			var w2 := int(ev.get("winner", -1))
			hud.callout("DRAW!" if w2 < 0 else "%s WINS!" % _team_label(w2), 3.0, Color(1.0, 0.85, 0.3))
		"round_reset":
			pass  # snapshots after a reset are detected as teleports and snap without interpolation
		"fighter_spawned", "fighter_rebuilt", "fighter_despawned":
			sync_roster()  # views follow the replicated roster (S_ROSTER precedes these events)
		"goal":
			hud.callout("GOAL!", 2.0, TeamColors.color(int(ev.get("team", 0))).lightened(0.3))
			if my_index >= 0 and int(ev.get("scorer", -1)) == my_index and not bool(ev.get("own_goal", false)):
				_goals_by_me += 1
				if _goals_by_me >= 3:
					Platform.unlock_achievement("ach_hat_trick")
			Audio.announce_trigger("mode", {"mode": "chumball_goal"})
		"unit_crowned":
			hud.callout("%s IS THE ABSOLUTE UNIT" % _display_name(fi).to_upper(), 2.2, Color("#8BD426"))
			Audio.announce_trigger("mode", {"mode": "new_unit"}, {"p": _display_name(fi)})
		"wave_start":
			hud.callout("WAVE %d" % int(ev.get("wave", 1)), 1.6, Color(1.0, 0.6, 0.3))
			if int(ev.get("wave", 1)) >= 20 and my_index >= 0:
				Platform.unlock_achievement("ach_last_call")
			Audio.announce_trigger("mode", {"mode": "rush_wave"}, {"n": int(ev.get("wave", 1))})
		"wave_cleared":
			hud.callout("WAVE CLEARED", 1.4, Color(0.6, 1.0, 0.6))
		"gate_spawn":
			var tags: Array = replica.roster.get(fi, {}).get("tags", [])
			if tags.has("headliner"):
				hud.callout("HEADLINER: %s" % _display_name(fi).to_upper(), 2.0, Color(1.0, 0.4, 0.3))
				Audio.announce_trigger("mode", {"mode": "rush_headliner"}, {"o": _display_name(fi)})
		"spotlight_swing":
			Audio.announce_trigger("mode", {"mode": "spotlight"})
		"sudden_death":
			hud.callout("SUDDEN DEATH", 1.8, Color(1.0, 0.35, 0.3))
			Audio.announce_trigger("time", {"kind": "sudden_death"})
