class_name ChumballMode
extends MatchMode
## CHUMBALL (docs/design/MODES.md §2.2): a 25 kg physics ball, two goals. Weapon contacts move the
## ball with the hit's knockback ×2; projectiles/areas/pushes move it too; Grab picks it up
## (carrier slowed, cannot attack, throws a 6 m lob; hit = drop). The ball carries the last
## element that struck it for 3 s and applies build-up to fighters it hits. Goals reset play.

const BALL_RADIUS := 0.5

var ball: RigidBody3D
var ball_spawn := Vector3.ZERO
var goals := {}                  ## team -> {pos, normal (into the field), width}
var carrier: Fighter = null
var last_touch: Fighter = null
var ball_element := ""
var _element_until := 0.0
var _reset_at := -1.0
var _contact_cd := {}            ## fighter index -> time
var keeper := {}                 ## team -> fighter index (bots)


func id() -> String:
	return "chumball"


func setup(match_sim) -> void:
	var defaults := {"round_time": 240.0, "rounds": 1, "win": "score", "score_target": 5, "respawn": true,
		"respawn_delay": 6.0, "ball_mass": 25.0, "goal_width": 3.0, "own_goals": true, "carry": true, "chaos": false, "hot_ball": false}
	for k in defaults:
		if not match_sim.rules.has(k):
			match_sim.rules[k] = defaults[k]
	super.setup(match_sim)
	for t in [0, 1]:
		scores[t] = 0.0
	var gm := sim.arena.markers_of("goal")
	for g in gm:
		var team := int(g["team"])
		if team < 0:
			team = goals.size()
		var p: Vector3 = g["pos"]
		var inward := -Vector3(p.x, 0.0, p.z).normalized()
		goals[team] = {"pos": Vector3(p.x, 0.0, p.z), "normal": inward, "width": float(rules["goal_width"])}
	if goals.size() < 2:
		goals.clear()
		var edge := sim.arena.radius - 0.15
		goals[0] = {"pos": Vector3(0, 0, -edge), "normal": Vector3(0, 0, 1), "width": float(rules["goal_width"])}
		goals[1] = {"pos": Vector3(0, 0, edge), "normal": Vector3(0, 0, -1), "width": float(rules["goal_width"])}
	var bs := sim.arena.marker_points("ball_spawn")
	ball_spawn = bs[0] if not bs.is_empty() else Vector3.ZERO
	_make_ball()
	for f: Fighter in sim.fighters:
		if f.controller_kind == "bot" and not keeper.has(f.team):
			keeper[f.team] = f.index


func _make_ball() -> void:
	ball = RigidBody3D.new()
	ball.name = "Chumball"
	ball.mass = float(rules["ball_mass"])
	ball.collision_layer = Rig.LAYER_PROPS
	ball.collision_mask = Rig.LAYER_WORLD | Rig.LAYER_FIGHTERS | Rig.LAYER_PROPS
	ball.continuous_cd = true
	ball.can_sleep = false
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.6
	pm.friction = 0.5
	ball.physics_material_override = pm
	ball.linear_damp = 0.25
	ball.angular_damp = 0.6
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = BALL_RADIUS
	cs.shape = sp
	ball.add_child(cs)
	sim.add_child(ball)
	ball.global_position = ball_spawn + Vector3.UP * 1.2
	sim.register_hittable({"id": "ball", "body": ball, "radius": BALL_RADIUS, "reach_up": 1.0, "on_hit": _on_ball_hit})


func _on_ball_hit(a: Fighter, dir: Vector3, kb: float, launch: float, element: String, _point: Vector3) -> void:
	if _reset_at > 0.0:
		return
	if carrier:
		_drop()
	var dv := dir * kb * 2.0 * sqrt(25.0 / maxf(5.0, ball.mass)) + Vector3.UP * (launch + kb * 0.25)
	ball.apply_central_impulse(dv * ball.mass)
	if a:
		last_touch = a
	if element != "":
		ball_element = element
		_element_until = sim.time + 3.0


func intercept_actions(f: Fighter) -> bool:
	if f != carrier:
		return false
	# the carrier cannot attack: any attack/grab press throws the ball
	var throw_now := false
	var throw_buttons := [FighterInput.GRAB, FighterInput.LIGHT, FighterInput.HEAVY]
	if f.combat_style == "moves":
		# All four named moves are offensive inputs, including the slots that used to be
		# abilities. Varga also throws with his two leg inputs instead of kicking the ball.
		throw_buttons.append_array([FighterInput.AB1, FighterInput.AB2])
		if f.creature.tags.has("martial"):
			throw_buttons.append_array([FighterInput.MMA_LL, FighterInput.MMA_RL])
	for b in throw_buttons:
		if f._consume(b):
			throw_now = true
	if throw_now:
		_throw(f)
		return true
	return false


