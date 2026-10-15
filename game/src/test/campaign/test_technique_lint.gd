extends CampaignTestCase
## CMP / CNT-07: every fighter technique and build-specific supplement really changes its fighter.
## Patches must hit existing fields of the real creature data (a "set" on a misspelled key would
## silently create a field nothing reads) and hooks must validate. Runs on the authored kits, so a
## kit change that orphans a technique fails here.


## For ops that may create their leaf field (set/append/merge): the parent must exist, and a
## top-level key must already exist (creating "string" next to "light_string" would do nothing).
## Selector/wildcard paths are judged by the hit count instead.
static func _creatable(root: Dictionary, path: String) -> bool:
	if path.contains("[") or path.contains("*"):
		return true
	var keys := path.split(".")
	var cur = root
	for i in keys.size():
		var k := keys[i]
		if not (cur is Dictionary):
			return false
		if i == keys.size() - 1:
			return keys.size() > 1 or (cur as Dictionary).has(k)
		if not (cur as Dictionary).has(k):
			return false
		cur = cur[k]
	return true


func test_technique_patches_and_hooks_hit_their_fighters() -> void:
	var resolver = cat().resolver
	var bad := []
	var checked := 0
	for tid in Content.ids("techniques"):
		var t := Content.get_entry("techniques", str(tid))
		if str(t.get("type", "")) != "technique":
			continue
		var fid := str(t.get("fighter", ""))
		var base: Dictionary = resolver.creature_dict(fid)
		if base.is_empty():
			bad.append("%s: fighter %s unusable" % [tid, fid])
			continue
		var ap: Dictionary = t.get("apply", {})
		for p in ap.get("patches", []):
			checked += 1
			var err := ContentPatch.validate(p)
			if err != "":
				bad.append("%s: %s" % [tid, err])
				continue
			var path := str(p.get("path", ""))
			var op := str(p.get("op", ""))
			if op in ["set", "append", "merge"] and not _creatable(base, path):
				bad.append("%s: '%s' %s creates a field %s does not have" % [tid, op, path, fid])
				continue
			var d: Dictionary = base.duplicate(true)
			if ContentPatch.apply(d, p) == 0:
				bad.append("%s: patch %s %s matches nothing on %s" % [tid, op, path, fid])
		for h in ap.get("hooks", []):
			checked += 1
			var errs := Hooks.validate(h)
			if not errs.is_empty():
				bad.append("%s: hook %s" % [tid, "; ".join(errs)])
	check(checked >= 36, "checked %d technique patches/hooks" % checked)
	check(bad.is_empty(), "%d technique problems: %s" % [bad.size(), "\n".join(bad)])


func test_minion_loadout_patches_hit_their_base_bodies() -> void:
	var c := cat()
	var bad := []
	for id in c.loadouts:
		var rec: Dictionary = c.loadouts[id]
		var base_id := str(rec.get("base", ""))
		var base: Dictionary = c.resolver.creature_dict(base_id)
		if base.is_empty():
			bad.append("%s: base %s is not a usable creature" % [id, base_id])
			continue
		for p in rec.get("patches", []):
			var err := ContentPatch.validate(p)
			if err != "":
				bad.append("%s: %s" % [id, err])
				continue
			var path := str(p.get("path", ""))
			var op := str(p.get("op", ""))
			if op in ["set", "append", "merge"] and not _creatable(base, path):
				bad.append("%s: '%s' %s creates a field %s does not have" % [id, op, path, base_id])
				continue
			if ContentPatch.apply(base.duplicate(true), p) == 0:
				bad.append("%s: patch %s %s matches nothing on %s" % [id, op, path, base_id])
	check(bad.is_empty(), "%d minion loadout problems: %s" % [bad.size(), "\n".join(bad)])
