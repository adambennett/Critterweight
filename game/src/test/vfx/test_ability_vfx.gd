extends TestCase
## v0.9.17 ability VFX (docs/art/VFX.md, src/view/fx/ability_vfx.gd): the simulation hands the
## effects the true footprint of every area, the effects draw exactly that footprint, every
## fighter's events and entities are drawn and cleaned up again, Effects quality and Reduce
## flashing are respected, and the extra event fields reach online clients.

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
	if t == "area" and str(ev["shape"]) in ["cone", "cone_back", "line"]:
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
	await wait_frames(int(6.0 * Engine.physics_ticks_per_second))
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
	await wait_frames(int(0.5 * Engine.physics_ticks_per_second))
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
	var w := NetWriter.new()
	NetEventCodec.encode_batch(w, [ev], 10)
	var r := NetReader.new(w.data())
	var out := NetEventCodec.decode_batch(r)
	check(r.ok and r.at_end(), "decoded cleanly")
	if not check_eq(out.size(), 1):
		return
	var d: Dictionary = out[0]
	for k in ["cone_deg", "length", "width", "inner", "radius", "yaw"]:
		check_near(float(d.get(k, -1.0)), float(ev[k]), 1e-4, "%s travels" % k)
	check(((d.get("origin", Vector3.INF)) as Vector3).distance_to(ev["origin"]) < 0.002, "origin travels")
	check_eq(str(d.get("shape", "")), "cone")
