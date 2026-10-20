extends Screen
## Career fight result ("career_result", CMP-08; Cage Rules end screen + gym result banner): WIN /
## LOSS / DRAW, the method (with round and time for a T.K.O.) and the judges' totals, the opponent
## and promotion, the title note, the pay, the popularity change and the new popularity with its
## label and standing, the record, the injuries the bout added, and the judges' cards
## (ScorecardPanel built from summary.scoring, names aligned with its teams). CONTINUE (or Back)
## returns to the hub; the result is already applied and saved (CareerController.apply_result).
## params: {flow: CareerFlow, summary: apply_result summary}. Every summary key is optional.

var flow: CareerFlow
var summary := {}
var _continue: UiButton
var _scroll: ScrollContainer
var _banner: Control


func on_enter(p: Dictionary) -> void:
	var f = p.get("flow", null)
	flow = f if f is CareerFlow else null
	var s = p.get("summary", {})
	summary = s if typeof(s) == TYPE_DICTIONARY else {}
	if summary.is_empty() and flow != null:
		summary = flow.last_summary
	MenuBackdrop.ensure()
	add_backdrop_gradient(0.97, 0.9)
	var res := str(summary.get("result", ""))
	var word: String = str({"win": "WIN", "loss": "LOSS", "draw": "DRAW"}.get(res, "RESULT"))
	var eyebrow := "Fight result"
	if str(summary.get("org_name", "")) != "":
		eyebrow = "%s · %s" % [str(summary.get("org_name", "")), str(summary.get("tier_name", ""))]
	var fr := build_frame(eyebrow, word)
	(fr["prompts"] as PromptBar).set_prompts([{"actions": ["ui_accept"], "text": "Continue", "call": _go_on},
		{"actions": ["ui_cancel"], "text": "Back to the gym", "call": _go_on}])
	var body: VBoxContainer = fr["body"]
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var left := UiTheme.vbox(UiTheme.GAP_M)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size = Vector2(820, 0)
	cols.add_child(left)
	_banner = _make_banner()
	left.add_child(_banner)
	left.add_child(_kpis())
	_continue = UiButton.new("CONTINUE", "PrimaryButton", "forward")
	_continue.route = "continue"
	_continue.custom_minimum_size = Vector2(420, 76)
	_continue.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_continue.set_help("Continue", "Back to your gym: the week has moved on and new offers are in.")
	_continue.pressed.connect(_go_on)
	left.add_child(_continue)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(_scroll)
	var sv := UiTheme.vbox(UiTheme.GAP_M)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(sv)
	var sc: Dictionary = summary.get("scoring", {}) if typeof(summary.get("scoring", {})) == TYPE_DICTIONARY else {}
	if not sc.is_empty() and not (sc.get("cards", []) as Array).is_empty():
		sv.add_child(ScorecardPanel.new(sc, _names_for(sc), true, true))
	else:
		var np := UiTheme.panel("PanelSolid", 22.0)
		np.add_child(UiTheme.label("No judges' cards for this bout: it was decided on health.", "Caption", true))
		sv.add_child(np)
	(func() -> void: Screen.stamp(_banner, 0.05)).call_deferred()
	play_intro()


## Fighter names aligned with scoring.teams (the career fighter is CareerFight.PLAYER_TEAM).
func _names_for(sc: Dictionary) -> Array:
	var me := str(flow.ctrl.state.get("name", "You")) if flow != null and flow.ctrl != null else "You"
	var opp_d: Dictionary = summary.get("opp", {}) if typeof(summary.get("opp", {})) == TYPE_DICTIONARY else {}
	var opp := str(opp_d.get("name", "Opponent"))
	var teams: Array = sc.get("teams", [0, 1])
	var out := []
	for t in teams:
		out.append(me if int(t) == CareerFight.PLAYER_TEAM else opp)
	return out


