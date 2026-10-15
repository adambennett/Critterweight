class_name MatchFlow
extends RefCounted
## UI-side match lifecycle around App.start_match():
##  - launch(cfg): starts a local match and, for spectating (cfg.spectate), switches the fight camera
##    to the auto-director and adds the spectator overlay. Remembers the config for Rematch/Restart.
##  - pause rules: offline matches pause the simulation AND the physics world (SceneTree.paused);
##    online matches never pause (pause menu says so). A match counts as online when its config has
##    "online": true, the scene is not a local MatchScene, or Net reports an active session
##    (Net.is_session_active(), if the net owner provides it).
## Config keys used by the UI (ignored by the sim): "spectate", "online", "ui": {mode, setup}.

static var last_config := {}


static func launch(cfg: Dictionary) -> MatchScene:
	last_config = cfg.duplicate(true)
	var scene := App.start_match(cfg)
	if scene == null:
		return null
	if bool(cfg.get("spectate", false)):
		scene.camera.mode = FightCamera.Mode.SPECTATE
		var ov := SpectatorOverlay.new()
		scene.hud_layer.add_child(ov)
		ov.setup(scene)
	return scene


static func current_match() -> MatchScene:
	var s = App.current_scene
	if s != null and is_instance_valid(s) and s is MatchScene:
		return s as MatchScene
	return null


static func match_running() -> bool:
	var s = App.current_scene
	if s == null or not is_instance_valid(s):
		return false
	if s is MatchScene:
		var ms := s as MatchScene
		return ms.sim != null and not ms.sim.is_finished
	return s.has_method("is_match_running") and bool(s.call("is_match_running"))


static func is_online() -> bool:
	var s = App.current_scene
	if s != null and is_instance_valid(s) and not (s is MatchScene) and not (s is MenuBackdrop):
		return true
	var ms := current_match()
	if ms != null and bool(ms.config.get("online", false)):
		return true
	if Net.has_method("is_session_active") and bool(Net.call("is_session_active")):
		return true
	return false


## Pauses/resumes a local match: sim stepping + the physics server (via SceneTree.paused).
static func set_paused(on: bool) -> void:
	var ms := current_match()
	if ms != null and ms.sim != null:
		ms.sim.paused = on
	(Engine.get_main_loop() as SceneTree).paused = on


static func open_pause(notice := "") -> void:
	if not App.has_screen("pause"):
		return
	App.push("pause", {"notice": notice})


## Leaves any match and returns to the main menu (unpausing first). The match scene is freed here;
## the main menu then installs the menu backdrop (skipped in headless runs).
static func quit_to_menu() -> void:
	set_paused(false)
	# online: quitting the match leaves the session (a listen host closes it for everyone with
	# "The host left"); Net removes its match scene itself
	if Net.has_method("is_session_active") and bool(Net.call("is_session_active")):
		Net.call("leave")
	if current_match() != null:
		App.set_scene(null)
	App.goto("main_menu")
