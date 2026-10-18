class_name CampaignUI
extends RefCounted
## Self-contained widgets for the campaign screens (plain Godot controls; the shared UI theme
## library can replace these factories without touching screen logic). Every interactive
## widget is focusable (controller) and clickable (mouse); colour is never the only cue:
## node types and rarities always carry an icon shape AND a text label.

const BG := Color("#14111a")
const PANEL := Color("#211c2b")
const PANEL_HI := Color("#2e2740")
const INK := Color("#f2ece0")
const MUTED := Color("#a79fb5")
const ACCENT := Color("#ffb627")
const DANGER := Color("#ff5a4f")
const GOOD := Color("#4fe08a")
const RARITY_COLORS := {"otc": Color("#e8e8e8"), "prescription": Color("#5aa9ff"), "black_market": Color("#9b8cff"), "banned": Color("#ff4f4f")}
const RARITY_SHAPES := {"otc": "circle", "prescription": "diamond", "black_market": "square", "banned": "cross"}
const NODE_COLORS := {"fight": Color("#ff7a59"), "elite": Color("#ffb627"), "event": Color("#5ad1ff"), "shop": Color("#7bed9f"),
	"rest": Color("#ff9ff3"), "mystery": Color("#c8b6ff"), "treasure": Color("#ffd166"), "boss": Color("#ff4f4f"), "unknown": Color("#6c6378")}
const NODE_NAMES := {"fight": "FIGHT", "elite": "ELITE", "event": "EVENT", "shop": "SHOP", "rest": "REST", "mystery": "?", "treasure": "TREASURE",
	"boss": "BOSS", "unknown": "???"}
const RISK_NAMES := {"safe": "SAFE", "risky": "RISKY", "gamble": "GAMBLE", "costly": "COSTLY"}
const RISK_COLORS := {"safe": Color("#4fe08a"), "risky": Color("#ffb627"), "gamble": Color("#c8b6ff"), "costly": Color("#ff9f6b")}

static var _fonts := {}


static func font(weight := "700") -> Font:
	if not _fonts.has(weight):
		var path := "res://assets/fonts/BarlowCondensed-%s.woff2" % weight
		if weight in ["400", "600"]:
			path = "res://assets/fonts/Barlow-%s.woff2" % weight
		_fonts[weight] = load(path) if ResourceLoader.exists(path) else null
	return _fonts[weight]


static func label(text: String, size := 22, color := INK, weight := "600") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	var f := font(weight)
	if f:
		l.add_theme_font_override("font", f)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func title(text: String, size := 54) -> Label:
	var l := label(text, size, ACCENT, "900")
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


## A short label for a row (HBox): no wrapping - a wrapping label in a row gets no width of its
## own and shrinks to one letter per line.
static func inline_label(text: String, size := 22, color := INK, weight := "600") -> Label:
	var l := label(text, size, color, weight)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


