class_name HubMode
extends MatchMode
## The Cannery's simulation rules (docs/design/HUB.md §6, docs/HUB_SYSTEMS.md §3). A MatchMode
## with no rounds, no timer, no damage and no knockdowns: the player's real fighter walks the hub
## with the fight controls. The mode owns:
##   * interactions: the focused interactable per fighter (2 m volumes, closest/facing wins) and
##     the A press — a buffered DODGE press near an interactable is consumed here
##     (intercept_actions) so the fighter does not also dodge; keyboard "interact" arrives through
##     request_interact() from HubPlayerInput
##   * carrying/throwing props with Grab (crates, the elevator parts, the sign's letter, the lid):
##     Grab/Light tosses, Heavy (hold) heaves with a charge
##   * the hittables: the three bags (scored by HubBagChallenge), the boiler and the NPCs
##   * the activities (bag challenge, chum drill, crate toss) and the ten secrets (HubSecrets)
##   * spaces (discovery, the current room), transitions (hatch/ladders/elevator) and Ludlow's rounds
## UI and presentation react to "hub_*" events (emit_hub); the mode never opens screens itself.

const INTERACT_COOLDOWN := 0.35
const TRANSITION_TIME := 0.32        ## fade-out before the teleport (HubScene fades back in)
const PICKUP_RANGE := 1.35
const NPC_HIT_COOLDOWN := 1.5

var state: HubState
var world := {}                      ## HubWorld.build() output
var secrets: HubSecrets
var bags: HubBagChallenge
var drill: HubChumDrill
var crates: HubCrateToss
var interactables: Array = []        ## runtime entries {id, kind, pos, r, def}
var focus := {}                      ## fighter index -> entry (or {})
var carry := {}                      ## fighter index -> {id, kind, body, charging, charge, size}
var flying := {}                     ## item id -> {from, t, kind, thrower}
var current_space := ""
var transition := {}                 ## {id, t, to, yaw, fighter} while fading out
var auto_transition := true          ## tests/headless: teleport without waiting for a presenter
var start_spot := "main_floor"
var ludlow := {"pos": Vector3.ZERO, "yaw": 0.0, "leg": 0, "wait": 2.0, "hold": 0.0, "moving": false}
var hidden_items := {}               ## item id -> true while not yet revealed
var delivered := {}                  ## item id -> true (given to Ludlow: removed from the world)
var _pending_interact := {}          ## fighter index -> sim time of the request
var _interact_cd := {}
var _npc_hit_cd := {}
var _space_time := 0.0
var _down_time := 0.0
var _bag_buildup := {}               ## element -> amount (bag 2 reactions)
var _taunt_seq := 0


func id() -> String:
	return "hub"


func display_name() -> String:
	return "The Cannery"


func _init(s: HubState = null, spot := "main_floor") -> void:
	state = s if s != null else HubState.new({})
	start_spot = spot


func setup(match_sim) -> void:
	match_sim.rules["round_time"] = 0.0
	match_sim.rules["rounds"] = 1
	match_sim.rules["intro_time"] = 0.0
	super.setup(match_sim)
	world = HubWorld.build(sim)
	secrets = HubSecrets.new(self, state)
	bags = HubBagChallenge.new(self)
	drill = HubChumDrill.new(self)
	crates = HubCrateToss.new(self)
	_build_interactables()
	for item_id in HubLayout.ITEMS:
		if bool((HubLayout.ITEMS[item_id] as Dictionary).get("hidden", false)):
			hidden_items[item_id] = true
	_apply_persistent_world()
	_register_hittables()
	var lp: Vector3 = HubLayout.NAV[HubLayout.LUDLOW_ROUND[0]]
	ludlow["pos"] = lp
	ludlow["yaw"] = deg_to_rad(float(HubLayout.NPC_SPOTS["ludlow"]["yaw"]))
	var sp := HubLayout.arrive_of(start_spot)
	for f: Fighter in sim.fighters:
		f.respawn(sp[0], sp[1])
		f.invuln_until = -1.0
	phase = Phase.FIGHT
	sim.input_enabled = true
	current_space = HubLayout.space_at(sim.fighters[0].pos()) if not sim.fighters.is_empty() else ""
	if current_space != "":
		state.discover(current_space)


func emit_hub(ev: Dictionary) -> void:
	sim.emit_event(ev)


func player() -> Fighter:
	return sim.fighters[0] if not sim.fighters.is_empty() else null


func _build_interactables() -> void:
	interactables.clear()
	for d in HubLayout.INTERACTS:
		interactables.append({"id": str(d["id"]), "kind": str(d["kind"]), "pos": d["pos"], "r": float(d.get("r", 1.6)), "def": d})
	for tid in HubLayout.TRANSITIONS:
		var t: Dictionary = HubLayout.TRANSITIONS[tid]
		interactables.append({"id": str(tid), "kind": "transition", "pos": t["from"], "r": 1.3, "def": t})


