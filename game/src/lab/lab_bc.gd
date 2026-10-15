class_name LabBC
extends RefCounted
## Behaviour cloning: supervised learning of act_v1 from recorded (obs_v1, action) pairs.
## Loss = cross-entropy(move head) + cross-entropy(button head, masked to the creature's
## buttons, optionally class-balanced); minibatch Adam with L2; early stopping on validation
## loss keeps the best weights.
## Split: whole recorded episodes (PolicyDataset split units: copies of an episode share one) go
## to training, validation (early stopping only) or test (reported accuracy only) — so no
## episode is in two splits, nothing is ever trained on validation or test data, and the
## reported accuracy comes from episodes that influenced neither the weights nor the stopping
## point. A dataset needs at least MIN_EPISODES episodes for that; smaller ones are refused.
## Why BC here: it learns a playstyle directly from a human or bot in minutes of recorded play,
## needs no reward design, and gives a strong starting point for ES fine-tuning (BC→ES).
## Training runs in small time slices (`train_steps`) so the worker stays responsive.

const MIN_EPISODES := 6

var net: PolicyMLP
var x := PackedFloat32Array()
var moves := PackedByteArray()
var buttons := PackedByteArray()
var units := PackedInt32Array()
var train_idx := PackedInt32Array()
var val_idx := PackedInt32Array()
var test_idx := PackedInt32Array()
## {mode, episodes, train/val/test episodes and samples}; "" error when the split was refused
var split_info := {}
var mask := PackedByteArray()
var button_w := PackedFloat32Array()
var lr := 0.003
var l2 := 0.0001
var batch := 128
var rng := RandomNumberGenerator.new()
var adam_m := PackedFloat32Array()
var adam_v := PackedFloat32Array()
var adam_t := 0
var epoch := 0
var best_val := INF
var best_epoch := 0
var best_params := PackedFloat32Array()
var bad_epochs := 0
var samples_seen := 0

var _order := PackedInt32Array()
var _pos := 0
var _loss_sum := 0.0
var _loss_n := 0
var _grad: PolicyMLP.Grad


## Prepares training. Returns "" or why the data cannot be split honestly (too few episodes).
func setup(data: Dictionary, p_net: PolicyMLP, p_mask: PackedByteArray, opts: Dictionary) -> String:
	net = p_net
	x = data["obs"]
	moves = data["moves"]
	buttons = data["buttons"]
	units = data["units"]
	mask = p_mask.duplicate()
	lr = float(opts.get("lr", 0.003))
	l2 = float(opts.get("l2", 0.0001))
	batch = int(opts.get("batch", 128))
	rng.seed = int(opts.get("seed", 1))
	adam_m = PackedFloat32Array()
	adam_m.resize(net.params.size())
	adam_v = PackedFloat32Array()
	adam_v.resize(net.params.size())
	adam_t = 0
	best_params = net.params.duplicate()
	button_w = PackedFloat32Array()
	button_w.resize(PolicyActions.BUTTON_COUNT)
	button_w.fill(1.0)
	if bool(opts.get("balance", false)):
		var counts := PackedInt32Array()
		counts.resize(PolicyActions.BUTTON_COUNT)
		for b in buttons:
			counts[b] += 1
		var used := 0
		for c in counts:
			if c > 0:
				used += 1
		for k in PolicyActions.BUTTON_COUNT:
			if counts[k] > 0:
				button_w[k] = clampf(sqrt(float(buttons.size()) / (float(used) * float(counts[k]))), 0.2, 5.0)
	_grad = net.make_grad()
	return split(float(opts.get("val_frac", 0.2)), float(opts.get("test_frac", 0.2)), int(opts.get("seed", 1)))


func sample_count() -> int:
	return moves.size()


