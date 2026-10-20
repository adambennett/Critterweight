class_name CareerFlow
extends RefCounted
## UI glue for the persistent Career (CMP-08), in the CampaignFlow pattern: every career screen
## receives the flow as params["flow"] and acts through `ctrl` (the CareerController is the only
## writer of the save and autosaves after every action). There is no global career state.
##   main menu > career (slots) > career_new > career_hub <-> bout > career_result > career_hub
## Fight lifecycle (design contract D4):
##   fight()          FIGHT on fight week: builds the bout (ctrl.fight_config), marks it in progress
##                    and saves (ctrl.begin_fight), then launch_match() presents it. The match scene
##                    keeps the flow alive (meta "career_flow"; Callables do not retain RefCounted
##                    targets) and MatchFlow's restart config is cleared: a career bout is never
##                    restarted from the pause menu.
##   finish_fight()   the bout's result is applied once (ctrl.apply_result is idempotent per fight
##                    id) and career_result shows it; a refused result returns to the hub.
##   pull_out()       the pause menu's "Quit to main menu" in a career bout: a withdrawal
##                    (popularity -4, week +1, no purse), then MatchFlow.quit_to_menu().
##   A crash or killed process leaves booked.in_fight set: ctrl.interrupted() is true and the slot
##   list and the hub offer the identical bout again (same seed, opponent, bot and arena).
## Career results never touch the profile's records (no_record) and are NOT written into the
## profile history either: that list is capped at 60 entries and shared with the campaign runs the
## Cannery's Wall of Fame reads, so career bouts would push those out. summary.profile_history is
## left unused on purpose (reported as a design question).
## Tests subclass this and override launch_match() to settle bouts synthetically; screens pass the
## flow's script along (flow_script) so the subclass survives slot list -> new career -> hub.

var catalog: CampaignCatalog
var ctrl: CareerController
var store: CareerStore
var last_summary := {}
var last_error := ""
var notice := ""          ## a one-shot line the hub shows on its next build (a refused result, ...)


## The catalog career screens use when nothing passes one in (the same rules the model reads).
## --campaign-stand-ins (a developer flag) fills unfinished roster kits with the test stand-in.
static func default_catalog() -> CampaignCatalog:
	if OS.get_cmdline_user_args().has("--campaign-stand-ins"):
		return CampaignFlow.make_catalog(true)
	return CampaignCatalog.shared()


## Careers belong to the active profile (three slots each).
static func profile_key() -> String:
	return CampaignFlow.profile_key()


## A flow over a controller. `script_`: a CareerFlow subclass (tests), else CareerFlow.
static func make(cat: CampaignCatalog, ctrl_: CareerController, script_: Script = null) -> CareerFlow:
	var f: CareerFlow = null
	if script_ != null:
		f = script_.new() as CareerFlow
	if f == null:
		f = CareerFlow.new()
	f.catalog = cat
	f.ctrl = ctrl_
	f.store = ctrl_.store if ctrl_ != null else null
	return f


## Loads a slot of the active profile. Returns {ok, error, flow, load} (load = the store's report).
static func open_slot(cat: CampaignCatalog, store_: CareerStore, slot_n: int, script_: Script = null) -> Dictionary:
	var r := CareerController.load_career(cat, store_, profile_key(), slot_n)
	if not bool(r["ok"]):
		return {"ok": false, "error": str(r["error"]), "flow": null, "load": r.get("load", {})}
	var c: CareerController = r["ctrl"]
	return {"ok": true, "error": "", "flow": make(cat, c, script_), "load": r.get("load", {})}


## Creates a career in a slot of the active profile (saved right away). opts: CareerController.create.
## Returns {ok, error, flow}.
static func start_career(cat: CampaignCatalog, store_: CareerStore, opts: Dictionary, slot_n: int, script_: Script = null) -> Dictionary:
	var r := CareerController.create(cat, opts, store_, profile_key(), slot_n)
	if not bool(r["ok"]):
		return {"ok": false, "error": str(r["error"]), "flow": null}
	var c: CareerController = r["ctrl"]
	return {"ok": true, "error": "", "flow": make(cat, c, script_)}


## The match scene's career flow, or null when the scene is not a career bout.
static func of_scene(scene: Node) -> CareerFlow:
	if scene == null or not is_instance_valid(scene) or not scene.has_meta("career_flow"):
		return null
	return scene.get_meta("career_flow") as CareerFlow


## "No purse, popularity -4." (the withdrawal terms, from the career rules).
func withdraw_terms() -> String:
	var pop := float(ctrl.rules.get("withdraw_pop", 4.0)) if ctrl != null else 4.0
	return "No purse, popularity -%s." % CareerUi.num(pop)


func show_hub(tab := "") -> void:
	App.goto("career_hub", {"flow": self, "tab": tab})


## Back to the slot list (the career is already saved).
func show_slots() -> void:
	App.goto("career", {"catalog": catalog, "flow_script": get_script()})


## FIGHT on fight week. False (last_error) when the bout cannot be made; the career is untouched then.
func fight() -> bool:
	last_error = ""
	if ctrl == null or not ctrl.fight_ready():
		last_error = "It is not fight week yet."
		return false
	var built := ctrl.fight_config()
	var errs: PackedStringArray = built["errors"]
	if not errs.is_empty() or (built["config"] as Dictionary).is_empty():
		last_error = "This fight can't be made: %s." % ", ".join(errs)
		return false
	if not ctrl.begin_fight():
		last_error = ctrl.last_error
		return false
	launch_match(built["config"])
	return true


## Presents the bout (tests override this to settle it synthetically).
func launch_match(cfg: Dictionary) -> void:
	SimSpeed.restore()
	# the pause menu's "Restart fight" replays MatchFlow.last_config: a career bout must never be
	# restarted (that would be a free re-roll of a fight the cards say you are losing)
	MatchFlow.last_config = {}
	var scene := App.start_match(cfg, _on_match_finished)
	if scene != null:
		scene.set_meta("career_flow", self)


func _on_match_finished(result: Dictionary) -> void:
	App.set_scene(null)
	finish_fight(result)


## Applies the bout's result once and shows it (career_result); a refused result (already settled,
## no result) returns to the hub with the reason. Returns the apply_result summary.
func finish_fight(result: Dictionary) -> Dictionary:
	var s := ctrl.apply_result(result, ctrl.booked_id())
	if not bool(s.get("ok", false)):
		notice = "The bout was not scored: %s" % str(s.get("error", ""))
		show_hub("camp")
		return s
	last_summary = s
	App.goto("career_result", {"flow": self, "summary": s})
	return s


## The pause menu's quit in a career bout (D4): a withdrawal, then back to the main menu.
func pull_out() -> bool:
	var ok := ctrl != null and ctrl.withdraw()
	var terms := withdraw_terms()
	MatchFlow.quit_to_menu()
	if ok:
		UiNav.toast("You pulled out of the fight. %s" % terms, "warning", 5.0)
	return ok
