class_name CareerState
extends RefCounted
## The persistent Career save (CMP-08): ONE JSON-safe Dictionary, written as-is by CareerStore
## (Saves kind "career", VERSION). Pure functions only; CareerController is the only writer.
##
## {
##   "version": 1, "career_id": "car_<seed text>_<created_at>", "seed": 53-bit int, "seed_text",
##   "created_at": unix int, "profile_id", "slot": 1..3, "content_hash",
##   "name" (<= 14), "nick" (<= 16), "fighter": roster creature id, "difficulty": easy|normal|hard,
##   "stats": {stamina, chin, speed, power, clinch, defence} in 0..stat_cap,
##   "week": >= 1, "money": int >= 0, "pop": 0..100 (one decimal),
##   "record": {"w", "l", "d", "tko", "dec"}, "streak": +n wins / -n losses / 0,
##   "gym": {stamina..defence, recovery, coach: 0..facility_max},
##   "injury": {"head", "body", "legs": 0..100},
##   "booked": {} | {"offer": offer, "weeks_left": n, "plan": [focus...], "in_fight": bool,
##               "accepted_week": w, "starts": n (fight launches, crash re-fights included)},
##   "offers": [offer...], "offer_roll": n (re-rolls within the current week),
##   "history": [entry...] (oldest first), "log": [{"week", "text"}] (<= news_cap, oldest first),
##   "champion": bool, "title_defences": n, "claims": [fight ids applied or withdrawn],
##   "last_fight": {} | result summary, "last_train": {} | train report,
##   "saved_at": unix int (stamped by CareerStore.save; absent until the first save)
## }
## Invariants (check()): every stat in 0..1, injuries 0..100, money >= 0, a booked fight is not
## also offered, weeks_left >= 0, an in-fight marker only on a booked fight whose id is unclaimed.
## Content references (the career fighter, offer/booked creatures and arenas) are reported as
## "missing ..." problems; only a missing career fighter blocks loading (design contract D9).

const VERSION := 1
const REQUIRED := ["version", "career_id", "seed", "name", "fighter", "difficulty", "stats", "week", "money", "pop",
	"record", "streak", "gym", "injury", "booked", "offers", "history", "log", "champion", "title_defences", "claims"]


## A fresh career dict (no offers yet: CareerController.create rolls them). opts: {name, nick,
## fighter, difficulty, seed (0 = fresh), created_at, profile_id, slot, content_hash}.
static func create(rules: Dictionary, opts: Dictionary) -> Dictionary:
	var seed_value := int(opts.get("seed", 0))
	seed_value = RunRng.normalize_seed(seed_value) if seed_value != 0 else RunRng.fresh_seed()
	var created := int(opts.get("created_at", int(Time.get_unix_time_from_system())))
	var fighter := str(opts.get("fighter", ""))
	var start: Dictionary = rules.get("start", {})
	var gym := {}
	for k in CareerDefaults.STATS + CareerDefaults.FACILITY_EXTRA:
		gym[k] = 0
	var diff := str(opts.get("difficulty", rules.get("difficulty_default", "normal")))
	if not (rules.get("difficulties", {}) as Dictionary).has(diff):
		diff = str(rules.get("difficulty_default", "normal"))
	var text := RunRng.seed_to_text(seed_value)
	return {
		"version": VERSION,
		"career_id": "car_%s_%d" % [text.replace("-", ""), created],
		"seed": seed_value, "seed_text": text, "created_at": created,
		"profile_id": str(opts.get("profile_id", "")), "slot": int(opts.get("slot", 1)),
		"content_hash": str(opts.get("content_hash", "")),
		"name": clean_name(str(opts.get("name", "")), int(rules.get("name_max", 14)), "You"),
		"nick": clean_name(str(opts.get("nick", "")), int(rules.get("nick_max", 16)), ""),
		"fighter": fighter, "difficulty": diff,
		"stats": starting_stats(rules, fighter),
		"week": int(start.get("week", 1)), "money": int(start.get("money", 2000)), "pop": float(start.get("pop", 2.0)),
		"record": {"w": 0, "l": 0, "d": 0, "tko": 0, "dec": 0}, "streak": 0,
		"gym": gym, "injury": {"head": 0.0, "body": 0.0, "legs": 0.0},
		"booked": {}, "offers": [], "offer_roll": 0, "history": [], "log": [],
		"champion": false, "title_defences": 0, "claims": [], "last_fight": {}, "last_train": {},
	}


## Trimmed text of at most `max_len` characters (Cage Rules: name 14, nickname 16).
static func clean_name(s: String, max_len: int, fallback: String) -> String:
	var t := s.strip_edges().replace("\n", " ").replace("\t", " ")
	t = t.substr(0, max_len).strip_edges()
	return t if t != "" else fallback


