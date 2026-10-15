extends Node
## Autoload "Platform": the platform-services boundary (identity, invites/overlay, rich presence,
## workshop, achievements, cloud saves). This build ships the LOCAL backend only: everything works
## offline with no account. A Steam backend is deferred commercial work; docs/PLATFORM.md lists
## exactly what it must implement and how each call maps. Nothing in the game calls a store SDK
## directly — only this interface — so swapping the backend touches one file.

signal achievement_unlocked(id: String, name_: String)

const BACKEND := "local"

var _presence := ""


func backend_name() -> String:
	return BACKEND


# --- identity --------------------------------------------------------------------------------

## Stable per-profile id (random UUID created on first use). Used for co-op run ownership and
## server rosters. Never derived from personal data.
func user_id() -> String:
	var id := str(Profiles.current.get("platform_id", ""))
	if id == "":
		var bytes := Crypto.new().generate_random_bytes(16)
		id = bytes.hex_encode()
		Profiles.current["platform_id"] = id
		Profiles.save()
	return id


func user_display_name() -> String:
	return Profiles.player_name()


# --- invites, overlay, presence --------------------------------------------------------------

func supports_invites() -> bool:
	return false


## Text a host can hand to friends out-of-band (local backend has no friends list or overlay).
func invite_text(address: String, port: int, has_password: bool) -> String:
	return "Join my Critterweight game: %s:%d%s (Online > Join > Direct connect)" % [address, port, " — I'll tell you the password" if has_password else ""]


func open_overlay(_page := "") -> bool:
	return false


func set_presence(text: String) -> void:
	_presence = text


func presence() -> String:
	return _presence


# --- achievements ----------------------------------------------------------------------------

## Local achievements live in the profile; a store backend would mirror them.
func unlock_achievement(id: String) -> bool:
	var defs := achievement_defs()
	if not defs.has(id):
		Log.w("platform", "unknown achievement '%s'" % id)
		return false
	var got: Dictionary = Profiles.current.get("achievements", {})
	if got.has(id):
		return false
	got[id] = int(Time.get_unix_time_from_system())
	Profiles.current["achievements"] = got
	Profiles.save()
	var nm := str((defs[id] as Dictionary).get("name", id))
	Log.i("platform", "achievement unlocked: %s" % nm)
	achievement_unlocked.emit(id, nm)
	if DisplayServer.get_name() != "headless":
		UiNav.toast("Achievement: %s" % nm, "success", 4.0)
	return true


func is_unlocked(id: String) -> bool:
	return (Profiles.current.get("achievements", {}) as Dictionary).has(id)


func achievement_defs() -> Dictionary:
	var out := {}
	for id in Content.ids("achievements"):
		out[str(id)] = Content.get_entry("achievements", str(id))
	return out


# --- workshop (MOD-07) ---------------------------------------------------------------------------

func supports_workshop() -> bool:
	return false


## Local behaviour: "publishing" exports a shareable package into the user packages folder; there
## are no subscriptions. A Steam adapter would download items into the user downloads folder and
## hand them to Mods.import_package().
func workshop_publish(mod_id: String) -> Dictionary:
	var out := Mods.export_package(mod_id)
	if out == "":
		return {"ok": false, "path": "", "message": "This mod cannot be exported (it has errors)."}
	return {"ok": true, "path": out, "message": "Workshop is not available in this build; saved a shareable package instead: %s" % out}


func workshop_list() -> Array:
	return []


# --- cloud saves ---------------------------------------------------------------------------------

func supports_cloud_saves() -> bool:
	return false


## Folders a cloud-save backend would sync (all under the user-data root; never the install).
func cloud_save_folders() -> PackedStringArray:
	return PackedStringArray(["profiles", "presets", "arenas", "runs", "policies", "mods/modsets.json"])
