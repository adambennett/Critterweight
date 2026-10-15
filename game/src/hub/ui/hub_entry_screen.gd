extends Screen
## App screen "hub": opening it walks into The Cannery (Hub.enter with the same params), so any
## menu can enter the Fight Camp hub with App.goto("hub", {spot, fighter, from}). The screen
## itself is replaced immediately (the hub is a 3D scene, not a menu).


func on_enter(p: Dictionary) -> void:
	var params := p.duplicate()
	Hub.enter.call_deferred(params)


func default_focus() -> Control:
	return null
