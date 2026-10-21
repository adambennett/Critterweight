class_name MovesUi
extends RefCounted
## Shared presentation of v0.9.18 Movesets (docs/design/MOVESET_COMBAT.md §2, §3, §9) for the HUD,
## the fighter sheet, the Compendium, the loadout screen, the Controls reference, the pause menu,
## practice and the tutorial. Everything is read from the move pool (PoolMove) and a loadout, never
## written per fighter, so modded fighters and the pools written later present themselves.
##  * The four move inputs: loadout slot m1..m4 = the Controls actions light / heavy / ability1 /
##    ability2 (the Classic Light / Heavy / Ability inputs, Fighter.MOVE_BUTTONS).
##  * Category names and colours (a colour always comes with its name, never alone), how to use a
##    move (tap / hold to charge / hold to sustain and aim / the basic string), its facts (cooldown,
##    charges, stamina) and its two styles.
##  * The player's saved loadout per fighter: profile "loadouts" {creature id: [pool ids]} (fight
##    setup's Moves row, practice's Change moves, Quick Fight and the tutorial read the same one).

const SLOT_ACTIONS := ["light", "heavy", "ability1", "ability2"]
## The categories that hit by themselves (a tutorial special must connect; supports and counters are
## used, not landed).
const OFFENSIVE := ["strike", "projectile", "volley", "stream", "blast", "rush", "control"]
const CATEGORY_NAMES := {"strike": "Strike", "projectile": "Projectile", "volley": "Volley", "stream": "Stream",
	"blast": "Blast", "rush": "Rush", "counter": "Counter", "control": "Control", "support": "Support", "utility": "Utility"}
## One line per category: what it does (design §3.1), for the Compendium and the loadout help.
const CATEGORY_HINTS := {"strike": "close-range melee", "projectile": "one precise shot, aim-assisted at your target",
	"volley": "several projectiles in a fan or a burst", "stream": "keeps going while held; aim it with the stick",
	"blast": "a big area or beam, often charged", "rush": "a movement attack: dash, charge or leap with a hit",
	"counter": "a stance that answers a hit", "control": "zones, pulls and traps", "support": "buffs, shields and cleanses",
	"utility": "positioning: hover, blink, props"}
const CATEGORY_COLORS := {"strike": Color("#e6c04a"), "projectile": Color("#4da3ff"), "volley": Color("#7fd0ff"),
	"stream": Color("#ff7a3d"), "blast": Color("#ff5a5a"), "rush": Color("#ffb340"), "counter": Color("#b06bff"),
	"control": Color("#35c1c9"), "support": Color("#8bd426"), "utility": Color("#9aa0ab")}


## True when `f` fights with equipped moves (Movesets and not a martial fighter, whose strikes keep
## the Cage Rules layout).
static func movesets(f: Fighter) -> bool:
	return f != null and f.creature != null and f.combat_style == "moves" and not f.creature.tags.has("martial")


## The Controls action of loadout slot index `i` (0..3) or slot name ("m1".."m4").
static func slot_action(i: int) -> String:
	return str(SLOT_ACTIONS[i]) if i >= 0 and i < SLOT_ACTIONS.size() else ""


static func slot_action_of(slot: String) -> String:
	return slot_action(Fighter.MOVE_SLOTS.find(slot))


## "[X]" / "[J]": an action's current binding as the bracketed text the tutorial and help use.
static func input_text(action: String) -> String:
	return "[%s]" % Controls.prompt_for(action)


static func category_name(cat: String) -> String:
	return str(CATEGORY_NAMES.get(cat, cat.capitalize()))


static func category_color(cat: String) -> Color:
	return CATEGORY_COLORS.get(cat, UiTheme.MUTED)


## The HUD tag of a held move: "HOLD" (charge, or sustain without aim), "HOLD+AIM" (sustained and
## steered with the stick), "" for a tap.
static func hold_tag(pm: PoolMove) -> String:
	match pm.hold:
		"charge":
			return "HOLD"
		"sustain":
			return "HOLD+AIM" if pm.aim_turn > 0.0 else "HOLD"
	return ""


## The names of a basic strike's string steps, in order (the last one is the finisher).
static func string_names(pm: PoolMove, c: CreatureDef) -> PackedStringArray:
	var out := PackedStringArray()
	for slot in pm.string:
		var m: MoveDef = c.moves.get(str(slot)) if c else null
		out.append(m.display_name if m else str(slot).capitalize())
	return out


## The name of a charge move's charged follow-up ("" when it has none: the charge scales the move).
static func charged_name(pm: PoolMove) -> String:
	return pm.charged.display_name if pm.charged != null else ""


## How to use a move, in one sentence: tap, hold to charge, hold to sustain (and aim), or the basic
## string; a martial technique changes a group of strikes instead.
static func how_to_use(pm: PoolMove, c: CreatureDef = null) -> String:
	if not pm.martial.is_empty():
		return "A technique: it changes your %s strikes" % str(pm.martial.get("group", "")).replace("_", " ")
	if pm.role == "basic":
		var steps := string_names(pm, c)
		var how := "Tap; press again as each hit lands to continue the string"
		if steps.size() > 1:
			how += " (%s); the last press is the finisher" % " – ".join(steps)
		if pm.dash != "" and c and c.moves.has(pm.dash):
			how += "; out of a dodge it is the dash strike (%s)" % (c.moves[pm.dash] as MoveDef).display_name
		return how
	match pm.hold:
		"charge":
			var ch := charged_name(pm)
			return "Hold to charge, release to strike" + (" (a full charge becomes %s)" % ch if ch != "" else "; the longer the charge, the bigger the hit")
		"sustain":
			return "Hold to keep it going (up to %s s)%s" % [num(pm.max_hold), ", steer it with the stick" if pm.aim_turn > 0.0 else ""]
	return "Tap"


