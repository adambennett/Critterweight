'use strict';
// Zero-dependency DSP toolkit used by every CRITTERWEIGHT synthesizer.
// Conventions: mono buffers are Float64Array at full scale [-1, 1]; stereo is {l, r}.
// Everything is deterministic (randomness comes in through an Rng instance, never Math.random).

const TAU = Math.PI * 2;

// ---------------------------------------------------------------------------------------
// Buffers and gain helpers
// ---------------------------------------------------------------------------------------

function zeros(n) { return new Float64Array(Math.max(0, Math.ceil(n))); }
function secs(sr, s) { return Math.ceil(s * sr); }
function db(d) { return Math.pow(10, d / 20); }
function lin2db(x) { return x <= 1e-12 ? -240 : 20 * Math.log10(x); }
function clamp(x, a, b) { return x < a ? a : x > b ? b : x; }
function lerp(a, b, t) { return a + (b - a) * t; }
function isStereo(b) { return b && b.l instanceof Float64Array; }
function stereo(n) { return { l: zeros(n), r: zeros(n) }; }
function toStereo(b) { return isStereo(b) ? b : { l: b, r: Float64Array.from(b) }; }
function length(b) { return isStereo(b) ? b.l.length : b.length; }

/** dst += src * gain starting at offset (samples). Grows nothing: clips to dst length. */
function mixInto(dst, src, gain = 1, offset = 0) {
  if (isStereo(dst)) {
    const s = toStereo(src);
    mixInto(dst.l, s.l, gain, offset);
    mixInto(dst.r, s.r, gain, offset);
    return dst;
  }
  if (isStereo(src)) src = src.l;
  offset = Math.round(offset);
  const n = Math.min(src.length, dst.length - offset);
  for (let i = 0; i < n; i++) dst[i + offset] += src[i] * gain;
  return dst;
}

function applyGain(b, g) {
  if (isStereo(b)) { applyGain(b.l, g); applyGain(b.r, g); return b; }
  for (let i = 0; i < b.length; i++) b[i] *= g;
  return b;
}

function multiply(b, env) { // b *= env (env shorter -> remainder zero)
  if (isStereo(b)) { multiply(b.l, env); multiply(b.r, env); return b; }
  const n = Math.min(b.length, env.length);
  for (let i = 0; i < n; i++) b[i] *= env[i];
  for (let i = n; i < b.length; i++) b[i] = 0;
  return b;
}

function concat(a, b) {
  const out = zeros(a.length + b.length);
  out.set(a, 0); out.set(b, a.length);
  return out;
}

function fade(b, sr, inSec = 0, outSec = 0) {
  if (isStereo(b)) { fade(b.l, sr, inSec, outSec); fade(b.r, sr, inSec, outSec); return b; }
  const ni = Math.min(b.length, secs(sr, inSec));
  for (let i = 0; i < ni; i++) b[i] *= i / ni;
  const no = Math.min(b.length, secs(sr, outSec));
  for (let i = 0; i < no; i++) b[b.length - 1 - i] *= i / no;
  return b;
}

function peak(b) {
  if (isStereo(b)) return Math.max(peak(b.l), peak(b.r));
  let p = 0;
  for (let i = 0; i < b.length; i++) { const a = Math.abs(b[i]); if (a > p) p = a; }
  return p;
}

function normalize(b, targetPeak = 1) {
  const p = peak(b);
  if (p > 1e-9) applyGain(b, targetPeak / p);
  return b;
}

function rms(b) {
  if (isStereo(b)) return Math.sqrt((rms(b.l) ** 2 + rms(b.r) ** 2) / 2);
  let s = 0;
  for (let i = 0; i < b.length; i++) s += b[i] * b[i];
  return Math.sqrt(s / Math.max(1, b.length));
}

/** Trims trailing silence (below threshold) but keeps `keepSec` of tail. */
function trimTail(b, sr, thresholdDb = -72, keepSec = 0.02) {
  const th = db(thresholdDb);
  const L = length(b);
  let last = 0;
  for (let i = L - 1; i >= 0; i--) {
    const v = isStereo(b) ? Math.max(Math.abs(b.l[i]), Math.abs(b.r[i])) : Math.abs(b[i]);
    if (v > th) { last = i; break; }
  }
  const n = Math.min(L, last + 1 + secs(sr, keepSec));
  if (isStereo(b)) return { l: b.l.slice(0, n), r: b.r.slice(0, n) };
  return b.slice(0, n);
}

/** Constant-power pan of a mono buffer. pan in [-1, 1]. */
function pan(mono, p = 0) {
  const a = (p + 1) * Math.PI / 4;
  const gl = Math.cos(a), gr = Math.sin(a);
  const out = stereo(mono.length);
  for (let i = 0; i < mono.length; i++) { out.l[i] = mono[i] * gl; out.r[i] = mono[i] * gr; }
  return out;
}

