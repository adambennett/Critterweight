class_name FightHud
extends Control
## In-match HUD: per-fighter cards (health with damage trail, stamina, hype/JUICE meter, ability
## cooldowns, status icons with text), round timer/pips, mode status, centre callouts and
## subtitles. Every essential cue has text, not only colour.
##
## 10-point scoring and the referee (MCH-07/08), presentation only, keyed off what the sim
## produced (local: mode.unlimited_health(); network mirror: hud_state "cards"), never the raw
## rules flags, so it runs unchanged on a NetHudMirror (no rig segments, no judge there):
##  * 10-point: every card's HP stack is hidden (cards[i]["hp_stack"]) and a team chip (letter +
##    colour) marks each fighter; under the timer a round line "ROUND n / N" (or the drawn-cards
##    note during a sudden death that follows them) and the judges' running totals from
##    hud_state.cards ("CARDS A–B 20–18 · 20–18 · 19–19").
##  * show_round_card(round_scored event): a between-rounds scorecard (the three judges' 10-x for
##    the round by name, the running totals, the round winner or "even round"), up through the
##    ROUND_END / intro break; show_decision(judges_decision event): the decision banner (winner or
##    draw, method, the three totals). Both sit above the subtitle band, below the centre callout.
##  * Referee (view_state.referee): the counted fighter's card status shows "DOWN · n", a stopped
##    fighter "STOPPED", and the local player being counted gets a hint with the wave-up time.
##
## Movesets (docs/design/MOVESET_COMBAT.md §9): the local player's strip shows one MoveCard per
## equipped move on its own input (name, HOLD / HOLD+AIM tag, charges, cooldown veil, a stamina-short
## state, the denied-press flash) and the Ultimate; the generic hints (guard / dodge / grapple) form
## a second row. The strip is rebuilt whenever the fighter's combat style or loadout changes
## (practice's Change moves; a network client's roster update), and is as tall as its rows, with the
## subtitles just above it. Every value comes from the fighter (cooldown_left, charges_left,
## stamina, loadout), so a NetHudMirror client renders the same cards as the host.

var sim: MatchSim
var player_index := 0
const TRAIL_HOLD := 0.6          ## seconds a hit's chunk stays lit on the health bar
const TRAIL_DRAIN := 0.5         ## then it drains this much of the bar per second
const ROUND_CARD_MIN := 2.0      ## seconds the between-rounds scorecard stays up at least
const ROUND_CARD_MAX := 8.0      ## ... and at most (it leaves when the next round starts)
const DECISION_SECONDS := 7.0    ## the decision banner (the results screen covers it at the bout end)
const DRAW_TO_SD_SECONDS := 3.5  ## a drawn decision that goes to sudden death clears for the fight

var cards := {}                  ## fighter index -> Dictionary of nodes
var _center: Label
var _sub: Label
var _timer: Label
var _mode_label: Label
var _round_label: Label          ## 10-point: "ROUND n / N" (or the drawn-cards note)
var _cards_label: Label          ## 10-point: the judges' running totals
var _ref_hint: Label             ## referee: the local player is being counted
var _round_panel: Control = null ## between-rounds scorecard (round_scored)
var _round_panel_shown := 0.0
var _banner: Control = null      ## the judges' decision (judges_decision)
var _banner_until := 0.0
var _banner_shown := 0.0
var _banner_draw := false
var _ten := false                ## the match is judged on 10-point cards (refreshed every frame)
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
var _moves_strip := false          ## the strip holds Movesets move cards (sized to its rows)
var _cards_sig := ""               ## combat style + loadout the strip was built for (rebuilt on change)


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
	_round_label = _label("", 32, _font_heavy)
	_round_label.name = "RoundLine"
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.visible = false
	_cards_label = _label("", 28, _font)
	_cards_label.name = "CardsLine"
	_cards_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cards_label.add_theme_color_override("font_color", UiTheme.WARM)
	_cards_label.visible = false
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
	mid.add_child(_round_label)
	mid.add_child(_cards_label)
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
	_ref_hint = _label("", 30, _font)
	_ref_hint.name = "RefereeHint"
	_ref_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ref_hint.offset_left = -760
	_ref_hint.offset_right = 760
	_ref_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ref_hint.add_theme_color_override("font_color", UiTheme.WARM)
	_ref_hint.add_theme_constant_override("outline_size", 10)
	_ref_hint.visible = false
	add_child(_ref_hint)
	_add_control_hints(n)
	_place_bottom_panels()


