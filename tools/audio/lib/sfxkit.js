'use strict';
// Building blocks for designed sound effects. Every function returns a mono Float64Array at `sr`.
// All randomness comes from the Rng passed in, so variants are reproducible.

const D = require('./dsp');
const { zeros, secs, clamp, TAU } = D;

function env(sr, n, { a = 0.001, d = null, curve = 1.6, hold = 0 } = {}) {
  // simple attack + exponential decay to zero at n
  const out = zeros(n);
  const na = Math.max(1, secs(sr, a)), nh = secs(sr, hold);
  const nd = d ? secs(sr, d) : n - na - nh;
  for (let i = 0; i < n; i++) {
    let v;
    if (i < na) v = i / na;
    else if (i < na + nh) v = 1;
    else { const k = (i - na - nh) / Math.max(1, nd); v = k >= 1 ? 0 : Math.pow(1 - k, curve); }
    out[i] = v;
  }
  return out;
}

function applyEnv(buf, e) { return D.multiply(buf, e); }

/** Filtered noise. filt: [{type:'hp'|'lp'|'bp'|'notch'|'peak', f, q, gain}] applied in order. color: white|pink|brown */
function noise(sr, dur, rng, { color = 'white', filt = [], gain = 1 } = {}) {
  const n = secs(sr, dur);
  const src = color === 'pink' ? new D.Pink(rng) : color === 'brown' ? new D.Brown(rng) : new D.Noise(rng);
  const out = zeros(n);
  for (let i = 0; i < n; i++) out[i] = src.next() * gain;
  return filterChain(out, sr, filt);
}

function filterChain(buf, sr, filt) {
  for (const f of filt || []) {
    const type = { hp: 'highpass', lp: 'lowpass', bp: 'bandpass', notch: 'notch', peak: 'peaking', ls: 'lowshelf', hs: 'highshelf' }[f.type] || f.type;
    D.filterBuf(buf, sr, type, f.f, f.q || 0.707, f.gain || 0);
    if (f.passes) for (let k = 1; k < f.passes; k++) D.filterBuf(buf, sr, type, f.f, f.q || 0.707, f.gain || 0);
  }
  return buf;
}

/** Short enveloped noise burst (the "crack" / "pff" / "shh" family). */
function burst(sr, rng, { dur = 0.06, color = 'white', filt = [], a = 0.0005, curve = 1.8, gain = 1 } = {}) {
  const b = noise(sr, dur, rng, { color, filt, gain });
  return applyEnv(b, env(sr, b.length, { a, curve }));
}

/** Pitched thump: sine with an exponential pitch drop from f0 to f1 and a decaying envelope. */
function thump(sr, { f0 = 160, f1 = 60, sweep = 0.04, dur = 0.25, curve = 2.2, drive = 1.6, harm = 0.15, a = 0.0005, wave = 'sine' } = {}) {
  const n = secs(sr, dur);
  const o = new D.Osc(sr, wave), o2 = new D.Osc(sr, 'sine', 0.3);
  const e = env(sr, n, { a, curve });
  const ns = secs(sr, sweep);
  const out = zeros(n);
  for (let i = 0; i < n; i++) {
    const k = i < ns ? Math.exp(-i / (ns * 0.4)) : 0;
    const f = f1 + (f0 - f1) * k;
    const v = o.next(f) + o2.next(f * 2) * harm;
    out[i] = Math.tanh(v * drive) * e[i];
  }
  return out;
}

/** Plain tone with ADSR. wave: sine|saw|square|tri|pulse. */
function tone(sr, { f = 440, f1 = null, dur = 0.2, wave = 'sine', a = 0.005, d = 0.05, s = 0.6, r = 0.05, lp = 0, q = 0.7, pw = 0.5, gain = 1 } = {}) {
  const e = D.adsr(sr, { a, d, s, r, dur });
  const n = e.length;
  const o = new D.Osc(sr, wave);
  const filt = lp ? new D.SVF(sr, lp, q) : null;
  const out = zeros(n);
  for (let i = 0; i < n; i++) {
    const fr = f1 ? f * Math.pow(f1 / f, i / n) : f;
    let v = o.next(fr, pw);
    if (filt) v = filt.lp(v);
    out[i] = v * e[i] * gain;
  }
  return out;
}

