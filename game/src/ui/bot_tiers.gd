class_name BotTiers
extends RefCounted
## THE single mapping between player-facing bot skill tiers (GAME_PITCH: career-stage nouns) and
## BotBrain difficulty profiles. Every menu that offers a bot difficulty uses this table; the
## campaign's bot tiers (content/core/ladder/difficulty.json) name the same profiles. What each
## tier does and the measured ladder: docs/BOTS.md.

const TIERS := [
	{"id": "punching_bag", "name": "Punching Bag", "brain": "rookie",
		"blurb": "Slow reactions, plenty of mistakes, never parries or punishes. For learning the basics."},
	{"id": "journeyman", "name": "Journeyman", "brain": "regular",
		"blurb": "Blocks some strings, punishes the odd big swing, rarely parries. A fair fight for most players."},
	{"id": "contender", "name": "Contender", "brain": "pro",
		"blurb": "Quicker reads, real combos, punishes whiffed Heavies, parries now and then. Bring your guard."},
	{"id": "headliner", "name": "Headliner", "brain": "champion",
		"blurb": "Fast reads: blocks your strings, parries and punishes button-mashing. Sharp spacing and JUICE use."},
	{"id": "hall_of_famer", "name": "Hall-of-Famer", "brain": "hall_of_famer", "fallback": "champion",
		"blurb": "Reads charge-ups and mashing, parries on your rhythm, punishes everything. The best the Circuit has."},
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
