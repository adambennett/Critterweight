class_name LocalPlayerInput
extends InputSource
## Feeds a fighter from the local keyboard/mouse/controller, converting the stick into a
## world direction relative to the active camera.

var camera: Camera3D
var enabled := true
var player_label := "Player"


func label() -> String:
	return player_label


func poll(f: Fighter, _sim, _dt: float) -> void:
	if not enabled:
		f.input.move = Vector3.ZERO
		f.input.held = 0
		return
	var b := Basis.IDENTITY
	if camera:
		if camera.has_method("input_basis"):
			b = camera.input_basis()
		else:
			b = camera.global_basis
	Controls.fill(f.input, b, f.creature, f.target.pos() - f.pos() if f.target else f.forward())
