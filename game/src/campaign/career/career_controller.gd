class_name CareerController
extends RefCounted
## The persistent Career (CMP-08): the Cage Rules career loop (js/career.js) over one CareerState
## dict. This is the only writer of the state; screens (WP5) call the methods below and read the
## plain-data helpers. Every mutating call validates, mutates, writes a news line where Cage Rules
## does, and commits: `changed` is emitted and the career autosaves to its CareerStore slot.
##
## Week loop: train one stat or rest per week (unbooked weeks cost popularity and bring new
## offers), accept an offer (camp of N weeks), fight on fight week, apply the result once.
## Fight lifecycle (design contract D4):
##   begin_fight()   marks booked.in_fight and saves BEFORE the bout launches
##   apply_result()  claims the fight id once (a second result for it is rejected), pays, moves
##                   popularity, records, injures, titles, history, news, next week + offers
##   withdraw()      pulled out (Cage Rules): popularity -4, week +1, no purse, offers re-rolled
##   interrupted()   a bout that crashed / was killed (in_fight, unclaimed) is re-fought with the
##                   same seed, opponent, bot and arena (fight_config is a pure function of state)
## Missing content (D9): stale offers are re-rolled on load (repair); a booked fight whose
## opponent or arena is gone can be cancelled without penalty (cancel_booked).
## Results with result.scoring (10-point, design contract §2.8/B1) or without it (HP scoring:
## derived from winner_team; -1 = draw) are both accepted.

signal changed(reason: String)

var catalog: CampaignCatalog
var rules := {}
var state := {}
var store: CareerStore = null       ## null = no autosave (tests, previews)
var profile_id := ""
var slot := 0
var last_error := ""
var last_save_error := OK
## Set by repair() when it changed the loaded state (stale offers re-rolled), for the UI.
var repairs: Array = []


func _init(cat: CampaignCatalog = null, st: Dictionary = {}) -> void:
	catalog = cat
	rules = CareerDefaults.for_catalog(cat)
	state = st


# =============================================================================================
# Creating and loading
# =============================================================================================

## A new career. opts: {name, nick, fighter, difficulty, seed, created_at, content_hash}.
## Returns {ok, error, ctrl}. With a store, the career is saved to `slot_n` right away.
static func create(cat: CampaignCatalog, opts: Dictionary, store_: CareerStore = null, profile_id_ := "", slot_n := 1) -> Dictionary:
	var fighter := str(opts.get("fighter", ""))
	if fighter == "" or not cat.available_fighters().has(fighter):
		return {"ok": false, "error": "Pick a fighter to start a career with.", "ctrl": null}
	if store_ != null:
		if not CareerStore.valid_slot(slot_n):
			return {"ok": false, "error": "There is no career slot %d." % slot_n, "ctrl": null}
		if store_.occupied(profile_id_, slot_n):
			return {"ok": false, "error": "Career slot %d is in use. Retire that career or move it aside first." % slot_n, "ctrl": null}
	var c := CareerController.new(cat)
	var o := opts.duplicate()
	o["profile_id"] = profile_id_
	o["slot"] = slot_n
	c.state = CareerState.create(c.rules, o)
	c.store = store_
	c.profile_id = profile_id_
	c.slot = slot_n
	c._roll_offers(false)
	var towns: Array = (c.rules.get("names", {}) as Dictionary).get("towns", ["the docks"])
	var trng := RunRng.stream(int(c.state["seed"]), "career/start")
	var town := str(towns[mini(towns.size() - 1, int(trng.randf() * towns.size()))]) if not towns.is_empty() else "the docks"
	c._say("Career started out of a %s boiler-room gym. Regional promoters are calling." % town)
	if not c._commit("create"):
		return {"ok": false, "error": "The career could not be saved (%s)." % error_string(c.last_save_error), "ctrl": c}
	return {"ok": true, "error": "", "ctrl": c}


## A controller over a loaded state (repairs stale offers; autosaves when it did).
static func from_state(cat: CampaignCatalog, st: Dictionary, store_: CareerStore = null, profile_id_ := "", slot_n := 0) -> CareerController:
	var c := CareerController.new(cat, st)
	c.store = store_
	c.profile_id = profile_id_
	c.slot = slot_n if slot_n > 0 else int(st.get("slot", 1))
	c.repair()
	return c


## Loads a slot. Returns {ok, error, ctrl, load} (load = CareerStore.load_slot's report).
static func load_career(cat: CampaignCatalog, store_: CareerStore, profile_id_: String, slot_n: int) -> Dictionary:
	var r := store_.load_slot(profile_id_, slot_n, cat)
	if not bool(r["ok"]):
		return {"ok": false, "error": str(r["error"]), "ctrl": null, "load": r}
	var c := from_state(cat, r["state"], store_, profile_id_, slot_n)
	return {"ok": true, "error": "", "ctrl": c, "load": r}


## Re-rolls offers that name content which is no longer installed (and rolls offers for an
## unbooked career that has none). Returns true when it changed (and saved) the state.
func repair() -> bool:
	repairs.clear()
	if is_booked():
		if not (state.get("offers", []) as Array).is_empty():
			state["offers"] = []
			repairs.append("offers cleared while booked")
	else:
		var stale := false
		for o in state.get("offers", []):
			if not CareerState.offer_missing(catalog, o).is_empty():
				stale = true
		if stale:
			# a new roll for this week (the same roll would draw the same, now impossible, fights)
			_roll_offers(true)
			repairs.append("offers re-rolled")
			_say("An offer fell through (that fighter or venue is gone). New offers came in.")
		elif (state.get("offers", []) as Array).is_empty():
			state["offers"] = CareerOffers.make_offers(catalog, rules, state)     # this week's own roll
			if not (state.get("offers", []) as Array).is_empty():
				repairs.append("offers rolled")
	if repairs.is_empty():
		return false
	_commit("repair")
	return true


# =============================================================================================
# Week loop
# =============================================================================================

func is_booked() -> bool:
	return not (state.get("booked", {}) as Dictionary).is_empty()


