class_name RoundJudge
extends RefCounted
## 10-point must scoring for a standard duel (rules "scoring": "ten_point", MCH-07). Owned by
## MatchMode (created in MatchMode.setup only for the standard mode, a two-sided duel and a round
## timer: see MatchMode._setup_officials). Three judges score every round from one tally of the
## sim's own event stream; the cards decide the match unless a referee stops it.
##
## Invariants:
##  * Deterministic and RNG-free: the tally, the three judges and the decision are pure functions
##    of the events of the round; the judge never touches sim.rng (or any RNG).
##  * Counts only between round_start (begin_round) and the round's close (score_round): events of
##    the intro, after the bell and during a sudden death that follows drawn cards are ignored.
##  * Team order everywhere is ascending team id: `teams` = [ta, tb]; every per-team value is an
##    Array aligned with it. No dictionary is keyed by a team or fighter index, all keys are
##    strings and whole-number floats are stored as ints, so cards, events and results are
##    unchanged by Saves.stabilize (JSON) and travel as plain data (var_to_bytes, NetEventCodec).
##  * A tally only credits a team for what it did to the OTHER team (hazards, self damage and
##    ally hits never score). taken_head + taken_body + taken_legs of one team == damage of the
##    other (DoT counts as body).
##
## Tally (per round, per team): damage (raw HP, blocked chip included, parried = 0, DoT by an
## enemy included), dmg_pts (damage normalised by the target's max HP: damage / max_health * 100
## * K_DMG), landed / blocked (melee strikes that landed clean / were blocked), thrown (strikes
## started), knockdowns (strike knockdowns: reason poise|move|hit by an enemy), throws, ringouts,
## parries, guard_breaks (the opponent's guard broken), taken_head / taken_body / taken_legs.
## With a referee, damage dealt to a fighter who was already down is never credited.
## Movesets (v0.9.18, hits and move starts carry the pool move and its category): a projectile,
## volley, blast or rush hit lands like a strike; a stream's repeating ticks land once per
## TICK_CREDIT_S of contact per target (not per tick); zones count as damage only; "thrown" counts
## the starts of offensive moves (strike, projectile, volley, stream, blast, rush). Classic matches
## keep the v0.9.16 counting (melee strikes only).
##
## Round score P = dmg_pts + W_LANDED*landed + W_KD*knockdowns + W_THROW*throws
##   + W_RINGOUT*ringouts + W_PARRY*parries + W_GUARD_BREAK*guard_breaks
## Judges: "Even card" P; "Volume" P + 0.5*landed + 1*parries; "Impact" P + 0.25*dmg_pts
## + 2*knockdowns. Per judge d = P_a - P_b: |d| < CLOSE -> 10-10; else 10-9 to the higher side,
## 10-8 when |d| >= DOMINANT, or when the round winner scored more knockdowns and |d| >= DOMINANT_KD.
## Decision over the judges' totals: 3-0 Unanimous, 2-0-1 Majority, 2-1 Split Decision; otherwise
## a Unanimous (0-0-3), Majority (1-0-2) or Split (1-1-1) Draw.
##
## Calibration (v0.9.16, 52 headless Cage Rules bot duels; numbers in docs/DECISIONS.md): bot
## rounds are lopsided (|P_a - P_b| median 25 in same-tier duels, 56 in mismatches) and knockdowns
## are frequent (0.77 per fighter-round), so CLOSE 3 gives ~8% 10-10 cards and the dominance
## thresholds sit high: 10-8 on ~5% of same-tier cards and ~33% of mismatch cards.

const K_DMG := 0.25
const CLOSE := 3.0
const DOMINANT := 80.0
const DOMINANT_KD := 65.0
const W_LANDED := 0.5
const W_KD := 10.0
const W_THROW := 4.0
const W_RINGOUT := 6.0
const W_PARRY := 2.0
const W_GUARD_BREAK := 2.0
const JUDGE_NAMES := ["Even card", "Volume", "Impact"]
const STRIKE_KD_REASONS := ["poise", "move", "hit"]
const TALLY_KEYS := ["damage", "dmg_pts", "landed", "blocked", "thrown", "knockdowns", "throws", "ringouts",
	"parries", "guard_breaks", "taken_head", "taken_body", "taken_legs"]
const FLOAT_KEYS := ["damage", "dmg_pts", "taken_head", "taken_body", "taken_legs"]
const STRIKE_SLOT_CLASSES := ["light", "heavy"]
const OFFENSIVE_CATEGORIES := ["strike", "projectile", "volley", "stream", "blast", "rush"]
const TICK_CREDIT_S := 1.0

