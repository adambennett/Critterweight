extends TestCase
## v0.9.17 ability VFX (docs/art/VFX.md, src/view/fx/ability_vfx.gd): the simulation hands the
## effects the true footprint of every area, the effects draw exactly that footprint, every
## fighter's events and entities are drawn and cleaned up again, Effects quality and Reduce
## flashing are respected, and the extra event fields reach online clients. The second half pins
## the review fixes: which recipe an event draws (fighter looks stay with their fighters, only
## Static strikes call lightning), where (on the floor, along the line, at the zone's current
## size, along the real dash) and for how long (hovers, build-ups, charges, Bulldoze's stamping).

const ROSTER := ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters", "f_varga", "f_knell"]

var _info := {}          ## fighter -> info override for the director under test


func _fx(views: Array) -> AbilityVfx:
	var fx := AbilityVfx.new()
	fx.view_of = func(i: int): return views[i] if i >= 0 and i < views.size() else null
	fx.info_of = func(i: int) -> Dictionary:
		if i < 0 or i >= views.size():
			return {}
		var d := {"ground": Vector3(i * 2.0, 0, 0), "yaw": 0.0, "state": Fighter.State.NEUTRAL, "juiced": false,
			"hidden": false, "charge": -1.0, "out": false}
		d.merge(_info.get(i, {}), true)
		return d
	fx.fighter_count = func() -> int: return views.size()
	add_child(fx)
	return fx


## The floor footprints the director currently draws: [{node, mat}].
func _footprints(fx: AbilityVfx) -> Array:
	var out := []
	for n in fx.get_children():
		if n is MeshInstance3D and (n as MeshInstance3D).material_override is ShaderMaterial:
			var m := (n as MeshInstance3D).material_override as ShaderMaterial
			if m.shader == FxKit.shader("fx_area"):
				out.append({"node": n, "mat": m})
	return out


## An effect event exactly as EffectsSystem.fire builds it (src/sim/effects.gd).
static func effect_event(i: int, e: Dictionary, m: MoveDef) -> Dictionary:
	var t := str(e.get("type", ""))
	var ev := {"type": "effect", "fighter": i, "effect": t, "pos": Vector3(i * 2.0, 0, 1), "element": str(e.get("element", "")),
		"vfx": str(e.get("vfx", t)), "radius": float(e.get("radius", 0.0)), "shape": str(e.get("shape", "circle")), "yaw": 0.0,
		"move": m.id if m else ""}
	for k in ["cone_deg", "length", "width", "inner", "duration", "distance", "delay", "speed"]:
		if e.has(k):
			ev[k] = float(e[k])
	if t == "area" and str(ev["shape"]) in ["cone", "line"]:
		ev["origin"] = Vector3(i * 2.0, 0, 0)
	return ev


func test_effect_events_carry_the_true_footprint() -> void:
	# [fighter, slot, shape, numbers the event must carry]
	var cases := [["f_stoke", "ability1", "cone", {"cone_deg": 60.0, "radius": 2.0}],
		["f_gusto", "juice", "cone", {"cone_deg": 90.0, "radius": 3.0}],
		["f_dozer", "juice", "line", {"length": 6.0, "width": 2.0}],
		["f_slurry", "juice", "line", {"length": 4.0, "width": 1.6}],
		["f_dredge", "juice", "ring", {"radius": 5.0, "inner": 0.0}],
		["f_jitters", "juice", "circle", {"radius": 3.0}]]
	for c in cases:
		var sim := make_sim("", {"rounds": 1, "round_time": 0, "intro_time": 0.5},
			[{"creature": c[0], "team": 0}, {"creature": c[0], "team": 1}])
		await step_sim(sim, 0.6)
		var f := sim.fighters[0]
		var m: MoveDef = f.creature.abilities[c[1]]
		var n0 := sim.events.size()
		f._start_move(m, c[1], Fighter.State.ABILITY)
		await step_sim(sim, m.duration + 0.1)
		var found := {}
		for k in range(n0, sim.events.size()):
			var ev: Dictionary = sim.events[k]
			if str(ev["type"]) == "effect" and str(ev.get("effect", "")) == "area" and str(ev.get("move", "")) == m.id:
				found = ev
				break
		if not check(not found.is_empty(), "%s %s fired its area" % [c[0], c[1]]):
			continue
		check_eq(str(found["shape"]), str(c[2]), "%s %s shape" % [c[0], c[1]])
		var want: Dictionary = c[3]
		for k in want:
			check(found.has(k), "%s %s event carries %s" % [c[0], c[1], k])
			check_near(float(found.get(k, -1.0)), float(want[k]), 1e-4, "%s %s %s" % [c[0], c[1], k])
		if str(c[2]) in ["cone", "line"]:
			# cones and lines start at the fighter's feet (EffectsSystem.area), not at `pos`
			var o: Vector3 = found.get("origin", Vector3.INF)
			check(o.distance_to(f.ground_pos()) < 0.6, "%s %s origin at the feet (%s vs %s)" % [c[0], c[1], o, f.ground_pos()])