func on_grab_pressed(f: Fighter) -> bool:
	if not bool(rules["carry"]) or carrier != null or _reset_at > 0.0 or f.is_down():
		return false
	if ball.global_position.distance_to(f.pos() + f.forward() * 0.5) > 1.3:
		return false
	carrier = f
	last_touch = f
	f.set_flag("carrying", 999.0)
	ball.freeze = true
	ball.collision_layer = 0
	sim.emit_event({"type": "ball_pickup", "fighter": f.index})
	return true


func _throw(f: Fighter) -> void:
	var dir := f.input.move.normalized() if f.input.move.length() > 0.3 else f.forward()
	_drop()
	var dist := 6.0
	var air := 0.9
	ball.global_position = f.pos() + dir * 0.7 + Vector3.UP * 0.6
	ball.linear_velocity = dir * (dist / air) + Vector3.UP * (9.81 * air * 0.5)
	sim.emit_event({"type": "ball_throw", "fighter": f.index})


func _drop() -> void:
	if carrier:
		carrier.clear_flag("carrying")
	carrier = null
	ball.freeze = false
	ball.collision_layer = Rig.LAYER_PROPS


func tick_fight(dt: float) -> void:
	if _reset_at > 0.0:
		if sim.time >= _reset_at:
			_reset_at = -1.0
			_drop()
			ball.freeze = false
			ball.global_position = ball_spawn + Vector3.UP * 1.2
			ball.linear_velocity = Vector3.ZERO
			ball.angular_velocity = Vector3.ZERO
			if not bool(rules["chaos"]):
				for i in sim.fighters.size():
					var f := sim.fighters[i]
					if f.despawned or f.is_out():
						continue
					var sp := choose_respawn(f)
					f.respawn(sp[0], sp[1])
			sim.emit_event({"type": "ball_reset"})
		return
	if carrier:
		if carrier.is_out() or carrier.despawned or carrier.state in [Fighter.State.HITSTUN, Fighter.State.KNOCKDOWN, Fighter.State.DOWN, Fighter.State.GUARD_BREAK, Fighter.State.HELD]:
			_drop()
			sim.emit_event({"type": "ball_drop"})
		else:
			ball.global_position = carrier.pos() + carrier.forward() * 0.65 + Vector3.UP * 0.35
			carrier.rig.desired_vel *= 0.8
	if ball.global_position.y < -3.0:
		_reset_at = sim.time + 0.5
		return
	if ball_element != "" and sim.time > _element_until:
		ball_element = ""
	# the ball's contact with fighters at speed: element build-up / hot ball
	var spd := ball.linear_velocity.length()
	if spd > 3.0 and carrier == null:
		for o: Fighter in sim.fighters:
			if o.despawned or o.is_out() or float(_contact_cd.get(o.index, -1.0)) > sim.time:
				continue
			var c := sim.combat.find_contact(ball.global_position, BALL_RADIUS, o)
			if c.is_empty():
				continue
			_contact_cd[o.index] = sim.time + 0.5
			if ball_element != "" and last_touch and o != last_touch:
				o.statuses.add_buildup(ball_element, 20.0, last_touch)
			if bool(rules["hot_ball"]) and spd > 6.0:
				sim.combat.apply_simple_damage(last_touch, o, 4.0, "hot_ball")
	# goals
	for t in goals:
		var g: Dictionary = goals[t]
		var rel: Vector3 = ball.global_position - g["pos"]
		var depth := rel.dot(g["normal"])
		var lateral := absf(rel.dot((g["normal"] as Vector3).cross(Vector3.UP)))
		if depth < 0.55 and lateral <= float(g["width"]) * 0.5 and ball.global_position.y < 2.2:
			var scorer_team := 1 - int(t)
			if last_touch and last_touch.team == int(t) and not bool(rules["own_goals"]):
				_reset_at = sim.time + 1.0
				sim.emit_event({"type": "own_goal_denied", "team": int(t)})
				return
			scores[scorer_team] = float(scores.get(scorer_team, 0.0)) + 1.0
			sim.emit_event({"type": "goal", "team": scorer_team, "scorer": last_touch.index if last_touch else -1, "own_goal": last_touch != null and last_touch.team == int(t)})
			_reset_at = sim.time + 3.0
			if sudden_death or float(scores[scorer_team]) >= float(rules["score_target"]):
				end_round(scorer_team)
			return


