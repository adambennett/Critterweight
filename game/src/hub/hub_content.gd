class_name HubContent
extends RefCounted
## Read access to the hub's data (content/core/hub/*.json, Content kind "hub"): NPCs and their
## lines, secrets, activity tuning and cosmetics, plus line selection with {token} substitution.
## Mods can add/override hub entries like any other content (docs/MODDING.md).

const NPC_KEYS := ["granny", "snappington", "needles", "doc", "kid", "ludlow", "teddy", "barnaby"]
const BOSS_OF_ACT := {1: "Bilge", 2: "Conduit", 3: "Commissioner Snappington"}


static func npc(key: String) -> Dictionary:
	return Content.get_entry("hub", "npc_" + key)


static func npc_name(key: String) -> String:
	return str(npc(key).get("name", key.capitalize()))


static func npc_color(key: String) -> Color:
	return Color.from_string(str(npc(key).get("color", "#F2F2EC")), Color(0.95, 0.95, 0.92))


static func secret(id: String) -> Dictionary:
	return Content.get_entry("hub", id)


static func secret_ids() -> Array:
	var out := []
	for id in Content.ids("hub"):
		var e := Content.get_entry("hub", str(id))
		if str(e.get("type", "")) == "secret":
			out.append(e)
	out.sort_custom(func(a, b): return int(a.get("order", 99)) < int(b.get("order", 99)))
	return out.map(func(e): return str(e["id"]))


static func activity(id: String) -> Dictionary:
	return Content.get_entry("hub", "act_" + id)


static func cosmetic(id: String) -> Dictionary:
	return Content.get_entry("hub", id)


static func cosmetic_name(id: String) -> String:
	var c := cosmetic(id)
	if not c.is_empty():
		return str(c.get("name", id))
	if id.begins_with("hub_badge_headliner_"):
		var fid := id.trim_prefix("hub_badge_headliner_")
		return "Beat a Headliner: %s" % str(Content.get_entry("creatures", fid).get("name", fid))
	return id


static func cosmetics_in_slot(slot: String) -> Array:
	var out := []
	for id in Content.ids("hub"):
		var e := Content.get_entry("hub", str(id))
		if str(e.get("type", "")) == "cosmetic" and str(e.get("slot", "")) == slot:
			out.append(str(id))
	return out


## Context for line tokens from the profile's most recent run.
static func run_context(state: HubState, fighter_name := "") -> Dictionary:
	var lr := state.last_run()
	var act := int(lr.get("act", 1))
	var fid := str(lr.get("fighter", ""))
	var fname := str(Content.get_entry("creatures", fid).get("name", fid.trim_prefix("f_").capitalize())) if fid != "" else fighter_name
	return {"player": str(state.profile.get("name", "Rookie")), "fighter": fname if fname != "" else "your fighter",
		"boss": str(BOSS_OF_ACT.get(act, "the card")), "act": act, "kos": int(lr.get("kos", 0)), "dose": int(lr.get("dose", 0)),
		"clout": state.clout(), "secrets": state.secrets_found()}


static func fill(text: String, ctx: Dictionary) -> String:
	var out := text
	for k in ctx:
		out = out.replace("{%s}" % k, str(ctx[k]))
	return out


## The run-reaction bucket for an NPC: none | loss | loss_act2 | loss_act3 | win | title.
static func run_bucket(state: HubState) -> String:
	var lr := state.last_run()
	if lr.is_empty():
		return "none"
	var res := HubState.classify(lr)
	if res == "title":
		return "title"
	if bool(lr.get("victory", false)) == false:
		var act := int(lr.get("act", 1))
		if act >= 3:
			return "loss_act3"
		if act == 2:
			return "loss_act2"
	return "loss" if res == "loss" else "win"


## Picks a line deterministically from `pool` (rotating with `salt`).
static func pick(pool: Array, salt: int) -> String:
	if pool.is_empty():
		return ""
	return str(pool[posmod(salt, pool.size())])


static func line(key: String, field: String, salt := 0) -> String:
	var d := npc(key)
	var v = d.get(field)
	if typeof(v) == TYPE_ARRAY:
		return pick(v, salt)
	return str(v) if v != null else ""


static func keyed_line(key: String, line_key: String) -> String:
	return str((npc(key).get("lines", {}) as Dictionary).get(line_key, ""))


static func run_line(key: String, state: HubState, salt := 0) -> String:
	var runs: Dictionary = npc(key).get("run", {})
	var bucket := run_bucket(state)
	var pool: Array = runs.get(bucket, [])
	if pool.is_empty() and bucket.begins_with("loss"):
		pool = runs.get("loss", [])
	return fill(pick(pool, salt), run_context(state))
