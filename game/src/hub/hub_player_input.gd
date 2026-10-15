class_name HubPlayerInput
extends LocalPlayerInput
## The local player in the hub: the normal fight controls (camera-relative stick, Light/Heavy/
## Grab/Guard/Taunt/abilities) plus the context interaction. "Interact" (pad A / Enter by default)
## near an interactable becomes an interaction and its Dodge press is swallowed here, so the
## fighter never also dodges (pad A is both Dodge and Interact); away from interactables A dodges
## as usual. While a hub board/menu is open (and for a moment after it closes, so the press that
## closed it does nothing) the fighter gets no input.

const AFTER_SCREEN := 0.26          ## seconds of no fighter input after a board/menu closes

var mode: HubMode
var _block_left := 0.0


func label() -> String:
	return "Player"


func poll(f: Fighter, s, dt: float) -> void:
	# counted in simulated time (the step's dt), so it holds the same at any frame rate
	if App.top_screen() != null:
		_block_left = AFTER_SCREEN
	elif _block_left > 0.0:
		_block_left -= dt
	var blocked := not enabled or _block_left > 0.0 or (mode != null and not mode.transition.is_empty())
	if blocked:
		f.input.move = Vector3.ZERO
		f.input.held = 0
		return
	var dodge_before: int = f.input.press_count[FighterInput.DODGE]
	super.poll(f, s, dt)
	if mode == null:
		return
	if Input.is_action_just_pressed("interact") and mode.interaction_available(f):
		f.input.press_count[FighterInput.DODGE] = dodge_before
		mode.request_interact(f)
