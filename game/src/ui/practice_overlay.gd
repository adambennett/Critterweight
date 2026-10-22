extends Control
## Practice controls over the fight HUD (MCH-01): choose what the dummy does (stand, guard, parry,
## counter, replay your recording, or fight back as a bot), record/stop a sequence for the replay
## dummy, reset positions and health, and (Movesets) change your four moves live. The hit
## telemetry is the HUD's mode line (PracticeMode).
##
## Shortcuts never collide with the fight (v0.9.18 fix): a practice shortcut only fires on an input
## that no fight action of the player's current layout uses, and the prompt bar only shows the
## shortcuts that are free on the active device. With the default bindings:
##  * keyboard (every layout): 1-6 dummy behaviour (F8 the next one), F5 record/stop, F6 reset,
##    F7 change moves;
##  * controller, ordinary layout: D-pad left/right = dummy, View = record/stop, LS click = reset
##    (the ordinary fight layout leaves them free; View's Scoreboard does nothing in practice);
##  * controller, Varga's Cage Rules layout: every one of those is a fight input (stance, ability 2,
##    JUICE, grapple), so the pad shortcuts stand down and Start opens the pause menu, whose
##    PRACTICE group has the same tools (the one input neither layout fights with).
## Change moves always goes through the pause menu (the match is paused under the loadout screen):
## the new loadout applies at once (Fighter.set_combat: charges and vitals restored), the HUD
## rebuilds its move cards, the profile remembers the loadout for this fighter and Restart fight
## keeps it.

const LABELS := {"stand": "Stand still", "guard": "Guard", "parry": "Parry", "counter": "Block and counter",
	"replay": "Replay my recording", "bot": "Fight back (bot)"}
## Inputs the ordinary fight layout uses (a practice shortcut on one of them stands down).
const FIGHT_ACTIONS := ["move_left", "move_right", "move_up", "move_down", "light", "heavy", "guard", "dodge", "grab",
	"ability1", "ability2", "juice", "taunt", "target", "tag", "cam_left", "cam_right", "pause"]
## The practice actions shown on the prompt bar, in order.
const SHORTCUTS := [["practice_prev", "practice_next"], ["practice_record"], ["practice_reset"], ["practice_moves"]]

var scene: MatchScene
var mode: PracticeMode
var _title: Label
var _bar: PromptBar
var _panel: PanelContainer


func bind(s: MatchScene) -> void:
	scene = s
	mode = s.sim.mode as PracticeMode
	name = "PracticeOverlay"
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	ensure_actions()
	if mode == null:
		return
	var panel := UiTheme.panel("PanelChip")
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -760
	panel.offset_right = 760
	panel.offset_top = -150
	panel.offset_bottom = -92
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_panel = panel
	var row := UiTheme.hbox(UiTheme.GAP_M)
	panel.add_child(row)
	_title = UiTheme.label("", "Value")
	row.add_child(_title)
	row.add_child(UiTheme.spacer())
	_bar = PromptBar.new()
	row.add_child(_bar)
	_rebuild_prompts()
	Controls.device_changed.connect(_on_device_changed)
	Controls.bindings_changed.connect(_rebuild_prompts)
	_refresh()
	_place.call_deferred()


## Practice-only input actions (registered once). Their inputs are free in the ordinary fight
## layout; see the header for the Cage Rules layout.
static func ensure_actions() -> void:
	var defs := {
		"practice_prev": [_joy(JOY_BUTTON_DPAD_LEFT)],
		"practice_next": [_key(KEY_F8), _joy(JOY_BUTTON_DPAD_RIGHT)],
		"practice_record": [_key(KEY_F5), _joy(JOY_BUTTON_BACK)],
		"practice_reset": [_key(KEY_F6), _joy(JOY_BUTTON_LEFT_STICK)],
		"practice_moves": [_key(KEY_F7)],
	}
	for a in defs:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.5)
			for ev in defs[a]:
				InputMap.action_add_event(a, ev)


