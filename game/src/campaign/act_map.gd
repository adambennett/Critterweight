class_name ActMap
extends RefCounted
## Static helpers over one act's map Dictionary (the map itself is plain JSON-safe data stored in
## the run save):
##   {"act": 1, "rows": [[node ids of row 1], ..., [boss id]], "nodes": {id: node}, "boss": id}
##   node: {"id", "act", "row" (1..7), "lane", "x" (0..1), "type", "edges": [next-row ids],
##          "encounter", "event", "hidden": {type, encounter, event} (mystery), "treasure": bool}
## Invariants checked by `problems()` (CAMPAIGN.md §2 generator rules): every node has 1–3 forward
## edges (except the boss), edges only go to the next row and never cross, every node is reachable
## from row 1 and reaches the boss, row 1 = fights, row 6 = rest/shop (both present), row 7 = boss,
## per-act guarantees (shop, rest, elite, event, mystery caps, elite rows/adjacency), and the
## pacing limits on every path (fight count, consecutive fights).

const FIGHTLIKE := ["fight", "elite"]


static func node(m: Dictionary, id: String) -> Dictionary:
	return m.get("nodes", {}).get(id, {})


static func row_ids(m: Dictionary, row: int) -> Array:
	var rows: Array = m.get("rows", [])
	if row < 1 or row > rows.size():
		return []
	return rows[row - 1]


static func row_count(m: Dictionary) -> int:
	return (m.get("rows", []) as Array).size()


## Every route from a row-1 node to the boss (arrays of node ids, boss included).
static func all_paths(m: Dictionary) -> Array:
	var out := []
	for start in row_ids(m, 1):
		_walk(m, str(start), [], out)
	return out


static func _walk(m: Dictionary, id: String, acc: Array, out: Array) -> void:
	var p := acc.duplicate()
	p.append(id)
	var n := node(m, id)
	var edges: Array = n.get("edges", [])
	if edges.is_empty():
		out.append(p)
		return
	for e in edges:
		_walk(m, str(e), p, out)


static func reachable_from(m: Dictionary, id: String) -> Dictionary:
	var seen := {}
	var stack := [id]
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		if seen.has(cur):
			continue
		seen[cur] = true
		for e in node(m, cur).get("edges", []):
			stack.append(str(e))
	return seen


## Fight-like nodes on a path between rows 2..5 (the variable part of an act's pacing).
static func path_fights(m: Dictionary, path: Array) -> int:
	var k := 0
	for id in path:
		var n := node(m, str(id))
		var r := int(n.get("row", 0))
		if r >= 2 and r <= 5 and FIGHTLIKE.has(str(n.get("type", ""))):
			k += 1
	return k


static func longest_fight_streak(m: Dictionary, path: Array) -> Array:
	var best := 0
	var cur := 0
	var best_end := -1
	for i in path.size():
		if FIGHTLIKE.has(str(node(m, str(path[i])).get("type", ""))):
			cur += 1
			if cur > best:
				best = cur
				best_end = i
		else:
			cur = 0
	return [best, best_end]


static func count_type(m: Dictionary, t: String) -> int:
	var n := 0
	for id in m.get("nodes", {}):
		if str(m["nodes"][id].get("type", "")) == t:
			n += 1
	return n


## Estimated play time of a path (seconds) with the rules' pacing table.
static func path_seconds(m: Dictionary, path: Array, pacing: Dictionary) -> float:
	var s := 0.0
	for id in path:
		s += float(pacing.get(str(node(m, str(id)).get("type", "fight")), 60.0))
	return s