func booked() -> Dictionary:
	return state.get("booked", {})


func fight_ready() -> bool:
	return is_booked() and int(booked().get("weeks_left", 0)) <= 0


## A bout that started but never reported (crash / killed process): fight it again (D4).
func interrupted() -> bool:
	return is_booked() and bool(booked().get("in_fight", false)) and not (state.get("claims", []) as Array).has(booked_id())


func booked_id() -> String:
	return str(booked().get("offer", {}).get("id", "")) if is_booked() else ""


## Cage Rules trainGain for one week of `stat` (0..1 stat units; x100 for display).
func preview_gain(stat: String) -> float:
	if not CareerDefaults.STATS.has(stat):
		return 0.0
	var tr: Dictionary = rules.get("training", {})
	var s := float(state["stats"].get(stat, 0.0))
	var lvl := int(state["gym"].get(stat, 0))
	var coach := int(state["gym"].get("coach", 0))
	var facility := 1.0 + lvl * float(tr.get("room_per_level", 0.3))
	var coach_mul := 1.0 + coach * float(tr.get("coach_per_level", 0.12))
	var dimin := pow(maxf(0.0, 1.0 - s), float(tr.get("dimin_exp", 1.2))) + float(tr.get("dimin_floor", 0.1))
	var hurt := 1.0 - CareerState.injury_total(state) / float(tr.get("injury_div", 260.0))
	return float(tr.get("base", 0.026)) * facility * coach_mul * dimin * maxf(float(tr.get("injury_floor", 0.35)), hurt)


## Healing per region this week (Cage Rules healWeek).
func heal_amount(rest_week: bool) -> float:
	var h: Dictionary = rules.get("healing", {})
	return (float(h.get("base", 10.0)) + int(state["gym"].get("recovery", 0)) * float(h.get("recovery_per_level", 4.0))) \
		* (float(h.get("rest_mult", 2.5)) if rest_week else 1.0)


## One week: train `focus` (a stat) or "rest". Returns {ok, error, week, focus, gain, before,
## after, healed, fight_ready}.
func train(focus: String) -> Dictionary:
	var out := {"ok": false, "error": "", "week": int(state["week"]), "focus": focus, "gain": 0.0, "before": 0.0,
		"after": 0.0, "healed": 0.0, "fight_ready": false}
	if fight_ready():
		out["error"] = "It's fight week: step in, or pull out."
		return _fail(out)
	if focus != "rest" and not CareerDefaults.STATS.has(focus):
		out["error"] = "Unknown training focus '%s'." % focus
		return _fail(out)
	if focus == "rest":
		out["healed"] = _heal(true)
	else:
		var before := float(state["stats"][focus])
		var g := preview_gain(focus)
		var after := snappedf(clampf(before + g, 0.0, float(rules.get("stat_cap", 0.99))), 0.0001)
		state["stats"][focus] = after
		out["before"] = before
		out["after"] = after
		out["gain"] = after - before
		out["healed"] = _heal(false)
	state["week"] = int(state["week"]) + 1
	if is_booked():
		var b: Dictionary = state["booked"]
		(b["plan"] as Array).append(focus)
		b["weeks_left"] = maxi(0, int(b["weeks_left"]) - 1)
	else:
		# no fight booked: a quiet week costs a sliver of popularity and brings new offers
		state["pop"] = maxf(0.0, snappedf(float(state["pop"]) - float(rules.get("idle_week_pop", 0.6)), 0.1))
		_roll_offers(false)
	out["ok"] = true
	out["fight_ready"] = fight_ready()
	state["last_train"] = out.duplicate()
	_commit("train")
	return out


func rest() -> Dictionary:
	return train("rest")


func _heal(rest_week: bool) -> float:
	var h := heal_amount(rest_week)
	for r in CareerDefaults.REGIONS:
		state["injury"][r] = maxf(0.0, float(state["injury"].get(r, 0.0)) - h)
	return h


## Signs an offer: camp of offer.weeks weeks. Returns false (last_error) when it cannot.
func accept(offer_id: String) -> bool:
	if is_booked():
		last_error = "You are already booked."
		return false
	var o := find_offer(offer_id)
	if o.is_empty():
		last_error = "That offer is gone."
		return false
	var miss := CareerState.offer_missing(catalog, o)
	if not miss.is_empty():
		last_error = "That fight can't be made: %s is not installed." % ", ".join(PackedStringArray(miss))
		return false
	state["booked"] = {"offer": o.duplicate(true), "weeks_left": int(o.get("weeks", 4)), "plan": [], "in_fight": false,
		"accepted_week": int(state["week"]), "starts": 0}
	state["offers"] = []
	_say("Signed to fight %s for %s in %d weeks." % [str(o["opp"].get("name", "?")), str(o.get("org_name", "")), int(o.get("weeks", 4))])
	last_error = ""
	_commit("accept")
	return true


func find_offer(offer_id: String) -> Dictionary:
	for o in state.get("offers", []):
		if str(o.get("id", "")) == offer_id:
			return o
	return {}


## Pulled out of the booked fight (Cage Rules withdraw: popularity -4, week +1, no purse, new
## offers). Also what quitting a career bout from the pause menu does (D4).
func withdraw() -> bool:
	if not is_booked():
		last_error = "No fight is booked."
		return false
	var o: Dictionary = booked()["offer"]
	state["pop"] = maxf(0.0, snappedf(float(state["pop"]) - float(rules.get("withdraw_pop", 4.0)), 0.1))
	_claim(str(o.get("id", "")))
	_say("Pulled out of the %s fight. %s is not happy. Popularity -%s." % [str(o["opp"].get("name", "?")), str(o.get("org_name", "")), _num(float(rules.get("withdraw_pop", 4.0)))])
	state["booked"] = {}
	state["week"] = int(state["week"]) + 1
	_roll_offers(false)
	last_error = ""
	_commit("withdraw")
	return true


## Content the booked fight needs that is gone (["creature:<id>", "arena:<id>"]).
func booked_missing() -> Array:
	return CareerState.offer_missing(catalog, booked().get("offer", {})) if is_booked() else []


