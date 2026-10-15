class_name RouteVote
extends RefCounted
## A party vote between options (route nodes, or a group event's choices) — CAMPAIGN.md §11:
##   * majority wins;
##   * tie -> the Captain decides: the Captain's own vote if it is among the tied options,
##     otherwise (Captain abstained/idle) a deterministic random pick among the tied options;
##   * no vote = abstain; everyone abstains -> the Captain's pick, or a deterministic random
##     pick when the Captain is idle when the timer ends.
## Deterministic for a given (seed, key) so every replica reaches the same result.

var options: Array = []
var votes := {}                 ## voter id -> option
var voters: Array = []          ## eligible voters (connected humans)
var captain := ""
var deadline := 0.0
var seed_value := 0
var key := ""


func _init(opts: Array = [], eligible: Array = [], captain_id := "", until := 0.0, seed_v := 0, key_s := "") -> void:
	options = opts.duplicate()
	voters = eligible.duplicate()
	captain = captain_id
	deadline = until
	seed_value = seed_v
	key = key_s


func cast(voter: String, option: String) -> bool:
	if not voters.has(voter) or not options.has(option):
		return false
	votes[voter] = option
	return true


func all_voted() -> bool:
	for v in voters:
		if not votes.has(v):
			return false
	return true


func counts() -> Dictionary:
	var c := {}
	for v in votes:
		c[votes[v]] = int(c.get(votes[v], 0)) + 1
	return c


## {option, reason: majority|captain_tiebreak|captain_idle_random|all_abstained_random, tie}
func result() -> Dictionary:
	var c := counts()
	if c.is_empty():
		return {"option": _random_of(options), "reason": "all_abstained_random", "tie": false}
	var best := 0
	for o in c:
		best = maxi(best, int(c[o]))
	var top := []
	for o2 in options:
		if int(c.get(o2, 0)) == best:
			top.append(o2)
	if top.size() == 1:
		return {"option": top[0], "reason": "majority", "tie": false}
	if votes.has(captain) and top.has(votes[captain]):
		return {"option": votes[captain], "reason": "captain_tiebreak", "tie": true}
	return {"option": _random_of(top), "reason": "captain_idle_random", "tie": true}


func _random_of(arr: Array):
	if arr.is_empty():
		return ""
	var r := RunRng.stream(seed_value, "vote/%s" % key)
	return arr[r.range_i(0, arr.size() - 1)]