function dcBlock(b, sr) {
  if (isStereo(b)) { dcBlock(b.l, sr); dcBlock(b.r, sr); return b; }
  const R = 1 - (TAU * 10 / sr);
  let x1 = 0, y1 = 0;
  for (let i = 0; i < b.length; i++) {
    const x = b[i];
    const y = x - x1 + R * y1;
    x1 = x; y1 = y; b[i] = y;
  }
  return b;
}

/** Linear-interpolating resampler: returns a buffer at a new rate (or pitch-shifted when ratio given). */
function resample(b, ratio) { // ratio = out_len / in_len
  const n = Math.max(1, Math.round(b.length * ratio));
  const out = zeros(n);
  const step = b.length / n;
  for (let i = 0; i < n; i++) {
    const x = i * step;
    const j = Math.floor(x);
    const f = x - j;
    const a = b[j] || 0, c = b[j + 1] || 0;
    out[i] = a + (c - a) * f;
  }
  return out;
}

// ---------------------------------------------------------------------------------------
// Oscillators (per-sample objects)
// ---------------------------------------------------------------------------------------

function polyblep(t, dt) {
  if (t < dt) { t /= dt; return t + t - t * t - 1; }
  if (t > 1 - dt) { t = (t - 1) / dt; return t * t + t + t + 1; }
  return 0;
}

class Osc {
  /** type: sine | saw | square | pulse | tri | ramp(up) */
  constructor(sr, type = 'sine', phase = 0) {
    this.sr = sr; this.type = type; this.phase = phase; this.last = 0;
  }
  next(freq, pw = 0.5) {
    const dt = freq / this.sr;
    const t = this.phase;
    let v;
    switch (this.type) {
      case 'sine': v = Math.sin(TAU * t); break;
      case 'saw': v = 2 * t - 1 - polyblep(t, dt); break;
      case 'square': {
        v = t < 0.5 ? 1 : -1;
        v += polyblep(t, dt);
        v -= polyblep((t + 0.5) % 1, dt);
        break;
      }
      case 'pulse': {
        v = t < pw ? 1 : -1;
        v += polyblep(t, dt);
        v -= polyblep((t + 1 - pw) % 1, dt);
        break;
      }
      case 'tri': {
        // integrated polyblep square (leaky) gives a band-limited triangle
        let sq = t < 0.5 ? 1 : -1;
        sq += polyblep(t, dt);
        sq -= polyblep((t + 0.5) % 1, dt);
        this.last = this.last * 0.999 + sq * 4 * dt;
        v = clamp(this.last, -1, 1);
        break;
      }
      default: v = Math.sin(TAU * t);
    }
    this.phase += dt;
    if (this.phase >= 1) this.phase -= Math.floor(this.phase);
    return v;
  }
}

/** FM operator: sine carrier with phase modulation input (radians). */
class FmOp {
  constructor(sr, phase = 0) { this.sr = sr; this.phase = phase; this.out = 0; }
  next(freq, mod = 0) {
    this.out = Math.sin(TAU * this.phase + mod);
    this.phase += freq / this.sr;
    if (this.phase >= 1) this.phase -= Math.floor(this.phase);
    return this.out;
  }
}

/** Hard-sync sawtooth: slave resets every master period (the "screaming" lead). */
class SyncSaw {
  constructor(sr) { this.sr = sr; this.mp = 0; this.sp = 0; }
  next(masterFreq, slaveFreq) {
    const dm = masterFreq / this.sr, ds = slaveFreq / this.sr;
    this.mp += dm;
    if (this.mp >= 1) { this.mp -= 1; this.sp = (this.mp / dm) * ds; }
    let v = 2 * this.sp - 1;
    this.sp += ds;
    if (this.sp >= 1) this.sp -= Math.floor(this.sp);
    return v;
  }
}

class Supersaw {
  constructor(sr, voices = 5, detuneCents = 12, rng = null) {
    this.oscs = [];
    this.det = [];
    for (let i = 0; i < voices; i++) {
      const spread = voices === 1 ? 0 : (i / (voices - 1)) * 2 - 1;
      this.oscs.push(new Osc(sr, 'saw', rng ? rng.float() : (i * 0.37) % 1));
      this.det.push(Math.pow(2, (spread * detuneCents) / 1200));
    }
    this.g = 1 / Math.sqrt(voices);
  }
  next(freq) {
    let v = 0;
    for (let i = 0; i < this.oscs.length; i++) v += this.oscs[i].next(freq * this.det[i]);
    return v * this.g;
  }
}

/** Wavetable oscillator: `tables` is an array of single-cycle Float64Arrays; `morph` (0..1) crossfades
 * between neighbouring tables, positions interpolate linearly. Wavetable.make(fn, size) builds a table. */
