class_name MatchScene
extends Node3D
## Runs a LOCAL authoritative match with full presentation: MatchSim + ArenaView +
## CreatureViews + VFX + camera + HUD, translating simulation events into feedback.
## (Networked clients use NetMatchScene, which renders the same views from snapshots.)
## With a referee (sim.mode.has_referee(), MCH-08) a view-only RefereeView stands in the arena as
## a sibling of ModeView (never under it, never in camera framing), fed every rendered frame from
## RefereeView.state_from_sim(sim). 10-point cards and decisions (round_scored, judges_decision)
## and the referee's count / wave-up / stoppage are presented by FightHud and callouts.

signal match_finished(result: Dictionary)

var sim: MatchSim
var arena_view: ArenaView
var views: Array = []           ## index -> CreatureView (null for despawned slots)
var vfx: Vfx
var ability_fx: AbilityVfx      ## v0.9.17 ability effects (docs/art/VFX.md)
var mode_view: ModeView
var _pick_panel: Control = null
var _dt := 0.016
var camera: FightCamera
var hud: FightHud
var hud_layer: CanvasLayer
var player_index := 0
## The profile owner's fighter (the first local player): wears the profile's Cannery cosmetics
## (FighterCosmetics, view-only). -1 when no local player fights (spectating, AI-only tapes).
var owner_index := -1
var _event_cursor := 0
var config := {}
var director: SpectatorDirector = null   ## auto-director when spectating (cfg.spectate)
var _goals_by_me := 0
var _debug: CombatDebugDraw = null
var _bench_hint: Label = null   ## campaign tag-team fights: what a benched partner can do
var _pause_until_us := 0        ## hit pause end (Time ticks), 0 = none
var _pause_base := 1.0          ## the time scale a hit pause returns to
var _pause_token := 0           ## the latest hit pause (only its timer ends the pause)
var referee_view: RefereeView = null   ## the view-only referee (only when the sim runs one)
var _decision_round := -1       ## 10-point: the round a judges' decision closed (its callout stays)
var _scored_round := -1         ## 10-point: the last round the judges scored (round_scored)
var _stopped_round := -1        ## the round the referee stopped (the T.K.O. callout stays)


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
	camera.open_stage = (cfg["arena"] as ArenaDef).base == "rooftop_canvas"
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
				if owner_index < 0:
					owner_index = idx
				# accessibility aim assist is part of the fighter's (replicated) modifiers
				var m: Dictionary = (entry.get("mods", {}) as Dictionary).duplicate()
				m["assist"] = float({"low": 0.5, "normal": 1.0, "high": 1.8}.get(str(Settings.get_value("access.target_assist")), 1.0))
				entry["mods"] = m
			"policy":
				# AI Lab policy: e.policy_id (falls back to a scripted bot if missing/incompatible)
				var rules_d = cfg.get("rules", {})
				var style := "classic" if typeof(rules_d) == TYPE_DICTIONARY and str((rules_d as Dictionary).get("combat", MatchSim.default_combat)) == "classic" else "moves"
				entry["source"] = PolicyInputSource.for_match(e, int(cfg.get("seed", 1)) * 31 + idx, idx, style)
			"bot":
				var bb := BotBrain.new(str(e.get("difficulty", "regular")), int(cfg.get("seed", 1)) * 31 + idx)
				bb.set_personality((e["creature"] as CreatureDef).ai)
				entry["source"] = bb
			_:
				entry["source"] = e.get("source")
		entries.append(entry)
		idx += 1
	Log.i("match", "start %s on %s: %s" % [str((cfg.get("rules", {}) as Dictionary).get("id", "?")), (cfg["arena"] as ArenaDef).id,
		", ".join(entries.map(func(en): return "%s/t%d/%s" % [(en["creature"] as CreatureDef).id, int(en.get("team", -1)), str(en.get("kind", "bot"))]))])
	sim = MatchSim.new()
	sim.running = false
	add_child(sim)
	sim.setup({"arena": cfg["arena"], "rules": cfg.get("rules", {}), "seed": cfg.get("seed", 1),
		"mode": cfg.get("mode"), "fighters": entries})
	for f in sim.fighters:
		views.append(null)
		_make_view(f.index)
	vfx = Vfx.new()
	add_child(vfx)
	ability_fx = AbilityVfx.new()
	ability_fx.view_of = func(i: int): return views[i] if i >= 0 and i < views.size() else null
	ability_fx.info_of = _fx_info
	ability_fx.fighter_count = func() -> int: return sim.fighters.size() if sim else 0
	add_child(ability_fx)
	mode_view = ModeView.new()
	add_child(mode_view)
	mode_view.head_of = _head_of
	if sim.mode != null and sim.mode.has_referee():
		# a sibling of ModeView (ModeView frees its children); not part of camera framing
		referee_view = RefereeView.new()
		add_child(referee_view)
		referee_view.setup(cfg["arena"], sim.rules)
	camera.points_provider = _camera_points
	camera.focus_provider = _camera_focus
	if bool(cfg.get("spectate", false)):
		director = SpectatorDirector.new(sim)
	camera.snap()
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	hud = FightHud.new()
	hud_layer.add_child(hud)
	hud.setup(sim, player_index)
	var ctx = cfg.get("context", {})
	if typeof(ctx) == TYPE_DICTIONARY and bool((ctx as Dictionary).get("campaign", false)):
		_bench_hint = NetMatchScene.bench_label(hud_layer)
	sim.finished.connect(_on_finished)
	_apply_presentation_settings()
	# audio bridge: impacts, voices, crowd, announcer and music follow the sim (docs/AUDIO.md §6)
	Audio.attach_match(sim, player_index, audio_context(cfg))
	Audio.music(str(cfg.get("music", _default_music())), 1.5, {"seed": int(cfg.get("seed", 1))})
	if not Audio.subtitle.is_connected(hud.subtitle):
		Audio.subtitle.connect(hud.subtitle)
	# accessibility game speed: offline matches with a local player only (recorded as custom)
	var speed := float(Settings.get_value("access.game_speed"))
	if speed < 0.999 and not bool(cfg.get("online", false)) and not bool(cfg.get("spectate", false)) and _is_local_player():
		Engine.time_scale = speed
	if OS.get_cmdline_user_args().has("--debug-draw"):
		toggle_debug_draw()
	if cfg.has("overlay_script"):
		var ov = load(str(cfg["overlay_script"])).new()
		hud_layer.add_child(ov)
		if ov.has_method("bind"):
			ov.call("bind", self)


