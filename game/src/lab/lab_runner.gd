class_name LabRunner
extends Node
## Runs queued episodes in up to `max_worlds` parallel physics worlds inside one process. The
## owner calls `step(dt)` once per physics frame (each world advances exactly one tick per frame,
## because the physics server steps every active space once per frame).
## Measured on the dev PC (docs/AI_LAB.md): one process sustains roughly 8–16 simulated seconds
## per wall second (busy vs idle PC) regardless of the number of worlds (the work is
## single-threaded GDScript + Jolt), so
## throughput scales with worker PROCESSES; several worlds per process keep slots busy while an
## episode is being built or torn down.

## (item: Dictionary) -> PolicyData (null for scripted learners)
var resolver: Callable = Callable()
## optional (episode: LabEpisode) -> void, called before an episode is disposed
var on_finished: Callable = Callable()
var max_worlds := 2
var queue: Array = []
var active: Array = []
var results: Array = []
var frozen := false
var sim_ticks := 0
var episodes_done := 0
var errors := 0


func add_items(items: Array) -> void:
	queue.append_array(items)


func busy() -> bool:
	return not queue.is_empty() or not active.is_empty()


func take_results() -> Array:
	var out := results
	results = []
	return out


func step(dt: float) -> void:
	if frozen:
		return
	while active.size() < max_worlds and not queue.is_empty():
		var it: Dictionary = queue.pop_front()
		var ep := LabEpisode.new()
		var pol: PolicyData = resolver.call(it) if resolver.is_valid() else null
		var err := ep.start(self, it, pol)
		if err != "":
			Log.w("lab", "episode %d failed to start: %s" % [int(it.get("i", -1)), err])
			errors += 1
			results.append(ep.result)
			ep.dispose()
			continue
		active.append(ep)
	for ep: LabEpisode in active.duplicate():
		ep.tick(dt)
		sim_ticks += 1
		if ep.done:
			if on_finished.is_valid():
				on_finished.call(ep)
			results.append(ep.result)
			episodes_done += 1
			active.erase(ep)
			ep.dispose()


func set_frozen(on: bool) -> void:
	if frozen == on:
		return
	frozen = on
	for ep: LabEpisode in active:
		ep.freeze(on)


func clear() -> void:
	for ep: LabEpisode in active:
		ep.dispose()
	active.clear()
	queue.clear()
	results.clear()