## Restores what found secrets/purchases changed in the physical world.
func _apply_persistent_world() -> void:
	if secrets.panel_open():
		remove_panel()
	if secrets.elevator_fixed():
		fix_elevator()
	for part in state.parts():
		delivered[str(part)] = true
		_park_item(str(part))
	if state.has_cosmetic("hub_trash_lid"):
		delivered["trash_lid"] = true
		_park_item("trash_lid")
	elif secrets.lid_available():
		hidden_items.erase("trash_lid")
	if secrets.sign_fixed():
		delivered["letter_a"] = true
		_park_item("letter_a")
	if bool(state.flag("button_taken")) and not state.parts().has("button"):
		hidden_items.erase("button")      # taken but not delivered: it is back in the cabinet drawer spot


func _register_hittables() -> void:
	for bid in world["bags"]:
		var body: RigidBody3D = world["bags"][bid]
		var d: Dictionary = HubLayout.BAGS[bid]
		sim.register_hittable({"id": "bag_" + str(bid), "body": body, "radius": float(d["radius"]), "reach_up": float(d["length"]),
			"on_hit": _on_bag_hit.bind(str(bid))})
	if world["boiler"]:
		sim.register_hittable({"id": "boiler", "body": world["boiler"], "radius": HubLayout.BOILER_R, "reach_up": 3.2, "on_hit": _on_boiler_hit})
	for npc in world["npc_bodies"]:
		sim.register_hittable({"id": "npc_" + str(npc), "body": world["npc_bodies"][npc], "radius": 0.42, "reach_up": 1.6,
			"on_hit": _on_npc_hit.bind(str(npc))})


# =====================================================================================
# MatchMode hooks: no rounds, no damage, no knockdowns
# =====================================================================================

func tick(dt: float) -> void:
	phase = Phase.FIGHT
	phase_time += dt
	sim.input_enabled = true
	tick_fight(dt)


func on_depleted(f: Fighter, _attacker: Fighter, _hit: Dictionary) -> void:
	f.health = f.max_health


func on_ringout(f: Fighter, _attacker: Fighter) -> void:
	# nothing in the hub can drop a fighter below the floor; if physics ever does, put them back
	var sp := HubLayout.arrive_of(current_space if current_space != "" else "main_floor")
	teleport(f, sp[0], sp[1])


func check_round_over() -> void:
	pass


func on_timeout() -> void:
	pass


func hud_status() -> String:
	return ""


func build_result() -> Dictionary:
	return {"mode": "hub", "winner_team": -1, "fighters": [], "time": sim.time}


## While a bag challenge runs, attacks snap toward the nearest bag (soft lock on objects).
func focus_point(f: Fighter):
	if not bags.running():
		return null
	var body: RigidBody3D = world["bags"].get(bags.bag)
	if body == null:
		return null
	var p := body.global_position + Vector3.UP * 0.9
	if Vector2(p.x - f.pos().x, p.z - f.pos().z).length() < 2.4:
		return p
	return null


func intercept_actions(f: Fighter) -> bool:
	var handled := false
	# A near an interactable is an interaction, not a dodge
	if f._peek(FighterInput.DODGE) and not (focus.get(f.index, {}) as Dictionary).is_empty() and transition.is_empty():
		f._consume(FighterInput.DODGE)
		_interact(f)
		handled = true
	if carry.has(f.index):
		var c: Dictionary = carry[f.index]
		if f._consume(FighterInput.GRAB) or f._consume(FighterInput.LIGHT):
			throw_carried(f, 0.0)
			return true
		if f._consume(FighterInput.HEAVY):
			c["charging"] = true
			c["charge"] = 0.0
			f.mods["speed"] = 0.3
			emit_hub({"type": "hub_charge", "fighter": f.index, "item": c["id"]})
			return true
		for b in [FighterInput.AB1, FighterInput.AB2, FighterInput.JUICE]:
			if f._consume(b):
				handled = true
		if bool(c.get("charging", false)):
			return true
	return handled


func on_grab_pressed(f: Fighter) -> bool:
	if carry.has(f.index):
		throw_carried(f, 0.0)
		return true
	if secrets.try_catch(f):
		return true
	if secrets.pull_panel(f):
		return true
	var near := _nearest_carryable(f)
	if not near.is_empty():
		if str(near["kind"]) == "crate":
			pick_up_crate(f, int(near["index"]))
		else:
			pick_up_item(f, str(near["id"]))
		return true
	return false


# =====================================================================================
# Tick
# =====================================================================================