## D9: a booked fight with missing content is called off without penalty (week unchanged,
## offers re-rolled). Refused while the content is all there (that is a withdrawal).
func cancel_booked() -> bool:
	if not is_booked():
		last_error = "No fight is booked."
		return false
	var miss := booked_missing()
	if miss.is_empty():
		last_error = "The fight can still be made; pulling out is a withdrawal."
		return false
	var o: Dictionary = booked()["offer"]
	_claim(str(o.get("id", "")))
	_say("The %s fight was called off (%s is gone). No penalty." % [str(o["opp"].get("name", "?")), ", ".join(PackedStringArray(miss))])
	state["booked"] = {}
	_roll_offers(true)
	last_error = ""
	_commit("cancel")
	return true


# =============================================================================================
# Gym
# =============================================================================================

func facility(id: String) -> Dictionary:
	for f in rules.get("facilities", []):
		if str(f.get("id", "")) == id:
			return f
	return {}


func upgrade_cost(id: String, level: int) -> int:
	var costs: Array = rules.get("coach_cost" if id == "coach" else "facility_cost", [])
	return int(costs[level]) if level >= 0 and level < costs.size() else -1


## Rows for the Gym page (FightCamp.list_upgrades shape): {id, name, stat, desc, effect, level,
## max_level, next_cost, maxed, locked, lock_reason, affordable}.
func upgrade_rows() -> Array:
	var out := []
	var fmax := int(rules.get("facility_max", 5))
	var money := int(state["money"])
	var tr: Dictionary = rules.get("training", {})
	for f in rules.get("facilities", []):
		var id := str(f.get("id", ""))
		var lv := int(state["gym"].get(id, 0))
		var maxed := lv >= fmax or upgrade_cost(id, lv) < 0
		var cost := -1 if maxed else upgrade_cost(id, lv)
		var effect := ""
		match id:
			"coach":
				effect = "+%d%% to all training per level" % int(round(float(tr.get("coach_per_level", 0.12)) * 100.0))
			"recovery":
				effect = "+%s healing a week per level" % _num(float((rules.get("healing", {}) as Dictionary).get("recovery_per_level", 4.0)))
			_:
				effect = "+%d%% %s training per level" % [int(round(float(tr.get("room_per_level", 0.3)) * 100.0)), stat_label(str(f.get("stat", id)))]
		out.append({"id": id, "name": str(f.get("name", id)), "stat": str(f.get("stat", "")), "desc": str(f.get("desc", "")),
			"effect": effect, "level": lv, "max_level": fmax, "next_cost": cost, "maxed": maxed, "locked": false,
			"lock_reason": "", "affordable": not maxed and money >= cost})
	return out


## Buys the next level of a facility. Returns {ok, error, level, money}.
func buy_upgrade(id: String) -> Dictionary:
	var f := facility(id)
	if f.is_empty():
		return _fail({"ok": false, "error": "Unknown facility '%s'." % id, "level": 0, "money": int(state["money"])})
	var lv := int(state["gym"].get(id, 0))
	var cost := upgrade_cost(id, lv)
	if lv >= int(rules.get("facility_max", 5)) or cost < 0:
		return _fail({"ok": false, "error": "Already at the top level.", "level": lv, "money": int(state["money"])})
	if int(state["money"]) < cost:
		return _fail({"ok": false, "error": "Not enough money (%s / %s)." % [money_text(int(state["money"])), money_text(cost)], "level": lv, "money": int(state["money"])})
	state["money"] = int(state["money"]) - cost
	state["gym"][id] = lv + 1
	_say("%s upgraded to level %d." % [str(f.get("name", id)), lv + 1])
	last_error = ""
	_commit("upgrade")
	return {"ok": true, "error": "", "level": lv + 1, "money": int(state["money"])}


# =============================================================================================
# The fight
# =============================================================================================

## The booked bout's match config (CareerFight.build): {config, errors, warnings, seed, max_seconds}.
func fight_config(opts := {}) -> Dictionary:
	return CareerFight.build(catalog, rules, state, opts)


## Marks the booked bout as in progress and saves BEFORE it launches (D4). False when it is not
## fight week or the fight cannot be made.
func begin_fight() -> bool:
	if not fight_ready():
		last_error = "It is not fight week."
		return false
	if not booked_missing().is_empty():
		last_error = "The fight can't be made: %s is not installed." % ", ".join(PackedStringArray(booked_missing()))
		return false
	var b: Dictionary = state["booked"]
	b["in_fight"] = true
	b["starts"] = int(b.get("starts", 0)) + 1
	last_error = ""
	_commit("begin_fight")
	return true


