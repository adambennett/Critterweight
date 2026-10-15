class_name NetRateLimiter
extends RefCounted
## Token bucket: `rate` tokens per second refill up to `burst`. take(cost) spends tokens and
## returns false when the bucket is empty (the caller drops / scores a violation).
##
## Clock: the larger of the wall-clock time and the simulated (physics) time since the bucket was
## made, both monotonic. In real-time runs simulated time never gets ahead of the wall clock, so
## this is the plain wall-clock bucket; under `--fixed-fps` (deterministic test runs) frames run
## faster than real time, and a client sending 60 inputs per simulated second must not look like
## a flood.

var rate := 10.0
var burst := 20.0
var tokens := 20.0
var _start_us := 0
var _start_frames := 0
var _credit := 0.0               ## seconds of the clock already turned into tokens


func _init(r := 10.0, b := 20.0) -> void:
	rate = r
	burst = b
	tokens = b
	_start_us = Time.get_ticks_usec()
	_start_frames = Engine.get_physics_frames()


func _elapsed() -> float:
	var wall := float(Time.get_ticks_usec() - _start_us) / 1000000.0
	var simulated := float(Engine.get_physics_frames() - _start_frames) / float(Engine.physics_ticks_per_second)
	return maxf(wall, simulated)


func take(cost := 1.0) -> bool:
	var e := _elapsed()
	tokens = minf(burst, tokens + (e - _credit) * rate)
	_credit = e
	if tokens < cost:
		return false
	tokens -= cost
	return true