func test_footprints_draw_the_exact_area() -> void:
	var fx := _fx([])
	await wait_frames(30)       # the warm-up pieces are gone
	var cases := [
		{"shape": "cone", "radius": 2.0, "cone_deg": 60.0, "yaw": 0.7, "id": 1},
		{"shape": "line", "radius": 0.0, "length": 6.0, "width": 2.0, "yaw": -1.2, "id": 2},
		{"shape": "ring", "radius": 5.0, "inner": 1.5, "yaw": 0.0, "id": 3},
		{"shape": "circle", "radius": 1.6, "yaw": 0.0, "id": 0},
	]
	for c in cases:
		for f in _footprints(fx):
			(f["node"] as Node).free()
		var ev := {"type": "effect", "fighter": -1, "effect": "area", "pos": Vector3(1, 0, 2), "origin": Vector3(-1, 0, 3), "element": "grit",
			"vfx": "area", "radius": float(c["radius"]), "shape": str(c["shape"]), "yaw": float(c["yaw"]), "move": ""}
		for k in ["cone_deg", "length", "width", "inner"]:
			if c.has(k):
				ev[k] = float(c[k])
		fx.on_event(ev)
		var fps := _footprints(fx)
		if not check_eq(fps.size(), 1, "%s: one footprint" % c["shape"]):
			continue
		var m: ShaderMaterial = fps[0]["mat"]
		var node: MeshInstance3D = fps[0]["node"]
		check_eq(int(m.get_shader_parameter("shape")), int(c["id"]), "%s shape id" % c["shape"])
		check_near(float(m.get_shader_parameter("radius")), float(c["radius"]), 1e-5, "%s radius" % c["shape"])
		if c.has("cone_deg"):
			check_near(float(m.get_shader_parameter("half_angle")), deg_to_rad(float(c["cone_deg"])) * 0.5, 1e-5, "cone half angle")
		if c.has("length"):
			check_near(float(m.get_shader_parameter("length_m")), float(c["length"]), 1e-5, "line length")
			check_near(float(m.get_shader_parameter("width_m")), float(c["width"]), 1e-5, "line width")
		if c.has("inner"):
			check_near(float(m.get_shader_parameter("inner")), float(c["inner"]), 1e-5, "ring inner radius")
		# the quad covers the whole shape and sits where the simulation measured from
		var reach := maxf(float(c["radius"]), float(c.get("length", 0.0)))
		check(float(m.get_shader_parameter("size_m")) >= 2.0 * reach, "%s quad covers the area" % c["shape"])
		var at: Vector3 = Vector3(-1, 0, 3) if str(c["shape"]) in ["cone", "line"] else Vector3(1, 0, 2)
		check(Vector2(node.global_position.x - at.x, node.global_position.z - at.z).length() < 1e-4, "%s placed at its origin" % c["shape"])
		check_near(node.rotation.y, float(c["yaw"]), 1e-4, "%s faces the attacker's yaw" % c["shape"])
	fx.queue_free()


func test_every_fighter_event_and_entity_is_drawn_and_cleaned_up() -> void:
	var views := []
	for id in ROSTER:
		var v := CreatureView.new()
		add_child(v)
		v.setup(Content.creature(id))
		views.append(v)
	var fx := _fx(views)
	await wait_frames(30)
	var pooled_before := _pooled(fx)
	var projectile_specs := []
	for i in ROSTER.size():
		var c: CreatureDef = (views[i] as CreatureView).creature
		var moves := []
		for slot in c.abilities:
			moves.append([slot, c.abilities[slot]])
		for slot in ["heavy", "heavy_charged", "finisher"]:
			if c.moves.has(slot):
				moves.append([slot, c.moves[slot]])
		for sm in moves:
			var m: MoveDef = sm[1]
			fx.on_event({"type": "move_start", "fighter": i, "slot": sm[0], "id": m.id})
			for e in m.effects:
				fx.on_event(effect_event(i, e, m))
				if str(e.get("type", "")) == "projectile":
					projectile_specs.append([i, e])
				for oe in [e.get("on_expire", {})] + Array(e.get("on_land", [])) + Array(e.get("on_emerge", [])):
					if oe is Dictionary and not (oe as Dictionary).is_empty():
						fx.on_event(effect_event(i, oe, null))
		fx.on_event({"type": "juice", "fighter": i, "id": c.id + ".juice"})
		for el in Elements.defs:
			fx.on_event({"type": "hit", "fighter": i, "target": (i + 1) % ROSTER.size(), "damage": 9.0, "point": Vector3(i, 1, 0),
				"normal": Vector3(0, 0, 1), "blocked": false, "element": el, "counter": false})
			fx.on_event({"type": "status", "fighter": i, "status": "x", "element": el, "reacted": false})
		fx.on_event({"type": "submerge", "fighter": i, "pos": Vector3(i, 0, 0), "dest": Vector3(i, 0, 3)})
		fx.on_event({"type": "hover", "fighter": i})
		fx.on_event({"type": "land", "fighter": i, "pos": Vector3(i, 0, 0)})
		fx.on_event({"type": "counter", "fighter": i, "victim": (i + 1) % ROSTER.size()})
		fx.on_event({"type": "carry", "fighter": i, "victim": (i + 1) % ROSTER.size()})
		fx.on_event({"type": "wall_bonk", "fighter": i})
		fx.on_event({"type": "dodge", "fighter": i})
	for key in Elements.reactions:
		var r: Dictionary = Elements.reactions[key]
		fx.on_event({"type": "reaction", "fighter": 1, "reaction": str(r.get("id", "")), "name": str(r.get("name", "")),
			"a": str(r.get("a", "")), "b": str(r.get("b", "")), "pos": Vector3(0, 0.8, 0), "by": 0})
	fx.on_event({"type": "zone_reaction", "result": "steam", "pos": Vector3.ZERO, "a": "brine", "b": "scorch"})
	fx.on_event({"type": "arc", "from": Vector3.ZERO, "to": Vector3(2, 0, 0), "fighter": 5, "element": "static"})
	fx.on_event({"type": "spring", "fighter": 0, "pos": Vector3(3, 0, 3)})
	fx.on_event({"type": "projectile_destroyed", "pos": Vector3(1, 1, 1), "fighter": 0})
	fx.on_event({"type": "reflect", "fighter": 0, "pos": Vector3(1, 1, 1)})
	# a JUICE aura comes and goes with the fighter's JUICE state
	_info[3] = {"juiced": true}
	await wait_frames(3)
	check(fx._auras.has(3), "JUICE aura while juiced")
	_info[3] = {"juiced": false}
	await wait_frames(3)
	check(not fx._auras.has(3), "JUICE aura ends with JUICE")
	# entities: every projectile look, every zone kind, props, a delayed strike, and a hazard zone
	var ents := []
	var nid := 1
	for ps in projectile_specs:
		var e: Dictionary = ps[1]
		ents.append({"id": nid, "kind": "projectile", "owner": ps[0], "team": ps[0], "pos": Vector3(nid * 0.1, 1, 0), "vel": Vector3(0, 0, 5),
			"radius": float(e.get("radius", 0.25)), "element": str(e.get("element", "")), "vfx": str(e.get("vfx", "orb")), "e": e})
		nid += 1
	for kind in Elements.zones:
		var z: Dictionary = Elements.zones[kind]
		ents.append({"id": nid, "kind": "zone", "zone_kind": kind, "pos": Vector3(0, 0, nid * 0.1), "radius": float(z.get("radius", 1.5)),
			"element": str(z.get("element", "")), "vfx": str(z.get("vfx", kind)), "e": z})
		nid += 1
	for vfx in ["brine_flood", "dust_bowl"]:
		ents.append({"id": nid, "kind": "zone", "zone_kind": "", "pos": Vector3.ZERO, "radius": 2.5, "element": "brine" if vfx == "brine_flood" else "grit", "vfx": vfx, "e": {}})
		nid += 1
	ents.append({"id": nid, "kind": "prop", "prop": "spring_pad", "pos": Vector3(3, 0, 3), "radius": 1.2, "element": "", "vfx": "spring_pad", "e": {}})
	ents.append({"id": nid + 1, "kind": "prop", "prop": "boulder", "pos": Vector3(-3, 0, 3), "radius": 0.8, "element": "", "vfx": "boulder", "e": {}})
	ents.append({"id": nid + 2, "kind": "delayed", "pos": Vector3(0, 0, -2), "radius": 1.5, "element": "static", "vfx": "marker", "e": {}})
	ents.append({"id": nid + 3, "kind": "zone", "zone_kind": "hazard", "pos": Vector3.ZERO, "radius": 2.0, "element": "", "vfx": "zone", "e": {"hazard": "lava"}})
	fx.sync_entities(ents)
	check_eq(fx._ents.size(), ents.size() - 1, "every entity but the arena hazard has a visual")
	check(not fx._ents.has(nid + 3), "hazard zones are left to the arena")
	for k in 5:
		for e in ents:
			e["pos"] = (e["pos"] as Vector3) + Vector3(0, 0, 0.05)
		fx.sync_entities(ents)
		await wait_frames(1)
	check(fx.get_child_count() > pooled_before + 20, "effects were built (%d nodes)" % fx.get_child_count())
	fx.sync_entities([])
	check_eq(fx._ents.size(), 0, "entities retired")
	# 6 s of effects time: everything transient dissipates and frees itself
	await _wait_s(6.0)
	var left := []
	for n in fx.get_children():
		if n is GPUParticles3D and (n as GPUParticles3D).one_shot:
			continue        # the pool (one-shot emitters are reused)
		left.append("%s:%s" % [n.get_class(), n.name])
	check(left.is_empty(), "nothing transient left behind: %s" % str(left.slice(0, 12)))
	check(fx._follows.is_empty(), "no followers left (%d)" % fx._follows.size())
	check(fx._anims.is_empty(), "no animations left (%d)" % fx._anims.size())
	for n in fx.get_children():
		if n is GPUParticles3D:
			check(not (n as GPUParticles3D).emitting, "pooled emitters finished")
			break
	fx.queue_free()
	for v in views:
		(v as Node).queue_free()