func tick_fight(dt: float) -> void:
	var f := player()
	if f == null:
		return
	_keep_standing(f, dt)
	_update_space(f, dt)
	_update_ludlow(dt)
	_update_carry(dt)
	_update_flying()
	_update_bag_buildup(dt)
	if bags.running():
		bags.tick(dt)
	if drill.running():
		drill.tick(dt)
	if crates.running():
		crates.tick(dt)
	secrets.tick(dt)
	_watch_events()
	_update_focus(f)
	if _pending_interact.has(f.index):
		if sim.time - float(_pending_interact[f.index]) < 0.25:
			if not (focus.get(f.index, {}) as Dictionary).is_empty():
				_pending_interact.erase(f.index)
				_interact(f)
		else:
			_pending_interact.erase(f.index)
	_update_transition(dt)


## HUB.md §6: fighters cannot be knocked down in the hub (nothing should cause it; if anything
## does, they are back on their feet at once).
func _keep_standing(f: Fighter, dt: float) -> void:
	if f.state == Fighter.State.KNOCKDOWN or f.state == Fighter.State.DOWN:
		_down_time += dt
		if _down_time > 0.2:
			f.revive(1.0)
			_down_time = 0.0
	else:
		_down_time = 0.0
	if f.health < f.max_health:
		f.health = f.max_health


func _update_space(f: Fighter, dt: float) -> void:
	_space_time += dt
	var s := HubLayout.space_at(f.pos())
	if s == "" or s == current_space:
		return
	current_space = s
	var first := state.discover(s)
	state.set_spot(s)
	emit_hub({"type": "hub_space", "space": s, "first": first, "tour_done": state.tour_done()})
	# activities tied to a place end when you walk off
	if bags.running() and s != "main_floor":
		bags.cancel()


## Ludlow's slow mop round between the dock and the Main Floor (he stops while you talk to him).
func _update_ludlow(dt: float) -> void:
	if float(ludlow["hold"]) > 0.0:
		ludlow["hold"] = float(ludlow["hold"]) - dt
		ludlow["moving"] = false
		var f := player()
		if f:
			var to := f.pos() - (ludlow["pos"] as Vector3)
			ludlow["yaw"] = atan2(to.x, to.z)
		_sync_ludlow_body()
		return
	if float(ludlow["wait"]) > 0.0:
		ludlow["wait"] = float(ludlow["wait"]) - dt
		ludlow["moving"] = false
		return
	var route: Array = HubLayout.LUDLOW_ROUND
	var nxt := (int(ludlow["leg"]) + 1) % route.size()
	var target: Vector3 = HubLayout.NAV[route[nxt]]
	var cur: Vector3 = ludlow["pos"]
	var to2 := target - cur
	to2.y = 0.0
	var step := 0.85 * dt
	# he never shoves anyone: if you are in his way he waits for you to pass
	var pf := player()
	if pf:
		var ahead := cur + to2.normalized() * 0.6
		if Vector2(pf.pos().x - ahead.x, pf.pos().z - ahead.z).length() < 1.25 and absf(pf.pos().y - cur.y) < 2.0:
			ludlow["moving"] = false
			return
	ludlow["moving"] = true
	if to2.length() <= step:
		ludlow["pos"] = Vector3(target.x, 0.0, target.z)
		ludlow["leg"] = nxt
		ludlow["wait"] = 5.0 if str(route[nxt]) in ["dock_bench", "mf_center", "mf_mats_s"] else 1.2
	else:
		ludlow["pos"] = cur + to2.normalized() * step
		ludlow["yaw"] = atan2(to2.x, to2.z)
	_sync_ludlow_body()


func _sync_ludlow_body() -> void:
	var body: RigidBody3D = world["npc_bodies"].get("ludlow")
	if body:
		body.global_position = ludlow["pos"]
	for e in interactables:
		if str(e["id"]) == "npc_ludlow":
			e["pos"] = ludlow["pos"]


func hold_npc(npc: String, seconds: float) -> void:
	if npc == "ludlow":
		ludlow["hold"] = maxf(float(ludlow["hold"]), seconds)


func npc_position(npc: String) -> Vector3:
	if npc == "ludlow":
		return ludlow["pos"]
	var s: Dictionary = HubLayout.NPC_SPOTS.get(npc, {})
	return s.get("pos", Vector3.ZERO)


# =====================================================================================
# Interactions
# =====================================================================================

func _update_focus(f: Fighter) -> void:
	var best := {}
	var best_score := INF
	if transition.is_empty() and f.state in [Fighter.State.NEUTRAL, Fighter.State.GUARD, Fighter.State.TAUNT]:
		var p := f.pos()
		var fwd := f.forward()
		for e in interactables:
			var ep: Vector3 = e["pos"]
			if absf(ep.y - (p.y - f.rig.hover_height)) > 1.4 and absf(ep.y - p.y) > 1.4:
				continue
			var to := Vector3(ep.x - p.x, 0.0, ep.z - p.z)
			var d := to.length()
			if d > float(e["r"]):
				continue
			if not _enabled(e, f):
				continue
			var facing := fwd.dot(to.normalized()) if d > 0.05 else 1.0
			var sc := d - facing * 0.35
			if sc < best_score:
				best_score = sc
				best = e
	if best.is_empty():
		focus[f.index] = {}
		return
	var out: Dictionary = best.duplicate()
	out["prompt"] = prompt_for(best, f)
	focus[f.index] = out


