class_name PolicyMLP
extends RefCounted
## Small multilayer perceptron in pure GDScript (no native plugins, no GPU): inputs -> hidden
## layers (tanh | relu) -> linear output logits. Used for inference in matches and for both
## training approaches in the AI Lab worker.
##
## Parameter layout (the flat `params` vector, also the serialization order): for each layer l,
## the weight matrix W_l row-major [out][in], followed by the bias vector b_l [out].
##
## Speed: GDScript loops are slow, so the forward pass is "compiled" into 4x4 Projection blocks
## (one native matrix-vector product = 16 multiply-adds per interpreted operation) over
## Vector4-packed activations: ~7x faster than scalar loops (docs/AI_LAB.md "Inference budget").
## `forward_naive` is the readable reference implementation used by the tests.
## Invariant: after changing `params` call `set_params` (or `mark_dirty`) so the compiled blocks
## are rebuilt before the next forward pass.

const MAX_HIDDEN_LAYERS := 4
const MAX_WIDTH := 256
const MAX_PARAMS := 250000
const ACTIVATIONS: PackedStringArray = ["tanh", "relu"]

var inputs := 0
var outputs := 0
var hidden := PackedInt32Array()
var activation := "tanh"
var params := PackedFloat32Array()

var _dims := PackedInt32Array()      ## [inputs, h1, ..., outputs]
var _w_off := PackedInt32Array()
var _b_off := PackedInt32Array()
var _nib := PackedInt32Array()
var _nob := PackedInt32Array()
var _blocks: Array = []              ## per layer: Array[Projection], index ob * nib + ib
var _blocks_t: Array = []            ## per layer: transposed blocks (training only)
var _bias4: Array = []               ## per layer: PackedVector4Array
var _compiled := false
var _compiled_t := false
var _relu := false


static func count_params(n_in: int, hid: PackedInt32Array, n_out: int) -> int:
	var total := 0
	var prev := n_in
	for h in hid:
		total += prev * h + h
		prev = h
	total += prev * n_out + n_out
	return total


## Returns "" when the architecture is acceptable, else a human-readable reason.
static func validate_arch(n_in: int, hid: PackedInt32Array, n_out: int, act: String) -> String:
	if n_in < 1 or n_in > 1024:
		return "input size %d out of range" % n_in
	if n_out < 1 or n_out > 256:
		return "output size %d out of range" % n_out
	if hid.size() > MAX_HIDDEN_LAYERS:
		return "too many hidden layers (%d > %d)" % [hid.size(), MAX_HIDDEN_LAYERS]
	for h in hid:
		if h < 1 or h > MAX_WIDTH:
			return "hidden width %d out of range 1..%d" % [h, MAX_WIDTH]
	if not ACTIVATIONS.has(act):
		return "unknown activation '%s'" % act
	if count_params(n_in, hid, n_out) > MAX_PARAMS:
		return "too many parameters (%d > %d)" % [count_params(n_in, hid, n_out), MAX_PARAMS]
	return ""


static func create(n_in: int, hid: PackedInt32Array, n_out: int, act: String, seed_value: int, out_scale := 0.1) -> PolicyMLP:
	var m := PolicyMLP.new()
	m.configure(n_in, hid, n_out, act)
	m.init_params(seed_value, out_scale)
	return m


func configure(n_in: int, hid: PackedInt32Array, n_out: int, act: String) -> void:
	inputs = n_in
	outputs = n_out
	hidden = hid.duplicate()
	activation = act
	_relu = act == "relu"
	_dims = PackedInt32Array([n_in])
	_dims.append_array(hid)
	_dims.append(n_out)
	_w_off.clear()
	_b_off.clear()
	var off := 0
	for l in _dims.size() - 1:
		_w_off.append(off)
		off += _dims[l] * _dims[l + 1]
		_b_off.append(off)
		off += _dims[l + 1]
	params.resize(off)
	_compiled = false
	_compiled_t = false


func param_total() -> int:
	return params.size()


func layer_count() -> int:
	return _dims.size() - 1


func dims() -> PackedInt32Array:
	return _dims.duplicate()


func weight_offset(layer: int) -> int:
	return _w_off[layer]


func bias_offset(layer: int) -> int:
	return _b_off[layer]