/** FM ping / bell / "ting". ratio non-integer = inharmonic. */
function fmHit(sr, { f = 800, ratio = 2.01, index = 2.5, dur = 0.25, idxDecay = 0.4, curve = 2, a = 0.0005, detune = 0 } = {}) {
  const n = secs(sr, dur);
  const c = new D.FmOp(sr), m = new D.FmOp(sr), c2 = new D.FmOp(sr, 0.4), m2 = new D.FmOp(sr, 0.2);
  const e = env(sr, n, { a, curve });
  const det = Math.pow(2, detune / 1200);
  const out = zeros(n);
  for (let i = 0; i < n; i++) {
    const idx = index * Math.exp(-i / (n * idxDecay));
    let v = c.next(f, m.next(f * ratio) * idx);
    if (detune) v = (v + c2.next(f * det, m2.next(f * det * ratio) * idx)) * 0.6;
    out[i] = v * e[i];
  }
  return out;
}

/** Filtered-noise sweep (whoosh): the filter centre glides from f0 to f1 over dur. */
function sweep(sr, rng, { dur = 0.12, f0 = 2000, f1 = 500, q = 1.2, color = 'white', mode = 'bp', a = 0.01, curve = 1.4, peakAt = 0.35, gain = 1 } = {}) {
  const n = secs(sr, dur);
  const src = color === 'pink' ? new D.Pink(rng) : new D.Noise(rng);
  const f = new D.SVF(sr, f0, q);
  const out = zeros(n);
  const np = Math.max(1, Math.round(n * peakAt));
  for (let i = 0; i < n; i++) {
    const k = i / n;
    f.set(f0 * Math.pow(f1 / f0, k), q);
    const x = src.next();
    const v = mode === 'bp' ? f.bp(x) : mode === 'lp' ? f.lp(x) : f.hp(x);
    const e = i < np ? Math.pow(i / np, 1.5) : Math.pow(1 - (i - np) / (n - np), curve);
    out[i] = v * e * gain;
  }
  return out;
}

/** Sine/other chirp from f0 to f1 (exponential glide). */
function chirp(sr, { f0 = 400, f1 = 1200, dur = 0.1, wave = 'sine', curve = 1.5, a = 0.002, gain = 1 } = {}) {
  const n = secs(sr, dur);
  const o = new D.Osc(sr, wave);
  const e = env(sr, n, { a, curve });
  const out = zeros(n);
  for (let i = 0; i < n; i++) out[i] = o.next(f0 * Math.pow(f1 / f0, i / n)) * e[i] * gain;
  return out;
}

/** Granular crackle (fire, static ticks, gravel). density = events per second. */
function crackle(sr, rng, { dur = 0.5, density = 120, tone = 2500, q = 2, decayMs = 6, gain = 1, lp = 9000, hp = 300, sizeJitter = 0.6 } = {}) {
  const n = secs(sr, dur);
  const out = zeros(n);
  const bp = new D.Biquad(sr, 'bandpass', tone, q);
  let i = 0;
  while (i < n) {
    const gap = Math.max(1, Math.round((sr / density) * (0.3 + rng.float() * 1.4)));
    const amp = rng.range(0.4, 1) * rng.sign();
    const len = Math.max(2, Math.round((decayMs / 1000) * sr * (1 - sizeJitter + rng.float() * 2 * sizeJitter)));
    for (let k = 0; k < len && i + k < n; k++) out[i + k] += amp * Math.exp(-k / (len * 0.3)) * (rng.float() * 2 - 1);
    i += gap;
  }
  for (let k = 0; k < n; k++) out[k] = bp.process(out[k]) * 3 * gain;
  return filterChain(out, sr, [{ type: 'lp', f: lp }, { type: 'hp', f: hp }]);
}