## The fighter's stat shape (Cage Rules ROSTER stats): content table, else the default shape.
static func shape(rules: Dictionary, fighter: String) -> Dictionary:
	var sh: Dictionary = (rules.get("fighters", {}) as Dictionary).get(fighter, {})
	var out := {}
	for k in CareerDefaults.STATS:
		out[k] = float(sh.get(k, rules.get("default_shape", 0.66)))
	return out


## Cage Rules startingStats: round(base + shape x scale, 2) per stat.
static func starting_stats(rules: Dictionary, fighter: String) -> Dictionary:
	var sh := shape(rules, fighter)
	var sf: Dictionary = rules.get("start_from_shape", {})
	var out := {}
	for k in CareerDefaults.STATS:
		out[k] = snappedf(float(sf.get("base", 0.16)) + float(sh[k]) * float(sf.get("scale", 0.36)), 0.01)
	return out


## Cage Rules rating: round(mean of the six stats x 100).
static func rating(stats: Dictionary) -> int:
	var t := 0.0
	for k in CareerDefaults.STATS:
		t += float(stats.get(k, 0.0))
	return int(round(t / CareerDefaults.STATS.size() * 100.0))


static func injury_total(st: Dictionary) -> float:
	var t := 0.0
	for r in CareerDefaults.REGIONS:
		t += float(st.get("injury", {}).get(r, 0.0))
	return t


## "Year Y · Week W" (52-week years, never ends).
static func week_label(w: int) -> String:
	var ww := maxi(1, w)
	return "Year %d · Week %d" % [int((ww - 1) / 52.0) + 1, ((ww - 1) % 52) + 1]


## Highest tier among the orgs whose popularity gate `pop` meets (Cage Rules tierFor).
static func tier_for(rules: Dictionary, pop: float) -> int:
	var t := 0
	for o in rules.get("orgs", []):
		if pop >= float(o.get("pop", 0)):
			t = maxi(t, int(o.get("tier", 0)))
	return t


static func tier_name(rules: Dictionary, tier: int) -> String:
	var names: Array = rules.get("tiers", [])
	return str(names[clampi(tier, 0, names.size() - 1)]) if not names.is_empty() else "Tier %d" % tier


static func pop_label(rules: Dictionary, pop: float) -> String:
	for e in rules.get("pop_labels", []):
		if pop >= float(e.get("min", 0)):
			return str(e.get("label", ""))
	return ""


static func record_text(rec: Dictionary) -> String:
	var t := "%d-%d" % [int(rec.get("w", 0)), int(rec.get("l", 0))]
	if int(rec.get("d", 0)) > 0:
		t += "-%d" % int(rec.get("d", 0))
	return t


static func org(rules: Dictionary, id: String) -> Dictionary:
	for o in rules.get("orgs", []):
		if str(o.get("id", "")) == id:
			return o
	return {}


## The promotion that holds the only belt (rules.belt_org, else the last org).
static func belt_org(rules: Dictionary) -> Dictionary:
	var o := org(rules, str(rules.get("belt_org", "")))
	if o.is_empty():
		var orgs: Array = rules.get("orgs", [])
		return orgs[orgs.size() - 1] if not orgs.is_empty() else {}
	return o


# ---------------------------------------------------------------------------------------------
# Invariants and content references
# ---------------------------------------------------------------------------------------------

## Content ids the career needs that are not installed: {"fighter": [ids], "offers": [ids],
## "booked": [ids]} (creatures and arenas; offers/booked ids are "creature:<id>" / "arena:<id>").
static func missing_content(catalog: CampaignCatalog, st: Dictionary) -> Dictionary:
	var out := {"fighter": [], "offers": [], "booked": []}
	if catalog == null:
		return out
	var f := str(st.get("fighter", ""))
	if not creature_ok(catalog, f):
		out["fighter"].append(f)
	for o in st.get("offers", []):
		if typeof(o) == TYPE_DICTIONARY:
			for m in offer_missing(catalog, o):
				if not (out["offers"] as Array).has(m):
					out["offers"].append(m)
	var b = st.get("booked", {})
	if typeof(b) == TYPE_DICTIONARY and not (b as Dictionary).is_empty():
		out["booked"] = offer_missing(catalog, (b as Dictionary).get("offer", {}))
	return out


## True when a career creature (the career fighter or an opponent) can be built: real content, or
## a campaign roster fighter while a stand-in is configured (tests, dev runs). A stand-in never
## covers an id outside the roster, so removed mod fighters are reported in every catalog.
static func creature_ok(catalog: CampaignCatalog, id: String) -> bool:
	if id == "":
		return false
	if catalog.resolver.exists(id):
		return true
	return catalog.resolver.stand_in != "" and (catalog.rules.get("roster", {}) as Dictionary).has(id)


