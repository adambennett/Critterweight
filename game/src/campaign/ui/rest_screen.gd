extends Screen
## Rest stop (Doc Sutura's back room): the four options as cards — Patch up (heal %), Train
## (learn a technique: opens a pick), Rub-down (clear side effects + small heal), Film study
## (reveal the next act's elite/boss, + Hype carry). Unavailable options say why.
## Once this player has rested, the flow decides what is next (Train's pick, the map); this
## screen never hands back to a flow that would show it again (it waits for the party instead).

var flow: CampaignFlow
var ctrl: RunController
var _cards: Array = []
var _msg: Label


func on_enter(p: Dictionary) -> void:
	flow = p.get("flow")
	ctrl = flow.ctrl
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_cards.clear()
	var r: Dictionary = ctrl.session().get("rest", {}).get(flow.me, {})
	if r.is_empty() or bool(r.get("done", false)):
		if flow.current_screen() != "rest":
			flow.show_current.call_deferred()
		else:
			CampaignUI.scaffold(self, "THE BACK ROOM", "Waiting for the rest of the party...")
		return
	var p := ctrl.player(flow.me)
	var v := CampaignUI.scaffold(self, "THE BACK ROOM", "Doc Sutura has one hour and a bucket of ice. Pick one.")
	var mh := ctrl.max_hp(p)
	v.add_child(CampaignUI.label("HP %d / %d   ·   Side effects: %d   ·   Hype carry %d" % [int(ceil(float(p.get("hp", 0)))), int(mh),
		(p.get("side_effects", []) as Array).size(), int(p.get("hype_carry", 0))], 24, CampaignUI.INK, "700"))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	for o in ctrl.rest_options(flow.me):
		var parts := CampaignUI.card(360, 260, CampaignUI.NODE_COLORS["rest"])
		var b: Button = parts[0]
		var cv: VBoxContainer = parts[1]
		var head := CampaignUI.label(str(o.get("label", "")).to_upper(), 34, CampaignUI.INK, "900")
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(head)
		var d := CampaignUI.label(str(o.get("desc", "")), 22, CampaignUI.INK, "600")
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(d)
		var hint := _hint(str(o.get("id", "")), p, mh)
		if hint != "":
			var hl := CampaignUI.label(hint, 18, CampaignUI.MUTED, "600")
			hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.add_child(hl)
		var ok := bool(o.get("available", true))
		if not ok:
			var why := CampaignUI.label("Unavailable: you already know every technique.", 18, CampaignUI.DANGER, "700")
			why.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.add_child(why)
		b.disabled = not ok
		b.focus_mode = Control.FOCUS_ALL if ok else Control.FOCUS_NONE
		b.pressed.connect(_choose.bind(str(o.get("id", ""))))
		row.add_child(b)
		_cards.append(b)
	_msg = CampaignUI.label("", 20, CampaignUI.DANGER)
	v.add_child(_msg)
	CampaignUI.chain_focus(_cards, false)
	var f := default_focus()
	if f:
		f.call_deferred("grab_focus")


func _hint(id: String, p: Dictionary, mh: float) -> String:
	match id:
		"patch_up":
			var gain := minf(mh - float(p.get("hp", 0)), mh * ctrl.rest_heal_fraction(flow.me))
			return "+%d HP" % int(round(gain))
		"rub_down":
			var n := (p.get("side_effects", []) as Array).size()
			return "Clears %d side effect%s" % [n, "" if n == 1 else "s"]
		"film_study":
			return "Know who's waiting at the end of the next act."
	return ""


func _choose(id: String) -> void:
	if ctrl.rest_choose(flow.me, id):
		flow.show_current()
	else:
		_msg.text = ctrl.last_error


func on_back() -> bool:
	return true


func default_focus() -> Control:
	return CampaignUI.first_enabled(_cards)