func _pooled(fx: AbilityVfx) -> int:
	var n := 0
	for c in fx.get_children():
		if c is GPUParticles3D:
			n += 1
	return n


func test_quality_and_reduced_flashing() -> void:
	var fx := _fx([])
	await wait_frames(30)
	fx.configure(0, false)
	check_near(fx._ratio(), 0.35, 1e-5, "Low effects thin the particles")
	fx.flash_light(Vector3.ZERO, Color.WHITE, 3.0, 3.0, 0.3)
	check_eq(_lights(fx).size(), 0, "no light flashes on Low")
	fx.configure(2, false)
	check_near(fx._ratio(), 1.0, 1e-5, "High effects: full particles")
	fx.flash_light(Vector3.ZERO, Color.WHITE, 3.0, 3.0, 0.3)
	var l := _lights(fx)
	if check_eq(l.size(), 1, "light flash on High"):
		check_near((l[0] as OmniLight3D).light_energy, 3.0, 0.01, "full flash")
	await _wait_s(0.5)
	fx.configure(2, true)
	fx.flash_light(Vector3.ZERO, Color.WHITE, 3.0, 3.0, 0.3)
	l = _lights(fx)
	if check_eq(l.size(), 1, "one flash"):
		check(float((l[0] as OmniLight3D).light_energy) <= 1.1, "Reduce flashing dims the flash (%.2f)" % (l[0] as OmniLight3D).light_energy)
	var fp := fx.footprint("static", "circle", Vector3.ZERO, 0.0, 1.0, {"front": 0.8}, 0.5)
	check_near(float((fp.material_override as ShaderMaterial).get_shader_parameter("front")), 0.4, 1e-4, "Reduce flashing halves the travelling front")
	# crowded fights thin the volumes further
	var many := []
	many.resize(8)
	var crowd := _fx(many)
	crowd.configure(2, false)
	check(crowd._ratio() < 1.0, "8 fighters: thinner effects")
	fx.queue_free()
	crowd.queue_free()


func _lights(fx: AbilityVfx) -> Array:
	return fx.get_children().filter(func(n): return n is OmniLight3D)


