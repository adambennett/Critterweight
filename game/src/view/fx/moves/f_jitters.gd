extends MoveFxKit
## Jitters' Movesets effects (v0.9.18): the Thunder Jolt's streaking bolt, the Chain Lightning ball
## and the jump it makes, the Discharge burst and its crackling ring, and the Static Field. Battery
## jelly identity: lightning that snaps in zigzags off a squashing, glowing jelly (yellow-white arcs
## and sparks around a cyan core), never a smooth beam. A build-up holds until its move's first
## effect, or until the move is cut off; projectiles and fields live exactly as long as their
## entities, and the fields follow their zone (position and size).

const BOLT := Color(1.0, 0.9, 0.3)          ## Jitters' lightning (as the v0.9.17 static recipes)
const HOT := Color(1.0, 1.0, 0.85)          ## white-hot cores
const SPARK := Color(1.0, 0.95, 0.6)
const JELLY := Color(0.74, 0.94, 1.0)       ## the battery jelly's own glow (palette primary)

const V_JOLT := "jitters_thunder_jolt"      ## Thunder Jolt: its launch event and the bolt entity
const V_BALL := "jitters_chain_bolt"        ## Chain Lightning: its launch event and the ball entity
const V_ARC := "jitters_chain_arc"          ## the jump from the struck target
const V_BEAM := "jitters_chain_beam"        ## Lightning Strike style: the instant line
const V_FIELD := "jitters_static_field"     ## Static Field (and Squash's Aftershock landing field)
const V_CHAIN_FIELD := "jitters_chain_field"   ## Ground Current style: the small field a ball leaves
const V_CORE := "jitters_discharge_core"    ## Discharge: the burst ...
const V_RING := "jitters_discharge_ring"    ## ... and each pulse of its ring

const NEW_MOVES := ["thunder_jolt", "chain_lightning", "discharge", "static_field"]
const PREP_TAG := "jitters_prep"            ## follow tag of this kit's build-up pieces
const CRACKLE := 0.06                       ## seconds between build-up arcs ...
const CRACKLE_REDUCED := 0.18               ## ... and under Reduce flashing
const JUMP_PAIR := 0.2                      ## a chain jump's hit and effect events arrive this close

var _preps := {}        ## fighter -> {pool, until, next, seen, n, st: {out, boost}, tele, ahead, lift}
var _jumps := {}        ## fighter -> {from | to: Vector3, t}: the half of a chain jump seen first
var _sphere: SphereMesh = null


func vfx_names() -> Array:
	return [V_JOLT, V_BALL, V_ARC, V_BEAM, V_FIELD, V_CHAIN_FIELD, V_CORE, V_RING]


## ---- build-ups ------------------------------------------------------------------------------------

func on_move_start(fi: int, ev: Dictionary) -> bool:
	_end_prep(fi)                               # a new move cuts any build-up still running
	var pool := str(ev.get("pool", ""))
	if not NEW_MOVES.has(pool):
		return false                            # the v0.9.17 moves keep their v0.9.17 build-ups
	var m := _pool_move(fi, pool)
	var lead := AbilityVfx.first_effect_t(m) if m != null else 0.3
	var floor_y := fx._ground(fi).y
	match pool:
		"thunder_jolt":
			# the antennae crackle and a charge gathers on the cap while Jitters crouches
			var pj := _begin_prep(fi, pool, lead + 0.25)
			for a in ["antenna_l", "antenna_r"]:
				fx._stream_at(fi, a, Vector3.ZERO, lead + 0.25, "sparks", SPARK, HOT, {"amount": 0.35, "speed": 0.4, "floor": floor_y}, PREP_TAG)
			_glow(fi, "cap", Vector3(0, 0.05, 0), lead, lead + 0.25, BOLT, 0.22, pj)
		"chain_lightning":
			# a ball of lightning swells in the drawn-back hand, fed by arcs from the antennae
			var pc := _begin_prep(fi, pool, lead + 0.3)
			_glow(fi, "slap_r", Vector3.ZERO, lead, lead + 0.3, JELLY, 0.42, pc)
			fx._converge(fi, "slap_r", Vector3.ZERO, lead, BOLT, HOT, 0.5)
			fx._stream_at(fi, "slap_r", Vector3.ZERO, lead + 0.3, "sparks", SPARK, HOT, {"amount": 0.4, "speed": 0.5, "floor": floor_y}, PREP_TAG)
		"discharge":
			# the coil glows through the squashed jelly, arcs crawl over it, and the ring's true band
			# spreads on the floor around it (a Capacitor charge may hold all of it longer)
			var pd := _begin_prep(fi, pool, lead + 1.3)
			_glow(fi, "core", Vector3.ZERO, lead, lead + 1.3, JELLY, 0.62, pd)
			fx._converge(fi, "core", Vector3.ZERO, lead, BOLT, HOT, 0.7)
			var ring := _shaped(m, "ring")
			var outer := float(ring.get("radius", 2.5))
			_telegraph(fi, pd, "ring", outer, {"inner": float(ring.get("inner", 0.0)), "fill": 0.15, "front": 0.3, "strength": 0.45}, lead, 0.0)
		"static_field":
			# both hands fizz as they rise, and the field's true circle spreads where it will land
			var pf := _begin_prep(fi, pool, lead + 0.3)
			for h in ["slap_l", "slap_r"]:
				fx._stream_at(fi, h, Vector3.ZERO, lead + 0.3, "sparks", SPARK, HOT, {"amount": 0.35, "speed": 0.5, "floor": floor_y}, PREP_TAG)
			var zone := AbilityVfx.effect_of(m, "zone")
			_telegraph(fi, pf, "circle", float(zone.get("radius", 2.0)), {"fill": 0.12, "front": 0.3, "strength": 0.45}, lead,
				_ahead(str(zone.get("at", "self"))))
	return false        # the generic move-start bookkeeping (hovers, v0.9.17 build-ups) still runs


