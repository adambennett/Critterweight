class_name LabScenarios
extends RefCounted
## Training/evaluation scenarios: which arena, how long a round lasts, how fighters spawn, and
## which opponents appear. Episode seeds come from disjoint, named streams so training and
## evaluation never share starting conditions:
##   train(job_seed, generation, k) · val(job_seed, k) (model selection) · test(job_seed, k)
##   (final report only) · rec(job_seed, index) (teacher recordings; each recorded episode of a
##   dataset has its own index, see LabTaskRecord).
## Spawns (both fighters are always placed explicitly, on every arena format):
##   random    — learner anywhere in the inner 55% of the arena, opponent `dist` metres away
##   standard  — the arena's standard opposite spawn points, jittered per seed (±0.35 m, ±25°) so
##               two episodes never start identically (a deterministic policy against a static
##               dummy would otherwise replay the same episode and be counted twice)
##   swapped   — the standard points with the fighters exchanged (also jittered)
## Evaluation includes the standard/swapped layout, which random-spawn training never uses.

const PRESETS := {
	"drill_dummy": {"name": "Drill: standing dummy", "opponents": ["idle"], "round_time": 8.0, "spawn": "random", "dist": [2.0, 4.5], "arena": "the_gullet",
		"help": "Close in on a dummy that never moves or fights back and land hits. The controlled learnable task."},
	"drill_patrol": {"name": "Drill: patrolling dummy", "opponents": ["patrol"], "round_time": 10.0, "spawn": "random", "dist": [2.0, 4.5], "arena": "the_gullet",
		"help": "A dummy that walks in circles: tracking practice."},
	"spar_jabber": {"name": "Sparring: jabber", "opponents": ["jabber"], "round_time": 20.0, "spawn": "random", "dist": [2.0, 4.0], "arena": "the_gullet",
		"help": "A scripted opponent that walks in and jabs on a rhythm. Learn to block, punish and survive."},
	"spar_mixed": {"name": "Sparring: jabber + turtle", "opponents": ["jabber", "turtle"], "round_time": 20.0, "spawn": "random", "dist": [2.0, 4.0], "arena": "the_gullet",
		"help": "Alternates an attacker and a guarding opponent (grabs beat guard)."},
	"bots_low": {"name": "Bots: Rookie + Regular", "opponents": ["bot_rookie", "bot_regular"], "round_time": 30.0, "spawn": "standard", "dist": [3.0, 3.6], "arena": "the_gullet",
		"help": "The two easiest shipped bot tiers, full rules."},
	"bots_high": {"name": "Bots: Pro + Champion", "opponents": ["bot_pro", "bot_champion"], "round_time": 30.0, "spawn": "standard", "dist": [3.0, 3.6], "arena": "the_gullet",
		"help": "The two hardest bot tiers. Expect slow progress."},
	# opponents filled from the profile (saved_build_opponents); offered with the Boiler Room Key
	"my_builds": {"name": "My saved builds", "opponents": [], "round_time": 30.0, "spawn": "standard", "dist": [3.0, 3.6], "arena": "the_gullet",
		"help": "Your own campaign builds — the fighter, techniques and supplements you finished a run with — piloted by a Pro bot. Unlocked by the Boiler Room Key (Teddy's ledger in the Cannery)."},
}
const SAVED_BUILDS_SHOWN := 6

## Standard-spawn jitter (per episode seed): position within this radius, yaw within ± degrees.
const JITTER_M := 0.35
const JITTER_DEG := 25.0


static func preset_ids() -> Array:
	return ["drill_dummy", "drill_patrol", "spar_jabber", "spar_mixed", "bots_low", "bots_high"]


## The scenario list the AI Lab offers this profile: the fixed presets, plus "My saved builds" with
## the Cannery's Boiler Room Key once the profile has a saved build.
static func preset_ids_for(profile: Dictionary) -> Array:
	var out := preset_ids()
	if not saved_build_opponents(profile).is_empty():
		out.append("my_builds")
	return out


## The Cannery's Boiler Room Key (meta_boiler_room_key, 100 Clout at Teddy's ledger).
static func boiler_room_key(profile: Dictionary) -> bool:
	var camp: Dictionary = profile.get("camp", {})
	return int((camp.get("upgrades", {}) as Dictionary).get("meta_boiler_room_key", 0)) > 0


## Opponent kinds for the profile's most recent saved builds (newest first), or [] without the key.
static func saved_build_opponents(profile: Dictionary) -> Array:
	if not boiler_room_key(profile):
		return []
	var out := []
	var builds: Array = (profile.get("campaign", {}) as Dictionary).get("saved_builds", [])
	for b in builds:
		if typeof(b) == TYPE_DICTIONARY and str((b as Dictionary).get("fighter", "")) != "":
			out.append(LabOpponents.build_kind(b))
		if out.size() >= SAVED_BUILDS_SHOWN:
			break
	return out


static func seed_for(stream: String, job_seed: int, a: int, b := 0) -> int:
	return int(MathX.hash32("%s:%d:%d:%d" % [stream, job_seed, a, b]) & 0x7FFFFFFF)


