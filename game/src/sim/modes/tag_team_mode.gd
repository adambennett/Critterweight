class_name TagTeamMode
extends MatchMode
## TAG TEAM (docs/design/MODES.md §1, CAMPAIGN.md §11): one active fighter per side in the cage;
## partners wait on the apron outside the fence. Press Tag (D-pad Down / G) to swap (4 s cooldown;
## not while stunned/knocked down). Resting partners regenerate health, can Cheer (Taunt) to feed
## the active partner Hype, and can call one Assist (Ability 1) per 12 s: they vault in, perform a
## dash attack toward the enemy, and return. A KO'd active fighter is replaced automatically; a side
## loses when every member is out.

const ASSIST_COOLDOWN := 12.0
const ASSIST_TIME := 1.1

var active := {}                 ## team -> Fighter
var _tag_cd := {}                ## team -> seconds
var _assist_cd := {}             ## fighter index -> seconds
var _assisting := {}             ## fighter index -> {until}
var _apron := {}                 ## team -> Vector3 apron spot
var _corner := {}                ## team -> Vector3 tag-in spot inside the cage


func id() -> String:
	return "tag_team"


func setup(match_sim) -> void:
	var defaults := {"round_time": 120.0, "rounds": 3, "tag_cooldown": 4.0, "tagged_regen": 4.0}
	for k in defaults:
		if not match_sim.rules.has(k):
			match_sim.rules[k] = defaults[k]
	super.setup(match_sim)
	_layout_corners()
	_place_teams()


func _layout_corners() -> void:
	var teams := []
	for f: Fighter in sim.fighters:
		if not teams.has(f.team):
			teams.append(f.team)
	teams.sort()
	for i in teams.size():
		var a := TAU * float(i) / float(maxi(2, teams.size())) + PI * 0.5
		var dir := Vector3(cos(a), 0.0, sin(a))
		_corner[teams[i]] = dir * (sim.arena.radius - 1.4)
		_apron[teams[i]] = dir * (sim.arena.radius + 0.75)


func _place_teams() -> void:
	active.clear()
	for f: Fighter in sim.fighters:
		if f.despawned:
			continue
		if not active.has(f.team):
			active[f.team] = f
			var c: Vector3 = _corner[f.team]
			f.respawn(c, atan2(-c.x, -c.z))
		else:
			_send_to_apron(f, 0)


func _send_to_apron(f: Fighter, slot: int) -> void:
	var ap: Vector3 = _apron[f.team]
	var side := ap.cross(Vector3.UP).normalized() * (0.8 * (slot + 1))
	f.respawn(ap + side, atan2(-ap.x, -ap.z))
	f.invuln_until = 1e9
	f.flags["resting"] = true
	f.set_inactive(true)
	f.rig.muscle = 1.0


func on_round_reset() -> void:
	super.on_round_reset()
	_assisting.clear()
	_assist_cd.clear()
	_tag_cd.clear()
	for f: Fighter in sim.fighters:
		if f.despawned:
			continue
		f.flags.erase("resting")
		f.flags.erase("_rest_counts")
		f.flags.erase("_tag_seen")
		f.set_inactive(false)
	_place_teams()


func is_resting(f: Fighter) -> bool:
	return bool(f.flags.get("resting", false))


func _members(team: int) -> Array:
	return sim.fighters.filter(func(o: Fighter): return o.team == team and not o.despawned)


func tick_fight(dt: float) -> void:
	for t in _tag_cd.keys():
		_tag_cd[t] = maxf(0.0, float(_tag_cd[t]) - dt)
	for i in _assist_cd.keys():
		_assist_cd[i] = maxf(0.0, float(_assist_cd[i]) - dt)
	for f: Fighter in sim.fighters:
		if f.despawned:
			continue
		if is_resting(f):
			if f.health > 0.0:
				f.health = minf(f.max_health, f.health + float(rules["tagged_regen"]) * dt)
				f.stamina = f.max_stamina
			var presses := _resting_presses(f)
			if presses & (1 << FighterInput.TAUNT):
				var a: Fighter = active.get(f.team)
				if a:
					a.gain_hype(5.0)
					sim.emit_event({"type": "cheer", "fighter": f.index})
			if presses & (1 << FighterInput.AB1) and float(_assist_cd.get(f.index, 0.0)) <= 0.0 and f.health > 0.0:
				_start_assist(f)
		elif _assisting.has(f.index) and sim.time >= float(_assisting[f.index]["until"]):
			_assisting.erase(f.index)
			if f.is_out():
				continue                      # knocked out during the assist: stays out
			var a: Fighter = active.get(f.team)
			if a == null or is_beaten(a):
				# the partner went down while we were in: we stay in as the active fighter
				active[f.team] = f
				sim.emit_event({"type": "auto_tag", "team": f.team})
			else:
				var hp := f.health
				_send_to_apron(f, 1)
				f.health = hp
	for t in active.keys():
		var a: Fighter = active[t]
		if a.is_out():
			continue
		if a.input.press_count[FighterInput.TAG] != int(a.flags.get("_tag_seen", a.input.press_count[FighterInput.TAG])):
			a.flags["_tag_seen"] = a.input.press_count[FighterInput.TAG]
			_try_tag(int(t))
		else:
			a.flags["_tag_seen"] = a.input.press_count[FighterInput.TAG]