class Wavetable {
  constructor(sr, tables, phase = 0) { this.sr = sr; this.tables = tables; this.phase = phase; }
  static make(fn, size = 2048) { const t = new Float64Array(size); for (let i = 0; i < size; i++) t[i] = fn(i / size); return t; }
  static harmonics(amps, size = 2048) { // additive table from harmonic amplitudes
    return Wavetable.make((x) => { let v = 0; for (let h = 0; h < amps.length; h++) v += amps[h] * Math.sin(TAU * (h + 1) * x); return v; }, size);
  }
  next(freq, morph = 0) {
    const n = this.tables.length;
    const m = clamp(morph, 0, 1) * (n - 1);
    const i0 = Math.floor(m), i1 = Math.min(n - 1, i0 + 1), f = m - i0;
    const read = (t) => {
      const p = this.phase * t.length;
      const j = Math.floor(p), k = p - j;
      return t[j] + (t[(j + 1) % t.length] - t[j]) * k;
    };
    const v = read(this.tables[i0]) * (1 - f) + (f > 0 ? read(this.tables[i1]) * f : 0);
    this.phase += freq / this.sr;
    if (this.phase >= 1) this.phase -= Math.floor(this.phase);
    return v;
  }
}

class Noise {
  constructor(rng) { this.rng = rng; }
  next() { return this.rng.float() * 2 - 1; }
}

class Pink { // Paul Kellet's refined method
  constructor(rng) { this.rng = rng; this.b = new Float64Array(7); }
  next() {
    const w = this.rng.float() * 2 - 1;
    const b = this.b;
    b[0] = 0.99886 * b[0] + w * 0.0555179;
    b[1] = 0.99332 * b[1] + w * 0.0750759;
    b[2] = 0.96900 * b[2] + w * 0.1538520;
    b[3] = 0.86650 * b[3] + w * 0.3104856;
    b[4] = 0.55000 * b[4] + w * 0.5329522;
    b[5] = -0.7616 * b[5] - w * 0.0168980;
    const out = b[0] + b[1] + b[2] + b[3] + b[4] + b[5] + b[6] + w * 0.5362;
    b[6] = w * 0.115926;
    return out * 0.11;
  }
}

class Brown {
  constructor(rng) { this.rng = rng; this.v = 0; }
  next() {
    this.v = clamp(this.v + (this.rng.float() * 2 - 1) * 0.02, -1, 1) * 0.998;
    return this.v * 3.5;
  }
}

/** Low-frequency oscillator in [-1, 1]. */
class Lfo {
  constructor(sr, type = 'sine', phase = 0) { this.sr = sr; this.type = type; this.phase = phase; }
  next(freq) {
    const t = this.phase;
    let v;
    switch (this.type) {
      case 'tri': v = 1 - 4 * Math.abs(t - 0.5); break;
      case 'saw': v = 2 * t - 1; break;
      case 'square': v = t < 0.5 ? 1 : -1; break;
      default: v = Math.sin(TAU * t);
    }
    this.phase += freq / this.sr;
    if (this.phase >= 1) this.phase -= 1;
    return v;
  }
}

// ---------------------------------------------------------------------------------------
// Envelopes (return Float64Array)
// ---------------------------------------------------------------------------------------

/** ADSR with exponential-ish segments. dur is the gate length (seconds); output includes release. */
function adsr(sr, { a = 0.005, d = 0.1, s = 0.7, r = 0.1, dur = 0.5, curve = 2, hold = 0 } = {}) {
  const na = secs(sr, a), nd = secs(sr, d), nh = secs(sr, hold), nr = secs(sr, r);
  const ng = Math.max(secs(sr, dur), na + nh);
  const out = zeros(ng + nr + 1);
  let i = 0;
  for (let k = 0; k < na && i < ng; k++, i++) out[i] = Math.pow(k / na, 1 / curve);
  for (let k = 0; k < nh && i < ng; k++, i++) out[i] = 1;
  for (let k = 0; k < nd && i < ng; k++, i++) out[i] = s + (1 - s) * Math.pow(1 - k / nd, curve);
  while (i < ng) out[i++] = s;
  const level = out[Math.max(0, i - 1)];
  for (let k = 0; k < nr; k++, i++) out[i] = level * Math.pow(1 - k / nr, curve);
  return out;
}

/** Piecewise envelope through [time, value] points; exponential interpolation when exp=true (values > 0). */
function envelope(sr, points, { exp = false } = {}) {
  const total = points[points.length - 1][0];
  const out = zeros(total * sr + 1);
  let p = 0;
  for (let i = 0; i < out.length; i++) {
    const t = i / sr;
    while (p < points.length - 2 && t >= points[p + 1][0]) p++;
    const [t0, v0] = points[p];
    const [t1, v1] = points[p + 1];
    const f = t1 > t0 ? clamp((t - t0) / (t1 - t0), 0, 1) : 1;
    out[i] = exp && v0 > 0 && v1 > 0 ? v0 * Math.pow(v1 / v0, f) : v0 + (v1 - v0) * f;
  }
  return out;
}

