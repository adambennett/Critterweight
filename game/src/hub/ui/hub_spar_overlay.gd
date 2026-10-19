extends Control
## Ring Sparring overlay (added by MatchScene from cfg.overlay_script): who you are sparring and a
## clickable "Back to the Cannery" prompt (the Scoreboard action: View/Back, or the key shown) that
## leaves early with no result. Practice telemetry (last hit quality, damage, body part, the
## dummy's poise and element build-up) comes from PracticeMode.hud_status() on the fight HUD.

var scene: MatchScene
var spar := {}
var _left := false
var _martial := false


func bind(s: MatchScene) -> void:
	scene = s
	spar = s.config.get("hub_spar", {})
	_martial = not s.sim.fighters.is_empty() and s.sim.fighters[0].creature.tags.has("martial")
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := UiTheme.margin(40, 116, 40)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	var col := UiTheme.vbox(UiTheme.GAP_S)
	m.add_child(col)
	var chip := UiTheme.panel("PanelChip", 12.0)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var hb := UiTheme.hbox(UiTheme.GAP_M)
	var fmt := "PRACTICE" if str(spar.get("format", "")) == "practice" else "SPAR"
	hb.add_child(UiTheme.label("RING SPARRING · %s vs %s (%s)" % [fmt, HubSparring.opponent_name(str(spar.get("opponent", ""))),
		BotTiers.display_name(str(spar.get("tier", "journeyman")))], "BodyStrong"))
	var back := ButtonPrompt.new(["mma_juice", "mma_guard"] if _martial else ["scoreboard"], "Hold together: Back to the Cannery" if _martial else "Back to the Cannery", 36.0)
	back.pressed.connect(_leave)
	hb.add_child(back)
	chip.add_child(hb)
	col.add_child(chip)


func _unhandled_input(event: InputEvent) -> void:
	var wants_back := event.is_action_pressed("scoreboard")
	if _martial:
		wants_back = (event.is_action_pressed("mma_guard") or event.is_action_pressed("mma_juice")) and Input.is_action_pressed("mma_juice") and Input.is_action_pressed("mma_guard")
	if wants_back and App.top_screen() == null:
		get_viewport().set_input_as_handled()
		_leave()


func _leave() -> void:
	if _left:
		return
	_left = true
	HubSparring.finished(spar, {"winner_team": -2, "left": true})
