extends Screen
## Random event: speaker, title, text, then the choices — each with its risk tag (text + colour),
## Scrip cost and description; unavailable choices stay visible but disabled with the reason.
## When nothing at all can be taken, MOVE ON passes (EventRunner.PASS) — no softlock.
## After a choice: the outcome text and every applied effect line, then CONTINUE (which may
## start an event fight, open a pick, or return to the map).
## Online party runs: a personal event is decided by whoever answers first (fighter-specific ones
## by that fighter's player); on a group event every member's choice is a vote. Everyone sees the
## outcome (who chose what) until they press CONTINUE - the shared run waits for nobody, but this
## screen holds until then (holds_screen).

var flow: CampaignFlow
var ctrl: RunController
var _buttons: Array = []
var _msg: Label
var _title := ""
var _showing := false


func on_enter(p: Dictionary) -> void:
	flow = p.get("flow")
	ctrl = flow.ctrl
	_build()


## CoopFlow: an outcome on screen is not replaced until the player continues.
func holds_screen() -> bool:
	return _showing


func _build() -> void:
	ctrl = flow.ctrl
	_showing = false
	for c in get_children():
		c.queue_free()
	_buttons.clear()
	var view := ctrl.event_view(flow.me)
	var shared := flow.party_event()
	if view.is_empty() or (flow.is_party() and str(view.get("chosen", "")) != "" and not shared.is_empty()):
		if not shared.is_empty() and str(shared.get("node", "")) == str(ctrl.state.get("position", "")):
			# a party run: the event at this node was decided (maybe by someone else) - its outcome
			_title = str(shared.get("title", "Event"))
			_show_result(_shared_texts(shared))
			return
		if view.is_empty():
			if flow.current_screen() != "event":
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
		if flow.is_party():
			bv.add_child(CampaignUI.label("Your pick is your vote: the most votes win, the Captain breaks ties.", 18, CampaignUI.MUTED))
	elif flow.is_party():
		bv.add_child(CampaignUI.label("Whoever answers first decides for the party.", 18, CampaignUI.MUTED))
	v.add_child(body)
	var can_decide := bool(view.get("can_decide", true))
	if not can_decide:
		v.add_child(CampaignUI.label("Only %s can answer this one." % str(view.get("decider", "")), 20, CampaignUI.MUTED))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	var any_available := false
	for ch in view.get("choices", []):
		list.add_child(_choice_button(ch, can_decide))
		any_available = any_available or bool(ch.get("available", false))
	if can_decide and not any_available:
		var pass_b := CampaignUI.button("NOTHING YOU CAN TAKE — MOVE ON", _choose.bind(EventRunner.PASS), 24, CampaignUI.MUTED)
		list.add_child(pass_b)
		_buttons.append(pass_b)
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
	if not flow.do_event(id):
		_msg.text = flow.error_text()
		return
	if flow.is_party():
		CampaignUI.wait_for_party(self, _msg)
	else:
		_show_result(ctrl.last_texts)


## A shared outcome's lines: who decided what, then what happened.
func _shared_texts(shared: Dictionary) -> Array:
	var who := str(shared.get("by", ""))
	var name_ := "The party" if who == "party" else who
	for p in ctrl.players():
		if str(p.get("id", "")) == who:
			name_ = "You" if who == flow.me else str(p.get("name", who))
	var out: Array = []
	var texts: Array = shared.get("texts", [])
	out.append_array(texts if not texts.is_empty() else ["Nothing happens."])
	out.append("%s chose: %s" % [name_, str(shared.get("choice", ""))])
	return out


func _show_result(texts: Array) -> void:
	for c in get_children():
		c.queue_free()
	_buttons.clear()
	_showing = true
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
	_showing = false
	flow.ack_event()
	flow.show_current()


func on_back() -> bool:
	return true


func default_focus() -> Control:
	return CampaignUI.first_enabled(_buttons)