static func style(color: Color, border := Color(0, 0, 0, 0), width := 0, radius := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func panel(color := PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style(color))
	return p


## A focusable button with clear focus/hover states. `on_press` receives no arguments.
static func button(text: String, on_press: Callable = Callable(), size := 24, accent := ACCENT) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", size)
	var f := font("700")
	if f:
		b.add_theme_font_override("font", f)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_focus_color", BG)
	b.add_theme_color_override("font_hover_color", BG)
	b.add_theme_color_override("font_pressed_color", BG)
	b.add_theme_color_override("font_hover_pressed_color", BG)
	b.add_theme_color_override("font_disabled_color", MUTED.darkened(0.3))
	b.add_theme_stylebox_override("normal", style(PANEL_HI, accent.darkened(0.4), 2))
	b.add_theme_stylebox_override("hover", style(accent.lightened(0.15), accent, 2))
	b.add_theme_stylebox_override("focus", style(accent, Color.WHITE, 3))
	b.add_theme_stylebox_override("pressed", style(accent.darkened(0.15), accent, 2))
	b.add_theme_stylebox_override("disabled", style(PANEL.darkened(0.2), PANEL_HI, 1))
	b.custom_minimum_size = Vector2(0, 48)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


## A large focusable card (pick/shop/rest option). Its content is a VBox of labels that ignore
## the mouse, so the whole card is one click/press target; focus = thick bright border (the
## background stays dark so coloured text keeps its contrast).
static func card(width := 340.0, height := 280.0, accent := ACCENT) -> Array:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(width, height)
	# keeps its height in a row that fills the screen (a stretched card was mostly empty space)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", style(PANEL_HI, accent.darkened(0.45), 2, 14))
	b.add_theme_stylebox_override("hover", style(PANEL_HI.lightened(0.06), accent.lightened(0.1), 4, 14))
	b.add_theme_stylebox_override("focus", style(PANEL_HI.lightened(0.1), Color.WHITE, 6, 14))
	b.add_theme_stylebox_override("pressed", style(PANEL_HI.lightened(0.12), accent, 6, 14))
	b.add_theme_stylebox_override("disabled", style(PANEL.darkened(0.25), PANEL_HI, 1, 14))
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	b.add_child(m)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	return [b, v]


## Fills a card's VBox with an owned-item description (supplement, technique or side effect).
static func describe_item(v: VBoxContainer, cat: CampaignCatalog, id: String, extra: Array = []) -> void:
	var d := cat.item(id)
	var kind := str(d.get("type", "supplement"))
	var tag := HBoxContainer.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_constant_override("separation", 8)
	var shape := "circle"
	var col := INK
	var tag_text := ""
	match kind:
		"technique":
			shape = "triangle"
			col = GOOD
			var build := str(cat.builds.get(str(d.get("build", "")), {}).get("name", ""))
			tag_text = "TECHNIQUE" + ((" · " + build.to_upper()) if build != "" else "")
		"side_effect":
			shape = "cross"
			col = DANGER
			tag_text = "SIDE EFFECT"
		_:
			var r := str(d.get("rarity", "otc"))
			shape = str(RARITY_SHAPES.get(r, "circle"))
			col = RARITY_COLORS.get(r, INK)
			tag_text = rarity_text(r) + (" · CONSUMABLE" if bool(d.get("consumable", false)) else "")
	var icon := ShapeIcon.new(shape, col)
	tag.add_child(icon)
	# a wrapping label in a row needs the row's width (else it shrinks to one letter per line)
	var tl := _quiet(label(tag_text, 17, col, "700"))
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.add_child(tl)
	v.add_child(tag)
	v.add_child(_quiet(label(str(d.get("name", id)), 30, INK, "900")))
	if str(d.get("effect", "")) != "":
		v.add_child(_quiet(label(str(d["effect"]), 20, INK, "600")))
	if str(d.get("side_effect", "")) != "":
		v.add_child(_quiet(label("Drawback: %s" % d["side_effect"], 18, DANGER, "600")))
	for line in extra:
		if typeof(line) == TYPE_ARRAY:
			v.add_child(_quiet(label(str(line[0]), 18, line[1] if (line as Array).size() > 1 else MUTED, "700")))
		else:
			v.add_child(_quiet(label(str(line), 18, MUTED, "600")))
	if str(d.get("label", "")) != "":
		var fl := _quiet(label("\"%s\"" % d["label"], 16, MUTED, "400"))
		v.add_child(fl)


static func _quiet(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Root layout for a full-screen campaign screen: background + margin + vbox. Returns the vbox.
static func scaffold(screen: Control, heading: String, sub := "") -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 36)
	screen.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	var run_flow = screen.get("flow")
	if run_flow is CampaignFlow and run_flow.ctrl != null and not run_flow.ctrl.state.is_empty():
		v.add_child(run_status(run_flow))
	if heading != "":
		var heading_label := title(heading)
		heading_label.name = "Heading"
		v.add_child(heading_label)
	if sub != "":
		v.add_child(label(sub, 22, MUTED))
	# online party runs: who is deciding what, the Captain, the vote (CoopFlow keeps it current)
	var fl = screen.get("flow")
	if fl is CampaignFlow and (fl as CampaignFlow).is_party():
		var strip := label((fl as CampaignFlow).party_text(), 18, ACCENT, "700")
		strip.name = "PartyStrip"
		v.add_child(strip)
		screen.set_meta("party_strip", strip)
	return v


## Persistent information used to weigh choices: current health, money and carried build.
static func run_status(flow: CampaignFlow) -> Control:
	var ctrl := flow.ctrl
	var player := ctrl.player(flow.me)
	var bar := panel(Color("#24282e"))
	bar.name = "RunStatus"
	var columns := VBoxContainer.new()
	columns.add_theme_constant_override("separation", 5)
	bar.add_child(columns)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 28)
	columns.add_child(row)
	row.add_child(inline_label(fighter_name(ctrl.catalog, str(player.get("fighter", ""))).to_upper(), 26, ACCENT, "900"))
	var hp := ceili(float(player.get("hp", 0)))
	row.add_child(inline_label("HP %d / %d" % [hp, ceili(ctrl.max_hp(player))], 25, GOOD if hp > ctrl.max_hp(player) * 0.5 else DANGER, "700"))
	row.add_child(inline_label("SCRIP %d" % int(player.get("scrip", 0)), 25, ACCENT))
	row.add_child(inline_label("HYPE %d" % int(player.get("hype_carry", 0)), 25))
	row.add_child(inline_label("ACT %d" % int(ctrl.state.get("act", 1)), 25, MUTED))
	var build: PackedStringArray = []
	for item in player.get("supplements", []):
		build.append(ctrl.catalog.item_name(str(item["id"])))
	for item in player.get("techniques", []):
		build.append(ctrl.catalog.item_name(str(item)))
	for item in player.get("side_effects", []):
		build.append("! " + ctrl.catalog.item_name(str(item)))
	var inventory := label("BUILD  " + (" · ".join(build) if not build.is_empty() else "No supplements yet"), 18, MUTED)
	inventory.max_lines_visible = 2
	inventory.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	inventory.tooltip_text = "\n".join(build)
	columns.add_child(inventory)
	return bar


