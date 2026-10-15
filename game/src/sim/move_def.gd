class_name MoveDef
extends RefCounted
## A physical action: keyframed effector targets / joint rotations that the motor chases, damage
## windows tied to weapon points, lunges, armor, cancel rules, and (for abilities) timed effects.
## Schema: content/schemas/kit.schema.json ("moves" entries).

const BASE := "base"

var id := ""
var display_name := ""
var kind := "melee"           ## melee | grab | taunt | ability
var duration := 0.5
var windows: Array = []       ## [{t0, t1, weapons: PackedStringArray}]
var cancel_t0 := 9.0          ## chaining allowed from this time...
var cancel_on_hit := false    ## ...only if this move hit something
var damage := 6.0
var knockback := 2.0          ## m/s of velocity change on a reference 80 kg target
var launch := 0.0             ## extra upward velocity (m/s)
var stun := 0.25
var poise := 10.0
var stamina := 6.0
var hype := 1.0               ## multiplier on hype gained from this move's damage
var vmin := 1.4               ## closing speed (m/s) below which contact does nothing
var vref := 5.0               ## closing speed that counts as a full-power hit
var lunges: Array = []        ## [[t0, t1, speed m/s forward]]
var move_mult := 0.3          ## locomotion allowed while performing
var turn_rate := 6.0          ## rad/s turning allowed while performing
var armor: Array = []         ## [[t0, t1]] super armor windows (no stun from hits)
var invuln: Array = []        ## [[t0, t1]] evasion windows
var element := ""
var buildup := 0.0
var knockdown := false
var multi_hit := false        ## may hit the same target again (each window, or every `rehit` s)
var rehit := 9.0              ## with multi_hit: seconds before the same window may hit again
var kb_dir := "auto"          ## auto (contact normal + forward) | side | up | radial
var kb_side := 1.0            ## side knockback: +1 toward the attacker's left, -1 right
var pull := 0.0               ## pulls the target this many metres toward the attacker on hit
var turn_target := 0.0        ## degrees the target is spun on hit
var splat := {}               ## wall-splat bonus if the target hits a wall shortly after {damage, stun, knockdown}
var on_hit: Array = []        ## inline hooks evaluated on this move's hits ({"if": {...}, "do": [...]})
var armor_level := "all"      ## all | lights | all_but_heavy (what the armor windows ignore)
var channel := false          ## an interruptible channel (Jolted micro-flinches cancel it)
var move_class := ""          ## overrides the slot-derived class (light|heavy|ability|juice|grab)
var unblockable := false
var guard_break := 1.0        ## multiplier on stamina drained from a guarding target
var speed := 1.0              ## muscle speed multiplier for animated segments
var charge_time := 0.0        ## >0: hold to charge up to this many seconds
var charge_damage := 0.5      ## extra damage fraction at full charge
var effects: Array = []       ## ability timeline events: [{t, type, ...}]
var keys: Array = []          ## [{t, chains:{name:Vector3|BASE}, poles:{}, joints:{idx:Quaternion|BASE}, lean, height}]
var animated_chains: PackedStringArray = PackedStringArray()
var animated_joints: PackedInt32Array = PackedInt32Array()
var props: PackedStringArray = PackedStringArray()
var interval := 0.0           ## kit extension (pummel slot): minimum seconds between pummels, 0 = no limit


