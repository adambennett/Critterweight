class_name CommentarySelector
extends RefCounted
## Picks one recorded line for a commentary request (v0.9.17, docs/audio/COMMENTARY.md §4).
##
## Every candidate already satisfies the request's context (its `when` matched), so each one is
## accurate; the score only decides which accurate line sounds best now:
##   + W_SPEC per matched `when` key (specific lines are preferred, but specificity is a bonus, not a
##     filter: a fresh generic line beats a specific one the player heard a minute ago)
##   + freshness from CommentaryHistory (heard this match: excluded while anything else is left;
##     heard in the last few matches or plays: penalised; never heard: a small bonus, so rarely
##     selected recordings get their turn)
##   - family penalty: a joke/topic family used in the last few lines (bookie, snacks, Kendall's
##     notes, ...) is penalised so the booth does not run the same bit twice in a row
##   + speaker balance for lull lines (the other voice answers) and energy fit
##   + seeded jitter, so equal choices vary between matches but replay the same for a seed.
## Pure scoring: no audio, no I/O. `last_breakdown` keeps the winner's terms for the audit log.

const W_SPEC := 2.5
const SPEC_CAP := 3
const HEARD_THIS_MATCH := -40.0
const UNHEARD_BONUS := 1.0
const JITTER := 0.8
const BORROWED := -1.2           ## a line registered for this trigger through "also" ranks below its own lines
## Standing facts of the match (Audio.booth_context): they decide whether a line is TRUE here, not how
## relevant it is to this moment, so they never add specificity.
const STANDING := ["venue", "outdoor", "fence", "open_edges", "night", "hazards", "props", "referee", "scoring", "context",
	"format", "objective", "special_rules", "rounds_multi", "hands", "size_gap", "quick"]

var history: CommentaryHistory
var rng := RandomNumberGenerator.new()
var last_breakdown := {}


func _init(h: CommentaryHistory = null) -> void:
	history = h if h != null else CommentaryHistory.new()


func seed_match(seed_value: int) -> void:
	rng.seed = hash("commentary:%d" % seed_value)


## ids: candidate line ids; table: id -> line dict; ctx: the request context; opts:
## {speaker_pref: "barnaby"|"kendall"|"", energy: "high"|"medium"|"low"|"", exclude: {id: true}}.
## Returns "" when nothing matches.
func pick(ids: Array, table: Dictionary, ctx: Dictionary, opts := {}) -> String:
	var best := ""
	var best_score := -INF
	var best_terms := {}
	var exclude: Dictionary = opts.get("exclude", {})
	var sorted_ids := ids.duplicate()
	sorted_ids.sort()           # the jitter sequence is drawn in a fixed order
	for id in sorted_ids:
		if exclude.has(id):
			continue
		var l: Dictionary = table.get(id, {})
		if l.is_empty():
			continue
		var spec := matched_keys(l.get("when", {}), ctx)
		if spec < 0:
			continue
		for k in l.get("when", {}):
			if STANDING.has(k):
				spec -= 1
		var terms := score_terms(str(id), l, spec, opts)
		var own := str(opts.get("trigger", ""))
		if own != "" and str(l.get("trigger", own)) != own:
			terms["borrowed"] = BORROWED
		var s := 0.0
		for k in terms:
			s += float(terms[k])
		if s > best_score:
			best_score = s
			best = str(id)
			best_terms = terms
	last_breakdown = best_terms
	last_breakdown["total"] = best_score if best != "" else 0.0
	return best


## Number of `when` keys a line matched, or -1 when one does not match.
static func matched_keys(when: Dictionary, ctx: Dictionary) -> int:
	for k in when:
		if not ctx.has(k) or not matches(ctx[k], when[k]):
			return -1
	return when.size()


static func matches(ctx_value, want) -> bool:
	if typeof(ctx_value) == TYPE_ARRAY:
		for v in ctx_value:
			if matches(v, want):
				return true
		return false
	if typeof(want) == TYPE_ARRAY:
		for w in want:
			if matches(ctx_value, w):
				return true
		return false
	var numeric := typeof(want) == TYPE_FLOAT or typeof(want) == TYPE_INT
	if numeric and (typeof(ctx_value) == TYPE_FLOAT or typeof(ctx_value) == TYPE_INT):
		return is_equal_approx(float(ctx_value), float(want))  # JSON numbers parse as floats
	return str(ctx_value) == str(want)


func score_terms(id: String, l: Dictionary, spec: int, opts: Dictionary) -> Dictionary:
	var t := {}
	t["spec"] = W_SPEC * mini(spec, SPEC_CAP)
	t["fresh"] = freshness(id)
	t["family"] = family_penalty(l.get("families", []))
	var pref := str(opts.get("speaker_pref", ""))
	t["speaker"] = 0.6 if pref != "" and str(l.get("speaker", "")) == pref else 0.0
	var energy := str(opts.get("energy", ""))
	t["energy"] = 0.4 if energy != "" and str(l.get("energy", "")) == energy else 0.0
	t["jitter"] = rng.randf() * JITTER
	return t


## 0 for a line not heard for a long while, negative for recent ones, +UNHEARD_BONUS when the
## player has never heard it (within the history window).
func freshness(id: String) -> float:
	var m := history.matches_since(id)
	var p := history.plays_since(id)
	if m >= 1 << 29:
		return UNHEARD_BONUS
	if m == 0:
		return HEARD_THIS_MATCH
	var f := 0.0
	# the last two matches (a rematch, the next campaign bout) almost never repeat a line
	if m == 1:
		f -= 7.0
	elif m == 2:
		f -= 4.0
	elif m <= 5:
		f -= 2.0 - 0.3 * (m - 3)
	# and lines further back still yield to ones heard less recently
	f -= clampf(1.0 - float(p) / 400.0, 0.0, 1.0) * 1.5
	return f


func family_penalty(families: Array) -> float:
	var pen := 0.0
	for fam in families:
		var p := history.family_plays_since(str(fam))
		if p <= 2:
			pen -= 4.0
		elif p <= 6:
			pen -= 2.0
		elif p <= 14:
			pen -= 0.8
		if history.family_matches_since(str(fam)) == 0:
			pen -= 0.4      # one bit per family per match is plenty
	return pen
