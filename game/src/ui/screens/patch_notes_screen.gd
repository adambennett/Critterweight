extends Screen
var list: FocusScroll
var notes: ScrollText
var releases: Array = []

func on_enter(_p: Dictionary) -> void:
	MenuBackdrop.ensure()
	add_backdrop_gradient(0.97, 0.8)
	var frame := build_frame("Release archive", "Patch Notes")
	var columns := UiTheme.hbox(24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(frame["body"] as VBoxContainer).add_child(columns)
	list = FocusScroll.new(8)
	list.custom_minimum_size.x = 360
	list.size_flags_stretch_ratio = 0.3
	columns.add_child(list)
	notes = ScrollText.new()
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(notes)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/patch_notes.json"))
	if parsed is Array:
		releases = parsed
	for i in releases.size():
		var b := UiButton.new(str(releases[i]["tag"]))
		b.focus_entered.connect(_show.bind(i))
		b.pressed.connect(func(): notes.grab_focus())
		list.content.add_child(b)
		b.focus_neighbor_right = b.get_path_to(notes)
	list.wrap_focus()
	if not releases.is_empty():
		_show(0)
	(frame["prompts"] as PromptBar).set_prompts([{"actions": ["ui_left", "ui_right"], "text": "Panels"}, {"actions": ["ui_cancel"], "text": "Back", "call": App.back}])

func _show(index: int) -> void:
	var release: Dictionary = releases[index]
	# Release Markdown remains readable as plain text, including bullets and links.
	notes.set_plain("%s\n%s\n\n%s" % [release.get("title", release.get("tag", "Release")), str(release["date"]).left(10), release["body"]])
	notes.focus_neighbor_left = notes.get_path_to(list.focusables()[index])

func right_stick_scroll_target() -> Control:
	return notes

func default_focus() -> Control:
	return list.focusables()[0] if list and not list.focusables().is_empty() else notes