## Deterministic initialisation from a seed: Glorot-style normal for tanh, He for relu, zero
## biases; the output layer is scaled by `out_scale` (0.1 = near-uniform initial action
## distribution, good for imitation; ~1 gives evolution strategies decisive random policies).
func init_params(seed_value: int, out_scale := 0.1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	params.fill(0.0)
	var last := _dims.size() - 2
	for l in _dims.size() - 1:
		var fan_in := _dims[l]
		var std := sqrt(2.0 / float(fan_in)) if _relu else 1.0 / sqrt(float(fan_in))
		if l == last:
			std *= out_scale
		var n := _dims[l] * _dims[l + 1]
		var wo := _w_off[l]
		for k in n:
			params[wo + k] = rng.randfn(0.0, std)
	_compiled = false
	_compiled_t = false


func set_params(p: PackedFloat32Array) -> void:
	assert(p.size() == params.size())
	params = p
	_compiled = false
	_compiled_t = false


func mark_dirty() -> void:
	_compiled = false
	_compiled_t = false


func clone() -> PolicyMLP:
	var m := PolicyMLP.new()
	m.configure(inputs, hidden, outputs, activation)
	m.params = params.duplicate()
	return m


# =====================================================================================
# Compiled (fast) forward
# =====================================================================================

func compile() -> void:
	_blocks.clear()
	_bias4.clear()
	_nib.clear()
	_nob.clear()
	for l in _dims.size() - 1:
		var nin := _dims[l]
		var nout := _dims[l + 1]
		var nib := (nin + 3) >> 2
		var nob := (nout + 3) >> 2
		_nib.append(nib)
		_nob.append(nob)
		var wo := _w_off[l]
		var blocks: Array[Projection] = []
		blocks.resize(nob * nib)
		for ob in nob:
			for ib in nib:
				var c0 := Vector4()
				var c1 := Vector4()
				var c2 := Vector4()
				var c3 := Vector4()
				for r in 4:
					var o := ob * 4 + r
					if o >= nout:
						break
					var row := wo + o * nin + ib * 4
					var i0 := ib * 4
					c0[r] = params[row] if i0 < nin else 0.0
					c1[r] = params[row + 1] if i0 + 1 < nin else 0.0
					c2[r] = params[row + 2] if i0 + 2 < nin else 0.0
					c3[r] = params[row + 3] if i0 + 3 < nin else 0.0
				blocks[ob * nib + ib] = Projection(c0, c1, c2, c3)
		_blocks.append(blocks)
		var b4 := PackedVector4Array()
		b4.resize(nob)
		var bo := _b_off[l]
		for ob in nob:
			var v := Vector4()
			for r in 4:
				var o := ob * 4 + r
				if o < nout:
					v[r] = params[bo + o]
			b4[ob] = v
		_bias4.append(b4)
	_compiled = true


static func pack4(x: PackedFloat32Array, n: int) -> PackedVector4Array:
	var nb := (n + 3) >> 2
	var out := PackedVector4Array()
	out.resize(nb)
	var full := n >> 2
	for b in full:
		var i := b * 4
		out[b] = Vector4(x[i], x[i + 1], x[i + 2], x[i + 3])
	if nb > full:
		var v := Vector4()
		for r in n - full * 4:
			v[r] = x[full * 4 + r]
		out[full] = v
	return out


static func unpack4(v: PackedVector4Array, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = v[i >> 2][i & 3]
	return out


func _activate(y: PackedVector4Array) -> void:
	if _relu:
		for i in y.size():
			y[i] = y[i].maxf(0.0)
	else:
		for i in y.size():
			var v := y[i]
			y[i] = Vector4(tanh(v.x), tanh(v.y), tanh(v.z), tanh(v.w))


func _layer(l: int, a: PackedVector4Array) -> PackedVector4Array:
	var blocks: Array[Projection] = _blocks[l]
	var b4: PackedVector4Array = _bias4[l]
	var nib := _nib[l]
	var nob := _nob[l]
	var y := PackedVector4Array()
	y.resize(nob)
	var k := 0
	for ob in nob:
		var acc := b4[ob]
		for ib in nib:
			acc += blocks[k] * a[ib]
			k += 1
		y[ob] = acc
	return y


## First layer skipping all-zero input blocks (observations are sparse: one-hot states,
## history and absent projectiles/statuses). Adding exact zeros changes nothing, so the result
## is identical to the dense product.
func _layer_sparse(l: int, a: PackedVector4Array) -> PackedVector4Array:
	var nib := _nib[l]
	var nz := PackedInt32Array()
	for ib in nib:
		if a[ib] != Vector4.ZERO:
			nz.append(ib)
	var blocks: Array[Projection] = _blocks[l]
	var b4: PackedVector4Array = _bias4[l]
	var nob := _nob[l]
	var y := PackedVector4Array()
	y.resize(nob)
	for ob in nob:
		var acc := b4[ob]
		var base := ob * nib
		for ib in nz:
			acc += blocks[base + ib] * a[ib]
		y[ob] = acc
	return y


## Logits for one observation (fast path).
func forward(x: PackedFloat32Array) -> PackedFloat32Array:
	if not _compiled:
		compile()
	var a := pack4(x, inputs)
	var n_layers := _dims.size() - 1
	for l in n_layers:
		a = _layer_sparse(l, a) if l == 0 else _layer(l, a)
		if l < n_layers - 1:
			_activate(a)
	return unpack4(a, outputs)


## Reference implementation (scalar loops), used by tests to validate the fast path.
func forward_naive(x: PackedFloat32Array) -> PackedFloat32Array:
	var a := x.duplicate()
	var n_layers := _dims.size() - 1
	for l in n_layers:
		var nin := _dims[l]
		var nout := _dims[l + 1]
		var y := PackedFloat32Array()
		y.resize(nout)
		for o in nout:
			var acc := params[_b_off[l] + o]
			var row := _w_off[l] + o * nin
			for i in nin:
				acc += params[row + i] * a[i]
			if l < n_layers - 1:
				acc = maxf(acc, 0.0) if _relu else tanh(acc)
			y[o] = acc
		a = y
	return a


# =====================================================================================
# Training support (behaviour cloning): cached forward + backward with gradient accumulation
# =====================================================================================

## Per-layer gradient accumulators in block layout (fast to accumulate, converted on demand).
class Grad:
	extends RefCounted
	var gcols: Array = []     ## per layer PackedVector4Array (nob * nib * 4 columns)
	var gb: Array = []        ## per layer PackedVector4Array (nob)

	func zero() -> void:
		for l in gcols.size():
			(gcols[l] as PackedVector4Array).fill(Vector4())
			(gb[l] as PackedVector4Array).fill(Vector4())


func make_grad() -> Grad:
	if not _compiled:
		compile()
	var g := Grad.new()
	for l in _dims.size() - 1:
		var gc := PackedVector4Array()
		gc.resize(_nob[l] * _nib[l] * 4)
		g.gcols.append(gc)
		var gbb := PackedVector4Array()
		gbb.resize(_nob[l])
		g.gb.append(gbb)
	return g


func _compile_transposed() -> void:
	if not _compiled:
		compile()
	_blocks_t.clear()
	for l in _dims.size() - 1:
		var blocks: Array[Projection] = _blocks[l]
		var bt: Array[Projection] = []
		bt.resize(blocks.size())
		for k in blocks.size():
			var p := blocks[k]
			bt[k] = Projection(Vector4(p.x.x, p.y.x, p.z.x, p.w.x), Vector4(p.x.y, p.y.y, p.z.y, p.w.y),
				Vector4(p.x.z, p.y.z, p.z.z, p.w.z), Vector4(p.x.w, p.y.w, p.z.w, p.w.w))
		_blocks_t.append(bt)
	_compiled_t = true


## Forward pass keeping every layer's (post-activation) output: [a0, a1, ..., logits].
func forward_cache(x: PackedFloat32Array) -> Array:
	if not _compiled:
		compile()
	var cache: Array = []
	var a := pack4(x, inputs)
	cache.append(a)
	var n_layers := _dims.size() - 1
	for l in n_layers:
		a = _layer(l, a)
		if l < n_layers - 1:
			_activate(a)
		cache.append(a)
	return cache


## Accumulates dLoss/dParams for one sample into `g`, given dLoss/dLogits (packed, size of the
## last layer's block count).
func backward(cache: Array, dlogits: PackedVector4Array, g: Grad) -> void:
	if not _compiled_t:
		_compile_transposed()
	var dy := dlogits
	var n_layers := _dims.size() - 1
	for l in range(n_layers - 1, -1, -1):
		var a_in: PackedVector4Array = cache[l]
		var nib := _nib[l]
		var nob := _nob[l]
		var gc: PackedVector4Array = g.gcols[l]
		var gbb: PackedVector4Array = g.gb[l]
		for ob in nob:
			var d := dy[ob]
			if d == Vector4.ZERO:
				continue
			gbb[ob] += d
			var base := ob * nib * 4
			for ib in nib:
				var xa := a_in[ib]
				var c := base + ib * 4
				gc[c] += d * xa.x
				gc[c + 1] += d * xa.y
				gc[c + 2] += d * xa.z
				gc[c + 3] += d * xa.w
		if l == 0:
			break
		var bt: Array[Projection] = _blocks_t[l]
		var dx := PackedVector4Array()
		dx.resize(nib)
		var k := 0
		for ob in nob:
			var d2 := dy[ob]
			if d2 == Vector4.ZERO:
				k += nib
				continue
			for ib in nib:
				dx[ib] += bt[k] * d2
				k += 1
		# through the activation that produced a_in
		if _relu:
			for ib in nib:
				var av := a_in[ib]
				dx[ib] = Vector4(dx[ib].x if av.x > 0.0 else 0.0, dx[ib].y if av.y > 0.0 else 0.0,
					dx[ib].z if av.z > 0.0 else 0.0, dx[ib].w if av.w > 0.0 else 0.0)
		else:
			for ib in nib:
				var av2 := a_in[ib]
				dx[ib] = dx[ib] * (Vector4.ONE - av2 * av2)
		dy = dx


## Converts accumulated block gradients to the flat parameter layout, scaled by `scale`.
func grad_to_flat(g: Grad, scale: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(params.size())
	for l in _dims.size() - 1:
		var nin := _dims[l]
		var nout := _dims[l + 1]
		var nib := _nib[l]
		var gc: PackedVector4Array = g.gcols[l]
		var gbb: PackedVector4Array = g.gb[l]
		var wo := _w_off[l]
		var bo := _b_off[l]
		for o in nout:
			var ob := o >> 2
			var r := o & 3
			var row := wo + o * nin
			var base := ob * nib * 4
			for i in nin:
				out[row + i] = gc[base + i][r] * scale
			out[bo + o] = gbb[ob][r] * scale
	return out
