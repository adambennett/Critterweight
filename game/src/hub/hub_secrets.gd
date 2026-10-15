class_name HubSecrets
extends RefCounted
## The Cannery's ten secrets (HUB.md §5, docs/HUB_SYSTEMS.md §7) as small state machines driven
## by HubMode hooks. Everything a secret changes in the world is derived from HubState, so a found
## secret stays found (the panel stays off the wall, the elevator keeps running, the sign stays lit).
##   1 sec_loose_panel        Charged Heavy on bag 3 -> the panel swings loose -> Grab pulls it off
##   2 sec_crawlspace_tooth   walk the crawlspace behind it, take the jar
##   3 sec_sleeping_scrapling 600+ on the Heavy bag wakes it; it drops its lid and runs for the dock
##   4 sec_belt_case_combo    taunt at the belt case three times, Kid Lamprey: "...it's not even locked"
##   5 sec_booth_tape         guard (crouch) under Barnaby's desk and press A
##   6 sec_freight_elevator   bring Ludlow a fuse, a cable spool and a button
##   7 sec_roof_sign          throw the fallen "A" back into the GL_NDCO sign
##   8 sec_pier_ladder        a crate thrown 8 m+ into the water scares the gulls off the ladder
##   9 sec_boiler_face        ten Scorch hits on the boiler
##  10 sec_doc_dumpster       30 s in the ice bath, then reach for the bottom

const FROST_TIME := 30.0
const BELT_TAUNTS := 3
const BOILER_HITS := 10
const FISH_TIME := 20.0
const SCRAPLING_SPEED := 2.6          ## a little slower than any fighter: catchable if you cut it off
const FISH_POOL := ["hub_fish_electrolyte", "hub_fish_tonic", "hub_fish_jerky", "hub_fish_liniment", "hub_fish_lozenge", "hub_fish_shake"]

var _mode_ref: WeakRef = null
## The owning HubMode, held weakly: the mode owns this object, so a strong back-reference would be a
## reference cycle that leaks the whole hub sim state on every visit.
var mode:
	get:
		return _mode_ref.get_ref() if _mode_ref != null else null
var state: HubState
var bath_time := 0.0
var _belt_taunts: Array = []        ## sim times of recent taunts at the case
var case_unlocked := false
var scrapling := {"state": "asleep", "pos": Vector3(10.4, 0, 7.0), "leg": 0, "caught": false}   ## asleep | running | gone | caught
var gulls_scared := false
var fishing := {}                   ## {t, fighter}
var _hint_this_visit := false


func _init(m, s: HubState) -> void:
	_mode_ref = weakref(m)
	state = s
	if state.has_secret("sec_sleeping_scrapling") or bool(state.flag("scrapling_woken")):
		scrapling["state"] = "gone"
	gulls_scared = pier_revealed()


# ---- world conditions ------------------------------------------------------------------------

func panel_revealed() -> bool:
	return bool(state.flag("panel_revealed")) or panel_open()


func panel_open() -> bool:
	return state.has_secret("sec_loose_panel")


func elevator_fixed() -> bool:
	return state.has_secret("sec_freight_elevator")


func pier_revealed() -> bool:
	return state.has_secret("sec_pier_ladder")


func sign_fixed() -> bool:
	return state.has_secret("sec_roof_sign")


func lid_available() -> bool:
	return bool(state.flag("scrapling_woken")) and not state.has_cosmetic("hub_trash_lid")


func button_available() -> bool:
	return state.upgrade_level("meta_scouting_report") > 0 and not state.parts().has("button") and not bool(state.flag("button_taken"))


func frost() -> float:
	return clampf(bath_time / FROST_TIME, 0.0, 1.0)


func _found(id: String) -> bool:
	if not state.find_secret(id):
		return false
	var d := HubContent.secret(id)
	var cl := int(d.get("clout", 0))
	if cl > 0:
		state.add_clout(cl, str(d.get("name", id)))
	for c in d.get("cosmetics", []):
		state.unlock_cosmetic(str(c))
	mode.emit_hub({"type": "hub_secret", "id": id, "count": state.secrets_found(), "clout": cl, "name": str(d.get("name", id))})
	return true


# ---- hooks from HubMode ----------------------------------------------------------------------

