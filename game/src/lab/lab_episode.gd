class_name LabEpisode
extends RefCounted
## One training/evaluation episode: a fresh physics world (SubViewport with its own World3D,
## so episodes never share Jolt state), a real MatchSim with the normal combat rules and mode,
## the learner in slot 0 (a policy, or a scripted teacher when recording) and one opponent.
## The cosmetic round intro is shortened to a short settle period; everything else — rules,
## timer, KO and decision — is the standard MatchMode.
##
## item = {i, episode: LabScenarios.episode(...), learner: {type: policy|scripted, kind},
##         record: bool}; the learner policy (PolicyData) is resolved by the caller.

const SETTLE_TICKS := 24

var item := {}
var world: SubViewport
var sim: MatchSim
var policy_src: PolicyInputSource
var recorder: PolicyRecorder
var tracker := LabRewards.Tracker.new()
var ticks := 0
var fight_ticks := 0
var max_ticks := 0
var started_fight := false
var done := false
var error := ""
var result := {}


## Builds the world and match. Returns "" or an error message (the episode is then done).
func start(parent: Node, it: Dictionary, policy: PolicyData) -> String:
	item = it
	var ep: Dictionary = it["episode"]
	var tree := parent.get_tree()
	var content: Node = tree.root.get_node_or_null("Content")
	var c_learner: CreatureDef = content.call("creature", str(ep.get("learner", ""))) as CreatureDef if content != null else null
	var c_opp: CreatureDef = content.call("creature", str(ep.get("opponent_creature", ""))) as CreatureDef if content != null else null
	var opp_mods := {}
	var opp_kind := str(ep.get("opponent", "idle"))
	if opp_kind.begins_with(LabOpponents.BUILD_PREFIX):
		# one of your saved builds: its fighter with the techniques and supplements it finished with
		var comp := compose_build(LabOpponents.build_of(opp_kind))
		if comp.get("creature") == null:
			return _fail("saved build unusable: %s" % "; ".join(comp.get("errors", PackedStringArray())))
		c_opp = comp["creature"]
		opp_mods = comp.get("mods", {})
	if c_learner == null or c_opp == null:
		return _fail("unknown creature '%s' / '%s'" % [str(ep.get("learner", "")), str(ep.get("opponent_creature", ""))])
	var seed_value := int(ep.get("seed", 1))
	var learner: Dictionary = it.get("learner", {"type": "policy"})
	var src: InputSource = null
	if str(learner.get("type", "policy")) == "policy":
		if policy == null:
			return _fail("no policy for the learner")
		policy_src = PolicyInputSource.create(policy, seed_value ^ 0x5bd1e995, 0)
		policy_src.apply_creature_mask(c_learner)
		policy_src.on_decision = func(_o: PackedFloat32Array, mv: int, bt: int) -> void: tracker.note_action(mv, bt)
		src = policy_src
	else:
		src = LabOpponents.create(str(learner.get("kind", "idle")), seed_value ^ 0x2545F491, c_learner)
		if src == null:
			return _fail("unknown scripted learner '%s'" % str(learner.get("kind", "")))
	if bool(it.get("record", false)):
		recorder = PolicyRecorder.new(src, "", "teacher")
		src = recorder
	var opp := LabOpponents.create(str(ep.get("opponent", "idle")), seed_value * 3 + 1, c_opp)
	if opp == null:
		return _fail("unknown opponent '%s'" % str(ep.get("opponent", "")))
	world = SubViewport.new()
	world.own_world_3d = true
	world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	world.size = Vector2i(2, 2)
	world.name = "Episode%d" % int(it.get("i", 0))
	parent.add_child(world)
	sim = MatchSim.new()
	sim.running = false
	world.add_child(sim)
	var round_time := float(ep.get("round_time", 10.0))
	# standard rules for one round; the cosmetic intro shrinks to a short settle and a timeout
	# tie is a draw (no sudden death), so every episode has a bounded length
	var rules := {"rounds": 1, "round_time": round_time, "lives": 1, "intro_time": float(SETTLE_TICKS) / float(Engine.physics_ticks_per_second),
		"sudden_death": false}
	sim.setup({"arena": LabScenarios.arena_for(ep), "rules": rules, "seed": seed_value,
		"fighters": [{"creature": c_learner, "team": 0, "source": src, "name": "Learner", "kind": "policy"},
			{"creature": c_opp, "team": 1, "source": opp, "name": LabOpponents.display_name(str(ep.get("opponent", ""))), "kind": "bot", "mods": opp_mods}]})
	max_ticks = int(round_time * Engine.physics_ticks_per_second) + Engine.physics_ticks_per_second
	return ""


