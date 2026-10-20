class_name CommentaryDirector
extends RefCounted
## Decides WHAT the booth should talk about and how urgently (v0.9.17, docs/audio/COMMENTARY.md §2).
## Reads simulation events and the 4 Hz match tick; never touches gameplay. Produces requests
##   {trigger, ctx, vars, class, ttl, tag, energy, speaker_pref, follow}
## that Audio turns into lines (selection: CommentarySelector; queue/interrupts: Audio).
##
## Three registers, in priority order:
##   play-by-play  what just happened (hits, counters, strings, knockdowns, abilities, JUICE,
##                 referee and judges, results); short time-to-live so a call is never late
##   observations  what it means (who is pressing, a close fight, someone hurt, the clock, an
##                 element taking hold, momentum swinging); only when the action leaves room
##   color         booth personality (jokes, fighter/element/matchup banter, rare conversations);
##                 only in real lulls and under the talk budget
## Pacing: per-situation cooldowns, a talk budget (share of the last 30 s spent talking), breathing
## room after each line, and lull detection (no significant action for a few seconds).
## Accuracy: calls are keyed on what the event really was — a referee stoppage is not a knockout, a
## decision names its kind and winner, a knockdown call is invalidated once the bout is over, a
## whiff is only called when a committed attack touched nothing.

const CLASS_PRIORITY := {"critical": 100, "high": 85, "medium": 60, "low": 40, "color": 15}
const CLASS_TTL := {"critical": 5.0, "high": 3.0, "medium": 1.8, "low": 1.4, "color": 2.0}
const BIG_DAMAGE := 15.0
const HEAVY_DAMAGE := 10.0
const CLEAN_DAMAGE := 7.0
const COMBO_GAP := 1.1          ## seconds between hits that keep a string alive
const EXCHANGE_GAP := 1.2       ## the other fighter answers within this -> an exchange
const PRESSURE_HITS := 4        ## unanswered hits ...
const PRESSURE_WINDOW := 6.0    ## ... inside this window
const WHIFF_WINDOW := 0.85      ## a committed attack that touched nothing for this long
const LULL := 4.5               ## seconds without significant action before observations
const COLOR_LULL := 7.0         ## ... before booth color
const TALK_WINDOW := 30.0
const TALK_BUDGET_LOW := 0.55   ## low/color requests yield above this share of talk
const TALK_BUDGET_MEDIUM := 0.8

var fighters: Array = []        ## [{index, creature, name, team}]
var player_index := 0
var context := "versus"         ## versus | campaign | career | coop | tutorial | spectate
var career := {}                ## {title, debut, champion, tier, ...} when context == career
var ten_point := false
var referee := false
var rounds := 1
var round_no := 1
var t := 0.0                    ## match time (sim time when the bridge provides it)
var last_action_t := 0.0        ## last significant action
var last_line_end_t := -100.0   ## when the booth last stopped talking
var _talk: Array = []           ## [[start, end]] spoken intervals (match time)
var _cool := {}                 ## cooldown key -> time it is free again
var _st := {}                   ## per-round / per-match bookkeeping
var _pending: Array = []        ## deferred checks [{at, kind, ...}]
var _statuses_seen := {}        ## fighter -> {status: true}
var _health: Array = []
var _rng := RandomNumberGenerator.new()
var _color_next_at := 14.0      ## the first color line is never right at the bell
var _conversation_done := false
var _pending_ko := {}           ## a KO call waiting for its round_end (does it end the bout or a round?)
var finished := false


func begin(ctx: Dictionary) -> void:
	fighters = (ctx.get("fighters", []) as Array).duplicate(true)
	player_index = int(ctx.get("player_index", 0))
	context = str(ctx.get("context", "versus"))
	career = (ctx.get("career", {}) as Dictionary).duplicate(true) if typeof(ctx.get("career", {})) == TYPE_DICTIONARY else {}
	ten_point = bool(ctx.get("ten_point", false))
	referee = bool(ctx.get("referee", false))
	rounds = int(ctx.get("rounds", 1))
	_rng.seed = hash("director:%d" % int(ctx.get("seed", 0)))
	t = 0.0
	last_action_t = 0.0
	last_line_end_t = -100.0
	_talk.clear()
	_cool.clear()
	_pending.clear()
	_statuses_seen.clear()
	_health.clear()
	_color_next_at = _rng.randf_range(12.0, 18.0)
	_conversation_done = false
	finished = false
	_st = _new_round_state()
	_st["match_knockdowns"] = 0
	_st["parries"] = 0


func _new_round_state() -> Dictionary:
	return {"first_hit": false, "combo": {}, "unanswered": {}, "last_hit_by": {}, "last_attacker": {}, "last_slot": {},
		"blocks": {}, "kd": {}, "round_started_at": t, "low": {}, "ten_warned": false, "dealt": {}, "momentum_owner": -1,
		"match_knockdowns": int(_st.get("match_knockdowns", 0)), "parries": int(_st.get("parries", 0))}