## Episode-level split: a seeded shuffle of the split units; the first `val_frac` of them
## validate (early stopping), the next `test_frac` test (reported only), the rest train. Each
## part gets at least one episode and training keeps at least half of them. Returns "" or the
## reason the split was refused (fewer than MIN_EPISODES episodes) — there is no fallback that
## would put parts of one episode into different splits or train on held-out data.
func split(val_frac: float, test_frac: float, seed_value: int) -> String:
	var n := moves.size()
	var unit_ids := {}
	for k in n:
		unit_ids[units[k]] = true
	var keys: Array = unit_ids.keys()
	train_idx = PackedInt32Array()
	val_idx = PackedInt32Array()
	test_idx = PackedInt32Array()
	split_info = {"mode": "episodes", "episodes": keys.size(), "min_episodes": MIN_EPISODES}
	if keys.size() < MIN_EPISODES:
		split_info["error"] = "only %d recorded episode(s): behaviour cloning needs at least %d, so whole episodes can be held out for validation and testing — record a few more matches" % [keys.size(), MIN_EPISODES]
		return str(split_info["error"])
	keys.sort()
	var r := RandomNumberGenerator.new()
	r.seed = seed_value * 31 + 7
	_shuffle(keys, r)
	var u := keys.size()
	var nval := maxi(1, int(round(float(u) * clampf(val_frac, 0.0, 0.5))))
	var ntest := maxi(1, int(round(float(u) * clampf(test_frac, 0.0, 0.5))))
	while nval + ntest > u / 2:
		if ntest >= nval and ntest > 1:
			ntest -= 1
		elif nval > 1:
			nval -= 1
		else:
			break
	var part := {}
	for i in u:
		part[keys[i]] = 1 if i < nval else (2 if i < nval + ntest else 0)
	for k in n:
		match int(part[units[k]]):
			1:
				val_idx.append(k)
			2:
				test_idx.append(k)
			_:
				train_idx.append(k)
	split_info["train_episodes"] = u - nval - ntest
	split_info["val_episodes"] = nval
	split_info["test_episodes"] = ntest
	split_info["train_samples"] = train_idx.size()
	split_info["val_samples"] = val_idx.size()
	split_info["test_samples"] = test_idx.size()
	return ""