## A weapon hit on a bag (info from HubMode.weapon_quality; may be empty for non-melee pushes).
func on_bag_hit(bag: String, info: Dictionary) -> void:
	if bag != "body" or info.is_empty() or panel_revealed():
		return
	var charged := str(info.get("slot", "")).begins_with("heavy_charged") or (str(info.get("class", "")) == "heavy" and float(info.get("charge", 0.0)) >= 0.5)
	if not charged:
		return
	state.set_flag("panel_revealed", true)
	var body: RigidBody3D = mode.bag_body("body")
	if body:
		body.apply_central_impulse(Vector3(-1, 0, 0.15).normalized() * body.mass * 2.6)
	mode.emit_hub({"type": "hub_reveal", "what": "panel", "pos": Vector3(-11.9, 1.0, HubLayout.PANEL_RECT.get_center().y)})
	mode.emit_hub({"type": "hub_say", "npc": "granny", "key": "line:bag_secret_hint"})


## Grab pressed near the revealed panel: pull it off.
func pull_panel(f: Fighter) -> bool:
	if not panel_revealed() or panel_open():
		return false
	if Vector2(f.pos().x - HubLayout.PANEL_RECT.position.x, f.pos().z - HubLayout.PANEL_RECT.get_center().y).length() > 1.8:
		return false
	mode.remove_panel()
	_found("sec_loose_panel")
	state.set_flag("panel_pal", true)
	return true


func on_bag_result(bag: String, score: float) -> void:
	var cfg := HubContent.activity("bags")
	if bag == "heavy" and score >= float(cfg.get("scrapling_wake", 600)) and str(scrapling["state"]) == "asleep":
		_wake_scrapling()
	if bag == "body" and score >= float(cfg.get("body_hint", 1000)) and not panel_open():
		state.set_flag("panel_hint", true)
		mode.emit_hub({"type": "hub_say", "npc": "granny", "key": "line:bag_secret_hint"})


func _wake_scrapling() -> void:
	scrapling["state"] = "running"
	scrapling["leg"] = 0
	scrapling["pos"] = HubLayout.SCRAPLING_RUN[0]
	state.set_flag("scrapling_woken", true)
	mode.show_item("trash_lid")
	mode.emit_hub({"type": "hub_reveal", "what": "scrapling", "pos": scrapling["pos"]})
	mode.emit_hub({"type": "hub_say", "npc": "kid", "key": "line:lid"})


func scrapling_pos() -> Vector3:
	return scrapling["pos"]


func scrapling_state() -> String:
	return str(scrapling["state"])


## Grab pressed: catch the running Scrapling if it is close enough.
func try_catch(f: Fighter) -> bool:
	if str(scrapling["state"]) != "running":
		return false
	var sp: Vector3 = scrapling["pos"]
	if Vector2(sp.x - f.pos().x, sp.z - f.pos().z).length() > 1.7:
		return false
	scrapling["state"] = "caught"
	scrapling["caught"] = true
	var before_door := sp.z > HubLayout.SCRAPLING_DOOR_Z
	if before_door:
		state.add_clout(25, "Caught the Scrapling")
	mode.emit_hub({"type": "hub_catch", "pos": sp, "clout": 25 if before_door else 0})
	_found("sec_sleeping_scrapling")
	return true


func on_lid_picked() -> void:
	state.unlock_cosmetic("hub_trash_lid")
	_found("sec_sleeping_scrapling")


func on_taunt(f: Fighter, now: float) -> void:
	if state.has_secret("sec_belt_case_combo") or case_unlocked:
		return
	var to := HubLayout.BELT_CASE_POS - f.pos()
	to.y = 0.0
	if to.length() > 2.6:
		return
	_belt_taunts.append(now)
	_belt_taunts = _belt_taunts.filter(func(x): return now - float(x) < 20.0)
	if _belt_taunts.size() >= BELT_TAUNTS:
		case_unlocked = true
		mode.emit_hub({"type": "hub_say", "npc": "kid", "key": "line:belt_case"})
		mode.emit_hub({"type": "hub_reveal", "what": "belt_case", "pos": HubLayout.BELT_CASE_POS})


