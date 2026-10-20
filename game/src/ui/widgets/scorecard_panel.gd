class_name ScorecardPanel
extends PanelContainer
## 10-point-must scorecards: the three judges' round scores and totals, a team legend (letter +
## colour + name, so colour is never the only cue) and optional fight totals of what the judges
## counted. Pure presentation: built from the plain `result.scoring` dictionary that
## MatchMode.build_result() produces under 10-point scoring (or a career history entry holding the
## same shape). Every key is optional; a missing or empty dictionary builds an empty panel.
##
## scoring: {"teams": [ta, tb], "judges": [name x3], "cards": [{"round", "judges": [[a, b] x3],
##   "tally": [{...ta}, {...tb}], "stoppage": bool}], "totals": [[A, B] x3], "method": String,
##   "stoppage": {"round", "time"} | {}}. Pairs are always ordered like "teams".
## names: display names aligned with "teams" (falls back to "Team A"/"Team B").

## Fight-total rows: tally key, label, decimals. Rows whose key appears in no tally are skipped.
const TALLY_ROWS := [["landed", "Strikes landed", 0], ["damage", "Damage dealt", 0], ["knockdowns", "Knockdowns", 0],
	["throws", "Throws", 0], ["ringouts", "Ring-outs", 0], ["parries", "Parries", 0]]

var scoring := {}
var names: Array = []


func _init(scoring_ := {}, names_: Array = [], show_tally := true) -> void:
	scoring = scoring_
	names = names_
	theme_type_variation = "PanelSolid"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := UiTheme.get_theme().get_stylebox(&"panel", "PanelSolid").duplicate() as StyleBox
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		sb.set_content_margin(side, 22.0)
	add_theme_stylebox_override("panel", sb)
	var col := UiTheme.vbox(UiTheme.GAP_S)
	add_child(col)
	col.add_child(_legend())
	col.add_child(_cards_grid())
	if show_tally:
		var t := _tally_grid()
		if t:
			col.add_child(t)


func teams() -> Array:
	var t: Array = scoring.get("teams", [0, 1])
	return t if t.size() == 2 else [0, 1]


func team_name(i: int) -> String:
	if i < names.size() and str(names[i]) != "":
		return str(names[i])
	return "Team %s" % UiTheme.team_letter(int(teams()[i]))


## "10–9" / "29–28": the pair in team order.
static func pair_text(p) -> String:
	if typeof(p) != TYPE_ARRAY or (p as Array).size() < 2:
		return "–"
	return "%d–%d" % [int(p[0]), int(p[1])]


func _legend() -> Control:
	var row := UiTheme.hbox(UiTheme.GAP_M)
	row.add_child(UiTheme.label("SCORECARDS", "Eyebrow"))
	for i in 2:
		var h := UiTheme.hbox(UiTheme.GAP_XS)
		h.add_child(TeamChip.new(int(teams()[i]), 32))
		h.add_child(UiTheme.label(team_name(i).to_upper(), "CaptionStrong"))
		row.add_child(h)
	row.add_child(UiTheme.label("scores read %s–%s" % [UiTheme.team_letter(int(teams()[0])), UiTheme.team_letter(int(teams()[1]))], "Caption"))
	return row


func _cards_grid() -> Control:
	var cards: Array = scoring.get("cards", [])
	var judges: Array = scoring.get("judges", ["Judge 1", "Judge 2", "Judge 3"])
	var grid := GridContainer.new()
	grid.columns = 2 + cards.size()
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 8)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(UiTheme.label("JUDGE", "Caption"))
	for c in cards:
		var cd: Dictionary = c
		var head := "R%d%s" % [int(cd.get("round", 0)), "*" if bool(cd.get("stoppage", false)) else ""]
		grid.add_child(_cell(head, "Caption"))
	grid.add_child(_cell("TOTAL", "Caption"))
	var totals: Array = scoring.get("totals", [])
	for j in 3:
		grid.add_child(UiTheme.label(str(judges[j]) if j < judges.size() else "Judge %d" % (j + 1), "Body"))
		for c in cards:
			var js: Array = (c as Dictionary).get("judges", [])
			grid.add_child(_cell(pair_text(js[j]) if j < js.size() else "–", "Value"))
		grid.add_child(_cell(pair_text(totals[j]) if j < totals.size() else "–", "ValueGold"))
	return grid


func _tally_grid() -> Control:
	var cards: Array = scoring.get("cards", [])
	if cards.is_empty():
		return null
	var sums := [{}, {}]
	for c in cards:
		var tl: Array = (c as Dictionary).get("tally", [])
		for i in mini(2, tl.size()):
			var d: Dictionary = tl[i]
			for k in d:
				if typeof(d[k]) in [TYPE_INT, TYPE_FLOAT]:
					sums[i][k] = float(sums[i].get(k, 0.0)) + float(d[k])
	var rows := []
	for r in TALLY_ROWS:
		if (sums[0] as Dictionary).has(r[0]) or (sums[1] as Dictionary).has(r[0]):
			rows.append(r)
	if rows.is_empty():
		return null
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 6)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(UiTheme.label("WHAT THE JUDGES COUNTED", "Caption"))
	for i in 2:
		grid.add_child(_cell(UiTheme.team_letter(int(teams()[i])), "CaptionStrong"))
	for r in rows:
		grid.add_child(UiTheme.label(str(r[1]), "Body"))
		for i in 2:
			grid.add_child(_cell(str(roundi(float((sums[i] as Dictionary).get(r[0], 0.0)))), "Value"))
	return grid


func _cell(text: String, variation: String) -> Label:
	var l := UiTheme.label(text, variation)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
