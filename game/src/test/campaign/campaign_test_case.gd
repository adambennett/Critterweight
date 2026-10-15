class_name CampaignTestCase
extends TestCase
## Shared helpers for campaign tests. Creature content that other owners author (roster
## fighters, npc_scrapling/npc_blister, bosses) is resolved through the test-only stand-in
## (dev_biped) when it is not installed, so these tests exercise the real campaign code paths
## against real MatchSim fights either way. Match-based tests run accelerated with SimSpeed.

const STAND_IN := "dev_biped"

var _cat: CampaignCatalog


func cat() -> CampaignCatalog:
	if _cat == null:
		_cat = CampaignCatalog.new(Content, STAND_IN)
	return _cat


func after_each() -> void:
	SimSpeed.restore()


func run_cfg(fighter := "f_stoke", extra := {}) -> Dictionary:
	var c := {"seed": 12345, "variant": "off_the_street", "difficulty": "amateur", "dose": 0, "created_at": 1,
		"players": [{"id": "p0", "name": "Tester", "profile_id": "test", "fighter": fighter}]}
	for k in extra:
		c[k] = extra[k]
	return c


func new_run(extra := {}, fighter := "f_stoke") -> RunController:
	return RunController.start_run(cat(), run_cfg(fighter, extra))


## A synthetic fight result (for state-machine tests that do not need physics).
func fake_result(ctrl: RunController, won := true, hp_frac := 0.8, extra := {}) -> Dictionary:
	var players := {}
	for p in ctrl.players():
		var r := {"hp": ctrl.max_hp(p) * hp_frac, "hype": 40.0, "out": false, "knockdowns": int(extra.get("knockdowns", 0)),
			"kos": 1, "minion_kos": 0, "damage_dealt": 30.0, "damage_taken": 10.0, "biggest_hit": 9.0, "taunts": 1, "downs": 0,
			"hit_by_boss": bool(extra.get("hit_by_boss", true))}
		if not won:
			r["hp"] = 0.0
			r["out"] = true
		players[str(p["id"])] = r
	return {"campaign": {"won": won, "time": 60.0, "players": players}}


## Resolves everything at the current node with simple deterministic choices (first option).
func settle_node(ctrl: RunController) -> void:
	var guard := 0
	while not ctrl.is_over() and ctrl.phase() != "map" and guard < 40:
		guard += 1
		match ctrl.phase():
			"fight":
				ctrl.complete_fight(fake_result(ctrl))
			"event":
				var v := ctrl.event_view("p0")
				var picked := false
				for c in v.get("choices", []):
					if bool(c["available"]) and not picked:
						picked = ctrl.choose_event("p0", str(c["id"]))
				if not picked:
					fail("no available event choice at %s" % ctrl.state["position"])
					return
			"shop":
				for pid in RunState.player_ids(ctrl.state):
					ctrl.shop_leave(pid)
			"rest":
				for pid2 in RunState.player_ids(ctrl.state):
					ctrl.rest_choose(pid2, "patch_up")
			"reward":
				for pid3 in RunState.player_ids(ctrl.state):
					for e in ctrl.pending_for(pid3).duplicate():
						var opts: Array = e.get("options", [])
						ctrl.claim(pid3, str(e["rid"]), str(opts[0]) if not opts.is_empty() else "skip")


## Plays a whole run with synthetic fight results, always taking the first route.
func play_synthetic(ctrl: RunController, lose_at_node := -1) -> void:
	var n := 0
	while not ctrl.is_over() and n < 40:
		var av := ctrl.available_nodes()
		if av.is_empty():
			fail("no available nodes in phase %s" % ctrl.phase())
			return
		ctrl.choose_node(str(av[0]), "p0")
		n += 1
		if n == lose_at_node and ctrl.phase() == "fight":
			ctrl.complete_fight(fake_result(ctrl, false))
			return
		settle_node(ctrl)
