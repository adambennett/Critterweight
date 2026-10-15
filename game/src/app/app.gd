extends Node
## Autoload "App": screen router, match launching and process lifecycle.
## Screens are registered by name -> script path; `goto` replaces the stack, `push` opens an
## overlay (dialogs, pause, settings-in-game), `back` pops (or asks the top screen first).

signal screen_changed(name: String)
signal match_started(scene: Node)
signal match_ended(result: Dictionary)

const SCREENS := {
	"title": "res://src/ui/screens/title_screen.gd",
	"main_menu": "res://src/ui/screens/main_menu.gd",
	"settings": "res://src/ui/screens/settings_screen.gd",
	"versus_setup": "res://src/ui/screens/versus_setup.gd",
	"character_select": "res://src/ui/screens/character_select.gd",
	"rules_editor": "res://src/ui/screens/rules_editor_screen.gd",
	"arena_editor": "res://src/editor/arena_editor_screen.gd",
	"online": "res://src/ui/screens/online_screen.gd",
	"lobby": "res://src/ui/screens/lobby_screen.gd",
	"campaign_menu": "res://src/campaign/ui/campaign_menu_screen.gd",
	"run_map": "res://src/campaign/ui/run_map_screen.gd",
	"reward": "res://src/campaign/ui/reward_screen.gd",
	"event": "res://src/campaign/ui/event_screen.gd",
	"shop": "res://src/campaign/ui/shop_screen.gd",
	"lab": "res://src/lab/ui/lab_screen.gd",
	"mods": "res://src/mods/ui/mods_screen.gd",
	"profile": "res://src/ui/screens/profile_screen.gd",
	"credits": "res://src/ui/screens/credits_screen.gd",
	"pause": "res://src/ui/screens/pause_menu.gd",
	"results": "res://src/ui/screens/results_screen.gd",
	"dialog": "res://src/ui/screens/dialog.gd",
	"spectate": "res://src/ui/screens/spectate_setup.gd",
	"bookie": "res://src/campaign/ui/bookie_screen.gd",
	"rest": "res://src/campaign/ui/rest_screen.gd",
	"run_summary": "res://src/campaign/ui/run_summary_screen.gd",
	"camp_ledger": "res://src/campaign/ui/camp_ledger_screen.gd",
	"hub": "res://src/hub/ui/hub_entry_screen.gd",
	"hub_board": "res://src/hub/ui/hub_board.gd",
	"tutorial_menu": "res://src/ui/screens/tutorial_menu.gd",
	"controls": "res://src/ui/screens/controls_screen.gd",
	"text_entry": "res://src/ui/screens/text_entry.gd",
	"ui_gallery": "res://src/ui/screens/ui_gallery.gd",
}