var sim: MatchSim
var referee_on := false          ## set by MatchMode: a referee protects downed fighters
var _tick_credit := {}           ## "side|target" -> sim time a repeating hit was last credited as landed
var teams: Array[int] = []       ## [ta, tb], ascending
var cards: Array = []            ## every scored round (plain data, see score_round)
var decision := {}               ## the last decision ({} until the cards are complete)
var counting := false            ## true between begin_round and the round's close
var _tally: Array = []           ## [{...ta...}, {...tb...}] (unrounded floats)
var _cursor := 0                 ## last event seq consumed


## No back-reference to the mode (RefCounted cycles never free): the mode passes what it knows.
func _init(match_sim: MatchSim, team_ids: Array) -> void:
	sim = match_sim
	for t in team_ids:
		teams.append(int(t))
	teams.sort()
	_tally = [empty_tally(), empty_tally()]
	_cursor = sim.event_seq


static func empty_tally() -> Dictionary:
	var t := {}
	for k in TALLY_KEYS:
		t[k] = 0.0 if k in FLOAT_KEYS else 0
	return t


## One definition of a strike knockdown, shared by the judges and the referee: a poise / move /
## hit knockdown caused by an opponent. Hazard, self and throw knockdowns never count.
static func is_strike_knockdown(sim_: MatchSim, ev: Dictionary) -> bool:
	if str(ev.get("type", "")) != "knockdown" or not str(ev.get("reason", "")) in STRIKE_KD_REASONS:
		return false
	var by := int(ev.get("by", -1))
	var v := int(ev.get("fighter", -1))
	if by < 0 or v < 0 or by >= sim_.fighters.size() or v >= sim_.fighters.size() or by == v:
		return false
	return sim_.are_enemies(sim_.fighters[by], sim_.fighters[v])


## Index (0/1) of a team in `teams`, -1 if not judged.
func slot_of_team(team: int) -> int:
	return teams.find(team)


func _slot_of_fighter(i: int) -> int:
	if i < 0 or i >= sim.fighters.size():
		return -1
	return slot_of_team(sim.fighters[i].team)


## The round starts (MatchMode, at round_start): a fresh tally from the current event.
func begin_round() -> void:
	_tally = [empty_tally(), empty_tally()]
	_tick_credit.clear()
	_cursor = sim.event_seq
	counting = true


## Consumes new events into the tally (every FIGHT tick, and once more at the close).
func scan() -> void:
	if not counting:
		_cursor = sim.event_seq
		return
	# walk back to the first unseen event (cheap: the ring is ordered by seq)
	var evs: Array = sim.events
	var i := evs.size()
	while i > 0 and int(evs[i - 1]["seq"]) > _cursor:
		i -= 1
	while i < evs.size():
		var ev: Dictionary = evs[i]
		_cursor = int(ev["seq"])
		_take(ev)
		i += 1


func flush() -> void:
	scan()


func _take(ev: Dictionary) -> void:
	match str(ev.get("type", "")):
		"hit":
			_take_damage(int(ev.get("fighter", -1)), int(ev.get("target", -1)), float(ev.get("damage", 0.0)),
				str(ev.get("part", "core")), ev)
		"dot":
			_take_damage(int(ev.get("by", -1)), int(ev.get("fighter", -1)), float(ev.get("damage", 0.0)), "core", ev)
		"knockdown":
			if is_strike_knockdown(sim, ev):
				_add(_slot_of_fighter(int(ev["by"])), "knockdowns", 1)
		"throw":
			var thrower := int(ev.get("fighter", -1))
			if _enemies(thrower, int(ev.get("victim", -1))):
				_add(_slot_of_fighter(thrower), "throws", 1)
		"parry":
			var defender := int(ev.get("fighter", -1))
			if _enemies(defender, int(ev.get("attacker", -1))):
				_add(_slot_of_fighter(defender), "parries", 1)
		"guard_break":
			# a duel: the other side broke it
			var s := _slot_of_fighter(int(ev.get("fighter", -1)))
			if s >= 0:
				_add(1 - s, "guard_breaks", 1)
		"move_start":
			var slot := str(ev.get("slot", "")).split("@")[0]
			if ev.has("pool"):
				if slot != "pummel" and str(ev.get("cat", "")) in OFFENSIVE_CATEGORIES:
					_add(_slot_of_fighter(int(ev.get("fighter", -1))), "thrown", 1)
			elif slot != "pummel" and Combat.move_class(slot) in STRIKE_SLOT_CLASSES:
				_add(_slot_of_fighter(int(ev.get("fighter", -1))), "thrown", 1)


