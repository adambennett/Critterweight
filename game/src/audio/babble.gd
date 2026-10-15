class_name Babble
extends Node
## Runtime "babble" voice for the announcer (Barnaby) and the coach (Granny): original gibberish
## speech assembled from short formant grains (rendered offline by tools/audio into
## assets/audio/announcer/<speaker>/) and streamed through an AudioStreamGenerator.
## plan(text, voice, ...) mirrors tools/audio/lib/babble.js (keep both in sync): syllables come from
## letter classes, the pitch contour from punctuation, ALL-CAPS words get +40% level and a pitch
## jump, fighter names get the two-honk fanfare grain, lines are capped at 4 s of babble.
## Invariant: everything here is cosmetic; it never touches gameplay state.

signal finished(line_id: String)

const MIX_RATE := 22050.0
const VOWELS := "aeiouy"

var bus := "Dialogue"
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _banks := {}              ## speaker -> {grain id -> PackedFloat32Array}
var _voices := {}             ## speaker -> voice parameters (from bank.json)
var _plan: Array = []         ## [{t, id, pitch, gain, dur, vib}] sorted by t (in samples)
var _active: Array = []       ## [{src, pos, step, gain, len, rel, vib}]
var _next := 0
var _pos := 0                 ## output sample counter for the current line
var _end := 0
var _line_id := ""
var speaking := false


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.12
	_player.stream = gen
	_player.bus = bus
	_player.name = "BabblePlayer"
	add_child(_player)


## Registers a speaker from the bank: {grains: {id: res path}, f0, rate, ...}
func add_voice(speaker: String, params: Dictionary) -> void:
	_voices[speaker] = params


func has_voice(speaker: String) -> bool:
	return _voices.has(speaker)


func _load_bank(speaker: String) -> bool:
	if _banks.has(speaker):
		return true
	if not _voices.has(speaker):
		return false
	var grains: Dictionary = _voices[speaker].get("grains", {})
	var bank := {}
	for gid in grains:
		var path := str(grains[gid])
		if not ResourceLoader.exists(path):
			continue
		var s = load(path)
		if not (s is AudioStreamWAV):
			continue
		var wav: AudioStreamWAV = s
		if wav.format != AudioStreamWAV.FORMAT_16_BITS:
			push_warning("Babble: grain %s is not 16-bit PCM (import compress/mode must be 0)" % path)
			continue
		var data := wav.data
		var n := data.size() / 2
		var pcm := PackedFloat32Array()
		pcm.resize(n)
		for i in n:
			pcm[i] = float(data.decode_s16(i * 2)) / 32768.0
		bank[gid] = pcm
	_banks[speaker] = bank
	return not bank.is_empty()


# ---------------------------------------------------------------------------------------
# Planning (reference: tools/audio/lib/babble.js)
# ---------------------------------------------------------------------------------------

static func letter_class(c: String) -> String:
	c = c.to_lower()
	if VOWELS.contains(c):
		return "vowel"
	if "pbtdkgq".contains(c):
		return "plosive"
	if "szxc".contains(c):
		return "sibilant"
	if c == "h":
		return "sh"
	if "fvjw".contains(c):
		return "fric"
	if "mn".contains(c):
		return "nasal"
	if "lr".contains(c):
		return "liquid"
	return "none"


static func _vowel_of(c: String) -> String:
	c = c.to_lower()
	if c == "y":
		return "i"
	return c if VOWELS.contains(c) else "a"