/** Bubble pops: short rising sine chirps at random times (sludge, drain, Dredge). */
function bubbles(sr, rng, { dur = 0.6, rate = 12, fLo = 180, fHi = 900, popDur = 0.04, gain = 1, wet = 0.5 } = {}) {
  const n = secs(sr, dur);
  const out = zeros(n);
  let t = 0;
  while (t < n) {
    const f0 = rng.range(fLo, fHi);
    const pd = secs(sr, popDur * rng.range(0.6, 1.5));
    const o = new D.Osc(sr, 'sine');
    for (let k = 0; k < pd && t + k < n; k++) {
      const kk = k / pd;
      out[t + k] += o.next(f0 * Math.pow(2.2, kk)) * Math.pow(1 - kk, 1.4) * Math.min(1, k / 20) * rng.range(0.5, 1);
    }
    if (wet > 0) { // wet click
      for (let k = 0; k < 40 && t + k < n; k++) out[t + k] += (rng.float() * 2 - 1) * wet * Math.exp(-k / 8) * 0.5;
    }
    t += Math.max(1, Math.round((sr / rate) * rng.range(0.3, 1.7)));
  }
  return D.applyGain(out, gain);
}

/** A single water drip: short descending chirp with a resonant tail. */
function drip(sr, rng, { f = 1500, dur = 0.12, gain = 1 } = {}) {
  const n = secs(sr, dur);
  const o = new D.Osc(sr, 'sine');
  const out = zeros(n);
  const f0 = f * rng.range(0.8, 1.25);
  for (let i = 0; i < n; i++) {
    const k = i / n;
    out[i] = o.next(f0 * (1 + 0.6 * Math.exp(-k * 20)) * Math.pow(0.55, k)) * Math.pow(1 - k, 2.5) * Math.min(1, i / 15) * gain;
  }
  return out;
}

/** Splash: wide noise burst with a wobbling bandpass and droplet tail. */
function splash(sr, rng, { dur = 0.35, size = 1, gain = 1 } = {}) {
  const n = secs(sr, dur);
  const nz = new D.Pink(rng);
  const f = new D.SVF(sr, 1200, 1.1);
  const lfo = new D.Lfo(sr, 'sine', rng.float());
  const out = zeros(n);
  for (let i = 0; i < n; i++) {
    const k = i / n;
    f.set(900 * size * (1 + 0.5 * lfo.next(18 + 10 * k)) * (1 + 1.5 * Math.exp(-k * 6)), 1.1);
    out[i] = f.bp(nz.next()) * 2.5 * Math.pow(1 - k, 1.6) * Math.min(1, i / (sr * 0.004));
  }
  const drops = Math.round(3 + 4 * size);
  for (let d = 0; d < drops; d++) {
    const at = Math.round(rng.range(0.08, dur * 0.9) * sr);
    D.mixInto(out, drip(sr, rng, { f: rng.range(900, 2600), dur: 0.08 }), 0.35, at);
  }
  return D.applyGain(out, gain);
}

/** Chain-link rattle: noise through a comb filter with jittered impulses. */
function rattle(sr, rng, { dur = 0.45, f = 90, feedback = 0.75, density = 40, gain = 1, hp = 400 } = {}) {
  const n = secs(sr, dur);
  const out = zeros(n);
  const comb = new D.Comb(sr, 1 / f, feedback, 0.3);
  const bp = new D.Biquad(sr, 'bandpass', 2400, 0.8);
  let nxt = 0;
  for (let i = 0; i < n; i++) {
    let x = 0;
    if (i >= nxt) {
      x = rng.range(0.4, 1) * rng.sign();
      nxt = i + Math.round((sr / density) * rng.range(0.2, 1.8));
    }
    const k = i / n;
    out[i] = bp.process(comb.process(x)) * 3 * Math.pow(1 - k, 1.3);
  }
  return filterChain(D.applyGain(out, gain), sr, [{ type: 'hp', f: hp }]);
}