/** Exponential decay: 1 -> 0 over `seconds`, time constant tau (fraction of seconds). */
function decay(sr, seconds, tau = 0.25, attackSec = 0.001) {
  const n = secs(sr, seconds);
  const out = zeros(n);
  const na = Math.max(1, secs(sr, attackSec));
  for (let i = 0; i < n; i++) {
    const t = i / sr;
    const e = Math.exp(-t / (seconds * tau));
    const a = i < na ? i / na : 1;
    out[i] = e * a * (1 - t / seconds); // reaches exactly zero at the end
  }
  return out;
}

// ---------------------------------------------------------------------------------------
// Filters (stateful, per sample)
// ---------------------------------------------------------------------------------------

/** Topology-preserving state variable filter (Zavalishin). set() then lp()/hp()/bp()/notch(). */
class SVF {
  constructor(sr, cutoff = 1000, q = 0.707) {
    this.sr = sr; this.ic1 = 0; this.ic2 = 0; this.set(cutoff, q);
    this.lpv = 0; this.hpv = 0; this.bpv = 0;
  }
  set(cutoff, q = 0.707) {
    const f = clamp(cutoff, 5, this.sr * 0.49);
    this.g = Math.tan(Math.PI * f / this.sr);
    this.k = 1 / Math.max(0.05, q);
    this.a1 = 1 / (1 + this.g * (this.g + this.k));
    this.a2 = this.g * this.a1;
    this.a3 = this.g * this.a2;
  }
  process(x) {
    const v3 = x - this.ic2;
    const v1 = this.a1 * this.ic1 + this.a2 * v3;
    const v2 = this.ic2 + this.a2 * this.ic1 + this.a3 * v3;
    this.ic1 = 2 * v1 - this.ic1;
    this.ic2 = 2 * v2 - this.ic2;
    this.lpv = v2; this.bpv = v1; this.hpv = x - this.k * v1 - v2;
    return v2;
  }
  lp(x) { this.process(x); return this.lpv; }
  hp(x) { this.process(x); return this.hpv; }
  bp(x) { this.process(x); return this.bpv * this.k; } // unity-gain bandpass
  notch(x) { this.process(x); return x - this.k * this.bpv; }
}

class OnePole {
  constructor(sr, cutoff = 1000) { this.sr = sr; this.z = 0; this.set(cutoff); }
  set(cutoff) { this.a = 1 - Math.exp(-TAU * clamp(cutoff, 1, this.sr * 0.49) / this.sr); }
  lp(x) { this.z += this.a * (x - this.z); return this.z; }
  hp(x) { return x - this.lp(x); }
}

/** RBJ biquad. type: lowpass highpass bandpass notch peaking lowshelf highshelf allpass */
class Biquad {
  constructor(sr, type = 'lowpass', f = 1000, q = 0.707, gainDb = 0) {
    this.sr = sr; this.x1 = this.x2 = this.y1 = this.y2 = 0; this.set(type, f, q, gainDb);
  }
  set(type, f, q = 0.707, gainDb = 0) {
    f = clamp(f, 5, this.sr * 0.49);
    const A = Math.pow(10, gainDb / 40);
    const w0 = TAU * f / this.sr;
    const cs = Math.cos(w0), sn = Math.sin(w0);
    const alpha = sn / (2 * Math.max(0.05, q));
    let b0, b1, b2, a0, a1, a2;
    switch (type) {
      case 'lowpass': b0 = (1 - cs) / 2; b1 = 1 - cs; b2 = (1 - cs) / 2; a0 = 1 + alpha; a1 = -2 * cs; a2 = 1 - alpha; break;
      case 'highpass': b0 = (1 + cs) / 2; b1 = -(1 + cs); b2 = (1 + cs) / 2; a0 = 1 + alpha; a1 = -2 * cs; a2 = 1 - alpha; break;
      case 'bandpass': b0 = alpha; b1 = 0; b2 = -alpha; a0 = 1 + alpha; a1 = -2 * cs; a2 = 1 - alpha; break;
      case 'notch': b0 = 1; b1 = -2 * cs; b2 = 1; a0 = 1 + alpha; a1 = -2 * cs; a2 = 1 - alpha; break;
      case 'allpass': b0 = 1 - alpha; b1 = -2 * cs; b2 = 1 + alpha; a0 = 1 + alpha; a1 = -2 * cs; a2 = 1 - alpha; break;
      case 'peaking': b0 = 1 + alpha * A; b1 = -2 * cs; b2 = 1 - alpha * A; a0 = 1 + alpha / A; a1 = -2 * cs; a2 = 1 - alpha / A; break;
      case 'lowshelf': {
        const sq = 2 * Math.sqrt(A) * alpha;
        b0 = A * ((A + 1) - (A - 1) * cs + sq); b1 = 2 * A * ((A - 1) - (A + 1) * cs); b2 = A * ((A + 1) - (A - 1) * cs - sq);
        a0 = (A + 1) + (A - 1) * cs + sq; a1 = -2 * ((A - 1) + (A + 1) * cs); a2 = (A + 1) + (A - 1) * cs - sq; break;
      }
      case 'highshelf': {
        const sq = 2 * Math.sqrt(A) * alpha;
        b0 = A * ((A + 1) + (A - 1) * cs + sq); b1 = -2 * A * ((A - 1) + (A + 1) * cs); b2 = A * ((A + 1) + (A - 1) * cs - sq);
        a0 = (A + 1) - (A - 1) * cs + sq; a1 = 2 * ((A - 1) - (A + 1) * cs); a2 = (A + 1) - (A - 1) * cs - sq; break;
      }
      default: throw new Error('biquad type ' + type);
    }
    this.b0 = b0 / a0; this.b1 = b1 / a0; this.b2 = b2 / a0; this.a1 = a1 / a0; this.a2 = a2 / a0;
  }
  process(x) {
    const y = this.b0 * x + this.b1 * this.x1 + this.b2 * this.x2 - this.a1 * this.y1 - this.a2 * this.y2;
    this.x2 = this.x1; this.x1 = x; this.y2 = this.y1; this.y1 = y;
    return y;
  }
}

