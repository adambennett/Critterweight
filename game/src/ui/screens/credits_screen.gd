extends Screen
## Credits ("credits"), data-driven from res://assets/ui/credits.json, with a Notices tab carrying
## every required licence text: the fonts' OFL texts (embedded in the JSON) and the engine's own
## licence plus its third-party component list and licence texts, read from the running engine
## (Engine.get_license_text / get_copyright_info / get_license_info), so they always match the binary.
## Credits roll slowly when left alone (not with Reduce motion); up/down, the right stick and the
## mouse wheel scroll; LB/RB switch tabs.

const DATA := "res://assets/ui/credits.json"

var _tabs: TabStrip
var _text: ScrollText
var _idle := 0.0
var _data := {}


func on_enter(p: Dictionary) -> void:
	MenuBackdrop.ensure()
	add_backdrop_gradient(0.97, 0.85)
	var f := build_frame("The people and the parts", "Credits")
	(f["prompts"] as PromptBar).set_prompts([{"actions": ["ui_up", "ui_down"], "text": "Scroll"},
		{"actions": ["ui_tab_prev", "ui_tab_next"], "text": "Credits / Notices"},
		{"actions": ["ui_cancel"], "text": "Back", "call": App.back}])
	var body: VBoxContainer = f["body"]
	_tabs = TabStrip.new()
	_tabs.setup(["Credits", "Notices"], ["credits", "notices"], 1 if str(p.get("tab", "")) == "notices" else 0)
	_tabs.tab_changed.connect(func(_i: int) -> void: _show())
	body.add_child(_tabs)
	var row := UiTheme.hbox(0)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	row.add_child(UiTheme.spacer())
	_text = ScrollText.new()
	_text.custom_minimum_size = Vector2(1180, 0)
	_text.size_flags_horizontal = Control.SIZE_FILL
	_text.size_flags_stretch_ratio = 3.0
	_text.help_title = "Credits"
	row.add_child(_text)
	row.add_child(UiTheme.spacer())
	_data = _load()
	_show()
	play_intro()


func default_focus() -> Control:
	return _text


func _load() -> Dictionary:
	var txt := FileAccess.get_file_as_string(DATA)
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		Log.e("ui", "credits: %s missing or invalid" % DATA)
		return {"title": "CRITTERWEIGHT", "sections": [], "notices": []}
	return parsed


func current_tab() -> String:
	return _tabs.current_id()


func text_length() -> int:
	return _text.rich.get_parsed_text().length()


func _show() -> void:
	_idle = 0.0
	var r := _text.rich
	r.clear()
	if _tabs.current_id() == "notices":
		_notices(r)
	else:
		_credits(r)
	_text.scroll.scroll_vertical = 0


func _credits(r: RichTextLabel) -> void:
	r.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	r.push_font(UiTheme.font("display"), UiTheme.size("h1"))
	r.push_color(UiTheme.TEXT)
	r.add_text(str(_data.get("title", "CRITTERWEIGHT")) + "\n")
	r.pop()
	r.pop()
	r.push_font(UiTheme.font("label"), UiTheme.size("h3"))
	r.push_color(UiTheme.WARM)
	r.add_text(str(_data.get("tagline", "")) + "\n\n")
	r.pop()
	r.pop()
	for s in _data.get("sections", []):
		var d: Dictionary = s
		r.push_font(UiTheme.font("label"), UiTheme.size("caption"))
		r.push_color(UiTheme.GOLD)
		r.add_text(str(d.get("heading", "")).to_upper() + "\n")
		r.pop()
		r.pop()
		r.push_font(UiTheme.font("body"), UiTheme.size("body"))
		r.push_color(UiTheme.TEXT)
		for line in d.get("lines", []):
			r.add_text(str(line) + "\n")
		r.add_text("\n")
		r.pop()
		r.pop()
	r.push_font(UiTheme.font("body"), UiTheme.size("caption"))
	r.push_color(UiTheme.MUTED)
	r.add_text("Licence texts for everything above are under Notices (LB / RB).\n\n\n")
	r.pop()
	r.pop()
	r.pop()


func _heading(r: RichTextLabel, t: String) -> void:
	r.push_font(UiTheme.font("head"), UiTheme.size("h3"))
	r.push_color(UiTheme.GOLD_HI)
	r.add_text(t + "\n")
	r.pop()
	r.pop()


func _plain(r: RichTextLabel, t: String, muted := false) -> void:
	r.push_font(UiTheme.font("body"), UiTheme.size("caption"))
	r.push_color(UiTheme.MUTED if muted else UiTheme.TEXT)
	r.add_text(t + "\n\n")
	r.pop()
	r.pop()


func _notices(r: RichTextLabel) -> void:
	_heading(r, "Fonts")
	for n in _data.get("notices", []):
		var d: Dictionary = n
		_heading(r, "%s — %s" % [str(d.get("title", "")), str(d.get("license", ""))])
		_plain(r, "Source: %s" % str(d.get("source", "")), true)
		_plain(r, str(d.get("text", "")))
	_heading(r, "Godot Engine %s" % str(Engine.get_version_info().get("string", "")))
	_plain(r, Engine.get_license_text())
	_heading(r, "Third-party components in the engine")
	var lic_names := {}
	for comp in Engine.get_copyright_info():
		var cd: Dictionary = comp
		var parts: PackedStringArray = PackedStringArray()
		for part in cd.get("parts", []):
			var pd: Dictionary = part
			var cr: Array = pd.get("copyright", [])
			parts.append("%s (%s)" % ["; ".join(PackedStringArray(cr)), str(pd.get("license", ""))])
			lic_names[str(pd.get("license", ""))] = true
		_plain(r, "%s — %s" % [str(cd.get("name", "")), " | ".join(parts)])
	_heading(r, "Licence texts")
	var info := Engine.get_license_info()
	for lic in info:
		_heading(r, str(lic))
		_plain(r, str(info[lic]))


func _process(dt: float) -> void:
	if not is_top():
		return
	_idle += dt
	if _idle > 3.0 and _tabs.current_id() == "credits" and not UiTheme.reduce_motion() and not _text.at_end():
		_text.scroll.scroll_vertical += int(ceilf(60.0 * dt))


func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton:
		_idle = 0.0
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.4:
		_idle = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not is_top():
		return
	if event.is_action_pressed("ui_tab_prev"):
		get_viewport().set_input_as_handled()
		_tabs.step(-1)
		return
	if event.is_action_pressed("ui_tab_next"):
		get_viewport().set_input_as_handled()
		_tabs.step(1)
		return
	super(event)
