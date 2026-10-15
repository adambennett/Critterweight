class_name RunRng
extends RefCounted
## Deterministic, platform-independent randomness for campaign runs (CAMPAIGN.md §2 "Seed").
##
## Every random decision of a run draws from its OWN stream derived from (run seed, purpose key),
## e.g. "a2/map/types/3", "node/a1r3l2/reward/p1/0". Streams never depend on call order, so a run is
## reproducible from its seed + decision log, a co-op replica regenerates the same card, and a
## reroll or resume never shifts unrelated rolls.
##
## Hashing is 32-bit FNV-1a done in integer arithmetic (no platform-dependent hash()); the stream
## itself is Godot's RandomNumberGenerator (PCG32), which is integer-exact across platforms.
## Invariant: given the same seed and key, `stream()` yields the same sequence on every machine.

const FNV_OFFSET := 2166136261
const FNV_PRIME := 16777619
const SEED_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"   ## Crockford-ish base32, no I/L/O/U
## Run seeds are stored in JSON (saves, party tickets), whose numbers are doubles: keep them
## within 53 bits so they survive every round trip exactly.
const SEED_MASK := (1 << 53) - 1


static func normalize_seed(s: int) -> int:
	var v := s & SEED_MASK
	return v if v != 0 else 1

var rng := RandomNumberGenerator.new()


static func hash32(s: String) -> int:
	var h: int = FNV_OFFSET
	for b in s.to_utf8_buffer():
		h = ((h ^ b) * FNV_PRIME) & 0xFFFFFFFF
	return h


## 63-bit seed derived from a base seed and a purpose key.
static func derive(seed_value: int, key: String) -> int:
	var s := "%d|%s" % [seed_value, key]
	var hi := hash32(s) & 0x7FFFFFFF
	var lo := hash32(s + "#lo")
	return (hi << 32) | lo


## A fresh stream for (seed, key).
static func stream(seed_value: int, key: String) -> RunRng:
	var r := RunRng.new()
	r.rng.seed = derive(seed_value, key)
	return r


## Human-friendly seed text ("7F3A-91C2-0B4"), and its parser. Arbitrary text is hashed so
## players can type words as seeds.
static func seed_to_text(seed_value: int) -> String:
	var v: int = seed_value & SEED_MASK
	var out := ""
	for i in 11:
		out = SEED_ALPHABET[v & 31] + out
		v = v >> 5
	return "%s-%s-%s" % [out.substr(0, 4), out.substr(4, 4), out.substr(8, 3)]


static func text_to_seed(text: String) -> int:
	var t := text.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if t == "":
		return 0
	var ok := t.length() <= 11
	var v := 0
	if ok:
		for ch in t:
			var d := SEED_ALPHABET.find(ch)
			if d < 0:
				ok = false
				break
			v = (v << 5) | d
	if ok and v > 0 and v <= SEED_MASK:
		return v
	return normalize_seed(derive(0, "text:" + text.strip_edges()))


## A new random seed for a fresh run (not reproducible by design).
static func fresh_seed() -> int:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return normalize_seed(((r.randi() & 0x7FFFFFFF) << 32) | r.randi())


# ---------------------------------------------------------------------------------------------
# Stream helpers
# ---------------------------------------------------------------------------------------------

func randf() -> float:
	return rng.randf()


func chance(p: float) -> bool:
	return rng.randf() < p


func range_i(lo: int, hi: int) -> int:
	return rng.randi_range(lo, hi)


func range_f(lo: float, hi: float) -> float:
	return lo + (hi - lo) * rng.randf()


## Index into `weights` (Array of numbers), proportional to weight. -1 if all weights <= 0.
func weighted_index(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return -1
	var roll := rng.randf() * total
	var acc := 0.0
	for i in weights.size():
		acc += maxf(0.0, float(weights[i]))
		if roll < acc:
			return i
	return weights.size() - 1


## Picks one element of `items`; `weight_of` (optional) maps an item to its weight.
func pick(items: Array, weight_of: Callable = Callable()):
	if items.is_empty():
		return null
	if not weight_of.is_valid():
		return items[rng.randi_range(0, items.size() - 1)]
	var ws := []
	for it in items:
		ws.append(float(weight_of.call(it)))
	var i := weighted_index(ws)
	return items[i] if i >= 0 else null


## Deterministic Fisher-Yates shuffle (returns a new array).
func shuffled(items: Array) -> Array:
	var out := items.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


## `n` distinct elements drawn by weight without replacement.
func pick_distinct(items: Array, n: int, weight_of: Callable = Callable()) -> Array:
	var pool := items.duplicate()
	var out := []
	while out.size() < n and not pool.is_empty():
		var it = pick(pool, weight_of)
		if it == null:
			break
		out.append(it)
		pool.erase(it)
	return out
