class_name NetRemoteInput
extends InputSource
## Server-side input source for a fighter controlled by a remote client.
##
## Clients sample FighterInput every physics tick and send it at 60 Hz; each packet carries the
## newest sample plus up to 7 older ones (redundancy), all tagged by a 16-bit sequence number.
## This source keeps a small jitter buffer: one sample is applied per 1/60 s of simulation time,
## a backlog deeper than MAX_DEPTH is collapsed (press counters are cumulative, so collapsing
## never loses a press), and a starved buffer holds the last sample (neutralized after 0.25 s).
## Press counters are remapped into the fighter's counter space when (re)bound, so a rejoining
## client or a bot hand-over never produces phantom presses.

const MAX_DEPTH := 3
const HARD_LIMIT := 16
const STARVE_NEUTRAL := 0.25

var player_id := 0
var label_text := "Player"
var _queue: Array[FighterInput] = []
var _last_seq := -1
var _current := FighterInput.new()
var _offset := PackedByteArray()
var _primed := false
var _acc := 0.0
var _starve := 0.0
var samples_received := 0
var samples_applied := 0
var samples_collapsed := 0
var starved_frames := 0


func _init(pid := 0, label_ := "Player") -> void:
	player_id = pid
	label_text = label_
	_offset.resize(FighterInput.BUTTON_COUNT)


func label() -> String:
	return label_text


## Call when this source takes over a fighter (match start, rejoin, after a bot).
func rebind() -> void:
	_queue.clear()
	_last_seq = -1
	_primed = false
	_acc = 0.0
	_starve = 0.0
	_current = FighterInput.new()


static func seq_newer(a: int, b: int) -> bool:
	var d := (a - b) & 0xFFFF
	return d > 0 and d < 0x8000


## samples: newest first; `seq` is the sequence number of samples[0].
func push(seq: int, samples: Array[FighterInput]) -> void:
	for k in range(samples.size() - 1, -1, -1):
		var s_seq := (seq - k) & 0xFFFF
		if _last_seq >= 0 and not seq_newer(s_seq, _last_seq):
			continue
		_queue.append(samples[k])
		_last_seq = s_seq
		samples_received += 1
	while _queue.size() > HARD_LIMIT:
		_queue.pop_front()
		samples_collapsed += 1


func buffered() -> int:
	return _queue.size()


func poll(f: Fighter, _sim, dt: float) -> void:
	var step := 1.0 / float(NetProtocol.INPUT_HZ)
	_acc += dt
	while _acc >= step:
		_acc -= step
		if _queue.is_empty():
			starved_frames += 1
			_starve += step
			break
		while _queue.size() > MAX_DEPTH:
			_queue.pop_front()
			samples_collapsed += 1
		var s: FighterInput = _queue.pop_front()
		if not _primed:
			for b in FighterInput.BUTTON_COUNT:
				_offset[b] = (f.input.press_count[b] - s.press_count[b]) & 0xFF
			_primed = true
		_current = s
		_starve = 0.0
		samples_applied += 1
	_acc = minf(_acc, step * 2.0)
	if not _primed:
		f.input.move = Vector3.ZERO
		f.input.held = 0
		return
	if _starve >= STARVE_NEUTRAL:
		f.input.move = Vector3.ZERO
		f.input.held = 0
	else:
		f.input.move = _current.move
		f.input.held = _current.held
	for b in FighterInput.BUTTON_COUNT:
		f.input.press_count[b] = (_current.press_count[b] + _offset[b]) & 0xFF
