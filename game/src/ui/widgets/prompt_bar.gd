class_name PromptBar
extends HBoxContainer
## Footer row of ButtonPrompts ("A Select  B Back  LB/RB Tabs"). Each entry may carry a callback so
## the prompt is clickable with the mouse. Right-aligned by default.
##   bar.set_prompts([{"actions": ["ui_accept"], "text": "Select"},
##                    {"actions": ["ui_cancel"], "text": "Back", "call": App.back}])

var prompts: Array[ButtonPrompt] = []


func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 36)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_prompts(list: Array) -> void:
	for p in prompts:
		p.queue_free()
	prompts.clear()
	for e in list:
		var d: Dictionary = e
		var bp := ButtonPrompt.new(d.get("actions", []), str(d.get("text", "")))
		var cb: Callable = d.get("call", Callable())
		if cb.is_valid():
			bp.pressed.connect(func() -> void:
				Audio.sfx("ui_accept")
				cb.call())
		else:
			bp.clickable = false
			bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bp)
		prompts.append(bp)


func find_prompt(text: String) -> ButtonPrompt:
	for p in prompts:
		if p.text == text:
			return p
	return null