## What happened in a finished bout, from the team-0 (career fighter) side. Works with and without
## result.scoring. Returns {winner, won, draw, method, finish, split, round, time, rounds_scored,
## landed: [me, opp], knockdowns: [me, opp] (scored BY each side), taken: {head, body, legs} (by
## the career fighter), totals: [[me, opp] x judges], stoppage: bool, scoring: bool}.
static func read_outcome(result: Dictionary, me_team := 0) -> Dictionary:
	var out := {"winner": -2, "won": false, "draw": false, "method": "", "finish": false, "split": false, "round": 1,
		"time": 0.0, "rounds_scored": 0, "landed": [0, 0], "knockdowns": [0, 0], "taken": {"head": 0.0, "body": 0.0, "legs": 0.0},
		"damage_taken": 0.0, "totals": [], "stoppage": false, "scoring": false}
	var sc = result.get("scoring", null)
	if typeof(sc) == TYPE_DICTIONARY and not (sc as Dictionary).is_empty():
		var s: Dictionary = sc
		out["scoring"] = true
		var teams: Array = s.get("teams", [0, 1])
		var mi := 0
		for i in teams.size():
			if int(teams[i]) == me_team:
				mi = i
		var oi := 1 - mi if teams.size() >= 2 else 0
		out["winner"] = int(s.get("winner", result.get("winner_team", -2)))
		out["method"] = str(s.get("method", ""))
		var stop = s.get("stoppage", {})
		var cards: Array = s.get("cards", [])
		out["rounds_scored"] = cards.size()
		out["round"] = maxi(1, cards.size())
		if typeof(stop) == TYPE_DICTIONARY and not (stop as Dictionary).is_empty():
			out["stoppage"] = true
			out["round"] = maxi(1, int((stop as Dictionary).get("round", cards.size())))
			out["time"] = float((stop as Dictionary).get("time", 0.0))
		var landed := [0, 0]
		var kds := [0, 0]
		var taken := {"head": 0.0, "body": 0.0, "legs": 0.0}
		var dmg := 0.0
		for c in cards:
			var tl = c.get("tally", [])
			if typeof(tl) != TYPE_ARRAY or (tl as Array).size() < 2:
				continue
			var a: Dictionary = tl[mi] if typeof(tl[mi]) == TYPE_DICTIONARY else {}
			var b: Dictionary = tl[oi] if typeof(tl[oi]) == TYPE_DICTIONARY else {}
			landed[0] = int(landed[0]) + int(a.get("landed", 0))
			landed[1] = int(landed[1]) + int(b.get("landed", 0))
			kds[0] = int(kds[0]) + int(a.get("knockdowns", 0))
			kds[1] = int(kds[1]) + int(b.get("knockdowns", 0))
			for r in CareerDefaults.REGIONS:
				taken[r] = float(taken[r]) + float(a.get("taken_%s" % r, 0.0))
			dmg += float(b.get("damage", 0.0))
		out["landed"] = landed
		out["knockdowns"] = kds
		out["taken"] = taken
		out["damage_taken"] = dmg
		var tot := []
		for t in s.get("totals", []):
			if typeof(t) == TYPE_ARRAY and (t as Array).size() >= 2:
				tot.append([int(t[mi]), int(t[oi])])
		out["totals"] = tot
	else:
		# HP scoring (no judges): derive the outcome from the winner and who was left standing
		out["winner"] = int(result.get("winner_team", -2))
		var me_f := {}
		var opp_f := {}
		for f in result.get("fighters", []):
			if int(f.get("team", -1)) == me_team and me_f.is_empty():
				me_f = f
			elif int(f.get("team", -1)) != me_team and opp_f.is_empty():
				opp_f = f
		var w := int(out["winner"])
		var loser: Dictionary = opp_f if w == me_team else me_f
		out["finish"] = w >= 0 and bool(loser.get("out", false))
		out["method"] = "KO" if bool(out["finish"]) else ("Decision" if w >= 0 else "Draw")
		out["round"] = maxi(1, int(result.get("rounds", 1)))
		out["rounds_scored"] = int(result.get("rounds", 1))
		var ms: Dictionary = me_f.get("stats", {})
		var os: Dictionary = opp_f.get("stats", {})
		out["landed"] = [int(ms.get("hits", 0)), int(os.get("hits", 0))]
		# stats_record "knockdowns" counts knockdowns SUFFERED: scored by me = suffered by them
		out["knockdowns"] = [int(os.get("knockdowns", 0)), int(ms.get("knockdowns", 0))]
		out["damage_taken"] = float(ms.get("damage_taken", 0.0))
		out["stoppage"] = bool(out["finish"])
	var wt := int(out["winner"])
	out["won"] = wt == me_team
	out["draw"] = wt == -1
	var m := str(out["method"])
	if bool(out["scoring"]):
		out["finish"] = m == "TKO" or m.begins_with("TKO")
	out["split"] = m == "Split Decision"
	return out


