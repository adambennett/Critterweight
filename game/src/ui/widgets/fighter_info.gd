class_name FighterInfo
extends FocusScroll
## Shared tale-of-the-tape presentation for character select and the compendium.
const STAT_RANGES := {"health": [60.0, 150.0], "walk_speed": [2.2, 4.6], "stamina": [80.0, 115.0], "poise": [30.0, 100.0], "power": [0.7, 1.3]}
const STAT_LABELS := {"health": "Health", "walk_speed": "Speed", "stamina": "Stamina", "poise": "Poise", "power": "Power"}
const CLASSES := [[65.0, "Pipsqueak"], [110.0, "Scrapper"], [145.0, "Lunker"], [9999.0, "Absolute Unit"]]


var creature_id := ""

func _init() -> void:
	super(12)
	focus_mode = Control.FOCUS_ALL

func show_fighter(id: String) -> void:
	creature_id = id
	clear()
	scroll_to_top()
	if id == "random":
		content.add_child(UiTheme.label("RANDOM", "H1"))
		content.add_child(UiTheme.label("Anyone on the roster could step through the door. Find out at the bell.", "Body", true))
		return
	var c := Content.creature(id)
	if c == null:
		return
	var d := Content.get_entry("creatures", id)
	content.add_child(UiTheme.label(c.display_name.to_upper(), "H2", true))
	content.add_child(UiTheme.label(c.title, "H3", true))
	content.add_child(UiIcons.element_badge(c.element, 40, true))
	content.add_child(UiTheme.label(weight_class(d).to_upper(), "Eyebrow", true))
	for k in STAT_RANGES:
		var value := float(c.stats.get(k, 1.0))
		var bounds: Array = STAT_RANGES[k]
		var frac := clampf((value - float(bounds[0])) / (float(bounds[1]) - float(bounds[0])), 0.0, 1.0)
		var txt := ("%.1f m/s" % value) if k == "walk_speed" else (("%d%%" % roundi(value * 100.0)) if k == "power" else "%d" % roundi(value))
		content.add_child(StatBar.new(str(STAT_LABELS[k]), frac, txt, UiTheme.element_color(c.element) if c.element != "" else UiTheme.GOLD))
	content.add_child(UiTheme.label("PLAYSTYLE", "Eyebrow"))
	var blurb := str(d.get("blurb", d.get("playstyle", d.get("description", ""))))
	if blurb == "":
		blurb = "%s · %s" % ["Opponent / NPC" if c.npc_only else "Playable fighter", c.title]
	content.add_child(UiTheme.label(blurb, "Body", true))
	content.add_child(UiTheme.label("KIT", "Eyebrow"))
	var i := 0
	for slot in ["ability1", "ability2", "juice"]:
		if c.abilities.has(slot):
			var move: MoveDef = c.abilities[slot]
			var prompt := ButtonPrompt.new([slot], move.display_name, 38)
			prompt.clickable = false
			prompt._label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			prompt._label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			content.add_child(prompt)
			var description := str(CompendiumData.ABILITIES[id][i]) if CompendiumData.ABILITIES.has(id) else CompendiumData.ability_summary(move)
			content.add_child(UiTheme.label(description, "Body", true))
			var cost := "Requires full Hype" if slot == "juice" else "Cooldown %s s · stamina %s · charges %s" % [c.cooldowns.get(slot, 0), move.stamina, c.ability_charges.get(slot, 1)]
			content.add_child(UiTheme.label(cost, "Caption", true))
		i += 1

static func weight_class(d: Dictionary) -> String:
	var body = d.get("body", {})
	var mass := 0.0
	if typeof(body) == TYPE_DICTIONARY:
		for s in (body as Dictionary).get("segments", []):
			mass += float((s as Dictionary).get("mass", 0.0))
	if mass <= 0.0:
		return ""
	for c in CLASSES:
		if mass <= float(c[0]):
			return "%s · %d kg" % [str(c[1]), roundi(mass)]
	return ""


