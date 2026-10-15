class_name LabStats
extends RefCounted
## Small statistics helpers for honest reporting: mean, sample standard deviation, standard
## error, Student-t 95% confidence intervals for means (exact quantiles for small n; no interval
## at all for n < 2), a paired comparison for two conditions played on the same episodes, and
## Wilson score intervals for win rates (well-behaved for small n and rates near 0 or 1).

## Two-sided 95% Student-t quantiles t(0.975, df) for df = 1..30.
const T975: PackedFloat64Array = [12.7062, 4.3027, 3.1824, 2.7764, 2.5706, 2.4469, 2.3646, 2.3060, 2.2622, 2.2281,
	2.2010, 2.1788, 2.1604, 2.1448, 2.1314, 2.1199, 2.1098, 2.1009, 2.0930, 2.0860,
	2.0796, 2.0739, 2.0687, 2.0639, 2.0595, 2.0555, 2.0518, 2.0484, 2.0452, 2.0423]
const Z975 := 1.959963985


static func mean(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var s := 0.0
	for x in xs:
		s += float(x)
	return s / float(xs.size())


static func std(xs: Array) -> float:
	if xs.size() < 2:
		return 0.0
	var m := mean(xs)
	var s := 0.0
	for x in xs:
		s += (float(x) - m) * (float(x) - m)
	return sqrt(s / float(xs.size() - 1))


## The 0.975 quantile of Student's t with `df` degrees of freedom (the 95% two-sided critical
## value): exact table up to 30, then the Cornish-Fisher expansion around the normal quantile
## (error < 1e-4 beyond 30). INF for df < 1 (no interval can be given).
static func t975(df: int) -> float:
	if df < 1:
		return INF
	if df <= T975.size():
		return T975[df - 1]
	var z := Z975
	var z3 := z * z * z
	var z5 := z3 * z * z
	var z7 := z5 * z * z
	var z9 := z7 * z * z
	var d := float(df)
	return z + (z3 + z) / (4.0 * d) + (5.0 * z5 + 16.0 * z3 + 3.0 * z) / (96.0 * d * d) \
		+ (3.0 * z7 + 19.0 * z5 + 17.0 * z3 - 15.0 * z) / (384.0 * d * d * d) \
		+ (79.0 * z9 + 776.0 * z7 + 1482.0 * z5 - 1920.0 * z3 - 945.0 * z) / (92160.0 * d * d * d * d)


## {n, mean, std, sem, ci95: [lo, hi]} with a Student-t interval. With fewer than two values no
## interval exists: ci95 is then [] (never a zero-width interval around a single episode).
static func describe(xs: Array) -> Dictionary:
	var n := xs.size()
	var m := mean(xs)
	var sd := std(xs)
	var sem := sd / sqrt(float(n)) if n > 0 else 0.0
	var ci: Array = []
	if n >= 2:
		var h := t975(n - 1) * sem
		ci = [m - h, m + h]
	return {"n": n, "mean": m, "std": sd, "sem": sem, "ci95": ci}


## "lo..hi" for a ci95 array, or "n/a" when there is no interval (n < 2).
static func ci_text(ci, fmt := "%.2f") -> String:
	if typeof(ci) != TYPE_ARRAY or (ci as Array).size() != 2:
		return "n/a"
	return (fmt + ".." + fmt) % [float(ci[0]), float(ci[1])]


## Paired comparison of two conditions measured on the SAME episodes: a[i] and b[i] belong to
## episode i. Differences d = a − b; returns {n, mean, std, sem, ci95, t, df, significant}.
## `significant` is true when the 95% interval of the mean difference excludes 0. Episodes are the
## unit of independence here, so n is the number of episode pairs, not of individual results.
static func paired(a: Array, b: Array) -> Dictionary:
	var d := []
	for i in mini(a.size(), b.size()):
		d.append(float(a[i]) - float(b[i]))
	var s := describe(d)
	var n := int(s["n"])
	var sem := float(s["sem"])
	var t := 0.0
	if n >= 2:
		if sem > 1e-12:
			t = float(s["mean"]) / sem
		elif absf(float(s["mean"])) > 1e-12:
			# every pair differs by exactly the same amount: an exact, not a noisy, difference
			t = 1.0e6 if float(s["mean"]) > 0.0 else -1.0e6
	var ci: Array = s["ci95"]
	s["t"] = t
	s["df"] = maxi(n - 1, 0)
	s["significant"] = ci.size() == 2 and (float(ci[0]) > 0.0 or float(ci[1]) < 0.0)
	return s


## Wilson score interval for k successes in n trials. [lo, hi]
static func wilson(k: int, n: int, z := 1.96) -> Array:
	if n <= 0:
		return [0.0, 1.0]
	var p := float(k) / float(n)
	var z2 := z * z
	var denom := 1.0 + z2 / float(n)
	var centre := (p + z2 / (2.0 * float(n))) / denom
	var half := z * sqrt(p * (1.0 - p) / float(n) + z2 / (4.0 * float(n) * float(n))) / denom
	return [maxf(0.0, centre - half), minf(1.0, centre + half)]


## Welch's t statistic between two independent samples (difference of means / combined standard
## error). Kept for unpaired comparisons; conditions played on the same episodes use `paired`.
static func welch_t(a: Array, b: Array) -> float:
	if a.size() < 2 or b.size() < 2:
		return 0.0
	var va := pow(std(a), 2.0) / float(a.size())
	var vb := pow(std(b), 2.0) / float(b.size())
	var se := sqrt(va + vb)
	return (mean(a) - mean(b)) / se if se > 1e-9 else 0.0


## Total variation distance between two histograms (counts), 0 = identical distributions.
static func tvd(a: Array, b: Array) -> float:
	var sa := 0.0
	var sb := 0.0
	for x in a:
		sa += float(x)
	for x in b:
		sb += float(x)
	if sa <= 0.0 or sb <= 0.0:
		return 1.0
	var d := 0.0
	for i in mini(a.size(), b.size()):
		d += absf(float(a[i]) / sa - float(b[i]) / sb)
	return 0.5 * d