static func parse(d: Dictionary, body: BodyDef, errors: PackedStringArray) -> MoveDef:
	var m := MoveDef.new()
	m.id = str(d.get("id", ""))
	m.display_name = str(d.get("name", m.id))
	m.kind = str(d.get("kind", "melee"))
	m.duration = float(d.get("duration", 0.5))
	m.cancel_t0 = float(d.get("cancel", 9.0))
	m.cancel_on_hit = bool(d.get("cancel_on_hit", false))
	m.damage = float(d.get("damage", 6.0))
	m.knockback = float(d.get("knockback", 2.0))
	m.launch = float(d.get("launch", 0.0))
	m.stun = float(d.get("stun", 0.25))
	m.poise = float(d.get("poise", 10.0))
	m.stamina = float(d.get("stamina", 6.0))
	m.hype = float(d.get("hype", 1.0))
	m.vmin = float(d.get("vmin", 1.4))
	m.vref = maxf(m.vmin + 0.5, float(d.get("vref", 5.0)))
	m.lunges = d.get("lunge", [])
	m.move_mult = float(d.get("move_mult", 0.3))
	m.turn_rate = float(d.get("turn_rate", 6.0))
	m.armor = d.get("armor", [])
	m.invuln = d.get("invuln", [])
	m.element = str(d.get("element", ""))
	m.buildup = float(d.get("buildup", 0.0))
	m.knockdown = bool(d.get("knockdown", false))
	m.multi_hit = bool(d.get("multi_hit", false))
	m.rehit = float(d.get("rehit", 9.0))
	m.kb_dir = str(d.get("kb_dir", "auto"))
	m.kb_side = float(d.get("kb_side", 1.0))
	m.pull = float(d.get("pull", 0.0))
	m.turn_target = float(d.get("turn_target", 0.0))
	m.splat = d.get("splat", {})
	m.on_hit = d.get("on_hit", [])
	m.armor_level = str(d.get("armor_level", "all"))
	m.channel = bool(d.get("channel", false))
	m.move_class = str(d.get("class", ""))
	for oh in m.on_hit:
		if typeof(oh) != TYPE_DICTIONARY:
			errors.append("move '%s': on_hit entries must be objects" % m.id)
	for ef in m.effects:
		var ve := EffectsSystem.validate(ef) if typeof(ef) == TYPE_DICTIONARY else "effect is not an object"
		if ve != "":
			errors.append("move '%s': %s" % [m.id, ve])
	m.unblockable = bool(d.get("unblockable", false))
	m.guard_break = float(d.get("guard_break", 1.0))
	m.speed = float(d.get("speed", 1.0))
	m.charge_time = float(d.get("charge_time", 0.0))
	m.charge_damage = float(d.get("charge_damage", 0.5))
	m.effects = d.get("effects", [])
	m.props = PackedStringArray(d.get("props", []))
	m.interval = float(d.get("interval", 0.0))
	for w in d.get("hit", []):
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var weps := PackedStringArray(w.get("weapons", []))
		for wn in weps:
			if body and not body.weapons.has(wn):
				errors.append("move '%s': unknown weapon '%s'" % [m.id, wn])
		m.windows.append({"t0": float(w.get("t0", 0.0)), "t1": float(w.get("t1", 0.0)), "weapons": weps})
	# keyframes
	var raw_keys: Array = d.get("keys", [])
	for kd in raw_keys:
		for cname in kd.get("chains", {}):
			if not m.animated_chains.has(str(cname)):
				m.animated_chains.append(str(cname))
		for sid in kd.get("joints", {}):
			if body and body.seg_index.has(str(sid)):
				var idx: int = body.seg_index[str(sid)]
				if not m.animated_joints.has(idx):
					m.animated_joints.append(idx)
	for kd in raw_keys:
		var k := {"t": float(kd.get("t", 0.0)), "chains": {}, "poles": {}, "joints": {},
			"lean": MathX.vec3(kd.get("lean", [0, 0, 0])), "height": float(kd.get("height", 0.0)) * (body.scale if body else 1.0)}
		var kc: Dictionary = kd.get("chains", {})
		for cname in m.animated_chains:
			if kc.has(cname) and typeof(kc[cname]) != TYPE_STRING:
				var entry = kc[cname]
				if typeof(entry) == TYPE_DICTIONARY:
					k["chains"][cname] = MathX.vec3(entry.get("target", [0, 0, 0])) * body.scale
					if entry.has("pole"):
						k["poles"][cname] = MathX.vec3(entry["pole"]).normalized()
				else:
					k["chains"][cname] = MathX.vec3(entry) * body.scale
				if body and not body.chains.has(cname):
					errors.append("move '%s': unknown chain '%s'" % [m.id, cname])
			else:
				k["chains"][cname] = BASE
		var kj: Dictionary = kd.get("joints", {})
		for idx in m.animated_joints:
			var sid2: String = body.segments[idx].id
			if kj.has(sid2) and typeof(kj[sid2]) != TYPE_STRING:
				k["joints"][idx] = MathX.euler_deg(MathX.vec3(kj[sid2]))
			else:
				k["joints"][idx] = BASE
		m.keys.append(k)
	m.keys.sort_custom(func(a, b): return a["t"] < b["t"])
	if m.id == "":
		errors.append("move without id")
	if m.duration <= 0.0:
		errors.append("move '%s': duration must be > 0" % m.id)
	return m


