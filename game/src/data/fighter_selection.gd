class_name FighterSelection
extends RefCounted
## Shared fighter selection behavior. "random" stays a UI choice and resolves to a concrete
## playable id before a match, run, or training job is created.


static func with_random(ids: Array) -> Array[String]:
	var out: Array[String] = ["random"]
	for candidate in ids:
		var id := str(candidate)
		if id != "" and id != "random" and not out.has(id):
			out.append(id)
	return out


static func resolve(id: String, ids: Array, seed: int = 0) -> String:
	if ids.is_empty():
		return ""
	if id != "random":
		return id if ids.has(id) else str(ids[0])
	var rng := RandomNumberGenerator.new()
	if seed == 0:
		rng.randomize()
	else:
		rng.seed = seed
	return str(ids[rng.randi_range(0, ids.size() - 1)])