## A hit on the boiler. Scorch hits count toward the face.
func on_boiler_hit(element: String) -> void:
	if state.has_secret("sec_boiler_face") or element != "scorch":
		return
	var n := int(state.hub().get("boiler_hits", 0)) + 1
	state.hub()["boiler_hits"] = n
	state.dirty = true
	mode.emit_hub({"type": "hub_boiler", "hits": n, "needed": BOILER_HITS})
	if n >= BOILER_HITS:
		_found("sec_boiler_face")
		mode.emit_hub({"type": "hub_say", "npc": "teddy", "key": "line:boiler_face"})


## A thrown prop touched down in the harbor. dist = horizontal throw distance.
func on_splash(item_kind: String, dist: float, pos: Vector3) -> void:
	if item_kind != "crate" or pier_revealed() or dist < 8.0:
		return
	if Vector2(pos.x - HubLayout.PIER_LADDER.x, pos.z - HubLayout.PIER_LADDER.z).length() > 14.0:
		return
	gulls_scared = true
	_found("sec_pier_ladder")
	mode.emit_hub({"type": "hub_reveal", "what": "pier_ladder", "pos": HubLayout.PIER_LADDER})


## The letter A in flight near the sign slot.
func on_letter_flight(pos: Vector3) -> bool:
	if sign_fixed():
		return false
	if pos.distance_to(HubLayout.SIGN_SLOT) > 1.05:
		return false
	_found("sec_roof_sign")
	state.unlock_cosmetic("hub_rooftop_neon")
	mode.emit_hub({"type": "hub_reveal", "what": "sign", "pos": HubLayout.SIGN_SLOT})
	return true


func give_part(f: Fighter, part: String) -> bool:
	if not HubState.ELEVATOR_PARTS.has(part) or not state.give_part(part):
		return false
	var n := state.parts().size()
	mode.emit_hub({"type": "hub_say", "npc": "ludlow", "key": "line:part_thanks", "vars": {"parts": n}})
	if n >= HubState.ELEVATOR_PARTS.size():
		_found("sec_freight_elevator")
		mode.fix_elevator()
		mode.emit_hub({"type": "hub_say", "npc": "ludlow", "key": "line:elevator_fixed"})
	return true


func tick(dt: float) -> void:
	var f: Fighter = mode.player()
	if f == null:
		return
	# ice bath (secret #10)
	var p := f.pos()
	if HubLayout.ICE_BATH.has_point(Vector2(p.x, p.z)) and not state.has_secret("sec_doc_dumpster"):
		var was := bath_time
		bath_time += dt
		if was < FROST_TIME and bath_time >= FROST_TIME:
			mode.emit_hub({"type": "hub_reveal", "what": "frost", "pos": p})
	else:
		bath_time = maxf(0.0, bath_time - dt * 4.0)
	# the Scrapling's escape run (secret #3)
	if str(scrapling["state"]) == "running":
		var run: Array = HubLayout.SCRAPLING_RUN
		var leg := int(scrapling["leg"])
		if leg + 1 >= run.size():
			scrapling["state"] = "gone"
			mode.emit_hub({"type": "hub_reveal", "what": "scrapling_gone", "pos": scrapling["pos"]})
		else:
			var target: Vector3 = run[leg + 1]
			var cur: Vector3 = scrapling["pos"]
			var step := SCRAPLING_SPEED * dt
			var to := target - cur
			if to.length() <= step:
				scrapling["pos"] = target
				scrapling["leg"] = leg + 1
			else:
				scrapling["pos"] = cur + to.normalized() * step
	# fishing (secret #8 reward)
	if not fishing.is_empty():
		var fp := HubLayout.interact_def("fishing_rod")
		var fpos: Vector3 = fp.get("pos", Vector3.ZERO)
		if f.pos().distance_to(fpos) > 2.2 or f.state != Fighter.State.NEUTRAL and f.state != Fighter.State.GUARD:
			fishing = {}
			mode.emit_hub({"type": "hub_fish", "phase": "cancel"})
		else:
			fishing["t"] = float(fishing["t"]) + dt
			if float(fishing["t"]) >= FISH_TIME:
				_fish_reward()