## Party runs: after a decision was sent to the party's host, the screen waits for the host's
## answer (the shared run then refreshes it): its buttons are disabled and `msg` says so.
static func wait_for_party(screen: Control, msg: Label) -> void:
	var stack: Array = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is BaseButton:
			(n as BaseButton).disabled = true
			(n as BaseButton).focus_mode = Control.FOCUS_NONE
		stack.append_array(n.get_children())
	if msg != null and is_instance_valid(msg):
		msg.text = "Sent - waiting for the party's host..."
		msg.add_theme_color_override("font_color", MUTED)


static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.focus_mode = Control.FOCUS_ALL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.follow_focus = true
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


## Links a list of controls vertically (or horizontally) for controller focus, wrapping around.
static func chain_focus(ctrls: Array, vertical := true) -> void:
	var live := []
	for c in ctrls:
		if c is Control and (c as Control).focus_mode != Control.FOCUS_NONE:
			live.append(c)
	for i in live.size():
		var a: Control = live[i]
		var prev: Control = live[(i - 1 + live.size()) % live.size()]
		var nxt: Control = live[(i + 1) % live.size()]
		if vertical:
			a.focus_neighbor_top = a.get_path_to(prev)
			a.focus_neighbor_bottom = a.get_path_to(nxt)
		else:
			a.focus_neighbor_left = a.get_path_to(prev)
			a.focus_neighbor_right = a.get_path_to(nxt)


## First enabled, focusable control in the list (or null).
static func first_enabled(ctrls: Array) -> Control:
	for c in ctrls:
		if c is BaseButton and (c as BaseButton).disabled:
			continue
		if c is Control and (c as Control).focus_mode != Control.FOCUS_NONE:
			return c
	return null


static func rarity_text(r: String) -> String:
	return str(CampaignCatalog.RARITY_NAMES.get(r, r)).to_upper()


static func fmt_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [int(s / 60.0), s % 60]


static func fighter_name(cat: CampaignCatalog, fid: String) -> String:
	return str(cat.fighter_info(fid).get("name", fid))


## Leaves the campaign screens for the game's menu (whichever the shell provides).
static func leave_campaign() -> void:
	if App.stack.size() > 1:
		# Called from on_back(): do not dispatch back into the same handler again.
		App.pop()
		return
	for s in ["main_menu", "title"]:
		if App.has_screen(s):
			App.goto(s)
			return


## In-screen modal (self-contained: no dependency on a shared dialog screen). buttons =
## [{label, id}]; the callback receives the chosen id ("" when cancelled with Back/Esc via
## close_modal). Focus is trapped inside the modal while it is open.
static func confirm(host: Control, heading: String, body: String, buttons: Array, callback: Callable = Callable()) -> Control:
	close_modal(host, false)
	var ov := Modal.new()
	ov.callback = callback
	host.add_child(ov)
	ov.build(heading, body, buttons)
	return ov