func _begin_prep(fi: int, pool: String, cap: float) -> Dictionary:
	var pr := {"pool": pool, "until": fx._clock + cap, "next": 0.0, "seen": false, "n": 0, "st": {"out": INF, "boost": 0.0},
		"tele": null, "ahead": 0.0, "lift": 0.0}
	_preps[fi] = pr
	return pr


## Ends a fighter's build-up: its followers stop, its glows and floor telegraph fade.
func _end_prep(fi: int) -> void:
	var pr: Dictionary = _preps.get(fi, {})
	if pr.is_empty():
		return
	_preps.erase(fi)
	var st: Dictionary = pr["st"]
	st["out"] = fx._clock          # its glows and telegraph read this and fade
	fx.release(fi, PREP_TAG)


## A charge swelling on an anchor over `grow` seconds, flickering like a live current, that holds
## until the build-up ends (at most `cap`) and then fades. A Capacitor charge swells it further.
func _glow(fi: int, anchor_name: String, off: Vector3, grow: float, cap: float, c: Color, size: float, pr: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _ball()
	var mat := FxKit.flow_material(c, HOT, {"additive": 1.0, "fresnel": 1.4, "scroll": Vector2(1.5, -2.5), "noise_scale": Vector2(6.0, 4.0),
		"edge_v": 0.0, "core": 0.55, "core_width": 0.5, "alpha": 0.0})
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(mi)
	fx.follow(mi, fi, anchor_name, off, cap)
	fx._follows[-1]["tag"] = PREP_TAG
	var st: Dictionary = pr["st"]
	var dim := 0.7 if fx.reduce_flashes else 1.0
	fx.animate(mi, cap + 0.2, func(_k: float, t: float) -> void:
		var g := smoothstep(0.0, 1.0, t / maxf(grow, 0.001))
		var out := clampf((fx._clock - float(st["out"])) / 0.12, 0.0, 1.0)
		var flick := 1.0 if fx.reduce_flashes else 1.0 + 0.12 * sin(t * 53.0)
		mi.scale = Vector3.ONE * size * (0.3 + 0.7 * g) * (1.0 + 0.6 * float(st["boost"])) * flick
		mat.set_shader_parameter("alpha", g * (1.0 - out) * dim)
		if out >= 1.0:
			mi.queue_free())


## The move's true footprint spreading on the floor over `lead` seconds; process() keeps it on
## Jitters' facing (`ahead` metres in front) until the build-up ends, then it fades in place.
func _telegraph(fi: int, pr: Dictionary, shape: String, r: float, o: Dictionary, lead: float, ahead: float) -> void:
	var mi := fx.footprint("static", shape, fx.fpoint(fi, Vector3(0, 0, ahead)), fx._yaw(fi), r, o, INF)
	var mat := mi.material_override as ShaderMaterial
	var st: Dictionary = pr["st"]
	var strength := float(o.get("strength", 0.5)) * (0.75 if fx.reduce_flashes else 1.0)
	pr["tele"] = mi
	pr["ahead"] = ahead
	pr["lift"] = mi.global_position.y - fx._ground(fi).y     # footprint()'s small lift keeps decals apart
	fx.animate(mi, float(pr["until"]) - fx._clock + 0.3, func(_k: float, t: float) -> void:
		var p := clampf(t / maxf(lead, 0.001), 0.0, 1.0)
		var out := clampf((fx._clock - float(st["out"])) / 0.2, 0.0, 1.0)
		mat.set_shader_parameter("progress", (1.0 - (1.0 - p) * (1.0 - p)) * 1.02)
		mat.set_shader_parameter("fade", strength * (1.0 - out))
		if out >= 1.0:
			mi.queue_free())


## The little arcs of a running build-up (every CRACKLE seconds; decorative, so Medium quality up).
func _crackle(fi: int, pr: Dictionary) -> void:
	var pool := str(pr["pool"])
	if pool == "discharge":
		# a Capacitor charge (the move's charge level, where the view knows it) swells the coil
		var st: Dictionary = pr["st"]
		st["boost"] = clampf(float(fx._info(fi).get("charge", -1.0)), 0.0, 1.0)
	if fx.quality < 1:
		return
	match pool:
		"thunder_jolt":
			fx.bolt(fx.anchor(fi, "antenna_l"), fx.anchor(fi, "antenna_r"), BOLT, 0.07, 0.035, 0.06)
		"chain_lightning":
			# the antennae feed the ball in the hand, one side at a time
			var side := "antenna_l" if int(pr["n"]) % 2 == 0 else "antenna_r"
			pr["n"] = int(pr["n"]) + 1
			fx.bolt(fx.anchor(fi, side), fx.anchor(fi, "slap_r"), BOLT, 0.08, 0.035, 0.08)
		"discharge":
			_body_arc(fi, 0.1)
		"static_field":
			fx.bolt(fx.anchor(fi, "slap_l"), fx.anchor(fi, "slap_r"), BOLT, 0.07, 0.035, 0.1)


## A short arc crawling over the jelly's surface.
func _body_arc(fi: int, dur: float) -> void:
	var c := fx.anchor(fi, "core")
	fx.bolt(c + _rand_dir() * 0.36, c + _rand_dir() * 0.36, BOLT, dur, 0.035, 0.1)


func process(_delta: float) -> void:
	for fi in _preps.keys():
		var pr: Dictionary = _preps[fi]
		var acting := is_acting(fi)
		if acting:
			pr["seen"] = true          # online the sampled state can trail the move_start event a little
		if fx._clock >= float(pr["until"]) or (bool(pr["seen"]) and not acting) or fx._view(fi) == null:
			_end_prep(fi)              # the move was cut off (or its effect never came)
			continue
		var tele = pr["tele"]
		if is_instance_valid(tele):
			var tm := tele as MeshInstance3D
			tm.global_position = fx.fpoint(fi, Vector3(0, float(pr["lift"]), float(pr["ahead"])))
			tm.rotation.y = fx._yaw(fi)
		if fx._clock >= float(pr["next"]):
			pr["next"] = fx._clock + (CRACKLE_REDUCED if fx.reduce_flashes else CRACKLE)
			_crackle(fi, pr)
	for fi in _jumps.keys():
		if fx._clock - float((_jumps[fi] as Dictionary)["t"]) > JUMP_PAIR:
			_jumps.erase(fi)           # the other half never came (no second target in reach)


## ---- contact (effect events) ---------------------------------------------------------------------

func on_effect(fi: int, ev: Dictionary) -> bool:
	var pos: Vector3 = ev.get("pos", fx._ground(fi))
	var r := float(ev.get("radius", 0.0))
	match str(ev.get("vfx", "")):
		V_JOLT:
			if str(ev.get("effect", "")) == "projectile":
				_jolt_launch(fi)
		V_BALL:
			if str(ev.get("effect", "")) == "projectile":
				_ball_launch(fi)
		V_ARC:
			_jump_from(fi, pos + Vector3.UP * 0.8, r)
		V_BEAM:
			_beam(fi, ev)
		V_CORE:
			_discharge_burst(fi, pos, r)
		V_RING:
			_discharge_ring(pos, float(ev.get("inner", 0.0)), r)
		V_FIELD:
			_field_slam(fi, pos, r)
		V_CHAIN_FIELD:
			_field_splash(pos, r)
		_:
			return false
	return true


## ---- Thunder Jolt ---------------------------------------------------------------------------------

## The bolt leaves the cap: a white flash fed by both antennae, a forward spit of sparks, and a jelly
## ripple at the feet as the pop bounces Jitters back.
func _jolt_launch(fi: int) -> void:
	_end_prep(fi)
	var p := fx.anchor(fi, "cap", Vector3(0, 0.04, 0.03))
	var g := fx._ground(fi)
	fx.burst("sparks", p, aim_dir(fi, -0.05), SPARK, HOT, {"amount": 0.6, "speed": 1.6, "spread": 0.45, "floor": g.y})
	fx.burst("glints", p, Vector3.UP, HOT, null, {"amount": 0.45, "speed": 0.5, "scale": 0.8})
	fx.bolt(fx.anchor(fi, "antenna_l"), p, HOT, 0.08, 0.045, 0.04)
	fx.bolt(fx.anchor(fi, "antenna_r"), p, HOT, 0.08, 0.045, 0.04)
	fx.ring_wall(g + Vector3.UP * 0.03, 0.15, 0.55, 0.12, JELLY, HOT, 0.22, {"bands": 6.0, "expand": 0.5})
	fx.flash_light(p, SPARK, 2.5, 3.0, 0.14)


## The Thunder Jolt in flight: a white-hot head stretched along its path and a zigzag tail through
## its last few positions that re-forks every few frames, shedding sparks.
func _jolt_bolt(e: Dictionary) -> Dictionary:
	var r := maxf(float(e.get("radius", 0.16)), 0.06)
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = e["pos"]
	var head := MeshInstance3D.new()
	head.mesh = _ball()
	head.scale = Vector3(r * 1.6, r * 1.6, r * 4.0)       # long along the flight (the root looks along it)
	head.material_override = FxKit.flow_material(BOLT, HOT, {"additive": 1.0, "fresnel": 0.7, "scroll": Vector2(3.0, -5.0),
		"noise_scale": Vector2(6.0, 3.0), "edge_v": 0.0, "core": 0.7, "core_width": 0.6, "alpha": 1.0})
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(head)
	var tail := fx.ribbon(BOLT, HOT, true)
	var tm := tail.material_override as ShaderMaterial
	tm.set_shader_parameter("cover", 0.85)
	tm.set_shader_parameter("glow_k", 1.4)
	var sparks := fx._attached_stream(root, "sparks", SPARK, HOT, {"speed": 0.3, "amount": 0.4})
	_light(root, SPARK, 1.4, 2.2)
	var hist: Array = []          # the bolt's last positions, oldest first (and the reused draw arrays)
	var pts: Array = []
	var w: Array = []
	var al: Array = []
	var st := {"next": 0.0}
	return {"node": root, "kind": "projectile", "pos": e["pos"], "dir": Vector3.FORWARD,
		"tick": func(_e2: Dictionary) -> void:
			if not is_instance_valid(root) or not is_instance_valid(tail):
				return
			hist.append(root.global_position)
			if hist.size() > 6:
				hist.pop_front()
			if hist.size() < 2 or fx._clock < float(st["next"]):
				return
			st["next"] = fx._clock + (0.08 if fx.reduce_flashes else 0.03)
			_zigzag(hist, pts, w, al, r * 1.4, 0.07)
			fx.draw_ribbon(tail, pts, w, al),
		"end": func() -> void:
			if is_instance_valid(root):
				fx.burst("sparks", root.global_position, Vector3.UP, SPARK, HOT, {"amount": 0.3, "speed": 0.6})
			if is_instance_valid(sparks):
				_drop_stream(sparks)
			if is_instance_valid(tail):
				tail.queue_free()
			if is_instance_valid(root):
				root.queue_free()}


## Fills `pts`, `w` and `al` (reused) with a zigzag through the path `hist` (oldest first): its ends
## stay on the path, the middle jumps sideways by up to `jag`, the old end thins out and fades.
func _zigzag(hist: Array, pts: Array, w: Array, al: Array, jag: float, width: float) -> void:
	var n := hist.size()
	pts.resize(n)
	w.resize(n)
	al.resize(n)
	var a: Vector3 = hist[0]
	var b: Vector3 = hist[n - 1]
	var dv := b - a
	var p1 := Vector3.RIGHT
	if dv.length_squared() > 1e-6 and absf(dv.normalized().y) < 0.95:
		p1 = dv.cross(Vector3.UP).normalized()
	var p2 := dv.cross(p1).normalized() if dv.length_squared() > 1e-6 else Vector3.UP
	var fade := 0.75 if fx.reduce_flashes else 1.0
	for i in n:
		var u := float(i) / float(n - 1)
		var hp: Vector3 = hist[i]
		if i > 0 and i < n - 1:
			hp += (p1 * fx._rng.randf_range(-1.0, 1.0) + p2 * fx._rng.randf_range(-1.0, 1.0)) * jag
		pts[i] = hp
		w[i] = width * (0.3 + 0.7 * u)
		al[i] = (0.25 + 0.75 * u) * fade


## The Thunder Jolt landing: a crisp star of short forks; off a guard it sprays away instead.
func _jolt_impact(p: Vector3, blocked: bool) -> void:
	if blocked:
		fx.burst("sparks", p, Vector3.UP, SPARK, HOT, {"amount": 0.5, "speed": 1.4, "spread": 1.2})
		return
	if fx.quality >= 1:
		for k in 4:
			fx.bolt(p, p + _rand_dir() * fx._rng.randf_range(0.25, 0.45), HOT, 0.09, 0.035, 0.06)
	fx.burst("glints", p, Vector3.UP, HOT, null, {"amount": 0.6, "speed": 0.8, "scale": 1.2})
	fx.flash_light(p, SPARK, 2.0, 2.5, 0.12)


## ---- Chain Lightning ------------------------------------------------------------------------------

## The ball leaves the hand: sparks and jelly-light thrown along the throw, the antennae spent.
func _ball_launch(fi: int) -> void:
	_end_prep(fi)
	var p := fx.anchor(fi, "slap_r")
	var d := aim_dir(fi)
	fx.burst("sparks", p, d, SPARK, HOT, {"amount": 0.7, "speed": 1.4, "spread": 0.6, "floor": fx._ground(fi).y})
	fx.burst("motes", p, d, JELLY, HOT, {"amount": 0.5, "speed": 1.2, "spread": 0.5})
	if fx.quality >= 1:
		fx.bolt(fx.anchor(fi, "antenna_l"), p, BOLT, 0.1, 0.04, 0.08)
		fx.bolt(fx.anchor(fi, "antenna_r"), p, BOLT, 0.1, 0.04, 0.08)
	fx.flash_light(p, JELLY, 2.5, 3.0, 0.18)


## The ball in flight: a cyan jelly-light core inside a crackling yellow shell, a band of current
## spinning around it and arcs snapping off it.
func _chain_ball(e: Dictionary) -> Dictionary:
	var r := maxf(float(e.get("radius", 0.24)), 0.1)
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = e["pos"]
	var core := MeshInstance3D.new()
	core.mesh = _ball()
	core.scale = Vector3.ONE * r * 1.4
	core.material_override = FxKit.flow_material(JELLY, HOT, {"additive": 1.0, "fresnel": 1.2, "scroll": Vector2(1.0, -2.0),
		"noise_scale": Vector2(4.0, 3.0), "edge_v": 0.0, "core": 0.6, "core_width": 0.6, "alpha": 1.0})
	var shell := MeshInstance3D.new()
	shell.mesh = _ball()
	shell.scale = Vector3.ONE * r * 2.3
	shell.material_override = FxKit.flow_material(BOLT, HOT, {"additive": 1.0, "fresnel": 2.2, "scroll": Vector2(4.0, -3.0),
		"noise_scale": Vector2(8.0, 6.0), "edge_v": 0.0, "core": 0.3, "core_width": 0.4, "jag": 0.6, "alpha": 0.7})
	var band := MeshInstance3D.new()
	band.mesh = FxKit.wall_mesh(24, 1.0)
	band.material_override = FxKit.flow_material(BOLT, HOT, {"additive": 1.0, "bands": 6.0, "scroll": Vector2(5.0, 0.0),
		"noise_scale": Vector2(12.0, 2.0), "edge_v": 0.5, "core": 0.5, "core_width": 0.3, "alpha": 0.9})
	band.scale = Vector3(r * 1.7, r * 0.35, r * 1.7)
	band.position = Vector3(0, -r * 0.17, 0)
	var spin := Node3D.new()
	spin.add_child(band)
	for n: GeometryInstance3D in [core, shell, band]:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	root.add_child(shell)
	root.add_child(spin)
	var sparks := fx._attached_stream(root, "sparks", SPARK, HOT, {"speed": 0.35, "amount": 0.5})
	_light(root, JELLY, 1.5, 2.4)
	var st := {"t0": fx._clock, "next": 0.0}
	return {"node": root, "kind": "projectile", "pos": e["pos"], "dir": Vector3.FORWARD,
		"tick": func(_e2: Dictionary) -> void:
			if not is_instance_valid(root):
				return
			var t := fx._clock - float(st["t0"])
			spin.rotation = Vector3(t * 9.0, t * 13.0, 0.0)
			shell.scale = Vector3.ONE * r * (2.3 if fx.reduce_flashes else 2.3 + 0.35 * sin(t * 37.0))
			if fx.quality >= 1 and fx._clock >= float(st["next"]):
				st["next"] = fx._clock + (0.2 if fx.reduce_flashes else 0.07)
				var c := root.global_position
				fx.bolt(c, c + _rand_dir() * (r * 2.8 + 0.15), BOLT, 0.07, 0.035, 0.07),
		"end": func() -> void:
			if is_instance_valid(root):
				fx.burst("sparks", root.global_position, Vector3.UP, SPARK, HOT, {"amount": 0.4, "speed": 0.8})
			if is_instance_valid(sparks):
				_drop_stream(sparks)
			if is_instance_valid(root):
				root.queue_free()}


## The ball breaking on its target: arcs crawl over the body and a ring of current drops to its feet.
func _ball_impact(p: Vector3, target: int) -> void:
	for k in (4 if fx.quality >= 1 else 2):
		fx.bolt(p, p + _rand_dir() * fx._rng.randf_range(0.3, 0.6), BOLT, 0.14, 0.04, 0.1)
	fx.burst("motes", p, Vector3.UP, JELLY, HOT, {"amount": 0.6, "speed": 1.2})
	if target >= 0:
		fx.ring_wall(fx._ground(target) + Vector3.UP * 0.04, 0.2, 0.8, 0.3, BOLT, HOT, 0.3, {"bands": 10.0, "scroll": Vector2(3.0, 0.0)})
	fx.flash_light(p, JELLY, 3.0, 3.0, 0.18)


## A guarded ball earths into the guard: a fizzle of sparks and a wisp of smoke, no jump.
func _earthed(p: Vector3) -> void:
	fx.burst("sparks", p, Vector3.DOWN, SPARK, HOT, {"amount": 0.6, "speed": 1.0, "spread": 1.0})
	fx.burst("smoke", p, Vector3.UP, Color(0.6, 0.62, 0.65, 0.35), null, {"amount": 0.25, "speed": 0.4})


## The jump leaving the struck target (`from`, its reach `r` drawn on the floor). The charge crawls
## down into the floor whether or not it finds a second foe; the second target's hit may come before
## or after this event, so whichever half comes first waits for the other and the second draws the leap.
func _jump_from(fi: int, from: Vector3, r: float) -> void:
	var g := Vector3(from.x, 0.0, from.z)
	if r > 0.0:
		fx.footprint("static", "ring", g, 0.0, r, {"inner": maxf(r - 0.3, 0.0), "fill": 0.35, "front": 1.0, "strength": 0.6}, 0.45, 0.12)
	for k in (4 if fx.quality >= 1 else 2):
		var a := fx._rng.randf() * TAU
		fx.bolt(from, g + Vector3(sin(a), 0.0, cos(a)) * fx._rng.randf_range(0.3, 0.7) + Vector3.UP * 0.05, BOLT, 0.16, 0.045, 0.12)
	var half: Dictionary = _jumps.get(fi, {})
	if half.has("to") and fx._clock - float(half["t"]) <= JUMP_PAIR:
		_jumps.erase(fi)
		var to: Vector3 = half["to"]
		_leap(from, to)
	else:
		_jumps[fi] = {"from": from, "t": fx._clock}


## The second target's hit (at `to`): the other half of a chain jump.
func _jump_to(fi: int, to: Vector3) -> void:
	var half: Dictionary = _jumps.get(fi, {})
	if half.has("from") and fx._clock - float(half["t"]) <= JUMP_PAIR:
		_jumps.erase(fi)
		var from: Vector3 = half["from"]
		_leap(from, to)
	else:
		_jumps[fi] = {"to": to, "t": fx._clock}


## The leap itself: a thick bolt between the two bodies with a fork that gives out half-way.
func _leap(from: Vector3, to: Vector3) -> void:
	fx.bolt(from, to, BOLT, 0.3, 0.1, 0.45)
	if fx.quality >= 1:
		fx.bolt(from, to.lerp(from, 0.35) + _rand_dir() * 0.3, HOT, 0.2, 0.05, 0.25)
	fx.burst("sparks", to, Vector3.UP, SPARK, HOT, {"amount": 0.7, "speed": 1.2})
	fx.burst("glints", from, Vector3.UP, HOT, null, {"amount": 0.4, "speed": 0.6})
	fx.flash_light(to, SPARK, 3.5, 3.5, 0.2)


## Lightning Strike (style): the bolt cracks at once along its whole line from the throwing hand.
func _beam(fi: int, ev: Dictionary) -> void:
	_end_prep(fi)
	var o: Vector3 = ev.get("origin", fx._ground(fi))
	var go := Vector3(o.x, 0.0, o.z)
	var yaw := float(ev.get("yaw", fx._yaw(fi)))
	var length := float(ev.get("length", 6.5))
	var width := float(ev.get("width", 0.7))
	var fwd := MathX.forward_of_yaw(yaw)
	var a := fx.anchor(fi, "slap_r")
	var b := go + fwd * length + Vector3.UP * 0.7
	var mid := go + fwd * length * 0.5
	fx.footprint("static", "line", go, yaw, 0.0, {"length": length, "width": width, "fill": 0.55, "front": 1.0}, 0.45, 0.06)
	fx.bolt(a, b, BOLT, 0.28, 0.1, 0.4)
	fx.bolt(a, b + _rand_dir() * 0.4, HOT, 0.2, 0.05, 0.3)
	fx.burst("sparks", mid + Vector3.UP * 0.4, fwd, SPARK, HOT, {"box": Vector3(width * 0.5, 0.1, length * 0.45), "yaw": yaw, "amount": 0.7, "speed": 0.8})
	fx.flash_light(mid + Vector3.UP * 0.8, SPARK, 3.5, 4.0, 0.2)


## ---- Discharge ------------------------------------------------------------------------------------

## The burst: the jelly flashes white and forks of lightning leap out to the burst's edge.
func _discharge_burst(fi: int, pos: Vector3, r: float) -> void:
	_end_prep(fi)
	var g := Vector3(pos.x, 0.0, pos.z)
	var rr := maxf(r, 0.5)
	var c := fx.anchor(fi, "core")
	fx.footprint("static", "circle", g, 0.0, rr, {"fill": 0.6, "front": 1.0}, 0.6, 0.08)
	_flash_ball(c, rr * 1.1, 0.2)
	var forks := 8 if fx.quality >= 1 else 4
	for k in forks:
		var a := TAU * (float(k) + fx._rng.randf() * 0.6) / float(forks)
		fx.bolt(c, g + Vector3(sin(a), 0.0, cos(a)) * rr + Vector3.UP * fx._rng.randf_range(0.05, 0.4), BOLT, 0.2, 0.06, 0.22)
	fx.ring_wall(g, 0.3, rr, 0.55, BOLT, HOT, 0.28, {"bands": 12.0, "scroll": Vector2(3.0, 0.0), "expand": 0.5})
	fx.burst("sparks", c, Vector3.UP, SPARK, HOT, {"amount": 1.0, "speed": 1.4, "floor": g.y})
	fx.burst("motes", c, Vector3.UP, JELLY, HOT, {"amount": 0.6, "speed": 2.0, "spread": 3.1})
	fx.flash_light(c, SPARK, 4.5, rr * 2.0 + 2.0, 0.22)


## One pulse of the ring: a jagged loop of lightning chained around its middle, a thin crackling
## wall racing out to its edge, its true band flashing on the floor.
func _discharge_ring(pos: Vector3, inner: float, r: float) -> void:
	var g := Vector3(pos.x, 0.0, pos.z)
	var rr := maxf(r, inner + 0.2)
	var mid := (inner + rr) * 0.5
	fx.footprint("static", "ring", g, 0.0, rr, {"inner": inner, "fill": 0.5, "front": 1.0}, 0.4, 0.05)
	fx.ring_wall(g, mid * 0.85, rr, 0.6, BOLT, HOT, 0.24, {"bands": 16.0, "scroll": Vector2(4.0, 0.0), "expand": 0.45})
	var n := 5 if fx.quality < 1 else (6 if fx.reduce_flashes else 9)
	var phase := fx._rng.randf() * TAU
	var first := Vector3.ZERO
	var prev := Vector3.ZERO
	for k in n + 1:
		var p := first
		if k < n:
			var a := phase + TAU * float(k) / float(n)
			p = g + Vector3(sin(a), 0.0, cos(a)) * mid * fx._rng.randf_range(0.9, 1.1) + Vector3.UP * fx._rng.randf_range(0.25, 0.7)
		if k == 0:
			first = p
		else:
			fx.bolt(prev, p, BOLT, 0.12, 0.045, 0.12)
		prev = p
	fx.burst("sparks", g + Vector3.UP * 0.3, Vector3.UP, SPARK, HOT, {"ring": true, "radius": mid, "amount": 0.6, "speed": 0.8, "floor": g.y})


## A white-hot sphere bursting out of the jelly (growing to `size` while it fades over `dur`).
func _flash_ball(c: Vector3, size: float, dur: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _ball()
	var mat := FxKit.flow_material(JELLY, HOT, {"additive": 1.0, "fresnel": 2.0, "scroll": Vector2(2.0, -3.0), "noise_scale": Vector2(5.0, 4.0),
		"edge_v": 0.0, "core": 0.4, "core_width": 0.5, "alpha": 1.0})
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(mi)
	mi.global_position = c
	var peak := 0.6 if fx.reduce_flashes else 1.0
	fx.animate(mi, dur, func(k: float, _t: float) -> void:
		mi.scale = Vector3.ONE * lerpf(0.3, size, 1.0 - pow(1.0 - k, 3.0))
		mat.set_shader_parameter("alpha", peak * (1.0 - k)))


## ---- Static Field ---------------------------------------------------------------------------------

## The field lands: both palms send current into the floor and a shock ring runs out to its edge
## (the field itself is drawn as its zone; Squash's Aftershock field lands the same way).
func _field_slam(fi: int, pos: Vector3, r: float) -> void:
	_end_prep(fi)
	var g := Vector3(pos.x, 0.0, pos.z)
	var rr := maxf(r, 0.5)
	for h in ["slap_l", "slap_r"]:
		fx.bolt(fx.anchor(fi, h), g + Vector3.UP * 0.05, BOLT, 0.18, 0.06, 0.16)
	fx.ring_wall(g + Vector3.UP * 0.03, 0.2, rr, 0.35, BOLT, HOT, 0.35, {"bands": 10.0, "scroll": Vector2(2.5, 0.0), "expand": 0.4})
	fx.burst("sparks", g + Vector3.UP * 0.1, Vector3.UP, SPARK, HOT, {"ring": true, "radius": rr * 0.6, "amount": 0.7, "speed": 0.8, "floor": g.y})
	fx.flash_light(g + Vector3.UP * 0.4, SPARK, 3.0, rr * 2.0 + 1.0, 0.2)


## Ground Current (style): the ball's charge spills onto the floor where it burst.
func _field_splash(pos: Vector3, r: float) -> void:
	var g := Vector3(pos.x, 0.0, pos.z)
	var rr := maxf(r, 0.5)
	var src := pos if pos.y > 0.3 else g + Vector3.UP * 0.4
	for k in 3:
		var a := TAU * (float(k) + fx._rng.randf() * 0.5) / 3.0
		fx.bolt(src, g + Vector3(sin(a), 0.0, cos(a)) * rr * 0.8 + Vector3.UP * 0.05, BOLT, 0.16, 0.05, 0.14)
	fx.ring_wall(g + Vector3.UP * 0.03, 0.1, rr, 0.25, BOLT, HOT, 0.3, {"bands": 8.0, "scroll": Vector2(2.0, 0.0)})
	fx.burst("sparks", g + Vector3.UP * 0.1, Vector3.UP, SPARK, HOT, {"amount": 0.5, "speed": 0.8, "floor": g.y})


## A static field on the floor: its true circle crackling in the static floor pattern, a low fence
## of current at its edge, sparks hopping inside, arcs snapping across it, and a zap at anyone who
## walks in (the simulation flinches them at that moment). It follows its zone (Tesla Aura rides on
## Jitters) and the zone's size.
func _field(e: Dictionary) -> Dictionary:
	var r := maxf(float(e.get("radius", 2.0)), 0.3)
	var p: Vector3 = e["pos"]
	var owner_i := int(e.get("owner", -1))     # local matches; online entities carry no owner
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = Vector3(p.x, 0.0, p.z)
	var fp := fx.footprint("static", "circle", Vector3.ZERO, 0.0, r, {"fill": 0.5, "front": 0.0, "stain_a": 0.34, "speed": 1.6}, INF)
	fp.reparent(root)
	fp.position = Vector3.UP * 0.026
	var mat := fp.material_override as ShaderMaterial
	mat.set_shader_parameter("pulse", 1.0)
	var fence := MeshInstance3D.new()
	fence.mesh = FxKit.wall_mesh(48, 1.0)
	var fence_mat := FxKit.flow_material(BOLT, HOT, {"additive": 1.0, "bands": 18.0, "scroll": Vector2(2.2, 0.0), "noise_scale": Vector2(24.0, 2.0),
		"edge_v": 0.5, "core": 0.15, "core_width": 0.2, "jag": 0.5, "alpha": 0.0})
	fence.material_override = fence_mat
	fence.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fence.scale = Vector3(r, 0.24, r)
	root.add_child(fence)
	var gp: GPUParticles3D = null
	if fx.quality >= 1:
		gp = fx.stream("sparks", SPARK, HOT, {"radius": r * 0.8, "speed": 0.35, "amount": clampf(r / 2.0, 0.3, 1.0) * 0.4, "floor": 0.0})
		gp.reparent(root)
		gp.position = Vector3.UP * 0.05
	var st := {"t0": fx._clock, "next": 0.0, "r": r, "in": {}}
	return {"node": root, "kind": "zone", "pos": p,
		"tick": func(ze: Dictionary) -> void:
			if not is_instance_valid(root):
				return
			var t := fx._clock - float(st["t0"])
			# zones grow and shrink in the simulation (zone reactions): keep drawing the real size
			var nr := maxf(float(ze.get("radius", st["r"])), 0.3)
			if absf(nr - float(st["r"])) > 0.005:
				st["r"] = nr
				mat.set_shader_parameter("radius", nr)
				AbilityVfx._fit_footprint(fp, nr)
				fence.scale = Vector3(nr, 0.24, nr)
				if is_instance_valid(gp):
					(gp.process_material as ShaderMaterial).set_shader_parameter("emit_radius", nr * 0.8)
			var cr := float(st["r"])
			mat.set_shader_parameter("progress", clampf(t / 0.25, 0.0, 1.0) * 1.02)
			fence_mat.set_shader_parameter("alpha", 0.55 * smoothstep(0.0, 0.25, t) * (0.7 if fx.reduce_flashes else 1.0))
			var c := root.global_position
			if fx.quality >= 1 and fx._clock >= float(st["next"]):
				st["next"] = fx._clock + (0.35 if fx.reduce_flashes else 0.12)
				fx.bolt(c + _disc_point(cr) + Vector3.UP * 0.06, c + _disc_point(cr) + Vector3.UP * 0.06, BOLT, 0.1, 0.04, 0.12)
			_field_entries(c, cr, owner_i, st["in"]),
		"end": func() -> void:
			if is_instance_valid(gp):
				gp.emitting = false
			if not is_instance_valid(root):
				return
			fx.animate(root, 0.4, func(k: float, _t: float) -> void:
				mat.set_shader_parameter("fade", 1.0 - k)
				fence_mat.set_shader_parameter("alpha", 0.55 * (1.0 - k))
				fence_mat.set_shader_parameter("dissolve", k))}


## Zaps the fighters stepping into a field at `c` (radius r) this frame; `inside` remembers who
## was in. Its owner is immune (online, where entities carry no owner, Jitters is left out).
func _field_entries(c: Vector3, r: float, owner_i: int, inside: Dictionary) -> void:
	var n := int(fx.fighter_count.call()) if fx.fighter_count.is_valid() else 0
	for i in n:
		if i == owner_i or (owner_i < 0 and fx._cid(i) == creature):
			continue
		var inf := fx._info(i)
		var g := fx._ground(i)
		var now := not inf.is_empty() and not bool(inf.get("out", false)) and not bool(inf.get("hidden", false)) \
			and Vector2(g.x - c.x, g.z - c.z).length() <= r
		if now and not bool(inside.get(i, false)):
			_zap(i, g)
		inside[i] = now


## The field snapping at fighter i: a bolt from the floor under it up into its body.
func _zap(i: int, g: Vector3) -> void:
	var body := fx.anchor(i, "core")
	var a := fx._rng.randf() * TAU
	fx.bolt(Vector3(g.x, 0.05, g.z) + Vector3(sin(a), 0.0, cos(a)) * 0.35, body, BOLT, 0.16, 0.06, 0.14)
	fx.burst("sparks", body, Vector3.UP, SPARK, HOT, {"amount": 0.45, "speed": 0.9, "floor": g.y})
	fx.flash_light(body, SPARK, 1.8, 2.0, 0.12)


## ---- hits -----------------------------------------------------------------------------------------

func on_hit(fi: int, ev: Dictionary) -> void:
	var p: Vector3 = ev.get("point", Vector3.ZERO)
	var blocked := bool(ev.get("blocked", false)) or bool(ev.get("parried", false))
	var move := str(ev.get("move", ""))
	match str(ev.get("pool", "")):
		"thunder_jolt":
			_jolt_impact(p, blocked)
		"chain_lightning":
			if move == "chain_lightning_arc":
				_jump_to(fi, p)
			elif blocked:
				_earthed(p)
			else:
				_ball_impact(p, int(ev.get("target", -1)))
		"discharge":
			# the burst strikes with a visible arc from the coil; the ring's pulses only spark
			# (told apart by the effect id: an event's "tick" field is the simulation tick counter)
			if move == "discharge" and not blocked:
				fx.bolt(fx.anchor(fi, "core"), p, BOLT, 0.14, 0.05, 0.15)
			fx.burst("sparks", p, Vector3.UP, SPARK, HOT, {"amount": 0.5 if move == "discharge" else 0.25, "speed": 0.8})


## ---- entities and helpers -------------------------------------------------------------------------

func make_entity(e: Dictionary) -> Dictionary:
	match str(e.get("vfx", "")):
		V_JOLT:
			return _jolt_bolt(e)
		V_BALL:
			return _chain_ball(e)
		V_FIELD, V_CHAIN_FIELD:
			return _field(e)
	return {}


## One of this fighter's pool moves as its view's creature has it (drilled styles included).
func _pool_move(fi: int, pool: String) -> MoveDef:
	var v := fx._view(fi)
	if v == null or v.creature == null:
		return null
	var pm: PoolMove = v.creature.pool.get(pool)
	return pm.move if pm != null else null


## The first effect of a move with this area shape ({} when none).
static func _shaped(m: MoveDef, shape: String) -> Dictionary:
	if m == null:
		return {}
	for e in m.effects:
		var ed: Dictionary = e
		if str(ed.get("shape", "")) == shape:
			return ed
	return {}


## Metres in front of the fighter an effect's "at" puts it ("forward:<m>"; anything else: its feet).
static func _ahead(at: String) -> float:
	if at.begins_with("forward"):
		var parts := at.split(":")
		return float(parts[1]) if parts.size() > 1 else 1.2
	return 0.0


## A small unit sphere (radius 0.5) shared by every glow, head, core and flash this kit draws.
func _ball() -> SphereMesh:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 0.5
		_sphere.height = 1.0
		_sphere.radial_segments = 14
		_sphere.rings = 7
	return _sphere


## A light riding on an entity (Medium quality up; dimmed under Reduce flashing).
func _light(parent: Node3D, c: Color, energy: float, reach: float) -> void:
	if fx.quality < 1:
		return
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy * (0.6 if fx.reduce_flashes else 1.0)
	l.omni_range = reach
	l.shadow_enabled = false
	parent.add_child(l)


## Lets a (live) attached emitter's wake fade where it is, reparented off the entity being freed.
func _drop_stream(gp: GPUParticles3D) -> void:
	var at := gp.global_position
	gp.reparent(fx)
	gp.global_position = at
	fx.end_stream(gp)


func _rand_dir() -> Vector3:
	return Vector3(fx._rng.randf_range(-1.0, 1.0), fx._rng.randf_range(-0.5, 1.0), fx._rng.randf_range(-1.0, 1.0)).normalized()


func _disc_point(r: float) -> Vector3:
	var a := fx._rng.randf() * TAU
	var d := sqrt(fx._rng.randf()) * r * 0.95
	return Vector3(sin(a) * d, 0.0, cos(a) * d)
