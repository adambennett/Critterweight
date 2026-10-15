class_name ArenaVariants
extends RefCounted
## Which arena looks (ArenaDef variants, lighting/dressing only) a profile may use. Besides its
## lighting keys a variant definition (base_def.variants.<id>) may carry:
##   "hidden": true, "unlock": "<cosmetic id>"  only offered once the profile owns that unlock
##                                               (the Cannery's Pier Night / Rooftop full neon)
##   "replaces": "<variant id>"                  once unlocked, used automatically instead of it
##   "modes": ["chum_rush", ...]                 only offered for those rules modes
## Applied when a match config is resolved (App.resolve_match_config -> upgrade) and offered as the
## "Look" row of the versus setup (selectable). Never changes gameplay.


static func owned(profile: Dictionary) -> Array:
	var u = profile.get("unlocks", {})
	if typeof(u) != TYPE_DICTIONARY:
		return []
	var c = (u as Dictionary).get("cosmetics", [])
	return c if typeof(c) == TYPE_ARRAY else []


static func unlocked(vdef: Dictionary, profile: Dictionary) -> bool:
	var need := str(vdef.get("unlock", ""))
	if need == "":
		return not bool(vdef.get("hidden", false))
	return owned(profile).has(need)


static func _variants(a: ArenaDef) -> Dictionary:
	if a == null:
		return {}
	var vs = a.base_def.get("variants", {})
	return vs if typeof(vs) == TYPE_DICTIONARY else {}


## Hidden variants of `a` this profile has unlocked, for the rules mode `mode_id` ("" = any):
## [{id, label}]. Empty for most arenas and for fresh profiles.
static func unlocked_extras(a: ArenaDef, profile: Dictionary, mode_id := "") -> Array:
	var out := []
	var vs := _variants(a)
	for vid in vs:
		var vd: Dictionary = vs[vid]
		if not bool(vd.get("hidden", false)) or not unlocked(vd, profile):
			continue
		if str(vd.get("replaces", "")) != "":
			continue          # automatic upgrades are not a separate choice
		var modes: Array = vd.get("modes", [])
		if mode_id != "" and not modes.is_empty() and not modes.has(mode_id):
			continue
		out.append({"id": str(vid), "label": str(vd.get("label", str(vid).capitalize()))})
	return out


## Every variant id a picker may list for this profile (the arena editor): visible ones plus
## unlocked hidden ones.
static func listable(a: ArenaDef, profile: Dictionary) -> Array:
	var out := []
	var vs := _variants(a)
	for vid in vs:
		var vd: Dictionary = vs[vid]
		if not bool(vd.get("hidden", false)) or unlocked(vd, profile):
			out.append(str(vid))
	return out


## The arena with any unlocked "replaces" upgrade of its current variant applied (else itself).
static func upgrade(a: ArenaDef, profile: Dictionary) -> ArenaDef:
	var vs := _variants(a)
	var cur := a.variant if a.variant != "" else str(a.base_def.get("default_variant", ""))
	for vid in vs:
		var vd: Dictionary = vs[vid]
		if str(vd.get("replaces", "")) == cur and cur != "" and unlocked(vd, profile):
			return a.with_variant(str(vid))
	return a
