class_name TeamColors
## Team/player colours chosen for colour-vision-deficiency separation, always paired with
## text labels and shapes (P1/P2 tags, team names) so colour is never the only cue.

const COLORS := [Color("#ff5a4f"), Color("#3fa7ff"), Color("#ffc23d"), Color("#4fe08a"),
	Color("#c77dff"), Color("#ff8fd1"), Color("#9aa5b1"), Color("#ff9f43")]
const NAMES := ["Red", "Blue", "Gold", "Green", "Violet", "Pink", "Steel", "Orange"]


static func color(team: int) -> Color:
	return COLORS[posmod(team, COLORS.size())]


static func name(team: int) -> String:
	return NAMES[posmod(team, NAMES.size())]