## The commentary context of a match config (docs/audio/COMMENTARY.md): a Career bout tells the booth
## what kind of bout it is (debut, title fight, champion defending); a spectated match has no "player"
## for the booth to address.
static func audio_context(cfg: Dictionary) -> Dictionary:
	var out := {"context": str(cfg.get("audio_context", "versus"))}
	var ctx = cfg.get("context", {})
	if typeof(ctx) == TYPE_DICTIONARY and bool((ctx as Dictionary).get("career", false)):
		out["context"] = "career"
		out["career"] = ((ctx as Dictionary).get("booth", {"title": bool((ctx as Dictionary).get("title", false))}) as Dictionary).duplicate()
	elif bool(cfg.get("spectate", false)) and not cfg.has("audio_context"):
		out["context"] = "spectate"
	return out


## Combat debug visualization (F3): hit capsules, weapon spheres by phase, reach, targets, hits.
func toggle_debug_draw() -> void:
	if _debug and is_instance_valid(_debug):
		_debug.visible = not _debug.visible
		return
	_debug = CombatDebugDraw.new()
	add_child(_debug)
	_debug.setup(sim)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_F3:
		toggle_debug_draw()
		get_viewport().set_input_as_handled()


func _default_music() -> String:
	var m := sim.mode.id() if sim.mode else "standard"
	if m != "standard" or sim.fighters.size() > 2:
		return "combat_b"
	return "combat_a"