class DelayLine {
  constructor(maxSamples) { this.buf = zeros(Math.max(2, Math.ceil(maxSamples) + 2)); this.w = 0; }
  write(x) { this.buf[this.w] = x; this.w = (this.w + 1) % this.buf.length; }
  read(d) { // integer delay
    let i = this.w - 1 - Math.round(d);
    const n = this.buf.length;
    i = ((i % n) + n) % n;
    return this.buf[i];
  }
  readInterp(d) {
    const n = this.buf.length;
    const di = Math.floor(d), f = d - di;
    let i0 = this.w - 1 - di; i0 = ((i0 % n) + n) % n;
    const i1 = (i0 - 1 + n) % n;
    return this.buf[i0] + (this.buf[i1] - this.buf[i0]) * f;
  }
}

class Comb { // feedback comb with damping (Freeverb style)
  constructor(sr, delaySec, feedback = 0.8, damp = 0.2) {
    this.d = new DelayLine(Math.ceil(delaySec * sr)); this.n = Math.ceil(delaySec * sr);
    this.fb = feedback; this.damp = damp; this.store = 0;
  }
  process(x) {
    const out = this.d.read(this.n - 1);
    this.store = out * (1 - this.damp) + this.store * this.damp;
    this.d.write(x + this.store * this.fb);
    return out;
  }
}

class Allpass {
  constructor(sr, delaySec, feedback = 0.5) {
    this.n = Math.ceil(delaySec * sr); this.d = new DelayLine(this.n); this.fb = feedback;
  }
  process(x) {
    const bufout = this.d.read(this.n - 1);
    const out = -x + bufout;
    this.d.write(x + bufout * this.fb);
    return out;
  }
}

/** Whole-buffer filter helper (in place). */
function filterBuf(b, sr, type, cutoff, q = 0.707, gainDb = 0) {
  if (isStereo(b)) { filterBuf(b.l, sr, type, cutoff, q, gainDb); filterBuf(b.r, sr, type, cutoff, q, gainDb); return b; }
  const f = new Biquad(sr, type, cutoff, q, gainDb);
  for (let i = 0; i < b.length; i++) b[i] = f.process(b[i]);
  return b;
}

// ---------------------------------------------------------------------------------------
// Effects on buffers
// ---------------------------------------------------------------------------------------

/** mode: tanh | soft | hard | fold | tube. drive >= 1. */
function saturate(b, drive = 2, mode = 'tanh', mix = 1) {
  if (isStereo(b)) { saturate(b.l, drive, mode, mix); saturate(b.r, drive, mode, mix); return b; }
  const norm = mode === 'tanh' ? 1 / Math.tanh(drive) : mode === 'tube' ? 1 / (1 - Math.exp(-drive)) : 1;
  for (let i = 0; i < b.length; i++) {
    const x = b[i] * drive;
    let y;
    switch (mode) {
      case 'soft': y = x - (x * x * x) / 3; if (x > 1) y = 2 / 3; else if (x < -1) y = -2 / 3; y *= 1.5; break;
      case 'hard': y = clamp(x, -1, 1); break;
      case 'fold': { let v = (x + 1) % 4; if (v < 0) v += 4; y = v < 2 ? v - 1 : 3 - v; break; }
      case 'tube': y = (x >= 0 ? 1 - Math.exp(-x) : -(1 - Math.exp(x))) * norm; break;
      default: y = Math.tanh(x) * norm;
    }
    b[i] = b[i] * (1 - mix) + y * mix;
  }
  return b;
}

