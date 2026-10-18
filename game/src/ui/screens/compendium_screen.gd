extends Screen
## A browsable guide with real fighter models and content-derived mechanics.
const SECTIONS := ["fighters", "elements", "arenas", "rules", "field", "guide"]
var tabs: TabStrip
var list: FocusScroll
var preview: FighterPreview
var preview_panel: Control
var details: ScrollText
var heading: Label
var rows: Array = []
var selected := 0
var section := 0

func on_enter(_p: Dictionary) -> void:
	MenuBackdrop.ensure()
	add_backdrop_gradient(0.95, 0.8)
	var frame := build_frame("The Cannery field guide", "Compendium")
	var body: VBoxContainer = frame["body"]
	tabs = TabStrip.new()
	tabs.setup(["Fighters", "Elements", "Arenas", "Rules", "Map objects", "Guide"], SECTIONS)
	tabs.tab_changed.connect(_select_section)
	body.add_child(tabs)
	var columns := UiTheme.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	list = FocusScroll.new(8)
	list.custom_minimum_size.x = 350
	columns.add_child(list)
	preview_panel = UiTheme.vbox(8)
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(preview_panel)
	preview = FighterPreview.new()
	preview_panel.add_child(preview)
	preview_panel.add_child(UiTheme.label("MODEL · Drag / right stick: orbit\nWheel / triggers: zoom · D-pad: change panel", "Caption", true))
	var info_panel := UiTheme.panel("PanelSolid", 20)
	info_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_panel.size_flags_stretch_ratio = 1.4
	columns.add_child(info_panel)
	var information := UiTheme.vbox(12)
	info_panel.add_child(information)
	heading = UiTheme.label("", "H2", true)
	information.add_child(heading)
	details = ScrollText.new()
	information.add_child(details)
	(frame["prompts"] as PromptBar).set_prompts([
		{"actions": ["ui_tab_prev", "ui_tab_next"], "text": "Sections"},
		{"actions": ["ui_left", "ui_right"], "text": "Panels"},
		{"actions": ["ui_cancel"], "text": "Back", "call": App.back}])
	_select_section(0)
	Controls.device_changed.connect(_device_changed)
	Controls.bindings_changed.connect(_bindings_changed)

func _device_changed(_device: String) -> void:
	_bindings_changed()

func _bindings_changed() -> void:
	if section == 0 and not rows.is_empty():
		rows = CompendiumData.entries("fighters")
		_select_entry(selected)

func _select_section(index: int) -> void:
	section = index
	tabs.select(index, false)
	rows = CompendiumData.entries(SECTIONS[index])
	list.clear()
	preview_panel.visible = index == 0
	for i in rows.size():
		var b := UiButton.new(str(rows[i]["name"]))
		b.custom_minimum_size.x = 300
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.focus_entered.connect(_select_entry.bind(i))
		b.pressed.connect(func():
			_select_entry(i)
			(preview if preview_panel.visible else details).grab_focus())
		list.content.add_child(b)
	if not rows.is_empty():
		_select_entry(0)
		list.focusables()[0].grab_focus.call_deferred()
	_link_focus.call_deferred()

func _select_entry(index: int) -> void:
	selected = index
	var entry: Dictionary = rows[index]
	heading.text = str(entry["name"]).to_upper()
	details.set_bbcode(str(entry["text"]))
	if preview_panel.visible and preview.creature_id != str(entry["id"]):
		preview.show_fighter(Content.creature(str(entry["id"])))
	_link_focus.call_deferred()

func _link_focus() -> void:
	var buttons := list.focusables()
	if buttons.is_empty():
		return
	var left: Control = buttons[clampi(selected, 0, buttons.size() - 1)]
	for button: Control in buttons:
		button.focus_neighbor_right = button.get_path_to(preview if preview_panel.visible else details)
	preview.focus_neighbor_left = preview.get_path_to(left)
	preview.focus_neighbor_right = preview.get_path_to(details)
	details.focus_neighbor_left = details.get_path_to(preview if preview_panel.visible else left)
	list.wrap_focus()

func default_focus() -> Control:
	var buttons := list.focusables() if list else []
	return buttons[0] if not buttons.is_empty() else details

func _unhandled_input(event: InputEvent) -> void:
	if not is_top():
		return
	if event.is_action_pressed("ui_tab_prev") or event.is_action_pressed("ui_tab_next"):
		get_viewport().set_input_as_handled()
		tabs.step(-1 if event.is_action_pressed("ui_tab_prev") else 1)
		return
	super(event)

func on_back() -> bool:
	App.pop() if App.stack.size() > 1 else App.goto("main_menu")
	return true
