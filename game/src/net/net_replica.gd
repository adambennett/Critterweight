class_name NetReplica
extends RefCounted
## Client-side copy of a remote match: buffered snapshots, the fighter roster, an adaptive
## interpolation clock and the tick-stamped event queue. No simulation runs here.
##
## Clock: every snapshot gives an offset sample (server time - local arrival time). The largest
## recent offset is the least-delayed path; the spread below it is the arrival jitter.
## render_time = estimated server time - target_delay, advanced smoothly at local rate with
## +-10% drift correction (a jump > 0.25 s re-syncs instantly).
## target_delay (setting network.interp):
##   low  = 1 snapshot interval + median jitter        (least delay, may stutter on bad links)
##   auto = 1 snapshot interval + 95th pct jitter + 5 ms
##   high = 2 snapshot intervals + 99th pct jitter + 10 ms
## Events fire when render_time reaches their tick, so sparks/flashes/callouts line up with the
## interpolated bodies exactly as in local play.
## Fighter slots: a slot is interpolated only between snapshots with the same roster generation;
## across a generation change (spawn/despawn/rebuild) it switches at the midpoint. Bodies are
## rebuilt (forward kinematics) only when the roster entry for that generation is known.

const MAX_SNAPS := 90
const OFFSET_WINDOW := 90
const TELEPORT_DIST := 2.5
const MAX_PENDING_EVENTS := 1024

var tick_rate := 120.0
var snapshot_interval := 1.0 / 30.0
var interp_mode := "auto"
var match_id := 0
var roster := {}                  ## slot -> {gen, creature, scale, team, name, kind, despawned, def: CreatureDef}
var snaps: Array = []             ## [{tick, t, arrival, data}] ordered by tick
var render_time := -1.0
var target_delay := 0.1
var _offsets: Array[float] = []
var _events: Array = []           ## [{t, ev}]
var newest_tick := -1
## statistics
var snapshots_received := 0
var snapshots_late := 0
var starved_frames := 0
var frames := 0
var jitter_ms := 0.0
var events_received := 0
var roster_updates := 0
## Resolves roster creatures that are not content creatures: func(id: String, scale: float) ->
## CreatureDef (NetClient sets it for campaign fights: minion loadouts, dev stand-ins).
var creature_lookup: Callable = Callable()


func reset(info: Dictionary) -> void:
	tick_rate = float(info.get("tick_rate", 120))
	snapshot_interval = 1.0 / maxf(1.0, float(info.get("snapshot_rate", 30)))
	match_id = int(info.get("match_id", 0))
	roster.clear()
	snaps.clear()
	_offsets.clear()
	_events.clear()
	render_time = -1.0
	newest_tick = -1
	target_delay = snapshot_interval * 2.0
	snapshots_received = 0
	snapshots_late = 0
	starved_frames = 0
	frames = 0
	events_received = 0
	roster_updates = 0
	for e in info.get("fighters", []):
		apply_roster_entry(e)


## Applies one roster entry; returns true if the slot's body (generation) changed.
func apply_roster_entry(e: Dictionary) -> bool:
	var slot := int(e.get("slot", e.get("index", -1)))
	if slot < 0 or slot >= NetProtocol.MAX_SLOTS:
		return false
	var prev: Dictionary = roster.get(slot, {})
	var entry := {"gen": int(e.get("gen", 1)), "creature": str(e.get("creature", "")), "scale": float(e.get("scale", 1.0)),
		"team": int(e.get("team", slot)), "name": str(e.get("name", "")), "kind": str(e.get("kind", "")),
		"despawned": bool(e.get("despawned", false)), "player": int(e.get("player", 0)),
		"tags": (e.get("tags", []) as Array).duplicate(),
		# v0.9.18 Movesets: the fighter's combat style and equipped loadout (NetHudMirror gives the
		# client's HUD the same move cards as the host's)
		"combat": "moves" if str(e.get("combat", "classic")) == "moves" else "classic",
		"loadout": (e.get("loadout", []) as Array).duplicate() if typeof(e.get("loadout", [])) == TYPE_ARRAY else []}
	var body_changed := prev.is_empty() or int(prev["gen"]) != int(entry["gen"])
	if body_changed:
		entry["def"] = NetSnapshot.roster_creature(entry)
		if entry["def"] == null and creature_lookup.is_valid() and not bool(entry["despawned"]):
			entry["def"] = creature_lookup.call(str(entry["creature"]), float(entry["scale"]))
	else:
		entry["def"] = prev.get("def")
	roster[slot] = entry
	roster_updates += 1
	return body_changed