function bitcrush(b, bits = 8, down = 1) {
  if (isStereo(b)) { bitcrush(b.l, bits, down); bitcrush(b.r, bits, down); return b; }
  const steps = Math.pow(2, bits - 1);
  let hold = 0;
  for (let i = 0; i < b.length; i++) {
    if (i % down === 0) hold = Math.round(b[i] * steps) / steps;
    b[i] = hold;
  }
  return b;
}

/** Chorus: returns stereo from mono/stereo input. depth in ms. */
function chorus(b, sr, { rate = 0.8, depth = 3.5, mix = 0.5, base = 12, voices = 2 } = {}) {
  const inL = isStereo(b) ? b.l : b, inR = isStereo(b) ? b.r : b;
  const n = inL.length;
  const out = stereo(n);
  const maxD = (base + depth * 2) * sr / 1000 + 4;
  const dl = new DelayLine(maxD), dr = new DelayLine(maxD);
  const lfos = [];
  for (let v = 0; v < voices; v++) lfos.push(new Lfo(sr, 'sine', v / voices));
  for (let i = 0; i < n; i++) {
    dl.write(inL[i]); dr.write(inR[i]);
    let wl = 0, wr = 0;
    for (let v = 0; v < voices; v++) {
      const m = lfos[v].next(rate * (1 + v * 0.13));
      const dsl = (base + depth * (1 + m)) * sr / 1000;
      const dsr = (base + depth * (1 - m)) * sr / 1000;
      wl += dl.readInterp(dsl); wr += dr.readInterp(dsr);
    }
    wl /= voices; wr /= voices;
    out.l[i] = inL[i] * (1 - mix) + wl * mix;
    out.r[i] = inR[i] * (1 - mix) + wr * mix;
  }
  return out;
}

/** Feedback delay. time in seconds; returns stereo. damp = lowpass cutoff in the feedback loop. */
function delayFx(b, sr, { time = 0.375, feedback = 0.35, mix = 0.3, damp = 4000, pingpong = false, spread = 0, hp = 120 } = {}) {
  const inL = isStereo(b) ? b.l : b, inR = isStereo(b) ? b.r : b;
  const n = inL.length;
  const out = stereo(n);
  const dsamp = Math.max(1, Math.round(time * sr));
  const dl = new DelayLine(dsamp + 2), dr = new DelayLine(dsamp + 2);
  const lpL = new OnePole(sr, damp), lpR = new OnePole(sr, damp);
  const hpL = new OnePole(sr, hp), hpR = new OnePole(sr, hp);
  const dr2 = Math.max(1, Math.round(time * (1 + spread) * sr));
  for (let i = 0; i < n; i++) {
    const tl = dl.read(dsamp - 1), tr = dr.read((pingpong ? dsamp : dr2) - 1);
    const fl = hpL.hp(lpL.lp(tl)), fr = hpR.hp(lpR.lp(tr));
    if (pingpong) {
      dl.write(inL[i] * 0.5 + inR[i] * 0.5 + fr * feedback);
      dr.write(fl * feedback);
    } else {
      dl.write(inL[i] + fl * feedback);
      dr.write(inR[i] + fr * feedback);
    }
    out.l[i] = inL[i] * (1 - mix) + tl * mix;
    out.r[i] = inR[i] * (1 - mix) + tr * mix;
  }
  return out;
}

