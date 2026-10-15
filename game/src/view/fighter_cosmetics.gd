class_name FighterCosmetics
extends RefCounted
## What the active profile's fighter wears — the Cannery locker's cosmetics turned into view
## instructions (docs/HUB_SYSTEMS.md §16). VIEW-ONLY: nothing here reaches the simulation, and only
## the profile owner's own fighter shows them (local matches, the hub, campaign fights).
##
## Profile layout (written by HubState): camp.hub.loadout.cosmetics {slot: id}; owned ids in
## unlocks.cosmetics. Item visuals live in content kind "hub" (content/core/hub/cosmetics.json):
##   "attach": {kind: tooth|lid|belt|scarf, color, accent}  -> CreatureView.set_cosmetics
##   "juice":  {creature, juice_color, glow_color, glow_mix} -> CreatureView.set_juice_style
##   "frame":  {border, glow, bg, tag}                       -> ProfileFrame (name cards)
## Headliner badges (hub_badge_headliner_<fighter>) are frames too.

const ATTACH_SLOTS := ["piece", "idle_prop", "back", "neck"]
const BADGE_PREFIX := "hub_badge_headliner_"


## slot -> cosmetic id, only for items the profile actually owns.
static func equipped(profile: Dictionary) -> Dictionary:
	var camp: Dictionary = profile.get("camp", {}) if typeof(profile.get("camp", {})) == TYPE_DICTIONARY else {}
	var hub: Dictionary = camp.get("hub", {}) if typeof(camp.get("hub", {})) == TYPE_DICTIONARY else {}
	var lo: Dictionary = hub.get("loadout", {}) if typeof(hub.get("loadout", {})) == TYPE_DICTIONARY else {}
	var cos: Dictionary = lo.get("cosmetics", {}) if typeof(lo.get("cosmetics", {})) == TYPE_DICTIONARY else {}
	var unlocks: Dictionary = profile.get("unlocks", {}) if typeof(profile.get("unlocks", {})) == TYPE_DICTIONARY else {}
	var owned: Array = unlocks.get("cosmetics", []) if typeof(unlocks.get("cosmetics", [])) == TYPE_ARRAY else []
	var out := {}
	for slot in cos:
		var id := str(cos[slot])
		if id != "" and owned.has(id):
			out[str(slot)] = id
	return out


static func item(id: String) -> Dictionary:
	return Content.get_entry("hub", id)


## Attachments for `creature_id`: [{kind, color, accent, id}].
static func attachments(profile: Dictionary, _creature_id := "") -> Array:
	var out := []
	var eq := equipped(profile)
	for slot in ATTACH_SLOTS:
		if not eq.has(slot):
			continue
		var att = item(str(eq[slot])).get("attach", {})
		if typeof(att) != TYPE_DICTIONARY or (att as Dictionary).is_empty():
			continue
		var e: Dictionary = (att as Dictionary).duplicate()
		e["id"] = str(eq[slot])
		out.append(e)
	return out


## The JUICE colour variant for `creature_id` ({} when none applies): {juice_color, glow_color, glow_mix}.
static func juice_style(profile: Dictionary, creature_id: String) -> Dictionary:
	var eq := equipped(profile)
	if not eq.has("juice"):
		return {}
	var j = item(str(eq["juice"])).get("juice", {})
	if typeof(j) != TYPE_DICTIONARY or (j as Dictionary).is_empty():
		return {}
	var jd: Dictionary = j
	if jd.has("creature") and str(jd["creature"]) != creature_id:
		return {}
	return jd


## The equipped profile frame: {id, name, border, glow, bg, tag} or {}.
static func frame(profile: Dictionary) -> Dictionary:
	var eq := equipped(profile)
	if not eq.has("frame"):
		return {}
	var id := str(eq["frame"])
	if id.begins_with(BADGE_PREFIX):
		var fid := id.trim_prefix(BADGE_PREFIX)
		var fname := str(Content.get_entry("creatures", fid).get("name", fid.trim_prefix("f_").capitalize()))
		return {"id": id, "name": "Headliner badge: %s" % fname, "border": "#E8B923", "glow": "#FFD86B", "bg": "#1A1508",
			"tag": "HEADLINER  ·  %s" % fname.to_upper()}
	var it := item(id)
	var f = it.get("frame", {})
	if typeof(f) != TYPE_DICTIONARY or (f as Dictionary).is_empty():
		return {}
	var out: Dictionary = (f as Dictionary).duplicate()
	out["id"] = id
	out["name"] = str(it.get("name", id))
	return out


## Applies the profile's cosmetics to a CreatureView of `creature_id` (the owner's fighter only).
static func dress(view: CreatureView, profile: Dictionary) -> void:
	if view == null or view.creature == null:
		return
	view.set_cosmetics(attachments(profile, view.creature.id))
	var js := juice_style(profile, view.creature.id)
	if js.is_empty():
		view.set_juice_style(CreatureView.DEFAULT_JUICE, Color(1, 1, 1, 0))
	else:
		var glow := Color.from_string(str(js.get("glow_color", "#FFFFFF")), Color.WHITE)
		glow.a = float(js.get("glow_mix", 0.0))
		view.set_juice_style(Color.from_string(str(js.get("juice_color", "#FF8C1A")), CreatureView.DEFAULT_JUICE), glow)
