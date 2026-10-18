class_name FlowPromptBar
extends HFlowContainer
## Prompts wrap within the available width, including after a device/glyph change.
var prompts: Array[ButtonPrompt] = []

func _init() -> void:
	add_theme_constant_override("h_separation", 22)
	add_theme_constant_override("v_separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_prompts(list: Array) -> void:
	for p in prompts:
		remove_child(p)
		p.queue_free()
	prompts.clear()
	for d: Dictionary in list:
		var bp := ButtonPrompt.new(d.get("actions", []), str(d.get("text", "")), 32)
		var cb: Callable = d.get("call", Callable())
		bp.clickable = cb.is_valid()
		if cb.is_valid():
			bp.pressed.connect(cb)
		else:
			bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bp)
		prompts.append(bp)

func find_prompt(text: String) -> ButtonPrompt:
	for p in prompts:
		if p.text == text:
			return p
	return null
