class_name LabEval
extends RefCounted
## Evaluation episodes and honest summaries. Evaluation is separate from training: it uses the
## fixed baseline opponents, seeds from the held-out "val"/"test" streams (never the training
## stream), the deterministic/declared action mode of the policy, and reports every episode's
## aggregate (mean ± std, 95% CI, Wilson interval for win rate) — never a best single episode.


## Items evaluating parameters `key` against each opponent: n episodes with random spawns from
## the `stream` seeds and (optionally) n with the arena's standard spawns (a held-out layout).
static func items(job: Dictionary, key: String, stream: String, opponents: Array, n: int, standard: bool, group: String, start_index: int, mode := "") -> Array:
	var out := []
	var scn: Dictionary = job["scenario"]
	var i := start_index
	var oi := 0
	for opp in opponents:
		for k in n:
			var s := LabScenarios.seed_for(stream, int(job["seed"]), oi * 1000 + k)
			var ep := LabScenarios.episode(scn, str(opp), s, str(job["creature"]), str(job["opponent_creature"]), "random")
			var pol := {"key": key}
			if mode != "":
				pol["mode"] = mode
			out.append({"i": i, "policy": pol, "episode": ep, "group": group})
			i += 1
			if standard:
				var ep2 := LabScenarios.episode(scn, str(opp), s + 1, str(job["creature"]), str(job["opponent_creature"]), "standard" if k % 2 == 0 else "swapped")
				out.append({"i": i, "policy": pol.duplicate(), "episode": ep2, "group": group})
				i += 1
		oi += 1
	return out


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
	return "n=%d reward %.2f ± %.2f (95%% CI %.2f..%.2f) win %.0f%% [%.0f–%.0f%%]" % [int(s.get("n", 0)), float(rw.get("mean", 0.0)),
		float(rw.get("std", 0.0)), float((rw.get("ci95", [0, 0]) as Array)[0]), float((rw.get("ci95", [0, 0]) as Array)[1]),
		100.0 * float(s.get("win_rate", 0.0)), 100.0 * float((s.get("win_ci95", [0, 1]) as Array)[0]), 100.0 * float((s.get("win_ci95", [0, 1]) as Array)[1])]


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