## The focused interaction of a fighter: {} or {id, kind, pos, prompt, ...}.
func focus_of(f: Fighter) -> Dictionary:
	return focus.get(f.index, {})


func interaction_available(f: Fighter) -> bool:
	return not focus_of(f).is_empty()


## Keyboard "interact" (and tests): interact on the next tick if something is in reach.
func request_interact(f: Fighter) -> void:
	_pending_interact[f.index] = sim.time


func condition(nm: String) -> bool:
	match nm:
		"elevator_fixed":
			return secrets.elevator_fixed()
		"pier_revealed":
			return secrets.pier_revealed()
		"panel_open":
			return secrets.panel_open()
	return true


func _enabled(e: Dictionary, f: Fighter) -> bool:
	var d: Dictionary = e["def"]
	if d.has("needs") and not condition(str(d["needs"])):
		return false
	match str(e["kind"]):
		"activity":
			return not (bags.running() or drill.running() or crates.running())
		"secret":
			return secrets.interact_enabled(str(e["id"]), f)
		"object":
			if str(e["id"]) == "elevator_gate":
				return not secrets.elevator_fixed()
	return true


func prompt_for(e: Dictionary, f: Fighter) -> String:
	var d: Dictionary = e["def"]
	match str(e["kind"]):
		"npc":
			var npc := str(d.get("npc", ""))
			if npc == "ludlow" and carry.has(f.index) and str(carry[f.index]["kind"]) == "part":
				return "Give Ludlow %s" % str(HubLayout.ITEMS[carry[f.index]["id"]]["name"])
			return "Talk to %s" % HubContent.npc_name(npc)
		"secret":
			if str(e["id"]) == "belt_case":
				if state.has_secret("sec_belt_case_combo"):
					return "Admire the replica belt"
				return "Open the belt case" if secrets.case_unlocked else "The belt case"
	return str(d.get("prompt", e["id"]))


func _interact(f: Fighter) -> void:
	var e: Dictionary = focus.get(f.index, {})
	if e.is_empty():
		return
	if sim.time - float(_interact_cd.get(f.index, -9.0)) < INTERACT_COOLDOWN:
		return
	_interact_cd[f.index] = sim.time
	var d: Dictionary = e["def"]
	var eid := str(e["id"])
	match str(e["kind"]):
		"npc":
			var npc := str(d["npc"])
			if npc == "ludlow" and carry.has(f.index) and str(carry[f.index]["kind"]) == "part":
				var part := str(carry[f.index]["id"])
				_release_carry(f)
				delivered[part] = true
				_park_item(part)
				secrets.give_part(f, part)
				return
			hold_npc(npc, 6.0)
			emit_hub({"type": "hub_interact", "kind": "npc", "npc": npc, "id": eid, "fighter": f.index})
		"station":
			emit_hub({"type": "hub_interact", "kind": "station", "station": str(d["station"]), "id": eid, "fighter": f.index})
		"service":
			emit_hub({"type": "hub_interact", "kind": "service", "service": str(d["service"]), "id": eid, "fighter": f.index})
		"transition":
			begin_transition(f, eid)
		"activity":
			start_activity(str(d["activity"]), str(d.get("bag", "")))
		"object":
			emit_hub({"type": "hub_interact", "kind": "object", "id": eid, "fighter": f.index})
		"secret":
			secrets.interact(eid, f)


# =====================================================================================
# Transitions and teleports
# =====================================================================================

func begin_transition(f: Fighter, tid: String) -> void:
	var t: Dictionary = HubLayout.TRANSITIONS.get(tid, {})
	if t.is_empty() or not transition.is_empty():
		return
	transition = {"id": tid, "t": 0.0, "to": t["to"], "yaw": deg_to_rad(float(t["yaw"])), "fighter": f.index, "dest": str(t["dest"])}
	emit_hub({"type": "hub_transition", "id": tid, "phase": "out", "dest": str(t["dest"]), "seconds": TRANSITION_TIME})


## Fast walk from the corkboard map (only to discovered spaces once the first tour is done).
func fast_walk(f: Fighter, space_id: String) -> bool:
	if not state.tour_done() or not state.discovered().has(space_id) or not transition.is_empty():
		return false
	var sp := HubLayout.arrive_of(space_id)
	transition = {"id": "fast_walk", "t": 0.0, "to": sp[0], "yaw": sp[1], "fighter": f.index, "dest": space_id}
	emit_hub({"type": "hub_transition", "id": "fast_walk", "phase": "out", "dest": space_id, "seconds": TRANSITION_TIME})
	return true


