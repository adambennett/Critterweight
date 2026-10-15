class_name TeamColors
## Team/player colours chosen for colour-vision-deficiency separation, always paired with
## text labels and shapes (P1/P2 tags, team names) so colour is never the only cue.

const COLORS := [Color("#ff5a4f"), Color("#3fa7ff"), Color("#ffc23d"), Color("#4fe08a"),
	Color("#c77dff"), Color("#ff8fd1"), Color("#9aa5b1"), Color("#ff9f43")]
const NAMES := ["Red", "Blue", "Gold", "Green", "Violet", "Pink", "Steel", "Orange"]
## Settings › Accessibility › Team colours. Red–green palettes follow Okabe–Ito (orange vs blue
## first); the tritan palette avoids blue/yellow pairs. Names always match what is shown.
const PALETTES := {
	"deuteranopia": [[Color("#e69f00"), "Orange"], [Color("#3f8fd9"), "Blue"], [Color("#f0e442"), "Yellow"], [Color("#cc79a7"), "Mauve"],
		[Color("#56b4e9"), "Sky"], [Color("#d0d0d0"), "Silver"], [Color("#009e73"), "Teal"], [Color("#8c6d1f"), "Bronze"]],
	"protanopia": [[Color("#e69f00"), "Orange"], [Color("#3f8fd9"), "Blue"], [Color("#f0e442"), "Yellow"], [Color("#cc79a7"), "Mauve"],
		[Color("#56b4e9"), "Sky"], [Color("#d0d0d0"), "Silver"], [Color("#009e73"), "Teal"], [Color("#8c6d1f"), "Bronze"]],
	"tritanopia": [[Color("#e8384f"), "Red"], [Color("#00a6a6"), "Teal"], [Color("#ff9ec4"), "Pink"], [Color("#2e2e8f"), "Navy"],
		[Color("#f7f7f7"), "White"], [Color("#7a5230"), "Brown"], [Color("#9c3fd1"), "Purple"], [Color("#8a8a8a"), "Grey"]],
}


static func _palette() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or not tree.root.has_node("Settings"):
		return "standard"
	return str(Settings.get_value("access.colorblind"))


static func color(team: int) -> Color:
	var p: Array = PALETTES.get(_palette(), [])
	if not p.is_empty():
		return p[posmod(team, p.size())][0]
	return COLORS[posmod(team, COLORS.size())]


static func name(team: int) -> String:
	var p: Array = PALETTES.get(_palette(), [])
	if not p.is_empty():
		return p[posmod(team, p.size())][1]
	return NAMES[posmod(team, NAMES.size())]
