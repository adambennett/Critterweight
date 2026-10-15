class_name FightHud
extends Control
## In-match HUD: per-fighter cards (health with damage trail, stamina, hype/JUICE meter, ability
## cooldowns, status icons with text), round timer/pips, mode status, centre callouts and
## subtitles. Every essential cue has text, not only colour.

var sim: MatchSim
var player_index := 0
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
var _bottom: HBoxContainer


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
	_bottom = HBoxContainer.new()
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_theme_constant_override("separation", 16)
	_bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_bottom)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer = _label("99", 54, _font_heavy)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label = _label("", 24, _font)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if n <= 2:
		cards[sim.fighters[0].index] = _make_card(sim.fighters[0], n, _top, false)
		_top.add_child(mid)
		if n == 2:
			cards[sim.fighters[1].index] = _make_card(sim.fighters[1], n, _top, true)
	else:
		_top.add_child(mid)
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
	_sub.offset_top = -230 if n > 2 else -150
	_sub.offset_bottom = -170 if n > 2 else -70
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.add_theme_constant_override("outline_size", 10)
	_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_child(_sub)


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
	var w := 520.0 if big else 300.0
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 3)
	box.custom_minimum_size = Vector2(w, 0)
	parent.add_child(box)
	if right_align:
		box.alignment = BoxContainer.ALIGNMENT_BEGIN
	var team_col := TeamColors.color(f.team)
	var head := HBoxContainer.new()
	box.add_child(head)
	var name_l := _label(f.display_name.to_upper(), 30 if big else 22, _font_heavy)
	name_l.add_theme_color_override("font_color", team_col.lightened(0.3))
	head.add_child(name_l)
	var tag := _label(" (YOU)" if f.index == player_index else "", 20, _font)
	head.add_child(tag)
	var lives := _label("", 20, _font)
	head.add_child(lives)
	var hp_stack := Control.new()
	hp_stack.custom_minimum_size = Vector2(w, 26 if big else 18)
	box.add_child(hp_stack)
	var trail := _bar(w, 26 if big else 18, Color(1.0, 0.85, 0.85))
	hp_stack.add_child(trail)
	var hp := _bar(w, 26 if big else 18, Color(0.95, 0.27, 0.3), Color(0, 0, 0, 0))
	hp_stack.add_child(hp)
	var hp_text := _label("", 18 if big else 14, _font)
	hp_text.position = Vector2(8, 0)
	hp_stack.add_child(hp_text)
	var st := _bar(w * 0.7, 8, Color(0.35, 0.85, 0.55))
	box.add_child(st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var hype := _bar(w * 0.45, 12, Color(1.0, 0.62, 0.15))
	row.add_child(hype)
	var hype_l := _label("HYPE", 16, _font)
	row.add_child(hype_l)
	var cd1 := _label("", 16, _font)
	row.add_child(cd1)
	var cd2 := _label("", 16, _font)
	row.add_child(cd2)
	var status := _label("", 16, _font)
	box.add_child(status)
	return {"box": box, "hp": hp, "trail": trail, "hp_text": hp_text, "st": st, "hype": hype, "hype_l": hype_l,
		"cd1": cd1, "cd2": cd2, "status": status, "lives": lives, "trail_v": 1.0}


func _process(dt: float) -> void:
	if sim == null:
		return
	for f in sim.fighters:
		if not cards.has(f.index) or f.despawned:
			continue
		var c: Dictionary = cards[f.index]
		var frac := f.health_frac()
		(c["hp"] as ProgressBar).value = frac
		c["trail_v"] = maxf(frac, float(c["trail_v"]) - dt * 0.35) if float(c["trail_v"]) > frac else frac
		(c["trail"] as ProgressBar).value = c["trail_v"]
		(c["hp_text"] as Label).text = "%d" % ceili(f.health) if not f.is_out() else ("KO" if f.state == Fighter.State.KO else "DOWN")
		(c["st"] as ProgressBar).value = f.stamina / f.max_stamina
		(c["hype"] as ProgressBar).value = f.hype / 100.0
		var juiced := f.time < f.juiced_until
		(c["hype_l"] as Label).text = "JUICED!" if juiced else ("JUICE READY [%s]" % Controls.prompt_for("juice") if f.hype >= 100.0 else "HYPE")
		(c["cd1"] as Label).text = _cd_text(f, "ability1", "A1")
		(c["cd2"] as Label).text = _cd_text(f, "ability2", "A2")
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
		_timer.text = "%d" % ceili(mm.round_timer) if rt > 0.0 else "--"
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
	for key in ["st", "hype", "cd1", "hype_l"]:
		(c[key] as CanvasItem).modulate = Color.WHITE
	match which:
		"stamina":
			(c["st"] as CanvasItem).modulate = on
		"hype":
			(c["hype"] as CanvasItem).modulate = on
			(c["hype_l"] as CanvasItem).modulate = on
		"cooldown":
			(c["cd1"] as CanvasItem).modulate = on


func _cd_text(f: Fighter, slot: String, short: String) -> String:
	if not f.creature.abilities.has(slot):
		return ""
	var left := float(f.cooldown_left.get(slot, 0.0))
	return "%s %.0f" % [short, ceilf(left)] if left > 0.0 else "%s ready" % short


func callout(text: String, seconds := 1.4, color := Color(1, 0.92, 0.7)) -> void:
	_center.text = text
	_center.add_theme_color_override("font_color", color)
	_center_until = Time.get_ticks_msec() / 1000.0 + seconds
	_center.scale = Vector2(1.25, 1.25)
	_center.pivot_offset = _center.size * 0.5
	var tw := create_tween()
	tw.tween_property(_center, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Subtitle line (announcer / coach). Always shown when subtitles are on.
func subtitle(speaker: String, text: String, seconds := 3.0) -> void:
	_sub.text = ("%s: %s" % [speaker, text]) if speaker != "" else text
	_sub_until = Time.get_ticks_msec() / 1000.0 + seconds
