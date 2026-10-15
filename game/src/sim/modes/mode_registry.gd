class_name ModeRegistry
## Maps rules "mode" ids to MatchMode implementations. Built-in bonus modes are registered on
## first use; other systems (campaign BossMode, mod ScriptedMode) register their own factories.

static var _factories := {}
static var _builtins_done := false


static func _ensure_builtins() -> void:
	if _builtins_done:
		return
	_builtins_done = true
	_factories["standard"] = func() -> MatchMode: return MatchMode.new()
	_factories["spotlight_hog"] = func() -> MatchMode: return SpotlightHogMode.new()
	_factories["chumball"] = func() -> MatchMode: return ChumballMode.new()
	_factories["absolute_unit"] = func() -> MatchMode: return AbsoluteUnitMode.new()
	_factories["chum_rush"] = func() -> MatchMode: return ChumRushMode.new()
	_factories["tag_team"] = func() -> MatchMode: return TagTeamMode.new()
	_factories["practice"] = func() -> MatchMode: return PracticeMode.new()
	_factories["tutorial"] = func() -> MatchMode: return TutorialMode.new()


static func register(id: String, factory: Callable) -> void:
	_ensure_builtins()
	_factories[id] = factory


static func create(id: String) -> MatchMode:
	_ensure_builtins()
	if _factories.has(id):
		return _factories[id].call()
	return MatchMode.new()


static func has(id: String) -> bool:
	_ensure_builtins()
	return _factories.has(id)


static func ids() -> Array:
	_ensure_builtins()
	return _factories.keys()
