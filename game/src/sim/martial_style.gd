class_name MartialStyle
## Cage Rules standing moves adapted to the authoritative Fighter state machine.
## Source poses/strike windows are imported by tools/cage_rules/import.js.
##
## Movesets (v0.9.18, docs/design/MOVESET_COMBAT.md §6, docs/kits/f_varga.md). The limb, the held
## modifier and the stance still choose the strike (slot()); then, only while
## Fighter.combat_style == "moves", the press may become something more, checked in this order:
##   * Iron Counter          Check held + a straight (Straights + a hand)   "<side>_iron_counter"
##   * Thousand-Fist Flurry  a plain hand (no modifier) as the third strike of a string whose two
##                           strikes before it landed (connected, hit or blocked: move_hit_any, the
##                           engine's own string rule), chained in their recovery "thousand_fist_flurry"
##   * Shockwave Uppercut    a plain hand with the target within SHOCKWAVE_RANGE "<side>_shockwave_uppercut"
##   * the equipped technique of the press's modifier group (Fighter.move_overrides, built by
##     Fighter.set_combat from the loadout's `martial.slots`), attributed to its pool move
##   * a plain strike's gold-aura version                                     "<side>_aura_<kind>"
##   * Afterimage Rush       stance switch + dodge in either order inside AFTERIMAGE_WINDOW: pose()
##                           turns the dodge into "afterimage_rush" right after the state machine.
## Each piece falls back to the one below it when its move is missing (mods, older content) or
## stamina cannot pay for it. The combinations report their own move key as the slot; techniques
## and aura strikes report the limb slot they stand in for (as Fighter._move_variant does), so
## hooks, judges and the tutorial keep reading Cage Rules slots. Classic never reaches any of it:
## the v0.9.17 path is unchanged.
## String bookkeeping (Movesets only): Fighter._light_step holds how many strikes of the current
## string landed before the strike now running (Fighter resets it to 0 back in neutral).
const LIMBS := [FighterInput.LIGHT, FighterInput.HEAVY, FighterInput.MMA_LL, FighterInput.MMA_RL]
const SIDES := ["lh", "rh", "ll", "rl"]
const KINDS := [
	["uppercut", "uppercut", "teep", "knee"],
	["hook", "hook", "bkick", "bkick"],
	["straight", "straight", "hkick", "hkick"],
	["overhand", "overhand", "lkick", "lkick"],
]
const HANDS := [FighterInput.LIGHT, FighterInput.HEAVY]
const STRAIGHTS := 2                     ## the modifier whose hand strikes are straights
const SHOCKWAVE_RANGE := 1.2             ## m, root to root: a plain hand this close is the Shockwave Uppercut
const FLURRY_AFTER := 2                  ## landed strikes of a string before a plain hand is the flurry
const AFTERIMAGE_WINDOW := 0.25          ## s between the stance switch and the dodge, either order
const STANCE_FLAG := "mma_stance_switch" ## timed flag: a Movesets stance switch just happened
const FLURRY := "thousand_fist_flurry"
const RUSH := "afterimage_rush"
const AURA := {"uppercut": "aura_uppercut", "teep": "aura_teep", "knee": "aura_knee"}
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
		if f.combat_style == "moves":
			f.set_flag(STANCE_FLAG, AFTERIMAGE_WINDOW)
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
		if f.combat_style == "moves":
			return _moves_strike(f, b, int(entry.get("mma_mod", 0)), key, move, from_cancel)
		if f.stamina < move.stamina:
			f._consume(b)
			return false
		f._consume(b)
		f._start_move(move, key, Fighter.State.ATTACK)
		f._light_step = 0
		return true
	return false


