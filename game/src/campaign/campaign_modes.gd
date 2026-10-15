class_name CampaignModes
extends RefCounted
## Registers the campaign match modes with ModeRegistry ("campaign", "boss") so presets, replays
## and network peers can recreate them by id. Called by EncounterBuilder before building a match.
## Factories are plain Callable(script, "new") — never lambdas: a lambda owned by this script and
## stored in ModeRegistry's static dictionary crashes the engine at exit (verified 4.5.1).

static var _done := false


static func ensure_registered() -> void:
	if _done:
		return
	_done = true
	ModeRegistry.register("campaign", Callable(CampaignMatchMode, "new"))
	ModeRegistry.register("boss", Callable(BossMode, "new"))