func test_footprint_fields_reach_online_clients() -> void:
	var ev := {"type": "effect", "tick": 10, "fighter": 0, "effect": "area", "pos": Vector3(1, 0, 2), "element": "scorch",
		"vfx": "steam_vent", "radius": 2.0, "shape": "cone", "yaw": 0.5, "move": "f_stoke.ability1", "cone_deg": 60.0,
		"length": 3.5, "width": 1.0, "inner": 0.5, "origin": Vector3(1, 0, 2)}
	# the other view-only keys: a dash's real direction, a hover's real length
	var dash := {"type": "effect", "tick": 11, "fighter": 0, "effect": "dash", "pos": Vector3.ZERO, "element": "", "vfx": "dash",
		"radius": 0.0, "shape": "circle", "yaw": 0.0, "move": "f_varga.ability1", "speed": 9.0, "dir": Vector3(0.6, 0, 0.8)}
	var hover := {"type": "hover", "tick": 12, "fighter": 1, "duration": 0.6}
	var w := NetWriter.new()
	NetEventCodec.encode_batch(w, [ev, dash, hover], 10)
	var r := NetReader.new(w.data())
	var out := NetEventCodec.decode_batch(r)
	check(r.ok and r.at_end(), "decoded cleanly")
	if not check_eq(out.size(), 3):
		return
	var d: Dictionary = out[0]
	for k in ["cone_deg", "length", "width", "inner", "radius", "yaw"]:
		check_near(float(d.get(k, -1.0)), float(ev[k]), 1e-4, "%s travels" % k)
	check(((d.get("origin", Vector3.INF)) as Vector3).distance_to(ev["origin"]) < 0.002, "origin travels")
	check_eq(str(d.get("shape", "")), "cone")
	var dd: Dictionary = out[1]
	check(dd.get("dir") is Vector3 and (dd["dir"] as Vector3).distance_to(dash["dir"]) < 0.002, "a dash's direction travels")
	check_near(float((out[2] as Dictionary).get("duration", -1.0)), 0.6, 1e-4, "a hover's length travels")


# =====================================================================================
# Review fixes: which recipe an event draws, where, and for how long
# =====================================================================================

func _views(ids: Array) -> Array:
	var out := []
	for id in ids:
		var v := CreatureView.new()
		add_child(v)
		v.setup(Content.creature(str(id)))
		out.append(v)
	return out


func _free(fx: AbilityVfx, views: Array) -> void:
	fx.queue_free()
	for v in views:
		(v as Node).queue_free()


func _wait_s(seconds: float) -> void:
	# AbilityVfx advances in _process(delta), not physics ticks. Counting process frames as
	# 120 Hz doubled these waits in a 60 Hz packaged window and expired a valid build-up.
	# A process timer uses the same engine delta as the effects, including fixed-fps test runs.
	await get_tree().create_timer(seconds, false, false).timeout


## Frees every drawn piece (pooled emitters stay) so a check sees only what the next event draws.
func _clear(fx: AbilityVfx) -> void:
	for n in fx.get_children():
		if not (n is GPUParticles3D):
			n.free()
	fx._lights = 0


## Lightning and other ribbons currently drawn.
func _ribbons(fx: AbilityVfx) -> Array:
	return fx.get_children().filter(func(n): return n is MeshInstance3D and (n as MeshInstance3D).mesh is ImmediateMesh)


## Ring walls (shockwaves, pulses, splash crowns) currently drawn.
func _walls(fx: AbilityVfx) -> Array:
	var wall := FxKit.wall_mesh(48, 1.0)
	return fx.get_children().filter(func(n): return n is MeshInstance3D and (n as MeshInstance3D).mesh == wall)


## Footprints of one shape id (fx_area `shape`) or in one element's floor pattern.
func _shaped(fx: AbilityVfx, shape_id: int) -> Array:
	return _footprints(fx).filter(func(f): return int((f["mat"] as ShaderMaterial).get_shader_parameter("shape")) == shape_id)


func _styled(fx: AbilityVfx, el: String) -> Array:
	var style := int(FxKit.AREA_STYLE.get(el, 0))
	return _footprints(fx).filter(func(f): return int((f["mat"] as ShaderMaterial).get_shader_parameter("style")) == style)


func _ids(nodes: Array) -> Array:
	return nodes.map(func(n): return ((n["node"] if n is Dictionary else n) as Node).get_instance_id())


## Followers of a fighter carrying a tag ("prep", "hover", "bulldoze", "stance", "charge").
func _tagged(fx: AbilityVfx, fi: int, tag: String) -> int:
	var n := 0
	for f in fx._follows:
		if int(f["fi"]) == fi and str(f.get("tag", "")) == tag:
			n += 1
	return n


## Emitting particle bursts thrown from a box.
func _boxed(fx: AbilityVfx) -> Array:
	var out := []
	for n in fx.get_children():
		if n is GPUParticles3D and (n as GPUParticles3D).emitting:
			var box = ((n as GPUParticles3D).process_material as ShaderMaterial).get_shader_parameter("emit_box")
			if box is Vector3 and box != Vector3.ZERO:
				out.append(n)
	return out


func test_only_static_strikes_call_lightning() -> void:
	var fx := _fx([])
	await wait_frames(30)
	# Gusto's l2 (gale) and Slurry's l3 (sludge) follow-ups and a thrown Scrapling (no element) land in
	# their own true circle; only a Static strike (Stormfront, storm zones) is a bolt from the sky
	for c in [["gale", 0.45], ["sludge", 1.0], ["", 1.0], ["static", 1.5]]:
		_clear(fx)
		var el: String = c[0]
		var lightning := el == "static"
		fx.on_event({"type": "effect", "fighter": -1, "effect": "strike", "pos": Vector3(1, 0, 2), "element": el, "vfx": "bolt",
			"radius": float(c[1]), "shape": "circle", "yaw": 0.0, "move": ""})
		check_eq(_ribbons(fx).size() > 0, lightning, "'%s' strike: lightning only for Static" % el)
		check_eq(_lights(fx).size(), 1 if lightning else 0, "'%s' strike: a flash only with the bolt" % el)
		var fps := _footprints(fx)
		if check_eq(fps.size(), 1, "'%s' strike: its circle" % el):
			check_near(float((fps[0]["mat"] as ShaderMaterial).get_shader_parameter("radius")), float(c[1]), 1e-5, "'%s' strike: its true radius" % el)
	# the Scrapling Pelter's throw merely looks like a bolt: no lightning comes down on the thrower
	_clear(fx)
	fx.on_event({"type": "effect", "fighter": -1, "effect": "projectile", "pos": Vector3.ZERO, "element": "", "vfx": "bolt",
		"radius": 0.18, "shape": "circle", "yaw": 0.0, "move": ""})
	check_eq(_ribbons(fx).size(), 0, "a bolt-looking projectile calls no lightning")
	check_eq(_footprints(fx).size(), 0, "nor a strike circle")
	fx.queue_free()