## Settings › Gameplay › Control hints: the core actions with the live bindings (players only).
## Movesets: the move cards (always shown) and, with control hints on, the generic actions.
func _add_control_hints(_n: int) -> void:
	if player_index < 0 or player_index >= sim.fighters.size() or sim.fighters[player_index].controller_kind != "player":
		return
	var fighter: Fighter = sim.fighters[player_index]
	_cards_sig = move_signature(fighter)
	if MovesUi.movesets(fighter):
		_add_move_strip(fighter)
		return
	var bar := HFlowContainer.new()
	bar.theme = UiTheme.get_theme()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("h_separation", 20)
	bar.alignment = FlowContainer.ALIGNMENT_CENTER
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
		var title := "JUICE" if slot == "juice" else ("Trick 1" if slot == "ability1" else "Trick 2")
		var prompt := CombatPrompt.new([MartialControls.action(slot, fighter.creature)], title, 40)
		bar.add_child(prompt)
		_ability_prompts[slot] = prompt
	var strip := _strip_panel()
	strip.add_child(bar)
	strip.offset_top = -116 if fighter.creature.tags.has("martial") else -78
	strip.offset_bottom = -16
	add_child(strip)
	if fighter.creature.tags.has("martial"):
		_sub.offset_top = -224
		_sub.offset_bottom = -124
	_hints = strip
	_hints_bottom = true


## Movesets: row one is a MoveCard per equipped move on its own input, then the Ultimate; row two
## (control hints on) guard, dodge and grapple. The strip grows upward to fit both rows.
func _add_move_strip(fighter: Fighter) -> void:
	var col := VBoxContainer.new()
	col.theme = UiTheme.get_theme()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	var row := HBoxContainer.new()
	row.name = "MoveCards"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 26)
	col.add_child(row)
	for i in mini(fighter.loadout.size(), Fighter.MOVE_SLOTS.size()):
		var pm: PoolMove = fighter.creature.pool.get(str(fighter.loadout[i]))
		if pm == null:
			continue
		var mslot: String = Fighter.MOVE_SLOTS[i]
		var card := MoveCard.new(str(MOVE_ACTIONS[i]), pm, mslot, 40)
		row.add_child(card)
		_ability_prompts[mslot] = card
	var ult := CombatPrompt.new([MartialControls.action("juice", fighter.creature)], "Ultimate", 40)
	ult.name = "UltimateCard"
	row.add_child(ult)
	_ability_prompts["juice"] = ult
	if bool(Settings.get_value("gameplay.tutorial_prompts")):
		var hints := HBoxContainer.new()
		hints.name = "BasicHints"
		hints.alignment = BoxContainer.ALIGNMENT_CENTER
		hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hints.add_theme_constant_override("separation", 26)
		for item in [["guard", "Guard (tap: parry)"], ["dodge", "Dodge"], ["grab", "Grapple"]]:
			var prompt := ButtonPrompt.new([item[0]], str(item[1]), 32)
			prompt.clickable = false
			hints.add_child(prompt)
		col.add_child(hints)
	var strip := _strip_panel()
	strip.name = "ControlHints"
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	strip.add_child(col)
	add_child(strip)
	_hints = strip
	_hints_bottom = true
	_moves_strip = true
	strip.minimum_size_changed.connect(_layout_bottom)
	_layout_bottom()


func _strip_panel() -> PanelContainer:
	var strip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.08, 0.75)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(8)
	strip.add_theme_stylebox_override("panel", sb)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	strip.offset_left = -850
	strip.offset_right = 850
	return strip


## The combat style, creature and loadout the local strip shows ("" for nobody).
static func move_signature(f: Fighter) -> String:
	if f == null or f.creature == null:
		return ""
	return "%s|%s|%s" % [f.combat_style, f.creature.id, ",".join(PackedStringArray(f.loadout))]


## Rebuilds the control-hint strip and its cards for the local fighter's current combat style and
## loadout (practice's Change moves calls it; FightHud also notices a change by itself, e.g. a
## network client's roster update).
func refresh_move_cards() -> void:
	if _hints != null and is_instance_valid(_hints):
		if _hints.get_parent() == self:
			remove_child(_hints)
		_hints.queue_free()
	_hints = null
	_hints_bottom = false
	_moves_strip = false
	_ability_prompts.clear()
	_add_control_hints(sim.fighters.size())
	set_bottom_inset(_bottom_inset)