func _update_transition(dt: float) -> void:
	if transition.is_empty():
		return
	transition["t"] = float(transition["t"]) + dt
	if auto_transition and float(transition["t"]) >= TRANSITION_TIME:
		complete_transition()


## Teleports the fighter (called by HubScene at the darkest point of the fade, or automatically).
func complete_transition() -> void:
	if transition.is_empty():
		return
	var tr := transition
	transition = {}
	var f: Fighter = sim.fighters[int(tr["fighter"])]
	teleport(f, tr["to"], float(tr["yaw"]))
	emit_hub({"type": "hub_transition", "id": str(tr["id"]), "phase": "in", "dest": str(tr["dest"])})


func teleport(f: Fighter, pos: Vector3, yaw: float) -> void:
	f._release_grab()
	f.rig.place(pos, yaw)
	f.facing_yaw = yaw
	f.motor.reset_feet()
	if bags.running():
		bags.cancel()
	if drill.running():
		drill.cancel()
	_interact_cd[f.index] = sim.time - 0.15     # interactions resume 0.2 s after arriving
	_update_carry(0.0)
	emit_hub({"type": "hub_teleport", "fighter": f.index, "pos": pos})


# =====================================================================================
# Activities
# =====================================================================================

func start_activity(kind: String, bag := "") -> bool:
	if bags.running() or drill.running() or crates.running():
		return false
	match kind:
		"bag":
			bags.start(bag)
		"drill":
			var f := player()
			if f and not HubLayout.DRILL_SQUARE.has_point(Vector2(f.pos().x, f.pos().z)):
				# step into the square first: the cannon waits for you there
				teleport_soft(f, Vector3(HubLayout.DRILL_SQUARE.get_center().x, 0.0, HubLayout.DRILL_SQUARE.get_center().y))
			drill.start()
		"crates":
			crates.start()
		_:
			return false
	return true


## A short guided walk-in used when an activity needs you somewhere specific (no fade).
func teleport_soft(f: Fighter, pos: Vector3) -> void:
	var yaw := atan2(HubLayout.CANNON_POS.x - pos.x, HubLayout.CANNON_POS.z - pos.z)
	f.rig.place(pos, yaw)
	f.facing_yaw = yaw
	f.motor.reset_feet()


func activity_running() -> String:
	if bags.running():
		return "bag"
	if drill.running():
		return "drill"
	if crates.running():
		return "crates"
	return ""


func cancel_activity() -> void:
	bags.cancel()
	drill.cancel()
	crates.cancel()


func bag_body(id: String) -> RigidBody3D:
	return world["bags"].get(id)


## Combat-identical contact quality of a fighter's active weapon at `point` against a body
## moving with `body_vel` (Combat._resolve_melee formula). {} when no weapon of an active hit
## window is at the point (projectiles, pushes).
func weapon_quality(a: Fighter, point: Vector3, body_center: Vector3, body_vel: Vector3) -> Dictionary:
	if a == null or a.move == null:
		return {}
	var m := a.move
	var widx := m.window_index(a.state_time)
	if widx < 0:
		return {}
	var best: BodyDef.Weapon = null
	var best_d := INF
	var best_wp := Vector3.ZERO
	for wname in m.windows[widx]["weapons"]:
		var w: BodyDef.Weapon = a.creature.body.weapons.get(wname)
		if w == null:
			continue
		var wp := a.rig.bodies[w.seg].global_transform * w.local
		var d := wp.distance_to(point)
		if d < best_d:
			best_d = d
			best = w
			best_wp = wp
	if best == null or best_d > 0.6:
		return {}
	var n := best_wp - Vector3(body_center.x, best_wp.y, body_center.z)
	n = n.normalized() if n.length_squared() > 1e-8 else -a.forward()
	var vrel := a.rig.point_velocity(best.seg, best_wp) - body_vel
	var vn := vrel.dot(-n)
	var spd := vrel.length()
	var clean := clampf(vn / maxf(spd, 0.01), 0.0, 1.0)
	var q := clampf((vn - m.vmin) / maxf(0.01, m.vref - m.vmin), 0.0, 1.0)
	return {"q": q, "clean": clean, "vn": vn, "damage": m.damage, "charge": a.move_charge, "charge_damage": m.charge_damage,
		"class": a.current_move_class(), "slot": a.move_slot, "element": a.element_for(m), "buildup": m.buildup}


