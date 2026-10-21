class_name NetHudMirror
extends RefCounted
## Client-side presentation mirror of a remote match: a MatchSim with Fighter objects that are
## never set up or stepped. They only carry replicated values, refreshed every frame from
## interpolated snapshots, the roster and due events, so presentation code written against a
## local MatchSim runs unchanged on network clients:
##  * FightHud: display_name, index, team, creature, controller_kind, despawned, state, health,
##    max_health, stamina, max_stamina, poise, max_poise, hype, lives, juiced/crash (via time and
##    *_until), guard_held, cooldown_left, statuses (active: id/element/left), target, flags (true
##    tags); sim.rules; mode phase/round/timer/wins/scores, hud_status(), hud_state(), view_state().
##  * AudioMatchBridge (Audio.attach_match): sim.events/event_seq/events_since() (replicated
##    events appended when due), sim.time, sim.arena, sim.effects.entities, fighter pos(),
##    ground_pos(), rig.com_velocity(), rig.grounded, health_frac(), state_name().
## A fighter's rig is a MirrorRig stand-in (root position + velocity estimated from snapshots);
## anything needing real bodies (head_pos(), segment transforms) is NOT available here.

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


class MirrorRig:
	extends Rig
	var net_root := Vector3.ZERO
	var net_vel := Vector3.ZERO

	func root_pos() -> Vector3:
		return net_root

	func com_velocity() -> Vector3:
		return net_vel


var sim: MatchSim = null
var mode: MirrorMode = null
var _gen := {}                   ## slot -> roster generation applied
var _fallback: CreatureDef = null
var _me := -1                    ## this client's own fighter slot (-1 spectator)


func build(info: Dictionary, replica: NetReplica) -> void:
	_me = int(info.get("you", -1))
	sim = MatchSim.new()
	sim.name = "NetMirrorSim"
	sim.running = false
	sim.rules = (info.get("rules", {}) as Dictionary).duplicate(true)
	sim.seed_value = int(info.get("match_id", 1))
	var checked = info.get("_arena_def", null)
	sim.arena = checked if checked is ArenaDef else ArenaDef.from_dict(info.get("arena", {}), "net")
	mode = MirrorMode.new()
	mode.net_mode_id = str(info.get("mode", "standard"))
	mode.sim = sim
	mode.rules = sim.rules
	mode.round_timer = float(sim.rules.get("round_time", 99.0))
	sim.mode = mode
	var playable := Content.playable_creatures()
	if not playable.is_empty():
		_fallback = Content.creature(str(playable[0]))
	sync_roster(replica)


## Creates/updates mirror fighters for every roster slot.
func sync_roster(replica: NetReplica) -> void:
	var n := replica.slot_count()
	while sim.fighters.size() < n:
		var f := Fighter.new()
		f.index = sim.fighters.size()
		f.statuses = StatusSet.new(f)
		f.time = 1000.0
		f.creature = _fallback
		var rig := MirrorRig.new()
		f.add_child(rig)
		f.rig = rig
		sim.fighters.append(f)
	for i in n:
		var e: Dictionary = replica.roster.get(i, {})
		if e.is_empty():
			continue
		var f2 := sim.fighters[i]
		f2.team = int(e["team"])
		f2.display_name = str(e["name"])
		# the server drives this client's fighter as "net"; here it is the local player (HUD "YOU"
		# tag, control hints), exactly like a local fighter in MatchScene
		f2.controller_kind = "player" if i == _me and str(e["kind"]) == "net" else str(e["kind"])
		f2.set("despawned", bool(e["despawned"]))
		for k in f2.flags.keys():
			if typeof(f2.flags[k]) == TYPE_BOOL:
				f2.flags.erase(k)
		for t in e.get("tags", []):
			f2.flags[str(t)] = true
		if int(_gen.get(i, -1)) != int(e["gen"]) and e.get("def") != null:
			_gen[i] = int(e["gen"])
			f2.creature = e["def"]
			f2.max_health = f2.creature.stat("health")
			f2.health = f2.max_health
		# Movesets: the HUD's move cards, prompts and names follow the server's loadout
		var style := str(e.get("combat", "classic"))
		var lo: Array = e.get("loadout", [])
		if f2.combat_style != style or f2.loadout != lo:
			f2.combat_style = style
			f2.loadout = lo.duplicate() if style == "moves" and f2.creature and f2.creature.loadout_problem(lo) == "" else []


func update(sample: Dictionary, dt: float) -> void:
	if sim == null or sample.is_empty():
		return
	sim.time = float(sample.get("time", sim.time))
	var fl: Array = sample.get("fighters", [])
	for i in mini(fl.size(), sim.fighters.size()):
		var fd: Dictionary = fl[i]
		var f := sim.fighters[i]
		var rig := f.rig as MirrorRig
		if int(fd["gen"]) == 0:
			f.state = Fighter.State.INACTIVE
			if rig:
				rig.net_vel = Vector3.ZERO
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
		var tf = f.get("timed_flags")
		if typeof(tf) == TYPE_DICTIONARY:
			var tfd: Dictionary = tf
			if flags & NetSnapshot.F_HIDDEN:
				tfd["submerged"] = f.time + 1.0
			else:
				tfd.erase("submerged")
		f.cooldown_left = (fd["cooldowns"] as Dictionary).duplicate()
		f.charges_left = (fd.get("charges", {}) as Dictionary).duplicate()
		f.statuses.active = (fd["statuses"] as Array).duplicate(true)
		var ti := int(fd["target"])
		f.target = sim.fighters[ti] if ti >= 0 and ti < sim.fighters.size() else null
		if rig:
			var root: Vector3 = fd["root"]
			var moved := root - rig.net_root
			if dt > 0.0 and moved.length() < 2.0:
				rig.net_vel = rig.net_vel.lerp(moved / dt, clampf(dt * 12.0, 0.0, 1.0))
			else:
				rig.net_vel = Vector3.ZERO
			rig.net_root = root
			rig.grounded = flags & NetSnapshot.F_GROUNDED != 0
			rig.ground_y = 0.0
	sim.effects.entities = sample.get("entities", [])
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


## Appends a replicated event (now due) to the mirror's event ring, where presentation bridges
## (AudioMatchBridge) read it exactly like local simulation events.
func push_event(ev: Dictionary) -> void:
	if sim == null:
		return
	var e := ev.duplicate()
	sim.event_seq += 1
	e["seq"] = sim.event_seq
	sim.events.append(e)
	if sim.events.size() > MatchSim.MAX_EVENTS:
		sim.events.pop_front()


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
