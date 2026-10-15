extends Screen
## Random event: speaker, title, text, then the choices — each with its risk tag (text + colour),
## Scrip cost and description; unavailable choices stay visible but disabled with the reason.
## After a choice: the outcome text and every applied effect line, then CONTINUE (which may
## start an event fight, open a pick, or return to the map).

var flow: CampaignFlow
var ctrl: RunController
var _buttons: Array = []
var _msg: Label
var _title := ""


func on_enter(p: Dictionary) -> void:
	flow = p.get("flow")
	ctrl = flow.ctrl
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_buttons.clear()
	var view := ctrl.event_view(flow.me)
	if view.is_empty():
		flow.show_current.call_deferred()
		return
	_title = str(view.get("title", "Event"))
	if str(view.get("chosen", "")) != "":
		_show_result(ctrl.last_texts if not ctrl.last_texts.is_empty() else view.get("result", []))
		return
	var v := CampaignUI.scaffold(self, _title.to_upper(), "")
	var body := CampaignUI.panel()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 10)
	body.add_child(bv)
	if str(view.get("speaker", "")) != "":
		bv.add_child(CampaignUI.label(str(view["speaker"]).to_upper(), 24, CampaignUI.ACCENT, "900"))
	bv.add_child(CampaignUI.label(str(view.get("text", "")), 26, CampaignUI.INK, "600"))
	if bool(view.get("group", false)):
		bv.add_child(CampaignUI.label("Group event: one decision for the whole party; Scrip costs are split.", 18, CampaignUI.MUTED))
	v.add_child(body)
	var can_decide := bool(view.get("can_decide", true))
	if not can_decide:
		v.add_child(CampaignUI.label("Only %s can answer this one." % str(view.get("decider", "")), 20, CampaignUI.MUTED))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	for ch in view.get("choices", []):
		list.add_child(_choice_button(ch, can_decide))
	v.add_child(CampaignUI.scroll(list))
	_msg = CampaignUI.label("", 20, CampaignUI.DANGER)
	v.add_child(_msg)
	CampaignUI.chain_focus(_buttons, true)
	var f := default_focus()
	if f:
		f.call_deferred("grab_focus")


func _choice_button(ch: Dictionary, can_decide: bool) -> Control:
	var risk := str(ch.get("risk", "safe"))
	var rcol: Color = CampaignUI.RISK_COLORS.get(risk, CampaignUI.MUTED)
	var parts := CampaignUI.card(0, 96, rcol)
	var b: Button = parts[0]
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v: VBoxContainer = parts[1]
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 12)
	var tag := CampaignUI.label("[%s]" % str(CampaignUI.RISK_NAMES.get(risk, risk.to_upper())), 20, rcol, "900")
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(tag)
	var name_l := CampaignUI.label(str(ch.get("label", "")), 26, CampaignUI.INK, "900")
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_l)
	var cost: Dictionary = ch.get("cost", {})
	if int(cost.get("scrip", 0)) > 0:
		var cl := CampaignUI.label("%d Scrip" % int(cost["scrip"]), 22, CampaignUI.ACCENT, "900")
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.autowrap_mode = TextServer.AUTOWRAP_OFF
		head.add_child(cl)
	v.add_child(head)
	var d := CampaignUI.label(str(ch.get("desc", "")), 20, CampaignUI.INK, "600")
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)
	var ok := bool(ch.get("available", true)) and can_decide
	if not bool(ch.get("available", true)):
		var why := CampaignUI.label("Unavailable: %s" % str(ch.get("reason", "")), 18, CampaignUI.DANGER, "700")
		why.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(why)
	b.disabled = not ok
	b.focus_mode = Control.FOCUS_ALL if ok else Control.FOCUS_NONE
	b.pressed.connect(_choose.bind(str(ch.get("id", ""))))
	# the card grows with its text (a Button does not size to child containers by itself)
	v.minimum_size_changed.connect(_fit.bind(b, v))
	_buttons.append(b)
	return b


func _fit(b: Button, v: VBoxContainer) -> void:
	if is_instance_valid(b) and is_instance_valid(v):
		b.custom_minimum_size.y = maxf(96.0, v.get_combined_minimum_size().y + 34.0)


func _choose(id: String) -> void:
	if ctrl.choose_event(flow.me, id):
		_show_result(ctrl.last_texts)
	else:
		_msg.text = ctrl.last_error


func _show_result(texts: Array) -> void:
	for c in get_children():
		c.queue_free()
	_buttons.clear()
	var v := CampaignUI.scaffold(self, _title.to_upper(), "")
	var body := CampaignUI.panel()
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 10)
	body.add_child(bv)
	if texts.is_empty():
		bv.add_child(CampaignUI.label("Nothing happens.", 26))
	for i in texts.size():
		bv.add_child(CampaignUI.label(str(texts[i]), 26 if i == 0 else 22, CampaignUI.INK if i == 0 else CampaignUI.ACCENT, "600" if i == 0 else "700"))
	v.add_child(body)
	var nxt := "CONTINUE"
	match ctrl.phase():
		"fight":
			nxt = "FIGHT!"
		"reward":
			if not ctrl.pending_for(flow.me).is_empty():
				nxt = "CLAIM YOUR PICK"
	var cont := CampaignUI.button(nxt, _continue, 30)
	v.add_child(cont)
	_buttons.append(cont)
	cont.call_deferred("grab_focus")


func _continue() -> void:
	ctrl.last_texts = []
	flow.show_current()


func on_back() -> bool:
	return true


func default_focus() -> Control:
	return CampaignUI.first_enabled(_buttons)
