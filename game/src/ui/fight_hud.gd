class_name FightHud
extends Control
## In-match HUD: per-fighter cards (health with damage trail, stamina, hype/JUICE meter, ability
## cooldowns, status icons with text), round timer/pips, mode status, centre callouts and
## subtitles. Every essential cue has text, not only colour.

var sim: MatchSim
var player_index := 0
const TRAIL_HOLD := 0.6          ## seconds a hit's chunk stays lit on the health bar
const TRAIL_DRAIN := 0.5         ## then it drains this much of the bar per second

var cards := {}                  ## fighter index -> Dictionary of nodes
var _center: Label
var _sub: Label
var _timer: Label
var _mode_label: Label
var _center_until := 0.0
var _sub_until := 0.0
var _font_heavy: Font
var _font: Font
var ui_scale := 1.0


var _top: HBoxContainer
var _margin: MarginContainer
var _hints: Control                ## the controls-hint strip (bottom-anchored in duels)
var _hints_bottom := false
var _bottom: GridContainer
var _ability_prompts := {}
var _bottom_inset := 0.0


func setup(match_sim: MatchSim, player_idx: int) -> void:
	sim = match_sim
	player_index = player_idx
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font_heavy = load("res://assets/fonts/BarlowCondensed-900.woff2")
	_font = load("res://assets/fonts/BarlowCondensed-700.woff2")
	var n := sim.fighters.size()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin = margin
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)
	_top = HBoxContainer.new()
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_top)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer = _label("99", 54, _font_heavy)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label = _label("", 26, _font)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if n <= 2:
		cards[sim.fighters[0].index] = _make_card(sim.fighters[0], n, _top, false)
		_top.add_child(mid)
		if n == 2:
			cards[sim.fighters[1].index] = _make_card(sim.fighters[1], n, _top, true)
	else:
		_top.add_child(mid)
		_bottom = GridContainer.new()
		_bottom.name = "TopRoster"
		_bottom.columns = mini(n, 4)
		_bottom.add_theme_constant_override("h_separation", 18)
		_bottom.add_theme_constant_override("v_separation", 8)
		_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bottom.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(_bottom)
		col.move_child(_bottom, 1)
		for f in sim.fighters:
			cards[f.index] = _make_card(f, n, _bottom, false)
	mid.add_child(_timer)
	mid.add_child(_mode_label)
	_center = _label("", 110, _font_heavy)
	_center.set_anchors_preset(Control.PRESET_CENTER)
	_center.offset_left = -700
	_center.offset_right = 700
	_center.offset_top = -170
	_center.offset_bottom = -20
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center.add_theme_constant_override("outline_size", 18)
	_center.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.08))
	add_child(_center)
	_sub = _label("", 30, _font)
	_sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub.offset_left = -700
	_sub.offset_right = 700
	# Keep subtitles between the top fighter cards and the bottom control prompts.
	_sub.offset_top = -180
	_sub.offset_bottom = -88
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.add_theme_constant_override("outline_size", 10)
	_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_child(_sub)
	_add_control_hints(n)


## Settings › Gameplay › Control hints: the core actions with the live bindings (players only).
func _add_control_hints(_n: int) -> void:
	if player_index < 0 or player_index >= sim.fighters.size() or sim.fighters[player_index].controller_kind != "player":
		return
	var bar := HFlowContainer.new()
	bar.theme = UiTheme.get_theme()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("h_separation", 20)
	bar.alignment = FlowContainer.ALIGNMENT_CENTER
	var fighter: Fighter = sim.fighters[player_index]
	if bool(Settings.get_value("gameplay.tutorial_prompts")):
		var hints := [["light", "Light"], ["heavy", "Heavy"], ["guard", "Guard"], ["dodge", "Dodge"], ["grab", "Grab"]]
		if fighter.creature.tags.has("martial"):
			hints = [["mma_lh", "L hand"], ["mma_rh", "R hand"], ["mma_ll", "L leg"], ["mma_rl", "R leg"], ["mma_mod1", "Hooks"], ["mma_mod2", "Straights"], ["mma_mod3", "Overhands"], ["mma_guard", "Guard"], ["mma_grab", "Grapple"], ["mma_dodge", "Slip"]]
		for item in hints:
			var prompt := ButtonPrompt.new([item[0]], item[1], 36)
			prompt.clickable = false
			bar.add_child(prompt)
	for slot in ["ability1", "ability2", "juice"]:
		if slot != "juice" and not fighter.creature.abilities.has(slot):
			continue
		var prompt := CombatPrompt.new([MartialControls.action(slot, fighter.creature)], "JUICE" if slot == "juice" else ("Trick 1" if slot == "ability1" else "Trick 2"), 40)
		bar.add_child(prompt)
		_ability_prompts[slot] = prompt
	var strip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.08, 0.75)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(8)
	strip.add_theme_stylebox_override("panel", sb)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(bar)
	strip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	strip.offset_top = -116 if fighter.creature.tags.has("martial") else -78
	strip.offset_bottom = -16
	strip.offset_left = -850
	strip.offset_right = 850
	add_child(strip)
	if fighter.creature.tags.has("martial"):
		_sub.offset_top = -224
		_sub.offset_bottom = -124
	_hints = strip
	_hints_bottom = true