func _on_bag_hit(a: Fighter, dir: Vector3, kb: float, launch: float, element: String, point: Vector3, bag_id: String) -> void:
	var body: RigidBody3D = world["bags"].get(bag_id)
	if body == null:
		return
	var info := weapon_quality(a, point, body.global_position, body.linear_velocity)
	var charge := float(info.get("charge", 0.0))
	var imp := dir * kb * body.mass * 0.45 * (1.0 + charge * 0.8) + Vector3.UP * launch * body.mass * 0.05
	body.apply_impulse(imp, point - body.global_position)
	var height := point.y
	if bags.running():
		bags.on_hit(bag_id, info, height, sim.time, point)
	secrets.on_bag_hit(bag_id, info)
	if bag_id == "heavy" and element != "":
		_bag_buildup[element] = float(_bag_buildup.get(element, 0.0)) + (float(info.get("buildup", 25.0)) if not info.is_empty() else 20.0)
		_check_bag_reaction(point)
	emit_hub({"type": "hub_bag_hit", "bag": bag_id, "pos": point, "quality": float(info.get("q", 0.0)), "element": element,
		"heavy": str(info.get("class", "")) == "heavy"})


## Bag 2 keeps element build-up like a fighter would; two elements over the threshold react
## (ELEMENTS.md table), e.g. Scorch + Gale = Flare-Up, and Granny notices.
func _check_bag_reaction(point: Vector3) -> void:
	var over := []
	for el in _bag_buildup:
		if float(_bag_buildup[el]) >= 50.0:
			over.append(str(el))
	if over.size() < 2:
		return
	var r := Elements.reaction(str(over[0]), str(over[1]))
	_bag_buildup.clear()
	if r.is_empty():
		return
	emit_hub({"type": "hub_reaction", "reaction": str(r.get("id", "")), "name": str(r.get("name", "Reaction")), "pos": point})
	if str(r.get("id", "")) == "flare_up":
		emit_hub({"type": "hub_say", "npc": "granny", "key": "line:flare_up"})


func _update_bag_buildup(dt: float) -> void:
	for el in _bag_buildup.keys():
		_bag_buildup[el] = float(_bag_buildup[el]) - dt * 12.0
		if float(_bag_buildup[el]) <= 0.0:
			_bag_buildup.erase(el)


func add_bag_buildup(element: String, amount: float) -> void:
	_bag_buildup[element] = float(_bag_buildup.get(element, 0.0)) + amount
	_check_bag_reaction(world["bags"]["heavy"].global_position + Vector3.UP)


func _on_boiler_hit(a: Fighter, _dir: Vector3, _kb: float, _launch: float, element: String, point: Vector3) -> void:
	emit_hub({"type": "hub_object_hit", "object": "boiler", "pos": point, "element": element, "fighter": a.index if a else -1})
	secrets.on_boiler_hit(element)


func _on_npc_hit(a: Fighter, _dir: Vector3, _kb: float, _launch: float, _element: String, point: Vector3, npc: String) -> void:
	if sim.time - float(_npc_hit_cd.get(npc, -9.0)) < NPC_HIT_COOLDOWN:
		return
	_npc_hit_cd[npc] = sim.time
	emit_hub({"type": "hub_npc_hit", "npc": npc, "pos": point, "fighter": a.index if a else -1})


func _watch_events() -> void:
	# taunts drive the belt-case secret
	for ev in sim.events_since(maxi(0, sim.event_seq - 8)):
		if str(ev["type"]) == "taunt" and int(ev.get("fighter", -1)) == 0 and int(ev["seq"]) > _taunt_seq:
			_taunt_seq = int(ev["seq"])
			secrets.on_taunt(player(), sim.time)


# =====================================================================================
# Carrying and throwing
# =====================================================================================

func _nearest_carryable(f: Fighter) -> Dictionary:
	var at := f.pos() + f.forward() * 0.45
	var best := {}
	var bd := PICKUP_RANGE
	for i in world["crates"].size():
		var c: RigidBody3D = world["crates"][i]
		if _is_carried(c):
			continue
		var d := Vector2(c.global_position.x - at.x, c.global_position.z - at.z).length()
		if d < bd and absf(c.global_position.y - f.ground_pos().y) < 1.6:
			bd = d
			best = {"kind": "crate", "index": i}
	for item_id in world["items"]:
		if hidden_items.has(item_id) or delivered.has(item_id):
			continue
		var b: RigidBody3D = world["items"][item_id]
		if _is_carried(b):
			continue
		var d2 := Vector2(b.global_position.x - at.x, b.global_position.z - at.z).length()
		if d2 < bd and absf(b.global_position.y - f.ground_pos().y) < 1.8:
			bd = d2
			best = {"kind": "item", "id": item_id}
	return best


func _is_carried(b: RigidBody3D) -> bool:
	for k in carry:
		if carry[k]["body"] == b:
			return true
	return false


func pick_up_crate(f: Fighter, i: int) -> void:
	var body: RigidBody3D = world["crates"][i]
	_begin_carry(f, "crate:%d" % i, "crate", body, Vector3.ONE * HubWorld.CRATE_SIZE)


func pick_up_item(f: Fighter, item_id: String) -> void:
	if not world["items"].has(item_id) or delivered.has(item_id):
		return
	hidden_items.erase(item_id)
	var d: Dictionary = HubLayout.ITEMS[item_id]
	if item_id == "trash_lid":
		# the lid is the cosmetic itself: picking it up unlocks it
		delivered[item_id] = true
		_park_item(item_id)
		secrets.on_lid_picked()
		return
	_begin_carry(f, item_id, str(d["kind"]), world["items"][item_id], d["size"])


