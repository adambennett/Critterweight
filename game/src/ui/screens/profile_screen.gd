extends Screen
## Profiles ("profile"): local profiles (no login). Select a profile to switch to it; create, rename
## and delete (with confirmation; the last profile cannot be deleted). The poster shows the active
## profile's statistics, records, The Dosage ladder per campaign variant and per-fighter use.
## Records exclude custom-rule / reduced-speed matches (Profiles.record_match), which is stated here.

var _list: FocusScroll
var _stats: VBoxContainer
var _help: HelpPanel


func on_enter(_p: Dictionary) -> void:
	MenuBackdrop.ensure()
	add_backdrop_gradient(0.97, 0.75)
	var f := build_frame("Locker room", "Profile")
	(f["prompts"] as PromptBar).set_prompts(std_prompts())
	var body: VBoxContainer = f["body"]
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var left := UiTheme.vbox(UiTheme.GAP_M)
	left.custom_minimum_size = Vector2(620, 0)
	cols.add_child(left)
	var lp := UiTheme.panel("PanelSolid", 18.0)
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(lp)
	_list = FocusScroll.new(8)
	lp.add_child(_list)
	_help = HelpPanel.new(_list)
	_help.custom_minimum_size = Vector2(0, 150)
	_help.size_flags_vertical = Control.SIZE_SHRINK_END
	left.add_child(_help)
	var poster := UiTheme.panel("PanelPoster")
	poster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(poster)
	var ps := ScrollContainer.new()
	ps.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	poster.add_child(ps)
	_stats = UiTheme.vbox(UiTheme.GAP_S)
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ps.add_child(_stats)
	_rebuild("")
	play_intro()


func default_focus() -> Control:
	var fs := _list.focusables()
	return fs[0] if not fs.is_empty() else null


func _rebuild(focus_route: String) -> void:
	_list.clear()
	var c := _list.content
	c.add_child(UiTheme.label("PROFILES", "Eyebrow"))
	var active := Profiles.id()
	var focus_target: Control = null
	for e in Profiles.list_profiles():
		var d: Dictionary = e
		var pid := str(d["id"])
		var is_active := pid == active
		var b := UiButton.new(str(d["name"]) + ("   ·   ACTIVE" if is_active else ""), "", "star" if is_active else "profile")
		b.route = "profile:" + pid
		if is_active:
			b.add_theme_color_override("font_color", UiTheme.GOLD_HI)
			b.add_theme_color_override("icon_normal_color", UiTheme.GOLD_HI)
			b.set_help(str(d["name"]), "This is the active profile. Statistics, records and campaign progress on the right belong to it.")
		else:
			b.set_help(str(d["name"]), "Select to switch to this profile. Settings are shared by all profiles.")
		b.pressed.connect(_switch.bind(pid))
		c.add_child(b)
		if b.route == focus_route:
			focus_target = b
	c.add_child(UiTheme.spacer(false, 8))
	c.add_child(UiTheme.label("MANAGE", "Eyebrow"))
	var nb := UiButton.new("New profile", "", "plus")
	nb.route = "new"
	nb.set_help("New profile", "Creates a fresh profile and switches to it.")
	nb.pressed.connect(_new_profile)
	c.add_child(nb)
	var rb := UiButton.new("Rename %s" % Profiles.player_name(), "", "edit")
	rb.route = "rename"
	rb.set_help("Rename", "Changes the active profile's display name.")
	rb.pressed.connect(_rename)
	c.add_child(rb)
	var db := UiButton.new("Delete %s…" % Profiles.player_name(), "DangerButton", "close")
	db.route = "delete"
	db.set_help("Delete profile", "Deletes the active profile and its progress after you confirm. The last remaining profile cannot be deleted.")
	db.pressed.connect(_delete)
	c.add_child(db)
	for b2 in [nb, rb, db]:
		if (b2 as UiButton).route == focus_route:
			focus_target = b2
	_list.wrap_focus.call_deferred()
	_build_stats()
	if focus_target:
		focus_target.grab_focus.call_deferred()


func _switch(pid: String) -> void:
	if pid == Profiles.id():
		UiNav.toast("%s is already active." % Profiles.player_name(), "info", 2.0)
		return
	if Profiles.switch_to(pid):
		UiNav.toast("Switched to %s." % Profiles.player_name(), "success")
	else:
		UiNav.toast(Profiles.last_error if Profiles.last_error != "" else "That profile could not be loaded.", "error", 6.0)
	_rebuild("profile:" + Profiles.id())


func _valid_name(t: String) -> String:
	if t.strip_edges() == "":
		return "Give the profile a name."
	if t.strip_edges().length() > 24:
		return "Keep it to 24 characters."
	return ""


func _new_profile() -> void:
	App.push("text_entry", {"title": "New profile", "value": "", "max_len": 24, "allow_empty": false,
		"help": "Profiles keep their own statistics, records, ladder progress and Fight Camp upgrades.",
		"validate": _valid_name, "callback": func(ok: bool, t: String) -> void:
			if not ok:
				return
			Profiles.create(t)
			UiNav.toast("Profile %s created." % Profiles.player_name(), "success")
			_rebuild("profile:" + Profiles.id())})