# ---- talk accounting (Audio reports what was actually spoken) -----------------------------------

func note_line_started(start_t: float) -> void:
	_talk.append([start_t, -1.0])


func note_line_finished(end_t: float) -> void:
	if not _talk.is_empty() and float(_talk.back()[1]) < 0.0:
		_talk.back()[1] = end_t
	last_line_end_t = end_t


## Share of the last TALK_WINDOW seconds spent talking.
func talk_share() -> float:
	var from := t - TALK_WINDOW
	var sum := 0.0
	var keep: Array = []
	for iv in _talk:
		var s := float(iv[0])
		var e := float(iv[1]) if float(iv[1]) >= 0.0 else t
		if e < from:
			continue
		keep.append(iv)
		sum += e - maxf(s, from)
	_talk = keep
	return clampf(sum / TALK_WINDOW, 0.0, 1.0)


func _talking() -> bool:
	return not _talk.is_empty() and float(_talk.back()[1]) < 0.0


# ---- helpers ------------------------------------------------------------------------------------

func _name(i: int) -> String:
	for f in fighters:
		if int(f.get("index", -1)) == i:
			return str(f.get("name", ""))
	return ""


func _creature(i: int) -> String:
	for f in fighters:
		if int(f.get("index", -1)) == i:
			return str(f.get("creature", ""))
	return ""


func _team(i: int) -> int:
	for f in fighters:
		if int(f.get("index", -1)) == i:
			return int(f.get("team", -1))
	return -1


func _is_player(i: int) -> bool:
	return i == player_index and context != "spectate"


## {who, target} relative to the local player, plus {p}/{o} vars naming the actual fighters.
func _who(attacker: int, target: int) -> Dictionary:
	var d := {}
	if _is_player(attacker):
		d["who"] = "player"
	elif _is_player(target):
		d["who"] = "opponent"
	if _is_player(target):
		d["target"] = "player"
	elif target >= 0:
		d["target"] = "opponent"
	return d


## Names for a line about attacker a and target b: {p} = the side the line is about.
func _vars(a: int, b: int) -> Dictionary:
	var v := {}
	if a >= 0 and _name(a) != "":
		v["p"] = _name(a)
	if b >= 0 and _name(b) != "":
		v["o"] = _name(b)
	return v


func _ready(key: String) -> bool:
	return t >= float(_cool.get(key, -1.0))


func _cool_for(key: String, seconds: float) -> void:
	_cool[key] = t + seconds


func _req(trigger: String, ctx: Dictionary, klass: String, vars := {}, opts := {}) -> Dictionary:
	var r := {"trigger": trigger, "ctx": ctx, "vars": vars, "class": klass, "priority": int(CLASS_PRIORITY.get(klass, 40)),
		"ttl": float(opts.get("ttl", CLASS_TTL.get(klass, 1.5))), "tag": str(opts.get("tag", "")), "energy": str(opts.get("energy", "")),
		"speaker_pref": str(opts.get("speaker_pref", "")), "t": t}
	if opts.has("follow"):
		r["follow"] = opts["follow"]
	return r


## Low/color requests respect the talk budget and breathing room; medium only the hard budget.
func _room_for(klass: String) -> bool:
	var share := talk_share()
	match klass:
		"critical", "high":
			return true
		"medium":
			return share < TALK_BUDGET_MEDIUM
		"low":
			return share < TALK_BUDGET_LOW and t - last_line_end_t > 0.6
		_:
			return share < TALK_BUDGET_LOW - 0.1 and t - last_line_end_t > 1.6 and not _talking()


func _action(at: float) -> void:
	last_action_t = maxf(last_action_t, at)


# ---- events -------------------------------------------------------------------------------------