static func _shuffle(a: Array, r: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func start_epoch() -> void:
	_order = train_idx.duplicate()
	for i in range(_order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := _order[i]
		_order[i] = _order[j]
		_order[j] = t
	_pos = 0
	_loss_sum = 0.0
	_loss_n = 0


func epoch_progress() -> float:
	return float(_pos) / float(maxi(_order.size(), 1))


## Loss and dLoss/dLogits (packed) for one sample. Returns [loss, dlogits].
func _sample_grad(logits4: PackedVector4Array, k: int, scale: float) -> Array:
	var logits := PolicyMLP.unpack4(logits4, PolicyActions.OUTPUTS)
	var all_moves := PackedByteArray()
	var pm := PolicyActions.head_probs(logits, 0, PolicyActions.MOVE_COUNT, all_moves)
	var pb := PolicyActions.head_probs(logits, PolicyActions.MOVE_COUNT, PolicyActions.BUTTON_COUNT, mask)
	var ym := int(moves[k])
	var yb := int(buttons[k])
	var wb := button_w[yb]
	var loss := -log(maxf(pm[ym], 1e-7)) - wb * log(maxf(pb[yb], 1e-7))
	var d := PackedFloat32Array()
	d.resize(logits4.size() * 4)
	for c in PolicyActions.MOVE_COUNT:
		d[c] = (pm[c] - (1.0 if c == ym else 0.0)) * scale
	for c in PolicyActions.BUTTON_COUNT:
		if mask[c] == 0:
			continue
		d[PolicyActions.MOVE_COUNT + c] = wb * (pb[c] - (1.0 if c == yb else 0.0)) * scale
	return [loss, PolicyMLP.pack4(d, d.size())]


## Runs minibatches for up to `budget_ms`. Returns true when the epoch's data is exhausted.
func train_steps(budget_ms: float) -> bool:
	var t0 := Time.get_ticks_usec()
	var dim := net.inputs
	while _pos < _order.size():
		var end := mini(_pos + batch, _order.size())
		var bs := end - _pos
		var scale := 1.0 / float(bs)
		_grad.zero()
		for q in range(_pos, end):
			var k := _order[q]
			var cache := net.forward_cache(x.slice(k * dim, (k + 1) * dim))
			var lg: Array = _sample_grad(cache[cache.size() - 1], k, scale)
			_loss_sum += float(lg[0])
			_loss_n += 1
			net.backward(cache, lg[1], _grad)
		_apply(net.grad_to_flat(_grad, 1.0))
		samples_seen += bs
		_pos = end
		if float(Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	return _pos >= _order.size()


func _apply(g: PackedFloat32Array) -> void:
	adam_t += 1
	var b1 := 0.9
	var b2 := 0.999
	var b1t := 1.0 - pow(b1, adam_t)
	var b2t := 1.0 - pow(b2, adam_t)
	var p := net.params
	for i in p.size():
		var gi := g[i] + l2 * p[i]
		adam_m[i] = b1 * adam_m[i] + (1.0 - b1) * gi
		adam_v[i] = b2 * adam_v[i] + (1.0 - b2) * gi * gi
		p[i] -= lr * (adam_m[i] / b1t) / (sqrt(adam_v[i] / b2t) + 1e-8)
	net.mark_dirty()


func train_loss() -> float:
	return _loss_sum / float(maxi(_loss_n, 1))


## Mean loss and accuracies (argmax, masked) on a subset.
func evaluate(idx: PackedInt32Array) -> Dictionary:
	var dim := net.inputs
	var loss := 0.0
	var am := 0
	var ab := 0
	var aj := 0
	var all_moves := PackedByteArray()
	for k in idx:
		var logits := net.forward(x.slice(k * dim, (k + 1) * dim))
		var pm := PolicyActions.head_probs(logits, 0, PolicyActions.MOVE_COUNT, all_moves)
		var pb := PolicyActions.head_probs(logits, PolicyActions.MOVE_COUNT, PolicyActions.BUTTON_COUNT, mask)
		var ym := int(moves[k])
		var yb := int(buttons[k])
		loss += -log(maxf(pm[ym], 1e-7)) - log(maxf(pb[yb], 1e-7))
		var mm := PolicyActions.choose(logits, 0, PolicyActions.MOVE_COUNT, all_moves, "argmax", 1.0, null)
		var mb := PolicyActions.choose(logits, PolicyActions.MOVE_COUNT, PolicyActions.BUTTON_COUNT, mask, "argmax", 1.0, null)
		if mm == ym:
			am += 1
		if mb == yb:
			ab += 1
		if mm == ym and mb == yb:
			aj += 1
	var n := float(maxi(idx.size(), 1))
	return {"n": idx.size(), "loss": loss / n, "acc_move": am / n, "acc_button": ab / n, "acc_joint": aj / n}


## Accuracy of always predicting the most common training label (per head) on `idx`.
func majority_baseline(idx: PackedInt32Array) -> Dictionary:
	var cm := PackedInt32Array()
	cm.resize(PolicyActions.MOVE_COUNT)
	var cb := PackedInt32Array()
	cb.resize(PolicyActions.BUTTON_COUNT)
	for k in train_idx:
		cm[moves[k]] += 1
		cb[buttons[k]] += 1
	var bm := 0
	var bb := 0
	for c in PolicyActions.MOVE_COUNT:
		if cm[c] > cm[bm]:
			bm = c
	for c in PolicyActions.BUTTON_COUNT:
		if cb[c] > cb[bb]:
			bb = c
	var hm := 0
	var hb := 0
	var hj := 0
	for k in idx:
		var okm := int(moves[k]) == bm
		var okb := int(buttons[k]) == bb
		if okm:
			hm += 1
		if okb:
			hb += 1
		if okm and okb:
			hj += 1
	var n := float(maxi(idx.size(), 1))
	return {"acc_move": hm / n, "acc_button": hb / n, "acc_joint": hj / n, "move_class": bm, "button_class": bb}


## Label histograms (move 9 + button 12) over a subset — the teacher's action distribution.
func label_hist(idx: PackedInt32Array) -> Array:
	var h := []
	h.resize(PolicyActions.OUTPUTS)
	h.fill(0)
	for k in idx:
		h[moves[k]] += 1
		h[PolicyActions.MOVE_COUNT + buttons[k]] += 1
	return h


## Called after each epoch with validation metrics; tracks the best weights. Returns true if
## training should stop early.
func end_epoch(val: Dictionary, patience: int) -> bool:
	epoch += 1
	var vl := float(val["loss"])
	if vl < best_val - 1e-4:
		best_val = vl
		best_epoch = epoch
		best_params = net.params.duplicate()
		bad_epochs = 0
	else:
		bad_epochs += 1
	return bad_epochs >= patience


func to_dict() -> Dictionary:
	return {"params": LabIO.b64_floats(net.params), "m": LabIO.b64_floats(adam_m), "v": LabIO.b64_floats(adam_v), "adam_t": adam_t,
		"epoch": epoch, "best_val": best_val if is_finite(best_val) else 1e30, "best_epoch": best_epoch,
		"best_params": LabIO.b64_floats(best_params), "bad_epochs": bad_epochs, "samples_seen": samples_seen,
		"rng_state": str(rng.state)}


func from_dict(d: Dictionary) -> bool:
	var p := LabIO.floats_b64(str(d.get("params", "")))
	var mm := LabIO.floats_b64(str(d.get("m", "")))
	var vv := LabIO.floats_b64(str(d.get("v", "")))
	var bp := LabIO.floats_b64(str(d.get("best_params", "")))
	if p.size() != net.params.size() or mm.size() != p.size() or vv.size() != p.size() or bp.size() != p.size():
		return false
	net.set_params(p)
	adam_m = mm
	adam_v = vv
	adam_t = int(d.get("adam_t", 0))
	epoch = int(d.get("epoch", 0))
	best_val = float(d.get("best_val", INF))
	best_epoch = int(d.get("best_epoch", 0))
	best_params = bp
	bad_epochs = int(d.get("bad_epochs", 0))
	samples_seen = int(d.get("samples_seen", 0))
	rng.state = int(str(d.get("rng_state", "0")))
	_grad = net.make_grad()
	return true
