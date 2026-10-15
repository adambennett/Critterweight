class_name LabEval
extends RefCounted
## Evaluation episodes and honest summaries. Evaluation is separate from training: it uses the
## fixed baseline opponents, seeds from the held-out "val"/"test" streams (never the training
## stream), the deterministic/declared action mode of the policy, and reports every episode's
## aggregate (mean ± std, Student-t 95% CI, Wilson interval for win rate) — never a best single
## episode. Every evaluation episode starts differently (random spawns from its own seed, or the
## standard spawns jittered by its seed), so n counts distinct episodes. Conditions compared on
## the same episodes (initial vs trained, policy vs comparison, clone vs teacher) are reported
## with a paired test over those episodes (LabStats.paired).


## Episode conditions for an evaluation: per opponent, n episodes with random spawns from the
## `stream` seeds and (optionally) n with the arena's standard spawns (jittered per seed,
## alternating standard/swapped sides). Every condition is played by every compared group.
static func conditions(job: Dictionary, stream: String, opponents: Array, n: int, standard: bool) -> Array:
	var out := []
	var scn: Dictionary = job["scenario"]
	var oi := 0
	for opp in opponents:
		for k in n:
			var s := LabScenarios.seed_for(stream, int(job["seed"]), oi * 1000 + k)
			out.append(LabScenarios.episode(scn, str(opp), s, str(job["creature"]), str(job["opponent_creature"]), "random"))
			if standard:
				out.append(LabScenarios.episode(scn, str(opp), s + 1, str(job["creature"]), str(job["opponent_creature"]), "standard" if k % 2 == 0 else "swapped"))
		oi += 1
	return out


## Items playing parameters `key` (or, with `learner`, a scripted learner) on the given episode
## conditions, indexed from start_index.
static func items_for(conds: Array, key: String, group: String, start_index: int, mode := "", learner := {}) -> Array:
	var out := []
	var i := start_index
	for ep: Dictionary in conds:
		var pol := {"key": key}
		if mode != "":
			pol["mode"] = mode
		var it := {"i": i, "policy": pol, "episode": ep, "group": group}
		if not learner.is_empty():
			it["learner"] = learner.duplicate()
		out.append(it)
		i += 1
	return out


## Items evaluating parameters `key` against each opponent (see `conditions`).
static func items(job: Dictionary, key: String, stream: String, opponents: Array, n: int, standard: bool, group: String, start_index: int, mode := "") -> Array:
	return items_for(conditions(job, stream, opponents, n, standard), key, group, start_index, mode)


## The same test episodes played by a scripted reference (job.eval.reference, e.g. "jabber"),
## so a trained policy can be compared with a hand-written script on identical conditions.
static func reference_items(job: Dictionary, opponents: Array, n: int, standard: bool, start_index: int) -> Array:
	return reference_items_for(job, conditions(job, "test", opponents, n, standard), start_index)


static func reference_items_for(job: Dictionary, conds: Array, start_index: int) -> Array:
	var kind := str((job["eval"] as Dictionary).get("reference", ""))
	if kind == "" or not LabOpponents.BASELINES.has(kind):
		return []
	return items_for(conds, "none", "reference", start_index, "", {"type": "scripted", "kind": kind})


## Identity of the episode a result was played on (opponent, seed, spawn layout).
static func episode_key(r: Dictionary) -> String:
	return "%s|%d|%s" % [str(r.get("opponent", "")), int(r.get("seed", 0)), str(r.get("spawn", ""))]


## Rewards of two groups on the episodes BOTH completed, aligned by episode: [a, b].
static func paired_rewards(results: Array, weights: Dictionary, group_a: String, group_b: String) -> Array:
	var ra := {}
	var rb := {}
	var order := []
	for r: Dictionary in results:
		if r.has("error"):
			continue
		var g := str(r.get("group", ""))
		if g != group_a and g != group_b:
			continue
		var key := episode_key(r)
		var rw := LabRewards.score(r.get("raw", {}), weights)
		if g == group_a:
			if not ra.has(key):
				order.append(key)
			ra[key] = rw
		else:
			rb[key] = rw
	var a := []
	var b := []
	for key in order:
		if rb.has(key):
			a.append(ra[key])
			b.append(rb[key])
	return [a, b]


## Paired comparison of group_a − group_b on their shared episodes (LabStats.paired), plus labels.
static func compare(results: Array, weights: Dictionary, group_a: String, group_b: String) -> Dictionary:
	var ab := paired_rewards(results, weights, group_a, group_b)
	var p := LabStats.paired(ab[0], ab[1])
	p["a"] = group_a
	p["b"] = group_b
	return p