## One simulation event (+ the bridge's info: time, health, referee, ten_point, ...). Returns requests.
func on_event(ev: Dictionary, info: Dictionary) -> Array:
	var out: Array = []
	if info.has("time"):
		t = maxf(t, float(info["time"]))
	if info.has("health"):
		_health = (info["health"] as Array).duplicate()
	if info.has("referee"):
		referee = referee or bool(info["referee"])
	if info.has("ten_point"):
		ten_point = ten_point or bool(info["ten_point"])
	var type := str(ev.get("type", ""))
	var fi := int(ev.get("fighter", -1))
	match type:
		"round_intro":
			round_no = int(ev.get("round", 1))
			if round_no == 1:
				out.append_array(_intro_requests())
		"round_start":
			round_no = int(ev.get("round", round_no))
			_st = _new_round_state()
			_action(t)
			var cr := {}
			if round_no >= 2:
				cr["round"] = "2plus"
			if bool(info.get("final_round", false)) and rounds > 1:
				cr["round"] = "final"
			if context in ["campaign", "career"]:
				cr["context"] = context
			if context == "career" and bool(career.get("title", false)):
				cr["title"] = true
			out.append(_req("round_start", cr, "high", {"n": round_no}, {"ttl": 2.5, "energy": "high"}))
		"hit":
			out.append_array(_on_hit(ev, info))
		"parry":
			_action(t)
			_st["parries"] = int(_st.get("parries", 0)) + 1
			var attacker := int(ev.get("attacker", -1))
			var cp := _who(fi, attacker)
			var kinds: Array = []
			if str((_st["last_slot"] as Dictionary).get(fi, "")) in ["heavy", "heavy_charged"]:
				kinds.append("heavy")
			if int(_st["parries"]) == 3:
				kinds.append("third")
			cp["kind"] = kinds
			if _ready("parry"):
				_cool_for("parry", 7.0)
				out.append(_req("parry", cp, "medium", _vars(fi, attacker), {"energy": "high"}))
		"dodge":
			_pending.append({"at": t + 0.5, "kind": "evade", "fighter": fi, "hp": _hp(fi)})
		"move_start":
			var slot := str(ev.get("slot", ""))
			if slot in ["heavy", "heavy_charged", "finisher", "dash_attack"] or slot.begins_with("rh_") or slot.begins_with("rl_"):
				_pending.append({"at": t + WHIFF_WINDOW, "kind": "whiff", "fighter": fi, "slot": slot, "since": t})
		"glance":
			_touched(fi)
		"knockdown":
			out.append_array(_on_knockdown(ev, info))
		"getup":
			if _ready("getup") and not finished and int((_st["kd"] as Dictionary).get(fi, 0)) > 0:
				_cool_for("getup", 18.0)
				out.append(_req("getup", _who(-1, fi), "low", _vars(fi, -1), {"ttl": 2.0, "tag": "round"}))
		"ref_count":
			# the first count of the bout gets a word; later ones are the referee's own business
			if int(ev.get("n", 0)) == 2 and _ready("ref_count"):
				_cool_for("ref_count", 40.0)
				out.append(_req("referee", {"kind": "count"}, "medium", _vars(fi, -1), {"ttl": 1.5, "tag": "round"}))
		"ref_wave_up":
			if _ready("ref_wave"):
				_cool_for("ref_wave", 20.0)
				out.append(_req("referee", {"kind": "wave_up"}, "medium", _vars(fi, -1), {"ttl": 2.0, "tag": "round"}))
		"ref_stoppage":
			finished = true
			_action(t)
			var by := int(ev.get("by", -1))
			var cs := _who(by, fi)
			cs["kind"] = ["stoppage"]
			out.append(_req("stoppage", cs, "critical", _vars(by, fi), {"tag": "result", "energy": "high"}))
		"ko":
			_action(t)
			# held until the same tick's round_end says whether it decides the bout
			_pending_ko = _on_ko(ev, info)
		"juice":
			_action(t)
			out.append(_req("juice", {"creature": _creature(fi)}, "high", _vars(fi, -1), {"ttl": 2.5, "energy": "high"}))
		"ability":
			out.append_array(_on_ability(ev))
		"reaction":
			_action(t)
			if _ready("reaction"):
				_cool_for("reaction", 9.0)
				out.append(_req("reaction", {"reaction": str(ev.get("reaction", ""))}, "medium", _vars(int(ev.get("by", -1)), fi), {"ttl": 2.0}))
		"status":
			var sid := str(ev.get("status", ""))
			var seen: Dictionary = _statuses_seen.get(fi, {})
			if sid != "" and not seen.has(sid):
				seen[sid] = true
				_statuses_seen[fi] = seen
				var el := str(ev.get("element", ""))
				if el != "" and _ready("element"):
					_cool_for("element", 25.0)
					out.append(_req("element", {"element": el, "status": sid}, "low", _vars(fi, -1), {"ttl": 3.0}))
		"slam":
			_action(t)
			var att := int((_st["last_attacker"] as Dictionary).get(fi, -1))
			var cw := _who(att, fi)
			cw["kind"] = "wall"
			if _ready("wall"):
				_cool_for("wall", 8.0)
				out.append(_req("big_hit", cw, "medium", _vars(att, fi), {"energy": "high"}))
		"ringout":
			_action(t)
			var cr2 := _who(int(ev.get("by", -1)), fi)
			if _is_player(fi):
				cr2["who"] = "player"
			out.append(_req("ringout", cr2, "high", _vars(int(ev.get("by", -1)), fi), {"energy": "high"}))
		"throw":
			_action(t)
			_touched(fi)
			_pending.append({"at": t + 0.35, "kind": "throw", "fighter": fi, "victim": int(ev.get("victim", -1))})
		"grab_escape":
			if _ready("escape"):
				_cool_for("escape", 16.0)
				out.append(_req("escape", {}, "low", _vars(fi, -1), {"ttl": 1.6}))
		"guard_break":
			_action(t)
			if _ready("guard_break"):
				_cool_for("guard_break", 12.0)
				out.append(_req("guard_break", _who(-1, fi), "medium", _vars(-1, fi), {"energy": "high"}))
		"taunt":
			var ct := {"creature": _creature(fi)}
			if fi >= 0 and fi < _health.size() and float(_health[fi]) < 0.2:
				ct["kind"] = "low"
			if _ready("taunt"):
				_cool_for("taunt", 20.0)
				out.append(_req("taunt", ct, "low", _vars(fi, -1), {"ttl": 1.6}))
		"timeout":
			if not ten_point:
				out.append(_req("time", {"kind": "decision"}, "critical", {}, {"tag": "result"}))
		"sudden_death":
			out.append(_req("time", {"kind": "sudden_death"}, "high", {}, {"energy": "high"}))
		"round_end":
			out.append_array(_on_round_end(ev))
		"round_scored":
			out.append_array(_on_round_scored(ev))
		"judges_decision":
			out.append_array(_on_decision(ev, info))
		"match_end":
			finished = true
			out.append_array(_on_match_end(ev, info))
	return out