func _begin_carry(f: Fighter, item_id: String, kind: String, body: RigidBody3D, size: Vector3) -> void:
	if carry.has(f.index):
		_release_carry(f)
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
	carry[f.index] = {"id": item_id, "kind": kind, "body": body, "charging": false, "charge": 0.0, "size": size}
	flying.erase(item_id)
	f.set_flag("carrying", 9999.0)
	emit_hub({"type": "hub_pickup", "fighter": f.index, "item": item_id, "kind": kind})


func _release_carry(f: Fighter) -> void:
	if not carry.has(f.index):
		return
	var c: Dictionary = carry[f.index]
	carry.erase(f.index)
	f.clear_flag("carrying")
	f.mods["speed"] = 1.0
	var body: RigidBody3D = c["body"]
	body.collision_layer = Rig.LAYER_PROPS
	body.collision_mask = HubWorld.PROP_MASK
	body.freeze = false


func carried_by(f: Fighter) -> Dictionary:
	return carry.get(f.index, {})


## Throw strength from the fighter's body mass and throw stats (fighter throws use the same
## inputs): Stoke 1.0, Dredge 1.3, Dozer 1.22, Gusto 0.84, Jitters 0.78.
static func throw_strength(f: Fighter) -> float:
	var td: Dictionary = f.creature.throws.get("throw_fwd", {})
	var stat := float(td.get("distance", 2.5)) / 2.5 * float(f.mods.get("throw_distance", 1.0))
	return clampf(pow(f.rig.total_mass / 85.0, 0.4), 0.72, 1.3) * stat


func throw_distance(f: Fighter, charge: float, item_mass: float) -> float:
	var cfg := HubContent.activity("crates")
	var m := clampf(sqrt(HubWorld.CRATE_MASS / maxf(1.0, item_mass)), 0.6, 1.4)
	var full := float(cfg.get("full_distance", 8.9))
	var tap := float(cfg.get("tap_distance", 3.2))
	return lerpf(tap, full, clampf(charge, 0.0, 1.0)) * throw_strength(f) * m


func throw_carried(f: Fighter, charge: float) -> void:
	if not carry.has(f.index):
		return
	var c: Dictionary = carry[f.index]
	var body: RigidBody3D = c["body"]
	var dir := f.input.move if f.input.move.length() > 0.3 else f.forward()
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 1e-6 else f.forward()
	f.facing_yaw = atan2(dir.x, dir.z)
	var dist := throw_distance(f, charge, body.mass)
	var from := f.pos() + dir * 0.55 + Vector3.UP * 0.75
	_release_carry(f)
	body.global_position = from
	# ballistic arc that touches down `dist` metres ahead on flat floor
	var half := float((c["size"] as Vector3).y) * 0.5
	var fl := 0.42 + 0.07 * dist
	var g: float = sim.gravity
	var vel := dir * (dist / fl)
	vel.y = (half - from.y + 0.5 * g * fl * fl) / fl
	body.linear_velocity = vel
	body.angular_velocity = dir.cross(Vector3.UP) * -4.0 * (0.5 + charge)
	flying[str(c["id"])] = {"from": from, "t": sim.time, "kind": str(c["kind"]), "thrower": f.index, "dist": dist}
	f.stats_record["throws"] += 1
	emit_hub({"type": "hub_throw", "fighter": f.index, "item": c["id"], "kind": c["kind"], "dist": dist, "charge": charge})
	if str(c["kind"]) == "crate" and crates.running():
		crates.on_throw(int(str(c["id"]).trim_prefix("crate:")), from)


func drop_carried(f: Fighter) -> void:
	if not carry.has(f.index):
		return
	var c: Dictionary = carry[f.index]
	var body: RigidBody3D = c["body"]
	_release_carry(f)
	body.global_position = f.pos() + f.forward() * 0.6
	body.linear_velocity = Vector3.ZERO


func _update_carry(dt: float) -> void:
	for idx in carry.keys():
		var f: Fighter = sim.fighters[int(idx)]
		var c: Dictionary = carry[idx]
		var body: RigidBody3D = c["body"]
		if f.is_out() or f.state in [Fighter.State.HITSTUN, Fighter.State.HELD, Fighter.State.KNOCKDOWN, Fighter.State.DOWN]:
			drop_carried(f)
			continue
		var size: Vector3 = c["size"]
		var p: Vector3
		if str(c["kind"]) == "crate":
			p = f.head_pos() + Vector3.UP * (size.y * 0.5 + 0.18)
		else:
			p = f.pos() + f.forward() * (0.45 + size.z * 0.5) + Vector3.UP * 0.25
		body.global_transform = Transform3D(MathX.yaw_basis(f.facing_yaw), p)
		if bool(c.get("charging", false)):
			c["charge"] = minf(1.0, float(c["charge"]) + dt / float(HubContent.activity("crates").get("charge_time", 0.9)))
			if not f.input.is_held(FighterInput.HEAVY):
				var ch := float(c["charge"])
				throw_carried(f, ch)