## Movesets strip: as tall as its rows, 16 du above the bottom (plus the inset); the subtitles sit
## just above it, the referee hint and the scorecards above them.
func _layout_bottom() -> void:
	if not _moves_strip or _hints == null or not is_instance_valid(_hints) or _sub == null:
		return
	var h := maxf(62.0, _hints.get_combined_minimum_size().y)
	_hints.offset_bottom = -16.0 - _bottom_inset
	_hints.offset_top = _hints.offset_bottom - h
	_sub.offset_bottom = _hints.offset_top - 10.0
	_sub.offset_top = _sub.offset_bottom - 92.0
	_place_bottom_panels()


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
	_place_bottom_panels()
	_layout_bottom()


## The referee hint and the scorecard / decision panels sit just above the subtitle band (which
## moves with martial control hints and set_bottom_inset), below the centre callouts.
func _place_bottom_panels() -> void:
	if _sub == null:
		return
	var top := _sub.offset_top
	if _ref_hint:
		_ref_hint.offset_bottom = top - 6.0
		_ref_hint.offset_top = top - 52.0
	for p in [_round_panel, _banner]:
		if p != null and is_instance_valid(p):
			(p as Control).offset_bottom = top - 10.0
			(p as Control).offset_top = top - 10.0


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
	# 10-point only: the team letter + colour the judges' totals are read in (hidden otherwise)
	var chip := TeamChip.new(f.team, 34.0)
	chip.visible = false
	head.add_child(chip)
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
		"status": status, "lives": lives, "trail_v": 1.0, "big": big, "hp_stack": hp_stack, "chip": chip}


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
	var mm := sim.mode
	var hs: Dictionary = mm.hud_state() if mm else {}
	var ref := {}
	if mm:
		var rv = mm.view_state().get("referee", {})
		if typeof(rv) == TYPE_DICTIONARY:
			ref = rv
	_ten = ten_point_of(mm, hs)
	if player_index >= 0 and player_index < sim.fighters.size():
		var me: Fighter = sim.fighters[player_index]
		if me.controller_kind == "player" and move_signature(me) != _cards_sig:
			refresh_move_cards()
	for f in sim.fighters:
		if not cards.has(f.index):
			continue
		var c: Dictionary = cards[f.index]
		(c["box"] as Control).visible = not f.despawned
		if f.despawned:
			continue
		(c["hp_stack"] as Control).visible = not _ten
		var chip := c["chip"] as TeamChip
		chip.visible = _ten
		if chip.team != f.team:
			chip.set_team(f.team)
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
				if _ability_prompts[slot] is MoveCard:
					(_ability_prompts[slot] as MoveCard).update_from(f, sim.rules)
					continue
				var left := float(f.cooldown_left.get(slot, 0.0))
				var full := 1.0
				if f.creature.abilities.has(slot) or f.slot_move(str(slot)) != null:
					full = maxf(0.01, f.slot_cooldown(str(slot)))
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
		var ref_line := referee_status(f, ref)
		if ref_line != "":
			st_txt.push_front(ref_line)
		(c["status"] as Label).text = "  ".join(st_txt)
		(c["lives"] as Label).text = ("  x%d" % f.lives) if f.lives > 1 or (f.lives >= 0 and sim.rules.get("lives", 1) > 1) else ""
	_update_ten_point_lines(hs)
	_update_ref_hint(ref)
	_update_panels(hs)
	if mm:
		var rt := float(sim.rules.get("round_time", 99.0))
		_timer.text = "%d" % ceili(mm.round_timer) if rt > 0.0 else ""
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


## Pulses one meter on the local player's card (tutorial: "stamina", "cooldown", "hype";
## "cooldown:m3" pulses that Movesets card).
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
	if which.begins_with("cooldown:"):
		var p = _ability_prompts.get(which.substr(9))
		if p is CanvasItem:
			(p as CanvasItem).modulate = on
		return
	match which:
		"stamina":
			(c["st"] as CanvasItem).modulate = on
		"hype":
			(c["hype"] as CanvasItem).modulate = on
			(c["hype_l"] as CanvasItem).modulate = on
		"cooldown":
			if _ability_prompts.has("ability1"):
				(_ability_prompts["ability1"] as CanvasItem).modulate = on


# =====================================================================================
# 10-point scoring and the referee (presentation only; every key is optional)
# =====================================================================================

