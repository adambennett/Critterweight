class_name HelpPanel
extends PanelContainer
## Description panel that follows focus: whenever a control inside `scope` gains focus, shows its
## `help_title`, `help_text` and `help_extra` properties (any focusable may define them). Screens can
## also push text directly with show_help(). Lives beside lists in settings/setup screens.

var scope: Node
var eyebrow := ""
var _eyebrow: Label
var _title: Label
var _body: Label
var _extra: Label
var _extra2: Label
var _footer: VBoxContainer


func _init(scope_: Node = null, eyebrow_ := "") -> void:
	scope = scope_
	eyebrow = eyebrow_
	theme_type_variation = "PanelHelp"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var v := UiTheme.vbox(UiTheme.GAP_S)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	_eyebrow = UiTheme.label(eyebrow_.to_upper(), "Eyebrow")
	_eyebrow.visible = eyebrow_ != ""
	v.add_child(_eyebrow)
	_title = UiTheme.label("", "H3", true)
	v.add_child(_title)
	_body = UiTheme.label("", "Body", true)
	v.add_child(_body)
	_extra = UiTheme.label("", "Caption", true)
	v.add_child(_extra)
	_extra2 = UiTheme.label("", "Warning", true)
	_extra2.visible = false
	v.add_child(_extra2)
	_footer = UiTheme.vbox(UiTheme.GAP_S)
	v.add_child(_footer)


func _ready() -> void:
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	var f := get_viewport().gui_get_focus_owner()
	if f:
		_on_focus_changed(f)


## Extra controls under the text (e.g. a preview, a stat list); cleared by clear_footer().
func footer() -> VBoxContainer:
	return _footer


func clear_footer() -> void:
	for c in _footer.get_children():
		c.queue_free()


func show_help(title: String, body: String, extra := "", warning := "") -> void:
	_title.text = title
	_body.text = body
	_body.visible = body != ""
	_extra.text = extra
	_extra.visible = extra != ""
	_extra2.text = warning
	_extra2.visible = warning != ""


func _on_focus_changed(c: Control) -> void:
	if c == null or not is_instance_valid(c):
		return
	if scope != null and is_instance_valid(scope) and not scope.is_ancestor_of(c):
		return
	var title := ""
	var body := ""
	var extra := ""
	var warning := ""
	if "help_title" in c:
		title = str(c.get("help_title"))
	if "help_text" in c:
		body = str(c.get("help_text"))
	if "help_extra" in c:
		extra = str(c.get("help_extra"))
	if "badge_text" in c:
		warning = str(c.get("badge_text"))
	if title == "" and c is Button:
		title = (c as Button).text
	if title == "" and body == "":
		return
	show_help(title, body, extra, warning)