## Movesets: what one limb press performs (see the header): a combination, the equipped technique,
## or the plain strike in its gold-aura version, the first of them that exists and that stamina
## pays for (a combination out of stamina falls back to the strike itself). Consumes the press;
## false when even the plain strike is too dear (as in Classic).
static func _moves_strike(f: Fighter, b: int, mod: int, key: String, plain: MoveDef, from_cancel: bool) -> bool:
	var hand := HANDS.has(b)
	# strikes of the current string that landed before this one
	var chain := f._light_step + 1 if from_cancel and f.move != null and f.move_hit_any else 0
	var options: Array = []          # [MoveDef, reported slot, pool move id], best first
	if hand and mod == STRAIGHTS and f.input.is_held(FighterInput.MMA_CHECK):
		_combo(options, f, named(key, "iron_counter"))
	if hand and mod == 0 and chain >= FLURRY_AFTER:
		_combo(options, f, FLURRY + ("@southpaw" if f.martial_southpaw else ""))
	if hand and mod == 0 and target_within(f, SHOCKWAVE_RANGE):
		_combo(options, f, named(key, "shockwave_uppercut"))
	var aura := named(key, str(AURA.get(kind_of(key), "")))
	if f.move_overrides.has(key):
		options.append([f.move_overrides[key], key, technique_of(f, key)])
	elif AURA.has(kind_of(key)) and f.creature.moves.has(aura):
		options.append([f.creature.moves[aura], key, ""])
	options.append([plain, key, ""])
	f._consume(b)
	for o: Array in options:
		var m: MoveDef = o[0]
		if f.stamina < m.stamina:
			continue
		f._start_move(m, str(o[1]), Fighter.State.ATTACK, str(o[2]))
		f._light_step = chain
		if m.charge_time > 0.0 and not bool(f.mods.get("auto_charge", false)):
			# a charging technique (Pressure Palm) charges while its limb stays held, fires on release
			f._charging = true
			f._hold_button = b
		return true
	return false


## Adds a contextual combination's move (reported under its own key) when the creature has it.
static func _combo(options: Array, f: Fighter, combo: String) -> void:
	if f.creature.moves.has(combo):
		options.append([f.creature.moves[combo], combo, ""])


## The strike kind of a limb slot ("lh_uppercut@southpaw" -> "uppercut").
static func kind_of(key: String) -> String:
	return key.split("@")[0].substr(3)


## A move key on the same side and stance as a limb slot ("rh_straight@southpaw", "iron_counter"
## -> "rh_iron_counter@southpaw").
static func named(key: String, word: String) -> String:
	return key.substr(0, 3) + word + ("@southpaw" if key.ends_with("@southpaw") else "")


## The equipped technique (pool move id) that performs limb slot `key`, or "".
static func technique_of(f: Fighter, key: String) -> String:
	for id in f.loadout:
		var pm: PoolMove = f.creature.pool.get(str(id))
		if pm == null:
			continue
		var reps = pm.martial.get("slots", {})
		if typeof(reps) == TYPE_DICTIONARY and (reps as Dictionary).has(key):
			return pm.id
	return ""


## Whether the fighter's target stands within `r` metres (root to root, on the floor plane).
static func target_within(f: Fighter, r: float) -> bool:
	if f.target == null or f.target.is_out():
		return false
	var d := f.target.pos() - f.pos()
	d.y = 0.0
	return d.length() <= r


## Movesets: a stance switch and a dodge inside AFTERIMAGE_WINDOW of each other (either order) turn
## the dodge into the Afterimage Rush. Runs right after the state machine (from pose()), so a dodge
## that has just started is caught before it slides a step; a stance press still waiting in the
## buffer is the switch itself.
static func _afterimage(f: Fighter) -> void:
	if f.state != Fighter.State.DODGE or f.state_time > AFTERIMAGE_WINDOW:
		return
	var m: MoveDef = f.creature.moves.get(RUSH)
	if m == null or f.stamina < m.stamina:
		return
	if not f.has_flag(STANCE_FLAG):
		if not f._consume(FighterInput.MMA_STANCE):
			return
		f.martial_southpaw = not f.martial_southpaw
		f.motor.reset_feet()
	f.clear_flag(STANCE_FLAG)
	f._start_move(m, RUSH, Fighter.State.ATTACK)
	f._light_step = 0


static func pose(f: Fighter) -> void:
	if f.combat_style == "moves":
		_afterimage(f)
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
