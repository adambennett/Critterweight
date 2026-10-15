class_name LabStats
extends RefCounted
## Small statistics helpers for honest reporting: mean, sample standard deviation, standard
## error, normal-approximation 95% confidence intervals for means, and Wilson score intervals
## for win rates (well-behaved for small n and rates near 0 or 1).


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


## {n, mean, std, sem, ci95: [lo, hi]}
static func describe(xs: Array) -> Dictionary:
	var n := xs.size()
	var m := mean(xs)
	var sd := std(xs)
	var sem := sd / sqrt(float(n)) if n > 0 else 0.0
	return {"n": n, "mean": m, "std": sd, "sem": sem, "ci95": [m - 1.96 * sem, m + 1.96 * sem]}


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


## Welch's t statistic between two samples (difference of means / combined standard error).
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