func _hp(i: int) -> float:
	return float(_health[i]) if i >= 0 and i < _health.size() else 1.0


## A fighter's committed attack touched something: no whiff.
func _touched(fi: int) -> void:
	for p in _pending:
		if str(p["kind"]) == "whiff" and int(p["fighter"]) == fi:
			p["cancel"] = true


func _intro_requests() -> Array:
	var out: Array = []
	# the opponent gets the walk-in (one line fits the intro); bosses have their own
	var subject := -1
	for f in fighters:
		if not _is_player(int(f.get("index", -1))):
			subject = int(f.get("index", -1))
			break
	if subject < 0 and not fighters.is_empty():
		subject = int(fighters[0].get("index", 0))
	var cid := _creature(subject)
	if cid.begins_with("b_"):
		out.append(_req("boss_intro", {"boss": cid}, "high", _vars(subject, -1), {"ttl": 4.0}))
	elif context == "career":
		var cc := {"creature": cid}
		if bool(career.get("title", false)):
			cc["kind"] = "title"
		elif bool(career.get("debut", false)):
			cc["kind"] = "debut"
		out.append(_req("career_intro", cc, "high", _vars(player_index, subject), {"ttl": 4.0, "energy": "high"}))
	else:
		out.append(_req("intro", {"creature": cid}, "high", _vars(subject, -1), {"ttl": 4.0, "energy": "high"}))
	return out


