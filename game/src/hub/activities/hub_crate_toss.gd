class_name HubCrateToss
extends RefCounted
## Crate Toss (HUB.md §3): ten crates at the pile on the Loading Dock. Grab picks one up, Grab or
## Light tosses it, Heavy (hold) heaves it — distance grows with charge and the fighter's throw
## strength (HubMode.throw_strength: body mass and throw stats; Dredge and Dozer throw far,
## Jitters less). Crates must leave from behind the painted line; where a crate first lands scores
## by the ring it lands in (3 m: 5, 5 m: 10, 8 m: 20). Tiers 30/60/100 pay 10/25/50 Clout; 100
## with Jitters earns Ludlow's hint about the pier (secret #8).

var _mode_ref: WeakRef = null
## The owning HubMode, held weakly: the mode owns this object, so a strong back-reference would be a
## reference cycle that leaks the whole hub sim state on every visit.
var mode:
	get:
		return _mode_ref.get_ref() if _mode_ref != null else null
var phase := "idle"            ## idle | running | done
var t := 0.0
var points := 0
var thrown := 0
var landed := 0
var throws: Array = []         ## [{crate, dist, ring, points, foul}]
var cfg := {}
var result := {}
var _pending := {}             ## crate index -> true (thrown this session, not landed yet)


func _init(m) -> void:
	_mode_ref = weakref(m)
	cfg = HubContent.activity("crates")


func running() -> bool:
	return phase == "running"


func start() -> void:
	phase = "running"
	t = 0.0
	points = 0
	thrown = 0
	landed = 0
	throws.clear()
	_pending.clear()
	result = {}
	mode.reset_crates()
	mode.emit_hub({"type": "hub_activity", "activity": "crates", "phase": "start", "crates": crates_total()})


func crates_total() -> int:
	return int(cfg.get("crates", 10))


func crates_left() -> int:
	return crates_total() - thrown


func tick(dt: float) -> void:
	if phase != "running":
		return
	t += dt
	var f: Fighter = mode.player()
	if f and HubLayout.space_at(f.pos()) != "loading_dock":
		finish("left the dock")
		return
	if t > float(cfg.get("time_limit", 150.0)):
		finish("time")
		return
	if thrown >= crates_total() and _pending.is_empty():
		finish("all crates")


## A crate left the fighter's hands (HubMode calls this for every crate throw during a session).
func on_throw(crate_index: int, from: Vector3) -> void:
	if phase != "running" or thrown >= crates_total():
		return
	thrown += 1
	var foul := from.z < HubLayout.CRATE_LINE_Z - 0.35
	_pending[crate_index] = {"foul": foul, "from": from}
	if foul:
		mode.emit_hub({"type": "hub_score", "activity": "crates", "points": 0, "pos": from + Vector3.UP, "label": "FOUL: THROW FROM BEHIND THE LINE"})


## First landing of a thrown crate (on the dock or in the water).
func on_land(crate_index: int, pos: Vector3, in_water: bool) -> void:
	if not _pending.has(crate_index):
		return
	var info: Dictionary = _pending[crate_index]
	_pending.erase(crate_index)
	landed += 1
	var ring := -1
	var pts := 0
	if not bool(info["foul"]) and not in_water:
		var rings: Array = HubLayout.CRATE_RINGS
		for i in rings.size():
			var rd: Dictionary = rings[i]
			var c := Vector2(HubLayout.CRATE_LANE_X, HubLayout.CRATE_LINE_Z - float(rd["dist"]))
			if Vector2(pos.x, pos.z).distance_to(c) <= float(rd["r"]) + HubWorld.CRATE_SIZE * 0.35:
				ring = i
				pts = int(rd["points"])
	points += pts
	var from: Vector3 = info["from"]
	var dist := Vector2(pos.x - from.x, pos.z - from.z).length()
	throws.append({"crate": crate_index, "dist": snappedf(dist, 0.01), "ring": ring, "points": pts, "foul": bool(info["foul"]), "water": in_water})
	var label := "SPLASH" if in_water else ("%d m RING" % int(HubLayout.CRATE_RINGS[ring]["dist"]) if ring >= 0 else "MISS")
	mode.emit_hub({"type": "hub_score", "activity": "crates", "points": pts, "pos": pos + Vector3.UP * 0.6, "label": label, "total": points})


func cancel() -> void:
	if running():
		phase = "done"
		result = {"points": points, "cancelled": true}
		mode.emit_hub({"type": "hub_activity", "activity": "crates", "phase": "cancel"})


func finish(reason: String) -> void:
	if phase == "done":
		return
	phase = "done"
	var rew: Dictionary = mode.state.reward_tiers("crates", float(points), cfg.get("tiers", [30, 60, 100]), cfg.get("clout", [10, 25, 50]), "Crate Toss")
	var f: Fighter = mode.player()
	var jitters_hint := false
	if f and f.creature.id == "f_jitters" and points >= int(cfg.get("jitters_hint", 100)):
		jitters_hint = true
		mode.state.set_flag("pier_hint", true)
	result = {"points": points, "thrown": thrown, "throws": throws.duplicate(true), "reason": reason, "tier": int(rew["tier"]),
		"new_tier": int(rew["tier"]) > int(rew["previous"]), "clout": int(rew["clout"]), "jitters_hint": jitters_hint}
	mode.emit_hub({"type": "hub_activity", "activity": "crates", "phase": "end", "result": result})
