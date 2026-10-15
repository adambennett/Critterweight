class_name CampaignValidator
extends RefCounted
## Load-time validation of campaign content, run by Content after every (re)load
## (Content.POST_LOAD_VALIDATORS). Two passes:
##   1. JSON Schema (content/schemas/*.schema.json) per entry. Entries that fail are REMOVED from
##      Content.tables so a broken mod entry can never reach a run; each error names the file.
##   2. Semantic cross-checks via CampaignCatalog.validate() (hooks DSL, patch ops, modifier keys,
##      references between campaign entries, boss attack telegraphs >= 0.5 s ...).
## References to content owned by other subsystems (roster fighters, minion/boss creatures,
## arenas) are reported as warnings (Log) — they are expected to be filled by those packages.

## content kind -> schema name, plus the entry "type" values the schema accepts.
const SCHEMAS := {
	"supplements": "supplement",
	"techniques": "technique",
	"meta_upgrades": "meta_upgrade",
	"events": "event",
	"encounters": "encounter",
	"boss_fights": "boss_fight",
	"ladder": "ladder",
}


static func validate_content(content) -> PackedStringArray:
	var errs := PackedStringArray()
	if content == null:
		return errs
	for kind in SCHEMAS:
		var table = content.tables.get(kind, {})
		if typeof(table) != TYPE_DICTIONARY:
			continue
		for id in (table as Dictionary).keys():
			var entry: Dictionary = table[id]
			var clean := entry.duplicate()
			clean.erase("_package")
			clean.erase("_file")
			var found := Schema.validate_named(clean, SCHEMAS[kind], "%s#%s" % [entry.get("_file", kind), id])
			if not found.is_empty():
				for e in found:
					errs.append(e)
				(table as Dictionary).erase(id)
	var cat := CampaignCatalog.new(content)
	for e2 in cat.errors:
		errs.append(e2)
	for w in cat.warnings:
		Log.d("campaign", w)
	if not cat.warnings.is_empty():
		Log.i("campaign", "%d campaign references wait for content from other packages (roster/minions/bosses/arenas)" % cat.warnings.size())
	return errs