## Summary of results (optionally filtered to one group) under objective `weights`.
static func summarize(results: Array, weights: Dictionary, group := "") -> Dictionary:
	var by_opp := {}
	var all_rewards := []
	var wins := 0
	var draws := 0
	var n_all := 0
	for r: Dictionary in results:
		if r.has("error") or (group != "" and str(r.get("group", "")) != group):
			continue
		var opp := str(r.get("opponent", "?"))
		if not by_opp.has(opp):
			by_opp[opp] = {"rewards": [], "dealt": [], "taken": [], "hits": [], "wins": 0, "draws": 0, "losses": 0, "kos": 0, "spawns": {}}
		var b: Dictionary = by_opp[opp]
		var raw: Dictionary = r.get("raw", {})
		var rew := LabRewards.score(raw, weights)
		(b["rewards"] as Array).append(rew)
		(b["dealt"] as Array).append(float(raw.get("damage_dealt", 0.0)))
		(b["taken"] as Array).append(float(raw.get("damage_taken", 0.0)))
		(b["hits"] as Array).append(float(raw.get("hits", 0.0)))
		b["kos"] = int(b["kos"]) + int(float(raw.get("ko_dealt", 0.0)))
		var sp := str(r.get("spawn", ""))
		b["spawns"][sp] = int(b["spawns"].get(sp, 0)) + 1
		match str(r.get("outcome", "")):
			"win":
				b["wins"] = int(b["wins"]) + 1
				wins += 1
			"draw":
				b["draws"] = int(b["draws"]) + 1
				draws += 1
			_:
				b["losses"] = int(b["losses"]) + 1
		all_rewards.append(rew)
		n_all += 1
	var per := []
	var keys := by_opp.keys()
	keys.sort()
	for opp in keys:
		var b2: Dictionary = by_opp[opp]
		var n := (b2["rewards"] as Array).size()
		per.append({"opponent": opp, "name": LabOpponents.display_name(str(opp)), "n": n,
			"wins": b2["wins"], "draws": b2["draws"], "losses": b2["losses"],
			"win_rate": float(b2["wins"]) / float(maxi(n, 1)), "win_ci95": LabStats.wilson(int(b2["wins"]), n),
			"reward": LabStats.describe(b2["rewards"]), "damage_dealt": LabStats.describe(b2["dealt"]),
			"damage_taken": LabStats.describe(b2["taken"]), "hits": LabStats.describe(b2["hits"]), "kos": b2["kos"], "spawns": b2["spawns"]})
	return {"n": n_all, "win_rate": float(wins) / float(maxi(n_all, 1)), "win_ci95": LabStats.wilson(wins, n_all),
		"draws": draws, "reward": LabStats.describe(all_rewards), "per_opponent": per}


## Short one-line text for logs/UI.
static func one_line(s: Dictionary) -> String:
	var rw: Dictionary = s.get("reward", {})
	var wc: Array = s.get("win_ci95", [0, 1])
	if wc.size() != 2:
		wc = [0, 1]
	return "n=%d reward %.2f ± %.2f (95%% CI %s) win %.0f%% [%.0f–%.0f%%]" % [int(s.get("n", 0)), float(rw.get("mean", 0.0)),
		float(rw.get("std", 0.0)), LabStats.ci_text(rw.get("ci95", [])), 100.0 * float(s.get("win_rate", 0.0)), 100.0 * float(wc[0]), 100.0 * float(wc[1])]


## One line for a paired comparison (LabEval.compare / LabStats.paired).
static func paired_line(p: Dictionary) -> String:
	if p.is_empty():
		return ""
	return "paired difference %+.2f (95%% CI %s, t = %.2f, n = %d episodes)%s" % [float(p.get("mean", 0.0)), LabStats.ci_text(p.get("ci95", [])),
		float(p.get("t", 0.0)), int(p.get("n", 0)), " — significant" if bool(p.get("significant", false)) else " — not significant"]


## Mean of a raw term across results of a group (e.g. damage_dealt for a quick curve point).
static func mean_term(results: Array, term: String, group := "") -> float:
	var xs := []
	for r: Dictionary in results:
		if r.has("error") or (group != "" and str(r.get("group", "")) != group):
			continue
		xs.append(float((r.get("raw", {}) as Dictionary).get(term, 0.0)))
	return LabStats.mean(xs)


## Sum of action histograms (21 bins) across results.
static func act_hist(results: Array, key := "act_hist", group := "") -> Array:
	var h := []
	h.resize(PolicyActions.OUTPUTS)
	h.fill(0)
	for r: Dictionary in results:
		if group != "" and str(r.get("group", "")) != group:
			continue
		var a: Array = r.get(key, [])
		for k in mini(a.size(), PolicyActions.OUTPUTS):
			h[k] = int(h[k]) + int(a[k])
	return h