func _rename() -> void:
	App.push("text_entry", {"title": "Rename profile", "value": Profiles.player_name(), "max_len": 24, "allow_empty": false,
		"validate": _valid_name, "callback": func(ok: bool, t: String) -> void:
			if not ok:
				return
			Profiles.rename(t)
			UiNav.toast("Profile renamed to %s." % Profiles.player_name(), "success")
			_rebuild("rename")})


func _delete() -> void:
	if Profiles.list_profiles().size() <= 1:
		Audio.sfx("ui_error")
		UiNav.toast("You need at least one profile. Create another one first.", "warning", 4.0)
		return
	var nm := Profiles.player_name()
	var pid := Profiles.id()
	App.dialog("Delete %s?" % nm, "This permanently removes %s's statistics, records, ladder progress and Fight Camp upgrades from this computer." % nm,
		[{"label": "Delete profile", "id": "delete", "danger": true}, {"label": "Keep it", "id": "keep", "cancel": true, "default": true}],
		func(id: String) -> void:
			if id != "delete":
				return
			Profiles.delete_profile(pid)
			UiNav.toast("%s was deleted. Active profile: %s." % [nm, Profiles.player_name()], "success", 5.0)
			_rebuild("profile:" + Profiles.id()))


func _row(parent: Container, label: String, value: String) -> void:
	var r := UiTheme.hbox(UiTheme.GAP_M)
	var l := UiTheme.label(label, "Body")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	r.add_child(UiTheme.label(value, "Value"))
	parent.add_child(r)


func _build_stats() -> void:
	for ch in _stats.get_children():
		ch.queue_free()
	var cur := Profiles.current
	var st: Dictionary = cur.get("stats", {})
	var rec: Dictionary = cur.get("records", {})
	_stats.add_child(UiTheme.label("RECORD", "Eyebrow"))
	_stats.add_child(UiTheme.label(Profiles.player_name().to_upper(), "H1", true))
	var m := int(st.get("matches", 0))
	var w := int(st.get("wins", 0))
	_stats.add_child(UiTheme.label("%d WINS  ·  %d LOSSES  ·  %d DRAWS" % [w, int(st.get("losses", 0)), int(st.get("draws", 0))], "H3"))
	_row(_stats, "Matches", str(m))
	_row(_stats, "Win rate", ("%d%%" % roundi(100.0 * w / m)) if m > 0 else "—")
	_row(_stats, "KOs", str(int(st.get("kos", 0))))
	_row(_stats, "Knockdowns", str(int(st.get("knockdowns", 0))))
	_row(_stats, "Damage dealt", str(roundi(float(st.get("damage_dealt", 0.0)))))
	_row(_stats, "Time in the cage", UiTheme.duration_text(float(st.get("time_played", 0.0))))
	_row(_stats, "Win streak (best)", "%d  (%d)" % [int(rec.get("win_streak", 0)), int(rec.get("best_win_streak", 0))])
	_stats.add_child(UiTheme.spacer(false, 8))
	_stats.add_child(UiTheme.label("THE DOSAGE", "Eyebrow"))
	var runs: Dictionary = rec.get("runs", {})
	var ladder: Dictionary = cur.get("ladder", {})
	for variant in [["off_the_street", "Off the Street"], ["fight_camp", "Fight Camp"]]:
		var r: Dictionary = runs.get(variant[0], {})
		var l: Dictionary = ladder.get(variant[0], {})
		_row(_stats, str(variant[1]), "Dose %d unlocked  ·  best %d  ·  %d/%d clears" % [int(l.get("unlocked", 1)), int(r.get("best_dose", 0)),
			int(r.get("clears", 0)), int(r.get("attempts", 0))])
	var camp: Dictionary = cur.get("camp", {})
	_row(_stats, "Clout (Fight Camp)", str(int(camp.get("clout", 0))))
	var pf: Dictionary = st.get("per_fighter", {})
	if not pf.is_empty():
		_stats.add_child(UiTheme.spacer(false, 8))
		_stats.add_child(UiTheme.label("FIGHTERS", "Eyebrow"))
		for fid in pf:
			var e: Dictionary = pf[fid]
			_row(_stats, str(Content.get_entry("creatures", str(fid)).get("name", str(fid))), "%d wins / %d matches" % [int(e.get("wins", 0)), int(e.get("matches", 0))])
	_stats.add_child(UiTheme.spacer(false, 8))
	var tut: Dictionary = cur.get("tutorial", {})
	_row(_stats, "Tutorial", "Completed" if bool(tut.get("completed", false)) else "Not completed")
	var note := UiTheme.label("Statistics count every match. Win streaks and ladder records skip matches played with custom rules or reduced game speed.", "Caption", true)
	_stats.add_child(note)
