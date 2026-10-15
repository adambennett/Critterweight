class_name SpotlightHogMode
extends MatchMode
## SPOTLIGHT HOG (docs/design/MODES.md §2.1): a roaming spotlight dwells on an anchor, then swings
## to the next in a seeded order. A side standing in it uncontested scores 1 point/s; contested =
## nobody scores; KOs are worth points; first to the target (or most at time) wins. Ties go to a
## shrunken-light sudden death: first side to hold it 5 uncontested seconds.

var anchors: Array = []          ## Array[Vector3]
var order: Array = []            ## anchor indices in seeded visiting order
var order_pos := 0
var light_pos := Vector3.ZERO
var light_from := Vector3.ZERO
var light_to := Vector3.ZERO
var light_t := 0.0
var swinging := false
var radius := 2.0
var hog := -1                    ## scoring team, -1 nobody, -2 contested
var _sd_hold := 0.0
var _sd_team := -1


func id() -> String:
	return "spotlight_hog"


func setup(match_sim) -> void:
	var defaults := {"round_time": 300.0, "rounds": 1, "win": "score", "score_target": 60, "respawn": true,
		"respawn_delay": 5.0, "ko_points": 3, "light_radius": 2.0, "dwell": 25.0, "swing_time": 1.5, "contest": "strict"}
	for k in defaults:
		if not match_sim.rules.has(k):
			match_sim.rules[k] = defaults[k]
	super.setup(match_sim)
	radius = float(rules["light_radius"])
	anchors = sim.arena.marker_points("spotlight_anchor").duplicate()
	if anchors.size() < 3:
		anchors = [Vector3.ZERO]
		var rr := sim.arena.radius * 0.5
		for i in 4:
			var a := TAU * i / 4.0 + PI * 0.25
			anchors.append(Vector3(cos(a) * rr, 0.0, sin(a) * rr))
	order = range(anchors.size())
	_shuffle(order)
	order_pos = 0
	light_pos = anchors[order[0]]
	light_to = light_pos


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := sim.rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


func _next_anchor() -> Vector3:
	order_pos += 1
	if order_pos >= order.size():
		var last: int = order[order.size() - 1]
		_shuffle(order)
		if order[0] == last and order.size() > 1:
			order.reverse()
		order_pos = 0
	return anchors[order[order_pos]]


func tick_fight(dt: float) -> void:
	var dwell := float(rules["dwell"])
	var swing := float(rules["swing_time"])
	light_t += dt
	if swinging:
		light_pos = light_from.lerp(light_to, MathX.smooth01(light_t / swing))
		if light_t >= swing:
			swinging = false
			light_t = 0.0
			light_pos = light_to
	elif light_t >= dwell and not sudden_death:
		swinging = true
		light_t = 0.0
		light_from = light_pos
		light_to = _next_anchor()
		sim.emit_event({"type": "spotlight_swing", "pos": light_to})
	var teams := {}
	for f: Fighter in sim.fighters:
		if f.despawned or f.is_out() or f.is_down():
			continue
		var d := Vector2(f.pos().x - light_pos.x, f.pos().z - light_pos.z).length()
		if d <= radius:
			teams[f.team] = int(teams.get(f.team, 0)) + 1
	var prev_hog := hog
	hog = -1
	if not swinging and not teams.is_empty():
		if teams.size() == 1:
			hog = int(teams.keys()[0])
		elif str(rules["contest"]) == "majority":
			var best := -1
			var bn := 0
			var tie := false
			for t in teams:
				if int(teams[t]) > bn:
					bn = int(teams[t])
					best = int(t)
					tie = false
				elif int(teams[t]) == bn:
					tie = true
			hog = -2 if tie else best
		else:
			hog = -2
	if bool(rules.get("hot_light", false)) and not swinging:
		for f: Fighter in sim.fighters:
			if not f.despawned and not f.is_out() and Vector2(f.pos().x - light_pos.x, f.pos().z - light_pos.z).length() <= radius:
				f.statuses.add_buildup("scorch", 5.0 * dt, null)
	if sudden_death:
		if hog >= 0 and hog == _sd_team:
			_sd_hold += dt
			if _sd_hold >= 5.0:
				end_round(hog)
		else:
			_sd_team = hog
			_sd_hold = 0.0
		return
	if hog >= 0:
		scores[hog] = float(scores.get(hog, 0.0)) + dt
		if prev_hog != hog:
			sim.emit_event({"type": "hog_start", "team": hog})
		if float(scores[hog]) >= float(rules["score_target"]):
			end_round(hog)
	elif hog == -2 and prev_hog != -2:
		sim.emit_event({"type": "contested"})


func start_sudden_death() -> void:
	sudden_death = true
	radius = 1.0
	_sd_hold = 0.0
	_sd_team = -1
	sim.emit_event({"type": "sudden_death"})


func choose_respawn(f: Fighter) -> Array:
	return sim.safe_spawn_for(f, light_pos, radius + 3.0)


func hud_status() -> String:
	if sudden_death:
		return "SUDDEN DEATH — hold the small light for 5 seconds"
	if swinging:
		return "The light is moving!"
	match hog:
		-1:
			return "Spotlight open — %ds until it swings" % ceili(float(rules["dwell"]) - light_t)
		-2:
			return "CONTESTED — nobody scores"
	return "%s is hogging the light" % _team_label(hog)


func _team_label(team: int) -> String:
	var names := []
	for f: Fighter in sim.fighters:
		if f.team == team and not f.despawned:
			names.append(f.display_name)
	return " & ".join(names) if names.size() <= 2 else TeamColors.name(team)


func hud_state() -> Dictionary:
	var rows := []
	for t in scores:
		rows.append({"label": _team_label(int(t)), "value": int(floor(float(scores[t]))), "team": int(t), "highlight": int(t) == hog})
	rows.sort_custom(func(a, b): return a["value"] > b["value"])
	return {"rows": rows, "status": hud_status(), "target": int(rules["score_target"])}


func view_state() -> Dictionary:
	var v := super.view_state()
	v["light"] = light_pos
	v["radius"] = radius
	v["swinging"] = swinging
	v["next"] = light_to
	v["countdown"] = maxf(0.0, float(rules["dwell"]) - light_t) if not swinging else 0.0
	v["hog"] = hog
	v["anchors"] = anchors
	return v


func bot_objective(f: Fighter) -> Dictionary:
	var base := super.bot_objective(f)
	if not base.is_empty():
		return base
	var goal := light_pos
	# good bots pre-move to the next anchor shortly before the swing
	if not swinging and light_t > float(rules["dwell"]) - 3.0 and order.size() > 1:
		var peek: int = order[(order_pos + 1) % order.size()]
		goal = anchors[peek]
	var my_side := 0
	var their_side := 0
	for o: Fighter in sim.fighters:
		if o.despawned or o.is_out():
			continue
		if Vector2(o.pos().x - light_pos.x, o.pos().z - light_pos.z).length() <= radius + 1.0:
			if o.team == f.team:
				my_side += 1
			else:
				their_side += 1
	if their_side >= my_side + 2:
		return {"pos": sim.clamp_to_arena(goal + (f.pos() - goal).normalized() * (radius + 2.5), 0.8), "engage": 1.5}
	return {"pos": goal, "engage": radius * 0.8, "radius": radius * 0.5}