## A saved campaign build as a fighter: the campaign's own BuildApplier (techniques, supplements
## and their hooks/patches; no Cannery upgrades, no Dose). {creature, mods, errors}.
static func compose_build(build: Dictionary) -> Dictionary:
	if str(build.get("fighter", "")) == "":
		return {"creature": null, "errors": PackedStringArray(["no fighter"])}
	var player := {"fighter": str(build["fighter"]), "techniques": build.get("techniques", []), "supplements": build.get("supplements", [])}
	return BuildApplier.compose(CampaignCatalog.shared(), {"variant": "off_the_street", "dose": 0}, player, {"party": "solo"})


func _fail(msg: String) -> String:
	error = msg
	done = true
	result = {"i": int(item.get("i", -1)), "error": msg}
	return msg


## Advances one physics tick (the physics server integrates the world after this frame).
func tick(dt: float) -> void:
	if done:
		return
	sim.step(dt)
	ticks += 1
	if not started_fight:
		# the mode itself ends the (shortened) intro and starts the fight with the round timer
		if sim.mode.phase == MatchMode.Phase.FIGHT:
			tracker.start(sim, 0)
			started_fight = true
		elif ticks > SETTLE_TICKS + Engine.physics_ticks_per_second * 5:
			_fail("the round never started")
		return
	fight_ticks += 1
	tracker.update(sim, dt)
	if sim.mode.phase != MatchMode.Phase.FIGHT or fight_ticks >= max_ticks or sim.is_finished:
		_complete()


func _complete() -> void:
	var winner := sim.mode.round_winner if sim.mode.phase != MatchMode.Phase.FIGHT else -2
	var outcome := tracker.finish(sim, winner)
	var ep: Dictionary = item["episode"]
	var me := sim.fighters[0]
	result = {"i": int(item.get("i", -1)), "outcome": outcome, "raw": tracker.raw.duplicate(), "ticks": fight_ticks,
		"opponent": str(ep.get("opponent", "")), "spawn": str(ep.get("spawn", "")), "seed": int(ep.get("seed", 0)),
		"group": str(item.get("group", "")), "act_hist": Array(tracker.act_hist), "health_left": me.health_frac(),
		"decision_us": policy_src.mean_decision_usec() if policy_src != null else 0.0,
		"decision_max_us": policy_src.max_usec if policy_src != null else 0}
	if recorder != null:
		recorder._close_window()
		result["samples"] = recorder.sample_count()
		var hist := []
		hist.resize(PolicyActions.OUTPUTS)
		hist.fill(0)
		for k in recorder.moves.size():
			hist[recorder.moves[k]] += 1
			hist[PolicyActions.MOVE_COUNT + recorder.buttons[k]] += 1
		result["label_hist"] = hist
	done = true


## Pauses/resumes this episode's physics world (used by the worker's pause command).
func freeze(on: bool) -> void:
	if sim != null and is_instance_valid(sim) and sim.is_inside_tree():
		PhysicsServer3D.space_set_active(sim.get_world_3d().space, not on)


func dispose() -> void:
	if policy_src != null:
		# the decision hook captures this episode: break the reference cycle
		policy_src.on_decision = Callable()
	if world != null and is_instance_valid(world):
		world.queue_free()
	world = null
	sim = null