static func _letters(word: String) -> String:
	var out := ""
	for ch in word:
		var code := ch.unicode_at(0)
		if (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or ch == "'":
			out += ch
	return out


## Splits a word into syllables: [{onset: class or "", vowel: a..u, coda: class or ""}]
static func syllabify(word: String) -> Array:
	var letters := _letters(word)
	var syl: Array = []
	var onset := ""
	var i := 0
	while i < letters.length():
		var c := letters[i]
		var cls := letter_class(c)
		if cls == "vowel":
			var j := i + 1
			while j < letters.length() and letter_class(letters[j]) == "vowel":
				j += 1
			if c.to_lower() == "e" and i == letters.length() - 1 and syl.size() > 0:
				break
			syl.append({"onset": onset, "vowel": _vowel_of(c), "coda": ""})
			onset = ""
			i = j
		else:
			if cls != "none":
				onset = cls
			i += 1
	if syl.is_empty():
		syl.append({"onset": onset if onset != "" else "plosive", "vowel": "u", "coda": ""})
	var last_cls := letter_class(letters[letters.length() - 1]) if letters.length() > 0 else "vowel"
	if last_cls != "vowel" and last_cls != "none":
		syl[syl.size() - 1]["coda"] = last_cls
	return syl


static func _contour_pitch(contour: String, term: String, u: float) -> float:
	if contour == "flat":
		return 1.0 - 0.03 * u
	match term:
		"!":
			return 1.0 + 0.22 * u
		"?":
			return 1.0 + 0.28 * sin(PI * minf(1.0, u * 1.1)) - 0.05 * u
		"…":
			return 0.97
	return 1.06 - 0.18 * u


static func _ends_with_any(w: String, chars: String) -> bool:
	if w.is_empty():
		return false
	return chars.contains(w[w.length() - 1])


static func _is_term(w: String) -> bool:
	return _ends_with_any(w, ".!?…") or w.ends_with("...")


## Builds the grain plan for a line. Returns {duration: float, grains: [{t, id, pitch, gain, dur, vib}]}
static func plan(text: String, voice: Dictionary, seed_value: int, reduced := false, names: Array = [], mood := "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s" % [seed_value, text])
	var rate := float(voice.get("rate", 11.0))
	var cons_ms := float(voice.get("consMs", 32.0))
	var contour := str(voice.get("contour", "auction"))
	var caps_gain := float(voice.get("capsGain", 1.4))
	var caps_pitch := float(voice.get("capsPitch", 1.3))
	var fanfare := bool(voice.get("fanfare", false))
	var is_granny := contour == "flat"
	var words: PackedStringArray = text.split(" ", false)
	var sentences: Array = []
	var cur: Array = []
	for w in words:
		cur.append(w)
		if _is_term(w):
			sentences.append(cur)
			cur = []
	if not cur.is_empty():
		sentences.append(cur)
	var slot := 1.0 / rate
	var grains: Array = []
	var t := 0.0
	var lower_names: Array = []
	for nm in names:
		lower_names.append(str(nm).to_lower())
	for sentence_v in sentences:
		var sentence: Array = sentence_v
		var last_word: String = sentence[sentence.size() - 1]
		var term := "."
		if last_word.ends_with("…") or last_word.ends_with("..."):
			term = "…"
		elif last_word.ends_with("!"):
			term = "!"
		elif last_word.ends_with("?"):
			term = "?"
		var total := 0
		var syl_lists: Array = []
		for w in sentence:
			var s := syllabify(w)
			syl_lists.append(s)
			total += s.size()
		var syl_index := 0
		for wi in sentence.size():
			var word: String = sentence[wi]
			var bare := _letters(word)
			var caps: bool = bare.length() >= 2 and bare == bare.to_upper()
			var is_name: bool = lower_names.has(bare.to_lower())
			var is_last: bool = wi == sentence.size() - 1
			var syls: Array = syl_lists[wi]
			var auto_name: bool = caps and lower_names.is_empty() and bare.length() >= 4 and is_last
			if fanfare and (is_name or auto_name):
				var u := float(syl_index) / float(total) if total > 0 else 0.0
				grains.append({"t": t, "id": "fanfare", "pitch": _contour_pitch(contour, term, u) * rng.randf_range(0.97, 1.03), "gain": caps_gain, "dur": 0.27, "vib": 0.0})
				t += 0.29
				syl_index += syls.size()
			else:
				for si in syls.size():
					var s: Dictionary = syls[si]
					var u := float(syl_index) / float(total - 1) if total > 1 else 0.5
					var pm := _contour_pitch(contour, term, u)
					if caps:
						pm *= caps_pitch
					if si == 0 and syls.size() > 1:
						pm *= 1.04
					if is_last and si == syls.size() - 1 and contour == "auction":
						pm *= 1.12 if term == "!" else (0.94 if term == "?" else 0.9)
					pm *= 1.0 + rng.randf_range(-0.04, 0.04)
					var g := caps_gain if caps else 1.0
					if is_last and contour == "auction":
						g *= 1.15
					var slot_len := slot * (1.25 if caps else 1.0) * (1.3 if is_last and si == syls.size() - 1 else 1.0)
					var onset := str(s["onset"])
					if onset != "":
						grains.append({"t": t, "id": "c_%s_%d" % [onset, rng.randi_range(0, 1)], "pitch": pm, "gain": g * 0.9, "dur": cons_ms / 1000.0, "vib": 0.0})
					var vid := "v_%s_%d" % [str(s["vowel"]), rng.randi_range(0, 1)]
					if is_granny and term == "?" and is_last and si == syls.size() - 1:
						vid = "eh"
					grains.append({"t": t + (0.018 if onset != "" else 0.0), "id": vid, "pitch": pm, "gain": g, "dur": maxf(0.05, slot_len * 0.95), "vib": 0.03 if (mood == "pleased" and is_granny) else 0.0})
					t += slot_len
					var coda := str(s["coda"])
					if coda != "" and si == syls.size() - 1 and (coda == "sibilant" or coda == "sh" or coda == "fric"):
						grains.append({"t": t - 0.01, "id": "c_%s_0" % coda, "pitch": pm, "gain": g * 0.7, "dur": 0.05, "vib": 0.0})
						t += 0.03
					syl_index += 1
			t += 0.025
			if word.ends_with(","):
				t += 0.12
			elif _ends_with_any(word, "—–-"):
				t += 0.1
			elif _ends_with_any(word, ";:"):
				t += 0.16
			elif _is_term(word) and not is_last:
				t += 0.18
		t += 0.2
	var duration := t
	var scale := 1.0
	if duration > 4.0:
		scale = 4.0 / duration
	if reduced:
		scale *= 0.5
	if scale != 1.0:
		for g2 in grains:
			g2["t"] = float(g2["t"]) * scale
			g2["dur"] = float(g2["dur"]) * maxf(scale, 0.6)
		duration *= scale
	if reduced:
		for g3 in grains:
			g3["gain"] = float(g3["gain"]) * 0.5
	return {"duration": duration, "grains": grains}


# ---------------------------------------------------------------------------------------
# Playback
# ---------------------------------------------------------------------------------------

## Starts babbling `text` as `speaker`. Returns the babble duration in seconds (0 if no bank).
func speak(line_id: String, speaker: String, text: String, seed_value: int, reduced := false, names: Array = [], mood := "") -> float:
	if not _load_bank(speaker):
		return 0.0
	var voice: Dictionary = _voices[speaker]
	var p := plan(text, voice, seed_value, reduced, names, mood)
	stop()
	_line_id = line_id
	var bank: Dictionary = _banks[speaker]
	var ps: Array = []
	for g in p["grains"]:
		if not bank.has(g["id"]):
			continue
		ps.append({"t": int(float(g["t"]) * MIX_RATE), "src": bank[g["id"]], "pitch": float(g["pitch"]), "gain": float(g["gain"]), "dur": int(float(g["dur"]) * MIX_RATE), "vib": float(g["vib"])})
	ps.sort_custom(func(a, b): return int(a["t"]) < int(b["t"]))
	_plan = ps
	_next = 0
	_pos = 0
	_active.clear()
	_end = int((float(p["duration"]) + 0.25) * MIX_RATE)
	speaking = true
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	_fill()
	return float(p["duration"])


func stop() -> void:
	if speaking:
		speaking = false
		_player.stop()
		_playback = null
		_active.clear()
		_plan.clear()


func _process(_dt: float) -> void:
	if speaking:
		_fill()


func _fill() -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(frames)
	var rel_len := int(MIX_RATE * 0.01)
	for n in frames:
		while _next < _plan.size() and int(_plan[_next]["t"]) <= _pos:
			var g: Dictionary = _plan[_next]
			var src: PackedFloat32Array = g["src"]
			var pitch := float(g["pitch"])
			var max_len := mini(int(g["dur"]) + int(MIX_RATE * 0.03), int(float(src.size() - 1) / pitch))
			_active.append({"src": src, "pos": 0.0, "step": pitch, "gain": float(g["gain"]), "len": max_len, "i": 0, "vib": float(g["vib"])})
			_next += 1
		var v := 0.0
		var k := 0
		while k < _active.size():
			var a: Dictionary = _active[k]
			var i: int = a["i"]
			var len_a: int = a["len"]
			if i >= len_a:
				_active.remove_at(k)
				continue
			var src2: PackedFloat32Array = a["src"]
			var pos: float = a["pos"]
			var j := int(pos)
			if j + 1 >= src2.size():
				_active.remove_at(k)
				continue
			var f := pos - float(j)
			var s := src2[j] + (src2[j + 1] - src2[j]) * f
			var w := 1.0
			if i > len_a - rel_len:
				w = float(len_a - i) / float(rel_len)
			v += s * float(a["gain"]) * w
			var step: float = a["step"]
			var vib: float = a["vib"]
			if vib > 0.0:
				step *= 1.0 + vib * sin(float(i) / MIX_RATE * TAU * 6.0)
			a["pos"] = pos + step
			a["i"] = i + 1
			k += 1
		v = clampf(v, -1.0, 1.0)
		buf[n] = Vector2(v, v)
		_pos += 1
	_playback.push_buffer(buf)
	if _pos >= _end and _active.is_empty() and _next >= _plan.size():
		var id := _line_id
		stop()
		finished.emit(id)