func _update_flying() -> void:
	for item_id in flying.keys():
		var fl: Dictionary = flying[item_id]
		var body: RigidBody3D = _body_of(str(item_id))
		if body == null:
			flying.erase(item_id)
			continue
		var p := body.global_position
		var age := sim.time - float(fl["t"])
		if str(fl["kind"]) == "letter":
			if secrets.on_letter_flight(p):
				flying.erase(item_id)
				delivered["letter_a"] = true
				_park_item("letter_a")
				continue
		var from: Vector3 = fl["from"]
		var dist := Vector2(p.x - from.x, p.z - from.z).length()
		if p.z < HubLayout.WATER_EDGE_Z and p.y < 0.05 and HubLayout.space_at(from) == "loading_dock":
			flying.erase(item_id)
			emit_hub({"type": "hub_splash", "item": item_id, "pos": Vector3(p.x, HubLayout.WATER_Y, p.z), "dist": dist})
			secrets.on_splash(str(fl["kind"]), dist, p)
			if str(fl["kind"]) == "crate" and crates.running():
				crates.on_land(int(str(item_id).trim_prefix("crate:")), p, true)
			_return_from_water(str(item_id))
			continue
		var half := 0.31 if str(fl["kind"]) == "crate" else 0.2
		var landed := age > 0.12 and body.linear_velocity.y <= 0.5 and p.y <= half + 0.12 + _floor_under(p)
		if landed or age > 4.0:
			flying.erase(item_id)
			emit_hub({"type": "hub_land", "item": item_id, "pos": p, "dist": dist})
			if str(fl["kind"]) == "crate" and crates.running():
				crates.on_land(int(str(item_id).trim_prefix("crate:")), p, false)
	# anything that fell into the harbor without being thrown comes back to its pile
	for i in world["crates"].size():
		var c: RigidBody3D = world["crates"][i]
		if c.global_position.y < -2.0:
			_return_from_water("crate:%d" % i)


func _floor_under(p: Vector3) -> float:
	var s := HubLayout.space_at(p + Vector3.UP * 0.5)
	return float(HubLayout.space(s).get("floor", 0.0)) if s != "" else 0.0


func _body_of(item_id: String) -> RigidBody3D:
	if item_id.begins_with("crate:"):
		var i := int(item_id.trim_prefix("crate:"))
		return world["crates"][i] if i < world["crates"].size() else null
	return world["items"].get(item_id)


func _return_from_water(item_id: String) -> void:
	var body := _body_of(item_id)
	if body == null:
		return
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	if item_id.begins_with("crate:"):
		body.global_position = HubWorld.crate_home(int(item_id.trim_prefix("crate:"))) + Vector3.UP * 0.4
	else:
		body.freeze = true
		body.global_position = (HubLayout.ITEMS[item_id] as Dictionary)["pos"]


## Puts every crate back on the pile (Crate Toss start).
func reset_crates() -> void:
	for f: Fighter in sim.fighters:
		if carry.has(f.index) and str(carry[f.index]["kind"]) == "crate":
			_release_carry(f)
	for i in world["crates"].size():
		var c: RigidBody3D = world["crates"][i]
		c.global_transform = Transform3D(Basis.IDENTITY, HubWorld.crate_home(i))
		c.linear_velocity = Vector3.ZERO
		c.angular_velocity = Vector3.ZERO
		flying.erase("crate:%d" % i)


# =====================================================================================
# World changes from secrets
# =====================================================================================

func remove_panel() -> void:
	var p: StaticBody3D = world.get("panel")
	if p and is_instance_valid(p):
		p.queue_free()
	world["panel"] = null


func fix_elevator() -> void:
	for g in world["gate"]:
		if is_instance_valid(g):
			(g as Node).queue_free()
	world["gate"] = []


func show_item(item_id: String) -> void:
	hidden_items.erase(item_id)


func _park_item(item_id: String) -> void:
	var b: RigidBody3D = world["items"].get(item_id)
	if b == null:
		return
	b.freeze = true
	b.collision_layer = 0
	b.collision_mask = 0
	b.global_position = Vector3(0, -50.0, 0)


func item_visible(item_id: String) -> bool:
	return not hidden_items.has(item_id) and not delivered.has(item_id)


func view_state() -> Dictionary:
	var v := {"mode": "hub", "space": current_space, "activity": activity_running(), "ludlow": ludlow.duplicate(),
		"scrapling": secrets.scrapling_state(), "scrapling_pos": secrets.scrapling_pos(), "frost": secrets.frost()}
	return v
