extends TestCase
## MCH-07 / MCH-08 presentation (v0.9.16): 10-point scoring and the referee on screen, locally and
## on a network client. FightHud hides the HP bars and shows the round line and the judges' running
## totals (local sim and NetHudMirror alike), the between-rounds scorecard and the decision banner;
## the referee's count shows on the downed fighter's card with a hint for the local player. The
## match scenes spawn the view-only referee only when the sim (or the replicated rules) has one,
## never frame him, and never claim "X WINS THE ROUND" for the round a decision closed. Results
## show the method, the judges' totals and the ScorecardPanel, and still fit at 1280x800 and
## 1920x1080 (2- and 5-round cards, T.K.O., draws). HP-scoring presentation is unchanged.
## Run: godot --headless --path game --fixed-fps 120 -- --test test_ten_point_ui --user-root <tmp>

const CAGE := {"id": "cage_test", "mode": "standard", "format": "duel", "teams": 2, "players": [2, 2], "rounds": 3,
	"round_time": 2.0, "intro_time": 0.3, "win": "ko", "lives": 1, "sudden_death": false, "scoring": "ten_point", "referee": true}
const DUEL := {"id": "duel_test", "mode": "standard", "format": "duel", "teams": 2, "players": [2, 2], "rounds": 3,
	"round_time": 99.0, "intro_time": 0.3, "win": "ko", "lives": 1, "sudden_death": true}


func before_each() -> void:
	App.clear_screens()


func after_each() -> void:
	App.clear_screens()
	if App.current_scene != null:
		App.set_scene(null)
	Engine.time_scale = 1.0


func _rules(base: Dictionary, over := {}) -> Dictionary:
	var r := base.duplicate(true)
	r.merge(over, true)
	return r


func _hud(sim: MatchSim, player := 0) -> FightHud:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := FightHud.new()
	layer.add_child(hud)
	hud.setup(sim, player)
	return hud


func _free_hud(hud: FightHud) -> void:
	if is_instance_valid(hud):
		hud.get_parent().queue_free()
	await wait_frames(1)


func _labels(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "Label", true, false):
		out.append(n)
	return out


func _label_with(root: Node, text: String) -> Label:
	if root == null:
		return null
	for l: Label in _labels(root):
		if l.is_visible_in_tree() and l.text.contains(text):
			return l
	return null


## Every visible text under `root` is at least Caption size (28 du).
func _text_at_least(root: Control, du: int, tag: String) -> void:
	var smallest := 999
	var which := ""
	for l: Label in _labels(root):
		if not l.is_visible_in_tree() or l.text.strip_edges() == "":
			continue
		var s := l.get_theme_font_size("font_size")
		if s < smallest:
			smallest = s
			which = l.text
	check(smallest >= du, "%s: smallest text '%s' is %d du (>= %d)" % [tag, which.substr(0, 30), smallest, du])


