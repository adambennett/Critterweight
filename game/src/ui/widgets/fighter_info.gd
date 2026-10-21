class_name FighterInfo
extends FocusScroll
## Shared tale-of-the-tape presentation for character select and the compendium.
## Movesets (`combat = "moves"`, the default combat style; docs/design/MOVESET_COMBAT.md §9):
##  * the character select sheet shows the loadout the fighter would bring (`loadout`, else the
##    player's saved one when `saved_loadouts`, else the fighter's default): each move on its input
##    with its name, category chip, HOLD tag and one line, then the Ultimate and the basic defence;
##  * the Compendium page (`full = true`) lists the whole move pool (category, how to use it,
##    cooldown, cost, description, its two styles), both recommended loadouts and the Ultimate,
##    then the Classic kit (the v0.9.17 abilities, still what Classic plays).
## Classic (`combat = "classic"`) and martial fighters (Varga's Cage Rules layout) show the v0.9.17
## sheet: abilities and JUICE with their inputs.
const STAT_RANGES := {"health": [60.0, 150.0], "walk_speed": [2.2, 4.6], "stamina": [80.0, 115.0], "poise": [30.0, 100.0], "power": [0.7, 1.3]}
const STAT_LABELS := {"health": "Health", "walk_speed": "Speed", "stamina": "Stamina", "poise": "Poise", "power": "Power"}
const CLASSES := [[65.0, "Pipsqueak"], [110.0, "Scrapper"], [145.0, "Lunker"], [9999.0, "Absolute Unit"]]


var creature_id := ""
var combat := "moves"              ## "moves" | "classic": the kit the sheet presents
var full := false                  ## Compendium page: the whole pool, both loadouts, then Classic
var saved_loadouts := false        ## character select for the player: their saved loadout per fighter
var loadout: Array = []            ## the loadout to show (empty: saved / default, see above)

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
	if c.tags.has("martial"):
		content.add_child(UiTheme.label("CAGE RULES CONTROLS", "Eyebrow"))
		content.add_child(UiTheme.label(MartialControls.description(), "Body", true))
		for pair in [["mma_lh", "Left hand"], ["mma_rh", "Right hand"], ["mma_ll", "Left leg"], ["mma_rl", "Right leg"], ["mma_mod1", "Hooks / body kicks"], ["mma_mod2", "Straights / head kicks"], ["mma_mod3", "Overhands / low kicks"], ["mma_guard", "Guard"], ["mma_grab", "Grapple"], ["mma_dodge", "Slip"], ["mma_stance", "Stance"], ["mma_check", "Check"]]:
			var key := ButtonPrompt.new([pair[0]], pair[1], 34)
			key.clickable = false
			content.add_child(key)
	if full:
		_pool_page(c)
		_classic_kit(c, "CLASSIC KIT")
		return
	if combat == "moves" and not c.tags.has("martial") and not c.pool.is_empty():
		_loadout_sheet(c)
		return
	_classic_kit(c, "KIT")


## The loadout this sheet shows for `c` (see `loadout` / `saved_loadouts`).
func shown_loadout(c: CreatureDef) -> Array:
	if not loadout.is_empty():
		return c.resolve_loadout(loadout)
	if saved_loadouts:
		return MovesUi.player_loadout(c)
	return c.resolve_loadout([])


## Character select (Movesets): the four equipped moves on their inputs, the Ultimate, defence.
func _loadout_sheet(c: CreatureDef) -> void:
	var lo := shown_loadout(c)
	var title := MovesUi.loadout_title(c, lo)
	content.add_child(UiTheme.label("MOVES · %s" % (title.to_upper() if title != "" else "YOUR PICK"), "Eyebrow"))
	for i in mini(lo.size(), 4):
		var pm: PoolMove = c.pool.get(str(lo[i]))
		if pm == null:
			continue
		content.add_child(_move_prompt(pm, MovesUi.slot_action(i), 38))
		var line := pm.short if pm.short != "" else MovesUi.description(pm, c)
		content.add_child(UiTheme.label(line if line != "" else MovesUi.how_to_use(pm, c), "Caption", true))
	_ultimate(c)
	content.add_child(UiTheme.label("Guard (tap to parry), Dodge and Grapple work for everyone. Change the four moves with Moves in fight setup.", "Caption", true))