func _on_hit(ev: Dictionary, info: Dictionary) -> Array:
	var out: Array = []
	var fi := int(ev.get("fighter", -1))
	var ti := int(ev.get("target", -1))
	var dmg := float(ev.get("damage", 0.0))
	var slot := str(ev.get("slot", ""))
	var move := str(ev.get("move", ""))
	(_st["last_attacker"] as Dictionary)[ti] = fi
	(_st["last_slot"] as Dictionary)[ti] = slot
	if slot in ["zone", "reaction", "throw", "slam", "pummel"] or fi < 0:
		return out
	_touched(fi)
	if bool(ev.get("blocked", false)) or bool(ev.get("parried", false)):
		_action(t)
		if bool(ev.get("blocked", false)):
			var bl: Array = (_st["blocks"] as Dictionary).get(ti, [])
			bl = bl.filter(func(x: float) -> bool: return t - x < 3.0)
			bl.append(t)
			(_st["blocks"] as Dictionary)[ti] = bl
			var heavy_blocked := slot in ["heavy", "heavy_charged", "finisher"]
			if (heavy_blocked or bl.size() >= 3) and _ready("block"):
				_cool_for("block", 16.0)
				out.append(_req("block", _who(ti, fi), "low", _vars(ti, fi), {"ttl": 1.4}))
		return out
	if dmg <= 0.5:
		return out
	_action(t)
	var heavy := dmg >= HEAVY_DAMAGE or slot in ["heavy", "heavy_charged", "finisher", "dash_attack"]
	# damage ledger for momentum (last 12 s)
	var dl: Array = (_st["dealt"] as Dictionary).get(fi, [])
	dl.append([t, dmg])
	(_st["dealt"] as Dictionary)[fi] = dl
	# who answered whom
	var answered_at := float((_st["last_hit_by"] as Dictionary).get(ti, -100.0))
	(_st["last_hit_by"] as Dictionary)[fi] = t
	var un: Array = (_st["unanswered"] as Dictionary).get(fi, [])
	un = un.filter(func(x: float) -> bool: return t - x < PRESSURE_WINDOW)
	un.append(t)
	(_st["unanswered"] as Dictionary)[fi] = un
	(_st["unanswered"] as Dictionary)[ti] = []
	# combo per attacker
	var cc: Dictionary = (_st["combo"] as Dictionary).get(fi, {"n": 0, "t": -10.0})
	cc["n"] = int(cc["n"]) + 1 if t - float(cc["t"]) < COMBO_GAP else 1
	cc["t"] = t
	(_st["combo"] as Dictionary)[fi] = cc
	var n := int(cc["n"])
	var who := _who(fi, ti)
	var names := _vars(fi, ti)
	# 1. first damaging touch of the round
	if not bool(_st["first_hit"]):
		_st["first_hit"] = true
		var c1 := who.duplicate()
		if heavy:
			c1["kind"] = "heavy"
		out.append(_req("first_hit", c1, "medium", names, {"ttl": 2.0}))
		return out
	# 2. the ability that landed
	if slot.begins_with("ability"):
		for p in _pending:
			if str(p["kind"]) == "ability" and int(p["fighter"]) == fi:
				p["cancel"] = true
				if _ready("ability_hit:" + str(p["id"])):
					_cool_for("ability_hit:" + str(p["id"]), 22.0)
					out.append(_req("ability_hit", {"creature": _creature(fi), "id": str(p["id"])}, "medium", names, {"ttl": 1.6}))
				return out
	# 3. big moments
	var kinds: Array = []
	if bool(ev.get("counter", false)):
		kinds.append("counter")
	if dmg >= BIG_DAMAGE:
		kinds.append("big_damage")
	if move.contains("charged") or slot == "heavy_charged":
		kinds.append("charged")
	if float(ev.get("launch", 0.0)) > 0.0:
		kinds.append("launcher")
	if slot == "finisher":
		var c3 := who.duplicate()
		c3["kind"] = "finisher"
		if _ready("combo"):
			_cool_for("combo", 6.0)
			out.append(_req("combo", c3, "medium", names, {"energy": "high"}))
		return out
	if heavy and (dmg >= HEAVY_DAMAGE or not kinds.is_empty()):
		var c2 := who.duplicate()
		c2["kind"] = kinds
		if _ready("big_hit"):
			_cool_for("big_hit", 5.0)
			out.append(_req("big_hit", c2, "medium", names, {"energy": "high"}))
			return out
	if bool(ev.get("counter", false)) and _ready("counter"):
		_cool_for("counter", 9.0)
		out.append(_req("counter", who, "medium", names, {"ttl": 1.5}))
		return out
	# 4. strings
	if n == 3 or n == 4 or n == 6:
		var c4 := who.duplicate()
		c4["kind"] = "three" if n == 3 else ("four_plus" if n == 4 else "six_plus")
		if _ready("combo"):
			_cool_for("combo", 7.0)
			out.append(_req("combo", c4, "medium", names, {"ttl": 1.5}))
			return out
	# 5. a trade
	if t - answered_at < EXCHANGE_GAP and _ready("exchange"):
		_cool_for("exchange", 14.0)
		out.append(_req("exchange", {}, "low", names, {"ttl": 1.4}))
		return out
	# 6. one-way traffic
	if un.size() >= PRESSURE_HITS and _ready("pressure"):
		_cool_for("pressure", 20.0)
		out.append(_req("pressure", who, "low", names, {"ttl": 2.0}))
		return out
	# 7. an ordinary clean shot, now and then
	if dmg >= CLEAN_DAMAGE and _ready("hit_clean") and t - last_line_end_t > 3.0:
		_cool_for("hit_clean", 11.0)
		out.append(_req("hit_clean", who, "low", names, {"ttl": 1.2}))
	return out


func _on_knockdown(ev: Dictionary, info: Dictionary) -> Array:
	var fi := int(ev.get("fighter", -1))
	_action(t)
	var kd: Dictionary = _st["kd"]
	kd[fi] = int(kd.get(fi, 0)) + 1
	_st["match_knockdowns"] = int(_st.get("match_knockdowns", 0)) + 1
	var reason := str(ev.get("reason", "hit"))
	var att := int(ev.get("by", (_st["last_attacker"] as Dictionary).get(fi, -1)))
	var ck := _who(att, fi)
	var kinds: Array = []
	if reason in ["poise", "throw", "trip"]:
		kinds.append(reason)
	if int(_st["match_knockdowns"]) == 3:
		kinds.append("third")
	if int(kd[fi]) >= 2:
		kinds.append("repeat")
	ck["kind"] = kinds
	if referee or bool(info.get("referee", false)):
		ck["referee"] = true
		ck.erase("who")       # "Let him up or don't, I'm not the ref!" never plays under a referee
	if ten_point:
		ck["scoring"] = "ten_point"
	# a throw's own call is replaced by the knockdown it caused
	for p in _pending:
		if str(p["kind"]) == "throw" and int(p.get("victim", -1)) == fi:
			p["cancel"] = true
	return [_req("knockdown", ck, "high", _vars(att, fi), {"ttl": 2.5, "tag": "round", "energy": "high"})]