/** Freeverb-style reverb. Returns stereo (wet mixed with dry according to mix). */
function reverb(b, sr, { size = 0.6, damp = 0.4, mix = 0.25, predelay = 0.01, width = 1.0, lowcut = 150, highcut = 9000, gate = 0 } = {}) {
  const inL = isStereo(b) ? b.l : b, inR = isStereo(b) ? b.r : b;
  const n = inL.length;
  const scale = sr / 44100;
  const combT = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617].map((v) => (v * scale) / sr);
  const apT = [556, 441, 341, 225].map((v) => (v * scale) / sr);
  const spread = 23 * scale / sr;
  const fb = 0.7 + size * 0.28;
  const mkCombs = (off) => combT.map((t) => new Comb(sr, t + off, fb, damp));
  const mkAps = (off) => apT.map((t) => new Allpass(sr, t + off, 0.5));
  const cL = mkCombs(0), cR = mkCombs(spread), aL = mkAps(0), aR = mkAps(spread);
  const pre = new DelayLine(Math.ceil(predelay * sr) + 2);
  const preN = Math.max(1, Math.round(predelay * sr));
  const hpL = new Biquad(sr, 'highpass', lowcut, 0.707), hpR = new Biquad(sr, 'highpass', lowcut, 0.707);
  const lpL = new OnePole(sr, highcut), lpR = new OnePole(sr, highcut);
  const out = stereo(n);
  const wet1 = mix * (width / 2 + 0.5), wet2 = mix * ((1 - width) / 2);
  const gateN = gate > 0 ? Math.round(gate * sr) : 0;
  let gateCount = 0;
  const inGain = 0.015 * 2 * 6; // Freeverb's fixed gain, lifted so mix=1 gives a ~-10 dB impulse peak
  for (let i = 0; i < n; i++) {
    const mono = (inL[i] + inR[i]) * 0.5;
    pre.write(mono);
    const x = pre.read(preN - 1) * inGain;
    let ol = 0, orr = 0;
    for (let c = 0; c < 8; c++) { ol += cL[c].process(x); orr += cR[c].process(x); }
    for (let a = 0; a < 4; a++) { ol = aL[a].process(ol); orr = aR[a].process(orr); }
    ol = lpL.lp(hpL.process(ol)); orr = lpR.lp(hpR.process(orr));
    let g = 1;
    if (gateN) { // gated reverb: wet opens on input energy and shuts after `gate` seconds
      if (Math.abs(mono) > 0.05) gateCount = gateN;
      g = gateCount > 0 ? Math.min(1, gateCount / (gateN * 0.1)) : 0;
      if (gateCount > 0) gateCount--;
    }
    out.l[i] = inL[i] * (1 - mix) + (ol * wet1 + orr * wet2) * g;
    out.r[i] = inR[i] * (1 - mix) + (orr * wet1 + ol * wet2) * g;
  }
  return out;
}

/** Feed-forward compressor with soft knee; linked stereo detection. Returns in place. */
function compressor(b, sr, { threshold = -18, ratio = 3, attack = 0.01, release = 0.12, knee = 6, makeup = 0, rmsWin = 0 } = {}) {
  const st = isStereo(b);
  const L = st ? b.l : b, R = st ? b.r : b;
  const n = L.length;
  const aCoef = Math.exp(-1 / (attack * sr)), rCoef = Math.exp(-1 / (release * sr));
  let env = 0, gr = 0;
  const mk = db(makeup);
  let rmsAcc = 0;
  const rmsCoef = rmsWin > 0 ? Math.exp(-1 / (rmsWin * sr)) : 0;
  for (let i = 0; i < n; i++) {
    let x = Math.max(Math.abs(L[i]), Math.abs(R[i]));
    if (rmsWin > 0) { rmsAcc = rmsCoef * rmsAcc + (1 - rmsCoef) * x * x; x = Math.sqrt(rmsAcc); }
    const xdb = lin2db(x);
    let over = xdb - threshold;
    let g;
    if (over <= -knee / 2) g = 0;
    else if (over >= knee / 2) g = over * (1 / ratio - 1);
    else { const t = over + knee / 2; g = (1 / ratio - 1) * t * t / (2 * knee); }
    // smooth the gain reduction (in dB)
    if (g < gr) gr = aCoef * gr + (1 - aCoef) * g; else gr = rCoef * gr + (1 - rCoef) * g;
    const lin = db(gr) * mk;
    L[i] *= lin; if (st) R[i] *= lin;
  }
  return b;
}

/** True-peak-ish lookahead limiter: never exceeds `ceiling` dBFS (sample peaks). In place. */
function limiter(b, sr, { ceiling = -1, release = 0.08, lookahead = 0.004 } = {}) {
  const st = isStereo(b);
  const L = st ? b.l : b, R = st ? b.r : b;
  const n = L.length;
  const c = db(ceiling);
  const la = Math.max(1, Math.round(lookahead * sr));
  const need = zeros(n + la);
  for (let i = 0; i < n; i++) {
    const a = Math.max(Math.abs(L[i]), Math.abs(R[i]));
    need[i] = a > c ? c / a : 1;
  }
  for (let i = n; i < n + la; i++) need[i] = 1;
  // sliding minimum over [i-la, i] (monotonic deque)
  const smin = zeros(n + la);
  const dq = new Int32Array(n + la + 1);
  let head = 0, tail = 0;
  for (let i = 0; i < n + la; i++) {
    while (tail > head && need[dq[tail - 1]] >= need[i]) tail--;
    dq[tail++] = i;
    while (dq[head] < i - la) head++;
    smin[i] = need[dq[head]];
  }
  // moving average over la samples for a smooth attack ramp, then exponential release
  const sm = zeros(n + la);
  let acc = 0;
  for (let i = 0; i < n + la; i++) {
    acc += smin[i];
    if (i >= la) acc -= smin[i - la];
    sm[i] = acc / Math.min(la, i + 1);
  }
  const rCoef = Math.exp(-1 / (release * sr));
  let env = 1;
  const outL = zeros(n), outR = st ? zeros(n) : null;
  for (let i = 0; i < n + la; i++) {
    const target = Math.min(sm[i], smin[i]);
    if (target < env) env = target; else env = env + (target - env) * (1 - rCoef);
    if (env > target) env = target;
    const src = i - la;
    if (src >= 0 && src < n) {
      outL[src] = L[src] * env;
      if (st) outR[src] = R[src] * env;
    }
  }
  // the output is delayed by `la`; align by writing back in place without the delay
  // (we computed env at index i for sample i-la, so outL[src] already holds the aligned result)
  L.set(outL);
  if (st) R.set(outR);
  // safety clip for rounding
  for (let i = 0; i < n; i++) {
    if (L[i] > c) L[i] = c; else if (L[i] < -c) L[i] = -c;
    if (st) { if (R[i] > c) R[i] = c; else if (R[i] < -c) R[i] = -c; }
  }
  return b;
}

