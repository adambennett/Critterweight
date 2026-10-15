class_name BotTiers
extends RefCounted
## THE single mapping between player-facing bot skill tiers (GAME_PITCH: career-stage nouns) and
## BotBrain difficulty profiles. Every menu that offers a bot difficulty uses this table.
##
## BotBrain currently ships four profiles (rookie/regular/pro/champion). CAMPAIGN.md specifies a
## fifth tier, Hall-of-Famer (reaction 0.14 s, 2% mistakes); it asks for a "hall_of_famer" profile
## and falls back to "champion" until the AI owner adds one — no code change needed here then.

const TIERS := [
	{"id": "punching_bag", "name": "Punching Bag", "brain": "rookie",
		"blurb": "Slow reactions, plenty of mistakes, never parries. For learning the basics."},
	{"id": "journeyman", "name": "Journeyman", "brain": "regular",
		"blurb": "Blocks some, punishes some, rarely parries. A fair fight for most players."},
	{"id": "contender", "name": "Contender", "brain": "pro",
		"blurb": "Quick reactions, real combos, parries now and then. Bring your guard."},
	{"id": "headliner", "name": "Headliner", "brain": "champion",
		"blurb": "Sharp spacing, frequent parries, smart ability and JUICE use."},
	{"id": "hall_of_famer", "name": "Hall-of-Famer", "brain": "hall_of_famer", "fallback": "champion",
		"blurb": "Reads your charge-ups. The best the Circuit has."},
]
const DEFAULT := "journeyman"
## Settings "gameplay.difficulty" (campaign presets) -> the bot tier quick fights use.
const FROM_DIFFICULTY := {"sparring": "punching_bag", "amateur": "journeyman", "pro": "contender", "title_shot": "headliner"}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for t in TIERS:
		out.append(str(t["id"]))
	return out


static func names() -> Array[String]:
	var out: Array[String] = []
	for t in TIERS:
		out.append(str(t["name"]))
	return out


static func get_tier(id: String) -> Dictionary:
	for t in TIERS:
		if str(t["id"]) == id:
			return t
	return TIERS[1]


static func display_name(id: String) -> String:
	return str(get_tier(id)["name"])


static func blurb(id: String) -> String:
	return str(get_tier(id)["blurb"])


## BotBrain profile id for a tier (falls back when BotBrain lacks the preferred profile).
static func brain_tier(id: String) -> String:
	var t := get_tier(id)
	var want := str(t["brain"])
	if BotBrain.PROFILES.has(want):
		return want
	return str(t.get("fallback", "regular"))


## Tier implied by the player's default difficulty setting.
static func default_tier() -> String:
	return str(FROM_DIFFICULTY.get(str(Settings.get_value("gameplay.difficulty")), DEFAULT))