func start_sudden_death() -> void:
	sudden_death = true
	sim.emit_event({"type": "sudden_death"})


func on_timeout() -> void:
	if float(scores.get(0, 0.0)) == float(scores.get(1, 0.0)):
		if not bool(rules.get("sudden_death", true)):
			end_round(-1)
			return
		start_sudden_death()
	else:
		end_round(0 if float(scores.get(0, 0.0)) > float(scores.get(1, 0.0)) else 1)


func check_round_over() -> void:
	# eliminations never end a Chumball round; only goals and time do
	pass


## KOs give nothing in Chumball; the ball gives everything (MODES.md). The preset wins on
## "score", so MatchMode's default would add ko_points per KO to the same totals as goals.
func on_elimination(_f: Fighter, _attacker: Fighter) -> void:
	pass


func choose_respawn(f: Fighter) -> Array:
	var g: Dictionary = goals.get(f.team, goals[0])
	var p: Vector3 = g["pos"] + (g["normal"] as Vector3) * 1.8
	p += (g["normal"] as Vector3).cross(Vector3.UP) * sim.rng.randf_range(-1.2, 1.2)
	return [sim.clamp_to_arena(p, 0.6), atan2((g["normal"] as Vector3).x, (g["normal"] as Vector3).z)]


func focus_point(f: Fighter):
	if ball == null or f == carrier:
		return null
	return ball.global_position


func hud_status() -> String:
	if _reset_at > 0.0:
		return "GOAL! Kick-off in %ds" % ceili(_reset_at - sim.time)
	if sudden_death:
		return "GOLDEN GOAL — next goal wins"
	if carrier:
		return "%s has the chum" % carrier.display_name
	return "First to %d goals" % int(rules["score_target"])


func hud_state() -> Dictionary:
	var rows := []
	for t in [0, 1]:
		rows.append({"label": TeamColors.name(t), "value": int(scores.get(t, 0.0)), "team": t})
	return {"rows": rows, "status": hud_status(), "target": int(rules["score_target"])}


func view_state() -> Dictionary:
	var v := super.view_state()
	v["ball"] = ball.global_transform if ball else Transform3D()
	v["ball_element"] = ball_element
	v["carrier"] = carrier.index if carrier else -1
	var gl := []
	for t in goals:
		gl.append({"team": int(t), "pos": goals[t]["pos"], "normal": goals[t]["normal"], "width": goals[t]["width"]})
	v["goals"] = gl
	return v


func bot_objective(f: Fighter) -> Dictionary:
	var base := super.bot_objective(f)
	if not base.is_empty():
		return base
	var bp := ball.global_position
	var opp: Dictionary = goals.get(1 - f.team, goals[0])
	var own: Dictionary = goals.get(f.team, goals[0])
	if f == carrier:
		var to_goal: Vector3 = opp["pos"] - f.pos()
		to_goal.y = 0.0
		return {"pos": opp["pos"], "engage": 99.0, "throw": to_goal.length() < 6.5, "radius": 0.5}
	if int(keeper.get(f.team, -1)) == f.index:
		var guard_pos: Vector3 = own["pos"] + ((bp - own["pos"]).normalized() * minf(3.5, (bp - own["pos"]).length() * 0.5))
		guard_pos.y = 0.0
		var near := Vector2(bp.x - f.pos().x, bp.z - f.pos().z).length() < 1.6
		return {"pos": bp if near else guard_pos, "engage": 1.5, "strike": near, "aim": opp["pos"], "radius": 0.4}
	var to_opp: Vector3 = opp["pos"] - bp
	to_opp.y = 0.0
	var behind := bp - to_opp.normalized() * 0.9
	behind.y = 0.0
	var d := Vector2(behind.x - f.pos().x, behind.z - f.pos().z).length()
	var close := Vector2(bp.x - f.pos().x, bp.z - f.pos().z).length() < 1.4
	return {"pos": bp if d < 0.6 or close else behind, "engage": 1.2, "strike": close, "aim": opp["pos"], "radius": 0.3,
		"grab_ball": close and sim.rng.randf() < 0.02}