func slot_count() -> int:
	var n := 0
	for k in roster.keys():
		n = maxi(n, int(k) + 1)
	return n


func add_snapshot(tick: int, data: Dictionary, now_s: float) -> void:
	var t := float(tick) / tick_rate
	snapshots_received += 1
	if render_time >= 0.0 and t < render_time:
		snapshots_late += 1
	_offsets.append(t - now_s)
	if _offsets.size() > OFFSET_WINDOW:
		_offsets.remove_at(0)
	if tick <= newest_tick:
		for s in snaps:
			if int(s["tick"]) == tick:
				return
		var at := 0
		while at < snaps.size() and int(snaps[at]["tick"]) < tick:
			at += 1
		snaps.insert(at, {"tick": tick, "t": t, "arrival": now_s, "data": data})
	else:
		snaps.append({"tick": tick, "t": t, "arrival": now_s, "data": data})
		newest_tick = tick
	while snaps.size() > MAX_SNAPS:
		snaps.remove_at(0)
	_update_delay()


func _update_delay() -> void:
	if _offsets.size() < 2:
		return
	var best: float = _offsets.max()
	var lags: Array[float] = []
	for o in _offsets:
		lags.append(best - o)
	lags.sort()
	var p50 := lags[int(lags.size() * 0.5)]
	var p95 := lags[mini(lags.size() - 1, int(lags.size() * 0.95))]
	var p99 := lags[mini(lags.size() - 1, int(lags.size() * 0.99))]
	jitter_ms = p95 * 1000.0
	var want := snapshot_interval + p95 + 0.005
	match interp_mode:
		"low":
			want = snapshot_interval + p50
		"high":
			want = snapshot_interval * 2.0 + p99 + 0.01
	want = clampf(want, snapshot_interval * 0.75, 0.5)
	# grow quickly (avoid stutter), shrink slowly (avoid oscillation)
	if want > target_delay:
		target_delay = lerpf(target_delay, want, 0.5)
	else:
		target_delay = lerpf(target_delay, want, 0.05)


func server_time_estimate(now_s: float) -> float:
	if _offsets.is_empty():
		return -1.0
	var best: float = _offsets.max()
	return now_s + best


func advance(dt: float, now_s: float) -> void:
	if snaps.is_empty():
		return
	frames += 1
	var desired := server_time_estimate(now_s) - target_delay
	if render_time < 0.0 or absf(desired - render_time) > 0.25:
		render_time = desired
	else:
		var err := desired - render_time
		render_time += dt * (1.0 + clampf(err * 2.0, -0.1, 0.1))
	if render_time > float(snaps.back()["t"]):
		starved_frames += 1
	while snaps.size() > 2 and float(snaps[1]["t"]) < render_time - 0.5:
		snaps.remove_at(0)


## How far ahead of render time the buffer reaches (seconds).
func buffer_ahead() -> float:
	if snaps.is_empty() or render_time < 0.0:
		return 0.0
	return float(snaps.back()["t"]) - render_time


