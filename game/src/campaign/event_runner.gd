class_name EventRunner
extends RefCounted
## Random events (CAMPAIGN.md §6). An event is data: title, text (with {element}/{fighter}
## placeholders), an optional setup roll, and choices with requirements, a cost, a risk tag and
## weighted outcomes. Each outcome is a list of effect ops (CampaignCatalog.EVENT_OPS):
##   hp, hp_pct, max_hp, scrip, clout, hype_carry, hype_carry_set, grant_supplement, side_effect,
##   remove_supplement, remove_side_effects, technique_pick, reward_pick, run_mods, run_patches,
##   run_hooks, next_fight, bet, boss_mod, fight, cosmetic, coupon, flag, nothing, consumable, quip,
##   learn_move ({options: n} a pick of new moves, or {move: id} that move; Movesets runs - a
##   Classic run, or a fighter who knows every move, gets 25 Scrip instead).
## run_patches may carry a "movesets" apply block (Movesets-only effects, UpgradeTranslation).
## Rolls use the node's own stream, so the same seed always produces the same outcome.
## Group events (marked "group": true) are decided once for the whole party and apply to every
## member; Scrip costs are split evenly (rounding up on the Captain), so a group choice is only
## available while EVERY member can cover their share (co-op votes offer only those).
## An event never softlocks: when nothing can be taken, the decider may PASS (move on, no
## outcome) — logged like any choice, so replays reproduce it.

const ELEMENT_ROLL := ["scorch", "brine", "static", "sludge", "grit", "gale", "scrap", "spectral"]
const PASS := "_pass"            ## reserved choice id: nothing can be taken, move on


static func begin(ctrl: RunController, node_id: String, event_id: String) -> Dictionary:
	var ev: Dictionary = ctrl.catalog.events.get(event_id, {})
	var roll := {}
	var spec: Dictionary = ev.get("roll", {})
	if spec.has("element"):
		var rng := RunRng.stream(int(ctrl.state["seed"]), "node/%s/event/roll" % node_id)
		roll["element"] = ELEMENT_ROLL[rng.range_i(0, ELEMENT_ROLL.size() - 1)]
	var decider := ""
	var req: Dictionary = ev.get("requires", {})
	if req.has("fighters") or req.has("party_element") or req.has("weight_class"):
		for p in ctrl.state["players"]:
			if requirement_ok(ctrl, p, req, roll):
				decider = str(p["id"])
				break
	return {"id": event_id, "roll": roll, "group": bool(ev.get("group", false)), "decider": decider,
		"chosen": "", "outcome": -1, "texts": []}


static func fill(text: String, ctrl, p: Dictionary, roll: Dictionary) -> String:
	var t := text
	if roll.has("element"):
		t = t.replace("{element}", Elements.display_name(str(roll["element"])))
	t = t.replace("{fighter}", str(ctrl.catalog.fighter_info(str(p.get("fighter", ""))).get("name", p.get("fighter", ""))))
	return t


static func requirement_ok(ctrl: RunController, p: Dictionary, req: Dictionary, roll: Dictionary) -> bool:
	var cat: CampaignCatalog = ctrl.catalog
	for k in req:
		var v = req[k]
		match str(k):
			"act":
				if not CampaignCatalog.has_num(v, int(ctrl.state.get("act", 1))):
					return false
			"fighters":
				if not (v as Array).has(str(p.get("fighter", ""))):
					return false
			"party_element", "element":
				if cat.fighter_element(str(p.get("fighter", ""))) != str(v):
					return false
			"weight_class":
				if not (v as Array).has(cat.weight_class(str(p.get("fighter", "")))):
					return false
			"scrip":
				if int(p.get("scrip", 0)) < int(v):
					return false
			"has_banned":
				if (_owned_of_rarity(cat, p, "banned").size() > 0) != bool(v):
					return false
			"no_banned":
				if (_owned_of_rarity(cat, p, "banned").is_empty()) != bool(v):
					return false
			"has_supplements":
				if (_owned_non_banned(cat, p).size() > 0) != bool(v):
					return false
			"roll_matches":
				var match_el := roll.has("element") and cat.fighter_element(str(p.get("fighter", ""))) == str(roll["element"])
				if match_el != bool(v):
					return false
			"variant":
				if str(ctrl.state.get("variant", "")) != str(v):
					return false
			"coop":
				if ((ctrl.state["players"] as Array).size() > 1) != bool(v):
					return false
	return true