## Lists every violated invariant (empty = valid). `rules` = catalog.rules.
static func problems(m: Dictionary, rules: Dictionary) -> Array:
	var out := []
	var mr: Dictionary = rules.get("map", {})
	var rows: Array = m.get("rows", [])
	var nrows := int(mr.get("rows", 6)) + 1
	if rows.size() != nrows:
		out.append("expected %d rows, got %d" % [nrows, rows.size()])
		return out
	var act := int(m.get("act", 1))
	var nodes: Dictionary = m.get("nodes", {})
	var boss := str(m.get("boss", ""))
	if not nodes.has(boss) or str(nodes[boss].get("type", "")) != "boss":
		out.append("boss node missing")
		return out
	if (rows[nrows - 1] as Array).size() != 1:
		out.append("boss row must hold exactly one node")
	# structure: lanes, edges (count, next row only, non-crossing), reachability
	for r in range(1, nrows + 1):
		var ids: Array = rows[r - 1]
		if r < nrows and (ids.size() < int(mr.get("lanes_min", 3)) or ids.size() > int(mr.get("lanes_max", 4))):
			out.append("row %d has %d lanes" % [r, ids.size()])
		var last_hi := -1
		for i in ids.size():
			var n: Dictionary = nodes.get(str(ids[i]), {})
			if n.is_empty():
				out.append("row %d references a missing node" % r)
				continue
			if int(n.get("row", 0)) != r or int(n.get("lane", -1)) != i:
				out.append("node %s has inconsistent row/lane" % n.get("id", "?"))
			var edges: Array = n.get("edges", [])
			if r == nrows:
				if not edges.is_empty():
					out.append("boss has forward edges")
				continue
			if edges.size() < 1 or edges.size() > 3:
				out.append("node %s has %d forward edges" % [n.get("id", "?"), edges.size()])
			var next_ids: Array = rows[r]
			var lanes := []
			for e in edges:
				var li := next_ids.find(str(e))
				if li < 0:
					out.append("node %s has an edge outside the next row" % n.get("id", "?"))
				lanes.append(li)
			lanes.sort()
			if not lanes.is_empty():
				if int(lanes[0]) < last_hi:
					out.append("edges from row %d cross" % r)
				last_hi = int(lanes[lanes.size() - 1])
				for k in range(1, lanes.size()):
					if int(lanes[k]) != int(lanes[k - 1]) + 1:
						out.append("node %s has non-contiguous edges" % n.get("id", "?"))
	var from_start := {}
	for s in rows[0]:
		from_start.merge(reachable_from(m, str(s)))
	for id in nodes:
		if not from_start.has(id):
			out.append("node %s is unreachable from row 1" % id)
		if not reachable_from(m, str(id)).has(boss):
			out.append("node %s cannot reach the boss" % id)
	# node types
	for id in rows[0]:
		if str(nodes[str(id)].get("type", "")) != "fight":
			out.append("row 1 must be all fights")
	var r6: Array = rows[nrows - 2]
	var has_rest := false
	var has_shop := false
	for id in r6:
		var t := str(nodes[str(id)].get("type", ""))
		if t == "rest":
			has_rest = true
		elif t == "shop":
			has_shop = true
		else:
			out.append("row %d must be rest or shop" % (nrows - 1))
	if r6.size() >= 2 and not (has_rest and has_shop):
		out.append("last row before the boss needs at least one rest and one shop")
	var elite_rows: Array = mr.get("elite_rows", [3, 4, 5])
	for id in nodes:
		var n2: Dictionary = nodes[id]
		var t2 := str(n2.get("type", ""))
		if not CampaignCatalog.NODE_TYPES.has(t2) or t2 == "treasure":
			out.append("node %s has invalid type '%s'" % [id, t2])
		if t2 == "boss" and str(id) != boss:
			out.append("extra boss node %s" % id)
		if t2 == "elite":
			if not CampaignCatalog.has_num(elite_rows, int(n2.get("row", 0))):
				out.append("elite %s outside elite rows" % id)
			for e2 in n2.get("edges", []):
				if str(nodes.get(str(e2), {}).get("type", "")) == "elite":
					out.append("elites %s and %s are adjacent" % [id, e2])
		if t2 in ["fight", "elite"] and str(n2.get("encounter", "")) == "":
			out.append("fight node %s has no encounter" % id)
		if t2 == "event" and str(n2.get("event", "")) == "":
			out.append("event node %s has no event" % id)
		if t2 == "mystery" and (n2.get("hidden", {}) as Dictionary).is_empty():
			out.append("mystery node %s has no hidden result" % id)
	var counts := {}
	for t3 in CampaignCatalog.NODE_TYPES:
		counts[t3] = count_type(m, t3)
	for need in ["shop", "rest", "elite", "event"]:
		if int(counts[need]) < 1:
			out.append("act %d has no %s" % [act, need])
	if int(counts["elite"]) > int(mr.get("max_elites", 2)):
		out.append("act %d has %d elites" % [act, counts["elite"]])
	if int(counts["mystery"]) > int(mr.get("max_mystery", 2)):
		out.append("act %d has %d mystery nodes" % [act, counts["mystery"]])
	if CampaignCatalog.has_num(mr.get("treasure_acts", [2, 3]), act):
		var treasures := 0
		for id in nodes:
			if bool(nodes[id].get("treasure", false)):
				treasures += 1
		if treasures != 1:
			out.append("act %d needs exactly one hidden treasure (has %d)" % [act, treasures])
	# pacing on every path
	var max_streak := int(mr.get("max_consecutive_fights", 3))
	for p in all_paths(m):
		var k := path_fights(m, p)
		if k < 2 or k > 3:
			out.append("a route has %d fights in rows 2-5" % k)
			break
		var st := longest_fight_streak(m, p)
		if int(st[0]) > max_streak:
			out.append("a route has %d consecutive fights" % st[0])
			break
	return out
