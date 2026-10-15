extends Screen
## Needles' pop-up stall: supplement and technique cards with prices (sold / can't afford /
## can't carry shown as text), this stall's one service (Rub-down, Antidote Lozenge, Restock or
## Sell at 50%), the player's Scrip, and LEAVE. Every purchase goes through RunController (claim
## keys stop double buys). Controller: arrows move between cards and buttons, A/Enter buys.

var flow: CampaignFlow
var ctrl: RunController
var _cards: Array = []
var _buttons: Array = []
var _msg: Label
var _note := ""

const SERVICE_TEXT := {
	"rub_down": ["RUB-DOWN", "Remove all side effects"],
	"antidote": ["ANTIDOTE LOZENGE", "A consumable that clears your side effects when used"],
	"reroll": ["RESTOCK", "Reroll this stall's stock once"],
	"sell": ["SELL", "Sell supplements back at %d%%"],
}


func on_enter(p: Dictionary) -> void:
	flow = p.get("flow")
	ctrl = flow.ctrl
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_cards.clear()
	_buttons.clear()
	var view := ctrl.shop_view(flow.me)
	if view.is_empty() or bool(view.get("done", false)):
		# never hand back to a flow that would show this very screen again
		if flow.current_screen() != "shop":
			flow.show_current.call_deferred()
		else:
			CampaignUI.scaffold(self, "NEEDLES' POP-UP STALL", "Waiting for the rest of the party...")
		return
	var p := ctrl.player(flow.me)
	var scrip := int(view.get("scrip", 0))
	var v := CampaignUI.scaffold(self, "NEEDLES' POP-UP STALL", "\"Everything's legal somewhere.\"")
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	top.add_child(CampaignUI.label("SCRIP %d" % scrip, 32, CampaignUI.ACCENT, "900"))
	top.add_child(CampaignUI.label("HP %d / %d" % [int(ceil(float(p.get("hp", 0)))), int(ctrl.max_hp(p))], 26, CampaignUI.INK, "700"))
	if float(view.get("coupon", 0.0)) > 0.0:
		top.add_child(CampaignUI.label("Glandco coupon: -%d%%" % int(round(float(view["coupon"]) * 100.0)), 22, CampaignUI.GOOD, "700"))
	v.add_child(top)
	if float(ctrl.rules_for(flow.me).get("supplement_side_effects", 0.0)) > 0.0:
		v.add_child(CampaignUI.label("Dose 7: every supplement bought here comes with a side effect.", 20, CampaignUI.DANGER, "700"))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	for it in view.get("items", []):
		grid.add_child(_item_card(it, p, scrip))
	v.add_child(CampaignUI.scroll(grid))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_service_row(row, view, scrip)
	var leave := CampaignUI.button("LEAVE THE STALL", _leave, 24, CampaignUI.MUTED)
	row.add_child(leave)
	_buttons.append(leave)
	v.add_child(row)
	_msg = CampaignUI.label(_note, 20, CampaignUI.GOOD if not _note.begins_with("!") else CampaignUI.DANGER)
	_msg.text = _note.trim_prefix("!")
	_note = ""
	v.add_child(_msg)
	var first_btn := CampaignUI.first_enabled(_buttons)
	for c2 in _cards:
		var cb: Control = c2
		if first_btn and not (cb as BaseButton).disabled:
			cb.focus_neighbor_bottom = cb.get_path_to(first_btn)
	CampaignUI.chain_focus(_buttons, false)
	var f := default_focus()
	if f:
		f.call_deferred("grab_focus")


func _item_card(it: Dictionary, p: Dictionary, scrip: int) -> Control:
	var id := str(it.get("id", ""))
	var price := int(it.get("price", 0))
	var parts := CampaignUI.card(330, 300, CampaignUI.GOOD if str(it.get("kind", "")) == "technique" else CampaignUI.ACCENT)
	var b: Button = parts[0]
	var why := ""
	if bool(it.get("sold", false)):
		why = "SOLD"
	elif scrip < price:
		why = "Need %d more Scrip" % (price - scrip)
	elif str(it.get("kind", "")) == "supplement" and not RewardRoller.can_take(ctrl.catalog, p, id):
		why = "You can't carry another"
	var extra := [["%d SCRIP" % price, CampaignUI.ACCENT]]
	if why != "":
		extra.append([why, CampaignUI.DANGER])
	CampaignUI.describe_item(parts[1], ctrl.catalog, id, extra)
	b.disabled = why != ""
	b.focus_mode = Control.FOCUS_NONE if b.disabled else Control.FOCUS_ALL
	b.tooltip_text = "Buy %s for %d Scrip" % [ctrl.catalog.item_name(id), price]
	b.pressed.connect(_buy.bind(str(it.get("slot", "")), ctrl.catalog.item_name(id)))
	_cards.append(b)
	return b


func _service_row(row: HBoxContainer, view: Dictionary, scrip: int) -> void:
	var svc := str(view.get("service", ""))
	var price := int(view.get("service_price", 0))
	var txt: Array = SERVICE_TEXT.get(svc, [svc.to_upper(), ""])
	if svc == "sell":
		var frac := int(round(float(ctrl.catalog.rules.get("shop", {}).get("sell_fraction", 0.5)) * 100.0))
		row.add_child(CampaignUI.label("SELL (%d%%):" % frac, 22, CampaignUI.INK, "900"))
		var sellable: Array = view.get("sellable", [])
		if sellable.is_empty():
			row.add_child(CampaignUI.label("nothing to sell", 20, CampaignUI.MUTED))
		for s in sellable:
			var sb := CampaignUI.button("%s +%d" % [ctrl.catalog.item_name(str(s["id"])), int(s["value"])], _sell.bind(str(s["id"])), 20)
			row.add_child(sb)
			_buttons.append(sb)
		return
	var used := (svc == "reroll" and bool(view.get("reroll_used", false)))
	var b := CampaignUI.button("%s — %d SCRIP" % [txt[0], price], _service, 22)
	b.tooltip_text = str(txt[1])
	if svc == "rub_down" and (ctrl.player(flow.me).get("side_effects", []) as Array).is_empty():
		b.tooltip_text += " (you have none)"
	b.disabled = used or scrip < price
	row.add_child(b)
	row.add_child(CampaignUI.label(str(txt[1]) + (" (used)" if used else ""), 18, CampaignUI.MUTED))
	_buttons.append(b)


func _buy(slot: String, item_name: String) -> void:
	if ctrl.shop_buy(flow.me, slot):
		_note = "Bought %s." % item_name
	else:
		_note = "!" + ctrl.last_error
	_build()


func _service() -> void:
	if ctrl.shop_service(flow.me):
		_note = "Done."
	else:
		_note = "!" + ctrl.last_error
	_build()


func _sell(item_id: String) -> void:
	if ctrl.shop_sell(flow.me, item_id):
		_note = "Sold %s." % ctrl.catalog.item_name(item_id)
	else:
		_note = "!" + ctrl.last_error
	_build()


func _leave() -> void:
	if ctrl.shop_leave(flow.me):
		flow.show_current()
	else:
		_msg.text = ctrl.last_error


func on_back() -> bool:
	var leave: Control = _buttons.back() if not _buttons.is_empty() else null
	for b in _buttons:
		if (b as Button).text.begins_with("LEAVE"):
			leave = b
	if leave:
		leave.grab_focus()
	return true


func default_focus() -> Control:
	var c := CampaignUI.first_enabled(_cards)
	return c if c else CampaignUI.first_enabled(_buttons)
