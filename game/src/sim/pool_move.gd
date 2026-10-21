class_name PoolMove
extends RefCounted
## One move of a fighter's move pool (v0.9.18 Movesets, docs/design/MOVESET_COMBAT.md §3).
## Parsed by CreatureDef from the creature JSON `movepool`; a creature without one gets a pool built
## from its Classic slots (see CreatureDef.derive_pool). The physical action is an ordinary MoveDef:
##   * `use`: a v0.9.17 move or ability by slot ("heavy", "ability1"); `charged` names its charged
##     follow-up ("heavy_charged"). Upgrades written for those slots keep reaching it.
##   * `string` (+ `dash`): a basic strike string over move slots (press again to continue; the last
##     step is the finisher; pressed out of a dodge it is the dash strike).
##   * `move` (+ `charged_move`): an inline MoveDef ("<creature>.mv.<id>").

const CATEGORIES := ["strike", "projectile", "volley", "stream", "blast", "rush", "counter", "control", "support", "utility"]
const ROLES := ["basic", "heavy", "special", "support"]
const HOLDS := ["", "charge", "sustain"]
## The generic Classic slots an upgrade can name, by the role that inherits them in Movesets (§7).
## (ability1/ability2 are each fighter's own abilities, still in its pool as themselves: upgrades
## naming them reach exactly those moves.)
const ROLE_OF_SLOT := {"l1": "basic", "l2": "basic", "l3": "basic", "finisher": "basic", "dash_attack": "basic",
	"heavy": "heavy", "heavy_charged": "heavy"}

var id := ""
var display_name := ""
var short := ""                   ## one line for HUD cards and menus
var desc := ""                    ## the Compendium / move list description
var category := "strike"
var role := "special"
var element := ""
var hold := ""                    ## "" | charge (charges while held, fires on release) | sustain (lasts while held)
var max_hold := 2.0               ## sustain: longest hold (s)
var drain := 0.0                  ## sustain: stamina per second while held
var aim_turn := 0.0               ## rad/s the stick (else the target) steers the fighter while the move runs; 0 = the move's own turn rate toward the target
var cooldown := 0.0               ## seconds; 0 = none (basic moves)
var charges := 1
var cost := -1.0                  ## stamina at the start; < 0 = the MoveDef's own stamina
var string: Array = []            ## basic: move slots walked by repeated presses (last = finisher)
var dash := ""                    ## basic: the dash strike's move slot ("" = none)
var move: MoveDef = null
var charged: MoveDef = null
var use := ""                     ## the Classic slot it is built on ("" = inline or a string)
var charged_use := ""
var classic_slots: PackedStringArray = PackedStringArray()   ## Classic slots it stands in for (upgrades, hooks)
var styles := {}                  ## style id -> {name, desc, patch}
var ai := {}                      ## bot hints {range: [min, max], hold: [min, max], when: [...], chance, apart}
var derived := false              ## built from the Classic slots (no movepool in the content)
var martial := {}                 ## martial techniques: {group, slots: {limb slot: technique move key}}


## Stamina a press needs (the move's own stamina when no explicit cost).
func stamina_cost() -> float:
	if cost >= 0.0:
		return cost
	return move.stamina if move else 0.0


## Whether a Classic slot name (as written in upgrades and hook conditions) applies to this move:
## directly (it is built on that slot) or through its role (a new heavy-role move inherits "heavy").
func answers_slot(slot: String) -> bool:
	if classic_slots.has(slot):
		return true
	return str(ROLE_OF_SLOT.get(slot, "")) == role and role != ""


## The slot name the simulation reports while this move runs (hooks, events, judges, VFX): the
## Classic slot it is built on, or "mv.<id>" for an inline move.
func report_slot() -> String:
	if use != "":
		return use
	return "mv." + id