## Missing content of one offer: ["creature:<id>", "arena:<id>"].
static func offer_missing(catalog: CampaignCatalog, offer) -> Array:
	var out := []
	if typeof(offer) != TYPE_DICTIONARY:
		return out
	var opp: Dictionary = (offer as Dictionary).get("opp", {})
	var c := str(opp.get("fighter", ""))
	if not creature_ok(catalog, c):
		out.append("creature:%s" % c)
	var a := str((offer as Dictionary).get("arena", ""))
	if a != "" and catalog.content != null and catalog.content.has_method("get_entry") and catalog.content.get_entry("arenas", a).is_empty():
		out.append("arena:%s" % a)
	return out


## Invariant problems ([] = valid). "missing ..." entries name content that is not installed.
static func check(catalog: CampaignCatalog, st: Dictionary) -> Array:
	var p := []
	if int(st.get("version", -1)) != VERSION:
		p.append("version %s is not %d" % [str(st.get("version", "?")), VERSION])
		return p
	for k in REQUIRED:
		if not st.has(k):
			p.append("missing key '%s'" % k)
	if not p.is_empty():
		return p
	for k in ["stats", "record", "gym", "injury", "booked"]:
		if typeof(st[k]) != TYPE_DICTIONARY:
			p.append("'%s' is not an object" % k)
	for k2 in ["offers", "history", "log", "claims"]:
		if typeof(st[k2]) != TYPE_ARRAY:
			p.append("'%s' is not a list" % k2)
	if not p.is_empty():
		return p
	for s in CareerDefaults.STATS:
		var v = st["stats"].get(s)
		if not (typeof(v) in [TYPE_INT, TYPE_FLOAT]) or float(v) < 0.0 or float(v) > 1.0:
			p.append("stat %s out of range" % s)
	for r in CareerDefaults.REGIONS:
		var iv = st["injury"].get(r)
		if not (typeof(iv) in [TYPE_INT, TYPE_FLOAT]) or float(iv) < 0.0 or float(iv) > 100.0:
			p.append("injury %s out of range" % r)
	if int(st["week"]) < 1:
		p.append("week before week 1")
	if int(st["money"]) < 0:
		p.append("negative money")
	if float(st["pop"]) < 0.0 or float(st["pop"]) > 100.0:
		p.append("popularity out of range")
	for rk in ["w", "l", "d", "tko", "dec"]:
		if int(st["record"].get(rk, -1)) < 0:
			p.append("record %s invalid" % rk)
	for g in CareerDefaults.STATS + CareerDefaults.FACILITY_EXTRA:
		if int(st["gym"].get(g, -1)) < 0 or int(st["gym"].get(g, -1)) > 9:
			p.append("gym %s level invalid" % g)
	var b: Dictionary = st["booked"]
	if not b.is_empty():
		var o = b.get("offer")
		if typeof(o) != TYPE_DICTIONARY or str((o as Dictionary).get("id", "")) == "":
			p.append("booked fight without an offer")
		else:
			var fid := str((o as Dictionary).get("id", ""))
			if int(b.get("weeks_left", -1)) < 0:
				p.append("booked fight weeks_left invalid")
			if (st["claims"] as Array).has(fid):
				p.append("booked fight %s was already settled" % fid)
			for o2 in st["offers"]:
				if typeof(o2) == TYPE_DICTIONARY and str(o2.get("id", "")) == fid:
					p.append("booked fight is still offered")
	for o3 in st["offers"]:
		if typeof(o3) != TYPE_DICTIONARY or str(o3.get("id", "")) == "" or typeof(o3.get("opp")) != TYPE_DICTIONARY:
			p.append("malformed offer")
	var miss := missing_content(catalog, st)
	for m in miss["fighter"]:
		p.append("missing fighter '%s'" % m)
	for m2 in miss["offers"]:
		p.append("missing offer %s" % m2)
	for m3 in miss["booked"]:
		p.append("missing booked %s" % m3)
	return p


## Problems that make a save unusable: everything except stale offers and a booked fight with
## missing content (both are repairable in play, design contract D9).
static func blocking(problems: Array) -> Array:
	var out := []
	for pr in problems:
		var s := str(pr)
		if s.begins_with("missing offer ") or s.begins_with("missing booked "):
			continue
		out.append(s)
	return out


## Save-format migrations (none yet: VERSION 1 is the first career format). Future versions
## chain here; returning null rejects the file (it stays on disk).
static func migrate(data, from_version: int):
	if typeof(data) != TYPE_DICTIONARY:
		return null
	if from_version == VERSION:
		return data
	return null