func test_fighter_looks_stay_with_their_fighters() -> void:
	var views := _views(["f_jitters", "f_dozer", "f_dredge"])
	var fx := _fx(views)
	await wait_frames(30)
	# Jitters' Pinball is a charge, and anyone may take a counter stance: neither is Dozer's or Dredge's
	var pinball: MoveDef = (views[0] as CreatureView).creature.moves["dash_attack"]
	var ce := AbilityVfx.effect_of(pinball, "charge")
	check(not ce.is_empty(), "Pinball is a charge")
	fx.on_event(effect_event(0, ce, pinball))
	fx.on_event(effect_event(0, {"type": "counter_stance", "duration": 1.2}, null))
	check_eq(_tagged(fx, 0, "bulldoze"), 0, "no Bulldoze plume on Jitters")
	check_eq(_styled(fx, "grit").size(), 0, "no torn-up floor under Jitters")
	check_eq(_tagged(fx, 0, "stance"), 0, "no Anchor Drop whirlpool on Jitters")
	check_eq(_styled(fx, "brine").size(), 0, "no brine floor under Jitters")
	var anchor_drop: MoveDef = (views[2] as CreatureView).creature.abilities["ability2"]
	fx.on_event(effect_event(2, AbilityVfx.effect_of(anchor_drop, "counter_stance"), anchor_drop))
	check(_tagged(fx, 2, "stance") > 0, "Dredge keeps his whirlpool")
	# Bulldoze tears the floor up only while Dozer really charges
	var bulldoze: MoveDef = (views[1] as CreatureView).creature.abilities["ability1"]
	_info[1] = {"state": Fighter.State.ABILITY, "ground": Vector3.ZERO}
	fx.on_event(effect_event(1, AbilityVfx.effect_of(bulldoze, "charge"), bulldoze))
	check(_tagged(fx, 1, "bulldoze") > 0, "Dozer's plume")
	for k in 24:
		_info[1]["ground"] = Vector3(0, 0, 0.06 * k)        # about 7 m/s
		await wait_frames(1)
	var stamps := _ids(_styled(fx, "grit"))
	check(stamps.size() >= 2, "the floor is torn up along the charge (%d)" % stamps.size())
	# stopped (the charge ran into its recovery): nothing piles up under him
	await _wait_s(0.25)
	check(_ids(_styled(fx, "grit")).all(func(id): return stamps.has(id)), "no stamps pile up under a stopped Dozer")
	# knocked out of the move (flinch, stun, KO): the plume and the stamping stop, even if he slides on
	_info[1]["state"] = Fighter.State.HITSTUN
	await wait_frames(3)
	check_eq(_tagged(fx, 1, "bulldoze"), 0, "the plume lets go when the charge is cut off")
	var before := _ids(_styled(fx, "grit"))
	for k in 24:
		_info[1]["ground"] = Vector3(0, 0, 1.5 + 0.06 * k)
		await wait_frames(1)
	check(_ids(_styled(fx, "grit")).all(func(id): return before.has(id)), "no stamping after the charge was cut off")
	_free(fx, views)


func test_airbursts_draw_their_area_on_the_floor() -> void:
	var fx := _fx([])
	await wait_frames(30)
	# Gust Bomb and Arc Lash expiring mid-flight, any other on_expire area, a puddle lobbed down: the
	# simulation's areas are horizontal circles, so the footprint and the rings lie on the floor
	var air := Vector3(1.0, 1.3, 2.0)
	for c in [["area", "gust_burst", "gale"], ["area", "pulse", "static"], ["area", "burst", "scorch"], ["zone", "brine_puddle", "brine"]]:
		_clear(fx)
		fx.on_event({"type": "effect", "fighter": -1, "effect": c[0], "pos": air, "element": c[2], "vfx": c[1], "radius": 1.5,
			"shape": "circle", "yaw": 0.0, "move": ""})
		if str(c[0]) == "area":
			check_eq(_footprints(fx).size(), 1, "%s: its footprint" % c[1])
		for f in _footprints(fx):
			var p: Vector3 = (f["node"] as Node3D).global_position
			check(p.y < 0.1 and Vector2(p.x - air.x, p.z - air.z).length() < 1e-4, "%s: footprint on the floor under the burst (%s)" % [c[1], p])
		for wall in _walls(fx):
			var q: Vector3 = (wall as Node3D).global_position
			check(q.y < 0.1, "%s: ring on the floor (%s)" % [c[1], q])
	fx.queue_free()