static func parse(c: CreatureDef, key: String, d: Dictionary, errors: PackedStringArray) -> PoolMove:
	var p := PoolMove.new()
	p.id = key
	p.display_name = str(d.get("name", key.capitalize()))
	p.short = str(d.get("short", ""))
	p.desc = str(d.get("desc", ""))
	p.category = str(d.get("category", "strike"))
	if not CATEGORIES.has(p.category):
		errors.append("%s: move '%s': unknown category '%s'" % [c.id, key, p.category])
	p.role = str(d.get("role", "basic" if d.has("string") else "special"))
	if not ROLES.has(p.role):
		errors.append("%s: move '%s': unknown role '%s'" % [c.id, key, p.role])
	p.hold = str(d.get("hold", ""))
	if not HOLDS.has(p.hold):
		errors.append("%s: move '%s': unknown hold '%s'" % [c.id, key, p.hold])
	p.max_hold = float(d.get("max_hold", 2.0))
	p.drain = float(d.get("drain", 0.0))
	var aim = d.get("aim", {})
	if typeof(aim) == TYPE_DICTIONARY:
		p.aim_turn = float((aim as Dictionary).get("turn_rate", 0.0))
	p.cost = float(d.get("cost", -1.0))
	p.styles = d.get("styles", {}) if typeof(d.get("styles", {})) == TYPE_DICTIONARY else {}
	p.martial = d.get("martial", {}) if typeof(d.get("martial", {})) == TYPE_DICTIONARY else {}
	if not p.martial.is_empty():
		var reps = p.martial.get("slots", {})
		if typeof(reps) == TYPE_DICTIONARY:
			for slot in reps:
				if not c.moves.has(str(reps[slot])):
					errors.append("%s: technique '%s': move '%s' missing" % [c.id, key, str(reps[slot])])
	p.ai = d.get("ai", {}) if typeof(d.get("ai", {})) == TYPE_DICTIONARY else {}
	if d.has("use"):
		p.use = str(d["use"])
		if c.abilities.has(p.use):
			p.move = c.abilities[p.use]
			p.cooldown = float(c.cooldowns.get(p.use, 6.0))
			p.charges = int(c.ability_charges.get(p.use, 1))
		elif c.moves.has(p.use):
			p.move = c.moves[p.use]
		else:
			errors.append("%s: move '%s' uses missing slot '%s'" % [c.id, key, p.use])
		p.classic_slots.append(p.use)
		if d.has("charged"):
			p.charged_use = str(d["charged"])
			if c.moves.has(p.charged_use):
				p.charged = c.moves[p.charged_use]
				p.classic_slots.append(p.charged_use)
			else:
				errors.append("%s: move '%s': charged slot '%s' missing" % [c.id, key, p.charged_use])
	elif d.has("string"):
		for s in d["string"]:
			if c.moves.has(str(s)):
				p.string.append(str(s))
				p.classic_slots.append(str(s))
			else:
				errors.append("%s: move '%s': string step '%s' missing" % [c.id, key, s])
		if p.string.is_empty():
			errors.append("%s: move '%s': empty string" % [c.id, key])
		else:
			p.move = c.moves[p.string[0]]
		p.dash = str(d.get("dash", ""))
		if p.dash != "":
			if c.moves.has(p.dash):
				p.classic_slots.append(p.dash)
			else:
				errors.append("%s: move '%s': dash strike '%s' missing" % [c.id, key, p.dash])
	elif not p.martial.is_empty():
		# a martial technique: no input of its own, it changes the strikes of its modifier group
		var first = (p.martial.get("slots", {}) as Dictionary).values()
		if not first.is_empty() and c.moves.has(str(first[0])):
			p.move = c.moves[str(first[0])]
	elif typeof(d.get("move", null)) == TYPE_DICTIONARY:
		p.move = _inline(c, key, d["move"], "", p, errors)
		if typeof(d.get("charged_move", null)) == TYPE_DICTIONARY:
			p.charged = _inline(c, key, d["charged_move"], "_charged", p, errors)
	else:
		errors.append("%s: move '%s' has no use, string or move" % [c.id, key])
	if d.has("cooldown"):
		p.cooldown = float(d["cooldown"])
	if d.has("charges"):
		p.charges = maxi(1, int(d["charges"]))
	p.element = str(d.get("element", p.move.element if p.move else ""))
	if p.role == "basic" and p.cooldown > 0.0:
		errors.append("%s: move '%s': basic moves have no cooldown" % [c.id, key])
	if p.hold == "sustain" and p.move and p.move.sustain.size() < 2:
		errors.append("%s: move '%s': a sustain move needs a 'sustain' [t0, t1] window" % [c.id, key])
	return p


static func _inline(c: CreatureDef, key: String, md: Dictionary, suffix: String, p: PoolMove, errors: PackedStringArray) -> MoveDef:
	var m: Dictionary = md.duplicate()
	if not m.has("id"):
		m["id"] = "%s.mv.%s%s" % [c.id, key, suffix]
	if not m.has("kind"):
		m["kind"] = "melee" if p.category == "strike" else "ability"
	if not m.has("name"):
		m["name"] = p.display_name
	if not m.has("class"):
		# hype, armour and the judges read the class: basic strikes are light, heavy-role moves heavy
		m["class"] = "light" if p.role == "basic" else ("heavy" if p.role == "heavy" else "ability")
	return MoveDef.parse(m, c.body, errors)
