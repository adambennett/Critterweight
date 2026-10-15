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


## Workshop boundary (MOD-07). Local behaviour: "publishing" exports a shareable package into
## the user packages folder; there are no subscriptions. A Steam adapter would download items
## into the user downloads folder and hand them to Mods.import_package().
func workshop_publish(mod_id: String) -> Dictionary:
	var out := Mods.export_package(mod_id)
	if out == "":
		return {"ok": false, "path": "", "message": "This mod cannot be exported (it has errors)."}
	return {"ok": true, "path": out, "message": "Workshop is not available in this build; saved a shareable package instead: %s" % out}


func workshop_list() -> Array:
	return []
