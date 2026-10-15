class_name HubBagChallenge
extends RefCounted
## Heavy Bag Score Challenge (HUB.md §3): 30 s on one of the three bags. Each weapon hit scores
## with the combat damage formula (closing-speed quality q and contact cleanliness, charge),
## x1.5 for a Heavy, x2 for a Finisher, plus a combo multiplier for hits landed within 0.6 s of
## each other. Light bag rewards speed (flat bonus, faster combo), Heavy bag rewards power
## (quality weighted), the Body bag (shaped like the Commissioner) only scores head/shell hits.
## Tiers 300/600/1000 pay 10/25/50 Clout once per tier per fighter per bag.

var mode
var bag := ""
var phase := "idle"            ## idle | countdown | running | done
var t := 0.0
var score := 0.0
var hits := 0
var combo := 0
var best_combo := 0
var _last_hit_t := -99.0
var cfg := {}
var result := {}


func _init(m) -> void:
	mode = m
	cfg = HubContent.activity("bags")


func running() -> bool:
	return phase == "countdown" or phase == "running"


func start(bag_id: String) -> void:
	bag = bag_id
	phase = "countdown"
	t = 0.0
	score = 0.0
	hits = 0
	combo = 0
	best_combo = 0
	_last_hit_t = -99.0
	result = {}
	mode.emit_hub({"type": "hub_activity", "activity": "bag", "phase": "countdown", "bag": bag, "seconds": float(cfg.get("countdown", 3.0))})


func time_left() -> float:
	if phase == "countdown":
		return float(cfg.get("duration", 30.0))
	return maxf(0.0, float(cfg.get("duration", 30.0)) - t)


func tick(dt: float) -> void:
	if phase == "countdown":
		t += dt
		if t >= float(cfg.get("countdown", 3.0)):
			phase = "running"
			t = 0.0
			mode.emit_hub({"type": "hub_activity", "activity": "bag", "phase": "start", "bag": bag})
	elif phase == "running":
		t += dt
		if t >= float(cfg.get("duration", 30.0)):
			finish()


func cancel() -> void:
	if running():
		phase = "done"
		result = {"bag": bag, "score": int(score), "cancelled": true}
		mode.emit_hub({"type": "hub_activity", "activity": "bag", "phase": "cancel", "bag": bag})


## Points for one weapon hit on a bag (0 when the hit does not count). `info` comes from
## HubMode.weapon_quality(); `height` is the contact height above the floor.
func points_for(bag_id: String, info: Dictionary, height: float) -> float:
	if info.is_empty():
		return 0.0
	var bc: Dictionary = (cfg.get("bags", {}) as Dictionary).get(bag_id, {})
	var zone_mult := 1.0
	if bc.has("zones"):
		zone_mult = 0.0
		var zones: Dictionary = bc["zones"]
		for z in zones:
			var zr: Array = zones[z]
			if height >= float(zr[0]) and height < float(zr[1]):
				zone_mult = float(zr[2])
		if zone_mult <= 0.0:
			return 0.0
	var q := float(info["q"])
	var clean := float(info["clean"])
	var base := float(info["damage"]) * (0.55 + 0.6 * q) * (0.75 + 0.25 * clean) * (1.0 + float(info["charge"]) * float(info["charge_damage"]))
	var qw := float(bc.get("quality_weight", 1.0))
	base *= 1.0 + (q - 0.5) * (qw - 1.0)
	var pts := base * float(cfg.get("points_per_damage", 6.0)) + float(bc.get("base_bonus", 0.0))
	var cls := str(info["class"])
	if str(info["slot"]).begins_with("finisher"):
		pts *= float(cfg.get("finisher_mult", 2.0))
	elif cls == "heavy":
		pts *= float(cfg.get("heavy_mult", 1.5))
	return maxf(0.0, pts * zone_mult)


## Called by HubMode for every weapon hit on a bag while the challenge runs.
func on_hit(bag_id: String, info: Dictionary, height: float, now: float, point: Vector3) -> void:
	if phase != "running" or bag_id != bag:
		return
	var pts := points_for(bag_id, info, height)
	if pts <= 0.0:
		mode.emit_hub({"type": "hub_score", "activity": "bag", "points": 0, "pos": point, "label": "NO SCORE"})
		return
	var bc: Dictionary = (cfg.get("bags", {}) as Dictionary).get(bag_id, {})
	if now - _last_hit_t <= float(cfg.get("combo_window", 0.6)):
		combo += 1
	else:
		combo = 1
	_last_hit_t = now
	best_combo = maxi(best_combo, combo)
	var mult := minf(float(cfg.get("combo_max", 2.0)), 1.0 + float(cfg.get("combo_step", 0.1)) * float(bc.get("combo_step_mult", 1.0)) * float(combo - 1))
	var gained := pts * mult
	score += gained
	hits += 1
	mode.emit_hub({"type": "hub_score", "activity": "bag", "points": int(round(gained)), "pos": point, "combo": combo, "total": int(score)})


func finish() -> void:
	phase = "done"
	var tiers: Array = cfg.get("tiers", [300, 600, 1000])
	var clouts: Array = cfg.get("clout", [10, 25, 50])
	var f: Fighter = mode.player()
	var fid := f.creature.id if f else "?"
	var rew: Dictionary = mode.state.reward_tiers("bag_%s_%s" % [bag, fid], score, tiers, clouts, "%s challenge" % str((cfg.get("bags", {}) as Dictionary).get(bag, {}).get("name", bag)))
	mode.state.reward_tiers("bag_%s" % bag, score, [], [])
	result = {"bag": bag, "score": int(score), "hits": hits, "best_combo": best_combo, "tier": int(rew["tier"]), "new_tier": int(rew["tier"]) > int(rew["previous"]),
		"clout": int(rew["clout"]), "fighter": fid}
	mode.emit_hub({"type": "hub_activity", "activity": "bag", "phase": "end", "bag": bag, "result": result})
	mode.secrets.on_bag_result(bag, score)
