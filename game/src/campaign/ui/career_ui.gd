class_name CareerUi
extends RefCounted
## Shared pieces of the Career screens (CMP-08), built from the UiTheme kit (theme type variations,
## Caption 28 du as the smallest text) like the rest of the menus, never the older CampaignUI kit.
## Colour is never the only cue: danger tags, results and condition levels are words; level pips
## and the popularity bar are shapes with their numbers written beside them.

const TAB_ICONS := {"camp": "practice", "offers": "fight", "gym": "settings", "history": "trophy"}


## A focusable card (ONE focus stop) holding any content: card style, gold focus border + chevron +
## 2% scale (focus never relies on colour alone), hover focuses, A / Enter / click emits
## `activated`. `route` names it for screens and tests; help_title/help_text feed HelpPanel.
## `enabled = false` keeps it focusable (readable) but A only plays the error sound and emits
## `refused`; `inert` cards (history, news) do nothing on A.
class ActionCard:
	extends PanelContainer

	signal activated
	signal refused

	var route := ""
	var help_title := ""
	var help_text := ""
	var enabled := true
	var inert := false
	var body: VBoxContainer
	var _tween: Tween

	func _init(route_ := "", min_size := Vector2.ZERO) -> void:
		route = route_
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size = min_size
		add_theme_stylebox_override("panel", UiTheme.style("card"))
		body = UiTheme.vbox(4)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(body)

	func _ready() -> void:
		mouse_entered.connect(_on_mouse_entered)
		resized.connect(_on_resized)
		_on_resized()

	func set_enabled(on: bool) -> void:
		enabled = on
		body.modulate = Color(1, 1, 1, 1.0 if on else 0.62)

	func _on_resized() -> void:
		pivot_offset = size * 0.5

	func _on_mouse_entered() -> void:
		if not has_focus() and is_visible_in_tree() and focus_mode != Control.FOCUS_NONE:
			grab_focus()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				if not has_focus():
					grab_focus()
				activate()
				accept_event()
			return
		if event.is_action_pressed("ui_accept", false, true):
			activate()
			accept_event()

	## What A does (also callable by tests and the mouse).
	func activate() -> void:
		if inert:
			return
		if not enabled:
			Audio.sfx("ui_error")
			refused.emit()
			return
		Audio.sfx("ui_accept")
		activated.emit()

	func _notification(what: int) -> void:
		match what:
			NOTIFICATION_FOCUS_ENTER:
				add_theme_stylebox_override("panel", UiTheme.style("card_focus"))
				if UiNav.user_initiated():
					Audio.sfx("ui_move")
				_animate(1.02)
				queue_redraw()
			NOTIFICATION_FOCUS_EXIT:
				add_theme_stylebox_override("panel", UiTheme.style("card"))
				_animate(1.0)
				queue_redraw()

	func _animate(target: float) -> void:
		if _tween and _tween.is_valid():
			_tween.kill()
		if UiTheme.reduce_motion() or not is_inside_tree():
			scale = Vector2.ONE * target
			return
		_tween = create_tween()
		_tween.tween_property(self, "scale", Vector2.ONE * target, UiTheme.ANIM_FAST).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		if not has_focus():
			return
		# chevron in the left padding: a shape cue besides the gold border
		var s := 8.0
		var cx := 9.0
		var cy := minf(size.y * 0.5, 34.0)
		draw_colored_polygon(PackedVector2Array([Vector2(cx - s * 0.55, cy - s), Vector2(cx + s * 0.75, cy), Vector2(cx - s * 0.55, cy + s)]), UiTheme.GOLD_HI)