static func _key(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	return e


static func _joy(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e


func _ready() -> void:
	ensure_actions()


## The local player's fighter (practice's player is fighter 0, MatchScene.player_index).
func player() -> Fighter:
	if scene == null or scene.sim == null or scene.player_index < 0 or scene.player_index >= scene.sim.fighters.size():
		return null
	return scene.sim.fighters[scene.player_index]


## The fight actions of the player's current layout (Cage Rules for a martial fighter).
func layout_actions() -> Array:
	var f := player()
	if f != null and f.creature != null and f.creature.tags.has("martial"):
		var out: Array = MartialControls.MAP.keys()
		out.append_array(["move_left", "move_right", "move_up", "move_down", "cam_left", "cam_right", "pause"])
		return out
	return FIGHT_ACTIONS


## True when `ev` is also one of the player's fight inputs (the practice shortcut stands down).
func collides(ev: InputEvent) -> bool:
	for a in layout_actions():
		if InputMap.has_action(a) and ev.is_action(str(a)):
			return true
	return false


## Whether a practice action has a free binding on the device the prompts show.
func shortcut_free(action: String) -> bool:
	var pad := PromptGlyph.wants_pad()
	for ev in PromptGlyph.events_for(action, pad):
		if not collides(ev):
			return true
	return false


func _on_device_changed(_kind: String) -> void:
	_rebuild_prompts()


## The prompt bar: the free shortcuts on the active device, and Start's practice menu when one of
## them (or Change moves on a controller) is only reachable there.
func _rebuild_prompts() -> void:
	if _bar == null:
		return
	var list: Array = []
	var hidden := false
	for acts in SHORTCUTS:
		var free: Array = []
		for a in acts:
			if shortcut_free(str(a)):
				free.append(a)
		var first := str(acts[0])
		if first == "practice_moves" and not can_change_moves():
			continue
		if free.is_empty():
			hidden = true
			continue
		match first:
			"practice_prev":
				list.append({"actions": free, "text": "Dummy", "call": func() -> void: cycle(1)})
			"practice_record":
				list.append({"actions": free, "text": "Record", "call": toggle_record})
			"practice_reset":
				list.append({"actions": free, "text": "Reset", "call": reset_positions})
			"practice_moves":
				list.append({"actions": free, "text": "Change moves", "call": open_moves})
	if hidden:
		list.append({"actions": ["pause"], "text": "Practice menu", "call": func() -> void: MatchFlow.open_pause()})
	_bar.set_prompts(list)


## Keeps the practice bar just above the HUD's control strip (whose height follows the moves).
func _place() -> void:
	if _panel == null or scene == null or scene.hud == null or not is_instance_valid(scene.hud):
		return
	var strip = scene.hud.get("_hints")
	var bottom := -92.0
	if strip != null and is_instance_valid(strip) and strip is Control:
		bottom = minf(-92.0, (strip as Control).offset_top - 14.0)
	_panel.offset_bottom = bottom
	_panel.offset_top = bottom - 58.0


func _process(_dt: float) -> void:
	if mode != null and Engine.get_process_frames() % 30 == 0:
		_place()


func cycle(step: int) -> void:
	var list: Array = PracticeMode.BEHAVIORS
	var i := list.find(mode.behavior)
	set_behavior(str(list[posmod(i + step, list.size())]))


func set_behavior(b: String) -> void:
	mode.set_behavior(b, str(scene.sim.rules.get("dummy_tier", "regular")))
	Audio.ui("ui_toggle")
	_refresh()


func behavior_label(b: String) -> String:
	return str(LABELS.get(b, b.capitalize()))


func current_behavior() -> String:
	return mode.behavior if mode else "stand"


func is_recording() -> bool:
	return mode != null and mode.recording


func toggle_record() -> void:
	mode.toggle_recording()
	Audio.ui("ui_toggle")
	UiNav.toast("Recording your moves — press again to stop" if mode.recording else "Recording saved: set the dummy to 'Replay my recording'", "info")
	_refresh()


func reset_positions() -> void:
	scene.sim.reset_round()
	Audio.ui("ui_accept")


## Movesets with an equipped loadout: the player can change moves here.
func can_change_moves() -> bool:
	var f := player()
	return f != null and f.combat_style == "moves" and not f.creature.pool.is_empty()


## Change moves: pauses (the pause menu) and opens the loadout screen for the player's fighter over
## it; Done applies the loadout live (apply_loadout) and returns to the pause menu.
func open_moves() -> void:
	if not can_change_moves() or not App.has_screen("loadout"):
		Audio.sfx("ui_error")
		return
	var top := App.top_screen()
	if top == null:
		MatchFlow.open_pause()
	elif top.screen_name != "pause":
		return
	var f := player()
	App.push("loadout", {"creature": f.creature.id, "loadout": f.loadout.duplicate(), "title": "Practice · your moves",
		"in_game": true, "on_done": apply_loadout})


## Equips `lo` on the player's fighter now (charges and vitals restored), rebuilds the HUD's move
## cards, remembers the loadout for this fighter and keeps it for Restart fight.
func apply_loadout(lo: Array) -> void:
	var f := player()
	if f == null:
		return
	f.set_combat(f.combat_style, lo)
	if scene.hud != null:
		scene.hud.refresh_move_cards()
	MovesUi.remember_loadout(f.creature.id, f.loadout)
	_keep_for_restart(f)
	UiNav.toast("Moves: %s" % ", ".join(MovesUi.loadout_names(f.creature, f.loadout)), "success")
	_place.call_deferred()


## MatchFlow.last_config (Restart fight; only when it is this match's config) and the setup the
## results screen returns to.
func _keep_for_restart(f: Fighter) -> void:
	for cfg in [MatchFlow.last_config, scene.config]:
		var d: Dictionary = cfg
		var fs = d.get("fighters", [])
		if typeof(fs) != TYPE_ARRAY or f.index >= (fs as Array).size() or typeof(fs[f.index]) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = fs[f.index]
		var cid = e.get("creature", "")
		if (cid.id if cid is CreatureDef else str(cid)) != f.creature.id or str(e.get("kind", "")) != "player":
			continue          # another match's config (a sandbox started without MatchFlow)
		e["loadout"] = f.loadout.duplicate()
		var ui = d.get("ui", {})
		if typeof(ui) == TYPE_DICTIONARY:
			var setup = (ui as Dictionary).get("setup", {})
			if typeof(setup) == TYPE_DICTIONARY:
				var slots = (setup as Dictionary).get("slots", [])
				if typeof(slots) == TYPE_ARRAY and f.index < (slots as Array).size() and typeof(slots[f.index]) == TYPE_DICTIONARY:
					(slots[f.index] as Dictionary)["loadout"] = f.loadout.duplicate()


func _refresh() -> void:
	if _title:
		_title.text = "PRACTICE  ·  Dummy: %s%s" % [LABELS.get(mode.behavior, mode.behavior), "   ● REC" if mode.recording else ""]


func _unhandled_input(event: InputEvent) -> void:
	if mode == null or App.top_screen() != null:
		return
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if event.is_echo() or not event.is_pressed() or collides(event):
		return
	if event.is_action_pressed("practice_next"):
		cycle(1)
	elif event.is_action_pressed("practice_prev"):
		cycle(-1)
	elif event.is_action_pressed("practice_record"):
		toggle_record()
	elif event.is_action_pressed("practice_reset"):
		reset_positions()
	elif event.is_action_pressed("practice_moves"):
		open_moves()
	elif event is InputEventKey:
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_6:
			set_behavior(str(PracticeMode.BEHAVIORS[k - KEY_1]))
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()