## Applies a finished bout once (claim per fight id). Returns the result-screen summary
## {ok, error, duplicate, fight_id, won, draw, result, method, finish, round, time, rounds, opp,
## org_name, tier, tier_name, title, title_note, pay, purse, bonus, d_pop, pop_before, pop,
## pop_label, standing, injury_added, injury, record, record_text, streak, champion,
## title_defences, scoring, totals, landed, knockdowns, action, action_bonus, week_label, news,
## history_entry, profile_history}.
func apply_result(result: Dictionary, fight_id := "") -> Dictionary:
	var out := {"ok": false, "error": "", "duplicate": false, "fight_id": fight_id}
	if fight_id != "" and (state.get("claims", []) as Array).has(fight_id):
		out["duplicate"] = true
		out["error"] = "That fight was already settled."
		return _fail(out)
	if not is_booked():
		out["error"] = "No fight is booked."
		return _fail(out)
	var o: Dictionary = booked()["offer"]
	var fid := str(o.get("id", ""))
	out["fight_id"] = fid
	if fight_id != "" and fight_id != fid:
		out["error"] = "That result belongs to another fight."
		return _fail(out)
	if (state["claims"] as Array).has(fid):
		out["duplicate"] = true
		out["error"] = "That fight was already settled."
		return _fail(out)
	if not fight_ready():
		out["error"] = "The fight is not due yet."
		return _fail(out)
	if result.is_empty() or bool(result.get("left", false)) or bool(result.get("aborted", false)):
		out["error"] = "The fight ended without a result."
		return _fail(out)
	var oc := read_outcome(result, CareerFight.PLAYER_TEAM)
	if int(oc["winner"]) == -2:
		out["error"] = "The fight ended without a result."
		return _fail(out)
	var won := bool(oc["won"])
	var draw := bool(oc["draw"])
	var finish := bool(oc["finish"])
	var rnd := int(oc["round"])
	var method := str(oc["method"])
	var tier_i := clampi(int(o.get("tier", 0)), 0, 3)
	var title := bool(o.get("title", false))
	var rounds := int(o.get("rounds", 3))
	var pp: Dictionary = rules.get("popularity", {})
	var mults: Array = rules.get("tier_pop_mult", [1.0, 1.4, 1.8, 2.4])
	var caps: Array = rules.get("tier_pop_cap", [42, 66, 88, 100])
	var tm := float(mults[clampi(tier_i, 0, mults.size() - 1)])
	var pop_before := float(state["pop"])
	# popularity (Cage Rules applyResult): bigger orgs and quicker finishes are worth more
	var d_pop := 0.0
	if won:
		d_pop = float(pp.get("win", 4.0)) * tm
		if finish:
			d_pop += (float(pp.get("finish", 3.0)) + maxi(0, rounds - rnd) * float(pp.get("finish_per_round_left", 2.5))) * tm
		if bool(oc["split"]):
			d_pop *= float(pp.get("split_mult", 0.75))
		if title:
			d_pop += float(pp.get("title_win", 6.0))
		if int(state["streak"]) >= int(pp.get("streak_min", 2)):
			d_pop += float(pp.get("streak_bonus", 1.5))
	elif draw:
		d_pop = float(pp.get("draw", 0.5))
	else:
		d_pop = -(float(pp.get("loss", 3.0)) + float(pp.get("loss_per_mult", 1.5)) * tm)
		if finish and rnd == 1:
			d_pop -= float(pp.get("r1_finish_loss", 2.0))
		if title:
			d_pop -= float(pp.get("title_loss", 3.0))
	# a fight-of-the-night pace sells too (combined clean strikes per scored round)
	var action := float(int(oc["landed"][0]) + int(oc["landed"][1])) / float(maxi(1, int(oc["rounds_scored"])))
	var action_bonus := action > float(pp.get("action_landed_per_round", 25.0))
	if action_bonus:
		d_pop += float(pp.get("action_bonus", 1.5))
	d_pop = snappedf(d_pop, 0.1)
	if d_pop > 0.0:
		d_pop = maxf(0.0, minf(d_pop, float(caps[clampi(tier_i, 0, caps.size() - 1)]) - pop_before))
	d_pop = snappedf(d_pop, 0.1)
	state["pop"] = clampf(snappedf(pop_before + d_pop, 0.1), 0.0, 100.0)
	var pay := int(o.get("purse", 0)) + (int(o.get("bonus", 0)) if won else 0)
	state["money"] = int(state["money"]) + pay
	# record and streak
	var rec: Dictionary = state["record"]
	if won:
		rec["w"] = int(rec["w"]) + 1
		state["streak"] = maxi(1, int(state["streak"]) + 1)
		if finish:
			rec["tko"] = int(rec.get("tko", 0)) + 1
		else:
			rec["dec"] = int(rec.get("dec", 0)) + 1
	elif draw:
		rec["d"] = int(rec["d"]) + 1
		state["streak"] = 0
	else:
		rec["l"] = int(rec["l"]) + 1
		state["streak"] = mini(-1, int(state["streak"]) - 1)
	# injuries carried out of the fight (PLACEHOLDER scales: CareerDefaults injury_out)
	var inj := injury_out(oc, won, draw)
	var cap := float((rules.get("injury_out", {}) as Dictionary).get("region_cap", 100.0))
	for r in CareerDefaults.REGIONS:
		state["injury"][r] = clampf(float(state["injury"].get(r, 0.0)) + float(inj[r]), 0.0, cap)
	# titles
	var title_note := ""
	if title:
		if won and not bool(state["champion"]):
			state["champion"] = true
			state["title_defences"] = 0
			title_note = "NEW %s" % str(rules.get("belt_name", "Champion")).to_upper()
		elif won:
			state["title_defences"] = int(state["title_defences"]) + 1
			title_note = "Title defended (%d)" % int(state["title_defences"])
		elif not draw and bool(state["champion"]):
			state["champion"] = false
			title_note = "Belt lost"
	var opp: Dictionary = o.get("opp", {})
	var res_word := "win" if won else ("draw" if draw else "loss")
	var entry := {"fight_id": fid, "week": int(state["week"]), "org": str(o.get("org", "")), "org_name": str(o.get("org_name", "")),
		"tier": tier_i, "title": title, "opp": str(opp.get("name", "")), "opp_nick": str(opp.get("nick", "")),
		"opp_fighter": str(opp.get("fighter", "")), "opp_rating": int(opp.get("rating", 0)), "won": won, "draw": draw,
		"result": res_word, "method": method, "round": rnd, "time": snappedf(float(oc["time"]), 0.01), "rounds": rounds,
		"pay": pay, "d_pop": d_pop, "pop": float(state["pop"]), "inj": inj, "totals": oc["totals"],
		"landed": oc["landed"], "knockdowns": oc["knockdowns"], "arena": str(o.get("arena", "")), "title_note": title_note}
	(state["history"] as Array).append(entry)
	_claim(fid)
	var finish_txt := ", R%d" % rnd if finish else ""
	var news_line := "%s %s (%s%s) at %s. %s, popularity %s%s.%s" % ["Beat" if won else ("Drew with" if draw else "Lost to"),
		str(opp.get("name", "?")), method, finish_txt, str(o.get("org_name", "")), money_text(pay),
		"+" if d_pop >= 0.0 else "", _num(d_pop), (" " + title_note + ".") if title_note != "" else ""]
	_say(news_line)
	var sum_d := entry.duplicate(true)
	sum_d.merge({"ok": true, "error": "", "duplicate": false, "finish": finish, "opp_info": opp.duplicate(true),
		"tier_name": CareerState.tier_name(rules, tier_i), "purse": int(o.get("purse", 0)), "bonus": int(o.get("bonus", 0)),
		"pop_before": pop_before, "pop_label": CareerState.pop_label(rules, float(state["pop"])),
		"injury_added": inj.duplicate(), "injury": (state["injury"] as Dictionary).duplicate(), "record": rec.duplicate(),
		"record_text": CareerState.record_text(rec), "streak": int(state["streak"]), "champion": bool(state["champion"]),
		"title_defences": int(state["title_defences"]), "scoring": (result.get("scoring", {}) as Dictionary).duplicate(true) if typeof(result.get("scoring")) == TYPE_DICTIONARY else {},
		"action": snappedf(action, 0.01), "action_bonus": action_bonus, "week_label": CareerState.week_label(int(state["week"])),
		"news": news_line}, true)
	sum_d["opp"] = opp.duplicate(true)
	sum_d["history_entry"] = entry.duplicate(true)
	sum_d["profile_history"] = {"kind": "career", "career_id": str(state.get("career_id", "")), "slot": slot,
		"fighter": str(state.get("fighter", "")), "name": str(state.get("name", "")), "opp": str(opp.get("name", "")),
		"org": str(o.get("org_name", "")), "result": res_word, "method": method, "title": title, "week": int(state["week"]),
		"pop": float(state["pop"]), "record": CareerState.record_text(rec)}
	# next week: booking over, new offers
	state["booked"] = {}
	state["week"] = int(state["week"]) + 1
	_roll_offers(false)
	sum_d["standing"] = standing()["text"]
	state["last_fight"] = sum_d.duplicate(true)
	last_error = ""
	_commit("result")
	return sum_d