func window_weapons(t: float) -> PackedStringArray:
	for w in windows:
		if t >= w["t0"] and t <= w["t1"]:
			return w["weapons"]
	return PackedStringArray()


func window_index(t: float) -> int:
	for i in windows.size():
		if t >= windows[i]["t0"] and t <= windows[i]["t1"]:
			return i
	return -1


func first_active() -> float:
	return windows[0]["t0"] if not windows.is_empty() else duration


## When the last hit window closes (0 for moves without windows).
func last_active() -> float:
	var t := 0.0
	for w in windows:
		t = maxf(t, float(w["t1"]))
	return t


func in_ranges(ranges: Array, t: float) -> bool:
	for r in ranges:
		if r.size() >= 2 and t >= float(r[0]) and t <= float(r[1]):
			return true
	return false


func lunge_speed(t: float) -> float:
	var v := 0.0
	for l in lunges:
		if l.size() >= 3 and t >= float(l[0]) and t <= float(l[1]):
			v = maxf(v, float(l[2]))
	return v


## Writes this move's pose overlay at time t into the motor. Chains/joints whose surrounding
## keys are both BASE are left to the base pose.
func apply_overlay(t: float, motor: FighterMotor) -> void:
	motor.overlay_chains.clear()
	motor.overlay_poles.clear()
	motor.overlay_joints.clear()
	motor.overlay_lean = Vector3.ZERO
	motor.overlay_height = 0.0
	if keys.is_empty():
		return
	var k0: Dictionary = keys[0]
	var k1: Dictionary = keys[keys.size() - 1]
	for i in range(keys.size() - 1):
		if t >= keys[i]["t"] and t <= keys[i + 1]["t"]:
			k0 = keys[i]
			k1 = keys[i + 1]
			break
	if t <= keys[0]["t"]:
		k0 = keys[0]
		k1 = keys[0]
	elif t >= keys[keys.size() - 1]["t"]:
		k0 = keys[keys.size() - 1]
		k1 = k0
	var span: float = k1["t"] - k0["t"]
	var u := MathX.smooth01((t - k0["t"]) / span) if span > 1e-5 else 1.0
	for cname in animated_chains:
		var a = k0["chains"][cname]
		var b = k1["chains"][cname]
		if typeof(a) == TYPE_STRING and typeof(b) == TYPE_STRING:
			continue
		var c: BodyDef.Chain = motor.def.chains[cname]
		var base_t: Vector3 = motor.base_chain_target(cname, c)
		var va: Vector3 = base_t if typeof(a) == TYPE_STRING else a
		var vb: Vector3 = base_t if typeof(b) == TYPE_STRING else b
		motor.overlay_chains[cname] = va.lerp(vb, u)
		var pa = k0["poles"].get(cname)
		var pb = k1["poles"].get(cname)
		if pa != null or pb != null:
			var dp: Vector3 = c.pole
			motor.overlay_poles[cname] = (pa if pa != null else dp).lerp(pb if pb != null else dp, u).normalized()
	for idx in animated_joints:
		var ja = k0["joints"][idx]
		var jb = k1["joints"][idx]
		if typeof(ja) == TYPE_STRING and typeof(jb) == TYPE_STRING:
			continue
		var base_q: Quaternion = motor.base_joint_local(idx)
		var qa: Quaternion = base_q if typeof(ja) == TYPE_STRING else ja
		var qb: Quaternion = base_q if typeof(jb) == TYPE_STRING else jb
		motor.overlay_joints[idx] = qa.slerp(qb, u)
	motor.overlay_lean = Vector3(k0["lean"]).lerp(k1["lean"], u)
	motor.overlay_height = lerpf(k0["height"], k1["height"], u)