func _resting_presses(f: Fighter) -> int:
	var key := "_rest_counts"
	var last: PackedByteArray = f.flags.get(key, f.input.press_count.duplicate())
	var mask := 0
	for b in FighterInput.BUTTON_COUNT:
		if f.input.press_count[b] != last[b]:
			mask |= 1 << b
	f.flags[key] = f.input.press_count.duplicate()
	return mask


func _try_tag(team: int) -> void:
	var a: Fighter = active[team]
	if float(_tag_cd.get(team, 0.0)) > 0.0 or a.is_down() or a.state in [Fighter.State.HITSTUN, Fighter.State.HELD, Fighter.State.GUARD_BREAK, Fighter.State.GRABBING]:
		return
	var partner := _next_partner(team, a)
	if partner == null:
		return
	_swap(team, a, partner)
	_tag_cd[team] = float(rules["tag_cooldown"])


func _next_partner(team: int, current: Fighter) -> Fighter:
	for o: Fighter in _members(team):
		if o != current and is_resting(o) and o.health > 0.0:
			return o
	return null


func _swap(team: int, out_f: Fighter, in_f: Fighter) -> void:
	var p := out_f.pos()
	var yaw := out_f.facing_yaw
	var in_hp := in_f.health
	in_f.flags.erase("resting")
	in_f.set_inactive(false)
	in_f.respawn(sim.clamp_to_arena(p, 0.6), yaw)
	in_f.health = minf(in_hp, in_f.max_health)      # respawn() refills; tagging in must not
	in_f.invuln_until = in_f.time + 0.5
	active[team] = in_f
	if out_f.health > 0.0 and not out_f.is_out():
		var keep_hp := out_f.health
		_send_to_apron(out_f, 0)
		out_f.health = keep_hp
	sim.emit_event({"type": "tag", "team": team, "in": in_f.index, "out": out_f.index})


func _start_assist(f: Fighter) -> void:
	var a: Fighter = active.get(f.team)
	if a == null or a.is_out():
		return
	_assist_cd[f.index] = ASSIST_COOLDOWN
	var keep_hp := f.health
	f.flags.erase("resting")
	f.set_inactive(false)
	var spot := sim.clamp_to_arena(a.pos() - a.forward() * 0.8 + a.forward().cross(Vector3.UP) * 0.8, 0.6)
	f.respawn(spot, a.facing_yaw)
	f.health = keep_hp
	f.invuln_until = f.time + ASSIST_TIME
	f.input.press(FighterInput.DODGE)
	f.input.press(FighterInput.LIGHT)
	_assisting[f.index] = {"until": sim.time + ASSIST_TIME}
	sim.emit_event({"type": "assist", "fighter": f.index})


func on_depleted(f: Fighter, attacker: Fighter, hit: Dictionary) -> void:
	f.knock_out(attacker)
	if attacker and attacker != f:
		attacker.stats_record["kos"] += 1
	sim.emit_event({"type": "elimination", "fighter": f.index, "by": attacker.index if attacker else -1})
	if active.get(f.team) == f:
		var partner := _next_partner(f.team, f)
		if partner:
			var t := f.team
			_swap(t, f, partner)
			sim.emit_event({"type": "auto_tag", "team": t})
	check_round_over()


## Timeout decision counts every member's remaining health, including partners on the apron.
func on_timeout() -> void:
	var totals := {}
	for f: Fighter in sim.fighters:
		if f.despawned:
			continue
		var alive := f.health > 0.0 and f.state != Fighter.State.KO
		totals[f.team] = float(totals.get(f.team, 0.0)) + (f.health_frac() if alive else 0.0)
	var best := -1
	var best_v := -INF
	var tie := false
	for t in totals:
		if float(totals[t]) > best_v + 0.001:
			best_v = float(totals[t])
			best = int(t)
			tie = false
		elif absf(float(totals[t]) - best_v) <= 0.001:
			tie = true
	sim.emit_event({"type": "timeout"})
	if tie and bool(rules.get("sudden_death", true)):
		start_sudden_death()
		return
	end_round(-1 if tie else best)


func alive_teams() -> Array:
	var teams := []
	for f: Fighter in sim.fighters:
		if f.despawned or f.health <= 0.0 or f.state == Fighter.State.KO:
			continue
		if not teams.has(f.team):
			teams.append(f.team)
	return teams


func hud_status() -> String:
	var parts := []
	for t in active:
		var a: Fighter = active[t]
		var cd := float(_tag_cd.get(t, 0.0))
		parts.append("%s: %s%s" % [TeamColors.name(int(t)), a.display_name, (" (tag %ds)" % ceili(cd)) if cd > 0.0 else " (tag ready)"])
	return "   ".join(parts)


func view_state() -> Dictionary:
	var v := super.view_state()
	var act := {}
	for t in active:
		act[str(t)] = (active[t] as Fighter).index
	v["active"] = act
	return v


func bot_objective(f: Fighter) -> Dictionary:
	if is_resting(f):
		return {}
	# bots tag out when hurt and the partner is healthier
	var partner := _next_partner(f.team, f)
	if partner and f.health_frac() < 0.35 and partner.health_frac() > f.health_frac() + 0.2:
		f.input.press(FighterInput.TAG)
	return {}
