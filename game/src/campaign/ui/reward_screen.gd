extends Screen
## Reward pick: the player's next pending pick (supplement or technique) as option cards, with
## reroll (cost / free rerolls / limit), skip, the Scrip alternative (treasure) and the Dose 7
## side-effect preview. Picks resolve through RunController.claim (claims are keyed by node, so a
## double press or a resumed save can never grant a reward twice). Controller: left/right
## between cards, down to the action row, A/Enter picks.

var flow: CampaignFlow
var ctrl: RunController
var _cards: Array = []
var _actions: Array = []
var _msg: Label
var _entry: Dictionary = {}


func on_enter(p: Dictionary) -> void:
	flow = p.get("flow")
	ctrl = flow.ctrl
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_cards.clear()
	_actions.clear()
	var pend := ctrl.pending_for(flow.me)
	if pend.is_empty():
		flow.show_current.call_deferred()
		return
	_entry = pend[0]
	var kind := str(_entry.get("kind", "supplement"))
	var source := str(_entry.get("source", "fight"))
	var heading := "LEARN A TECHNIQUE" if kind == "technique" else ("TREASURE!" if source == "treasure" else "PICK A SUPPLEMENT")
	var sub := _banner()
	if pend.size() > 1:
		sub += ("   ·   " if sub != "" else "") + "%d picks waiting" % pend.size()
	var v := CampaignUI.scaffold(self, heading, sub)
	var p := ctrl.player(flow.me)
	v.add_child(CampaignUI.label("Scrip %d   ·   HP %d / %d" % [int(p.get("scrip", 0)), int(ceil(float(p.get("hp", 0)))), int(ctrl.max_hp(p))], 22, CampaignUI.INK, "700"))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	var options: Array = _entry.get("options", [])
	for id in options:
		var parts := CampaignUI.card(360, 360, CampaignUI.GOOD if kind == "technique" else CampaignUI.ACCENT)
		var b: Button = parts[0]
		var extra := []
		if kind == "supplement":
			var d: Dictionary = ctrl.catalog.supplements.get(str(id), {})
			var have := RewardRoller.stacks_of(p, str(id))
			if have > 0:
				extra.append(["You have %d / %d" % [have, int(d.get("stack", 1))], CampaignUI.ACCENT])
			var tags: Array = d.get("tags", [])
			if not tags.is_empty():
				extra.append("Tags: " + ", ".join(tags))
		CampaignUI.describe_item(parts[1], ctrl.catalog, str(id), extra)
		b.pressed.connect(_pick.bind(str(id)))
		b.tooltip_text = "Take %s" % ctrl.catalog.item_name(str(id))
		row.add_child(b)
		_cards.append(b)
	if options.is_empty():
		row.add_child(CampaignUI.label("Nothing left to offer here.", 24, CampaignUI.MUTED))
	var se := str(_entry.get("side_effect", ""))
	if se != "":
		var se_text := "Dose 7: this pick also brings a hidden side effect."
		if bool(_entry.get("side_effect_visible", false)):
			se_text = "Dose 7: this pick also brings the side effect %s (%s)." % [ctrl.catalog.item_name(se), ctrl.catalog.item(se).get("effect", "")]
		v.add_child(CampaignUI.label(se_text, 20, CampaignUI.DANGER, "700"))
	var acts := HBoxContainer.new()
	acts.alignment = BoxContainer.ALIGNMENT_CENTER
	acts.add_theme_constant_override("separation", 16)
	v.add_child(acts)
	var rid := str(_entry.get("rid", ""))
	var limit := int(ctrl.catalog.rules.get("reroll", {}).get("max_per_node", 2))
	var left := limit - int(_entry.get("rerolls", 0))
	var cost := ctrl.reroll_cost(flow.me, rid)
	var rr_text := "REROLL (%s) · %d left" % ["free" if cost == 0 else "%d Scrip" % cost, maxi(0, left)]
	var reroll := CampaignUI.button(rr_text, _reroll, 22)
	reroll.disabled = left <= 0 or (cost > 0 and int(p.get("scrip", 0)) < cost) or options.is_empty()
	acts.add_child(reroll)
	_actions.append(reroll)
	if int(_entry.get("scrip_alt", 0)) > 0:
		var sc := CampaignUI.button("TAKE %d SCRIP INSTEAD" % int(_entry["scrip_alt"]), _pick.bind("scrip"), 22, CampaignUI.GOOD)
		acts.add_child(sc)
		_actions.append(sc)
	var skip := CampaignUI.button("SKIP", _pick.bind("skip"), 22, CampaignUI.MUTED)
	acts.add_child(skip)
	_actions.append(skip)
	_msg = CampaignUI.label("", 20, CampaignUI.DANGER)
	v.add_child(_msg)
	CampaignUI.chain_focus(_cards, false)
	CampaignUI.chain_focus(_actions, false)
	var first_action := CampaignUI.first_enabled(_actions)
	var first_card := CampaignUI.first_enabled(_cards)
	for c2 in _cards:
		var cb: Control = c2
		if first_action:
			cb.focus_neighbor_bottom = cb.get_path_to(first_action)
	for a in _actions:
		var ab: Control = a
		if first_card:
			ab.focus_neighbor_top = ab.get_path_to(first_card)
	var f := default_focus()
	if f:
		f.call_deferred("grab_focus")


## One line about the fight that produced this reward (won in m:ss, HP left).
func _banner() -> String:
	var src := str(_entry.get("source", ""))
	if not src in ["fight", "elite", "boss"]:
		return str({"rest": "Training at the back room.", "treasure": "A locker full of the good stuff.", "event": "A little something on the side."}.get(src, ""))
	var lf := ctrl.last_fight()
	if lf.is_empty() or not bool(lf.get("won", false)):
		return ""
	var me: Dictionary = lf.get("players", {}).get(flow.me, {})
	var s := "WON in %s" % CampaignUI.fmt_time(float(lf.get("time", 0.0)))
	if me.has("kos"):
		s += "   ·   KOs %d" % int(me["kos"])
	if lf.has("boss"):
		s = "BOSS DOWN! " + s
	return s


func _pick(choice: String) -> void:
	if ctrl.claim(flow.me, str(_entry.get("rid", "")), choice):
		if ctrl.pending_for(flow.me).is_empty():
			flow.show_current()
		else:
			_build()
	else:
		_msg.text = ctrl.last_error


func _reroll() -> void:
	if ctrl.reroll(flow.me, str(_entry.get("rid", ""))):
		_build()
	else:
		_msg.text = ctrl.last_error


func on_back() -> bool:
	# Back never skips a reward by accident: it moves focus to SKIP instead.
	var skip: Control = _actions.back() if not _actions.is_empty() else null
	if skip:
		skip.grab_focus()
	return true


func default_focus() -> Control:
	var c := CampaignUI.first_enabled(_cards)
	return c if c else CampaignUI.first_enabled(_actions)