## Lifts subtitles and the control-hint strip by `px`, so a control
## bar laid over the match (The Bookie's Table) never hides them.
func set_bottom_inset(px: float) -> void:
	_bottom_inset = px
	var martial := player_index >= 0 and player_index < sim.fighters.size() and sim.fighters[player_index].creature.tags.has("martial")
	if _sub:
		_sub.offset_top = (-224.0 if martial else -180.0) - px
		_sub.offset_bottom = (-124.0 if martial else -88.0) - px
	if _margin:
		_margin.add_theme_constant_override("margin_bottom", 28 + int(px))
	if _hints and _hints_bottom:
		_hints.offset_top = (-116.0 if martial else -78.0) - px
		_hints.offset_bottom = -16.0 - px


func _label(t: String, size: int, font: Font) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.08))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(w: float, h: float, fill: Color, back := Color(0.08, 0.06, 0.1, 0.85)) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(w, h)
	pb.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = back
	bg.set_corner_radius_all(3)
	bg.border_color = Color(0, 0, 0, 0.9)
	bg.set_border_width_all(2)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	pb.max_value = 1.0
	pb.value = 1.0
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pb


func _make_card(f: Fighter, n: int, parent: Container, right_align: bool) -> Dictionary:
	var big := n <= 2
	var w := 520.0 if big else 340.0
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 3)
	box.custom_minimum_size = Vector2(w, 0)
	parent.add_child(box)
	if right_align:
		box.alignment = BoxContainer.ALIGNMENT_BEGIN
	var team_col := TeamColors.color(f.team)
	var head := HBoxContainer.new()
	# the profile owner's card wears the equipped profile frame (a Cannery cosmetic)
	box.add_child(ProfileFrame.wrap(head, ProfileFrame.style(), 26) if f.index == _owner_index() else head)
	var name_l := _label(f.display_name.to_upper(), 32 if big else 26, _font_heavy)
	name_l.add_theme_color_override("font_color", team_col.lightened(0.3))
	head.add_child(name_l)
	var tag := _label(" (YOU)" if f.index == player_index and f.controller_kind == "player" else "", 24, _font)
	head.add_child(tag)
	var lives := _label("", 24, _font)
	head.add_child(lives)
	var hp_stack := Control.new()
	hp_stack.custom_minimum_size = Vector2(w, 30 if big else 26)
	box.add_child(hp_stack)
	var trail := _bar(w, 30 if big else 26, Color(1.0, 0.85, 0.85))
	hp_stack.add_child(trail)
	var hp := _bar(w, 30 if big else 26, Color(0.95, 0.27, 0.3), Color(0, 0, 0, 0))
	hp_stack.add_child(hp)
	var hp_text := _label("", 24, _font)
	hp_text.position = Vector2(8, 0)
	hp_stack.add_child(hp_text)
	var st := _bar(w * 0.7, 10, Color(0.35, 0.85, 0.55))
	box.add_child(st)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	box.add_child(row)
	var hype := _bar(w * (0.45 if big else 0.32), 14, Color(1.0, 0.62, 0.15))
	hype.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hype)
	var hype_l := _label("HYPE", 24, _font)
	row.add_child(hype_l)
	var status := _label("", 23, _font)
	status.max_lines_visible = 2
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	return {"box": box, "name": name_l, "hp": hp, "trail": trail, "hp_text": hp_text, "st": st, "hype": hype, "hype_l": hype_l,
		"status": status, "lives": lives, "trail_v": 1.0, "big": big}


## Damage trail behind the health bar: the chunk a hit took stays lit for TRAIL_HOLD seconds
## after the latest hit (so a landed hit reads at a glance), then drains at TRAIL_DRAIN per
## second. Returns [trail, hold left]. A heal snaps the trail to the new health.
static func trail_step(trail: float, hold: float, frac: float, prev: float, dt: float) -> Array:
	if frac < prev - 0.0001:
		hold = TRAIL_HOLD
	if trail <= frac:
		return [frac, 0.0]
	if hold > 0.0:
		return [trail, hold - dt]
	return [maxf(frac, trail - dt * TRAIL_DRAIN), 0.0]


## The first local player's fighter (the profile owner), -1 when none fights.
func _owner_index() -> int:
	for f in sim.fighters:
		if f.controller_kind == "player":
			return f.index
	return -1


