extends Screen
## End of a run: victory / defeat / abandoned, the run's numbers, the final build, what the
## profile earned (Clout, ladder, records, cosmetics — or why a custom run earns no records),
## and RUN IT BACK (same seed) / NEW CARD / RAISE THE DOSE / CAMPAIGN MENU.

var flow: CampaignFlow
var ctrl: RunController
var _buttons: Array = []


func on_enter(p: Dictionary) -> void:
	flow = p.get("flow")
	ctrl = flow.ctrl
	_build()


func _build() -> void:
	ctrl = flow.ctrl
	for c in get_children():
		c.queue_free()
	_buttons.clear()
	var s := ctrl.summary()
	var victory := bool(s.get("victory", false))
	var abandoned := bool(s.get("abandoned", false))
	var me := ctrl.player(flow.me)
	var fname := CampaignUI.fighter_name(ctrl.catalog, str(me.get("fighter", "")))
	var heading := "CHAMPION OF THE GULLET!" if victory else ("RUN ABANDONED" if abandoned else "KNOCKED OUT")
	var where := "Title won" if victory else "Act %d" % int(s.get("act", 1))
	var dose := int(s.get("dose", 0))
	var diff := str(ctrl.catalog.difficulty(str(s.get("difficulty", ""))).get("name", s.get("difficulty", "")))
	var variant := "The Bookie's Table" if str(s.get("mode", "")) == "bookie" else str(s.get("variant", "")).replace("_", " ").capitalize()
	var sub := "%s · %s · %s%s · %s · %s · seed %s" % [fname, variant, diff, (" · Dose %d" % dose) if dose > 0 else "", where,
		CampaignUI.fmt_time(float(s.get("elapsed", 0.0))), str(s.get("seed_text", ""))]
	var v := CampaignUI.scaffold(self, heading, sub)
	(v.get_child(0) as Label).add_theme_color_override("font_color", CampaignUI.ACCENT if victory else CampaignUI.DANGER)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	cols.add_child(_column("THE NUMBERS", _stats_lines(s)))
	cols.add_child(_column("THE BUILD", _build_lines(me)))
	cols.add_child(_column("THE TAKE", _reward_lines()))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	if flow.is_party():
		# an online party run ends together: everyone back to the session's lobby
		var lb := CampaignUI.button("BACK TO THE LOBBY", _restart.bind(false, 0), 24)
		row.add_child(lb)
		_buttons.append(lb)
		CampaignUI.chain_focus(_buttons, false)
		var f0 := default_focus()
		if f0:
			f0.call_deferred("grab_focus")
		return
	var again := CampaignUI.button("RUN IT BACK (same seed)", _restart.bind(true, 0), 24)
	row.add_child(again)
	_buttons.append(again)
	var fresh := CampaignUI.button("NEW CARD", _restart.bind(false, 0), 24)
	row.add_child(fresh)
	_buttons.append(fresh)
	if victory and _can_raise(dose):
		var up := CampaignUI.button("RAISE THE DOSE (Dose %d)" % (dose + 1), _restart.bind(false, 1), 24, CampaignUI.DANGER)
		row.add_child(up)
		_buttons.append(up)
	# Fight Camp runs end back in the Cannery (docs/HUB_SYSTEMS.md)
	if str(s.get("variant", "")) == "fight_camp" and str(s.get("mode", "")) != "bookie" and App.has_screen("hub"):
		var hub := CampaignUI.button("BACK TO THE CANNERY", _cannery, 24, CampaignUI.GOOD)
		row.add_child(hub)
		_buttons.append(hub)
	var menu := CampaignUI.button("CAMPAIGN MENU", _menu, 24, CampaignUI.MUTED)
	row.add_child(menu)
	_buttons.append(menu)
	CampaignUI.chain_focus(_buttons, false)
	var f := default_focus()
	if f:
		f.call_deferred("grab_focus")


func _column(title: String, lines: Array) -> Control:
	var pnl := CampaignUI.panel()
	pnl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pnl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(CampaignUI.label(title, 28, CampaignUI.ACCENT, "900"))
	for l in lines:
		if typeof(l) == TYPE_ARRAY:
			box.add_child(CampaignUI.label(str(l[0]), 20, l[1], "700"))
		else:
			box.add_child(CampaignUI.label(str(l), 20))
	pnl.add_child(CampaignUI.scroll(box))
	return pnl


func _stats_lines(s: Dictionary) -> Array:
	var st: Dictionary = s.get("stats", {})
	var ps: Dictionary = s.get("players", {}).get(flow.me, {}).get("stats", {})
	var out := []
	out.append("Fights won: %d / %d" % [int(st.get("fights_won", 0)), int(st.get("fights", 0))])
	out.append("Nodes visited: %d" % int(st.get("nodes", 0)))
	out.append("KOs: %d (minions %d)" % [int(ps.get("kos", 0)), int(ps.get("minion_kos", 0))])
	out.append("Damage dealt: %d" % int(ps.get("damage_dealt", 0)))
	out.append("Damage taken: %d" % int(ps.get("damage_taken", 0)))
	out.append("Biggest hit: %d" % int(ps.get("biggest_hit", 0)))
	out.append("Knockdowns suffered: %d" % int(ps.get("knockdowns_taken", 0)))
	out.append("Taunts: %d" % int(ps.get("taunts", 0)))
	out.append("Scrip earned: %d · left: %d" % [int(ps.get("scrip_earned", 0)), int(s.get("players", {}).get(flow.me, {}).get("scrip", 0))])
	var nohit: Array = ps.get("boss_no_hit", [])
	if not nohit.is_empty():
		out.append(["No-hit bosses: %d" % nohit.size(), CampaignUI.GOOD])
	return out


