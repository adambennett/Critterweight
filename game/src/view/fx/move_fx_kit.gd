class_name MoveFxKit
extends RefCounted
## One fighter's Movesets effects (see MoveVfx). Override what the fighter's moves need; every
## method is view-only: it reads events, entities and the views, never the simulation.
##   vfx_names()          the effect / entity vfx names this kit draws
##   on_effect(fi, ev)    an "effect" event with one of those names (true = drawn)
##   on_sustain(fi, ev)   a sustained move starts / ends (ev.phase "start" | "end", ev.pool)
##   on_move_start(fi, ev) / on_ability(fi, ev)   a pool move starts (wind-up, build-up)
##   on_hit(fi, ev)       a hit landed by one of the fighter's pool moves (extras over the impact)
##   make_entity(e)       a projectile / zone look: {node, kind, pos, end: Callable, tick?: Callable}
##   process(delta)       per frame (beams and streams that follow the fighter)
## Helpers on `fx` (AbilityVfx): burst, stream, end_stream, animate, footprint, ring_wall, vortex,
## jet, crest, ribbon/draw_ribbon, bolt, flash_light, follow/release, anchor, fpoint, _yaw, _ground,
## _info, _attached_stream, quality, reduce_flashes.

var fx: AbilityVfx
var creature := ""


func vfx_names() -> Array:
	return []


func on_effect(_fi: int, _ev: Dictionary) -> bool:
	return false


func on_sustain(_fi: int, _ev: Dictionary) -> bool:
	return false


func on_move_start(_fi: int, _ev: Dictionary) -> bool:
	return false


func on_ability(_fi: int, _ev: Dictionary) -> bool:
	return false


func on_hit(_fi: int, _ev: Dictionary) -> void:
	pass


func make_entity(_e: Dictionary) -> Dictionary:
	return {}


func process(_delta: float) -> void:
	pass


## The fighter's facing as a unit vector, tilted `pitch` radians (negative = down).
func aim_dir(fi: int, pitch := 0.0) -> Vector3:
	var d := MathX.forward_of_yaw(fx._yaw(fi))
	return (d * cos(pitch) + Vector3.UP * sin(pitch)).normalized()


## Whether fighter fi is still in a state where its move is running (attack / ability).
func is_acting(fi: int) -> bool:
	var st := int(fx._info(fi).get("state", -1))
	return st == Fighter.State.ATTACK or st == Fighter.State.ABILITY