func _enemies(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a >= sim.fighters.size() or b >= sim.fighters.size():
		return false
	return sim.are_enemies(sim.fighters[a], sim.fighters[b])


func _take_damage(by: int, target: int, dmg: float, part: String, ev: Dictionary) -> void:
	if not _enemies(by, target):
		return
	var s := _slot_of_fighter(by)
	var o := _slot_of_fighter(target)
	if s < 0 or o < 0:
		return
	if bool(ev.get("was_down", false)) and referee_on:
		return   # the referee keeps it off a downed fighter: nothing to credit
	var pooled := str(ev.get("pool", "")) != ""
	if str(ev.get("type", "")) == "hit" and (bool(ev.get("melee", false)) or pooled):
		var tick := bool(ev.get("tick", false))
		if bool(ev.get("blocked", false)):
			if not tick:
				_add(s, "blocked", 1)
		elif not bool(ev.get("parried", false)) and dmg > 0.0:
			if tick:
				# a stream lands once per second of contact, however often it ticks
				var key := "%d|%d" % [s, target]
				if sim.time - float(_tick_credit.get(key, -99.0)) >= TICK_CREDIT_S:
					_tick_credit[key] = sim.time
					_add(s, "landed", 1)
			else:
				_add(s, "landed", 1)
	if dmg <= 0.0:
		return
	var mh := maxf(1.0, sim.fighters[target].max_health)
	_add(s, "damage", dmg)
	_add(s, "dmg_pts", dmg / mh * 100.0 * K_DMG)
	var region := "taken_head" if part == "head" else ("taken_legs" if part == "leg" else "taken_body")
	_add(o, region, dmg)


func _add(slot: int, key: String, v) -> void:
	if slot < 0 or slot > 1:
		return
	var t: Dictionary = _tally[slot]
	if key in FLOAT_KEYS:
		t[key] = float(t[key]) + float(v)
	else:
		t[key] = int(t[key]) + int(v)


## Ring-outs are priced by MatchMode.on_ringout (both ring-out paths reach it with the attacker).
func note_ringout(f: Fighter, attacker: Fighter) -> void:
	if not counting or attacker == null or not sim.are_enemies(attacker, f):
		return
	_add(slot_of_team(attacker.team), "ringouts", 1)


## The live (unrounded) tally of the current round, aligned with `teams`.
func live_tally() -> Array:
	return [_tally[0].duplicate(), _tally[1].duplicate()]


## Closes the round: scores it, freezes the tally until the next begin_round and returns the card
## {round, teams, judges [[a,b] x3], scores [[Pa,Pb] x3], tally [{..}, {..}], winner (team | -1),
## stoppage (bool)}. `stoppage` is the referee's stoppage dict ({} at the bell).
func score_round(round_no: int, stoppage := {}) -> Dictionary:
	flush()
	counting = false
	var sc := score_tallies(_tally[0], _tally[1])
	var w_slot := int(sc["winner"])
	var card := {"round": round_no, "teams": [teams[0], teams[1]], "judges": sc["judges"], "scores": sc["scores"],
		"tally": [plain_tally(_tally[0]), plain_tally(_tally[1])],
		"winner": teams[w_slot] if w_slot >= 0 else -1, "stoppage": not stoppage.is_empty()}
	cards.append(card)
	return card


## Judges' running totals over every scored round: [[A,B] x3] (ints).
func totals() -> Array:
	return totals_of(cards)


static func totals_of(card_list: Array) -> Array:
	var tot := [[0, 0], [0, 0], [0, 0]]
	for c in card_list:
		var js: Array = c["judges"]
		for j in 3:
			tot[j][0] = int(tot[j][0]) + int(js[j][0])
			tot[j][1] = int(tot[j][1]) + int(js[j][1])
	return tot


## The three judges' view of one round from the two tallies. Returns {judges: [[a,b] x3] (ints),
## scores: [[Pa,Pb] x3] (0.1, plain), winner: 0|1 (slot of the majority) | -1}.
static func score_tallies(ta: Dictionary, tb: Dictionary) -> Dictionary:
	var judges := []
	var scores := []
	var votes := [0, 0]
	for j in 3:
		var pa := judge_score(j, ta)
		var pb := judge_score(j, tb)
		var pair := card_pair(pa - pb, int(ta.get("knockdowns", 0)), int(tb.get("knockdowns", 0)))
		judges.append(pair)
		scores.append([plain(pa), plain(pb)])
		if int(pair[0]) > int(pair[1]):
			votes[0] += 1
		elif int(pair[1]) > int(pair[0]):
			votes[1] += 1
	var w := 0 if int(votes[0]) >= 2 else (1 if int(votes[1]) >= 2 else -1)
	return {"judges": judges, "scores": scores, "winner": w}


## Base round score P of one side (see the file header).
static func base_score(t: Dictionary) -> float:
	return float(t.get("dmg_pts", 0.0)) + W_LANDED * float(t.get("landed", 0)) + W_KD * float(t.get("knockdowns", 0)) \
		+ W_THROW * float(t.get("throws", 0)) + W_RINGOUT * float(t.get("ringouts", 0)) \
		+ W_PARRY * float(t.get("parries", 0)) + W_GUARD_BREAK * float(t.get("guard_breaks", 0))


## Judge j's score of one side: 0 "Even card", 1 "Volume", 2 "Impact".
static func judge_score(j: int, t: Dictionary) -> float:
	var p := base_score(t)
	match j:
		1:
			p += 0.5 * float(t.get("landed", 0)) + 1.0 * float(t.get("parries", 0))
		2:
			p += 0.25 * float(t.get("dmg_pts", 0.0)) + 2.0 * float(t.get("knockdowns", 0))
	return p


## One judge's 10-point must card for a score difference d = P_a - P_b: [a, b].
static func card_pair(d: float, kd_a: int, kd_b: int) -> Array:
	var ad := absf(d)
	if ad < CLOSE:
		return [10, 10]
	var win_kd := kd_a if d > 0.0 else kd_b
	var lose_kd := kd_b if d > 0.0 else kd_a
	var loser := 9
	if ad >= DOMINANT or (win_kd > lose_kd and ad >= DOMINANT_KD):
		loser = 8
	return [10, loser] if d > 0.0 else [loser, 10]


## The decision over a list of cards: {winner_slot: 0|1|-1, method, totals, judges: [slot|-1 x3]}.
static func decide_cards(card_list: Array) -> Dictionary:
	var tot := totals_of(card_list)
	var w := [0, 0]
	var per := []
	for j in 3:
		if int(tot[j][0]) > int(tot[j][1]):
			w[0] += 1
			per.append(0)
		elif int(tot[j][1]) > int(tot[j][0]):
			w[1] += 1
			per.append(1)
		else:
			per.append(-1)
	var even := 3 - int(w[0]) - int(w[1])
	var slot := -1
	var method := ""
	if int(w[0]) >= 2 or int(w[1]) >= 2:
		slot = 0 if int(w[0]) >= 2 else 1
		method = ("Unanimous" if even == 0 and (int(w[0]) == 3 or int(w[1]) == 3) else ("Majority" if even == 1 else "Split")) + " Decision"
	else:
		method = ("Unanimous" if even == 3 else ("Majority" if even == 2 else "Split")) + " Draw"
	return {"winner_slot": slot, "method": method, "totals": tot, "judges": per}


## The decision on this match's cards, with teams instead of slots: {winner (team | -1), method,
## totals [[A,B] x3], judges [team | -1 x3], teams}.
func decide() -> Dictionary:
	var d := decide_cards(cards)
	var per := []
	for s in d["judges"]:
		per.append(teams[int(s)] if int(s) >= 0 else -1)
	var ws := int(d["winner_slot"])
	return {"winner": teams[ws] if ws >= 0 else -1, "method": str(d["method"]), "totals": d["totals"],
		"judges": per, "teams": [teams[0], teams[1]]}


## Judges' verdict of the cards so far (team | -1 per judge), used for a stoppage's decision event.
func judges_leaning() -> Array:
	return decide()["judges"]


## Rounded, JSON-stable copy of a tally (0.1 for HP values; whole numbers as ints).
static func plain_tally(t: Dictionary) -> Dictionary:
	var out := {}
	for k in TALLY_KEYS:
		out[k] = plain(float(t.get(k, 0.0))) if k in FLOAT_KEYS else int(t.get(k, 0))
	return out


## A number as stored in cards: rounded to 0.1, whole values as int (what Saves.stabilize keeps).
static func plain(v: float):
	var r := snappedf(v, 0.1)
	if is_finite(r) and floorf(r) == r and absf(r) < 1e15:
		return int(r)
	return r
