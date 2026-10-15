class_name HubBoardMap
extends RefCounted
## The corkboard map by the roller door (HUB.md §1/§6): the Cannery's floor plan with the spaces
## you have found, where you are, the ten secrets as silhouettes (found ones named, hinted ones
## with Ludlow's hint) and Fast walk: after the first tour, HOLD A on a discovered space to walk
## straight there (a short fade). Mouse: hold the left button on it.

const HOLD_TIME := 0.6


## A button that fires `held` after being held down for HOLD_TIME (pad A, Enter or the mouse).
class HoldButton:
	extends UiButton
	signal held
	var hold_t := -1.0

	func _init(text_ := "") -> void:
		super(text_, "SubItem", "forward")
		button_down.connect(func() -> void: hold_t = 0.0)
		button_up.connect(func() -> void: hold_t = -1.0)

	func _process(dt: float) -> void:
		if hold_t < 0.0:
			return
		hold_t += dt
		queue_redraw()
		if hold_t >= HubBoardMap.HOLD_TIME:
			hold_t = -1.0
			held.emit()

	func _draw() -> void:
		super()
		if hold_t > 0.0:
			var w := size.x * clampf(hold_t / HubBoardMap.HOLD_TIME, 0.0, 1.0)
			draw_rect(Rect2(0, size.y - 8, w, 8), UiTheme.GOLD)


## The drawn floor plan.
class MapDraw:
	extends Control
	var state: HubState
	var player_pos := Vector3.ZERO
	var region := "cannery"

	func _draw() -> void:
		var spaces := HubLayout.SPACES
		var bounds := Rect2(-23, -20, 44, 37) if region == "cannery" else Rect2()
		if region != "cannery":
			for sid in spaces:
				var s: Dictionary = spaces[sid]
				if str(s["area"]) == region:
					bounds = (s["rect"] as Rect2).grow(3.0)
		var sc := minf(size.x / bounds.size.x, size.y / bounds.size.y)
		var off := (size - bounds.size * sc) * 0.5
		draw_rect(Rect2(Vector2.ZERO, size), Color("#b0844f"))
		var font: Font = load("res://assets/fonts/BarlowCondensed-700.woff2")
		for sid in spaces:
			var s: Dictionary = spaces[sid]
			if str(s["area"]) != region and not (region == "cannery" and sid == "crawlspace"):
				continue
			var r: Rect2 = s["rect"]
			var rr := Rect2(off + (r.position - bounds.position) * sc, r.size * sc)
			var found := state.discovered().has(sid)
			if bool(s.get("secret", false)) and not found:
				continue
			draw_rect(rr, Color("#efe6d2") if found else Color(0.3, 0.22, 0.12, 0.5))
			draw_rect(rr, Color("#5a3b22"), false, 3.0)
			var label := str(s["name"]).to_upper() if found else "?"
			draw_string(font, rr.position + Vector2(8, 30), label, HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 12, 28, Color("#23262e"))
		# the cage and the dock water
		if region == "cannery":
			var c := HubLayout.CAGE_CENTER
			draw_circle(off + (Vector2(c.x, c.z) - bounds.position) * sc, 3.0 * sc, Color(0.75, 0.22, 0.18, 0.35))
			draw_rect(Rect2(off + (Vector2(-23, -20) - bounds.position) * sc, Vector2(44, 1.4) * sc), Color("#2e6f8f"))
		# you are here
		var pp := off + (Vector2(player_pos.x, player_pos.z) - bounds.position) * sc
		draw_circle(pp, 11.0, Color("#ff3b3b"))
		draw_circle(pp, 5.0, Color.WHITE)


static func build(b: HubBoard, _p: Dictionary) -> void:
	b.frame("By the roller door", "The Cannery", 1500.0, false, "center")
	var st := b.hub_state()
	var mode := b.hub_mode()
	b.list.queue_free()
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.body_row.add_child(cols)
	var map := MapDraw.new()
	map.state = st
	map.custom_minimum_size = Vector2(760, 560)
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if mode:
		map.player_pos = mode.player().pos()
		var area := str(HubLayout.space(mode.current_space).get("area", "cannery"))
		map.region = area if area in ["basement", "roof", "pier"] else "cannery"
	cols.add_child(map)
	var right := FocusScroll.new(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	b.list = right
	var tour := 0
	for sid in HubLayout.TOUR:
		if st.discovered().has(sid):
			tour += 1
	b.section("Fast walk")
	if not st.tour_done():
		b.text_line("Walk every room once to unlock Fast walk (%d / %d)." % [tour, HubLayout.TOUR.size()], "BodyMuted")
	else:
		for sid in HubLayout.SPACES:
			if not st.discovered().has(sid):
				continue
			var hb := HoldButton.new("Hold: %s" % str(HubLayout.SPACES[sid]["name"]))
			hb.set_help(str(HubLayout.SPACES[sid]["name"]), "Hold to walk straight there.")
			hb.custom_minimum_size = Vector2(0, 60)
			hb.route = str(sid)
			hb.held.connect(func() -> void: _fast_walk(b, str(sid)))
			hb.pressed.connect(func() -> void: b.set_status("Hold the button to Fast walk.", "Caption"))
			right.content.add_child(hb)
	b.section("Secrets (%d / 10)" % st.secrets_found())
	for id in HubContent.secret_ids():
		var d := HubContent.secret(str(id))
		var txt := ""
		var variation := "BodyMuted"
		if st.has_secret(str(id)):
			txt = "✓  %s  —  %s" % [str(d.get("name", id)), str(HubLayout.space(str(d.get("where", ""))).get("name", ""))]
			variation = "Success"
		elif st.hint_given(str(id)):
			txt = "?  \"%s\"" % str(d.get("hint", ""))
			variation = "Body"
		else:
			txt = "?  ? ? ?"
		b.text_line(txt, variation)
	b.set_status("First tour %d / %d  ·  Ludlow drops one hint per visit about the nearest secret." % [tour, HubLayout.TOUR.size()])
	b.prompts.set_prompts([{"actions": ["ui_accept"], "text": "Hold: Fast walk"}, {"actions": ["ui_cancel"], "text": "Close", "call": b.close}])
	b.focus_first()


static func _fast_walk(b: HubBoard, sid: String) -> void:
	var mode := b.hub_mode()
	if mode == null:
		return
	if mode.fast_walk(mode.player(), sid):
		Audio.ui("ui_accept")
		App.clear_screens()
	else:
		Audio.ui("ui_error")
		b.set_status("Can't Fast walk right now.", "Warning")