func _fish_reward() -> void:
	fishing = {}
	var got := ""
	if not state.has_cosmetic("hub_pier_night"):
		got = "hub_pier_night"
	else:
		var pool := FISH_POOL.filter(func(c): return not state.has_cosmetic(str(c)))
		if not pool.is_empty():
			got = str(pool[mode.sim.rng.randi() % pool.size()])
	if got != "":
		state.unlock_cosmetic(got)
	mode.emit_hub({"type": "hub_fish", "phase": "catch", "cosmetic": got})


## Interactions whose id belongs to a secret. Returns true when handled.
func interact(id: String, f: Fighter) -> bool:
	match id:
		"crawl_jar":
			if panel_open() and _found("sec_crawlspace_tooth"):
				mode.emit_hub({"type": "hub_say", "npc": "granny", "key": "text:So that's where my tooth went. Keep it. It suits you."})
			return true
		"belt_case":
			if state.has_secret("sec_belt_case_combo"):
				mode.emit_hub({"type": "hub_interact", "kind": "object", "id": "belt_case_open"})
			elif case_unlocked:
				_found("sec_belt_case_combo")
			else:
				mode.emit_hub({"type": "hub_interact", "kind": "object", "id": "belt_case_locked"})
			return true
		"booth_chair":
			if f.state == Fighter.State.GUARD and _found("sec_booth_tape"):
				state.set_pack("vintage_bellows", true)
				mode.emit_hub({"type": "hub_say", "npc": "barnaby", "key": "line:tape"})
			return true
		"filing_cabinet_2":
			if button_available():
				state.set_flag("button_taken", true)
				mode.show_item("button")
				mode.pick_up_item(f, "button")
				mode.emit_hub({"type": "hub_say", "npc": "snappington", "key": "line:cabinet"})
			return true
		"ice_bath":
			if bath_time >= FROST_TIME and _found("sec_doc_dumpster"):
				mode.emit_hub({"type": "hub_say", "npc": "doc", "key": "line:dumpster_prize"})
			return true
		"fishing_rod":
			if fishing.is_empty():
				fishing = {"t": 0.0, "fighter": f.index}
				mode.emit_hub({"type": "hub_fish", "phase": "start", "seconds": FISH_TIME})
			return true
		"roof_trunk":
			if state.unlock_cosmetic("hub_rooftop_scarf"):
				mode.emit_hub({"type": "hub_reveal", "what": "trunk", "pos": f.pos(), "cosmetic": "hub_rooftop_scarf"})
			else:
				mode.emit_hub({"type": "hub_interact", "kind": "object", "id": "trunk_empty"})
			return true
	return false


## Whether a secret interaction is currently offered.
func interact_enabled(id: String, f: Fighter) -> bool:
	match id:
		"crawl_jar":
			return panel_open() and not state.has_secret("sec_crawlspace_tooth")
		"booth_chair":
			return f.state == Fighter.State.GUARD and not state.has_secret("sec_booth_tape")
		"filing_cabinet_2":
			return button_available()
		"ice_bath":
			return bath_time >= FROST_TIME and not state.has_secret("sec_doc_dumpster")
		"fishing_rod":
			return fishing.is_empty()
	return true


## Ludlow's hint about the unfound secret nearest to `pos` (one per visit). Returns
## {id, text} or {} when he has nothing (or already gave today's hint).
func hint_for(pos: Vector3) -> Dictionary:
	if _hint_this_visit:
		return {"id": "", "text": "That's all I've got for today... come back tomorrow. Or tonight. Whenever tomorrow is..."}
	var best := ""
	var bd := INF
	for id in HubContent.secret_ids():
		if state.has_secret(id):
			continue
		var d := HubContent.secret(id)
		var sp := MathX.vec3(d.get("pos", [0, 0, 0]))
		# roof/pier secrets need the elevator/pier first: hint the gate instead
		if id == "sec_roof_sign" and not elevator_fixed():
			continue
		var dist := pos.distance_to(sp)
		if dist < bd:
			bd = dist
			best = id
	if best == "":
		return {"id": "", "text": HubContent.keyed_line("ludlow", "no_more_hints")}
	_hint_this_visit = true
	state.mark_hint(best)
	return {"id": best, "text": str(HubContent.secret(best).get("hint", ""))}
