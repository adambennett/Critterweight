class_name HubHud
extends Control
## The Cannery's HUD (docs/HUB_SYSTEMS.md §8): where you are, your Clout, the context prompt
## ("[A] Talk to Granny Haymaker" with the current device's glyph), carry hints, the running
## activity (timer, score, combo / streak / drill HP / crates), banners (space names, results,
## SECRET FOUND), subtitles for speakers you cannot see, the ice-bath frost and the fishing line.
## Built from UiTheme text styles so everything stays >= 18 px at 1280x800.

var scene
var _space: Label
var _tod: Label
var _clout: Label
var _clout_gain: Label
var _prompt_box: PanelContainer
var _prompt: ButtonPrompt
var _hint_box: HBoxContainer
var _activity: PanelContainer
var _act_title: Label
var _act_time: Label
var _act_score: Label
var _act_extra: Label
var _count: Label
var _banner: PanelContainer
var _banner_eyebrow: Label
var _banner_title: Label
var _banner_sub: Label
var _banner_left := 0.0
var _subtitle: PanelContainer
var _subtitle_text: Label
var _subtitle_left := 0.0
var _frost: ColorRect
var _fish: ProgressBar
var _shown_clout := -1
var _gain_left := 0.0


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frost = ColorRect.new()
	_frost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform float amount = 0.0;\nvoid fragment() {\n\tvec2 d = UV - 0.5;\n\tfloat r = length(d * vec2(1.6, 1.0));\n\tfloat edge = smoothstep(0.35, 0.95, r + sin(UV.x * 60.0 + UV.y * 40.0) * 0.02);\n\tCOLOR = vec4(0.85, 0.95, 1.0, edge * amount * 0.85);\n}\n"
	fm.shader = sh
	_frost.material = fm
	add_child(_frost)
	var m := UiTheme.margin(40, 28, 36)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	var col := UiTheme.vbox(UiTheme.GAP_S)
	m.add_child(col)
	# top row: space + time | activity | clout
	var top := UiTheme.hbox(UiTheme.GAP_M)
	col.add_child(top)
	var where := UiTheme.panel("PanelChip", 14.0)
	var wv := UiTheme.vbox(0)
	_space = UiTheme.label("THE CANNERY", "H3")
	_tod = UiTheme.label("", "Caption")
	wv.add_child(_space)
	wv.add_child(_tod)
	where.add_child(wv)
	where.size_flags_vertical = Control.SIZE_SHRINK_BEGIN      # the activity panel is taller
	top.add_child(where)
	top.add_child(UiTheme.spacer())
	_activity = UiTheme.panel("PanelPoster", 16.0)
	_activity.visible = false
	var av := UiTheme.vbox(2)
	_act_title = UiTheme.label("", "Eyebrow")
	_act_time = UiTheme.label("", "H2")
	_act_score = UiTheme.label("", "ValueGold")
	_act_extra = UiTheme.label("", "Caption")
	for l in [_act_title, _act_time, _act_score, _act_extra]:
		(l as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		av.add_child(l)
	_activity.add_child(av)
	_activity.custom_minimum_size = Vector2(420, 0)
	top.add_child(_activity)
	top.add_child(UiTheme.spacer())
	var cl := UiTheme.panel("PanelChip", 14.0)
	var cv := UiTheme.vbox(0)
	var ct := UiTheme.label("CLOUT", "Eyebrow")
	ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clout = UiTheme.label("0", "H2")
	_clout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clout_gain = UiTheme.label("", "Success")
	_clout_gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cv.add_child(ct)
	cv.add_child(_clout)
	cv.add_child(_clout_gain)
	cl.add_child(cv)
	cl.custom_minimum_size = Vector2(220, 0)
	cl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(cl)
	# middle: countdown + banner
	var mid := UiTheme.vbox(UiTheme.GAP_S)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(mid)
	_count = UiTheme.label("", "Display")
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.visible = false
	mid.add_child(_count)
	_banner = UiTheme.panel("PanelPoster", 22.0)
	_banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_banner.visible = false
	var bv := UiTheme.vbox(4)
	_banner_eyebrow = UiTheme.label("", "Eyebrow")
	_banner_title = UiTheme.label("", "H1")
	_banner_sub = UiTheme.label("", "Body", true)
	_banner_sub.custom_minimum_size = Vector2(640, 0)
	for l2 in [_banner_eyebrow, _banner_title, _banner_sub]:
		(l2 as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bv.add_child(l2)
	_banner.add_child(bv)
	mid.add_child(_banner)
	# bottom: fishing line, subtitles, prompt + hints
	var bottom := UiTheme.vbox(UiTheme.GAP_S)
	col.add_child(bottom)
	_fish = ProgressBar.new()
	_fish.custom_minimum_size = Vector2(520, 26)
	_fish.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_fish.show_percentage = false
	_fish.visible = false
	bottom.add_child(_fish)
	_subtitle = UiTheme.panel("PanelToast", 14.0)
	_subtitle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_subtitle.visible = false
	_subtitle_text = UiTheme.label("", "BodyStrong", true)
	_subtitle_text.custom_minimum_size = Vector2(700, 0)
	_subtitle_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_child(_subtitle_text)
	bottom.add_child(_subtitle)
	_prompt_box = UiTheme.panel("PanelChip", 14.0)
	_prompt_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_prompt = ButtonPrompt.new(["interact"], "", 44.0)
	_prompt.clickable = false
	_prompt_box.add_child(_prompt)
	_prompt_box.visible = false
	bottom.add_child(_prompt_box)
	_hint_box = UiTheme.hbox(UiTheme.GAP_L)
	_hint_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_hint_box.visible = false
	var h1 := ButtonPrompt.new(["grab"], "Toss", 36.0)
	h1.clickable = false
	var h2 := ButtonPrompt.new(["heavy"], "Hold to heave", 36.0)
	h2.clickable = false
	_hint_box.add_child(h1)
	_hint_box.add_child(h2)
	bottom.add_child(_hint_box)


func set_space(space_id: String, tod: String) -> void:
	_space.text = str(HubLayout.space(space_id).get("name", "The Cannery")).to_upper()
	_tod.text = {"morning": "Morning shift", "evening": "Evening session", "night": "After hours"}.get(tod, "")


func banner(eyebrow: String, title: String, sub := "", seconds := 2.6) -> void:
	_banner_eyebrow.text = eyebrow.to_upper()
	_banner_title.text = title.to_upper()
	_banner_sub.text = sub
	_banner_sub.visible = sub != ""
	_banner.visible = true
	_banner_left = seconds
	_banner.modulate.a = 1.0
	Screen.stamp(_banner)


func subtitle(speaker: String, text: String, seconds := 3.0) -> void:
	_subtitle_text.text = ("%s:  %s" % [speaker, text]) if speaker != "" else text
	_subtitle.visible = true
	_subtitle_left = seconds


func countdown(n: int) -> void:
	_count.visible = n > 0
	_count.text = "GO!" if n == 0 else str(n)


func flash_go() -> void:
	_count.visible = true
	_count.text = "GO!"
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(func() -> void: _count.visible = false)


func update_hud(dt: float, mode: HubMode, state: HubState) -> void:
	var f := mode.player()
	# Clout (animated count-up)
	var c := state.clout()
	if _shown_clout < 0:
		_shown_clout = c
	if _shown_clout != c:
		var diff := c - _shown_clout
		_shown_clout += clampi(int(signf(diff)) * maxi(1, int(absi(diff) / 12.0)), -absi(diff), absi(diff))
	_clout.text = str(_shown_clout)
	_gain_left = maxf(0.0, _gain_left - dt)
	_clout_gain.visible = _gain_left > 0.0
	# context prompt / carry hints
	var focus := mode.focus_of(f) if f else {}
	var screen_open := App.top_screen() != null
	_prompt_box.visible = not focus.is_empty() and not screen_open and mode.transition.is_empty()
	if _prompt_box.visible:
		_prompt.set_text(str(focus.get("prompt", "")))
	_hint_box.visible = f != null and not mode.carried_by(f).is_empty() and not screen_open
	# activity panel
	var act := mode.activity_running()
	_activity.visible = act != ""
	match act:
		"bag":
			var b := mode.bags
			_act_title.text = str((HubContent.activity("bags").get("bags", {}) as Dictionary).get(b.bag, {}).get("name", "Bag")).to_upper() + " CHALLENGE"
			_act_time.text = "%.1f" % b.time_left()
			_act_score.text = "%d PTS" % int(b.score)
			_act_extra.text = ("COMBO x%d" % b.combo) if b.combo > 1 else "%d hits" % b.hits
			if b.phase == "countdown":
				countdown(ceili(float(HubContent.activity("bags").get("countdown", 3.0)) - b.t))
			elif _count.visible and _count.text != "GO!":
				flash_go()
		"drill":
			var d := mode.drill
			_act_title.text = "CHUM CANNON · " + str(HubChumDrill.DIFFICULTIES[d.difficulty]["name"]).to_upper()
			_act_time.text = "%.1f" % d.time_left()
			_act_score.text = "STREAK %d" % d.streak
			_act_extra.text = "Drill HP %d   ·   best %d" % [d.drill_hp, d.best_streak]
			if d.phase == "countdown":
				countdown(ceili(float(HubContent.activity("drill").get("countdown", 3.0)) - d.t))
			elif _count.visible and _count.text != "GO!":
				flash_go()
		"crates":
			var ct := mode.crates
			_act_title.text = "CRATE TOSS"
			_act_time.text = "%d CRATES LEFT" % ct.crates_left()
			_act_score.text = "%d PTS" % ct.points
			_act_extra.text = ct.target_text()
	if act == "" and _count.visible and _count.text != "GO!":
		_count.visible = false
	# banner / subtitle timers
	if _banner.visible:
		_banner_left -= dt
		if _banner_left < 0.4:
			_banner.modulate.a = maxf(0.0, _banner_left / 0.4)
		if _banner_left <= 0.0:
			_banner.visible = false
	if _subtitle.visible:
		_subtitle_left -= dt
		if _subtitle_left <= 0.0:
			_subtitle.visible = false
	# frost (ice bath) and fishing
	(_frost.material as ShaderMaterial).set_shader_parameter("amount", mode.secrets.frost())
	_fish.visible = not mode.secrets.fishing.is_empty()
	if _fish.visible:
		_fish.value = float(mode.secrets.fishing.get("t", 0.0)) / HubSecrets.FISH_TIME * 100.0


func clout_gain(amount: int, reason: String) -> void:
	_clout_gain.text = "+%d  %s" % [amount, reason]
	_gain_left = 3.5
	Audio.scrip(clampi(int(amount / 10.0), 1, 5))