static func _owned_of_rarity(cat: CampaignCatalog, p: Dictionary, rarity: String) -> Array:
	var out := []
	for s in p.get("supplements", []):
		if str(cat.supplements.get(str(s["id"]), {}).get("rarity", "")) == rarity:
			out.append(str(s["id"]))
	return out


static func _owned_non_banned(cat: CampaignCatalog, p: Dictionary) -> Array:
	var out := []
	for s in p.get("supplements", []):
		if str(cat.supplements.get(str(s["id"]), {}).get("rarity", "")) != "banned":
			out.append(str(s["id"]))
	return out


## UI view of the current event for a player.
static func view(ctrl: RunController, session: Dictionary, pid: String) -> Dictionary:
	var ev: Dictionary = ctrl.catalog.events.get(str(session.get("id", "")), {})
	var p: Dictionary = RunState.player(ctrl.state, pid)
	var roll: Dictionary = session.get("roll", {})
	var choices := []
	for c in ev.get("choices", []):
		var cost: Dictionary = c.get("cost", {})
		var reason := block_reason(ctrl, session, pid, c)
		choices.append({"id": str(c.get("id", "")), "label": fill(str(c.get("label", "")), ctrl, p, roll),
			"desc": fill(str(c.get("desc", "")), ctrl, p, roll), "risk": str(c.get("risk", "safe")),
			"cost": cost, "available": reason == "", "reason": reason})
	var decider := str(session.get("decider", ""))
	return {"id": str(session.get("id", "")), "title": fill(str(ev.get("title", "")), ctrl, p, roll),
		"speaker": str(ev.get("speaker", "")), "text": fill(str(ev.get("text", "")), ctrl, p, roll),
		"choices": choices, "group": bool(session.get("group", false)), "decider": decider,
		"can_decide": decider == "" or decider == pid, "chosen": str(session.get("chosen", "")),
		"result": session.get("texts", [])}


## Why `pid` cannot take choice `c` right now ("" = available). Requirements are the deciding
## player's; a group choice also needs every member to cover their share of its Scrip cost.
static func block_reason(ctrl: RunController, session: Dictionary, pid: String, c: Dictionary) -> String:
	var p: Dictionary = RunState.player(ctrl.state, pid)
	if not requirement_ok(ctrl, p, c.get("requires", {}), session.get("roll", {})):
		return str(c.get("locked_text", "Not available"))
	var cost := int(c.get("cost", {}).get("scrip", 0))
	if cost <= 0:
		return ""
	if not bool(session.get("group", false)):
		return "Not enough Scrip" if int(p.get("scrip", 0)) < cost else ""
	for mid in RunState.player_ids(ctrl.state):
		var mp: Dictionary = RunState.player(ctrl.state, str(mid))
		if int(mp.get("scrip", 0)) < _cost_share(ctrl, session, str(mid), cost):
			return "Not enough Scrip" if str(mid) == pid else "%s can't cover their share" % str(mp.get("name", mid))
	return ""


## Ids of the current event's choices `pid` (the decider) can take now — for a group event,
## only those the whole party can pay for.
static func available_choices(ctrl: RunController, session: Dictionary, pid: String) -> Array:
	var ev: Dictionary = ctrl.catalog.events.get(str(session.get("id", "")), {})
	var out := []
	for c in ev.get("choices", []):
		if typeof(c) == TYPE_DICTIONARY and block_reason(ctrl, session, pid, c) == "":
			out.append(str(c.get("id", "")))
	return out


## Scrip a player pays for a group choice (even split, remainder on the Captain).
static func _cost_share(ctrl: RunController, session: Dictionary, pid: String, total: int) -> int:
	if not bool(session.get("group", false)):
		return total
	var ids := RunState.player_ids(ctrl.state)
	var n := maxi(1, ids.size())
	var base := int(floor(float(total) / float(n)))
	var rem := total - base * n
	return base + (rem if pid == ctrl.captain() else 0)