func test_box_bursts_run_along_their_line() -> void:
	var fx := _fx([])
	await wait_frames(30)
	var yaw := 0.9
	# Overflow (and Brine Wave, Landslide) throw gobs and bubbles from boxes laid along the line
	fx.on_event({"type": "effect", "fighter": -1, "effect": "area", "pos": Vector3.ZERO, "origin": Vector3.ZERO, "element": "sludge",
		"vfx": "wave", "radius": 0.0, "shape": "line", "yaw": yaw, "length": 4.0, "width": 1.6, "move": ""})
	var boxed := _boxed(fx)
	check_eq(boxed.size(), 2, "gobs and bubbles from boxes")
	for gp: GPUParticles3D in boxed:
		check(gp.global_basis.z.distance_to(MathX.forward_of_yaw(yaw)) < 1e-3, "the box runs along the line (%s)" % gp.global_basis.z)
	# a pooled emitter must not keep a yaw for its next burst
	var pool: Array = fx._pool["gobs"]
	for gp: GPUParticles3D in pool:
		gp.emitting = false
	fx.burst("gobs", Vector3(0, 1, 0), Vector3.UP, Color.WHITE, null, {"box": Vector3(1, 0.1, 2), "yaw": yaw})
	var first: GPUParticles3D = pool[0]
	check(first.emitting and not first.global_basis.is_equal_approx(Basis.IDENTITY), "turned for a burst along a line")
	for gp: GPUParticles3D in pool:
		gp.emitting = false
	fx.burst("gobs", Vector3(0, 1, 0), Vector3.UP, Color.WHITE, null, {"box": Vector3(1, 0.1, 2)})
	check(first.emitting and first.global_basis.is_equal_approx(Basis.IDENTITY), "the reused emitter is square to the world again")
	fx.queue_free()


func test_zone_decals_follow_the_zone_radius() -> void:
	var fx := _fx([])
	await wait_frames(30)
	var ents := [{"id": 1, "kind": "zone", "zone_kind": "sludge_puddle", "pos": Vector3(1, 0, 1), "radius": 1.5, "element": "sludge",
			"vfx": "sludge_puddle", "e": {}},
		{"id": 2, "kind": "zone", "zone_kind": "", "pos": Vector3(-2, 0, 0), "radius": 2.0, "element": "grit", "vfx": "dust_bowl", "e": {}}]
	fx.sync_entities(ents)
	await wait_frames(2)
	# zone reactions resize zones in the simulation (grow x1.5, smear x0.8); snapshots carry the radius
	ents[0]["radius"] = 2.25
	ents[1]["radius"] = 1.6
	fx.sync_entities(ents)
	for e in ents:
		var root: Node3D = fx._ents[int(e["id"])]["node"]
		var want := float(e["radius"])
		var decals := 0
		for n in root.get_children():
			if not (n is MeshInstance3D and (n as MeshInstance3D).material_override is ShaderMaterial):
				continue
			var mi := n as MeshInstance3D
			var m := mi.material_override as ShaderMaterial
			if m.shader == FxKit.shader("fx_area"):
				decals += 1
				check_near(float(m.get_shader_parameter("radius")), want, 1e-4, "%s: decal at the new radius" % e["vfx"])
				check(float(m.get_shader_parameter("size_m")) >= 2.0 * want, "%s: the decal's quad covers it" % e["vfx"])
				check(mi.custom_aabb.size.x >= 2.0 * want, "%s: so does its culling box" % e["vfx"])
			elif str(e["vfx"]) == "dust_bowl":
				check_near(mi.scale.x, want, 1e-4, "the Dust Bowl wall turns at the new radius")
		check_eq(decals, 1, "%s: one decal" % e["vfx"])
	fx.sync_entities([])
	fx.queue_free()


func test_downdraft_lasts_as_long_as_the_hover() -> void:
	# the simulation's hover event carries the hover's real length (view only); a dive's hover
	# effect (duration 0) ends the hover
	var sim := make_sim("", {"rounds": 1, "round_time": 0, "intro_time": 0.5},
		[{"creature": "f_gusto", "team": 0}, {"creature": "f_gusto", "team": 1}])
	await step_sim(sim, 0.6)
	var f := sim.fighters[0]
	f.mods["hover_duration"] = 0.5
	f.start_hover(2.0, 1.2, 3.0)
	var hev: Dictionary = sim.events.back()
	check_eq(str(hev["type"]), "hover")
	check_near(float(hev.get("duration", -1.0)), 0.6, 1e-6, "Hang Time's event carries its real length")
	f.start_hover(0.0, 0.0, 0.0)
	var dive: Dictionary = sim.events.back()
	check_near(float(dive.get("duration", -1.0)), 0.0, 1e-6, "a dive's hover event ends the hover")
	check(not f.has_flag("hovering"), "and the simulation agrees")
	var views := _views(["f_gusto"])
	var fx := _fx(views)
	await wait_frames(30)
	fx.on_event({"type": "hover", "fighter": 0, "duration": 0.0})
	check(not fx._hovers.has(0) and _tagged(fx, 0, "hover") == 0, "a dive draws no downdraft")
	fx.on_event({"type": "hover", "fighter": 0, "duration": 1.2})
	check(fx._hovers.has(0) and _tagged(fx, 0, "hover") > 0, "Hang Time's downdraft")
	await _wait_s(0.3)
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "l1@hovering", "id": "f_gusto.l1@hovering"})
	check(fx._hovers.has(0), "a hover variant keeps the hover")
	# the dive's own hover event ends it: the wind stream stops and no more rings pulse
	fx.on_event({"type": "hover", "fighter": 0, "duration": 0.0})
	var pulses := _ids(_walls(fx))
	await wait_frames(3)
	check_eq(_tagged(fx, 0, "hover"), 0, "the downdraft stream stops with the hover")
	await _wait_s(0.5)
	check(_ids(_walls(fx)).all(func(id): return pulses.has(id)), "no downdraft pulses after the dive")
	# any other move ends a hover too (Fighter._start_move), and so does a knockdown
	fx.on_event({"type": "hover", "fighter": 0, "duration": 1.2})
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "ability1", "id": "f_gusto.ability1"})
	check(not fx._hovers.has(0), "another move ends the downdraft")
	fx.on_event({"type": "hover", "fighter": 0, "duration": 1.2})
	fx.on_event({"type": "knockdown", "fighter": 0, "reason": "hit", "by": -1})
	check(not fx._hovers.has(0), "a knockdown ends the downdraft")
	_free(fx, views)


