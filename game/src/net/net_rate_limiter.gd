class_name NetRateLimiter
extends RefCounted
## Token bucket: `rate` tokens per second refill up to `burst`. take(cost) spends tokens and
## returns false when the bucket is empty (the caller drops / scores a violation).
##
## Clock: the larger of the wall-clock time and the simulated (physics) time since the bucket was
## made. Simulated time is summed step by step at the tick rate in force (it never runs backwards,
## even if the tick rate changes). In real-time runs it never gets ahead of the wall clock, so this
## is the plain wall-clock bucket; under `--fixed-fps` (deterministic test runs) frames run faster
## than real time, and a client sending 60 inputs per simulated second must not look like a flood.

var rate := 10.0
var burst := 20.0
var tokens := 20.0
var _start_us := 0
var _last_frames := 0
var _sim_s := 0.0                ## simulated seconds since the bucket was made
var _credit := 0.0               ## seconds of the clock already turned into tokens


func _init(r := 10.0, b := 20.0) -> void:
	rate = r
	burst = b
	tokens = b
	_start_us = Time.get_ticks_usec()
	_last_frames = Engine.get_physics_frames()


func _elapsed() -> float:
	var frames := Engine.get_physics_frames()
	if frames > _last_frames:
		_sim_s += float(frames - _last_frames) / float(maxi(1, Engine.physics_ticks_per_second))
	_last_frames = frames
	var wall := float(Time.get_ticks_usec() - _start_us) / 1000000.0
	return maxf(wall, _sim_s)


func take(cost := 1.0) -> bool:
	var e := _elapsed()
	if e > _credit:
		tokens = minf(burst, tokens + (e - _credit) * rate)
		_credit = e
	if tokens < cost:
		return false
	tokens -= cost
	return true
