class_name MartialStyle
## Cage Rules standing moves adapted to the authoritative Fighter state machine.
## Source poses/strike windows are imported by tools/cage_rules/import.js.
const LIMBS := [FighterInput.LIGHT, FighterInput.HEAVY, FighterInput.MMA_LL, FighterInput.MMA_RL]
const SIDES := ["lh", "rh", "ll", "rl"]
const KINDS := [
	["uppercut", "uppercut", "teep", "knee"],
	["hook", "hook", "bkick", "bkick"],
	["straight", "straight", "hkick", "hkick"],
	["overhand", "overhand", "lkick", "lkick"],
]
static func modifier(inp: FighterInput) -> int:
	for pair in [[FighterInput.MMA_MOD3, 3], [FighterInput.MMA_MOD2, 2], [FighterInput.MMA_MOD1, 1]]:
		if inp.is_held(pair[0]):
			return pair[1]
	return 0
static func slot(limb: int, mod: int, southpaw: bool) -> String:
	var idx := LIMBS.find(limb)
	if idx < 0:
		return ""
	var side := idx ^ 1 if southpaw else idx
	return SIDES[side] + "_" + KINDS[clampi(mod, 0, 3)][idx] + ("@southpaw" if southpaw else "")
static func actions(f: Fighter, from_cancel: bool) -> bool:
	if not from_cancel and f._consume(FighterInput.MMA_STANCE):
		f.martial_southpaw = not f.martial_southpaw
		f.motor.reset_feet()
		return true
	for entry: Dictionary in f._buffer:
		var b := int(entry["b"])
		if not LIMBS.has(b):
			continue
		var key := slot(b, int(entry.get("mma_mod", 0)), f.martial_southpaw)
		var move: MoveDef = f.creature.moves.get(key)
		if move == null:
			continue
		if b in [FighterInput.MMA_LL, FighterInput.MMA_RL] and (f._airborne or not f.rig.grounded):
			continue
		if f.stamina < move.stamina:
			f._consume(b)
			return false
		f._consume(b)
		f._start_move(move, key, Fighter.State.ATTACK)
		f._light_step = 0
		return true
	return false
static func pose(f: Fighter) -> void:
	# Only the striking hand needs height retargeting. Lowering the guard/counterweight
	# hand toward a short opponent folds that forearm into the chest during kicks.
	if f.move and f.motor.strike_height_scale != 1.0:
		var striking := {}
		for window in f.move.windows:
			for name in window["weapons"]:
				var weapon: BodyDef.Weapon = f.creature.body.weapons[name]
				striking[weapon.seg] = true
		for name in ["arm_l", "arm_r"]:
			var chain: BodyDef.Chain = f.creature.body.chains[name]
			if f.motor.overlay_chains.has(name) and not striking.has(chain.segs[1]):
				var point: Vector3 = f.motor.overlay_chains[name]
				point.y /= f.motor.strike_height_scale
				f.motor.overlay_chains[name] = point
	var pose_name := "guard"
	if f.input.is_held(FighterInput.MMA_MOD3):
		pose_name = "shell"
	elif f.input.is_held(FighterInput.MMA_CHECK):
		pose_name = "check"
	f.motor.guard_pose = f.creature.body.poses.get(pose_name, f.motor.base_pose)
	if f.input.is_held(FighterInput.MMA_CHECK) and f.state in [Fighter.State.NEUTRAL, Fighter.State.GUARD]:
		var p: BodyDef.Pose = f.creature.body.poses.get("check")
		for name in ["lThigh", "lShin"]:
			var src: int = f.creature.body.seg_index[name]
			var idx: int = f.creature.body.seg_index["r" + name.substr(1)] if f.martial_southpaw else src
			if p and p.joints.has(src):
				var q: Quaternion = p.joints[src]
				f.motor.overlay_joints[idx] = Quaternion(q.x,-q.y,-q.z,q.w) if f.martial_southpaw else q
	if f.martial_southpaw:
		# Mirror the imported orthodox body pose as well as selecting the opposite-side strike.
		var original := f.motor.overlay_joints.duplicate()
		for s: BodyDef.Seg in f.creature.body.segments:
			if s.parent < 0 or original.has(s.index) or s.part in ["leg", "arm"]:
				continue
			var other := s.id
			if s.id.begins_with("l"):
				other = "r" + s.id.substr(1)
			elif s.id.begins_with("r"):
				other = "l" + s.id.substr(1)
			var src: int = f.creature.body.seg_index.get(other, s.index)
			var q: Quaternion = original.get(src, f.motor._joint_local(src, f.motor.guard_blend))
			f.motor.overlay_joints[s.index] = Quaternion(q.x, -q.y, -q.z, q.w)
		# Move chains are already mirrored by the importer. Mirror only idle/guard targets.
		var targets := {}
		var poles := {}
		for name in ["arm_l", "arm_r"]:
			if f.motor.overlay_chains.has(name):
				continue
			var other := "arm_r" if name == "arm_l" else "arm_l"
			var chain: BodyDef.Chain = f.creature.body.chains[other]
			var target := f.motor.base_chain_target(other, chain)
			target.x = -target.x
			targets[name] = target
			var pole: Vector3 = f.motor._pose_pole(other, f.motor.guard_blend)
			pole.x = -pole.x
			poles[name] = pole
		f.motor.overlay_chains.merge(targets)
		f.motor.overlay_poles.merge(poles)
		if not f.move:
			f.motor.overlay_lean.y = -f.motor.overlay_lean.y
