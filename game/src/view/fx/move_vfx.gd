class_name MoveVfx
extends RefCounted
## Effects for the v0.9.18 Movesets moves (docs/art/VFX.md "Movesets"). Each fighter's new moves draw
## through a kit script res://src/view/fx/moves/<creature id>.gd (extends MoveFxKit). AbilityVfx
## offers the kits every move event (effect, sustain, move start, ability use, hit) and every entity
## look first; a kit returns true (or an entity record) when it drew it, otherwise the v0.9.17
## recipes run. Kits are found by creature (events of their fighters) and by vfx name (effect events
## and entities, which online clients receive without an owner).

const DIR := "res://src/view/fx/moves/"
const KIT_IDS := ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters", "f_knell", "f_varga"]

var fx: AbilityVfx
var kits := {}          ## creature id -> MoveFxKit
var by_vfx := {}        ## vfx name -> MoveFxKit


func _init(owner: AbilityVfx) -> void:
	fx = owner
	for id in KIT_IDS:
		var path: String = DIR + str(id) + ".gd"
		if not ResourceLoader.exists(path):
			continue
		var scr = load(path)
		if not (scr is GDScript) or not (scr as GDScript).can_instantiate():
			push_warning("move effects kit %s did not load" % path)
			continue
		var kit: MoveFxKit = (scr as GDScript).new()
		kit.fx = owner
		kit.creature = str(id)
		kits[str(id)] = kit
		for v in kit.vfx_names():
			by_vfx[str(v)] = kit


## Offers an event to the kits. Returns true when a kit drew it completely (the v0.9.17 recipes
## then skip it). Hits are never consumed: the impact recipes still run under a kit's extras.
func on_event(fi: int, cid: String, ev: Dictionary) -> bool:
	var type := str(ev.get("type", ""))
	match type:
		"effect":
			var k1: MoveFxKit = by_vfx.get(str(ev.get("vfx", "")))
			return k1 != null and k1.on_effect(fi, ev)
		"sustain":
			var k2: MoveFxKit = kits.get(cid)
			return k2 != null and k2.on_sustain(fi, ev)
		"move_start", "ability":
			if str(ev.get("pool", "")) == "":
				return false
			var k3: MoveFxKit = kits.get(cid)
			if k3 == null:
				return false
			return k3.on_move_start(fi, ev) if type == "move_start" else k3.on_ability(fi, ev)
		"hit":
			if str(ev.get("pool", "")) != "":
				var k4: MoveFxKit = kits.get(cid)
				if k4 != null:
					k4.on_hit(fi, ev)
	return false


## An entity look from the kit that owns its vfx name, or {} (the v0.9.17 looks).
func make_entity(e: Dictionary) -> Dictionary:
	var kit: MoveFxKit = by_vfx.get(str(e.get("vfx", "")))
	return kit.make_entity(e) if kit != null else {}


func process(delta: float) -> void:
	for kit: MoveFxKit in kits.values():
		kit.process(delta)
