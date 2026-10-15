class_name ModeRegistry
## Maps rules "mode" ids to MatchMode implementations. Bonus modes register here; data-defined
## mod modes are wrapped by ScriptedMode (see docs/MODDING.md#modes).

static var _factories := {}


static func register(id: String, factory: Callable) -> void:
	_factories[id] = factory


static func create(id: String) -> MatchMode:
	if _factories.has(id):
		return _factories[id].call()
	return MatchMode.new()


static func ids() -> Array:
	var out := ["standard"]
	out.append_array(_factories.keys())
	return out