func _make_banner() -> Control:
	var p := UiTheme.panel("PanelPoster", 26.0)
	var v := UiTheme.vbox(UiTheme.GAP_S)
	p.add_child(v)
	v.add_child(UiTheme.label(CareerUi.method_line(summary), "H3", true))
	var opp_d: Dictionary = summary.get("opp", {}) if typeof(summary.get("opp", {})) == TYPE_DICTIONARY else {}
	var billed := CareerFight.billed_name(str(opp_d.get("name", "?")), str(opp_d.get("nick", "")))
	var fn := str(opp_d.get("fighter_name", ""))
	v.add_child(UiTheme.label("vs %s%s" % [billed, (" (%s)" % fn) if fn != "" else ""], "BodyStrong", true))
	var where := str(summary.get("org_name", ""))
	if bool(summary.get("title", false)):
		where += " · TITLE FIGHT"
	if str(summary.get("week_label", "")) != "":
		where += " · " + str(summary["week_label"])
	v.add_child(UiTheme.label(where, "Caption", true))
	var note := str(summary.get("title_note", ""))
	if note != "":
		var nh := UiTheme.hbox(UiTheme.GAP_S)
		nh.add_child(UiIcons.rect("trophy", 36, UiTheme.GOLD_HI))
		nh.add_child(UiTheme.label(note.to_upper(), "ValueGold"))
		v.add_child(nh)
	return p


func _kpis() -> Control:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 48)
	g.add_theme_constant_override("v_separation", 18)
	var won := bool(summary.get("won", false))
	var pay_sub := "purse %s" % CareerController.money_text(int(summary.get("purse", 0)))
	if won and int(summary.get("bonus", 0)) > 0:
		pay_sub += " + %s win bonus" % CareerController.money_text(int(summary.get("bonus", 0)))
	g.add_child(CareerUi.kpi("Pay", CareerController.money_text(int(summary.get("pay", 0))), pay_sub, "ValueGold"))
	var dp := float(summary.get("d_pop", 0.0))
	var pop_sub := "now %s · %s" % [CareerUi.num(float(summary.get("pop", 0.0))), str(summary.get("pop_label", ""))]
	if bool(summary.get("action_bonus", false)):
		pop_sub += " · fight-of-the-night pace"
	g.add_child(CareerUi.kpi("Popularity", CareerUi.signed(dp), pop_sub, "Success" if dp > 0.0 else ("Danger" if dp < 0.0 else "Value")))
	g.add_child(CareerUi.kpi("Standing", str(summary.get("standing", "")), ""))
	var rec: Dictionary = summary.get("record", {}) if typeof(summary.get("record", {})) == TYPE_DICTIONARY else {}
	var streak := int(summary.get("streak", 0))
	var streak_txt := ""
	if streak >= 2:
		streak_txt = "%d in a row" % streak
	elif streak <= -2:
		streak_txt = "%d straight losses" % -streak
	g.add_child(CareerUi.kpi("Record", "%d-%d-%d" % [int(rec.get("w", 0)), int(rec.get("l", 0)), int(rec.get("d", 0))], streak_txt))
	var inj: Dictionary = summary.get("injury_added", {}) if typeof(summary.get("injury_added", {})) == TYPE_DICTIONARY else {}
	var parts := []
	for r in CareerDefaults.REGIONS:
		parts.append("+%d %s" % [int(round(float(inj.get(r, 0.0)))), r])
	var now: Dictionary = summary.get("injury", {}) if typeof(summary.get("injury", {})) == TYPE_DICTIONARY else {}
	var total := 0.0
	for r2 in CareerDefaults.REGIONS:
		total += float(now.get(r2, 0.0))
	g.add_child(CareerUi.kpi("Injuries", "  ".join(PackedStringArray(parts)), "carrying %d into camp (it heals week by week)" % int(round(total))))
	var landed: Array = summary.get("landed", []) if typeof(summary.get("landed", [])) == TYPE_ARRAY else []
	if landed.size() >= 2:
		g.add_child(CareerUi.kpi("Strikes landed", "%d - %d" % [int(landed[0]), int(landed[1])], "you - them"))
	return g


func default_focus() -> Control:
	return _continue


func right_stick_scroll_target() -> Control:
	return _scroll


func _go_on() -> void:
	if flow != null:
		flow.show_hub("camp")
	else:
		App.goto("career")


func on_back() -> bool:
	_go_on()
	return true
