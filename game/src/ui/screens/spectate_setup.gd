extends VersusSetup
## Spectate setup ("spectate"): the versus setup restricted to bots — pick fighters, skill tiers,
## rules and arena, then watch with the auto-director camera (MatchFlow.launch sets the camera to
## FightCamera SPECTATE and adds the SpectatorOverlay for camera/HUD controls).


func on_enter(p: Dictionary) -> void:
	var q := p.duplicate()
	q["mode"] = "spectate"
	super(q)