## True when the match is judged on 10-point cards: the local mode runs a judge
## (unlimited_health) or the replicated hud_state carries the judges' running totals (a network
## mirror has no judge of its own).
static func ten_point_of(mm: MatchMode, hs := {}) -> bool:
	if mm == null:
		return false
	if mm.unlimited_health():
		return true
	var h: Dictionary = hs if not hs.is_empty() else mm.hud_state()
	return typeof(h.get("cards", null)) == TYPE_DICTIONARY


func is_ten_point() -> bool:
	return sim != null and ten_point_of(sim.mode)


## Card status from view_state.referee: "DOWN · n" while the referee counts this fighter,
## "STOPPED" once he has waved it off for them (a KO already reads "KO" on the card).
static func referee_status(f: Fighter, ref: Dictionary) -> String:
	var cnt = ref.get("count", {})
	if typeof(cnt) == TYPE_DICTIONARY and int((cnt as Dictionary).get("fighter", -1)) == f.index:
		var n := int((cnt as Dictionary).get("n", 0))
		return "DOWN · %d" % n if n > 0 else "DOWN"
	if ref.has("stop") and int(ref["stop"]) == f.index and f.state != Fighter.State.KO:
		return "STOPPED"
	return ""


## The two judged teams, ascending (the order of every pair in cards and totals).
func duel_teams() -> Array:
	var t: Array = []
	for f in sim.fighters:
		if not f.despawned and not t.has(f.team):
			t.append(f.team)
	t.sort()
	while t.size() < 2:
		t.append(t.size())
	return t.slice(0, 2)


## Display name of a team: its fighters' names ("TEAM B" when nobody is listed).
func team_name(team: int) -> String:
	var names := PackedStringArray()
	for f in sim.fighters:
		if f.team == team and not f.despawned:
			names.append(f.display_name.to_upper())
	return " & ".join(names) if not names.is_empty() else "TEAM %s" % UiTheme.team_letter(team)


## "20–18 · 20–18 · 19–19": three [a, b] pairs in team order, or winner first when `first` is one
## of the two teams (how a decision is read out).
static func totals_text(totals: Array, teams: Array = [0, 1], first := -1) -> String:
	var flip := teams.size() == 2 and first >= 0 and first == int(teams[1])
	var parts := PackedStringArray()
	for p in totals:
		if typeof(p) != TYPE_ARRAY or (p as Array).size() < 2:
			continue
		var a := int(p[1]) if flip else int(p[0])
		var b := int(p[0]) if flip else int(p[1])
		parts.append("%d–%d" % [a, b])
	return " · ".join(parts)


## The big centre callout for a judges_decision: "SPLIT DECISION", "T.K.O.!", "DRAW", or the
## winner after a sudden death that followed drawn cards.
static func decision_callout(ev: Dictionary, winner_label := "") -> String:
	var m := str(ev.get("method", ""))
	if m == "TKO":
		return "T.K.O.!"
	if int(ev.get("winner", -1)) < 0:
		return "DRAW"
	if m.begins_with("Sudden Death"):
		return ("%s WINS!" % winner_label) if winner_label != "" else "SUDDEN DEATH!"
	return m.to_upper() if m != "" else "DECISION"


func _update_ten_point_lines(hs: Dictionary) -> void:
	_round_label.visible = _ten
	_cards_label.visible = _ten
	if not _ten or sim.mode == null:
		return
	var total := maxi(1, int(sim.rules.get("rounds", 3)))
	if bool(hs.get("sd", false)):
		_round_label.text = "DRAWN CARDS — SUDDEN DEATH"
	else:
		_round_label.text = "ROUND %d / %d" % [mini(sim.mode.round_index + 1, total), total]
	var cd = hs.get("cards", {})
	var n := 0
	var t: Array = []
	if typeof(cd) == TYPE_DICTIONARY:
		n = int((cd as Dictionary).get("n", 0))
		var tv = (cd as Dictionary).get("t", [])
		if typeof(tv) == TYPE_ARRAY:
			t = tv
	var teams := duel_teams()
	if n <= 0 or t.is_empty():
		_cards_label.text = "3 JUDGES · 10-POINT MUST"
	else:
		_cards_label.text = "CARDS %s–%s   %s" % [UiTheme.team_letter(int(teams[0])), UiTheme.team_letter(int(teams[1])), totals_text(t)]