## Applies a choice. Returns {ok, error, texts}.
static func choose(ctrl: RunController, pid: String, choice_id: String) -> Dictionary:
	var session: Dictionary = ctrl.state["node"].get("event", {})
	var ev: Dictionary = ctrl.catalog.events.get(str(session.get("id", "")), {})
	if str(session.get("chosen", "")) != "":
		return {"ok": false, "error": "this event was already decided"}
	var decider := str(session.get("decider", ""))
	if decider != "" and decider != pid and not bool(session.get("group", false)):
		return {"ok": false, "error": "only %s can decide this event" % decider}
	if choice_id == PASS:
		if not available_choices(ctrl, session, pid).is_empty():
			return {"ok": false, "error": "there is still a choice to make"}
		var pass_texts := ["Nothing here anyone can take. You move on."]
		session["chosen"] = PASS
		session["decider"] = pid
		session["outcome"] = -1
		session["texts"] = pass_texts
		return {"ok": true, "texts": pass_texts.duplicate()}
	var choice := {}
	for c in ev.get("choices", []):
		if str(c.get("id", "")) == choice_id:
			choice = c
	if choice.is_empty():
		return {"ok": false, "error": "unknown choice '%s'" % choice_id}
	var targets := []
	if bool(session.get("group", false)):
		targets = RunState.player_ids(ctrl.state)
	else:
		targets = [pid]
	var roll: Dictionary = session.get("roll", {})
	for t in targets:
		var tp: Dictionary = RunState.player(ctrl.state, str(t))
		if not requirement_ok(ctrl, tp, choice.get("requires", {}), roll) and str(t) == pid:
			return {"ok": false, "error": "requirements not met"}
	var cost := int(choice.get("cost", {}).get("scrip", 0))
	for t2 in targets:
		var share := _cost_share(ctrl, session, str(t2), cost)
		var tp2: Dictionary = RunState.player(ctrl.state, str(t2))
		if int(tp2.get("scrip", 0)) < share:
			if str(t2) == pid:
				return {"ok": false, "error": "not enough Scrip"}
			return {"ok": false, "error": "not enough Scrip: %s can't cover their share" % str(tp2.get("name", t2))}
	for t3 in targets:
		var tp3: Dictionary = RunState.player(ctrl.state, str(t3))
		tp3["scrip"] = int(tp3["scrip"]) - _cost_share(ctrl, session, str(t3), cost)
	session["chosen"] = choice_id
	session["decider"] = pid
	var outs: Array = choice.get("outcomes", [])
	var rng := RunRng.stream(int(ctrl.state["seed"]), "node/%s/event/%s/outcome" % [ctrl.state["position"], choice_id])
	var ws := []
	for o in outs:
		ws.append(float(o.get("weight", 1.0)))
	var oi := maxi(0, rng.weighted_index(ws))
	session["outcome"] = oi
	var outcome: Dictionary = outs[oi] if oi < outs.size() else {}
	var texts := []
	var p0: Dictionary = RunState.player(ctrl.state, pid)
	if str(outcome.get("text", "")) != "":
		texts.append(fill(str(outcome["text"]), ctrl, p0, roll))
	for t4 in targets:
		for eff in outcome.get("effects", []):
			var line := apply_effect(ctrl, str(t4), eff, {"source": "%s:%s" % [session["id"], choice_id], "key": "event/%s" % choice_id})
			if line != "" and (str(t4) == pid or bool(session.get("group", false))):
				texts.append(line)
	session["texts"] = texts
	return {"ok": true, "texts": texts}