/** Electric zap: short noisy burst with a dense buzz at `f` and a click. */
function zap(sr, rng, { dur = 0.12, f = 4000, buzz = 120, gain = 1, curve = 2.5 } = {}) {
  const n = secs(sr, dur);
  const out = zeros(n);
  const bp = new D.Biquad(sr, 'bandpass', f, 1.5);
  const nz = new D.Noise(rng);
  const o = new D.Osc(sr, 'square');
  const e = env(sr, n, { a: 0.0003, curve });
  for (let i = 0; i < n; i++) {
    const am = 0.5 + 0.5 * o.next(buzz * rng.range(0.9, 1.1));
    out[i] = (bp.process(nz.next()) * 2.5 * am + (i < 60 ? (rng.float() * 2 - 1) : 0)) * e[i];
  }
  return D.applyGain(out, gain);
}

/** Buzz drone: pulse wave with AM/jitter through a resonant filter (hum, 60 Hz, capacitor whine). */
function buzz(sr, rng, { dur = 1, f = 60, harmonics = 1, am = 0.2, amRate = 7, lp = 2400, q = 1.5, jitter = 0.02, gain = 1, wave = 'pulse', pw = 0.2 } = {}) {
  const n = secs(sr, dur);
  const o = new D.Osc(sr, wave), o2 = new D.Osc(sr, 'saw', 0.3);
  const lfo = new D.Lfo(sr, 'sine');
  const filt = new D.SVF(sr, lp, q);
  const out = zeros(n);
  let j = 0;
  for (let i = 0; i < n; i++) {
    if (i % 64 === 0) j = rng.range(-jitter, jitter);
    const v = o.next(f * (1 + j), pw) + (harmonics > 1 ? o2.next(f * harmonics * (1 + j)) * 0.4 : 0);
    out[i] = filt.lp(v) * (1 - am * 0.5 * (1 + lfo.next(amRate))) * gain;
  }
  return out;
}

/** Wind / air loop: pink noise through slowly wandering bandpass filters. */
function wind(sr, rng, { dur = 4, base = 500, wander = 1.2, q = 0.9, gusts = 0.4, gain = 1, rate = 0.15 } = {}) {
  const n = secs(sr, dur);
  const nz = new D.Pink(rng);
  const f1 = new D.SVF(sr, base, q), f2 = new D.SVF(sr, base * 2.6, q * 1.5);
  const l1 = new D.Lfo(sr, 'sine', rng.float()), l2 = new D.Lfo(sr, 'tri', rng.float()), l3 = new D.Lfo(sr, 'sine', rng.float());
  const out = zeros(n);
  for (let i = 0; i < n; i++) {
    const w = l1.next(rate) * 0.5 + l2.next(rate * 1.7) * 0.5;
    f1.set(base * Math.pow(2, w * wander), q);
    f2.set(base * 2.6 * Math.pow(2, -w * wander * 0.6), q * 1.5);
    const x = nz.next();
    const g = 1 - gusts * 0.5 * (1 + l3.next(rate * 0.7));
    out[i] = (f1.bp(x) * 2.2 + f2.bp(x) * 0.8) * g * gain;
  }
  return out;
}

/** Makes a buffer loop seamlessly by crossfading its tail into its head. */
function seamless(buf, sr, xfade = 0.25) {
  const n = buf.length;
  const nx = Math.min(Math.floor(n / 2), secs(sr, xfade));
  const out = zeros(n - nx);
  for (let i = 0; i < out.length; i++) out[i] = buf[i];
  for (let i = 0; i < nx; i++) {
    const t = i / nx;
    const a = Math.cos(t * Math.PI / 2), b = Math.sin(t * Math.PI / 2);
    out[i] = buf[n - nx + i] * a + buf[i] * b;
  }
  return out;
}

/** Short mono room/slap ("room slap" on heavy hits). */
function room(buf, sr, { size = 0.3, mix = 0.2, damp = 0.5, predelay = 0.004, lowcut = 250, gate = 0 } = {}) {
  const st = D.reverb(buf, sr, { size, mix, damp, predelay, lowcut, gate });
  const out = zeros(buf.length);
  for (let i = 0; i < out.length; i++) out[i] = (st.l[i] + st.r[i]) * 0.5;
  return out;
}