## Popularity 0..100 as a bar with the promotion gates marked (CR: marks at 24, 50, 74, 92). The
## number and its label are written next to it by the screen (the bar is never the only cue).
class PopBar:
	extends Control

	var pop := 0.0
	var marks: Array = []

	func _init(pop_ := 0.0, marks_: Array = []) -> void:
		pop = pop_
		marks = marks_
		custom_minimum_size = Vector2(260, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var h := size.y
		var track := Rect2(Vector2(0, h * 0.25), Vector2(size.x, h * 0.5))
		draw_rect(track, UiTheme.BG_DEEP)
		draw_rect(Rect2(track.position, Vector2(size.x * clampf(pop / 100.0, 0.0, 1.0), track.size.y)), UiTheme.GOLD)
		draw_rect(track, UiTheme.LINE, false, 2.0)
		for m in marks:
			var x := size.x * clampf(float(m) / 100.0, 0.0, 1.0)
			# a notch through the bar: reached gates are solid, the rest outlined
			var reached := pop >= float(m)
			draw_line(Vector2(x, 0), Vector2(x, h), UiTheme.TEXT if reached else UiTheme.MUTED, 3.0 if reached else 2.0)


# --- small builders -----------------------------------------------------------------------------

## "4" / "4.5" (one decimal at most, whole numbers without one).
static func num(x: float) -> String:
	var r := snappedf(x, 0.1)
	return str(int(r)) if is_equal_approx(r, roundf(r)) else "%.1f" % r


static func signed(x: float) -> String:
	return ("+" if x >= 0.0 else "-") + num(absf(x))


## "1:34" (seconds into a round).
static func clock(seconds: float) -> String:
	var s := maxi(0, int(round(seconds)))
	return "%d:%02d" % [int(s / 60.0), s % 60]


## "19 Oct 2026, 21:40" in local time ("" for 0).
static func saved_text(unix: int) -> String:
	if unix <= 0:
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%d %s %d, %02d:%02d" % [int(d["day"]), months[clampi(int(d["month"]) - 1, 0, 11)], int(d["year"]), int(d["hour"]), int(d["minute"])]


## A key figure: CAPTION / Value / caption.
static func kpi(title: String, value: String, sub := "", value_variation := "Value") -> VBoxContainer:
	var v := UiTheme.vbox(0)
	v.add_child(UiTheme.label(title.to_upper(), "Eyebrow"))
	var vl := UiTheme.label(value, value_variation)
	v.add_child(vl)
	if sub != "":
		v.add_child(UiTheme.label(sub, "Caption"))
	return v


## The theme variation of a danger tag (the WORD is the cue; colour only reinforces it).
static func danger_variation(tag: String) -> String:
	match tag:
		"FAVOURED":
			return "Success"
		"UNDERDOG":
			return "Warning"
		"LONG SHOT":
			return "Danger"
	return "BodyStrong"


static func result_variation(result: String) -> String:
	match result:
		"win":
			return "Success"
		"loss":
			return "Danger"
	return "BodyStrong"


static func condition_variation(level: String) -> String:
	match level:
		"injured":
			return "Danger"
		"hurt":
			return "Warning"
	return "BodyStrong"


## Level pips (5 segments: filled = bought, outlined = not yet).
static func pips(level: int, max_level: int) -> StatSegments:
	var s := StatSegments.new()
	s.segments = maxi(1, max_level)
	s.fraction = clampf(float(level) / float(maxi(1, max_level)), 0.0, 1.0)
	s.custom_minimum_size = Vector2(150, 24)
	return s


## "UNANIMOUS DECISION · 30-27 · 29-28 · 29-28" or "T.K.O. · ROUND 2 · 1:34" from an apply_result
## summary (or a history entry): totals are [me, opp] per judge, shown winner first.
static func method_line(s: Dictionary) -> String:
	var m := str(s.get("method", ""))
	var won := bool(s.get("won", false))
	var draw := bool(s.get("draw", false))
	if m == "TKO" or m.begins_with("TKO"):
		var t := "T.K.O. · ROUND %d" % int(s.get("round", 1))
		if float(s.get("time", 0.0)) > 0.0:
			t += " · " + clock(float(s.get("time", 0.0)))
		return t
	if m == "KO":
		return "K.O. · ROUND %d" % int(s.get("round", 1))
	var parts := [m.to_upper()]
	for p in s.get("totals", []):
		if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
			var a := int(p[0])
			var b := int(p[1])
			parts.append("%d-%d" % ([a, b] if won or draw else [b, a]))
	return " · ".join(PackedStringArray(parts))


## The six stats with the overall rating; `last` = the stat trained last week (shows its gain).
static func stats_box(ctrl: CareerController) -> VBoxContainer:
	var v := UiTheme.vbox(8)
	var head := UiTheme.hbox(UiTheme.GAP_S)
	head.add_child(UiTheme.label("STATS", "Eyebrow"))
	head.add_child(UiTheme.spacer())
	head.add_child(UiTheme.label("OVERALL", "Caption"))
	head.add_child(UiTheme.label(str(ctrl.rating()), "ValueGold"))
	v.add_child(head)
	var last: Dictionary = ctrl.state.get("last_train", {})
	for r in ctrl.stat_rows():
		var d: Dictionary = r
		var lbl := str(d["short"])
		if str(last.get("focus", "")) == str(d["id"]) and float(last.get("gain", 0.0)) > 0.0 and int(last.get("week", -1)) == int(ctrl.state["week"]) - 1:
			lbl += " +" + num(float(last["gain"]) * 100.0)
		var bar := StatBar.new(lbl, float(d["value"]), str(int(d["points"])), UiTheme.GOLD)
		bar.set_meta("stat", str(d["id"]))
		v.add_child(bar)
	return v


## Head / body / legs with words for each level, plus the fight-night line and the healing rate.
static func condition_box(ctrl: CareerController) -> VBoxContainer:
	var cond := ctrl.condition()
	var v := UiTheme.vbox(6)
	v.add_child(UiTheme.label("CONDITION", "Eyebrow"))
	var row := UiTheme.hbox(UiTheme.GAP_M)
	for r in cond["regions"]:
		var d: Dictionary = r
		var cell := UiTheme.vbox(0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(UiTheme.label(str(d["label"]), "Caption"))
		cell.add_child(UiTheme.label(str(d["text"]), condition_variation(str(d["level"]))))
		row.add_child(cell)
	v.add_child(row)
	var line := "%s Heals %s a week (%s resting)." % [str(cond["line"]), num(float(cond["heal_week"])), num(float(cond["heal_rest"]))]
	v.add_child(UiTheme.label(line, "Caption", true))
	return v