## Interpolated view at render_time:
## {tick, time, fighters: [slot dicts: gen 0 = absent; else root, rots, xforms (empty until the
## roster knows the generation) + vitals of the nearer snapshot], entities, props, mode}
func sample() -> Dictionary:
	if snaps.is_empty():
		return {}
	var i0 := 0
	for i in snaps.size():
		if float(snaps[i]["t"]) <= render_time:
			i0 = i
		else:
			break
	var has_next := i0 + 1 < snaps.size()
	var s0: Dictionary = snaps[i0]
	var s1: Dictionary = snaps[i0 + 1] if has_next else s0
	var alpha := 0.0
	if has_next:
		alpha = clampf((render_time - float(s0["t"])) / maxf(float(s1["t"]) - float(s0["t"]), 1e-6), 0.0, 1.0)
	var d0: Dictionary = s0["data"]
	var d1: Dictionary = s1["data"]
	var f0: Array = d0["fighters"]
	var f1: Array = d1["fighters"]
	var fighters: Array = []
	for i in maxi(f0.size(), f1.size()):
		var a: Dictionary = f0[i] if i < f0.size() else {"gen": 0}
		var b: Dictionary = f1[i] if i < f1.size() else {"gen": 0}
		var ga := int(a["gen"])
		var gb := int(b["gen"])
		var fd: Dictionary
		var rots: Array[Quaternion] = []
		if ga != 0 and ga == gb:
			var ra: Vector3 = a["root"]
			var rb: Vector3 = b["root"]
			var qa: Array[Quaternion] = a["rots"]
			var qb: Array[Quaternion] = b["rots"]
			fd = (a if alpha < 0.5 else b).duplicate()
			if ra.distance_to(rb) > TELEPORT_DIST or qa.size() != qb.size():
				fd["root"] = rb if alpha >= 0.5 else ra
				for q in (qb if alpha >= 0.5 else qa):
					rots.append(q)
			else:
				fd["root"] = ra.lerp(rb, alpha)
				for k in qa.size():
					rots.append(qa[k].slerp(qb[k], alpha))
		else:
			var pick: Dictionary = b if alpha >= 0.5 else a
			if int(pick["gen"]) == 0:
				fighters.append({"gen": 0})
				continue
			fd = pick.duplicate()
			for q in pick["rots"]:
				rots.append(q)
		fd["rots"] = rots
		var xf: Array[Transform3D] = []
		var re: Dictionary = roster.get(i, {})
		if not re.is_empty() and int(re["gen"]) == int(fd["gen"]) and re.get("def") != null:
			xf = NetSnapshot.fk((re["def"] as CreatureDef).body, fd["root"], rots)
		fd["xforms"] = xf
		fighters.append(fd)
	var ents: Array = []
	var e1 := {}
	for e in d1["entities"]:
		e1[int(e["id"])] = e
	var seen := {}
	for e in d0["entities"]:
		var id := int(e["id"])
		if e1.has(id):
			var ed: Dictionary = (e as Dictionary).duplicate()
			ed["pos"] = (e["pos"] as Vector3).lerp(e1[id]["pos"], alpha)
			ents.append(ed)
			seen[id] = true
		elif alpha < 0.5:
			ents.append(e)
			seen[id] = true
	if alpha >= 0.5:
		for id2 in e1:
			if not seen.has(id2):
				ents.append(e1[id2])
	var props: Array = []
	var p1 := {}
	for p in d1["props"]:
		p1[int(p["index"])] = p
	for p in d0["props"]:
		var idx := int(p["index"])
		if p1.has(idx):
			props.append({"index": idx, "pos": (p["pos"] as Vector3).lerp(p1[idx]["pos"], alpha),
				"rot": (p["rot"] as Quaternion).slerp(p1[idx]["rot"], alpha)})
		else:
			props.append(p)
	var m0: Dictionary = d0["mode"]
	var m1: Dictionary = d1["mode"]
	var mode: Dictionary = (m0 if alpha < 0.5 else m1).duplicate()
	mode["timer"] = lerpf(float(m0["timer"]), float(m1["timer"]), alpha)
	mode["view"] = NetEventCodec.blend(m0.get("view", {}), m1.get("view", {}), alpha)
	return {"tick": int(s0["tick"]), "time": render_time, "fighters": fighters, "entities": ents, "props": props, "mode": mode}


## Most recent snapshot body (no interpolation) - used by scripted test clients.
func latest() -> Dictionary:
	if snaps.is_empty():
		return {}
	return snaps.back()["data"]


func add_events(evs: Array) -> void:
	for ev in evs:
		events_received += 1
		_events.append({"t": float(int(ev.get("tick", 0))) / tick_rate, "ev": ev})
	while _events.size() > MAX_PENDING_EVENTS:
		_events.remove_at(0)


## Events whose tick has been reached by the render clock (in arrival order). Before the first
## snapshot arrives nothing is due; a backlog older than 1 s is released immediately.
func pop_due_events() -> Array:
	var out: Array = []
	if _events.is_empty() or render_time < 0.0:
		return out
	var keep: Array = []
	for item in _events:
		if float(item["t"]) <= render_time:
			out.append(item["ev"])
		else:
			keep.append(item)
	_events = keep
	return out


func stats() -> Dictionary:
	return {"interp_delay_ms": target_delay * 1000.0, "jitter_ms": jitter_ms, "buffer_ms": buffer_ahead() * 1000.0,
		"snapshots": snapshots_received, "late": snapshots_late, "starved_frames": starved_frames, "frames": frames,
		"events": events_received, "roster_updates": roster_updates}
