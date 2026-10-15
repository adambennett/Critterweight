class_name LabES
extends RefCounted
## OpenAI-style evolution strategies (Salimans et al. 2017) on the flat policy parameters:
##  * antithetic (mirrored) Gaussian perturbations θ ± σ·ε, ε regenerated from per-pair seeds
##    (so worker processes rebuild the same candidates from θ + seeds; nothing large is shipped),
##  * centered-rank fitness shaping (robust to reward scale and outliers),
##  * gradient estimate g = Σ_pairs (r⁺ − r⁻)·ε / (2·n·σ),
##  * Adam ascent on θ with decoupled weight decay (AdamW); no step when all candidates tie.
## Why ES here: episodes are long, rewards sparse/delayed and the physics is non-differentiable;
## ES needs only episode returns, parallelises trivially across processes, has few
## hyper-parameters and works with the deterministic (argmax) policies used in matches.

var theta := PackedFloat32Array()
var m := PackedFloat32Array()
var v := PackedFloat32Array()
var adam_t := 0
var sigma := 0.05
var lr := 0.03
var l2 := 0.005
var pairs := 12
var seed_base := 1
var beta1 := 0.9
var beta2 := 0.999
var eps := 1e-8


func setup(initial: PackedFloat32Array, p_pairs: int, p_sigma: float, p_lr: float, p_l2: float, p_seed: int) -> void:
	theta = initial.duplicate()
	m = PackedFloat32Array()
	m.resize(theta.size())
	v = PackedFloat32Array()
	v.resize(theta.size())
	adam_t = 0
	pairs = p_pairs
	sigma = p_sigma
	lr = p_lr
	l2 = p_l2
	seed_base = p_seed


func noise_seed(gen: int, pair: int) -> int:
	return int(MathX.hash32("es-noise:%d:%d:%d" % [seed_base, gen, pair]) & 0x7FFFFFFF)


static func noise(seed_value: int, n: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var e := PackedFloat32Array()
	e.resize(n)
	for i in n:
		e[i] = rng.randfn(0.0, 1.0)
	return e


## Parameters of a perturbed candidate: base + sign·σ·ε(seed).
static func perturbed(base: PackedFloat32Array, seed_value: int, sign: float, p_sigma: float) -> PackedFloat32Array:
	var e := noise(seed_value, base.size())
	var out := base.duplicate()
	var s := sign * p_sigma
	for i in out.size():
		out[i] += s * e[i]
	return out


## Candidate k of generation `gen`: pair k/2, sign + for even k and − for odd k.
func candidate_spec(gen: int, k: int) -> Dictionary:
	return {"noise_seed": noise_seed(gen, k >> 1), "sign": 1.0 if k % 2 == 0 else -1.0, "sigma": sigma}


func population() -> int:
	return pairs * 2


## Centered ranks in [-0.5, 0.5] (ties share the mean rank).
static func centered_ranks(f: PackedFloat32Array) -> PackedFloat32Array:
	var n := f.size()
	var idx := []
	for i in n:
		idx.append(i)
	idx.sort_custom(func(a, b): return f[a] < f[b])
	var ranks := PackedFloat32Array()
	ranks.resize(n)
	var i := 0
	while i < n:
		var j := i
		while j + 1 < n and f[idx[j + 1]] == f[idx[i]]:
			j += 1
		var r := (float(i) + float(j)) * 0.5
		for k in range(i, j + 1):
			ranks[idx[k]] = r
		i = j + 1
	var out := PackedFloat32Array()
	out.resize(n)
	for k in n:
		out[k] = ranks[k] / float(maxi(n - 1, 1)) - 0.5 if n > 1 else 0.0
	return out


## Applies one ES step from the fitness of every candidate of `gen` (index = candidate k).
## Returns {grad_norm, step_norm, theta_norm}.
func update(gen: int, fitness: PackedFloat32Array) -> Dictionary:
	var n := theta.size()
	var shaped := centered_ranks(fitness)
	var any_signal := false
	for p in pairs:
		if shaped[2 * p] != shaped[2 * p + 1]:
			any_signal = true
			break
	if not any_signal:
		# every mirrored pair tied: no information, so no step (Adam would otherwise turn
		# numerical noise into full-size steps)
		return {"grad_norm": 0.0, "step_norm": 0.0, "theta_norm": _norm(theta), "no_signal": true}
	var g := PackedFloat32Array()
	g.resize(n)
	for p in pairs:
		var w := shaped[2 * p] - shaped[2 * p + 1]
		if w == 0.0:
			continue
		var e := noise(noise_seed(gen, p), n)
		for i in n:
			g[i] += w * e[i]
	var scale := 1.0 / (float(2 * pairs) * sigma)
	adam_t += 1
	var b1t := 1.0 - pow(beta1, adam_t)
	var b2t := 1.0 - pow(beta2, adam_t)
	var gn := 0.0
	var sn := 0.0
	var tn := 0.0
	var decay := 1.0 - lr * l2
	for i in n:
		var gi := g[i] * scale
		gn += gi * gi
		m[i] = beta1 * m[i] + (1.0 - beta1) * gi
		v[i] = beta2 * v[i] + (1.0 - beta2) * gi * gi
		var step := lr * (m[i] / b1t) / (sqrt(v[i] / b2t) + eps)
		# decoupled weight decay (AdamW): shrinks weights without being normalised by Adam
		theta[i] = theta[i] * decay + step
		sn += step * step
		tn += theta[i] * theta[i]
	return {"grad_norm": sqrt(gn), "step_norm": sqrt(sn), "theta_norm": sqrt(tn)}


static func _norm(a: PackedFloat32Array) -> float:
	var s := 0.0
	for x in a:
		s += x * x
	return sqrt(s)


func to_dict() -> Dictionary:
	return {"theta": LabIO.b64_floats(theta), "m": LabIO.b64_floats(m), "v": LabIO.b64_floats(v), "adam_t": adam_t,
		"sigma": sigma, "lr": lr, "l2": l2, "pairs": pairs, "seed_base": seed_base}


func from_dict(d: Dictionary) -> bool:
	var th := LabIO.floats_b64(str(d.get("theta", "")))
	var mm := LabIO.floats_b64(str(d.get("m", "")))
	var vv := LabIO.floats_b64(str(d.get("v", "")))
	if th.is_empty() or mm.size() != th.size() or vv.size() != th.size():
		return false
	theta = th
	m = mm
	v = vv
	adam_t = int(d.get("adam_t", 0))
	sigma = float(d.get("sigma", sigma))
	lr = float(d.get("lr", lr))
	l2 = float(d.get("l2", l2))
	pairs = int(d.get("pairs", pairs))
	seed_base = int(d.get("seed_base", seed_base))
	return true