## Applies one effect op to a player. Returns a short line for the result text ("" = silent).
static func apply_effect(ctrl: RunController, pid: String, eff: Dictionary, ctx: Dictionary) -> String:
	var p: Dictionary = RunState.player(ctrl.state, pid)
	var cat: CampaignCatalog = ctrl.catalog
	if eff.has("variant") and str(eff["variant"]) != str(ctrl.state.get("variant", "")):
		return ""
	var src := str(ctx.get("source", "event"))
	var key := "node/%s/%s/%s/%s" % [ctrl.state.get("position", ""), pid, ctx.get("key", "fx"), eff.get("op", "")]
	match str(eff.get("op", "")):
		"hp":
			var amt := float(eff.get("amount", 0.0))
			p["hp"] = clampf(float(p["hp"]) + amt, 1.0, ctrl.max_hp(p))
			return "%+d HP" % int(amt)
		"hp_pct":
			var amt2: float = float(eff.get("amount", 0.0)) * ctrl.max_hp(p)
			p["hp"] = clampf(float(p["hp"]) + amt2, 1.0, ctrl.max_hp(p))
			return ("Healed %d HP" % int(amt2)) if amt2 >= 0.0 else ("%d HP" % int(amt2))
		"max_hp":
			var a3 := float(eff.get("amount", 0.0))
			(p["run_effects"] as Array).append({"source": src, "apply": {"mods": [{"key": "max_health_add", "add": a3}]}})
			if a3 > 0.0:
				p["hp"] = float(p["hp"]) + a3
			p["hp"] = clampf(float(p["hp"]), 1.0, ctrl.max_hp(p))
			return "Max HP %+d" % int(a3)
		"scrip":
			var s := int(eff.get("amount", 0))
			p["scrip"] = maxi(0, int(p["scrip"]) + s)
			if s > 0:
				p["stats"]["scrip_earned"] = int(p["stats"].get("scrip_earned", 0)) + s
			return "%+d Scrip" % s
		"clout":
			if eff.has("variant") and str(eff["variant"]) != str(ctrl.state.get("variant", "")):
				return ""
			p["clout"] = int(p.get("clout", 0)) + int(eff.get("amount", 0))
			return "+%d Clout" % int(eff.get("amount", 0))
		"hype_carry":
			p["hype_carry"] = clampf(float(p.get("hype_carry", 0.0)) + float(eff.get("amount", 0.0)), 0.0, 100.0)
			return "Hype carry %+d" % int(eff.get("amount", 0))
		"hype_carry_set":
			p["hype_carry"] = clampf(float(eff.get("value", 0.0)), 0.0, 100.0)
			return ""
		"grant_supplement":
			var id := str(eff.get("id", ""))
			if id == "":
				var offer := RewardRoller.supplement_offer(cat, ctrl.state, p, key, {"source": "fight", "n": 1, "rarity": str(eff.get("rarity", "otc"))})
				id = str(offer[0]) if not offer.is_empty() else ""
			if id == "":
				p["scrip"] = int(p["scrip"]) + 30
				return "Nothing in the box: +30 Scrip"
			return ctrl.grant_supplement(pid, id, src)
		"side_effect":
			var lines := []
			for i in int(eff.get("count", 1)):
				var se := RewardRoller.side_effect_roll(cat, ctrl.state, p, "%s/%d" % [key, i])
				if se != "" and not (p["side_effects"] as Array).has(se):
					(p["side_effects"] as Array).append(se)
					lines.append("Side effect: %s" % cat.item_name(se))
			p["hp"] = clampf(float(p["hp"]), 1.0, ctrl.max_hp(p))
			return ", ".join(lines)
		"remove_supplement":
			var pool: Array = _owned_of_rarity(cat, p, "banned") if str(eff.get("filter", "non_banned")) == "banned" else _owned_non_banned(cat, p)
			if pool.is_empty():
				return ""
			var rng := RunRng.stream(int(ctrl.state["seed"]), key)
			var rid := str(pool[rng.range_i(0, pool.size() - 1)])
			ctrl.remove_supplement(pid, rid)
			return "Lost %s" % cat.item_name(rid)
		"remove_side_effects":
			p["side_effects"] = []
			p["hp"] = clampf(float(p["hp"]), 1.0, ctrl.max_hp(p))
			return "Side effects cleared"
		"technique_pick":
			ctrl.add_pending(pid, "technique", {"n": int(eff.get("options", 2)), "source": "event"})
			return "Technique pick"
		"reward_pick":
			ctrl.add_pending(pid, "supplement", {"n": int(eff.get("options", 3)), "source": "treasure",
				"min_rarity": str(eff.get("min_rarity", "")), "scrip_alt": int(eff.get("scrip_alt", 0))})
			return "Supplement pick"
		"run_mods":
			(p["run_effects"] as Array).append({"source": src, "apply": {"mods": eff.get("mods", [])}})
			p["hp"] = clampf(float(p["hp"]), 1.0, ctrl.max_hp(p))
			return str(eff.get("text", ""))
		"run_patches":
			var ap := {"patches": eff.get("patches", [])}
			# (an outcome an older build applied is replayed exactly as it was stored)
			if typeof(eff.get("movesets")) == TYPE_DICTIONARY and ctrl.new_rules():
				ap["movesets"] = (eff["movesets"] as Dictionary).duplicate(true)
			(p["run_effects"] as Array).append({"source": src, "apply": ap})
			var line := str(eff.get("text", ""))
			var imp := RunMoves.improves_text(cat, ctrl.state, p, "", ap) if ctrl.new_rules() else ""
			return line + (" (%s)" % imp if imp != "" and line != "" else "")
		"learn_move":
			if not RunMoves.is_movesets(ctrl.state) or (RunMoves.learnable(cat, p).is_empty() and ctrl.new_rules()):
				p["scrip"] = int(p["scrip"]) + 25
				return "Nothing new to learn: +25 Scrip"
			if not ctrl.new_rules():
				return ""
			var fighter := str(p.get("fighter", ""))
			var mv := str(eff.get("move", ""))
			if mv != "" and not RunMoves.move_info(cat, fighter, mv).is_empty() and RunMoves.learnable(cat, p).has(mv):
				(RunMoves.block(p)["learned"] as Array).append(mv)
				return "Learned %s" % RunMoves.move_name(cat, fighter, mv)
			ctrl.add_pending(pid, "move", {"n": int(eff.get("options", cat.rules.get("moves", {}).get("event_options", 2))), "source": "event"})
			return "Move pick"
		"run_hooks":
			(p["run_effects"] as Array).append({"source": src, "apply": {"hooks": eff.get("hooks", [])}})
			return str(eff.get("text", ""))
		"next_fight":
			(p["next_fights"] as Array).append({"source": src, "remaining": int(eff.get("count", 1)), "apply": eff.get("apply", {}),
				"rules": eff.get("rules", {}), "arena": str(eff.get("arena", ""))})
			return str(eff.get("text", "Next fight changed"))
		"bet":
			(p["triggers"] as Array).append({"source": src, "if": eff.get("if", {}), "win": eff.get("win", []), "lose": eff.get("lose", []), "remaining": 1})
			return str(eff.get("text", "Bet placed"))
		"boss_mod":
			var bm: Dictionary = ctrl.state["flags"]["boss_mods"]
			var b := str(eff.get("boss", ""))
			if not bm.has(b):
				bm[b] = {}
			for k in eff:
				if not k in ["op", "boss", "text"]:
					bm[b][k] = eff[k]
			return str(eff.get("text", ""))
		"fight":
			ctrl.begin_event_fight(pid, str(eff.get("encounter", "")), bool(eff.get("spar", false)), eff.get("on_win", []), eff.get("on_loss", []))
			return ""
		"cosmetic":
			(p["cosmetics"] as Array).append(str(eff.get("id", "")))
			return "Unlocked: %s" % str(eff.get("name", eff.get("id", "")))
		"quip":
			(p["cosmetics"] as Array).append("quip:%s" % ctrl.state.get("position", ""))
			return "Announcer quip unlocked"
		"coupon":
			p["coupon"] = maxf(float(p.get("coupon", 0.0)), float(eff.get("discount", 0.2)))
			return "Shop coupon: %d%% off" % int(float(eff.get("discount", 0.2)) * 100.0)
		"consumable":
			var cs: Dictionary = p["consumables"]
			var cid := str(eff.get("id", ""))
			cs[cid] = int(cs.get(cid, 0)) + int(eff.get("count", 1))
			return "+%d %s" % [int(eff.get("count", 1)), cat.item_name(cid)]
		"flag":
			ctrl.state["flags"][str(eff.get("key", ""))] = eff.get("value", true)
			return ""
	return ""