## The local player is on the referee's count: when he waves them up, and that staying down
## recovers (RefereeRules.KD_DOWN_RECOVER).
func _update_ref_hint(ref: Dictionary) -> void:
	var cnt = ref.get("count", {})
	var mine := typeof(cnt) == TYPE_DICTIONARY and int((cnt as Dictionary).get("fighter", -1)) == player_index \
		and player_index >= 0 and player_index < sim.fighters.size() and sim.fighters[player_index].controller_kind == "player"
	_ref_hint.visible = mine
	if mine:
		var left := float((cnt as Dictionary).get("left", 0.0))
		_ref_hint.text = "Stay down to recover, or get up — the referee waves you up in %ds" % maxi(1, ceili(left))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _update_panels(hs: Dictionary) -> void:
	var now := _now()
	if _round_panel != null and is_instance_valid(_round_panel):
		var age := now - _round_panel_shown
		var live := sim.mode != null and sim.mode.phase == MatchMode.Phase.FIGHT
		if age > ROUND_CARD_MAX or (age > ROUND_CARD_MIN and live):
			_round_panel.queue_free()
			_round_panel = null
	if _banner != null and is_instance_valid(_banner):
		if _banner_draw and bool(hs.get("sd", false)):
			_banner_until = minf(_banner_until, _banner_shown + DRAW_TO_SD_SECONDS)
		if now > _banner_until:
			_banner.queue_free()
			_banner = null


## A themed panel anchored above the subtitle band (grows upward, centred).
func _bottom_panel(panel_name: String) -> PanelContainer:
	var p := UiTheme.panel("PanelSolid", 18.0)
	p.name = panel_name
	p.theme = UiTheme.get_theme()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(p)
	return p


## "[A] STOKE   [B] DREDGE": the team letters the pairs are read in (colour never the only cue).
func _legend(teams: Array) -> HBoxContainer:
	var row := UiTheme.hbox(UiTheme.GAP_M)
	for t in teams:
		var h := UiTheme.hbox(UiTheme.GAP_XS)
		h.add_child(TeamChip.new(int(t), 32.0))
		h.add_child(UiTheme.label(team_name(int(t)), "CaptionStrong"))
		row.add_child(h)
	return row


func _cell(text: String, variation: String) -> Label:
	var l := UiTheme.label(text, variation)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## The between-rounds scorecard for a round_scored event {round, teams, judges [[a,b] x3],
## winner, stoppage, totals [[A,B] x3]}: shown through the ROUND_END / intro break.
func show_round_card(ev: Dictionary) -> void:
	if _round_panel != null and is_instance_valid(_round_panel):
		_round_panel.queue_free()
	var teams: Array = ev.get("teams", [])
	if teams.size() != 2:
		teams = duel_teams()
	var rn := int(ev.get("round", 0))
	var p := _bottom_panel("RoundScorecard")
	var col := UiTheme.vbox(UiTheme.GAP_S)
	p.add_child(col)
	# one header row (round, its winner, the A/B legend) keeps the card short: the break shows the
	# fighters and the referee above it
	var head := UiTheme.hbox(UiTheme.GAP_L)
	var eb := UiTheme.label("ROUND %d %s" % [rn, "STOPPED" if bool(ev.get("stoppage", false)) else "SCORED"], "Eyebrow")
	eb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(eb)
	var w := int(ev.get("winner", -1))
	var res := UiTheme.hbox(UiTheme.GAP_XS)
	if w >= 0:
		res.add_child(TeamChip.new(w, 34.0))
		res.add_child(UiTheme.label("ROUND TO %s" % team_name(w), "H3"))
	else:
		res.add_child(UiTheme.label("EVEN ROUND", "H3"))
	head.add_child(res)
	var lg := _legend(teams)
	lg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lg.alignment = BoxContainer.ALIGNMENT_END
	head.add_child(lg)
	col.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(UiTheme.label("JUDGE", "Caption"))
	for j in RoundJudge.JUDGE_NAMES:
		grid.add_child(_cell(str(j), "CaptionStrong"))
	var js: Array = ev.get("judges", [])
	var tot: Array = ev.get("totals", [])
	grid.add_child(UiTheme.label("ROUND %d" % rn, "Body"))
	for j in 3:
		grid.add_child(_cell(totals_text([js[j]]) if j < js.size() else "–", "Value"))
	grid.add_child(UiTheme.label("TOTAL", "Body"))
	for j in 3:
		grid.add_child(_cell(totals_text([tot[j]]) if j < tot.size() else "–", "ValueGold"))
	col.add_child(grid)
	_round_panel = p
	_round_panel_shown = _now()
	_place_bottom_panels()