func _until(pred: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if bool(pred.call()):
			return true
		await get_tree().process_frame
	return bool(pred.call())


func _attacker() -> InputSource:
	return InputSource.Scripted.new([{"t0": 0.0, "t1": 999.0, "move": "to_target", "press": ["light"], "every": 0.25}])


## A snapshot sample / roster pair for a NetHudMirror (dev_biped, two fighters).
func _replica() -> NetReplica:
	var rep := NetReplica.new()
	rep.reset({"tick_rate": 120, "snapshot_rate": 30, "match_id": 1, "fighters": [
		{"slot": 0, "gen": 1, "creature": "dev_biped", "scale": 1.0, "team": 0, "name": "Alice", "kind": "net", "despawned": false},
		{"slot": 1, "gen": 1, "creature": "dev_biped", "scale": 1.0, "team": 1, "name": "Bob", "kind": "bot", "despawned": false}]})
	return rep


func _fd(root: Vector3, state := Fighter.State.NEUTRAL) -> Dictionary:
	var c := Content.creature("dev_biped")
	var rots: Array[Quaternion] = []
	for s in c.body.segments.size():
		rots.append(Quaternion.IDENTITY)
	return {"gen": 1, "state": state, "flags": NetSnapshot.F_GROUNDED, "root": root, "rots": rots, "health": 100.0,
		"max_health": 100.0, "stamina": 80.0, "max_stamina": 100.0, "poise": 80.0, "max_poise": 100.0, "hype": 10.0,
		"lives": 1, "target": -1, "cooldowns": {}, "statuses": []}


func _sample(hud_state: Dictionary, view: Dictionary, phase := MatchMode.Phase.FIGHT, round_index := 1, down := -1) -> Dictionary:
	var fa := _fd(Vector3(-0.9, 0.9, 0.0), Fighter.State.DOWN if down == 0 else Fighter.State.NEUTRAL)
	var fb := _fd(Vector3(0.9, 0.9, 0.0), Fighter.State.DOWN if down == 1 else Fighter.State.NEUTRAL)
	fa["target"] = 1
	fb["target"] = 0
	return {"fighters": [fa, fb], "entities": [], "props": [], "mode": {"phase": phase, "round": round_index, "timer": 42.5, "flags": 1,
		"winner": -2, "round_winner": -2, "teams": [{"team": 0, "wins": 1, "score": 0}, {"team": 1, "wins": 0, "score": 0}],
		"status": "", "hud": hud_state, "view": view}}


func _round_ev(rn: int, judges: Array, totals: Array, winner: int, stoppage := false) -> Dictionary:
	return {"type": "round_scored", "round": rn, "teams": [0, 1], "judges": judges, "scores": [[30, 20], [33, 22], [36, 24]],
		"tally": [RoundJudge.empty_tally(), RoundJudge.empty_tally()], "winner": winner, "stoppage": stoppage, "totals": totals}


# ---- FightHud ---------------------------------------------------------------------------------

func test_hud_hides_health_and_shows_round_and_cards_locally() -> void:
	var sim := make_sim("the_gullet", _rules(CAGE), [{"creature": "f_stoke", "team": 0, "source": _attacker()},
		{"creature": "f_dredge", "team": 1, "source": null}], 21)
	check(sim.mode.unlimited_health() and sim.mode.has_referee(), "a judged, refereed duel")
	var hud := _hud(sim)
	await wait_frames(3)
	check(hud.is_ten_point(), "the HUD sees 10-point scoring")
	for c in hud.cards.values():
		check(c.has("hp_stack") and not (c["hp_stack"] as Control).visible, "HP stack hidden under 10-point")
		check(c.has("chip") and (c["chip"] as Control).visible, "team chip (letter + colour) shown")
		check(c.has("box") and c.has("name") and c.has("hp") and c.has("status"), "existing card keys kept")
		check((c["box"] as Control).get_global_rect().end.y < hud._sub.get_global_rect().position.y, "card above the subtitles")
	check(hud._round_label.visible and hud._round_label.text == "ROUND 1 / 3", "round line: '%s'" % hud._round_label.text)
	check_eq(hud._cards_label.text, "3 JUDGES · 10-POINT MUST", "before the first card")
	_text_at_least(hud._round_label, 28, "round line")
	_text_at_least(hud._cards_label, 28, "cards line")
	# play round 1 to the bell: the running totals come from hud_state.cards
	await step_sim(sim, 3.2)
	await wait_frames(2)
	check_eq(sim.mode.judge.cards.size(), 1, "round 1 scored")
	var want := "CARDS A–B   " + FightHud.totals_text(sim.mode.judge.totals())
	check_eq(hud._cards_label.text, want, "running totals under the timer")
	await _free_hud(hud)
	# Health scoring: the HUD is exactly the plain one (with or without a referee)
	for ref in [false, true]:
		var s2 := make_sim("the_gullet", _rules(DUEL, {"referee": ref}), [{"creature": "f_stoke", "team": 0, "source": null},
			{"creature": "f_dredge", "team": 1, "source": null}], 22)
		var h2 := _hud(s2)
		await wait_frames(3)
		check(not h2.is_ten_point(), "HP scoring is not 10-point (referee %s)" % ref)
		for c in h2.cards.values():
			check((c["hp_stack"] as Control).visible, "HP stack visible under Health scoring")
			check(not (c["chip"] as Control).visible, "no team chip under Health scoring")
			check(str((c["hp_text"] as Label).text) != "", "HP number shown")
		check(not h2._round_label.visible and not h2._cards_label.visible, "no round / cards line under Health scoring")
		await _free_hud(h2)


func test_hud_on_the_net_mirror_cards_count_and_sudden_death() -> void:
	var rep := _replica()
	var mirror := NetHudMirror.new()
	mirror.build({"rules": _rules(CAGE), "mode": "standard", "you": 0}, rep)
	check(mirror.sim.mode.judge == null and not mirror.sim.mode.unlimited_health(), "the mirror has no judge of its own")
	var hs := {"cards": {"n": 2, "t": [[20, 18], [20, 18], [19, 19]]}}
	var view := {"mode": "standard", "referee": {"count": {"fighter": 0, "n": 3, "left": 1.2}}}
	mirror.update(_sample(hs, view, MatchMode.Phase.FIGHT, 1, 0), 1.0 / 60.0)
	var hud := _hud(mirror.sim, 0)
	await wait_frames(4)
	check(hud.is_ten_point(), "hud_state.cards marks a 10-point match on the mirror")
	for c in hud.cards.values():
		check(not (c["hp_stack"] as Control).visible, "mirror: HP stack hidden")
	check_eq(hud._round_label.text, "ROUND 2 / 3", "mirror round line")
	check_eq(hud._cards_label.text, "CARDS A–B   20–18 · 20–18 · 19–19", "mirror running totals")
	check_eq((hud.cards[0]["status"] as Label).text, "DOWN · 3", "the counted fighter's card")
	check_eq((hud.cards[1]["status"] as Label).text, "", "the other card has no count")
	check(hud._ref_hint.visible and hud._ref_hint.text.contains("waves you up in 2s"), "local player hint: '%s'" % hud._ref_hint.text)
	check(hud._ref_hint.get_global_rect().end.y <= hud._sub.get_global_rect().position.y + 1.0, "hint above the subtitles")
	_text_at_least(hud._ref_hint, 28, "referee hint")
	# someone else counted: no hint for this player
	mirror.update(_sample(hs, {"mode": "standard", "referee": {"count": {"fighter": 1, "n": 1, "left": 3.0}}}, MatchMode.Phase.FIGHT, 1, 1), 1.0 / 60.0)
	await wait_frames(2)
	check(not hud._ref_hint.visible, "no hint when the opponent is counted")
	check_eq((hud.cards[1]["status"] as Label).text, "DOWN · 1", "opponent's count on its card")
	# a stoppage latched for the round
	mirror.update(_sample(hs, {"mode": "standard", "referee": {"stop": 1, "wave_off": true}}, MatchMode.Phase.ROUND_END), 1.0 / 60.0)
	await wait_frames(2)
	check_eq((hud.cards[1]["status"] as Label).text, "STOPPED", "the stopped fighter's card")
	# drawn cards -> sudden death
	mirror.update(_sample({"cards": {"n": 3, "t": [[29, 29], [28, 29], [29, 28]]}, "sd": true}, {"mode": "standard"}, MatchMode.Phase.FIGHT, 2), 1.0 / 60.0)
	await wait_frames(2)
	check_eq(hud._round_label.text, "DRAWN CARDS — SUDDEN DEATH", "the drawn-cards note")
	await _free_hud(hud)
	# a Health-scoring mirror keeps the HP bars
	var hp_mirror := NetHudMirror.new()
	hp_mirror.build({"rules": _rules(DUEL), "mode": "standard", "you": 0}, _replica())
	hp_mirror.update(_sample({"rows": []}, {"mode": "standard"}), 1.0 / 60.0)
	var h2 := _hud(hp_mirror.sim, 0)
	await wait_frames(3)
	check(not h2.is_ten_point(), "an HP mirror is not 10-point")
	check((h2.cards[0]["hp_stack"] as Control).visible, "mirror under Health scoring: HP visible")
	await _free_hud(h2)
	mirror.free_all()
	hp_mirror.free_all()


func test_between_rounds_scorecard_and_decision_banner() -> void:
	var rep := _replica()
	var mirror := NetHudMirror.new()
	mirror.build({"rules": _rules(CAGE), "mode": "standard", "you": 0}, rep)
	var hs := {"cards": {"n": 1, "t": [[10, 9], [10, 9], [10, 10]]}}
	mirror.update(_sample(hs, {"mode": "standard"}, MatchMode.Phase.ROUND_END, 0), 1.0 / 60.0)
	var hud := _hud(mirror.sim, 0)
	await wait_frames(3)
	hud.show_round_card(_round_ev(1, [[10, 9], [10, 9], [10, 10]], [[10, 9], [10, 9], [10, 10]], 0))
	await wait_frames(3)
	var rp := hud._round_panel
	check(rp != null and rp.is_visible_in_tree(), "between-rounds scorecard shown")
	for t in ["ROUND 1 SCORED", "Even card", "Volume", "Impact", "10–9", "10–10", "TOTAL", "ROUND TO ALICE", "BOB"]:
		check(_label_with(rp, t) != null, "scorecard shows '%s'" % t)
	check(rp.find_children("*", "TeamChip", true, false).size() >= 2, "team letters beside the names")
	var r := rp.get_global_rect()
	var view := hud.get_global_rect()
	check(r.end.y <= hud._sub.get_global_rect().position.y + 1.0, "above the subtitles (%s)" % str(r))
	check(r.position.y >= hud._center.get_global_rect().end.y - 1.0, "below the centre callout (%s)" % str(r))
	check(r.position.x >= view.position.x and r.end.x <= view.end.x, "on screen horizontally")
	_text_at_least(rp, 28, "round scorecard")
	# it stays through the break and leaves when the next round fights
	hud._process(0.0)
	check(is_instance_valid(rp) and hud._round_panel == rp, "still up during ROUND_END")
	mirror.update(_sample(hs, {"mode": "standard"}, MatchMode.Phase.FIGHT, 1), 1.0 / 60.0)
	hud._round_panel_shown -= FightHud.ROUND_CARD_MIN + 0.5
	await wait_frames(2)
	check(hud._round_panel == null, "gone once the next round fights")
	# an even round
	hud.show_round_card(_round_ev(2, [[10, 10], [10, 10], [10, 10]], [[20, 19], [20, 19], [20, 20]], -1))
	await wait_frames(2)
	check(_label_with(hud._round_panel, "EVEN ROUND") != null, "an even round says so")
	# the decision replaces it: winner (B) first in the totals
	hud.show_decision({"type": "judges_decision", "winner": 1, "method": "Split Decision", "totals": [[29, 28], [28, 29], [28, 29]],
		"judges": [0, 1, 1], "teams": [0, 1]}, 3)
	await wait_frames(3)
	check(hud._round_panel == null, "the decision banner replaces the round card")
	var b := hud._banner
	check(b != null and b.is_visible_in_tree(), "decision banner shown")
	for t in ["THE JUDGES' DECISION", "BOB WINS", "SPLIT DECISION", "CARDS   28–29 · 29–28 · 29–28"]:
		check(_label_with(b, t) != null, "banner shows '%s'" % t)
	var br := b.get_global_rect()
	check(br.end.y <= hud._sub.get_global_rect().position.y + 1.0 and br.position.y >= hud._center.get_global_rect().end.y - 1.0,
		"banner between the callout and the subtitles (%s)" % str(br))
	_text_at_least(b, 28, "decision banner")
	# T.K.O. and draws
	hud.show_decision({"winner": 0, "method": "TKO", "totals": [[19, 18], [19, 18], [20, 17]], "teams": [0, 1]}, 2)
	await wait_frames(2)
	for t in ["THE REFEREE STOPS IT", "ALICE WINS", "T.K.O. · ROUND 2", "CARDS AT THE STOPPAGE"]:
		check(_label_with(hud._banner, t) != null, "T.K.O. banner shows '%s'" % t)
	hud.show_decision({"winner": -1, "method": "Split Draw", "totals": [[29, 28], [28, 29], [29, 29]], "teams": [0, 1]}, 3)
	await wait_frames(2)
	for t in ["THE CARDS ARE LEVEL", "DRAW", "SPLIT DRAW", "29–28 · 28–29 · 29–29", "ALICE", "BOB"]:
		check(_label_with(hud._banner, t) != null, "draw banner shows '%s'" % t)
	# drawn cards with sudden death on: the banner clears for the fight
	mirror.update(_sample({"cards": {"n": 3, "t": [[29, 28], [28, 29], [29, 29]]}, "sd": true}, {"mode": "standard"}, MatchMode.Phase.FIGHT, 2), 1.0 / 60.0)
	hud._banner_shown -= FightHud.DRAW_TO_SD_SECONDS + 0.2
	await wait_frames(2)
	check(hud._banner == null, "a drawn decision's banner leaves for the sudden death")
	# callouts
	check_eq(FightHud.decision_callout({"method": "Split Decision", "winner": 0}), "SPLIT DECISION")
	check_eq(FightHud.decision_callout({"method": "TKO", "winner": 0}), "T.K.O.!")
	check_eq(FightHud.decision_callout({"method": "Majority Draw", "winner": -1}), "DRAW")
	check_eq(FightHud.decision_callout({"method": "Sudden Death (after a Split Draw)", "winner": 1}, "BOB"), "BOB WINS!")
	check_eq(FightHud.totals_text([[30, 27], [29, 28]], [0, 1], 1), "27–30 · 28–29", "winner-first reading")
	await _free_hud(hud)
	mirror.free_all()


# ---- match scenes -----------------------------------------------------------------------------

## rules: a preset id or a rules dictionary (App.resolve_match_config resolves both).
func _scene(rules, sources := [null, null]) -> MatchScene:
	var cfg := App.resolve_match_config({"arena": "the_gullet", "rules": rules, "seed": 5, "fighters": [
		{"creature": "f_stoke", "team": 0, "kind": "scripted", "source": sources[0], "name": "Stoke"},
		{"creature": "f_dredge", "team": 1, "kind": "scripted", "source": sources[1], "name": "Dredge"}]})
	var scene := MatchScene.new()
	add_child(scene)
	scene.start(cfg)
	return scene


func test_match_scene_referee_framing_and_ten_point_callouts() -> void:
	var scene := _scene(_rules(CAGE, {"rounds": 2}), [_attacker(), null])
	await wait_frames(2)
	check(scene.sim.mode.has_referee(), "the sim runs a referee")
	var rv := scene.referee_view
	check(rv != null and rv.get_parent() == scene, "RefereeView spawned beside the ModeView")
	if rv == null:
		scene.queue_free()
		return
	check(not scene.mode_view.is_ancestor_of(rv), "never under ModeView")
	check_eq(scene.find_children("*", "RefereeView", true, false).size(), 1, "exactly one referee")
	await wait_frames(30)
	var rpos: Vector3 = rv.debug_state()["pos"]
	check(scene.sim.arena.clamp_point(rpos, 0.3).distance_to(rpos) < 0.01, "he stands on the floor (%s)" % rpos)
	var pts: Array = scene._camera_points()
	check_eq(pts.size(), 2, "camera frames the two fighters only")
	for p in pts:
		var pv: Vector3 = p
		check(Vector2(pv.x, pv.z).distance_to(Vector2(rpos.x, rpos.z)) > 0.05, "the referee is not a camera point")
	# the real match: round 1's card, then the decision (and no round callout over it)
	check(await _until(func() -> bool: return scene.hud._round_panel != null, 12.0), "the round 1 scorecard appears after the bell")
	check(_label_with(scene.hud._round_panel, "ROUND 1") != null, "for round 1")
	check(await _until(func() -> bool: return not scene.sim.mode.decision.is_empty(), 15.0), "the cards decide")
	await wait_frames(2)
	var d: Dictionary = scene.sim.mode.decision
	var w := int(d.get("winner", -1))
	check(scene.hud._banner != null, "decision banner up")
	var want := FightHud.decision_callout(d, scene._team_label(w) if w >= 0 else "")
	check_eq(scene.hud._center.text, want, "the decision callout stays after the final round_end")
	check(not scene.hud._center.text.contains("WINS THE ROUND"), "no round-winner claim for the decided round")
	# referee view state keeps updating through the bout end (view only)
	await wait_frames(20)
	check(is_instance_valid(rv) and str(rv.debug_state()["mode"]) != "", "referee still directed: %s" % str(rv.debug_state()["mode"]))
	# event handling straight through _on_event (both shapes of "decision" are safe)
	var hud := scene.hud
	scene._on_event({"type": "round_end", "winner": -1, "round": 7})
	check_eq(hud._center.text, "EVEN ROUND", "10-point level round")
	scene._on_event({"type": "round_end", "winner": 0, "round": 8})
	check_eq(hud._center.text, "STOKE WINS THE ROUND", "10-point card winner of a round")
	scene._on_event({"type": "ref_stoppage", "fighter": 1, "by": 0, "reason": "knockdowns", "round": 9})
	scene._on_event({"type": "round_end", "winner": 0, "round": 9})
	check_eq(hud._center.text, "T.K.O.!", "the stoppage callout stays over its round_end")
	scene._on_event({"type": "ref_count", "fighter": 1, "n": 2})
	scene._on_event({"type": "ref_wave_up", "fighter": 1})
	scene._on_event({"type": "decision", "party": 0.4, "enemy": 0.3})   # the campaign's own event: ignored here
	check_eq(hud._center.text, "T.K.O.!", "a campaign 'decision' event changes nothing")
	scene.queue_free()
	await wait_frames(2)
	# a plain duel: no referee, round callouts unchanged
	var plain := _scene(_rules(DUEL))
	await wait_frames(2)
	check(plain.referee_view == null and plain.find_children("*", "RefereeView", true, false).is_empty(), "no referee in a plain duel")
	plain._on_event({"type": "round_end", "winner": -1, "round": 1})
	check_eq(plain.hud._center.text, "DRAW", "HP scoring level round")
	plain._on_event({"type": "round_end", "winner": 1, "round": 2})
	check_eq(plain.hud._center.text, "DREDGE WINS THE ROUND", "HP scoring round winner")
	plain._on_event({"type": "decision", "party": 0.4, "enemy": 0.3})
	plain.queue_free()
	await wait_frames(2)
	# the built-in presets: Cage Rules has the referee and the cards, the plain duel neither
	for pid in ["cage_rules", "duel"]:
		var ps := _scene(pid)
		await wait_frames(3)
		var cage: bool = pid == "cage_rules"
		check_eq(ps.referee_view != null, cage, "%s: referee view" % pid)
		check_eq(ps.hud.is_ten_point(), cage, "%s: 10-point HUD" % pid)
		check_eq((ps.hud.cards[0]["hp_stack"] as Control).visible, not cage, "%s: HP bars" % pid)
		ps.queue_free()
		await wait_frames(2)


func test_net_scene_referee_cards_and_decision_from_replicated_data() -> void:
	var arena := Content.arena("the_gullet")
	for ref in [true, false]:
		var rep := _replica()
		var rules := _rules(CAGE) if ref else _rules(DUEL)
		var info := {"rules": rules, "mode": "standard", "you": 0, "arena": arena.to_dict(), "_arena_def": arena, "match_id": 3}
		check_eq(NetMatchScene.has_referee(info), ref, "the client's referee gate (%s)" % ref)
		var scene := NetMatchScene.new()
		add_child(scene)
		var err := scene.start(info, rep)
		check_eq(err, "", "client scene starts")
		if not ref:
			check(scene.referee_view == null, "no referee without one in the replicated rules")
			scene.queue_free()
			await wait_frames(2)
			continue
		check(scene.referee_view != null and scene.referee_view.get_parent() == scene, "client spawns the referee beside ModeView")
		var hs := {"cards": {"n": 1, "t": [[10, 9], [10, 9], [10, 9]]}}
		var view := {"mode": "standard", "referee": {"count": {"fighter": 1, "n": 2, "left": 2.0}}}
		rep.add_snapshot(120, _sample(hs, view, MatchMode.Phase.FIGHT, 1, 1), 10.0)
		rep.add_snapshot(124, _sample(hs, view, MatchMode.Phase.FIGHT, 1, 1), 10.033)
		rep.render_time = 122.0 / 120.0
		rep.add_events([{"type": "ref_count", "fighter": 1, "n": 2, "tick": 121},
			_round_ev(1, [[10, 9], [10, 9], [10, 9]], [[10, 9], [10, 9], [10, 9]], 0).merged({"tick": 121})])
		await wait_frames(4)
		var hud := scene.hud
		check(hud.is_ten_point(), "client HUD on 10-point from hud_state")
		check(not (hud.cards[0]["hp_stack"] as Control).visible, "client: HP hidden")
		check_eq((hud.cards[1]["status"] as Label).text, "DOWN · 2", "client: the count on the downed card")
		check(hud._round_panel != null, "client: round_scored shows the scorecard")
		var rpos: Vector3 = scene.referee_view.debug_state()["pos"]
		check(arena.clamp_point(rpos, 0.3).distance_to(rpos) < 0.01, "client referee on the floor (%s)" % rpos)
		check_eq(scene._camera_points().size(), 2, "client camera frames the fighters only")
		# the final bell, in the sim's order: round_scored, judges_decision, round_end (its callout is not replaced)
		rep.add_events([_round_ev(3, [[10, 9], [10, 9], [9, 10]], [[30, 27], [30, 27], [29, 28]], 0).merged({"tick": 123}),
			{"type": "judges_decision", "winner": 0, "method": "Unanimous Decision", "totals": [[30, 27], [30, 27], [29, 28]],
			"judges": [0, 0, 0], "teams": [0, 1], "tick": 123}, {"type": "round_end", "winner": 0, "round": 3, "tick": 123}])
		rep.add_snapshot(128, _sample(hs, {"mode": "standard"}, MatchMode.Phase.ROUND_END, 2), 10.066)
		rep.render_time = 123.5 / 120.0
		await wait_frames(4)
		check(hud._banner != null and _label_with(hud._banner, "ALICE WINS") != null, "client decision banner")
		check_eq(hud._center.text, "UNANIMOUS DECISION", "client decision callout kept over round_end")
		scene.queue_free()
		await wait_frames(2)


# ---- results ------------------------------------------------------------------------------------

func _card(rn: int, judges: Array, stoppage := false) -> Dictionary:
	var ta := RoundJudge.empty_tally()
	ta["landed"] = 14 + rn
	ta["damage"] = 150.0 + rn * 3.0
	ta["knockdowns"] = 1
	ta["parries"] = 1
	var tb := RoundJudge.empty_tally()
	tb["landed"] = 9 + rn
	tb["damage"] = 120.0
	var sc := RoundJudge.score_tallies(ta, tb)
	return {"round": rn, "teams": [0, 1], "judges": judges, "scores": sc["scores"], "tally": [RoundJudge.plain_tally(ta), RoundJudge.plain_tally(tb)],
		"winner": -1, "stoppage": stoppage}


func _scoring(cards: Array, method: String, winner: int, stoppage := {}, sd := false) -> Dictionary:
	return {"mode": "ten_point", "method": method, "winner": winner, "teams": [0, 1], "cards": cards, "totals": RoundJudge.totals_of(cards),
		"judges": RoundJudge.JUDGE_NAMES.duplicate(), "stoppage": stoppage, "sudden_death": sd}


func _result(sc: Dictionary, winner: int) -> Dictionary:
	var r := {"mode": "standard", "winner_team": winner, "round_wins": {0: 1, 1: 1}, "scores": {0: 0.0, 1: 0.0},
		"rounds": (sc.get("cards", []) as Array).size() if not sc.is_empty() else 3, "time": 312.0, "fighters": [
		{"index": 0, "team": 0, "creature": "f_stoke", "name": "Stoke", "health": 340.0, "out": false, "kind": "player",
			"stats": {"damage_dealt": 480.0, "damage_taken": 360.0, "hits": 44, "blocks": 6, "parries": 3, "knockdowns": 3, "kos": 0}},
		{"index": 1, "team": 1, "creature": "f_dredge", "name": "Dredge", "health": 420.0, "out": false, "kind": "bot",
			"stats": {"damage_dealt": 360.0, "damage_taken": 480.0, "hits": 31, "blocks": 9, "parries": 1, "knockdowns": 1, "kos": 0}}]}
	if not sc.is_empty():
		r["scoring"] = sc
	return r


func _results_cases() -> Array:
	var ud := [_card(1, [[10, 9], [10, 9], [10, 9]]), _card(2, [[10, 9], [10, 9], [10, 9]])]
	var five := []
	for i in 5:
		var a := i < 3
		five.append(_card(i + 1, [[10, 9] if a else [9, 10], [9, 10] if a else [10, 9], [9, 10] if a else [10, 9]]))
	var tko := [_card(1, [[10, 9], [10, 9], [10, 9]]), _card(2, [[10, 8], [10, 8], [10, 8]], true)]
	var draw := [_card(1, [[10, 9], [9, 10], [10, 10]]), _card(2, [[9, 10], [10, 9], [9, 10]]), _card(3, [[10, 9], [9, 10], [10, 9]])]
	check_eq(str(RoundJudge.decide_cards(ud)["method"]), "Unanimous Decision", "fixture: unanimous")
	check_eq(str(RoundJudge.decide_cards(five)["method"]), "Split Decision", "fixture: split")
	check_eq(int(RoundJudge.decide_cards(five)["winner_slot"]), 1, "fixture: split for B")
	check_eq(str(RoundJudge.decide_cards(draw)["method"]), "Split Draw", "fixture: split draw")
	var stop := {"fighter": 1, "by": 0, "round": 2, "time": 94, "reason": "knockdowns"}
	return [
		["2-round decision", _result(_scoring(ud, "Unanimous Decision", 0), 0), "UNANIMOUS DECISION · 20–18 · 20–18 · 20–18", ["Went the distance"]],
		["5-round split", _result(_scoring(five, "Split Decision", 1), 1), "SPLIT DECISION · 47–48 · 48–47 · 48–47", ["Went the distance"]],
		["T.K.O.", _result(_scoring(tko, "TKO", 0, stop), 0), "T.K.O. · ROUND 2 · 1:34", ["Stopped (T.K.O.)", "Went the distance"]],
		["split draw", _result(_scoring(draw, "Split Draw", -1), -1), "SPLIT DRAW · 29–28 · 28–29 · 29–29", ["Went the distance"]],
		["sudden death", _result(_scoring(draw, "Sudden Death (after a Split Draw)", 0, {}, true), 0), "SUDDEN DEATH (AFTER A SPLIT DRAW)", []],
	]


func test_results_show_method_cards_and_fit() -> void:
	await wait_frames(2)
	UiNav.ensure()
	var root := get_tree().root
	var old := root.size
	var cases := _results_cases()
	for res in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = res
		await wait_frames(3)
		var vr := get_viewport().get_visible_rect()
		var px_per_du := get_viewport().get_final_transform().get_scale().y
		for cs in cases:
			var tag := "%s@%dx%d" % [str(cs[0]), res.x, res.y]
			App.push("results", {"result": cs[1], "config": {"fighters": [{"kind": "player", "team": 0}], "ui": {"mode": "versus"}}})
			await wait_frames(4)
			var s := App.top_screen()
			_audit(s, tag, vr, px_per_du)
			check(_label_with(s, str(cs[2])) != null, "%s: method line '%s'" % [tag, str(cs[2])])
			var sc: ScorecardPanel = s.get("scorecard")
			var scroll: ScrollContainer = s.get("_scroll")
			check(sc != null and scroll != null and scroll.is_ancestor_of(sc), "%s: scorecards inside the scroll area" % tag)
			check(s.call("right_stick_scroll_target") == scroll, "%s: the right stick scrolls the cards" % tag)
			if sc != null:
				var r := sc.get_global_rect()
				check(r.position.x >= vr.position.x - 1.0 and r.end.x <= vr.end.x + 1.0, "%s: scorecards fit across (%s)" % [tag, str(r)])
				check(_label_with(sc, "STOKE") != null and _label_with(sc, "DREDGE") != null, "%s: names aligned with the teams" % tag)
				check(_label_with(sc, "Even card") != null and _label_with(sc, "Strikes landed") != null, "%s: judges and tally" % tag)
			for cap in cs[3]:
				check(_label_with(s, str(cap)) != null, "%s: caption '%s'" % [tag, str(cap)])
			check(_label_with(s, "HP left") == null, "%s: no HP captions under 10-point" % tag)
			var focus := get_viewport().gui_get_focus_owner()
			check(focus != null and vr.encloses(focus.get_global_rect()), "%s: focused button on screen" % tag)
			App.pop()
			await wait_frames(2)
	root.size = old
	await wait_frames(2)


func test_results_without_scoring_are_unchanged() -> void:
	await wait_frames(2)
	UiNav.ensure()
	var plain := _result({}, 1)
	App.push("results", {"result": plain, "config": {"fighters": [{"kind": "player", "team": 0}], "ui": {"mode": "quick"}}})
	await wait_frames(4)
	var s := App.top_screen()
	check(_label_with(s, "Rounds") != null and _label_with(s, "HP left") != null, "plain score line and HP captions")
	check(s.get("scorecard") == null and s.find_children("*", "ScorecardPanel", true, false).is_empty(), "no scorecards")
	check(s.call("right_stick_scroll_target") == null, "right stick as before")
	check(_label_with(s, "T.K.O.") == null, "no T.K.O. without a referee stoppage")
	App.pop()
	await wait_frames(2)
	# Health scoring with a referee who stopped round 2
	var refd := _result({}, 0)
	refd["referee"] = {"stoppages": [{"fighter": 1, "by": 0, "round": 2, "time": 40.5, "reason": "knockdowns"}]}
	App.push("results", {"result": refd, "config": {"fighters": [{"kind": "player", "team": 0}]}})
	await wait_frames(4)
	s = App.top_screen()
	check(_label_with(s, "T.K.O. · ROUND 2") != null, "the referee's stoppage is named on the score line")
	check(_label_with(s, "Rounds") != null and _label_with(s, "HP left") != null, "otherwise the HP results")
	App.pop()
	await wait_frames(2)


## Layout audit (UI-10), as test_ui_navigation's: footer prompts on screen, a prompt bar, every
## visible text >= 18 px.
func _audit(s: Screen, tag: String, vr: Rect2, px_per_du: float) -> void:
	if not check(s != null, "%s: screen open" % tag):
		return
	var bars := 0
	for b in s.find_children("*", "PromptBar", true, false):
		var bar := b as Control
		if not bar.is_visible_in_tree():
			continue
		bars += 1
		var r := bar.get_global_rect()
		check(r.end.y <= vr.end.y + 1.0 and r.position.y >= vr.position.y - 1.0 and r.end.x <= vr.end.x + 1.0,
			"%s: footer prompts on screen (bar %s, view %s)" % [tag, str(r), str(vr.size)])
	check(bars > 0, "%s: has a prompt bar" % tag)
	var smallest := 999.0
	var smallest_text := ""
	for n in s.find_children("*", "", true, false):
		var size_du := 0
		var text := ""
		if n is Label and (n as Label).is_visible_in_tree():
			text = (n as Label).text
			size_du = (n as Label).get_theme_font_size("font_size")
		elif n is Button and (n as Button).is_visible_in_tree():
			text = (n as Button).text
			size_du = (n as Button).get_theme_font_size("font_size")
		if text.strip_edges() == "":
			continue
		var px := size_du * px_per_du
		if px < smallest:
			smallest = px
			smallest_text = text
	check(smallest >= 18.0 - 0.01, "%s: smallest text '%s' is %.1f px (< 18 px)" % [tag, smallest_text.substr(0, 30), smallest])