## Injuries out of a bout (design contract §5.2 "injuries out"; PLACEHOLDER constants): damage
## taken by part as % of max HP x per_hp_pct, + per_knockdown head per knockdown suffered,
## + stoppage_loss_head when stopped. {head, body, legs} (whole numbers).
func injury_out(oc: Dictionary, won: bool, draw: bool) -> Dictionary:
	var io: Dictionary = rules.get("injury_out", {})
	var max_hp := float(catalog.resolver.creature_dict(str(state.get("fighter", ""))).get("stats", {}).get("health", 100.0)) if catalog else 100.0
	max_hp = maxf(1.0, max_hp)
	var taken: Dictionary = oc.get("taken", {})
	var t_sum := 0.0
	for r in CareerDefaults.REGIONS:
		t_sum += float(taken.get(r, 0.0))
	if t_sum <= 0.0 and float(oc.get("damage_taken", 0.0)) > 0.0:
		# no per-part tally (HP scoring): split the damage taken
		var split: Dictionary = io.get("fallback_split", {"head": 0.4, "body": 0.4, "legs": 0.2})
		taken = {}
		for r2 in CareerDefaults.REGIONS:
			taken[r2] = float(oc["damage_taken"]) * float(split.get(r2, 0.0))
	var per := float(io.get("per_hp_pct", 0.04))
	var out := {}
	for r3 in CareerDefaults.REGIONS:
		out[r3] = float(roundi(float(taken.get(r3, 0.0)) / max_hp * 100.0 * per))
	out["head"] = float(out["head"]) + float(roundi(int(oc["knockdowns"][1]) * float(io.get("per_knockdown", 2.0))))
	if not won and not draw and bool(oc.get("finish", false)):
		out["head"] = float(out["head"]) + float(io.get("stoppage_loss_head", 10.0))
	return out


# =============================================================================================
# Read helpers (plain data for the screens)
# =============================================================================================

func stat_label(stat: String) -> String:
	return str((rules.get("stat_info", {}) as Dictionary).get(stat, {}).get("label", stat.capitalize()))


func week_label(w := -1) -> String:
	return CareerState.week_label(int(state["week"]) if w < 0 else w)


func rating() -> int:
	return CareerState.rating(state["stats"])


func pop_label() -> String:
	return CareerState.pop_label(rules, float(state["pop"]))


func tier() -> int:
	return CareerState.tier_for(rules, float(state["pop"]))


## Standing (no ranking table in Cage Rules): {tier, tier_name, pop, pop_label, contender (0 =
## none, else #15..#1 in the top tier), champion, text}.
static func standing_of(r: Dictionary, pop: float, champion: bool) -> Dictionary:
	var t := CareerState.tier_for(r, pop)
	var c: Dictionary = r.get("contender", {})
	var contender := 0
	var tiers: Array = r.get("tiers", [])
	var top_tier := maxi(0, tiers.size() - 1)
	if not champion and t >= top_tier:
		var lo := float(c.get("from", 74.0))
		var hi := float(c.get("to", 92.0))
		var worst := int(c.get("worst", 15))
		var f := clampf((pop - lo) / maxf(0.001, hi - lo), 0.0, 1.0)
		contender = worst - int(round(f * (worst - 1)))
	var text := ""
	if champion:
		text = str(r.get("belt_name", "Champion"))
	elif contender > 0:
		text = "#%d contender · %s" % [contender, CareerState.tier_name(r, t)]
	else:
		text = "%s · %s" % [CareerState.tier_name(r, t), CareerState.pop_label(r, pop)]
	return {"tier": t, "tier_name": CareerState.tier_name(r, t), "pop": pop, "pop_label": CareerState.pop_label(r, pop),
		"contender": contender, "champion": champion, "text": text}


func standing() -> Dictionary:
	return standing_of(rules, float(state["pop"]), bool(state["champion"]))


func streak_text() -> String:
	var s := int(state["streak"])
	if s >= 2:
		return "%d in a row" % s
	if s <= -2:
		return "%d straight losses" % -s
	return ""


## Header KPIs: {name, nick, billed, fighter, fighter_name, record, record_text, tko, dec, money,
## money_text, week, week_label, pop, pop_label, pop_marks, standing, streak, streak_text,
## champion, title_defences, rating, difficulty, difficulty_name}.
func header() -> Dictionary:
	var st := standing()
	var diff := str(state.get("difficulty", "normal"))
	return {"name": str(state["name"]), "nick": str(state.get("nick", "")), "billed": CareerFight.billed_name(str(state["name"]), str(state.get("nick", ""))),
		"fighter": str(state["fighter"]), "fighter_name": CareerOffers.fighter_name(catalog, str(state["fighter"])),
		"record": (state["record"] as Dictionary).duplicate(), "record_text": CareerState.record_text(state["record"]),
		"tko": int(state["record"].get("tko", 0)), "dec": int(state["record"].get("dec", 0)),
		"money": int(state["money"]), "money_text": money_text(int(state["money"])), "week": int(state["week"]),
		"week_label": week_label(), "pop": float(state["pop"]), "pop_label": pop_label(), "pop_marks": rules.get("pop_marks", []),
		"standing": st["text"], "streak": int(state["streak"]), "streak_text": streak_text(), "champion": bool(state["champion"]),
		"title_defences": int(state["title_defences"]), "rating": rating(), "difficulty": diff,
		"difficulty_name": str((rules.get("difficulties", {}) as Dictionary).get(diff, {}).get("name", diff.capitalize()))}


