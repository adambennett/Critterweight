extends TestCase
## LAB-01/02: the policy network — deterministic initialisation, the compiled fast path equals
## the reference implementation, and backpropagation matches finite differences.


func _rand_input(n: int, seed_value: int) -> PackedFloat32Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var x := PackedFloat32Array()
	x.resize(n)
	for i in n:
		x[i] = r.randf_range(-1.0, 1.0) if r.randf() < 0.7 else 0.0
	return x


func test_param_count_and_layout() -> void:
	check_eq(PolicyMLP.count_params(118, PackedInt32Array([32, 32]), 21), 118 * 32 + 32 + 32 * 32 + 32 + 32 * 21 + 21)
	var m := PolicyMLP.create(10, PackedInt32Array([7]), 5, "tanh", 1)
	check_eq(m.params.size(), 10 * 7 + 7 + 7 * 5 + 5)
	check_eq(m.bias_offset(0), 70, "biases follow the weight matrix")
	check_eq(m.weight_offset(1), 77)
	check(PolicyMLP.validate_arch(118, PackedInt32Array([512]), 21, "tanh") != "", "too wide rejected")
	check(PolicyMLP.validate_arch(118, PackedInt32Array([8, 8, 8, 8, 8]), 21, "tanh") != "", "too deep rejected")
	check(PolicyMLP.validate_arch(118, PackedInt32Array([32]), 21, "sigmoid") != "", "unknown activation rejected")
	check_eq(PolicyMLP.validate_arch(118, PackedInt32Array([64, 64]), 21, "relu"), "")


func test_init_is_deterministic_from_seed() -> void:
	var a := PolicyMLP.create(118, PackedInt32Array([32, 32]), 21, "tanh", 77)
	var b := PolicyMLP.create(118, PackedInt32Array([32, 32]), 21, "tanh", 77)
	var c := PolicyMLP.create(118, PackedInt32Array([32, 32]), 21, "tanh", 78)
	check(a.params == b.params, "same seed -> same weights")
	check(a.params != c.params, "different seed -> different weights")
	# biases start at zero, weights do not
	check_eq(a.params[a.bias_offset(0)], 0.0)
	check(absf(a.params[0]) > 0.0)


func test_fast_forward_matches_reference() -> void:
	for cfg in [[118, [32, 32], 21, "tanh"], [118, [64, 64], 21, "relu"], [13, [7, 5], 6, "tanh"], [5, [], 3, "tanh"], [9, [3], 2, "relu"]]:
		var m := PolicyMLP.create(int(cfg[0]), PackedInt32Array(cfg[1]), int(cfg[2]), str(cfg[3]), 5)
		# non-zero biases so the bias path is exercised too
		for l in m.layer_count():
			for o in m.dims()[l + 1]:
				m.params[m.bias_offset(l) + o] = 0.01 * float(o + 1)
		m.mark_dirty()
		for s in 4:
			var x := _rand_input(int(cfg[0]), 100 + s)
			var fast := m.forward(x)
			var slow := m.forward_naive(x)
			var worst := 0.0
			for k in fast.size():
				worst = maxf(worst, absf(fast[k] - slow[k]))
			check(worst < 1e-5, "%s: fast path within 1e-5 of reference (worst %.2e)" % [str(cfg), worst])
			check_eq(fast.size(), int(cfg[2]))