/** Simple stereo widener using mid/side. width 0..2 */
function widen(b, width = 1.2) {
  if (!isStereo(b)) return b;
  for (let i = 0; i < b.l.length; i++) {
    const m = (b.l[i] + b.r[i]) * 0.5, s = (b.l[i] - b.r[i]) * 0.5 * width;
    b.l[i] = m + s; b.r[i] = m - s;
  }
  return b;
}

/** Haas-style stereo spread of a mono buffer. */
function spread(mono, sr, ms = 12, mix = 0.5) {
  const out = stereo(mono.length);
  const d = Math.round(ms * sr / 1000);
  for (let i = 0; i < mono.length; i++) {
    const late = i >= d ? mono[i - d] : 0;
    out.l[i] = mono[i];
    out.r[i] = mono[i] * (1 - mix) + late * mix;
  }
  return out;
}

// ---------------------------------------------------------------------------------------
// Measurement (ITU-R BS.1770-4 style loudness, peak)
// ---------------------------------------------------------------------------------------

function peakDb(b) { return lin2db(peak(b)); }
function rmsDb(b) { return lin2db(rms(b)); }

/** Integrated loudness in LUFS with K-weighting and absolute/relative gating. */
function lufs(b, sr) {
  const st = isStereo(b);
  const chans = st ? [b.l, b.r] : [b];
  const n = chans[0].length;
  const block = Math.round(0.4 * sr), hop = Math.round(0.1 * sr);
  if (n < block) return -70;
  const powers = []; // per block: sum over channels of mean square
  const filtered = chans.map((ch) => {
    const hs = new Biquad(sr, 'highshelf', 1681.97, 0.7071, 3.99);
    const hp = new Biquad(sr, 'highpass', 38.13, 0.5);
    const out = zeros(n);
    for (let i = 0; i < n; i++) out[i] = hp.process(hs.process(ch[i]));
    return out;
  });
  for (let start = 0; start + block <= n; start += hop) {
    let p = 0;
    for (const ch of filtered) {
      let s = 0;
      for (let i = start; i < start + block; i++) s += ch[i] * ch[i];
      p += s / block;
    }
    powers.push(p);
  }
  const toL = (p) => -0.691 + 10 * Math.log10(Math.max(p, 1e-20));
  const absGated = powers.filter((p) => toL(p) > -70);
  if (!absGated.length) return -70;
  const mean1 = absGated.reduce((a, c) => a + c, 0) / absGated.length;
  const relTh = toL(mean1) - 10;
  const relGated = absGated.filter((p) => toL(p) > relTh);
  if (!relGated.length) return toL(mean1);
  return toL(relGated.reduce((a, c) => a + c, 0) / relGated.length);
}

function countOver(b, lin = 1.0) {
  if (isStereo(b)) return countOver(b.l, lin) + countOver(b.r, lin);
  let c = 0;
  for (let i = 0; i < b.length; i++) if (Math.abs(b[i]) > lin) c++;
  return c;
}

module.exports = {
  TAU, zeros, secs, db, lin2db, clamp, lerp, isStereo, stereo, toStereo, length, mixInto, applyGain, multiply, concat,
  fade, peak, normalize, rms, trimTail, pan, dcBlock, resample,
  Osc, FmOp, SyncSaw, Supersaw, Wavetable, Noise, Pink, Brown, Lfo,
  adsr, envelope, decay,
  SVF, OnePole, Biquad, DelayLine, Comb, Allpass, filterBuf,
  saturate, bitcrush, chorus, delayFx, reverb, compressor, limiter, widen, spread,
  peakDb, rmsDb, lufs, countOver,
};