## The six stats: [{id, label, short, desc, value (0..1), points (0..99), gain (0..1 next week),
## gain_points, facility, facility_level, capped}].
func stat_rows() -> Array:
	var out := []
	var cap := float(rules.get("stat_cap", 0.99))
	for k in CareerDefaults.STATS:
		var info: Dictionary = (rules.get("stat_info", {}) as Dictionary).get(k, {})
		var v := float(state["stats"].get(k, 0.0))
		var g := minf(preview_gain(k), maxf(0.0, cap - v))
		out.append({"id": k, "label": str(info.get("label", k.capitalize())), "short": str(info.get("short", k.substr(0, 3).to_upper())),
			"desc": str(info.get("desc", "")), "value": v, "points": int(round(v * 100.0)), "gain": g, "gain_points": snappedf(g * 100.0, 0.1),
			"facility": str(facility(k).get("name", "")), "facility_level": int(state["gym"].get(k, 0)), "capped": v >= cap - 0.00001})
	return out


## The train grid (Cage Rules camp page): the six stat rows + {id: "rest", label, heal,
## rest_mult, healthy, desc}. Empty on fight week.
func train_rows() -> Array:
	if fight_ready():
		return []
	var out := stat_rows()
	var h: Dictionary = rules.get("healing", {})
	var healthy := CareerState.injury_total(state) <= 0.0
	var desc := "No stat gains this week; injuries heal %s times as fast." % _num(float(h.get("rest_mult", 2.5)))
	if healthy:
		desc += " You are healthy: probably train instead."
	out.append({"id": "rest", "label": "Rest & recover", "short": "REST", "desc": desc, "heal": heal_amount(true),
		"rest_mult": float(h.get("rest_mult", 2.5)), "healthy": healthy})
	return out


## Condition: {regions: [{id, label, value, level ("healthy"|"sore"|"hurt"|"injured"), text}],
## total, line (fight-night line), heal_week, heal_rest, training_mult, carry}.
func condition() -> Dictionary:
	var cd: Dictionary = rules.get("condition", {})
	var regions := []
	for r in CareerDefaults.REGIONS:
		var v := float(state["injury"].get(r, 0.0))
		var lvl := "healthy"
		var text := "healthy"
		if v > float(cd.get("injured", 40.0)):
			lvl = "injured"
			text = "injured %d" % int(round(v))
		elif v > float(cd.get("sore", 10.0)):
			lvl = "hurt"
			text = "hurt %d" % int(round(v))
		elif v > 0.0:
			lvl = "sore"
			text = "sore %d" % int(round(v))
		regions.append({"id": r, "label": r.to_upper(), "value": v, "level": lvl, "text": text})
	var total := CareerState.injury_total(state)
	var line := "Healthy and ready."
	if total > float(cd.get("hurt_total", 30.0)):
		line = "You are going in hurt (%d damage carried)." % int(round(total))
	elif total > 0.0:
		line = "A little banged up (%d), nothing serious." % int(round(total))
	var tr: Dictionary = rules.get("training", {})
	return {"regions": regions, "total": total, "line": line, "heal_week": heal_amount(false), "heal_rest": heal_amount(true),
		"training_mult": maxf(float(tr.get("injury_floor", 0.35)), 1.0 - total / float(tr.get("injury_div", 260.0))),
		"carry": float((rules.get("injury_in", {}) as Dictionary).get("carry", 0.5))}


## Offer rows (design contract D7): the offer + {tier_name, billed, record_text, rating, danger,
## danger_diff, bot_tier, bot_tier_name, rounds_label, missing}.
func offer_rows() -> Array:
	var out := []
	for o in state.get("offers", []):
		out.append(decorate_offer(o))
	return out


func decorate_offer(o: Dictionary) -> Dictionary:
	var d: Dictionary = o.duplicate(true)
	var opp: Dictionary = d.get("opp", {})
	var diff := int(opp.get("rating", 0)) - rating()
	d["tier_name"] = CareerState.tier_name(rules, int(d.get("tier", 0)))
	d["billed"] = CareerFight.billed_name(str(opp.get("name", "")), str(opp.get("nick", "")))
	d["record_text"] = CareerState.record_text(opp.get("record", {}))
	d["rating"] = int(opp.get("rating", 0))
	d["danger_diff"] = diff
	d["danger"] = CareerOffers.danger(rules, diff)
	d["bot_tier"] = str(opp.get("bot_tier", ""))
	d["bot_tier_name"] = bot_tier_name(str(opp.get("bot_tier", "")))
	d["rounds_label"] = CareerFight.rounds_label(d)
	d["missing"] = CareerState.offer_missing(catalog, o)
	return d


func bot_tier_name(id: String) -> String:
	if catalog and catalog.bot_tiers.has(id):
		return str(catalog.bot_tiers[id].get("name", id))
	return BotTiers.display_name(id)


## Offers-page hints (Cage Rules footer): {lines: [..], next_org: {} | {id, name, pop},
## title_pop, tier_cap}.
func hints() -> Dictionary:
	var pop := float(state["pop"])
	var lines := []
	var next := {}
	for o in rules.get("orgs", []):
		if float(o.get("pop", 0)) > pop and (next.is_empty() or float(o.get("pop", 0)) < float(next.get("pop", 0))):
			next = {"id": str(o.get("id", "")), "name": str(o.get("name", "")), "pop": float(o.get("pop", 0))}
	var title_offer := false
	for o2 in state.get("offers", []):
		if bool(o2.get("title", false)):
			title_offer = true
	if bool(state["champion"]):
		lines.append("You are the champion. Keep defending.")
	elif title_offer:
		lines.append("The champion has agreed to fight you.")
	elif not next.is_empty():
		lines.append("Next up: %s starts calling at popularity %s (you are at %s)." % [str(next["name"]), _num(float(next["pop"])), _num(pop)])
	elif pop < float(rules.get("title_pop", 92.0)):
		lines.append("A title shot comes at popularity %s." % _num(float(rules.get("title_pop", 92.0))))
	var caps: Array = rules.get("tier_pop_cap", [42, 66, 88, 100])
	var t := tier()
	var cap := float(caps[clampi(t, 0, caps.size() - 1)]) if not caps.is_empty() else 100.0
	var cap_txt := []
	for i in range(0, maxi(0, caps.size() - 1)):
		cap_txt.append(_num(float(caps[i])))
	lines.append("Wins only make you so famous at each level (%s): move up to keep climbing." % " / ".join(PackedStringArray(cap_txt)))
	return {"lines": lines, "next_org": next, "title_pop": float(rules.get("title_pop", 92.0)), "tier_cap": cap}