## Gradient check: L = Σ c_k · logit_k; backward(dL/dlogits = c) vs central differences.
func test_backward_matches_finite_differences() -> void:
	for act in ["tanh", "relu"]:
		var m := PolicyMLP.create(9, PackedInt32Array([6, 5]), 7, act, 11, 1.0)
		var x := _rand_input(9, 3)
		for i in x.size():
			if x[i] == 0.0:
				x[i] = 0.37
		var c := PackedFloat32Array([0.3, -1.2, 0.8, 0.05, -0.4, 1.5, -0.9])
		var g := m.make_grad()
		var cache := m.forward_cache(x)
		var dl := PackedFloat32Array()
		dl.resize(8)
		for k in 7:
			dl[k] = c[k]
		m.backward(cache, PolicyMLP.pack4(dl, 8), g)
		var grad := m.grad_to_flat(g, 1.0)
		var worst := 0.0
		var checked := 0
		var h := 1e-3
		for i in range(0, m.params.size(), 3):
			var num := _fd(m, x, c, i, h)
			var num_half := _fd(m, x, c, i, h * 0.5)
			if absf(num - num_half) > 1e-3 * maxf(1.0, absf(num)):
				continue    # a ReLU kink lies inside ±h: finite differences are meaningless there
			var err := absf(num - grad[i]) / maxf(1.0, absf(num) + absf(grad[i]))
			worst = maxf(worst, err)
			checked += 1
		check(checked > 20, "checked %d parameters" % checked)
		check(worst < 2e-3, "%s: analytic gradient matches finite differences (worst relative error %.6f)" % [act, worst])


func _fd(m: PolicyMLP, x: PackedFloat32Array, c: PackedFloat32Array, i: int, h: float) -> float:
	var orig := m.params[i]
	m.params[i] = orig + h
	var lp := _dot(m.forward_naive(x), c)
	m.params[i] = orig - h
	var lm := _dot(m.forward_naive(x), c)
	m.params[i] = orig
	m.mark_dirty()
	return (lp - lm) / (2.0 * h)


func _dot(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var s := 0.0
	for k in b.size():
		s += a[k] * b[k]
	return s


func test_es_noise_is_reproducible() -> void:
	var a := LabES.noise(1234, 50)
	var b := LabES.noise(1234, 50)
	check(a == b, "same seed -> same perturbation (helper processes rebuild candidates from seeds)")
	var base := PackedFloat32Array()
	base.resize(50)
	var plus := LabES.perturbed(base, 1234, 1.0, 0.1)
	var minus := LabES.perturbed(base, 1234, -1.0, 0.1)
	check_near(plus[7], -minus[7], 1e-7, "antithetic pair")
	check_near(plus[7], 0.1 * a[7], 1e-7)


func test_centered_ranks() -> void:
	var r := LabES.centered_ranks(PackedFloat32Array([10.0, -5.0, 3.0, 3.0]))
	check_near(r[1], -0.5, 1e-6, "worst -> -0.5")
	check_near(r[0], 0.5, 1e-6, "best -> +0.5")
	check_near(r[2], r[3], 1e-6, "ties share a rank")
	var s := 0.0
	for x in r:
		s += x
	check_near(s, 0.0, 1e-5, "centered")


## Pure optimisation sanity check: ES climbs a smooth synthetic objective.
func test_es_optimises_a_synthetic_objective() -> void:
	var target := PackedFloat32Array()
	var r := RandomNumberGenerator.new()
	r.seed = 9
	for i in 40:
		target.append(r.randf_range(-1.0, 1.0))
	var es := LabES.new()
	var start := PackedFloat32Array()
	start.resize(40)
	es.setup(start, 10, 0.1, 0.05, 0.0, 3)
	var f0 := _score(es.theta, target)
	for gen in 60:
		var fit := PackedFloat32Array()
		for k in es.population():
			var spec := es.candidate_spec(gen, k)
			fit.append(_score(LabES.perturbed(es.theta, int(spec["noise_seed"]), float(spec["sign"]), es.sigma), target))
		es.update(gen, fit)
	var f1 := _score(es.theta, target)
	check(f1 > f0 * 0.25, "objective improved from %.2f to %.2f" % [f0, f1])
	# a tie (no information) must not move the parameters
	var before := es.theta.duplicate()
	var flat := PackedFloat32Array()
	flat.resize(es.population())
	var st := es.update(99, flat)
	check(bool(st.get("no_signal", false)) and es.theta == before, "no step without signal")


func _score(theta: PackedFloat32Array, target: PackedFloat32Array) -> float:
	var s := 0.0
	for i in theta.size():
		s -= (theta[i] - target[i]) * (theta[i] - target[i])
	return s