func _exit_tree() -> void:
	_end_hit_pause()
	if hud and Audio.subtitle.is_connected(hud.subtitle):
		Audio.subtitle.disconnect(hud.subtitle)
	# A rematch starts the new scene before this one is freed: only reset the playback speed when no
	# newer match has taken over. The audio is ended only if it is still this match's own (the hub
	# or a newer match attached theirs before this scene left).
	var newer := App.current_scene != null and is_instance_valid(App.current_scene) and App.current_scene != self and App.current_scene is MatchScene
	if not newer:
		Engine.time_scale = 1.0          # spectator/accessibility speed never leaks out of the match
	Audio.end_match(sim)


func _make_view(i: int) -> void:
	if i < views.size() and views[i] != null:
		(views[i] as CreatureView).queue_free()
	while views.size() <= i:
		views.append(null)
	var f := sim.fighters[i]
	if f.despawned:
		views[i] = null
		return
	var v := CreatureView.new()
	add_child(v)
	v.setup(f.creature, TeamColors.color(f.team))
	v.gore_level = int({"full": 2, "reduced": 1, "off": 0}.get(str(Settings.get_value("access.gore")), 2))
	if i == owner_index and bool(config.get("cosmetics", true)):
		FighterCosmetics.dress(v, Profiles.current)
	elif i < (config.get("fighters", []) as Array).size() and typeof(config["fighters"][i]) == TYPE_DICTIONARY \
			and (config["fighters"][i] as Dictionary).has("cosmetics"):
		# an online guest's own look, as the server validated it (listen host; view only)
		FighterCosmetics.dress(v, NetProtocol.cosmetics_profile(config["fighters"][i]["cosmetics"]))
	v.snap_transforms(f.rig.segment_transforms())
	views[i] = v


func _head_of(i: int) -> Vector3:
	if i < 0 or i >= views.size() or views[i] == null:
		return Vector3.ZERO
	var f := sim.fighters[i]
	var hs: int = f.creature.body.seg_index.get("head", 0)
	return (views[i] as CreatureView).segment_world(hs).origin


func _apply_presentation_settings() -> void:
	camera.shake_scale = float(Settings.get_value("access.camera_shake"))
	vfx.reduce_flashes = bool(Settings.get_value("access.reduce_flashing"))
	vfx.quality = int(Settings.get_value("graphics.effects"))
	ability_fx.configure(int(Settings.get_value("graphics.effects")), bool(Settings.get_value("access.reduce_flashing")))
	arena_view.apply_quality(Settings.quality())


func _camera_points() -> Array:
	if director and camera.mode == FightCamera.Mode.SPECTATE:
		var dp := director.points()
		if not dp.is_empty():
			return dp
	var pts := []
	for f in sim.fighters:
		if f.despawned or f.state == Fighter.State.INACTIVE:
			continue
		if f.pos().y > -3.0:
			pts.append(f.pos())
	return pts


func _camera_focus() -> Array:
	if director and camera.mode == FightCamera.Mode.SPECTATE:
		var df := director.focus()
		if not df.is_empty():
			return df
	var me := sim.fighters[player_index]
	if me.state == Fighter.State.INACTIVE or me.pos().y < -3.0:
		# a tag partner on the bench (parked out of the arena): follow the teammate who is in
		for f in sim.fighters:
			if f != me and f.team == me.team and not f.despawned and f.state != Fighter.State.INACTIVE and f.pos().y > -3.0:
				return [f.pos(), f.target.pos() if f.target else null]
	return [me.pos(), me.target.pos() if me.target else null]


