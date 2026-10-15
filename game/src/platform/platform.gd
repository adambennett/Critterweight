extends Node
## Autoload "Platform": the platform-services boundary (identity, invites/overlay, workshop,
## achievements, cloud saves). This build ships LocalPlatform behaviour only; a Steam adapter is
## deferred commercial work (docs/PLATFORM.md lists exactly what it must implement).

func backend_name() -> String:
	return "local"


func user_display_name() -> String:
	return Profiles.player_name()


func supports_invites() -> bool:
	return false


func supports_workshop() -> bool:
	return false


func unlock_achievement(_id: String) -> void:
	pass