## The booked fight card (design contract D7): {} when unbooked, else {fight_id, org_name,
## tier_name, title, defence, purse, bonus, rounds, round_time, rounds_label, weeks_left,
## fight_week, arena_name, note, me: {...}, opp: {...}, rows: [six-row stat comparison {id,
## label, short, me, opp, me_ahead}], plan: [labels], condition_line, interrupted, missing}.
func fight_card() -> Dictionary:
	if not is_booked():
		return {}
	var b := booked()
	var o: Dictionary = b.get("offer", {})
	var opp: Dictionary = o.get("opp", {})
	var rows := []
	for k in CareerDefaults.STATS:
		var info: Dictionary = (rules.get("stat_info", {}) as Dictionary).get(k, {})
		var mine := int(round(float(state["stats"].get(k, 0.0)) * 100.0))
		var theirs := int(round(float(opp.get("stats", {}).get(k, 0.0)) * 100.0))
		rows.append({"id": k, "label": str(info.get("label", k)), "short": str(info.get("short", k)), "me": mine, "opp": theirs, "me_ahead": mine >= theirs})
	var plan := []
	for p in b.get("plan", []):
		plan.append("Rest" if str(p) == "rest" else stat_label(str(p)))
	var d := decorate_offer(o)
	return {"fight_id": str(o.get("id", "")), "org_name": str(o.get("org_name", "")), "tier_name": d["tier_name"],
		"title": bool(o.get("title", false)), "defence": bool(o.get("defence", false)), "purse": int(o.get("purse", 0)),
		"bonus": int(o.get("bonus", 0)), "rounds": int(o.get("rounds", 3)), "round_time": float(o.get("round_time", 99.0)),
		"rounds_label": d["rounds_label"], "weeks_left": int(b.get("weeks_left", 0)), "weeks_total": int(o.get("weeks", 0)),
		"fight_week": fight_ready(), "arena_name": str(o.get("arena_name", "")), "note": str(o.get("note", "")),
		"me": {"name": str(state["name"]), "nick": str(state.get("nick", "")), "billed": header()["billed"],
			"fighter": str(state["fighter"]), "fighter_name": CareerOffers.fighter_name(catalog, str(state["fighter"])),
			"record_text": CareerState.record_text(state["record"]), "rating": rating()},
		"opp": {"name": str(opp.get("name", "")), "nick": str(opp.get("nick", "")), "billed": d["billed"],
			"fighter": str(opp.get("fighter", "")), "fighter_name": str(opp.get("fighter_name", "")), "record_text": d["record_text"],
			"rating": int(opp.get("rating", 0)), "from": str(opp.get("from", "")), "bot_tier": d["bot_tier"],
			"bot_tier_name": d["bot_tier_name"], "danger": d["danger"], "danger_diff": d["danger_diff"]},
		"rows": rows, "plan": plan, "condition_line": condition()["line"], "interrupted": interrupted(), "missing": booked_missing()}


## Fight history, newest first.
func history() -> Array:
	var h: Array = (state.get("history", []) as Array).duplicate(true)
	h.reverse()
	return h


## News log, newest first: [{week, week_label, text}].
func news() -> Array:
	var out := []
	for e in state.get("log", []):
		out.push_front({"week": int(e.get("week", 1)), "week_label": CareerState.week_label(int(e.get("week", 1))), "text": str(e.get("text", ""))})
	return out


func summary() -> Dictionary:
	return CareerStore.summarize(state, catalog)


## Retire (confirmed in the UI): the save is moved aside and the slot frees (D3). The controller
## stops autosaving. Returns CareerStore.retire's report.
func retire() -> Dictionary:
	if store == null:
		return {"ok": true, "error": "", "moved": []}
	var r := store.retire(profile_id, slot)
	if bool(r["ok"]):
		store = null
	return r


static func money_text(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-$" if n < 0 else "$") + s + out


# =============================================================================================
# Internals
# =============================================================================================

static func _num(x: float) -> String:
	var r := snappedf(x, 0.1)
	return str(int(r)) if is_equal_approx(r, roundf(r)) else "%.1f" % r


func _roll_offers(same_week: bool) -> void:
	if same_week:
		state["offer_roll"] = int(state.get("offer_roll", 0)) + 1
	else:
		state["offer_roll"] = 0
	state["offers"] = CareerOffers.make_offers(catalog, rules, state)


func _claim(fid: String) -> void:
	var c: Array = state["claims"]
	if fid != "" and not c.has(fid):
		c.append(fid)


func _say(text: String) -> void:
	var lg: Array = state["log"]
	lg.append({"week": int(state["week"]), "text": text})
	var cap := int(rules.get("news_cap", 60))
	while lg.size() > cap:
		lg.pop_front()


func _fail(out: Dictionary) -> Dictionary:
	last_error = str(out.get("error", ""))
	return out


## Emits `changed` and autosaves (when a store is attached). False when the save failed.
func _commit(reason: String) -> bool:
	changed.emit(reason)
	if store == null:
		last_save_error = OK
		return true
	last_save_error = store.save(state, profile_id, slot)
	if last_save_error != OK:
		Log.w("career", "autosave (%s) failed: %s" % [reason, error_string(last_save_error)])
	return last_save_error == OK