func _on_ko(ev: Dictionary, info: Dictionary) -> Dictionary:
	var fi := int(ev.get("fighter", -1))
	var att := int(ev.get("by", (_st["last_attacker"] as Dictionary).get(fi, -1)))
	var slot := str((_st["last_slot"] as Dictionary).get(fi, ""))
	var ck := _who(att, fi)
	var kinds: Array = []
	if slot in ["heavy", "finisher", "heavy_charged"]:
		kinds.append("heavy")
	elif slot in ["throw", "slam"]:
		kinds.append("throw")
	elif slot in ["zone", "reaction"]:
		kinds.append("zone")
	if str(ev.get("by_kind", "")) == "juice" or bool(info.get("attacker_juiced", false)):
		kinds.append("juice")
	if t - float(_st.get("round_started_at", 0.0)) < 30.0:
		kinds.append("fast")
	if bool(info.get("gore_full", false)):
		kinds.append("piece")
	ck["kind"] = kinds
	return _req("ko", ck, "critical", _vars(att, fi), {"tag": "result", "energy": "high"})


## The held KO call, now that we know what it ended: "fight" (the bout is decided), "round" (a
## best-of round goes to the attacker) or "none" (an elimination in a match that goes on).
func _release_ko(ends: String) -> Array:
	if _pending_ko.is_empty():
		return []
	var r := _pending_ko
	_pending_ko = {}
	(r["ctx"] as Dictionary)["ends"] = ends
	if ends == "fight":
		finished = true
	else:
		r["class"] = "high"
		r["priority"] = int(CLASS_PRIORITY["high"])
		r["tag"] = "round"
	return [r]


func _on_ability(ev: Dictionary) -> Array:
	var out: Array = []
	var fi := int(ev.get("fighter", -1))
	var aid := str(ev.get("id", ""))
	_action(t)
	_pending.append({"at": t + 2.6, "kind": "ability", "fighter": fi, "id": aid})
	# the cast itself is called now and then (every ability fires every few seconds)
	if _ready("ability:" + aid) and _ready("ability_any"):
		_cool_for("ability:" + aid, 28.0)
		_cool_for("ability_any", 7.0)
		out.append(_req("ability", {"creature": _creature(fi), "slot": str(ev.get("slot", "")), "id": aid}, "low", _vars(fi, -1),
			{"ttl": 1.5}))
	return out


func _on_round_end(ev: Dictionary) -> Array:
	var out: Array = []
	var winner_team := int(ev.get("winner", -1))
	var decided := bool(ev.get("decided", false))
	if not _pending_ko.is_empty():
		# a knockout ended this round: its call says it all
		return _release_ko("fight" if decided or rounds <= 1 else "round")
	if decided:
		finished = true
	if ten_point or rounds <= 1 or decided:
		return out
	var wf := -1
	for f in fighters:
		if int(f.get("team", -9)) == winner_team:
			wf = int(f.get("index", -1))
			break
	var c := {"kind": "won" if winner_team >= 0 else "even"}
	if wf >= 0 and _is_player(wf):
		c["who"] = "player"
	elif wf >= 0:
		c["who"] = "opponent"
	out.append(_req("round_end", c, "high", _vars(wf, -1), {"ttl": 3.0, "follow": {"trigger": "round_break", "class": "color", "ttl": 3.0}}))
	return out


func _on_round_scored(ev: Dictionary) -> Array:
	var out: Array = []
	var judges: Array = ev.get("judges", [])
	var winner_team := int(ev.get("winner", -1))
	var margin := 0
	var split := false
	var signs := {}
	for j in judges:
		if typeof(j) == TYPE_ARRAY and (j as Array).size() >= 2:
			var d := int(j[0]) - int(j[1])
			margin = maxi(margin, absi(d))
			signs[signi(d)] = true
	split = signs.size() > 1
	var kind := "clear"
	if winner_team < 0:
		kind = "even"
	elif margin >= 2:
		kind = "ten_eight"
	elif split:
		kind = "split"
	var wf := -1
	for f in fighters:
		if int(f.get("team", -9)) == winner_team:
			wf = int(f.get("index", -1))
			break
	if round_no >= rounds:
		return out        # the decision itself follows: no round call on top of it
	out.append(_req("judges_round", {"kind": kind}, "high", _vars(wf, -1), {"ttl": 3.0}))
	return out


func _on_decision(ev: Dictionary, info: Dictionary) -> Array:
	var out: Array = []
	var wt := int(ev.get("winner", -1))
	var method := str(ev.get("method", ""))
	if wt >= 0 and method == "TKO":
		return out          # the stoppage had its own call
	var wf := -1
	for f in fighters:
		if int(f.get("team", -9)) == wt:
			wf = int(f.get("index", -1))
			break
	var names := _team_names(wt)
	if wt >= 0 and method.begins_with("Sudden Death"):
		out.append(_req("time", {"kind": "sudden_death_won"}, "critical", names, {"tag": "result"}))
		return out
	if wt < 0:
		if not bool(info.get("sudden_death_follows", false)):
			_st["draw_announced"] = true
			out.append(_req("draw", {"kind": "decision"}, "critical", {}, {"tag": "result"}))
		return out
	var kind := "unanimous"
	var lower := method.to_lower()
	if lower.contains("split"):
		kind = "split"
	elif lower.contains("majority"):
		kind = "majority"
	var c := {"kind": kind}
	if wf >= 0 and _is_player(wf):
		c["who"] = "player"
	out.append(_req("decision", c, "critical", names, {"tag": "result", "energy": "high"}))
	return out


