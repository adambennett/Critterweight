extends Screen
## Needles' pop-up stall: supplement, technique and (Movesets) move scroll cards with prices (sold /
## can't afford / can't carry shown as text; upgrades say which moves they improve), this stall's
## one service (Rub-down, Antidote Lozenge, Restock or Sell at 50%), the player's Scrip, and LEAVE.
## Every purchase goes through RunController (claim keys stop double buys; a scroll is the learn
## decision). Controller: arrows move between cards and buttons, A/Enter buys.

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
	ctrl = flow.ctrl
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
	top.add_child(CampaignUI.inline_label("SCRIP %d" % scrip, 32, CampaignUI.ACCENT, "900"))
	top.add_child(CampaignUI.inline_label("HP %d / %d" % [int(ceil(float(p.get("hp", 0)))), int(ctrl.max_hp(p))], 26, CampaignUI.INK, "700"))
	if float(view.get("coupon", 0.0)) > 0.0:
		top.add_child(CampaignUI.inline_label("Glandco coupon: -%d%%" % int(round(float(view["coupon"]) * 100.0)), 22, CampaignUI.GOOD, "700"))
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
	var item_name := ctrl.catalog.item_name(id)
	if str(it.get("kind", "")) == "move":
		var fighter := str(p.get("fighter", ""))
		item_name = "the %s scroll" % RunMoves.move_name(ctrl.catalog, fighter, id)
		CampaignUI.describe_move(parts[1], ctrl.catalog, fighter, id, "MOVE SCROLL · LEARN IT FOR GOOD", "", extra)
	else:
		var imp := RunMoves.improves_text(ctrl.catalog, ctrl.state, p, id)
		if imp != "":
			extra.append([imp, CampaignUI.GOOD])
		CampaignUI.describe_item(parts[1], ctrl.catalog, id, extra)
	b.disabled = why != ""
	b.focus_mode = Control.FOCUS_NONE if b.disabled else Control.FOCUS_ALL
	b.tooltip_text = "Buy %s for %d Scrip" % [item_name, price]
	b.pressed.connect(_buy.bind(str(it.get("slot", "")), item_name))
	_cards.append(b)
	return b


func _service_row(row: HBoxContainer, view: Dictionary, scrip: int) -> void:
	var svc := str(view.get("service", ""))
	var price := int(view.get("service_price", 0))
	var txt: Array = SERVICE_TEXT.get(svc, [svc.to_upper(), ""])
	if svc == "sell":
		var frac := int(round(float(ctrl.catalog.rules.get("shop", {}).get("sell_fraction", 0.5)) * 100.0))
		row.add_child(CampaignUI.inline_label("SELL (%d%%):" % frac, 22, CampaignUI.INK, "900"))
		var sellable: Array = view.get("sellable", [])
		if sellable.is_empty():
			row.add_child(CampaignUI.inline_label("nothing to sell", 20, CampaignUI.MUTED))
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
	var desc := CampaignUI.label(str(txt[1]) + (" (used)" if used else ""), 18, CampaignUI.MUTED)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL     # a wrapping label needs the row's width
	desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(desc)
	_buttons.append(b)


func _buy(slot: String, item_name: String) -> void:
	_after(flow.do_shop_buy(slot), "Bought %s." % item_name)


func _service() -> void:
	_after(flow.do_shop_service(), "Done.")


func _sell(item_id: String) -> void:
	_after(flow.do_shop_sell(item_id), "Sold %s." % ctrl.catalog.item_name(item_id))


## Solo: the purchase is applied - show the stall again with the note. Party run: the host
## answers with the new state (CoopFlow rebuilds the stall); until then the stall waits.
func _after(ok: bool, note: String) -> void:
	_note = note if ok else "!" + flow.error_text()
	if ok and flow.is_party():
		CampaignUI.wait_for_party(self, _msg)
		return
	_build()


func _leave() -> void:
	if not flow.do_shop_leave():
		_msg.text = flow.error_text()
		return
	if flow.is_party():
		CampaignUI.wait_for_party(self, _msg)
	else:
		flow.show_current()


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
