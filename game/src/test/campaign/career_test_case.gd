class_name CareerTestCase
extends CampaignTestCase
## Shared helpers for the Career tests (CMP-08): careers with a fixed seed, a temp CareerStore,
## booking an offer straight to fight week, and synthetic bout results in both shapes (10-point
## result.scoring per design contract §2.8/B1, and plain HP-scoring results without it).

var store: CareerStore


func new_store() -> CareerStore:
	store = CareerStore.new(temp_dir("career_store_%d" % Time.get_ticks_usec()))
	return store


## A new career (seed 4242 unless opts.seed). with_store: autosaves into `store` (new_store()).
func new_career(opts := {}, with_store := false, catalog: CampaignCatalog = null) -> CareerController:
	var o := {"name": "Tester", "nick": "The Test", "fighter": "f_stoke", "difficulty": "normal", "seed": 4242, "created_at": 1}
	for k in opts:
		o[k] = opts[k]
	if with_store and store == null:
		new_store()
	var r := CareerController.create(catalog if catalog else cat(), o, store if with_store else null, "tester", int(opts.get("slot", 1)))
	check(bool(r["ok"]), "career created: %s" % r["error"])
	return r["ctrl"]


## Accepts the first offer (fields override the offer first) and jumps to fight week.
func book(ctrl: CareerController, fields := {}) -> Dictionary:
	var offers: Array = ctrl.state["offers"]
	if offers.is_empty():
		fail("no offers to book")
		return {}
	var o: Dictionary = offers[0]
	for k in fields:
		o[k] = fields[k]
	check(ctrl.accept(str(o["id"])), "accept: %s" % ctrl.last_error)
	ctrl.state["booked"]["weeks_left"] = 0
	return ctrl.booked()["offer"]


## A 10-point result. winner: team (0 = the career fighter) or -1. opts: {rounds (scored),
## landed: [me, opp] per round, kd: [me, opp] per round (knockdowns scored), taken: {head, body,
## legs} the career fighter took per round, stoppage_round (TKO), stoppage_time}.
func scoring_result(winner: int, method: String, opts := {}) -> Dictionary:
	var n := int(opts.get("rounds", 3))
	var landed: Array = opts.get("landed", [5, 5])
	var kd: Array = opts.get("kd", [0, 0])
	var taken: Dictionary = opts.get("taken", {"head": 10.0, "body": 10.0, "legs": 5.0})
	var cards := []
	for i in n:
		var me := {"damage": 20.0, "dmg_pts": 5.0, "landed": int(landed[0]), "blocked": 1, "thrown": 9, "knockdowns": int(kd[0]),
			"throws": 0, "ringouts": 0, "parries": 0, "guard_breaks": 0,
			"taken_head": float(taken.get("head", 0.0)), "taken_body": float(taken.get("body", 0.0)), "taken_legs": float(taken.get("legs", 0.0))}
		var them := {"damage": float(taken.get("head", 0.0)) + float(taken.get("body", 0.0)) + float(taken.get("legs", 0.0)), "dmg_pts": 4.0,
			"landed": int(landed[1]), "blocked": 1, "thrown": 9, "knockdowns": int(kd[1]), "throws": 0, "ringouts": 0, "parries": 0,
			"guard_breaks": 0, "taken_head": 8.0, "taken_body": 8.0, "taken_legs": 4.0}
		cards.append({"round": i + 1, "teams": [0, 1], "judges": [[10, 9], [10, 9], [10, 9]], "scores": [[9.0, 6.0], [9.0, 6.0], [9.0, 6.0]],
			"tally": [me, them], "winner": winner, "stoppage": false})
	var stoppage := {}
	if opts.has("stoppage_round"):
		stoppage = {"fighter": 1 if winner == 0 else 0, "by": winner, "round": int(opts["stoppage_round"]),
			"time": float(opts.get("stoppage_time", 42.0)), "reason": "knockdowns"}
		(cards[cards.size() - 1] as Dictionary)["stoppage"] = true
	var totals := [[30, 27], [29, 28], [29, 28]] if winner == 0 else ([[27, 30], [28, 29], [28, 29]] if winner == 1 else [[29, 29], [29, 29], [29, 29]])
	return {"mode": "standard", "winner_team": winner, "rounds": n, "time": 300.0, "round_wins": {},
		"fighters": [{"index": 0, "team": 0, "creature": "f_stoke", "name": "Tester", "out": false, "health": 110.0,
			"stats": {"damage_dealt": 60.0, "damage_taken": 75.0, "hits": 15, "blocks": 3, "parries": 0, "knockdowns": 0, "kos": 0, "throws": 0}},
			{"index": 1, "team": 1, "creature": "f_gusto", "name": "Opp", "out": false, "health": 85.0,
			"stats": {"damage_dealt": 75.0, "damage_taken": 60.0, "hits": 15, "blocks": 3, "parries": 0, "knockdowns": 0, "kos": 0, "throws": 0}}],
		"scoring": {"mode": "ten_point", "method": method, "winner": winner, "teams": [0, 1], "cards": cards, "totals": totals,
			"judges": ["Even card", "Volume", "Impact"], "stoppage": stoppage, "sudden_death": false}}


## A plain HP-scoring result (no "scoring"): winner team, the loser knocked out or not.
func hp_result(winner: int, ko := false, rounds := 2) -> Dictionary:
	var f0 := {"index": 0, "team": 0, "creature": "f_stoke", "name": "Tester", "out": winner == 1 and ko, "health": 0.0 if winner == 1 and ko else 50.0,
		"stats": {"damage_dealt": 120.0, "damage_taken": 100.0, "hits": 30, "blocks": 4, "parries": 1, "knockdowns": 1, "kos": 1 if winner == 0 and ko else 0, "throws": 1}}
	var f1 := {"index": 1, "team": 1, "creature": "f_gusto", "name": "Opp", "out": winner == 0 and ko, "health": 0.0 if winner == 0 and ko else 30.0,
		"stats": {"damage_dealt": 100.0, "damage_taken": 120.0, "hits": 25, "blocks": 2, "parries": 0, "knockdowns": 2, "kos": 1 if winner == 1 and ko else 0, "throws": 0}}
	return {"mode": "standard", "winner_team": winner, "rounds": rounds, "time": 200.0, "round_wins": {}, "fighters": [f0, f1]}