func _team_names(team: int) -> Dictionary:
	var ns := PackedStringArray()
	for f in fighters:
		if int(f.get("team", -9)) == team and str(f.get("name", "")) != "":
			ns.append(str(f.get("name", "")))
	return {"p": " & ".join(ns)} if not ns.is_empty() else {}


func _on_match_end(ev: Dictionary, _info: Dictionary) -> Array:
	var out: Array = []
	var w := int(ev.get("winner", -1))
	if w < 0:
		if not bool(_st.get("draw_announced", false)):
			out.append(_req("draw", {}, "critical", {}, {"tag": "result"}))
		return out
	var winner_creature := ""
	var wf := -1
	for f in fighters:
		if int(f.get("team", -98)) == w and winner_creature == "":
			winner_creature = str(f.get("creature", ""))
			wf = int(f.get("index", -1))
	var c := {"creature": winner_creature}
	var trig := "win"
	if context == "career":
		trig = "career_result"
		c["kind"] = "title" if bool(career.get("title", false)) else "win"
		c["who"] = "player" if wf >= 0 and _is_player(wf) else "opponent"
	var names := _team_names(w)
	out.append(_req(trig, c, "critical", names, {"tag": "final", "follow": {"trigger": "result", "class": "color", "ttl": 4.0, "speaker_pref": "kendall"}}))
	return out


# ---- the 4 Hz tick ------------------------------------------------------------------------------

## health: fractions per fighter; time_left: round clock (-1 = none); positions: optional
## {index: Vector3} with arena_radius for edge observations.
func on_tick(health: Array, time_left: float, dt: float, info := {}) -> Array:
	var out: Array = []
	t += dt
	_health = health.duplicate()
	# a KO whose tick brought no round_end: an elimination in a match that continues
	out.append_array(_release_ko("none"))
	# deferred checks (whiffs, evasions, throws, ability results)
	var keep: Array = []
	for p in _pending:
		if float(p["at"]) > t:
			keep.append(p)
			continue
		if bool(p.get("cancel", false)) or finished:
			continue
		match str(p["kind"]):
			"whiff":
				if _ready("whiff"):
					_cool_for("whiff", 15.0)
					out.append(_req("whiff", _who(int(p["fighter"]), -1), "low", _vars(int(p["fighter"]), -1), {"ttl": 1.2}))
			"evade":
				# a dodge that took nothing (no damage since) and came while an attack was out
				if _hp(int(p["fighter"])) >= float(p["hp"]) - 0.001 and t - last_action_t < 1.5 and _ready("evade"):
					_cool_for("evade", 16.0)
					out.append(_req("evade", _who(int(p["fighter"]), -1), "low", _vars(int(p["fighter"]), -1), {"ttl": 1.2}))
			"throw":
				if _ready("grab_throw"):
					_cool_for("grab_throw", 14.0)
					out.append(_req("grab_throw", _who(int(p["fighter"]), int(p.get("victim", -1))), "low",
						_vars(int(p["fighter"]), int(p.get("victim", -1))), {"ttl": 1.5}))
	_pending = keep
	if finished:
		return out
	out.append_array(_watch_health(health))
	out.append_array(_watch_momentum(health))
	if time_left > 0.0 and time_left <= 10.0 and not bool(_st.get("ten_warned", false)):
		_st["ten_warned"] = true
		out.append(_req("time", {"kind": "ten_seconds"}, "medium", {}, {"ttl": 2.0}))
	elif time_left > 10.0:
		_st["ten_warned"] = false
	if not out.is_empty():
		return out
	# lulls: observations, then color
	var quiet := t - last_action_t
	if quiet >= LULL and _room_for("low") and _ready("observe"):
		var obs := _observation(health, time_left, info)
		if not obs.is_empty():
			_cool_for("observe", _rng.randf_range(9.0, 14.0))
			out.append(obs)
			return out
	if t >= _color_next_at and quiet >= COLOR_LULL * 0.5 and _room_for("color"):
		var col := _color()
		if not col.is_empty():
			_color_next_at = t + _rng.randf_range(16.0, 26.0)
			out.append(col)
	return out


func _watch_health(health: Array) -> Array:
	var out: Array = []
	var low: Dictionary = _st["low"]
	var low_count := 0
	for i in health.size():
		var h := float(health[i])
		if h < 0.2 and h > 0.0:
			low_count += 1
	for i in health.size():
		var h2 := float(health[i])
		if h2 < 0.2 and h2 > 0.0 and not bool(low.get(i, false)):
			low[i] = true
			var ctx := {"who": "player" if _is_player(i) else "opponent"}
			if low_count >= 2:
				ctx["who"] = "both"
			if h2 < 0.1:
				ctx["kind"] = "ten"
			if context == "coop":
				ctx["context"] = "coop"
			out.append(_req("low_health", ctx, "medium", _vars(i, -1), {"ttl": 3.0}))
		elif h2 >= 0.3:
			low[i] = false
	_st["low"] = low
	return out