func _process(dt: float) -> void:
	if sim == null:
		return
	for f in sim.fighters:
		if not cards.has(f.index):
			continue
		var c: Dictionary = cards[f.index]
		(c["box"] as Control).visible = not f.despawned
		if f.despawned:
			continue
		(c["name"] as Label).text = f.display_name.to_upper()
		var frac := f.health_frac()
		(c["hp"] as ProgressBar).value = frac
		var tr := trail_step(float(c["trail_v"]), float(c.get("trail_hold", 0.0)), frac, float(c.get("hp_prev", frac)), dt)
		c["trail_v"] = tr[0]
		c["trail_hold"] = tr[1]
		c["hp_prev"] = frac
		(c["trail"] as ProgressBar).value = c["trail_v"]
		var resting := bool(f.flags.get("resting", false)) and f.health > 0.0
		(c["hp_text"] as Label).text = ("%d  RESTING" % ceili(f.health)) if resting else ("%d" % ceili(f.health) if not f.is_out() else ("KO" if f.state == Fighter.State.KO else "DOWN"))
		(c["st"] as ProgressBar).value = f.stamina / f.max_stamina
		(c["hype"] as ProgressBar).value = f.hype / 100.0
		var juiced := f.time < f.juiced_until
		(c["hype_l"] as Label).text = "JUICED!" if juiced else "HYPE"
		if f.index == player_index and f.controller_kind == "player":
			for slot in _ability_prompts:
				var left := float(f.cooldown_left.get(slot, 0.0))
				var full := 1.0
				if f.creature.abilities.has(slot):
					full = maxf(0.01, float(f.creature.cooldowns.get(slot, 1.0)))
				var available := int(f.charges_left.get(slot, 1)) > 0
				if available:
					left = 0.0 # A second charge stays usable while the spent charge recharges.
				if slot == "juice":
					available = f.hype >= 100.0 or juiced
					left = 0.0
				(_ability_prompts[slot] as CombatPrompt).set_cooldown(left, full, available)
		var st_txt := []
		for s in f.statuses.summary():
			var nm := str(s["element"]) if str(s["element"]) != "" else str(s["name"])
			nm = nm.replace("_", " ").to_upper()
			var left := float(s["left"])
			# mode-long statuses (e.g. the Absolute Unit) show no countdown
			st_txt.append(nm if left > 999.0 else "%s %.0fs" % [nm, ceilf(left)])
		(c["status"] as Label).text = "  ".join(st_txt)
		(c["lives"] as Label).text = ("  x%d" % f.lives) if f.lives > 1 or (f.lives >= 0 and sim.rules.get("lives", 1) > 1) else ""
	var mm := sim.mode
	if mm:
		var rt := float(sim.rules.get("round_time", 99.0))
		_timer.text = "%d" % ceili(mm.round_timer) if rt > 0.0 else ""
		var hs: Dictionary = mm.hud_state()
		var parts := []
		for row in hs.get("rows", []):
			parts.append("%s %d" % [str(row["label"]), int(row["value"])])
		var line := "   ".join(parts)
		if hs.has("target") and not parts.is_empty():
			line += "   (to %d)" % int(hs["target"])
		_mode_label.text = mm.hud_status() + ("\n" + line if line != "" else "")
		_apply_highlight(str(hs.get("highlight", "")))
	if _center.text != "" and Time.get_ticks_msec() / 1000.0 > _center_until:
		_center.text = ""
	if _sub.text != "" and Time.get_ticks_msec() / 1000.0 > _sub_until:
		_sub.text = ""


## Pulses one meter on the local player's card (tutorial: "stamina", "cooldown", "hype").
func _apply_highlight(which: String) -> void:
	if not cards.has(player_index):
		return
	var c: Dictionary = cards[player_index]
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 7.0)
	var on := Color(1.0 + 0.6 * pulse, 1.0 + 0.6 * pulse, 1.0 + 0.2 * pulse)
	for key in ["st", "hype", "hype_l"]:
		(c[key] as CanvasItem).modulate = Color.WHITE
	for prompt: CanvasItem in _ability_prompts.values():
		prompt.modulate = Color.WHITE
	match which:
		"stamina":
			(c["st"] as CanvasItem).modulate = on
		"hype":
			(c["hype"] as CanvasItem).modulate = on
			(c["hype_l"] as CanvasItem).modulate = on
		"cooldown":
			if _ability_prompts.has("ability1"):
				(_ability_prompts["ability1"] as CanvasItem).modulate = on




func callout(text: String, seconds := 1.4, color := Color(1, 0.92, 0.7)) -> void:
	_center.text = text
	_center.add_theme_color_override("font_color", color)
	_center_until = Time.get_ticks_msec() / 1000.0 + seconds
	_center.scale = Vector2(1.25, 1.25)
	_center.pivot_offset = _center.size * 0.5
	var tw := create_tween()
	tw.tween_property(_center, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Subtitle line (announcer / coach). Always shown when subtitles are on.
const SPEAKERS := {"barnaby": "Barnaby Bellows", "kendall": "Kendall", "granny": "Granny Haymaker"}


func subtitle(speaker: String, text: String, seconds := 3.0) -> void:
	var who := str(SPEAKERS.get(speaker, speaker.capitalize()))
	_sub.text = ("%s: %s" % [who, text]) if speaker != "" else text
	_sub_until = Time.get_ticks_msec() / 1000.0 + seconds