## Compendium (any style): every pool move, the recommended loadouts and the Ultimate.
func _pool_page(c: CreatureDef) -> void:
	if c.pool.is_empty():
		return
	content.add_child(UiTheme.label("MOVE POOL", "Eyebrow"))
	if c.tags.has("martial"):
		content.add_child(UiTheme.label("In Movesets (the default) %s keeps the Cage Rules layout above; a technique changes one group of his strikes, one technique per group." % c.display_name, "Caption", true))
	else:
		content.add_child(UiTheme.label("In Movesets (the default) %s fights with four of these, one on each move input; one of the four is always a basic strike." % c.display_name, "Caption", true))
	for id in c.pool:
		var pm: PoolMove = c.pool[id]
		var head := UiTheme.hbox(UiTheme.GAP_S)
		head.name = "Move_" + str(id)
		head.add_child(MovesUi.category_chip(pm.category, 26))
		var nm := UiTheme.label(pm.display_name, "H3")
		head.add_child(nm)
		var tag := MovesUi.hold_tag(pm)
		if tag != "":
			head.add_child(MovesUi.chip(tag, UiTheme.WARM, 26))
		if pm.role == "basic":
			head.add_child(MovesUi.chip("Basic", UiTheme.GOLD_HI, 26))
		content.add_child(head)
		content.add_child(UiTheme.label(MovesUi.how_to_use(pm, c) + ".", "BodyStrong", true))
		content.add_child(UiTheme.label(MovesUi.facts(pm), "Caption", true))
		var desc := MovesUi.description(pm, c)
		if desc != "":
			content.add_child(UiTheme.label(desc, "Body", true))
		var styles := MovesUi.style_lines(pm)
		if not styles.is_empty():
			content.add_child(UiTheme.label("Styles (drilling picks one): " + "  ·  ".join(styles), "Caption", true))
	if not c.loadouts.is_empty():
		content.add_child(UiTheme.label("RECOMMENDED LOADOUTS", "Eyebrow"))
		for lk in c.loadouts:
			var lo: Dictionary = c.loadouts[lk]
			var ids: Array = lo.get("moves", [])
			var name_l := UiTheme.label("%s%s" % [str(lo.get("name", str(lk).capitalize())), "  (default)" if str(lk) == c.default_loadout else ""], "BodyStrong", true)
			name_l.name = "Loadout_" + str(lk)
			content.add_child(name_l)
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 22)
			flow.add_theme_constant_override("v_separation", 6)
			flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			for i in mini(ids.size(), 4):
				var pm2: PoolMove = c.pool.get(str(ids[i]))
				if pm2:
					var p := ButtonPrompt.new([MovesUi.slot_action(i)], pm2.display_name, 34)
					p.clickable = false
					flow.add_child(p)
			content.add_child(flow)
	_ultimate(c)


func _move_prompt(pm: PoolMove, action: String, glyph_du: float) -> ButtonPrompt:
	var prompt := ButtonPrompt.new([action], pm.display_name, glyph_du)
	prompt.name = "MovePrompt_" + pm.id
	prompt.clickable = false
	prompt.add_child(MovesUi.category_chip(pm.category, 26))
	var tag := MovesUi.hold_tag(pm)
	if tag != "":
		prompt.add_child(MovesUi.chip(tag, UiTheme.WARM, 26))
	return prompt


func _ultimate(c: CreatureDef) -> void:
	if not c.abilities.has("juice"):
		return
	var j: MoveDef = c.abilities["juice"]
	content.add_child(UiTheme.label("ULTIMATE", "Eyebrow"))
	var prompt := ButtonPrompt.new([MartialControls.action("juice", c)], j.display_name, 38)
	prompt.clickable = false
	prompt._label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt._label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(prompt)
	var texts: Array = CompendiumData.ABILITIES.get(c.id, [])
	content.add_child(UiTheme.label(str(texts[2]) if texts.size() > 2 else CompendiumData.ability_summary(j), "Body", true))
	content.add_child(UiTheme.label("Requires full Hype", "Caption", true))


## The v0.9.17 kit: abilities and JUICE with their inputs (Classic, martial fighters, and the
## Classic section of a Compendium page).
func _classic_kit(c: CreatureDef, heading: String) -> void:
	content.add_child(UiTheme.label(heading, "Eyebrow"))
	if full and not c.tags.has("martial"):
		content.add_child(UiTheme.label("In Classic (a match rule: Rules Editor › Fighters › Combat style) %s fights with Light, Heavy (hold to charge), Grab and these abilities:" % c.display_name, "Caption", true))
	var i := 0
	for slot in ["ability1", "ability2", "juice"]:
		if c.abilities.has(slot):
			var move: MoveDef = c.abilities[slot]
			var prompt := ButtonPrompt.new([MartialControls.action(slot, c)], move.display_name, 38)
			prompt.clickable = false
			prompt._label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			prompt._label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			content.add_child(prompt)
			var description := str(CompendiumData.ABILITIES[c.id][i]) if CompendiumData.ABILITIES.has(c.id) else CompendiumData.ability_summary(move)
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