func _physics_process(dt: float) -> void:
	if sim == null or sim.paused:
		return
	sim.step(dt)
	_process_events()
	for i in sim.fighters.size():
		var f := sim.fighters[i]
		if f.despawned:
			continue
		if i >= views.size() or views[i] == null:
			_make_view(i)
		(views[i] as CreatureView).push_transforms(f.rig.segment_transforms())


func _process(delta: float) -> void:
	_dt = delta
	if sim == null:
		return
	var alpha := Engine.get_physics_interpolation_fraction()
	var live := sim.mode != null and sim.mode.phase == MatchMode.Phase.FIGHT
	for i in views.size():
		if views[i] == null or i >= sim.fighters.size():
			continue
		var f := sim.fighters[i]
		var cv: CreatureView = views[i]
		cv.juice_amount = 1.0 if f.time < f.juiced_until else 0.0
		cv.cosmetic_combat = live and f.state != Fighter.State.CELEBRATE
		cv.status_color = _status_color(f)
		cv.visible = not f.has_flag("submerged")
		cv.fx_mood = CreatureView.mood_for_state(f.state, f.health_frac())
		cv.fx_look = _head_of(f.target.index) if f.target != null and f.target.index < views.size() and views[f.target.index] != null else Vector3.INF
		cv.render(alpha)
	if sim.mode:
		mode_view.update_state(sim.mode.view_state(), _dt)
		_update_pick_panel()
	if referee_view:
		referee_view.update_view(RefereeView.state_from_sim(sim), camera.global_position, delta)
	if _bench_hint:
		var mf := sim.fighters[player_index] if player_index < sim.fighters.size() else null
		_bench_hint.visible = live and mf != null and _is_local_player() and mf.state == Fighter.State.INACTIVE and mf.health > 0.0
	var props: Array = sim.arena_nodes.get("props", [])
	for i in props.size():
		arena_view.set_prop_transform(i, (props[i] as Node3D).global_transform)
	arena_view.fade_occluders(camera.global_position, CameraOccluders.points_for(camera, _camera_focus()))
	ability_fx.sync_entities(sim.effects.entities)


## What the ability effects need to know about a fighter (view only).
func _fx_info(i: int) -> Dictionary:
	if sim == null or i < 0 or i >= sim.fighters.size():
		return {}
	var f := sim.fighters[i]
	return {"ground": f.ground_pos(), "yaw": f.facing_yaw, "state": f.state, "juiced": f.time < f.juiced_until,
		"hidden": f.has_flag("submerged"), "charge": f.move_charge if f._charging else -1.0,
		"out": f.despawned or f.state == Fighter.State.INACTIVE or f.pos().y < -3.0}


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
		if director:
			director.on_event(ev)
	if director:
		director.update(1.0 / Engine.physics_ticks_per_second)


