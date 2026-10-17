extends SceneTree
## Configure only the isolated --user-root capture profile through the game's save API.
func _init() -> void:
	call_deferred("_configure")

func _configure() -> void:
	var settings: Node = root.get_node_or_null("Settings")
	if settings == null:
		push_error("Settings autoload is unavailable")
		quit(2)
		return
	settings.call("set_value", "gameplay.pause_on_focus_loss", false, true, true)
	print("Capture profile: pause_on_focus_loss=false")
	quit()