## A complete, self-contained episode description (serializable; workers rebuild it exactly).
static func episode(scn: Dictionary, opponent: String, seed_value: int, learner_creature: String, opponent_creature: String, spawn_override := "") -> Dictionary:
	return {"seed": seed_value, "opponent": opponent, "arena": str(scn.get("arena", "the_gullet")),
		"round_time": float(scn.get("round_time", 10.0)), "spawn": spawn_override if spawn_override != "" else str(scn.get("spawn", "random")),
		"dist": scn.get("dist", [2.0, 4.5]), "learner": learner_creature, "opponent_creature": opponent_creature}


## Arena for an episode: the base arena with exactly two spawns (learner first, opponent second)
## chosen from the episode seed. Arenas of format 2 list their spawns as a ring of markers; those
## are replaced here, so spawn_point(0/1, 2) are exactly the two positions chosen below.
static func arena_for(ep: Dictionary) -> ArenaDef:
	var base: ArenaDef = null
	var tree := Engine.get_main_loop() as SceneTree
	var content: Node = tree.root.get_node_or_null("Content") if tree != null else null
	if content != null:
		base = content.call("arena", str(ep.get("arena", "the_gullet"))) as ArenaDef
	var d := base.to_dict() if base != null else {"id": "lab", "name": "Lab cage", "base": "octagon", "radius": 5.0,
		"spawns": [[0, -1.8, 0], [0, 1.8, 180]]}
	d["id"] = "lab_" + str(d.get("id", "arena"))
	var probe := ArenaDef.from_dict(d)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(ep.get("seed", 1)) * 7919 + 17
	var mode := str(ep.get("spawn", "random"))
	var two: Array
	if mode == "random":
		# (learner draw and radius exactly as before the opponent fix: d's radius, default 5 m)
		two = _random_pair(probe, float(d.get("radius", 5.0)), ep, rng)
	else:
		two = _standard_pair(probe, mode == "swapped", rng)
	d["spawns"] = two
	_drop_ring_markers(d)
	return ArenaDef.from_dict(d)


## [[x, z, yaw_deg], [x, z, yaw_deg]]: learner inside the inner 55% of the arena, opponent
## `dist` metres away (inside the walls), roughly facing each other.
static func _random_pair(probe: ArenaDef, radius: float, ep: Dictionary, rng: RandomNumberGenerator) -> Array:
	var dist_r: Array = ep.get("dist", [2.0, 4.5])
	var dmin := float(dist_r[0]) if dist_r.size() > 0 else 2.0
	var dmax := float(dist_r[1]) if dist_r.size() > 1 else 4.5
	var p0 := Vector3.ZERO
	var p1 := Vector3.ZERO
	for attempt in 40:
		var a0 := rng.randf() * TAU
		var r0 := sqrt(rng.randf()) * radius * 0.55
		p0 = Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
		var a1 := rng.randf() * TAU
		var dd := rng.randf_range(dmin, dmax)
		p1 = p0 + Vector3(cos(a1), 0.0, sin(a1)) * dd
		if probe.inside(p1, 1.0) and probe.inside(p0, 1.0):
			break
	p1 = probe.clamp_point(p1, 1.0)
	var yaw0 := rad_to_deg(atan2(p1.x - p0.x, p1.z - p0.z)) + rng.randf_range(-90.0, 90.0)
	var yaw1 := rad_to_deg(atan2(p0.x - p1.x, p0.z - p1.z)) + rng.randf_range(-45.0, 45.0)
	return [[p0.x, p0.z, yaw0], [p1.x, p1.z, yaw1]]


## The arena's standard spawn points for two fighters (swapped on request), each jittered by the
## episode seed.
static func _standard_pair(probe: ArenaDef, swapped: bool, rng: RandomNumberGenerator) -> Array:
	var s0: Array = probe.spawn_point(0, 2)
	var s1: Array = probe.spawn_point(1, 2)
	if swapped:
		var t := s0
		s0 = s1
		s1 = t
	var out := []
	for s: Array in [s0, s1]:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * JITTER_M
		var at: Vector3 = s[0]
		var p := probe.clamp_point(at + Vector3(cos(a) * r, 0.0, sin(a) * r), 1.0)
		var yaw := rad_to_deg(float(s[1])) + rng.randf_range(-JITTER_DEG, JITTER_DEG)
		out.append([p.x, p.z, yaw])
	return out


## Removes the format-2 spawn ring (team-less spawn markers): the explicit two spawns replace it.
static func _drop_ring_markers(d: Dictionary) -> void:
	var mk = d.get("markers")
	if typeof(mk) != TYPE_DICTIONARY:
		return
	for key in (mk as Dictionary).keys():
		var k := str(key).trim_prefix("marker_")
		if k != "spawn" or typeof(mk[key]) != TYPE_ARRAY:
			continue
		var keep := []
		for m in mk[key]:
			if typeof(m) == TYPE_DICTIONARY and int((m as Dictionary).get("team", -1)) >= 0:
				keep.append(m)
		mk[key] = keep
