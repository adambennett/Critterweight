class_name NetRateLimiter
extends RefCounted
## Token bucket: `rate` tokens per second refill up to `burst`. take(cost) spends tokens and
## returns false when the bucket is empty (the caller drops / scores a violation).

var rate := 10.0
var burst := 20.0
var tokens := 20.0
var _last_us := 0


func _init(r := 10.0, b := 20.0) -> void:
	rate = r
	burst = b
	tokens = b
	_last_us = Time.get_ticks_usec()


func take(cost := 1.0) -> bool:
	var now := Time.get_ticks_usec()
	tokens = minf(burst, tokens + float(now - _last_us) / 1000000.0 * rate)
	_last_us = now
	if tokens < cost:
		return false
	tokens -= cost
	return true