## Closes an open modal on `host` (cancel). Returns true if there was one — screens call this
## first in on_back() so Back/Esc closes the modal instead of leaving the screen.
static func close_modal(host: Control, notify := true) -> bool:
	for c in host.get_children():
		if c is Modal and not (c as Modal).closing:
			(c as Modal).cancel(notify)
			return true
	return false


static func has_modal(host: Control) -> bool:
	for c in host.get_children():
		if c is Modal and not (c as Modal).closing:
			return true
	return false


class Modal:
	extends Control
	var callback: Callable
	var closing := false
	var _buttons: Array = []
	var _covered: Array = []

	func build(heading: String, body: String, buttons: Array) -> void:
		for sibling in get_parent().get_children():
			if sibling != self and sibling is Control:
				_covered.append([sibling, sibling.focus_behavior_recursive, sibling.mouse_behavior_recursive])
				sibling.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
				sibling.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.66)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(center)
		var p := CampaignUI.panel(CampaignUI.PANEL_HI)
		p.custom_minimum_size = Vector2(760, 0)
		center.add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 16)
		p.add_child(v)
		v.add_child(CampaignUI.label(heading, 38, CampaignUI.ACCENT, "900"))
		if body != "":
			v.add_child(CampaignUI.label(body, 22))
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_theme_constant_override("separation", 12)
		v.add_child(row)
		for b in buttons:
			var btn := CampaignUI.button(str(b.get("label", "OK")), _choose.bind(str(b.get("id", "ok"))), 24,
				CampaignUI.DANGER if bool(b.get("danger", false)) else CampaignUI.ACCENT)
			row.add_child(btn)
			_buttons.append(btn)
		if _buttons.is_empty():
			var ok := CampaignUI.button("OK", _choose.bind("ok"), 24)
			row.add_child(ok)
			_buttons.append(ok)
		CampaignUI.chain_focus(_buttons, false)
		for bb in _buttons:
			var bt: Button = bb
			bt.focus_neighbor_top = bt.get_path_to(bt)
			bt.focus_neighbor_bottom = bt.get_path_to(bt)
			bt.focus_next = bt.focus_neighbor_right
			bt.focus_previous = bt.focus_neighbor_left
		(_buttons[0] as Button).call_deferred("grab_focus")

	func _uncover() -> void:
		for entry in _covered:
			if is_instance_valid(entry[0]):
				entry[0].focus_behavior_recursive = entry[1]
				entry[0].mouse_behavior_recursive = entry[2]
		_covered.clear()

	func _process(_dt: float) -> void:
		if closing or not is_inside_tree() or App.top_screen() != get_parent():
			return
		var focus := get_viewport().gui_get_focus_owner()
		if focus == null or not is_ancestor_of(focus):
			(_buttons[0] as Control).grab_focus()

	func _choose(id: String) -> void:
		if closing:
			return
		closing = true
		_uncover()
		queue_free()
		if callback.is_valid():
			callback.call(id)

	func cancel(notify := true) -> void:
		if closing:
			return
		closing = true
		_uncover()
		queue_free()
		if notify and callback.is_valid():
			callback.call("")


## Small vector shape (rarity/kind cue next to a text tag).
class ShapeIcon:
	extends Control
	var shape := "circle"
	var color := Color.WHITE

	func _init(s := "circle", c := Color.WHITE) -> void:
		shape = s
		color = c
		custom_minimum_size = Vector2(22, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.4
		match shape:
			"diamond":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), color)
			"square":
				draw_rect(Rect2(c - Vector2(r, r) * 0.85, Vector2(r, r) * 1.7), color)
			"cross":
				draw_line(c + Vector2(-r, -r), c + Vector2(r, r), color, 4.0, true)
				draw_line(c + Vector2(r, -r), c + Vector2(-r, r), color, 4.0, true)
			"triangle":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, r * 0.8), c + Vector2(-r, r * 0.8)]), color)
			_:
				draw_circle(c, r, color)


## Small vector icon for a node type (shape + colour; the caller adds the text label).
class NodeIcon:
	extends Control
	var kind := "fight"
	var lit := false

	func _init(k := "fight") -> void:
		kind = k
		custom_minimum_size = Vector2(44, 44)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var texture := UiIcons.tex("route_" + kind)
		if texture:
			var col: Color = CampaignUI.NODE_COLORS.get(kind, Color.WHITE)
			draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false, col if lit else col.darkened(0.35))