func _on_event(ev: Dictionary) -> void:
	ability_fx.on_event(ev)
	match str(ev["type"]):
		"hit":
			var ti := int(ev["target"])
			var dmg := float(ev["damage"])
			var p: Vector3 = ev["point"]
			var n: Vector3 = ev["normal"]
			if ti >= views.size() or views[ti] == null:
				return
			var v: CreatureView = views[ti]
			var el := str(ev.get("element", ""))
			var col := Elements.color(el) if el != "" else Color(1.0, 0.9, 0.55)
			var blocked := bool(ev["blocked"])
			var counter := bool(ev.get("counter", false))
			# a local player's hits (given or taken) get the strong feedback (HitFeel)
			var involved := _is_local(ti) or _is_local(int(ev["fighter"]))
			if blocked:
				vfx.emit("spark", p, n, Color(0.6, 0.85, 1.0), 0.6)
				v.jolt(n, 0.3)
			else:
				v.flash(HitFeel.flash(dmg))
				v.jolt(n, HitFeel.flash(dmg) * (1.0 if involved else 0.6))
				v.add_bruise(_seg_near(ti, p), p, clampf(dmg / 16.0, 0.15, 1.0))
				vfx.emit("spark", p, n, col, HitFeel.spark_scale(dmg, involved))
				if dmg >= (6.0 if involved else 10.0):
					vfx.ring(p, 0.8, Color(1, 1, 1, 0.8), 0.25, false)
			# a stream's repeating ticks (Movesets): a light touch each, no hit pause or punch
			var tick := bool(ev.get("repeat", false))
			camera.add_trauma(HitFeel.trauma(dmg, involved) * (0.15 if tick else 1.0))
			if not tick:
				camera.punch(HitFeel.punch(dmg, blocked, involved))
				hit_pause(HitFeel.hit_pause(dmg, blocked, counter, involved))
			if counter:
				vfx.word(p + Vector3.UP * 0.3, "COUNTER!", Color(1.0, 0.75, 0.2))
			if (ti == player_index or int(ev["fighter"]) == player_index) and not tick:
				var r := HitFeel.rumble(dmg, blocked)
				Controls.rumble(r[0], r[1], r[2])
			if bool(Settings.get_value("gameplay.damage_numbers")) and dmg >= 0.5 and not tick:
				vfx.word(p + Vector3.UP * 0.25, "%d" % roundi(dmg), Color(0.75, 0.85, 1.0) if bool(ev["blocked"]) else Color(1.0, 0.95, 0.8), 40)
		"parry":
			var pp: Vector3 = ev.get("pos", sim.fighters[int(ev["fighter"])].pos())
			vfx.word(pp + Vector3.UP * 1.2, "PARRY!", Color(0.5, 0.9, 1.0))
			vfx.ring(pp + Vector3.UP * 1.0, 1.2, Color(0.6, 0.9, 1.0, 0.9), 0.3, false)
		"knockdown":
			var f := sim.fighters[int(ev["fighter"])]
			vfx.emit("dust", f.ground_pos(), Vector3.UP, Color(0.8, 0.75, 0.65, 0.5))
			camera.add_trauma(0.3)
		"ko":
			var fk := sim.fighters[int(ev["fighter"])]
			var away := fk.pos() - camera.global_position
			var ki := int(ev["fighter"])
			if ki < views.size() and views[ki] != null:
				(views[ki] as CreatureView).detach_piece(Vector3(away.x, 0, away.z))
			hud.callout("K.O.!", 2.0, Color(1.0, 0.35, 0.3))
			camera.add_trauma(0.5)
			camera.punch(0.8)
			hit_pause(HitFeel.ko_pause())
			vfx.stars(_head_of.bind(ki), 2.6)
		"guard_break":
			vfx.word(sim.fighters[int(ev["fighter"])].head_pos() + Vector3.UP * 0.3, "GUARD BREAK!", Color(1.0, 0.5, 0.2))
		"burst":
			var fb := sim.fighters[int(ev["fighter"])]
			vfx.ring(fb.ground_pos() + Vector3.UP * 0.05, 2.5, Color(1, 1, 1, 0.9), 0.35)
		"juice":
			var ji := int(ev["fighter"])
			var fj := sim.fighters[ji]
			var jc := Color(1.0, 0.6, 0.1)
			if ji < views.size() and views[ji] != null:
				jc = (views[ji] as CreatureView).juice_color    # a cosmetic JUICE colour (Sizzle) shows here too
			vfx.word(fj.head_pos() + Vector3.UP * 0.4, "JUICED!", jc, 80)
		"reaction":
			# the reaction's own effect is AbilityVfx's; the name pops here
			var pr: Vector3 = ev["pos"]
			vfx.word(pr + Vector3.UP * 1.6, str(ev.get("name", "REACTION")).to_upper() + "!", Color(1, 1, 1), 72)
		"elimination":
			var by := int(ev.get("by", -1))
			if by == player_index and _is_local_player() and by < sim.fighters.size() and sim.fighters[by].time < sim.fighters[by].juiced_until:
				Platform.unlock_achievement("ach_juice_ko")
		"slam":
			camera.add_trauma(0.4)
			vfx.word(ev["pos"] + Vector3.UP * 1.0, "CAGE SLAM!", Color(1.0, 0.8, 0.3))
		"round_intro":
			hud.callout("ROUND %d" % int(ev["round"]), 1.8)
			for v2 in views:
				if v2 != null:
					(v2 as CreatureView).clear_bruises()
		"round_start":
			hud.callout("FIGHT!", 1.0, Color(1.0, 0.85, 0.3))
		"round_end":
			var w := int(ev["winner"])
			var rn := int(ev.get("round", -9))
			if rn == _decision_round or rn == _stopped_round:
				pass   # the decision / T.K.O. callout stays (10-point: the cards, not this round, decide)
			elif hud.is_ten_point():
				hud.callout("EVEN ROUND" if w < 0 else "%s WINS THE ROUND" % _team_label(w), 2.4)
			else:
				hud.callout("DRAW" if w < 0 else "%s WINS THE ROUND" % _team_label(w), 2.4)
		"timeout":
			hud.callout("TIME!", 1.2)
		"round_scored":
			_scored_round = int(ev.get("round", -1))
			hud.show_round_card(ev)
		"judges_decision":
			var wd := int(ev.get("winner", -1))
			# the round the cards just closed (round_scored precedes the decision in the same tick)
			_decision_round = _scored_round if _scored_round > 0 else (sim.mode.round_index + 1 if sim.mode else -1)
			hud.show_decision(ev, _decision_round)
			hud.callout(FightHud.decision_callout(ev, _team_label(wd) if wd >= 0 else ""), 2.6, Color(1.0, 0.85, 0.3))
		"ref_count":
			var ci := int(ev.get("fighter", -1))
			if ci >= 0 and ci < sim.fighters.size():
				vfx.word(_head_of(ci) + Vector3.UP * 0.6, "%d" % int(ev.get("n", 0)), Color(1.0, 0.95, 0.85), 72)
		"ref_wave_up":
			var ui := int(ev.get("fighter", -1))
			if ui >= 0 and ui < sim.fighters.size():
				vfx.word(_head_of(ui) + Vector3.UP * 0.6, "UP!", Color(0.6, 0.95, 1.0), 64)
		"ref_stoppage":
			_stopped_round = int(ev.get("round", -1))
			hud.callout("T.K.O.!", 2.6, Color(1.0, 0.35, 0.3))
			camera.add_trauma(0.3)
		"match_end":
			Engine.time_scale = 1.0
			var w2 := int(ev["winner"])
			hud.callout("DRAW!" if w2 < 0 else "%s WINS!" % _team_label(w2), 3.0, Color(1.0, 0.85, 0.3))
		"round_reset":
			for i in sim.fighters.size():
				if i < views.size() and views[i] != null and not sim.fighters[i].despawned:
					(views[i] as CreatureView).snap_transforms(sim.fighters[i].rig.segment_transforms())
		"fighter_spawned", "fighter_rebuilt":
			_make_view(int(ev["fighter"]))
		"fighter_despawned":
			var di := int(ev["fighter"])
			if di < views.size() and views[di] != null:
				(views[di] as CreatureView).queue_free()
				views[di] = null
		"goal":
			hud.callout("GOAL!", 2.0, TeamColors.color(int(ev["team"])).lightened(0.3))
			if int(ev.get("scorer", -1)) == player_index and _is_local_player() and not bool(ev.get("own_goal", false)):
				_goals_by_me += 1
				if _goals_by_me >= 3:
					Platform.unlock_achievement("ach_hat_trick")
			Audio.announce_trigger("mode", {"mode": "chumball_goal"})
		"unit_crowned":
			hud.callout("%s IS THE ABSOLUTE UNIT" % sim.fighters[int(ev["fighter"])].display_name.to_upper(), 2.2, Color("#8BD426"))
			Audio.announce_trigger("mode", {"mode": "new_unit"}, {"p": sim.fighters[int(ev["fighter"])].display_name})
		"wave_start":
			hud.callout("WAVE %d" % int(ev["wave"]), 1.6, Color(1.0, 0.6, 0.3))
			if int(ev["wave"]) >= 20 and _is_local_player():
				Platform.unlock_achievement("ach_last_call")
			Audio.announce_trigger("mode", {"mode": "rush_wave"}, {"n": int(ev["wave"])})
		"wave_cleared":
			hud.callout("WAVE CLEARED", 1.4, Color(0.6, 1.0, 0.6))
		"gate_spawn":
			var gi := int(ev["fighter"])
			if gi < sim.fighters.size() and bool(sim.fighters[gi].flags.get("headliner", false)):
				hud.callout("HEADLINER: %s" % sim.fighters[gi].display_name.to_upper(), 2.0, Color(1.0, 0.4, 0.3))
				Audio.announce_trigger("mode", {"mode": "rush_headliner"}, {"o": sim.fighters[gi].display_name})
		"spotlight_swing":
			Audio.announce_trigger("mode", {"mode": "spotlight"})
		"sudden_death":
			hud.callout("SUDDEN DEATH", 1.8, Color(1.0, 0.35, 0.3))
		"move_denied":
			if int(ev.get("fighter", -1)) == player_index:
				hud.move_denied(str(ev.get("slot", "")), str(ev.get("why", "")))
			# the booth calls it from the event itself (CommentaryDirector)


