class_name NetHudMirror
extends RefCounted
## Client-side stand-ins for HUD code written against MatchSim/Fighter/MatchMode (FightHud):
## a MatchSim and Fighter objects that are never added to the scene tree, never set up and never
## stepped - they only carry replicated values, refreshed every frame from interpolated snapshots
## and the roster. Replicated fields: display_name, index, team, creature, controller_kind,
## despawned, state, health, max_health, stamina, max_stamina, poise, max_poise, hype, lives,
## juiced/crash (via time and *_until), guard_held, cooldown_left, statuses (active: id/element/
## left), target; sim.rules, sim.input_enabled, sim.is_finished; mode phase/round/timer/wins/
## scores, hud_status(), hud_state(), view_state().
## Fighter methods that need a physical body (pos(), head_pos(), ...) are NOT available here.

class MirrorMode:
	extends MatchMode
	var net_status := ""
	var net_mode_id := "standard"
	var net_hud := {}
	var net_view := {}

	func id() -> String:
		return net_mode_id

	func hud_status() -> String:
		return net_status

	func hud_state() -> Dictionary:
		var h := net_hud.duplicate()
		if not h.has("status"):
			h["status"] = net_status
		if not h.has("rows"):
			h["rows"] = []
		return h

	func view_state() -> Dictionary:
		return net_view


var sim: MatchSim = null
var mode: MirrorMode = null
var _gen := {}                   ## slot -> roster generation applied


func build(info: Dictionary, replica: NetReplica) -> void:
	sim = MatchSim.new()
	sim.name = "NetMirrorSim"
	sim.running = false
	sim.rules = (info.get("rules", {}) as Dictionary).duplicate(true)
	mode = MirrorMode.new()
	mode.net_mode_id = str(info.get("mode", "standard"))
	mode.sim = sim
	mode.rules = sim.rules
	mode.round_timer = float(sim.rules.get("round_time", 99.0))
	sim.mode = mode
	sync_roster(replica)


## Creates/updates mirror fighters for every roster slot.
func sync_roster(replica: NetReplica) -> void:
	var n := replica.slot_count()
	while sim.fighters.size() < n:
		var f := Fighter.new()
		f.index = sim.fighters.size()
		f.statuses = StatusSet.new(f)
		f.time = 1000.0
		sim.fighters.append(f)
	for i in n:
		var e: Dictionary = replica.roster.get(i, {})
		if e.is_empty():
			continue
		var f2 := sim.fighters[i]
		f2.team = int(e["team"])
		f2.display_name = str(e["name"])
		f2.controller_kind = str(e["kind"])
		f2.set("despawned", bool(e["despawned"]))
		if int(_gen.get(i, -1)) != int(e["gen"]) and e.get("def") != null:
			_gen[i] = int(e["gen"])
			f2.creature = e["def"]
			f2.max_health = f2.creature.stat("health")
			f2.health = f2.max_health


func update(sample: Dictionary) -> void:
	if sim == null or sample.is_empty():
		return
	var fl: Array = sample.get("fighters", [])
	for i in mini(fl.size(), sim.fighters.size()):
		var fd: Dictionary = fl[i]
		var f := sim.fighters[i]
		if int(fd["gen"]) == 0:
			f.state = Fighter.State.INACTIVE
			continue
		f.state = int(fd["state"])
		f.health = float(fd["health"])
		f.max_health = float(fd["max_health"])
		f.stamina = float(fd["stamina"])
		f.max_stamina = float(fd["max_stamina"])
		f.poise = float(fd["poise"])
		f.max_poise = float(fd["max_poise"])
		f.hype = float(fd["hype"])
		f.lives = int(fd["lives"])
		var flags := int(fd["flags"])
		f.juiced_until = f.time + 1.0 if flags & NetSnapshot.F_JUICED else -1.0
		f.crash_until = f.time + 1.0 if flags & NetSnapshot.F_CRASH else -1.0
		f.guard_held = flags & NetSnapshot.F_GUARD != 0
		f.cooldown_left = (fd["cooldowns"] as Dictionary).duplicate()
		f.statuses.active = (fd["statuses"] as Array).duplicate(true)
		var ti := int(fd["target"])
		f.target = sim.fighters[ti] if ti >= 0 and ti < sim.fighters.size() else null
	var m: Dictionary = sample.get("mode", {})
	if not m.is_empty():
		mode.phase = int(m["phase"])
		mode.round_index = int(m["round"])
		mode.round_timer = float(m["timer"])
		mode.winner_team = int(m["winner"])
		mode.round_winner = int(m["round_winner"])
		mode.net_status = str(m["status"])
		mode.net_hud = m.get("hud", {})
		mode.net_view = m.get("view", {})
		for t in m["teams"]:
			mode.round_wins[int(t["team"])] = int(t["wins"])
			mode.scores[int(t["team"])] = int(t["score"])
		sim.input_enabled = int(m["flags"]) & NetSnapshot.M_INPUT != 0
		sim.is_finished = int(m["flags"]) & NetSnapshot.M_FINISHED != 0


func free_all() -> void:
	if sim == null:
		return
	for f in sim.fighters:
		if is_instance_valid(f):
			f.free()
	sim.fighters.clear()
	sim.mode = null
	sim.free()
	sim = null
	mode = null