## The decision banner for a judges_decision event {winner (team | -1), method, totals, teams}:
## the winner (or DRAW), the method and the three totals (winner first). `round_no` names the
## round of a T.K.O.
func show_decision(ev: Dictionary, round_no := 0) -> void:
	if _round_panel != null and is_instance_valid(_round_panel):
		_round_panel.queue_free()
		_round_panel = null
	if _banner != null and is_instance_valid(_banner):
		_banner.queue_free()
	var teams: Array = ev.get("teams", [])
	if teams.size() != 2:
		teams = duel_teams()
	var w := int(ev.get("winner", -1))
	var m := str(ev.get("method", ""))
	var p := _bottom_panel("DecisionBanner")
	var col := UiTheme.vbox(UiTheme.GAP_XS)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(col)
	var eyebrow := "THE JUDGES' DECISION"
	if m == "TKO":
		eyebrow = "THE REFEREE STOPS IT"
	elif m.begins_with("Sudden Death"):
		eyebrow = "SUDDEN DEATH"
	elif w < 0:
		eyebrow = "THE CARDS ARE LEVEL"
	col.add_child(_cell(eyebrow, "Eyebrow"))
	# three short rows (eyebrow, who + how, the cards) so the referee's ceremony stays in view
	var who := UiTheme.hbox(UiTheme.GAP_L)
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_row := UiTheme.hbox(UiTheme.GAP_S)
	if w >= 0:
		name_row.add_child(TeamChip.new(w, 48.0))
		name_row.add_child(UiTheme.label("%s WINS" % team_name(w), "H2"))
	else:
		name_row.add_child(UiTheme.label("DRAW", "H2"))
	who.add_child(name_row)
	var how := m.to_upper() if m != "" else "DECISION"
	if m == "TKO":
		how = ("T.K.O. · ROUND %d" % round_no) if round_no > 0 else "T.K.O."
	var how_l := UiTheme.label(how, "H3")
	how_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(how_l)
	col.add_child(who)
	var tot: Array = ev.get("totals", [])
	var cards_row := UiTheme.hbox(UiTheme.GAP_M)
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	if not tot.is_empty():
		var lead := "CARDS AT THE STOPPAGE" if m == "TKO" else "CARDS"
		cards_row.add_child(UiTheme.label("%s   %s" % [lead, totals_text(tot, teams, w)], "Value"))
	if w >= 0:
		if not tot.is_empty():
			var note := UiTheme.label("(winner first)", "Caption")
			note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cards_row.add_child(note)
	else:
		cards_row.add_child(_legend(teams))
	if cards_row.get_child_count() > 0:
		col.add_child(cards_row)
	_banner = p
	_banner_shown = _now()
	_banner_until = _banner_shown + DECISION_SECONDS
	_banner_draw = w < 0
	_place_bottom_panels()


## Movesets: the Controls actions of loadout slots m1..m4 (the Classic Light/Heavy/Ability inputs).
const MOVE_ACTIONS := ["light", "heavy", "ability1", "ability2"]


## A move's name with how to use it when that is not a tap (prompts and lists outside the HUD,
## whose cards show the hold as a tag).
static func move_card_title(pm: PoolMove) -> String:
	match pm.hold:
		"charge":
			return "%s (hold)" % pm.display_name
		"sustain":
			return "%s (hold, aim)" % pm.display_name if pm.aim_turn > 0.0 else "%s (hold)" % pm.display_name
	return pm.display_name


## The local player's card of a loadout slot ("m1".."m4"), null when not shown.
func move_card(slot: String) -> MoveCard:
	var p = _ability_prompts.get(slot)
	if p == null or not is_instance_valid(p) or not (p is MoveCard):
		return null
	return p as MoveCard


## A move press that could not start (Fighter `move_denied`: cooldown or stamina): the card flashes.
func move_denied(slot: String, why: String) -> void:
	var p = _ability_prompts.get(slot)
	if p == null or not is_instance_valid(p):
		return
	if p is MoveCard:
		(p as MoveCard).flash_denied(why)
		return
	var c := p as CanvasItem
	c.modulate = Color(1.0, 0.35, 0.3) if why == "stamina" else Color(0.75, 0.75, 0.8)
	var tw := create_tween()
	tw.tween_property(c, "modulate", Color.WHITE, 0.35)


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