var ui_layer: CanvasLayer
var world: Node
var stack: Array = []            ## Array[Screen]
var current_scene: Node = null   ## active 3D scene (match, hub, editor preview)
var quitting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.name = "UI"
	add_child(ui_layer)
	world = Node.new()
	world.name = "World"
	add_child(world)
	get_tree().set_auto_accept_quit(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit()


func has_screen(name_: String) -> bool:
	return SCREENS.has(name_) and ResourceLoader.exists(SCREENS[name_])


func _make(name_: String, p: Dictionary) -> Screen:
	if not has_screen(name_):
		Log.e("app", "screen '%s' is not available" % name_)
		return null
	var s: Screen = load(SCREENS[name_]).new()
	s.screen_name = name_
	s.params = p
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(s)
	s.on_enter(p)
	return s


func top_screen() -> Screen:
	return stack.back() if not stack.is_empty() else null


## Replaces the whole stack with a new screen.
func goto(name_: String, p := {}) -> Screen:
	while not stack.is_empty():
		var s: Screen = stack.pop_back()
		s.on_exit()
		s.queue_free()
	var n := _make(name_, p)
	if n:
		stack.append(n)
		n.restore_focus()
		screen_changed.emit(name_)
	return n


## Opens a screen on top (the one below keeps its state and focus memory).
func push(name_: String, p := {}) -> Screen:
	var top := top_screen()
	if top:
		top.remember_focus()
	var n := _make(name_, p)
	if n:
		stack.append(n)
		n.restore_focus()
		screen_changed.emit(name_)
	return n


func back() -> void:
	var top := top_screen()
	if top == null:
		return
	if top.on_back():
		return
	if stack.size() <= 1:
		return
	pop()


func pop() -> void:
	if stack.is_empty():
		return
	var s: Screen = stack.pop_back()
	s.on_exit()
	s.queue_free()
	var t := top_screen()
	if t:
		t.on_resume()
		screen_changed.emit(t.screen_name)


func clear_screens() -> void:
	while not stack.is_empty():
		var s: Screen = stack.pop_back()
		s.on_exit()
		s.queue_free()


## Shows a modal message; `buttons` = [{label, id}] ; callback receives the chosen id.
func dialog(title: String, body: String, buttons: Array = [], callback: Callable = Callable()) -> void:
	if has_screen("dialog"):
		push("dialog", {"title": title, "body": body, "buttons": buttons, "callback": callback})
	else:
		Log.w("app", "%s: %s" % [title, body])


## Replaces the active 3D scene (match, hub, lab preview). Screens stay on the UI layer.
func set_scene(n: Node) -> void:
	if current_scene and is_instance_valid(current_scene):
		current_scene.queue_free()
	current_scene = n
	if n:
		world.add_child(n)


## Resolves a match config that may contain content ids into concrete defs.
## cfg: {arena: id|ArenaDef, rules: preset id|Dictionary, seed, context,
##       fighters: [{creature: id|CreatureDef, team, kind: player|bot|policy|net, difficulty, name, mods}]}
func resolve_match_config(cfg: Dictionary) -> Dictionary:
	var out := cfg.duplicate()
	var a = cfg.get("arena", "the_gullet")
	out["arena"] = a if a is ArenaDef else ArenaLibrary.resolve(str(a))   # content first, then saved/imported layouts
	if out["arena"] == null:
		out["arena"] = Content.arena("the_gullet")
	# a context may name the arena's look (campaign: gullet_day / gullet_title); unknown names are ignored
	var ctx = cfg.get("context", {})
	if typeof(ctx) == TYPE_DICTIONARY:
		out["arena"] = (out["arena"] as ArenaDef).with_variant(str((ctx as Dictionary).get("variant", "")))
	# unlocked looks that replace the stock one (the Cannery's Rooftop full neon) apply automatically
	out["arena"] = ArenaVariants.upgrade(out["arena"] as ArenaDef, Profiles.current)
	var r = cfg.get("rules", "duel")
	var rules: Dictionary = r if typeof(r) == TYPE_DICTIONARY else Content.get_entry("rules", str(r))
	out["rules"] = rules.duplicate(true)
	if not out.has("mode"):
		out["mode"] = ModeRegistry.create(str(rules.get("mode", "standard")))
	var fs := []
	for f in cfg.get("fighters", []):
		var e: Dictionary = f.duplicate()
		var c = f.get("creature")
		e["creature"] = c if c is CreatureDef else Content.creature(str(c))
		if e["creature"] == null:
			Log.e("app", "unknown creature %s" % str(c))
			continue
		fs.append(e)
	if not out.has("seed"):
		out["seed"] = randi()
	_fill_bots(rules, fs, int(out["seed"]))
	out["fighters"] = fs
	return out


## Rules "bots" (Fill with bots): adds that many bots at the rules' bot skill, never past the
## maximum fighters. Teams follow the format (co-op bots join the players' side).
func _fill_bots(rules: Dictionary, fs: Array, seed_value: int) -> void:
	var extra := int(rules.get("bots", 0))
	if extra <= 0:
		return
	var pl: Array = rules.get("players", [2, 8])
	var cap := mini(8, int(pl[1]) if pl.size() > 1 else 8)
	var roster := Content.playable_creatures().filter(func(c): return not str(c).begins_with("dev_"))
	if roster.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 977 + 13
	var fmt := str(rules.get("format", "duel"))
	var teams := maxi(1, int(rules.get("teams", 2)))
	var tier := BotTiers.brain_tier(str(rules.get("bot_tier", "journeyman")))
	var n := 0
	while n < extra and fs.size() < cap:
		var i := fs.size()
		var team := i
		if fmt == "coop":
			team = 0
		elif fmt in ["teams", "tag", "duel"]:
			team = i % teams
		var c := Content.creature(str(roster[rng.randi_range(0, roster.size() - 1)]))
		fs.append({"creature": c, "team": team, "kind": "bot", "difficulty": tier, "name": "%s (bot)" % c.display_name})
		n += 1


## Starts a local authoritative match with presentation. Menus are cleared; when the match
## ends the results screen is shown (or `on_finished` is called if given).
func start_match(cfg: Dictionary, on_finished: Callable = Callable()) -> MatchScene:
	var resolved := resolve_match_config(cfg)
	clear_screens()
	var scene := MatchScene.new()
	set_scene(scene)
	scene.start(resolved)
	if on_finished.is_valid():
		scene.set_meta("on_finished", on_finished)     # MatchFlow.restart() ends a restart the same way
	scene.match_finished.connect(func(result: Dictionary):
		_record_match(cfg, scene, result)
		match_ended.emit(result)
		if on_finished.is_valid():
			on_finished.call(result)
		elif has_screen("results"):
			push("results", {"result": result, "config": cfg}))
	match_started.emit(scene)
	return scene


## Records a finished match in the active profile exactly once (local player matches only;
## spectated, tutorial and online-client matches are not recorded here). Custom rules / mods
## mark the result custom so records stay separate (CMP-07, UI-11).
func _record_match(cfg: Dictionary, scene: MatchScene, result: Dictionary) -> void:
	if bool(cfg.get("spectate", false)) and float(result.get("time", 0.0)) > 20.0:
		Platform.unlock_achievement("ach_ringside")
	if bool(cfg.get("no_record", false)) or str(result.get("mode", "")) in ["tutorial", "practice"]:
		return
	var me := -1
	for i in (cfg.get("fighters", []) as Array).size():
		if str((cfg["fighters"][i] as Dictionary).get("kind", "")) == "player":
			me = i
			break
	if me < 0 or me >= scene.sim.fighters.size():
		return
	var f := scene.sim.fighters[me]
	var wt := int(result.get("winner_team", -2))
	var custom := bool(cfg.get("custom", false)) or not Mods.load_order.is_empty() or float(Settings.get_value("access.game_speed")) < 0.999
	var won := wt == f.team
	Profiles.record_match(won, wt == -1, f.creature.id, f.stats_record, float(result.get("time", 0.0)), custom)
	if won:
		Platform.unlock_achievement("ach_first_win")
		var rid := str((cfg.get("rules") as Dictionary).get("id", "")) if typeof(cfg.get("rules")) == TYPE_DICTIONARY else str(cfg.get("rules", ""))
		if bool(cfg.get("custom", false)) or RulePresets.is_user(rid):
			Platform.unlock_achievement("ach_house_rules")
		var pf: Dictionary = (Profiles.current["stats"] as Dictionary).get("per_fighter", {})
		var roster := Content.playable_creatures().filter(func(c): return str(c).begins_with("f_"))
		if not roster.is_empty() and roster.all(func(c): return int((pf.get(c, {}) as Dictionary).get("wins", 0)) > 0):
			Platform.unlock_achievement("ach_full_card")


func quit() -> void:
	if quitting:
		return
	quitting = true
	Log.i("app", "shutting down")
	if Engine.has_singleton("Net") or get_node_or_null("/root/Net"):
		get_node("/root/Net").call("shutdown")
	Profiles.save()
	get_tree().quit()
