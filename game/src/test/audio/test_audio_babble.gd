extends TestCase
## The babble synthesizer runs headless (dummy audio driver): grain banks decode from the PCM
## imports, a line plans, streams through the generator without errors and finishes.


func test_babble_speaks_a_line_headless() -> void:
	var b := Babble.new()
	add_child(b)
	for sp in Audio.bank.get("voices", {}):
		b.add_voice(str(sp), Audio.bank["voices"][sp])
	check(b.has_voice("barnaby") and b.has_voice("granny"), "both voices registered")
	var finished := []
	b.finished.connect(func(id: String): finished.append(id))
	var seconds := b.speak("t1", "barnaby", "PARRIED! Timed to the hair!", 1, false, [], "")
	check(seconds > 0.5 and seconds <= 4.0, "babble duration %.2f s" % seconds)
	check(b.speaking, "speaking after speak()")
	var bank: Dictionary = b._banks.get("barnaby", {})
	check(bank.size() >= 20, "barnaby bank decoded %d grains" % bank.size())
	for gid in bank:
		var pcm: PackedFloat32Array = bank[gid]
		check(pcm.size() > 200, "grain %s has samples" % gid)
		var peak := 0.0
		for v in pcm:
			peak = maxf(peak, absf(v))
		check(peak > 0.3 and peak <= 1.0, "grain %s decoded to a sane level (%.2f)" % [gid, peak])
	await wait_frames(12)
	# with the dummy driver the mix still runs, so frames get pulled and pushed
	check(b._pos > 0 or not b.speaking, "generator consumed frames (pos=%d)" % b._pos)
	# the dummy audio driver mixes in real time, so wait on the wall clock (the suite usually
	# runs with --fixed-fps, where frames are much shorter than real time)
	var t_end := Time.get_ticks_msec() + int((seconds + 3.0) * 1000.0)
	while b.speaking and Time.get_ticks_msec() < t_end:
		await wait_frames(1)
	check(not b.speaking, "line finished within %.1f s of real time" % (seconds + 3.0))
	check(finished.has("t1"), "finished signal emitted")
	b.queue_free()
