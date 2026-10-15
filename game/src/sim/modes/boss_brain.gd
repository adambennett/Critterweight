class_name BossBrain
extends InputSource
## Input source for a boss: the ordinary BotBrain pilots its regular moveset between special
## attacks; BossMode takes the stick ("hold") while it telegraphs and executes scripted attacks,
## during the recovery windows that are the players' punish, during Dazed and phase transitions.
## Like every input source it only writes FighterInput — the boss obeys all combat rules.

var inner: BotBrain
var hold := false                ## BossMode is driving (telegraph / attack / recovery / dazed)
var move_override := Vector3.ZERO
var _presses: Array = []


func _init(bot: BotBrain = null) -> void:
	inner = bot if bot else BotBrain.new("regular", 1)


func label() -> String:
	return "Boss (%s)" % (inner.label() if inner else "scripted")


func press(button: int) -> void:
	_presses.append(button)


func poll(f: Fighter, sim, dt: float) -> void:
	if hold:
		f.input.move = move_override
		f.input.held = 0
	elif inner:
		inner.poll(f, sim, dt)
	for b in _presses:
		f.input.press(int(b))
	_presses.clear()
