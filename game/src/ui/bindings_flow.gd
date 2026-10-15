class_name BindingsFlow
extends RefCounted
## UI-side rebinding operations on top of the Controls autoload. Every change is persisted through
## Settings ("input.bindings") so it survives restarts, and conflicts are reported back: an input can
## belong to only one gameplay action, so binding it to B removes it from A (Controls.rebind).

const CAPTURE_SECONDS := 5.0


static func is_pad(ev: InputEvent) -> bool:
	return ev is InputEventJoypadButton or ev is InputEventJoypadMotion


static func events_of(action: String, pad: bool) -> Array[InputEvent]:
	return PromptGlyph.events_for(action, pad)


static func has_binding(action: String, pad: bool) -> bool:
	return not events_of(action, pad).is_empty()


static func label_of(action: String) -> String:
	return str(Controls.ACTION_LABELS.get(action, action.capitalize()))


## Binds `ev` as the primary input of `action` for its device class. Returns the action the input
## was taken from ("" if it was free) so the caller can show a conflict notice.
static func rebind(action: String, ev: InputEvent) -> String:
	var stolen := Controls.rebind(action, ev)
	# Controls appends the new event; make it the primary (first) one of its class so prompts show it.
	var evs := InputMap.action_get_events(action)
	if not evs.is_empty():
		var newest: InputEvent = evs[evs.size() - 1]
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, newest)
		for e in evs:
			if e != newest:
				InputMap.action_add_event(action, e)
	_persist()
	return stolen


## Restores one action's default inputs (both device classes). Defaults that are currently used by
## other actions are taken back from them; returns those actions (conflicts to report).
static func reset_action(action: String) -> Array[String]:
	var cur := Controls.current_bindings()
	var defs := Controls.default_bindings()
	var wanted: Array = defs.get(action, [])
	var losers: Array[String] = []
	for other in Controls.GAME_ACTIONS:
		if other == action:
			continue
		var kept := []
		for d in cur.get(other, []):
			var clash := false
			for w in wanted:
				if _same(d, w):
					clash = true
			if clash:
				if not losers.has(other):
					losers.append(other)
			else:
				kept.append(d)
		cur[other] = kept
	cur[action] = wanted.duplicate(true)
	Controls.apply_bindings(cur)
	_persist()
	return losers


static func reset_all() -> void:
	Controls.apply_bindings(Controls.default_bindings())
	Settings.set_value("input.bindings", {})


## True when the bindings differ from the defaults (for "Reset all" availability / tests).
static func is_default() -> bool:
	var cur := Controls.current_bindings()
	var defs := Controls.default_bindings()
	for a in Controls.GAME_ACTIONS:
		var x: Array = cur.get(a, [])
		var y: Array = defs.get(a, [])
		if x.size() != y.size():
			return false
		for i in x.size():
			if not _same(x[i], y[i]):
				return false
	return true


static func _same(a, b) -> bool:
	if typeof(a) != TYPE_DICTIONARY or typeof(b) != TYPE_DICTIONARY:
		return false
	var da: Dictionary = a
	var db: Dictionary = b
	if str(da.get("type", "")) != str(db.get("type", "")):
		return false
	match str(da.get("type", "")):
		"key":
			return int(da.get("code", 0)) == int(db.get("code", 0))
		"mouse", "joy_button":
			return int(da.get("button", 0)) == int(db.get("button", 0))
		"joy_axis":
			return int(da.get("axis", 0)) == int(db.get("axis", 0)) and signf(float(da.get("dir", 0))) == signf(float(db.get("dir", 0)))
	return false


static func _persist() -> void:
	var b := Controls.current_bindings()
	Settings.set_value("input.bindings", b)