func _is_local_player() -> bool:
	return player_index < sim.fighters.size() and sim.fighters[player_index].controller_kind == "player"


func _is_local(i: int) -> bool:
	return i >= 0 and i < sim.fighters.size() and sim.fighters[i].controller_kind == "player"


## Hit pause (HitFeel): the whole local match nearly stops for `sec` real seconds, then returns to
## the speed it had (accessibility or spectator speed included). A later hit extends a running
## pause instead of stacking. Never online: a listen host's clock is everyone's clock.
func hit_pause(sec: float) -> void:
	if sec <= 0.0 or bool(config.get("online", false)) or not is_inside_tree():
		return
	var end := Time.get_ticks_usec() + int(sec * 1e6)
	if _pause_until_us == 0:
		_pause_base = Engine.time_scale
	if end > _pause_until_us:
		_pause_until_us = end
		_pause_token += 1
		# real-time and pause-proof: a pause menu opened mid-freeze must not run at 4 % speed. The
		# latest hit's timer ends the pause (a timer may fire a hair early by the wall clock).
		get_tree().create_timer(sec, true, false, true).timeout.connect(_end_hit_pause.bind(_pause_token))
	Engine.time_scale = _pause_base * HitFeel.PAUSE_SCALE


func hit_paused() -> bool:
	return _pause_until_us != 0


## `token`: the hit whose timer fired (an older one is ignored); -1 ends any pause now.
func _end_hit_pause(token := -1) -> void:
	if _pause_until_us == 0 or (token >= 0 and token != _pause_token):
		return
	_pause_until_us = 0
	Engine.time_scale = _pause_base


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


## Chum Rush supplement pick for the local player (every 5th break).
func _update_pick_panel() -> void:
	if not (sim.mode is ChumRushMode):
		return
	var cr := sim.mode as ChumRushMode
	# only this machine's own fighter: a listen host who sits a match out keeps player_index 0 and
	# must not see (or answer) the offer of a remote player's fighter
	var mine: Array = cr.pending_pick.get(player_index, []) if _is_local_player() else []
	if mine.is_empty():
		if _pick_panel:
			_pick_panel.queue_free()
			_pick_panel = null
		return
	if _pick_panel:
		return
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
		b.pressed.connect(cr.choose_pick.bind(player_index, i))
		row.add_child(b)
		if first == null:
			first = b
	if first:
		first.grab_focus.call_deferred()