/** Mixes parts [{buf, gain(dB or linear via lin), at (seconds)}] into one buffer. */
function mix(sr, parts, extra = 0) {
  let n = 0;
  for (const p of parts) n = Math.max(n, Math.round((p.at || 0) * sr) + p.buf.length);
  const out = zeros(n + secs(sr, extra));
  for (const p of parts) D.mixInto(out, p.buf, p.lin !== undefined ? p.lin : D.db(p.gain || 0), (p.at || 0) * sr);
  return out;
}

function pitch(buf, ratio) { return D.resample(buf, 1 / ratio); }

/** Trim/fade utility for one-shots: fades the last `ms` and trims silence. */
function tidy(buf, sr, { fadeOut = 0.012, threshold = -66 } = {}) {
  const b = D.trimTail(buf, sr, threshold, fadeOut * 1.2);
  D.fade(b, sr, 0.0008, fadeOut);
  return b;
}

// ---------------------------------------------------------------------------------------
// Creature vocal synthesis
// ---------------------------------------------------------------------------------------

/**
 * Formant vocal. f0: [[t, hz]...] pitch contour; formants: [[f, q, gain]...]; source: 'pulse' |
 * 'saw' | 'noise' mix via `breath`; growl: AM depth at ~30 Hz; jitter: per-cycle pitch noise;
 * drive: saturation; ring: metallic resonator frequency (0 = none); dur: seconds; env: adsr.
 */
function vocal(sr, rng, opts = {}) {
  const P = Object.assign({ dur: 0.4, f0: [[0, 140], [0.4, 110]], formants: [[600, 6, 1], [1100, 7, 0.6], [2500, 8, 0.25]], breath: 0.12, growl: 0.25, growlRate: 32, jitter: 0.03, drive: 1.6, ring: 0, ringGain: 0.3, a: 0.02, d: 0.1, s: 0.8, r: 0.08, wave: 'pulse', pw: 0.12, lp: 6000, hp: 80, vib: 0, vibRate: 6, tremor: 0 }, opts);
  const e = D.adsr(sr, { a: P.a, d: P.d, s: P.s, r: P.r, dur: P.dur, curve: 1.6 });
  const n = e.length;
  const src = new D.Osc(sr, P.wave);
  const nz = new D.Noise(rng);
  const bands = P.formants.map(([f, q]) => new D.SVF(sr, f, q));
  const ringF = P.ring ? new D.SVF(sr, P.ring, 18) : null;
  const lp = new D.SVF(sr, P.lp, 0.7);
  const hp = new D.OnePole(sr, P.hp);
  const growl = new D.Lfo(sr, 'sine', rng.float());
  const vib = new D.Lfo(sr, 'sine');
  const out = zeros(n);
  let jit = 0, lastPhase = 0;
  const fEnv = D.envelope(sr, P.f0.map(([t, h]) => [t, h]), { exp: true });
  for (let i = 0; i < n; i++) {
    if (src.phase < lastPhase) jit = rng.range(-P.jitter, P.jitter); // new glottal cycle
    lastPhase = src.phase;
    const base = i < fEnv.length ? fEnv[i] : fEnv[fEnv.length - 1];
    const f = base * (1 + jit) * (1 + P.vib * vib.next(P.vibRate));
    const voiced = src.next(f, P.pw);
    const x = voiced * (1 - P.breath) + nz.next() * P.breath;
    let y = 0;
    for (let k = 0; k < bands.length; k++) {
      const [bf, bq, bg] = P.formants[k];
      bands[k].set(bf, bq);
      y += bands[k].bp(x) * bg;
    }
    y = y * 0.8 + x * 0.1;
    if (ringF) y += ringF.bp(x) * P.ringGain;
    const g = 1 - P.growl * 0.5 * (1 + growl.next(P.growlRate));
    out[i] = Math.tanh(lp.lp(hp.hp(y)) * P.drive * g) * e[i];
  }
  return out;
}

module.exports = {
  env, applyEnv, noise, filterChain, burst, thump, tone, fmHit, sweep, chirp, crackle, bubbles, drip, splash, rattle, zap, buzz, wind,
  seamless, room, mix, pitch, tidy, vocal,
};