func test_cut_the_angle_draws_the_real_dash() -> void:
	var sim := make_sim("", {"rounds": 1, "round_time": 0, "intro_time": 0.5},
		[{"creature": "f_varga", "team": 0}, {"creature": "f_varga", "team": 1}])
	await step_sim(sim, 0.6)
	var f := sim.fighters[0]
	f.facing_yaw = 0.0
	f.input.move = Vector3(1, 0, 0)          # the stick points to his side; he keeps facing his man
	sim.effects.fire(f, {"type": "dash", "dir": "stick", "speed": 9.0, "time": 0.18})
	var ev: Dictionary = sim.events.back()
	check_eq(str(ev.get("effect", "")), "dash")
	check(ev.get("dir") is Vector3 and (ev["dir"] as Vector3).distance_to(Vector3(1, 0, 0)) < 1e-4, "the event carries the dash's own direction (%s)" % str(ev.get("dir")))
	check_near(float(ev["yaw"]), 0.0, 1e-6, "while his facing stays put")
	sim.effects.fire(f, {"type": "dash", "speed": -3.4})
	var hop: Dictionary = sim.events.back()
	check(hop.get("dir") is Vector3 and (hop["dir"] as Vector3).distance_to(-f.forward()) < 1e-4, "a hop back goes backwards")
	var views := _views(["f_varga"])
	var fx := _fx(views)
	await wait_frames(30)
	var cut: MoveDef = (views[0] as CreatureView).creature.abilities["ability1"]
	fx.on_event({"type": "effect", "fighter": 0, "effect": "dash", "pos": Vector3.ZERO, "element": "", "vfx": "dash", "radius": 0.0,
		"shape": "circle", "yaw": 0.0, "move": cut.id, "speed": 9.0, "dir": Vector3(1, 0, 0)})
	var lines := _shaped(fx, 2)
	if check_eq(lines.size(), 1, "Cut the Angle's skid line"):
		check_near((lines[0]["node"] as Node3D).rotation.y, PI * 0.5, 1e-4, "drawn along the dash, not his facing")
	_free(fx, views)


func test_reduce_flashing_slows_the_static_floor_flicker() -> void:
	var fx := _fx([])
	await wait_frames(30)
	fx.configure(2, false)
	var a := fx.footprint("static", "circle", Vector3.ZERO, 0.0, 1.0, {}, 0.3)
	check_near(float((a.material_override as ShaderMaterial).get_shader_parameter("flicker_hz")), 12.0, 1e-4, "static forks re-fork at 12 Hz")
	fx.configure(2, true)
	var b := fx.footprint("static", "circle", Vector3.ZERO, 0.0, 1.0, {}, 0.3)
	check(float((b.material_override as ShaderMaterial).get_shader_parameter("flicker_hz")) <= 3.0, "Reduce flashing: 3 Hz at most")
	# lingering static fields too (zone decals)
	fx.sync_entities([{"id": 1, "kind": "zone", "zone_kind": "static_field", "pos": Vector3.ZERO, "radius": 1.5, "element": "static",
		"vfx": "static_field", "e": {}}])
	var root: Node3D = fx._ents[1]["node"]
	for n in root.get_children():
		if n is MeshInstance3D and (n as MeshInstance3D).material_override is ShaderMaterial:
			var m := (n as MeshInstance3D).material_override as ShaderMaterial
			if m.shader == FxKit.shader("fx_area"):
				check(float(m.get_shader_parameter("flicker_hz")) <= 3.0, "a static field's floor flickers slowly too")
	fx.sync_entities([])
	fx.queue_free()


func test_area_warnings_track_the_fighter_until_contact() -> void:
	var views := _views(["f_dozer"])
	var fx := _fx(views)
	await wait_frames(30)
	var landslide: MoveDef = (views[0] as CreatureView).creature.abilities["juice"]
	_info[0] = {"ground": Vector3.ZERO, "yaw": 0.0, "state": Fighter.State.ABILITY}
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "juice", "id": landslide.id})
	var lines := _shaped(fx, 2)
	if not check_eq(lines.size(), 1, "Landslide's line warning"):
		_free(fx, views)
		return
	var warn: MeshInstance3D = lines[0]["node"]
	# he keeps walking and turning through the windup: the warning stays on his feet and facing
	_info[0]["ground"] = Vector3(1.0, 0, 0.5)
	_info[0]["yaw"] = 0.8
	await wait_frames(3)
	check(Vector2(warn.global_position.x - 1.0, warn.global_position.z - 0.5).length() < 1e-4, "the warning walks with him (%s)" % warn.global_position)
	check_near(warn.rotation.y, 0.8, 1e-4, "and turns with him")
	# contact: the move's first effect ends the build-up; the warning stays where the line fired and fades
	var ev := effect_event(0, AbilityVfx.effect_of(landslide, "area"), landslide)
	ev["origin"] = Vector3(1.0, 0, 0.5)
	ev["yaw"] = 0.8
	fx.on_event(ev)
	check(not fx._preps.has(0), "contact ends the build-up")
	await wait_frames(2)
	_info[0]["yaw"] = -0.5
	await wait_frames(2)
	if is_instance_valid(warn):
		check_near(warn.rotation.y, 0.8, 1e-4, "after contact the warning no longer turns")
	await _wait_s(0.4)
	check(not is_instance_valid(warn), "the warning is gone once the real footprint took over")
	_free(fx, views)