## "Stream · Scorch · cooldown 6 s · 6 stamina + 10 per second held · 2 charges"
static func facts(pm: PoolMove) -> String:
	var parts := PackedStringArray()
	parts.append(category_name(pm.category))
	if pm.element != "":
		parts.append(Elements.display_name(pm.element))
	if pm.role == "basic":
		parts.append("no cooldown")
	elif pm.cooldown > 0.0:
		parts.append("cooldown %s s" % num(pm.cooldown))
	if pm.charges > 1:
		parts.append("%d charges" % pm.charges)
	var cost := roundi(pm.stamina_cost())
	if cost > 0:
		parts.append("%d stamina%s" % [cost, " + %d per second held" % roundi(pm.drain) if pm.drain > 0.0 else ""])
	elif pm.drain > 0.0:
		parts.append("%d stamina per second held" % roundi(pm.drain))
	return " · ".join(parts)


## What a move does: its own description, else its one-liner, else (a pool derived from the Classic
## kit, a mod fighter) the Compendium's ability text or a summary of its effects.
static func description(pm: PoolMove, c: CreatureDef = null) -> String:
	if pm.desc != "":
		return pm.desc
	if pm.short != "":
		return pm.short
	if c and pm.use in ["ability1", "ability2", "juice"] and CompendiumData.ABILITIES.has(c.id):
		var texts: Array = CompendiumData.ABILITIES[c.id]
		var i: int = ["ability1", "ability2", "juice"].find(pm.use)
		if i < texts.size():
			return str(texts[i])
	if pm.role == "basic":
		return "%s: the basic string. No cooldown and next to no stamina, so there is always something to throw." % " – ".join(string_names(pm, c))
	if pm.move:
		return CompendiumData.ability_summary(pm.move)
	return ""


## Each style as "Name: what it changes" (drilling a move picks one of them).
static func style_lines(pm: PoolMove) -> PackedStringArray:
	var out := PackedStringArray()
	for sid in pm.styles:
		var s = pm.styles[sid]
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = s
		out.append("%s: %s" % [str(d.get("name", str(sid).capitalize())), str(d.get("desc", ""))])
	return out


## The loadout screen's help text: what it does, how to use it, what it costs.
static func describe(pm: PoolMove, c: CreatureDef = null) -> String:
	var lines := PackedStringArray()
	var d := description(pm, c)
	if d != "":
		lines.append(d)
	lines.append(how_to_use(pm, c) + ".")
	lines.append(facts(pm))
	return "\n".join(lines)


## A loadout's move names in slot order.
static func loadout_names(c: CreatureDef, ids: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for id in ids:
		var pm: PoolMove = c.pool.get(str(id)) if c else null
		out.append(pm.display_name if pm else str(id))
	return out


## The recommended loadout `ids` matches ("Furnace"), else "" (a custom pick).
static func loadout_title(c: CreatureDef, ids: Array) -> String:
	if c == null:
		return ""
	for lk in c.loadouts:
		var lo: Dictionary = c.loadouts[lk]
		if (lo.get("moves", []) as Array) == ids:
			return str(lo.get("name", str(lk).capitalize()))
	return ""


## The player's saved loadout for a fighter (profile "loadouts"), [] when none.
static func saved_loadout(creature_id: String) -> Array:
	var all = Profiles.current.get("loadouts", {})
	if typeof(all) != TYPE_DICTIONARY:
		return []
	var lo = (all as Dictionary).get(creature_id, [])
	return (lo as Array).duplicate() if typeof(lo) == TYPE_ARRAY else []


## The loadout a player fights with: the saved one when it is valid, else the fighter's default.
static func player_loadout(c: CreatureDef) -> Array:
	return c.resolve_loadout(saved_loadout(c.id)) if c else []


## Remembers the player's loadout for a fighter and saves the profile.
static func remember_loadout(creature_id: String, lo: Array) -> void:
	var all = Profiles.current.get("loadouts", {})
	var d: Dictionary = all if typeof(all) == TYPE_DICTIONARY else {}
	d[creature_id] = lo.duplicate()
	Profiles.current["loadouts"] = d
	Profiles.save()


## The local player's fighter in the running match (local or online: both scenes carry a FightHud),
## null outside matches or when nobody local fights.
static func local_fighter() -> Fighter:
	var s = App.current_scene
	if s == null or not is_instance_valid(s):
		return null
	var hud = s.get("hud")
	if not (hud is FightHud):
		return null
	var h := hud as FightHud
	if h.sim == null or h.player_index < 0 or h.player_index >= h.sim.fighters.size():
		return null
	var f: Fighter = h.sim.fighters[h.player_index]
	return f if f.controller_kind == "player" else null


## A small category chip: the category's name on its colour (the name is the cue, the colour helps).
static func chip(text: String, color: Color, size_du := 26) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.darkened(0.6), 0.92)
	sb.border_color = Color(color, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", UiTheme.font("label"))
	l.add_theme_font_size_override("font_size", size_du)
	l.add_theme_color_override("font_color", color.lightened(0.35))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


static func category_chip(cat: String, size_du := 26) -> PanelContainer:
	var p := chip(category_name(cat), category_color(cat), size_du)
	p.name = "Category_" + cat
	return p


static func num(v: float) -> String:
	return ("%d" % roundi(v)) if is_equal_approx(v, roundf(v)) else ("%.1f" % v)