## A trailing fighter out-landing the leader over the last 12 s: the tide is turning.
func _watch_momentum(health: Array) -> Array:
	var out: Array = []
	if health.size() < 2 or not _ready("momentum"):
		return out
	var recent := {}
	for fi in _st["dealt"]:
		var arr: Array = (_st["dealt"] as Dictionary)[fi]
		var keep: Array = arr.filter(func(x: Array) -> bool: return t - float(x[0]) < 12.0)
		(_st["dealt"] as Dictionary)[fi] = keep
		var s := 0.0
		for x in keep:
			s += float(x[1])
		recent[fi] = s
	for fi2 in recent:
		var me := int(fi2)
		var mine := float(recent[fi2])
		var theirs := 0.0
		for other in recent:
			if int(other) != me and _team(int(other)) != _team(me):
				theirs = maxf(theirs, float(recent[other]))
		if me >= health.size():
			continue
		var my_hp := float(health[me])
		var best_other := 0.0
		for j in health.size():
			if j != me and _team(j) != _team(me):
				best_other = maxf(best_other, float(health[j]))
		if mine >= 20.0 and mine >= 2.2 * theirs and my_hp + 0.2 < best_other and int(_st.get("momentum_owner", -1)) != me:
			_st["momentum_owner"] = me
			_cool_for("momentum", 30.0)
			var c := {"who": "player" if _is_player(me) else "opponent"}
			out.append(_req("comeback", c, "medium", _vars(me, -1), {"ttl": 3.0, "energy": "high"}))
			break
	return out


func _observation(health: Array, time_left: float, info: Dictionary) -> Dictionary:
	var cands: Array = []
	if health.size() >= 2:
		var lo := 1.0
		var hi := 0.0
		for h in health:
			lo = minf(lo, float(h))
			hi = maxf(hi, float(h))
		if hi - lo < 0.12 and hi < 0.75:
			cands.append(_req("close", {}, "low", {}, {"ttl": 3.0}))
		if lo < 0.3 and lo > 0.0:
			var who := -1
			for i in health.size():
				if float(health[i]) == lo:
					who = i
			cands.append(_req("hurt", _who(-1, who), "low", _vars(who, -1), {"ttl": 3.0}))
	if time_left > 0.0 and time_left < 30.0:
		cands.append(_req("late", {"round": "final" if round_no >= rounds and rounds > 1 else "any"}, "low", {}, {"ttl": 3.0}))
	if round_no == 1 and t - float(_st.get("round_started_at", 0.0)) < 20.0:
		cands.append(_req("opening", {}, "low", {}, {"ttl": 3.0}))
	var edge := int(info.get("edge_fighter", -1))
	if edge >= 0:
		var ce := _who(-1, edge)
		ce["kind"] = str(info.get("edge_kind", "cage"))
		cands.append(_req("edge", ce, "low", _vars(edge, -1), {"ttl": 2.0}))
	for fi in (_st["unanswered"] as Dictionary):
		if ((_st["unanswered"] as Dictionary)[fi] as Array).size() >= 3:
			cands.append(_req("pressure", _who(int(fi), -1), "low", _vars(int(fi), -1), {"ttl": 2.0}))
			break
	if cands.is_empty():
		return {}
	return cands[_rng.randi_range(0, cands.size() - 1)]


func _color() -> Dictionary:
	var creatures: Array = []
	var elements: Array = []
	for f in fighters:
		var c := str(f.get("creature", ""))
		if c != "" and not creatures.has(c):
			creatures.append(c)
		var el := str(f.get("element", ""))
		if el != "" and not elements.has(el):
			elements.append(el)
	var matchups: Array = []
	for i in range(fighters.size()):
		for j in range(i + 1, fighters.size()):
			if int(fighters[i].get("team", -1)) == int(fighters[j].get("team", -2)):
				continue
			var pair: Array = [str(fighters[i].get("creature", "")), str(fighters[j].get("creature", ""))]
			pair.sort()
			matchups.append(str(pair[0]) + "|" + str(pair[1]))
	var roll := _rng.randi_range(0, 99)
	var ctx := {"creature": creatures, "matchup": matchups, "element": elements}
	var trigger := "color"
	if not _conversation_done and context in ["spectate", "versus", "campaign", "career"] and roll < 6 and t - last_action_t > 9.0:
		_conversation_done = true
		trigger = "color_conversation"
	elif roll >= 90:
		trigger = "matchup_color"
	elif roll >= 80:
		trigger = "element_color"
	elif roll >= 62:
		trigger = "fighter_color"
	return _req(trigger, ctx, "color", {}, {"ttl": 2.5, "speaker_pref": "kendall" if roll % 2 == 0 else "barnaby"})