func test_build_ups_last_until_the_first_effect() -> void:
	var views := _views(["f_stoke"])
	var fx := _fx(views)
	await wait_frames(30)
	var vent: MoveDef = (views[0] as CreatureView).creature.abilities["ability1"]
	var lead := AbilityVfx.first_effect_t(vent)
	_info[0] = {"state": Fighter.State.ABILITY}
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "ability1", "id": vent.id})
	check(fx._preps.has(0) and _tagged(fx, 0, "prep") > 0, "Steam Vent builds up")
	# a slow windup (low stamina runs it at 0.77x): still building past the definition's time
	await _wait_s(lead * 1.25)
	check(fx._preps.has(0) and _tagged(fx, 0, "prep") > 0, "the build-up holds until the vent fires")
	fx.on_event(effect_event(0, AbilityVfx.effect_of(vent, "area"), vent))
	check(not fx._preps.has(0), "the vent firing ends the build-up")
	await wait_frames(2)
	check_eq(_tagged(fx, 0, "prep"), 0, "its stacks and glow let go")
	# a windup cut off by a hit (the fighter leaves ABILITY) ends it without an effect
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "ability1", "id": vent.id})
	await wait_frames(2)
	_info[0]["state"] = Fighter.State.HITSTUN
	await wait_frames(2)
	check(not fx._preps.has(0), "a cut-off windup ends its build-up")
	# and a build-up whose effect never arrives stops at its cap
	_info[0]["state"] = Fighter.State.NEUTRAL
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "ability1", "id": vent.id})
	await _wait_s(lead * AbilityVfx.PREP_CAP + 0.05)
	check(not fx._preps.has(0), "the cap ends a build-up whose effect never came")
	await _wait_s(0.5)
	check_eq(_tagged(fx, 0, "prep"), 0, "nothing of it is left")
	_free(fx, views)


func test_build_up_glows_share_the_light_cap() -> void:
	var views := _views(["f_stoke"])
	var fx := _fx(views)
	await wait_frames(30)
	fx.configure(1, false)                 # Medium: at most 3 lights
	for k in 3:
		fx.flash_light(Vector3(k, 1, 0), Color.WHITE, 2.0, 2.0, 0.5)
	var vent: MoveDef = (views[0] as CreatureView).creature.abilities["ability1"]
	_info[0] = {"state": Fighter.State.ABILITY}
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "ability1", "id": vent.id})
	check_eq(_lights(fx).size(), 3, "the boiler glow adds no light past the cap")
	check_eq(fx._lights, 3, "light budget")
	await _wait_s(0.7)                    # the flashes are over and so is that build-up (its cap)
	check_eq(fx._lights, 0, "every slot given back")
	# with room, the glow's light takes a slot while it lives and gives it back when the build-up ends
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "ability1", "id": vent.id})
	check_eq(fx._lights, 1, "the glow's light is counted")
	check_eq(_lights(fx).size(), 1, "one light")
	await wait_frames(2)
	_info[0]["state"] = Fighter.State.HITSTUN
	await _wait_s(0.3)
	check_eq(fx._lights, 0, "its slot is given back")
	check_eq(_lights(fx).size(), 0, "and the light is gone")
	_free(fx, views)


func test_heavy_charge_glow_only_while_charging() -> void:
	var views := _views(["f_gusto"])
	var fx := _fx(views)
	await wait_frames(30)
	var c: CreatureDef = (views[0] as CreatureView).creature
	var heavy: MoveDef = c.moves["heavy"]
	if not check(heavy.charge_time > 0.0 and c.moves.has("heavy_charged"), "Gusto's heavy charges into Downdraft"):
		_free(fx, views)
		return
	var start := heavy.first_active() * 0.7
	# online a tapped heavy is not charging (-1, NetMatchScene.fx_charge): no glow
	_info[0] = {"state": Fighter.State.ATTACK, "charge": -1.0}
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "heavy", "id": heavy.id})
	await _wait_s(start + 0.3)
	check(not fx._charges.has(0) and _tagged(fx, 0, "charge") == 0, "a tapped heavy shows no charge glow")
	# a held one (-2: charging, level unknown) glows by time
	_info[0]["charge"] = -2.0
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "heavy", "id": heavy.id})
	await _wait_s(start + 0.3)
	check(fx._charges.has(0) and fx._charges[0]["node"] != null, "a held heavy glows")
	# let go into the charged heavy: the flag can drop a moment before its move_start arrives
	_info[0]["charge"] = -1.0
	await wait_frames(2)
	check(fx._charges.has(0), "the glow waits for the charged heavy's move_start")
	var lights := _lights(fx).size()
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "heavy_charged", "id": (c.moves["heavy_charged"] as MoveDef).id})
	check(not fx._charges.has(0), "released")
	check_eq(_lights(fx).size(), lights + 1, "with its release flash")
	_free(fx, views)


func test_cone_back_is_drawn_from_its_point() -> void:
	# EffectsSystem.area measures a cone_back from the effect's point, not the feet: no origin is sent
	var sim := make_sim("", {"rounds": 1, "round_time": 0, "intro_time": 0.5},
		[{"creature": "f_stoke", "team": 0}, {"creature": "f_stoke", "team": 1}])
	await step_sim(sim, 0.6)
	var f := sim.fighters[0]
	for shape in ["cone", "cone_back", "line"]:
		sim.effects.fire(f, {"type": "area", "shape": shape, "radius": 1.0, "cone_deg": 60.0, "length": 1.0, "width": 0.5,
			"at": "forward:1.0", "damage": 0.0, "stun": 0.0, "poise": 0.0})
		var ev: Dictionary = sim.events.back()
		check_eq(str(ev.get("shape", "")), shape)
		check_eq(ev.has("origin"), shape != "cone_back", "%s: origin at the feet only for cones and lines" % shape)
	var fx := _fx([])
	await wait_frames(30)
	fx.on_event({"type": "effect", "fighter": -1, "effect": "area", "pos": Vector3(1, 0, 2), "element": "grit", "vfx": "area",
		"radius": 2.0, "shape": "cone_back", "cone_deg": 90.0, "yaw": 0.4, "move": ""})
	var fps := _shaped(fx, 4)
	if check_eq(fps.size(), 1, "the cone behind"):
		var p: Vector3 = (fps[0]["node"] as Node3D).global_position
		check(Vector2(p.x - 1.0, p.z - 2.0).length() < 1e-4, "drawn from its point (%s)" % p)
	fx.queue_free()
