extends TestCase
## CNT-01 / CNT-02 / CMB-09: every roster fighter has a complete kit, its own element, three build
## directions, and respects the ROSTER.md reach cap: no normal melee weapon point travels beyond
## 1.6 m from the fighter's root (posed reach, without the hit sphere's radius; lunges are visible
## movement and are judged by the kits' own range tests).

const ROSTER := ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters"]
const MOVES := ["l1", "l2", "l3", "heavy", "heavy_charged", "finisher", "dash_attack", "grab", "pummel", "taunt"]
const ABILITIES := ["ability1", "ability2", "juice"]
const REACH_CAP := 1.6


## Posed melee reach of a move: farthest animated effector target or weapon rest point of the
## weapons its hit windows use (0 when the move only acts through effects).
static func melee_reach(c: CreatureDef, m: MoveDef) -> float:
	var r := 0.0
	for k in m.keys:
		for cname in k["chains"]:
			var v = k["chains"][cname]
			if typeof(v) == TYPE_VECTOR3:
				r = maxf(r, (v as Vector3).z)
	for w in m.windows:
		for wn in w["weapons"]:
			var wd: BodyDef.Weapon = c.body.weapons.get(wn)
			if wd:
				var seg: BodyDef.Seg = c.body.segments[wd.seg]
				r = maxf(r, (wd.local + seg.pivot).z)
	return r if not m.windows.is_empty() else 0.0


func test_complete_kits() -> void:
	for id in ROSTER:
		var c := Content.creature(id)
		if not check(c != null and c.is_valid(), "%s parses cleanly %s" % [id, c.errors if c else []]):
			continue
		for slot in MOVES:
			check(c.moves.has(slot), "%s has move %s" % [id, slot])
		for slot in ABILITIES:
			check(c.abilities.has(slot), "%s has ability %s" % [id, slot])
		check(not bool(Content.get_entry("creatures", id).get("npc_only", false)), "%s is selectable" % id)


func test_distinct_elements_and_three_builds() -> void:
	var elements := {}
	for id in ROSTER:
		var e := str(Content.get_entry("creatures", id).get("element", ""))
		check(e != "" and not elements.has(e), "%s has its own element (%s)" % [id, e])
		elements[e] = id
	var builds := {}
	for tid in Content.ids("techniques"):
		var t := Content.get_entry("techniques", str(tid))
		if str(t.get("type", "")) == "build":
			var who := str(t.get("fighter", t.get("creature", "")))
			builds[who] = int(builds.get(who, 0)) + 1
	for id in ROSTER:
		check(int(builds.get(id, 0)) >= 3, "%s has three build directions (%d)" % [id, int(builds.get(id, 0))])


func test_melee_reach_cap() -> void:
	var table := []
	for id in ROSTER:
		var c := Content.creature(id)
		if c == null:
			continue
		for slot in c.moves:
			var m: MoveDef = c.moves[slot]
			var r := melee_reach(c, m)
			table.append("%s.%s %.2f" % [id, slot, r])
			check(r <= REACH_CAP + 0.001, "%s.%s melee reach %.2f m <= %.1f m" % [id, slot, r, REACH_CAP])
	print("melee reach: ", ", ".join(table))