func _build_lines(p: Dictionary) -> Array:
	var out := []
	for t in p.get("techniques", []):
		out.append(["Technique: %s" % ctrl.catalog.item_name(str(t)), CampaignUI.GOOD])
	for sp in p.get("supplements", []):
		var d: Dictionary = ctrl.catalog.supplements.get(str(sp["id"]), {})
		var stacks := int(sp.get("stacks", 1))
		out.append(["%s%s" % [d.get("name", sp["id"]), (" x%d" % stacks) if stacks > 1 else ""], CampaignUI.RARITY_COLORS.get(str(d.get("rarity", "otc")), CampaignUI.INK)])
	for se in p.get("side_effects", []):
		out.append(["Side effect: %s" % ctrl.catalog.item_name(str(se)), CampaignUI.DANGER])
	if out.is_empty():
		out.append("Clean. Suspiciously clean.")
	return out


func _reward_lines() -> Array:
	var rep: Dictionary = flow.report
	var out := []
	if flow.is_party():
		out.append_array(_party_lines())
		if rep.is_empty():
			out.append(["Your profile is credited when the host's final result checks out against your own record of the run...", CampaignUI.MUTED])
			return out
	if rep.is_empty() or bool(rep.get("duplicate", false)):
		out.append(["Already credited to your profile.", CampaignUI.MUTED])
		return out
	var camp := str(ctrl.state.get("variant", "")) == "fight_camp"
	out.append(["+%d Clout%s" % [int(rep.get("clout", 0)), " (Cannery upgrades)" if camp else " (cosmetics wallet)"], CampaignUI.ACCENT])
	if bool(ctrl.state.get("custom", false)):
		var reasons: Array = ctrl.state.get("custom_reasons", ctrl.state.get("start_cfg", {}).get("custom_reasons", []))
		out.append(["Custom run%s: statistics and history only — no records, ladder or unlocks." % ((" (%s)" % ", ".join(reasons)) if not reasons.is_empty() else ""), CampaignUI.MUTED])
	if bool(rep.get("dose_ineligible", false)):
		out.append(["Dose %d is not on your own Dosage ladder (or not allowed on this difficulty): no Dose records, badges or ladder progress." % int(ctrl.state.get("dose", 0)), CampaignUI.MUTED])
	if bool(rep.get("ladder_open", false)):
		out.append(["THE DOSAGE IS OPEN: Dose 1 unlocked!", CampaignUI.DANGER])
	elif int(rep.get("new_dose", 0)) > 0:
		out.append(["Dose %d unlocked!" % int(rep["new_dose"]), CampaignUI.DANGER])
	var names := {"fastest_clear": "Fastest clear", "fewest_knockdowns": "Fewest knockdowns", "best_scrip": "Biggest Scrip hoard"}
	for r in rep.get("records", []):
		var key := str(r)
		var txt := str(names.get(key, key))
		if key.begins_with("no_hit:"):
			txt = "No-hit boss: %s" % str(ctrl.catalog.encounters.get(key.trim_prefix("no_hit:"), {}).get("name", key.trim_prefix("no_hit:")))
		out.append(["New record — %s" % txt, CampaignUI.GOOD])
	for c in rep.get("cosmetics", []):
		out.append(["Unlocked: %s" % str(c).replace("_", " ").capitalize(), CampaignUI.GOOD])
	var ach_defs := Platform.achievement_defs()
	for a in rep.get("achievements", []):
		out.append(["Achievement: %s" % str(ach_defs.get(str(a), {}).get("name", a)), CampaignUI.ACCENT])
	if out.size() == 1:
		out.append(["Saved to your history.", CampaignUI.MUTED])
	return out


## Party runs: every member's line (fighter, KOs, Scrip) - each credits only their own profile.
func _party_lines() -> Array:
	var out := []
	var per: Dictionary = ctrl.summary().get("players", {})
	for pid in per:
		var pd: Dictionary = per[pid]
		var st: Dictionary = pd.get("stats", {})
		out.append(["%s%s: %s · KOs %d · Scrip %d" % [str(pd.get("name", pid)), " (you)" if str(pid) == flow.me else "",
			CampaignUI.fighter_name(ctrl.catalog, str(pd.get("fighter", ""))), int(st.get("kos", 0)), int(pd.get("scrip", 0))],
			CampaignUI.ACCENT if str(pid) == flow.me else CampaignUI.INK])
	out.append(["Party run: each member's Clout and records go to their own profile, once.", CampaignUI.MUTED])
	return out


func _can_raise(dose: int) -> bool:
	if bool(ctrl.state.get("custom", false)) or str(ctrl.state.get("mode", "")) == "bookie":
		return false
	if not bool(ctrl.catalog.difficulty(str(ctrl.state.get("difficulty", ""))).get("dose_allowed", true)):
		return false
	return dose < 10 and CampaignProgression.max_selectable_dose(Profiles.current, str(ctrl.state.get("variant", ""))) > dose


func _restart(same_seed: bool, dose_delta: int) -> void:
	flow.restart(same_seed, dose_delta)


func _menu() -> void:
	if flow.is_party():
		flow.restart(false, 0)      # CoopFlow: back to the session's lobby
		return
	App.goto("campaign_menu")


func _cannery() -> void:
	App.goto("hub", {"from": "run"})


func on_back() -> bool:
	_menu()
	return true


func default_focus() -> Control:
	return CampaignUI.first_enabled(_buttons)
