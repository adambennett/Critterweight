'use strict';
// Synth voices for the sequencer. Every instrument is a factory `make(params) -> {render, tail}`;
// `render(note, sr, rng)` returns a mono Float64Array covering the gate plus the release tail.
// note = { freq, dur (gate seconds), vel 0..1, glideFrom (Hz|0) }. Drums ignore freq unless noted.

const D = require('./dsp');
const { TAU, zeros, secs, clamp, db } = D;

// ---------------------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------------------

function withEnv(sr, n, fn) { // allocate + fill
  const out = zeros(n);
  for (let i = 0; i < n; i++) out[i] = fn(i, i / sr);
  return out;
}

function vibrato(sr, rate, depth, delay) {
  // returns function(i) -> pitch multiplier
  const lfo = new D.Lfo(sr, 'sine');
  const nd = secs(sr, delay);
  return (i) => {
    const v = lfo.next(rate);
    const d = i < nd ? (i / nd) * depth : depth;
    return 1 + v * d;
  };
}

function glideFreq(note, sr, time = 0.06) {
  // returns function(i) -> freq with portamento from note.glideFrom
  if (!note.glideFrom || note.glideFrom <= 0) return () => note.freq;
  const n = Math.max(1, secs(sr, time));
  const ratio = note.freq / note.glideFrom;
  return (i) => (i >= n ? note.freq : note.glideFrom * Math.pow(ratio, i / n));
}

function softClip(x) { return Math.tanh(x); }

// ---------------------------------------------------------------------------------------
// Melodic instruments
// ---------------------------------------------------------------------------------------

/** 3-operator FM brass: carrier 1:1 modulator with feedback, second modulator at 2x. */
function fmBrass(p = {}) {
  const P = Object.assign({ index: 2.6, feedback: 0.25, index2: 0.6, a: 0.03, d: 0.18, s: 0.75, r: 0.14, cutoff: 5200, detune: 0.3, drive: 1.3, vib: 0.004 }, p);
  return {
    tail: P.r + 0.05,
    render(note, sr) {
      const env = D.adsr(sr, { a: P.a, d: P.d, s: P.s, r: P.r, dur: note.dur, curve: 1.6 });
      const n = env.length;
      const idxEnv = D.adsr(sr, { a: P.a * 0.6, d: P.d * 1.4, s: 0.55, r: P.r, dur: note.dur, curve: 1.2 });
      const c1 = new D.FmOp(sr), m1 = new D.FmOp(sr, 0.13), m2 = new D.FmOp(sr, 0.41);
      const c2 = new D.FmOp(sr, 0.5), m1b = new D.FmOp(sr, 0.77), m2b = new D.FmOp(sr, 0.23);
      const lp = new D.SVF(sr, P.cutoff, 0.8);
      const vib = vibrato(sr, 5.2, P.vib, 0.18);
      const fq = glideFreq(note, sr);
      const det = Math.pow(2, P.detune / 1200);
      let fb1 = 0, fb2 = 0;
      const out = zeros(n);
      const vel = 0.5 + 0.5 * note.vel;
      for (let i = 0; i < n; i++) {
        const f = fq(i) * vib(i);
        const idx = P.index * idxEnv[i] * vel;
        const mm2 = m2.next(f * 2) * P.index2 * idxEnv[i];
        const mm1 = m1.next(f, fb1 * P.feedback + mm2);
        fb1 = mm1;
        const v1 = c1.next(f, mm1 * idx);
        const mm2b = m2b.next(f * det * 2) * P.index2 * idxEnv[i];
        const mm1b = m1b.next(f * det, fb2 * P.feedback + mm2b);
        fb2 = mm1b;
        const v2 = c2.next(f * det, mm1b * idx);
        lp.set(P.cutoff * (0.5 + 0.5 * env[i]) * (0.6 + 0.4 * note.vel), 0.8);
        out[i] = softClip(lp.lp((v1 + v2) * 0.5) * P.drive) * env[i] * vel;
      }
      return out;
    },
  };
}

/** Muted trumpet: narrow FM with a formant band and vibrato; `flat` detunes in cents. */
function mutedTrumpet(p = {}) {
  const P = Object.assign({ index: 1.4, a: 0.04, d: 0.12, s: 0.8, r: 0.12, formant: 1150, flat: 0, vib: 0.006, vibRate: 5.4, breath: 0.03 }, p);
  return {
    tail: P.r + 0.05,
    render(note, sr, rng) {
      const env = D.adsr(sr, { a: P.a, d: P.d, s: P.s, r: P.r, dur: note.dur, curve: 1.5 });
      const n = env.length;
      const c = new D.FmOp(sr), m = new D.FmOp(sr, 0.2);
      const f1 = new D.SVF(sr, P.formant, 2.2), f2 = new D.SVF(sr, P.formant * 2.1, 2.5), lp = new D.SVF(sr, 3800, 0.7);
      const vib = vibrato(sr, P.vibRate, P.vib, 0.16);
      const fq = glideFreq(note, sr, 0.08);
      const flat = Math.pow(2, P.flat / 1200);
      const noise = new D.Noise(rng);
      const out = zeros(n);
      const vel = 0.55 + 0.45 * note.vel;
      for (let i = 0; i < n; i++) {
        const f = fq(i) * vib(i) * flat;
        const idx = P.index * (0.6 + 0.4 * env[i]);
        const v = c.next(f, m.next(f) * idx);
        const breath = noise.next() * P.breath * env[i];
        const x = v + breath;
        const y = f1.bp(x) * 1.2 + f2.bp(x) * 0.5 + x * 0.25;
        out[i] = softClip(lp.lp(y) * 1.6) * env[i] * vel;
      }
      return out;
    },
  };
}

function subBass(p = {}) {
  const P = Object.assign({ a: 0.006, d: 0.08, s: 0.9, r: 0.09, drive: 1.6, harm: 0.12 }, p);
  return {
    tail: P.r + 0.02,
    render(note, sr) {
      const env = D.adsr(sr, { a: P.a, d: P.d, s: P.s, r: P.r, dur: note.dur, curve: 1.4 });
      const n = env.length;
      const o = new D.Osc(sr, 'sine'), o2 = new D.Osc(sr, 'sine');
      const fq = glideFreq(note, sr, 0.04);
      const out = zeros(n);
      const vel = 0.7 + 0.3 * note.vel;
      for (let i = 0; i < n; i++) {
        const f = fq(i);
        const v = o.next(f) + o2.next(f * 2) * P.harm;
        out[i] = Math.tanh(v * P.drive) / Math.tanh(P.drive) * env[i] * vel;
      }
      return out;
    },
  };
}

/** Pulse-wave bass with a filter envelope and a sine sub an octave down. */
function squareBass(p = {}) {
  const P = Object.assign({ pw: 0.5, a: 0.004, d: 0.14, s: 0.55, r: 0.06, cutoff: 2600, floor: 260, q: 1.3, sub: 0.45, drive: 1.4, fenv: 0.2 }, p);
  return {
    tail: P.r + 0.02,
    render(note, sr) {
      const env = D.adsr(sr, { a: P.a, d: P.d, s: P.s, r: P.r, dur: note.dur, curve: 1.5 });
      const fenv = D.adsr(sr, { a: 0.002, d: P.fenv, s: 0.15, r: P.r, dur: note.dur, curve: 2 });
      const n = env.length;
      const o = new D.Osc(sr, 'pulse'), sub = new D.Osc(sr, 'sine');
      const lp = new D.SVF(sr, P.cutoff, P.q);
      const fq = glideFreq(note, sr, 0.03);
      const out = zeros(n);
      const vel = 0.6 + 0.4 * note.vel;
      for (let i = 0; i < n; i++) {
        const f = fq(i);
        lp.set(P.floor + (P.cutoff - P.floor) * fenv[i] * (0.6 + 0.4 * note.vel), P.q);
        const v = lp.lp(o.next(f, P.pw)) + sub.next(f * 0.5) * P.sub;
        out[i] = Math.tanh(v * P.drive) * env[i] * vel;
      }
      return out;
    },
  };
}

/** Reese bass: two detuned saws beating slowly, low-passed, with a sine sub. */
function reeseBass(p = {}) {
  const P = Object.assign({ detune: 35, cutoff: 620, q: 0.9, a: 0.012, d: 0.2, s: 0.8, r: 0.1, sub: 0.5, drive: 1.5 }, p);
  return {
    tail: P.r + 0.03,
    render(note, sr) {
      const env = D.adsr(sr, { a: P.a, d: P.d, s: P.s, r: P.r, dur: note.dur, curve: 1.4 });
      const n = env.length;
      const a = new D.Osc(sr, 'saw', 0.1), b = new D.Osc(sr, 'saw', 0.6), sub = new D.Osc(sr, 'sine');
      const lp = new D.SVF(sr, P.cutoff, P.q);
      const fq = glideFreq(note, sr, 0.05);
      const r1 = Math.pow(2, P.detune / 2400), r2 = Math.pow(2, -P.detune / 2400);
      const out = zeros(n);
      const vel = 0.6 + 0.4 * note.vel;
      for (let i = 0; i < n; i++) {
        const f = fq(i);
        const v = (a.next(f * r1) + b.next(f * r2)) * 0.5;
        lp.set(P.cutoff * (0.7 + 0.5 * env[i]), P.q);
        out[i] = Math.tanh((lp.lp(v) + sub.next(f * 0.5) * P.sub) * P.drive) * env[i] * vel;
      }
      return out;
    },
  };
}

/** Detuned supersaw lead with filter envelope and delayed vibrato. */
function sawLead(p = {}) {
  const P = Object.assign({ voices: 5, detune: 14, cutoff: 6000, floor: 900, q: 0.9, a: 0.012, d: 0.25, s: 0.7, r: 0.16, vib: 0.007, vibRate: 5.6, drive: 1.2 }, p);
  return {
    tail: P.r + 0.05,
    render(note, sr, rng) {
      const env = D.adsr(sr, { a: P.a, d: P.d, s: P.s, r: P.r, dur: note.dur, curve: 1.5 });
      const fenv = D.adsr(sr, { a: 0.005, d: 0.35, s: 0.45, r: P.r, dur: note.dur, curve: 1.8 });
      const n = env.length;
      const ss = new D.Supersaw(sr, P.voices, P.detune, rng);
      const lp = new D.SVF(sr, P.cutoff, P.q);
      const vib = vibrato(sr, P.vibRate, P.vib, 0.22);
      const fq = glideFreq(note, sr, 0.07);
      const out = zeros(n);
      const vel = 0.6 + 0.4 * note.vel;
      for (let i = 0; i < n; i++) {
        const f = fq(i) * vib(i);
        lp.set(P.floor + (P.cutoff - P.floor) * fenv[i], P.q);
        out[i] = Math.tanh(lp.lp(ss.next(f)) * P.drive) * env[i] * vel;
      }
      return out;
    },
  };
}

/** Hard-sync "screaming" lead: the slave frequency sweeps against the master. */
function syncLead(p = {}) {
  const P = Object.assign({ ratioLow: 1.6, ratioHigh: 3.4, sweep: 0.4, a: 0.01, d: 0.3, s: 0.8, r: 0.18, cutoff: 7000, vib: 0.009, drive: 1.6 }, p);
  return {
    tail: P.r + 0.05,
    render(note, sr) {
      const env = D.adsr(sr, { a: P.a, d: P.d, s: P.s, r: P.r, dur: note.dur, curve: 1.5 });
      const n = env.length;
      const s1 = new D.SyncSaw(sr), s2 = new D.SyncSaw(sr);
      const lp = new D.SVF(sr, P.cutoff, 0.8);
      const vib = vibrato(sr, 6.0, P.vib, 0.15);
      const fq = glideFreq(note, sr, 0.06);
      const out = zeros(n);
      const ns = secs(sr, P.sweep);
      const vel = 0.6 + 0.4 * note.vel;
      for (let i = 0; i < n; i++) {
        const f = fq(i) * vib(i);
        const k = i < ns ? i / ns : 1;
        const ratio = P.ratioHigh - (P.ratioHigh - P.ratioLow) * k * 0.6;
        const v = (s1.next(f, f * ratio) + s2.next(f * 1.003, f * ratio * 0.98)) * 0.5;
        out[i] = Math.tanh(lp.lp(v) * P.drive) * env[i] * vel;
      }
      return out;
    },
  };
}

/** Chip-style pulse arpeggio voice. */
function pulseArp(p = {}) {
  const P = Object.assign({ pw: 0.25, a: 0.002, d: 0.16, s: 0.25, r: 0.05, cutoff: 4200 }, p);
  return {
    tail: P.r + 0.02,
    render(note, sr) {
      const env = D.adsr(sr, { a: P.a, d: P.d, s: P.s, r: P.r, dur: note.dur, curve: 1.8 });
      const n = env.length;
      const o = new D.Osc(sr, 'pulse');
      const lp = new D.SVF(sr, P.cutoff, 0.7);
      const out = zeros(n);
      const vel = 0.6 + 0.4 * note.vel;
      for (let i = 0; i < n; i++) out[i] = lp.lp(o.next(note.freq, P.pw)) * env[i] * vel * 0.8;
      return out;
    },
  };
}

/** Electric piano: FM tine over a warm body, tremolo, optional lo-fi lowpass. */
function epiano(p = {}) {
  const P = Object.assign({ tineRatio: 14, tineIndex: 1.2, tineDecay: 0.08, decay: 1.6, trem: 4.2, tremDepth: 0.18, cutoff: 3200, r: 0.25 }, p);
  return {
    tail: P.r + 0.1,
    render(note, sr) {
      const gate = Math.min(note.dur, P.decay);
      const env = D.adsr(sr, { a: 0.003, d: P.decay, s: 0.0001, r: P.r, dur: gate, curve: 2.2 });
      const n = env.length;
      const c = new D.FmOp(sr), t = new D.FmOp(sr), b2 = new D.Osc(sr, 'sine', 0.3);
      const tine = D.decay(sr, Math.max(0.05, P.tineDecay * 3), 0.33);
      const lp = new D.SVF(sr, P.cutoff, 0.7);
      const lfo = new D.Lfo(sr, 'sine', 0.25);
      const out = zeros(n);
      const vel = 0.5 + 0.5 * note.vel;
      for (let i = 0; i < n; i++) {
        const ti = i < tine.length ? tine[i] : 0;
        const v = c.next(note.freq, t.next(note.freq * P.tineRatio) * P.tineIndex * ti * note.vel) + b2.next(note.freq * 2) * 0.15 * env[i];
        const trem = 1 - P.tremDepth * 0.5 * (1 + lfo.next(P.trem));
        out[i] = lp.lp(v) * env[i] * vel * trem;
      }
      return out;
    },
  };
}

/** Whistle: sine with breath noise, vibrato and portamento. */
function whistle(p = {}) {
  const P = Object.assign({ a: 0.05, d: 0.1, s: 0.85, r: 0.12, vib: 0.012, vibRate: 5.0, breath: 0.08 }, p);
  return {
    tail: P.r + 0.05,
    render(note, sr, rng) {
      const env = D.adsr(sr, { a: P.a, d: P.d, s: P.s, r: P.r, dur: note.dur, curve: 1.4 });
      const n = env.length;
      const o = new D.Osc(sr, 'sine'), o2 = new D.Osc(sr, 'sine', 0.4);
      const noise = new D.Noise(rng);
      const bp = new D.SVF(sr, note.freq * 1.0, 4);
      const vib = vibrato(sr, P.vibRate, P.vib, 0.12);
      const fq = glideFreq(note, sr, 0.09);
      const out = zeros(n);
      for (let i = 0; i < n; i++) {
        const f = fq(i) * vib(i);
        bp.set(f, 6);
        const v = o.next(f) + o2.next(f * 2.001) * 0.08 + bp.bp(noise.next()) * P.breath;
        out[i] = v * env[i] * (0.6 + 0.4 * note.vel);
      }
      return out;
    },
  };
}

/** Choir-ish pad: detuned saws through three vowel formant filters; slow attack. */
function choirPad(p = {}) {
  const P = Object.assign({ a: 0.4, d: 0.3, s: 0.9, r: 0.6, vowel: 'ah', detune: 9, voices: 4, lp: 5000 }, p);
  const FORMANTS = { ah: [[730, 1090, 2440], [1, 0.5, 0.2]], oh: [[570, 840, 2410], [1, 0.45, 0.15]], oo: [[300, 870, 2240], [1, 0.3, 0.1]], ee: [[270, 2290, 3010], [0.8, 0.4, 0.3]], eh: [[530, 1840, 2480], [1, 0.5, 0.2]] };
  return {
    tail: P.r + 0.1,
    render(note, sr, rng) {
      const env = D.adsr(sr, { a: P.a, d: P.d, s: P.s, r: P.r, dur: note.dur, curve: 1.3 });
      const n = env.length;
      const ss = new D.Supersaw(sr, P.voices, P.detune, rng);
      const [fs, gs] = FORMANTS[P.vowel] || FORMANTS.ah;
      const bands = fs.map((f) => new D.SVF(sr, f, 7));
      const lp = new D.SVF(sr, P.lp, 0.7);
      const out = zeros(n);
      const vel = 0.5 + 0.5 * note.vel;
      for (let i = 0; i < n; i++) {
        const x = ss.next(note.freq);
        let y = x * 0.12;
        for (let k = 0; k < bands.length; k++) y += bands[k].bp(x) * gs[k];
        out[i] = lp.lp(y) * env[i] * vel * 0.9;
      }
      return out;
    },
  };
}

/** Bell: FM with ratio 3.5 (inharmonic) and a long decay. */
function bell(p = {}) {
  const P = Object.assign({ ratio: 3.5, index: 2.2, decay: 2.4, idxDecay: 0.6, detune: 4 }, p);
  return {
    tail: 0.05,
    render(note, sr) {
      const n = secs(sr, P.decay);
      const env = D.decay(sr, P.decay, 0.3, 0.002);
      const ienv = D.decay(sr, P.decay, P.idxDecay / P.decay, 0.001);
      const c = new D.FmOp(sr), m = new D.FmOp(sr), c2 = new D.FmOp(sr, 0.3), m2 = new D.FmOp(sr, 0.5);
      const det = Math.pow(2, P.detune / 1200);
      const out = zeros(n);
      const vel = 0.5 + 0.5 * note.vel;
      for (let i = 0; i < n; i++) {
        const idx = P.index * ienv[i];
        const v = c.next(note.freq, m.next(note.freq * P.ratio) * idx) + c2.next(note.freq * det, m2.next(note.freq * det * P.ratio) * idx) * 0.6;
        out[i] = v * 0.6 * env[i] * vel;
      }
      return out;
    },
  };
}

/** Foghorn: low square+saw, slow swell, pitch sag, saturated and low-passed. */
function foghorn(p = {}) {
  const P = Object.assign({ a: 0.35, r: 0.6, cutoff: 420, sag: 0.03, drive: 2.2 }, p);
  return {
    tail: P.r + 0.1,
    render(note, sr) {
      const env = D.adsr(sr, { a: P.a, d: 0.2, s: 0.9, r: P.r, dur: note.dur, curve: 1.3 });
      const n = env.length;
      const sq = new D.Osc(sr, 'square'), sw = new D.Osc(sr, 'saw', 0.5), sub = new D.Osc(sr, 'sine');
      const lp = new D.SVF(sr, P.cutoff, 1.4);
      const out = zeros(n);
      for (let i = 0; i < n; i++) {
        const f = note.freq * (1 - P.sag * (1 - env[i]));
        const v = sq.next(f) * 0.5 + sw.next(f * 1.005) * 0.4 + sub.next(f * 0.5) * 0.5;
        out[i] = Math.tanh(lp.lp(v) * P.drive) * env[i] * (0.6 + 0.4 * note.vel);
      }
      return out;
    },
  };
}

function sine(p = {}) {
  const P = Object.assign({ a: 0.01, d: 0.1, s: 0.8, r: 0.1, harm2: 0 }, p);
  return {
    tail: P.r + 0.02,
    render(note, sr) {
      const env = D.adsr(sr, { a: P.a, d: P.d, s: P.s, r: P.r, dur: note.dur });
      const o = new D.Osc(sr, 'sine'), o2 = new D.Osc(sr, 'sine');
      const fq = glideFreq(note, sr);
      return withEnv(sr, env.length, (i) => (o.next(fq(i)) + o2.next(fq(i) * 2) * P.harm2) * env[i] * note.vel);
    },
  };
}

/** Organ-ish stacked sines (used for the hub radio's warm chords). */
function organ(p = {}) {
  const P = Object.assign({ a: 0.03, r: 0.12, drawbars: [1, 0.6, 0.35, 0.2], lp: 2600, trem: 0 }, p);
  return {
    tail: P.r + 0.02,
    render(note, sr) {
      const env = D.adsr(sr, { a: P.a, d: 0.05, s: 0.95, r: P.r, dur: note.dur });
      const oscs = P.drawbars.map((_, k) => new D.Osc(sr, 'sine', k * 0.21));
      const lp = new D.SVF(sr, P.lp, 0.7);
      const lfo = new D.Lfo(sr);
      return withEnv(sr, env.length, (i) => {
        let v = 0;
        for (let k = 0; k < oscs.length; k++) v += oscs[k].next(note.freq * (k + 1)) * P.drawbars[k];
        const t = P.trem ? 1 - P.trem * 0.5 * (1 + lfo.next(5.5)) : 1;
        return lp.lp(v) * env[i] * (0.5 + 0.5 * note.vel) * 0.5 * t;
      });
    },
  };
}

/** Plucked string (Karplus-Strong) for the radio's lazy guitar comping. */
function pluck(p = {}) {
  const P = Object.assign({ decay: 1.2, damp: 0.4, bright: 0.6 }, p);
  return {
    tail: 0.05,
    render(note, sr, rng) {
      const n = secs(sr, P.decay);
      const period = Math.max(2, Math.round(sr / note.freq));
      const ring = zeros(period);
      const hp = new D.OnePole(sr, 60);
      for (let i = 0; i < period; i++) ring[i] = (rng.float() * 2 - 1) * (i < period * P.bright ? 1 : 0.3);
      const out = zeros(n);
      let idx = 0, last = 0;
      const fb = 0.996 - (1 - P.damp) * 0.004;
      for (let i = 0; i < n; i++) {
        const cur = ring[idx];
        const nxt = ring[(idx + 1) % period];
        const v = (cur + nxt) * 0.5 * fb;
        ring[idx] = v * (1 - P.damp * 0.3) + last * P.damp * 0.3;
        last = v;
        idx = (idx + 1) % period;
        out[i] = hp.hp(cur) * (0.5 + 0.5 * note.vel) * (1 - i / n);
      }
      return out;
    },
  };
}

// ---------------------------------------------------------------------------------------
// Drums
// ---------------------------------------------------------------------------------------

function kick(p = {}) {
  const P = Object.assign({ start: 160, end: 44, sweep: 0.035, decay: 0.42, click: 0.5, drive: 1.9, tone: 0.1 }, p);
  return {
    tail: 0,
    render(note, sr, rng) {
      const n = secs(sr, P.decay);
      const env = D.decay(sr, P.decay, 0.3, 0.0005);
      const o = new D.Osc(sr, 'sine');
      const noise = new D.Noise(rng);
      const hp = new D.Biquad(sr, 'highpass', 1800, 0.7);
      const out = zeros(n);
      const nclick = secs(sr, 0.0025);
      const ns = secs(sr, P.sweep);
      for (let i = 0; i < n; i++) {
        const k = i < ns ? Math.exp(-i / (ns * 0.35)) : 0;
        const f = P.end + (P.start - P.end) * k;
        let v = o.next(f);
        v = Math.tanh(v * P.drive) * (1 + P.tone * 0.5);
        if (i < nclick) v += hp.process(noise.next()) * P.click * (1 - i / nclick);
        out[i] = v * env[i] * (0.7 + 0.3 * note.vel);
      }
      return out;
    },
  };
}

function snare(p = {}) {
  const P = Object.assign({ tone: 190, decay: 0.22, noiseDecay: 0.26, body: 0.6, snap: 1.0, bp: 1900, hp: 350 }, p);
  return {
    tail: 0,
    render(note, sr, rng) {
      const n = secs(sr, Math.max(P.decay, P.noiseDecay) + 0.02);
      const envB = D.decay(sr, P.decay, 0.25, 0.0005);
      const envN = D.decay(sr, P.noiseDecay, 0.3, 0.0005);
      const o1 = new D.Osc(sr, 'sine'), o2 = new D.Osc(sr, 'tri', 0.3);
      const noise = new D.Noise(rng);
      const bp = new D.Biquad(sr, 'bandpass', P.bp, 0.7), hp = new D.Biquad(sr, 'highpass', P.hp, 0.7);
      const out = zeros(n);
      const vel = 0.6 + 0.4 * note.vel;
      for (let i = 0; i < n; i++) {
        const k = Math.exp(-i / (sr * 0.012));
        const body = (o1.next(P.tone * (1 + 1.2 * k)) + o2.next(P.tone * 1.78 * (1 + 0.8 * k)) * 0.5) * (i < envB.length ? envB[i] : 0) * P.body;
        const nz = noise.next();
        const sn = (bp.process(nz) * 1.6 + hp.process(nz) * 0.6) * (i < envN.length ? envN[i] : 0) * P.snap;
        out[i] = Math.tanh((body + sn) * 1.6) * vel;
      }
      return out;
    },
  };
}

function clap(p = {}) {
  const P = Object.assign({ bursts: 4, spacing: 0.011, decay: 0.2, bp: 1300 }, p);
  return {
    tail: 0,
    render(note, sr, rng) {
      const n = secs(sr, P.decay + P.spacing * P.bursts);
      const noise = new D.Noise(rng);
      const bp = new D.Biquad(sr, 'bandpass', P.bp, 0.8), hp = new D.Biquad(sr, 'highpass', 600, 0.7);
      const out = zeros(n);
      const sp = secs(sr, P.spacing);
      const tailStart = sp * P.bursts;
      for (let i = 0; i < n; i++) {
        let env;
        if (i < tailStart) { const k = i % sp; env = Math.exp(-k / (sp * 0.35)); }
        else env = Math.exp(-(i - tailStart) / (sr * P.decay * 0.33)) * (1 - (i - tailStart) / (n - tailStart));
        const nz = noise.next();
        out[i] = Math.tanh((bp.process(nz) * 2.2 + hp.process(nz) * 0.4) * env * 1.5) * (0.6 + 0.4 * note.vel);
      }
      return out;
    },
  };
}

function hat(p = {}) {
  const P = Object.assign({ decay: 0.06, open: false, hp: 7200, base: 320, metal: 0.8 }, p);
  const ratios = [1, 1.342, 1.2312, 1.6532, 1.9254, 2.1538];
  return {
    tail: 0,
    render(note, sr, rng) {
      const dec = P.open ? Math.max(P.decay, 0.4) : P.decay;
      const n = secs(sr, dec + 0.01);
      const env = D.decay(sr, dec, P.open ? 0.4 : 0.28, 0.0005);
      const oscs = ratios.map((r, k) => new D.Osc(sr, 'square', k * 0.17));
      const noise = new D.Noise(rng);
      const hp = new D.Biquad(sr, 'highpass', P.hp, 0.9), bp = new D.Biquad(sr, 'bandpass', 10500, 0.6);
      const out = zeros(n);
      const vel = 0.5 + 0.5 * note.vel;
      for (let i = 0; i < n; i++) {
        let v = 0;
        for (let k = 0; k < 6; k++) v += oscs[k].next(P.base * ratios[k]);
        v = v / 6 * P.metal + noise.next() * (1 - P.metal) * 0.8;
        const y = hp.process(v) * 0.7 + bp.process(v) * 0.5;
        out[i] = Math.tanh(y * 2.2) * (i < env.length ? env[i] : 0) * vel * 0.9;
      }
      return out;
    },
  };
}

function tom(p = {}) {
  const P = Object.assign({ tune: 110, decay: 0.32, fm: 0, fmRatio: 1.4, wet: 0 }, p);
  return {
    tail: 0,
    render(note, sr, rng) {
      const tune = note.freq && note.freq > 20 && note.freq < 400 ? note.freq : P.tune;
      const n = secs(sr, P.decay);
      const env = D.decay(sr, P.decay, 0.3, 0.0005);
      const c = new D.FmOp(sr), m = new D.FmOp(sr);
      const noise = new D.Noise(rng);
      const bp = new D.Biquad(sr, 'bandpass', tune * 3, 1.2);
      const out = zeros(n);
      for (let i = 0; i < n; i++) {
        const k = Math.exp(-i / (sr * 0.03));
        const f = tune * (1 + 0.7 * k);
        const idx = P.fm * Math.exp(-i / (sr * 0.08));
        let v = c.next(f, m.next(f * P.fmRatio) * idx);
        if (P.wet) v += bp.process(noise.next()) * P.wet * Math.exp(-i / (sr * 0.05));
        if (i < sr * 0.002) v += noise.next() * 0.4;
        out[i] = Math.tanh(v * 1.5) * env[i] * (0.6 + 0.4 * note.vel);
      }
      return out;
    },
  };
}

function crash(p = {}) {
  const P = Object.assign({ decay: 1.8, hp: 3000, base: 410, shimmer: 0.002 }, p);
  const ratios = [1, 1.483, 1.932, 2.546, 2.63, 3.897, 4.361, 5.12];
  return {
    tail: 0,
    render(note, sr, rng) {
      const n = secs(sr, P.decay);
      const env = D.decay(sr, P.decay, 0.35, 0.002);
      const oscs = ratios.map((r, k) => new D.Osc(sr, 'square', k * 0.11));
      const noise = new D.Noise(rng);
      const hp = new D.Biquad(sr, 'highpass', P.hp, 0.7), lp = new D.OnePole(sr, 12000);
      const lfo = new D.Lfo(sr, 'sine');
      const out = zeros(n);
      for (let i = 0; i < n; i++) {
        const sh = 1 + lfo.next(3.1) * P.shimmer;
        let v = 0;
        for (let k = 0; k < ratios.length; k++) v += oscs[k].next(P.base * ratios[k] * sh);
        v = v / 8 * 0.8 + noise.next() * 0.9 * Math.exp(-i / (sr * 0.25));
        out[i] = Math.tanh(lp.lp(hp.process(v)) * 2.0) * env[i] * (0.6 + 0.4 * note.vel) * 0.8;
      }
      return out;
    },
  };
}

function ride(p = {}) { return crash(Object.assign({ decay: 0.5, hp: 5000, base: 620, shimmer: 0 }, p)); }

function rim(p = {}) {
  const P = Object.assign({ decay: 0.05, tone: 420 }, p);
  return {
    tail: 0,
    render(note, sr, rng) {
      const n = secs(sr, P.decay);
      const noise = new D.Noise(rng);
      const bp = new D.Biquad(sr, 'bandpass', P.tone, 3), bp2 = new D.Biquad(sr, 'bandpass', P.tone * 4.2, 4);
      const out = zeros(n);
      for (let i = 0; i < n; i++) {
        const e = Math.exp(-i / (n * 0.22));
        const nz = noise.next() * (i < sr * 0.001 ? 1 : 0.1);
        out[i] = Math.tanh((bp.process(nz) * 6 + bp2.process(nz) * 3) * e) * (0.6 + 0.4 * note.vel);
      }
      return out;
    },
  };
}

function shaker(p = {}) {
  const P = Object.assign({ decay: 0.09, hp: 6000 }, p);
  return {
    tail: 0,
    render(note, sr, rng) {
      const n = secs(sr, P.decay);
      const noise = new D.Noise(rng);
      const hp = new D.Biquad(sr, 'highpass', P.hp, 0.8);
      const out = zeros(n);
      const na = secs(sr, 0.006);
      for (let i = 0; i < n; i++) {
        const e = (i < na ? i / na : 1) * Math.exp(-(i - na) / (n * 0.3)) * (1 - i / n);
        out[i] = hp.process(noise.next()) * e * (0.5 + 0.5 * note.vel) * 0.9;
      }
      return out;
    },
  };
}

/** Wood knock (gavel) : short resonant bandpassed burst plus a low thump. */
function gavel(p = {}) {
  const P = Object.assign({ tone: 1150, decay: 0.09 }, p);
  return {
    tail: 0,
    render(note, sr, rng) {
      const n = secs(sr, P.decay + 0.05);
      const noise = new D.Noise(rng);
      const bp = new D.Biquad(sr, 'bandpass', P.tone, 3.5), bp2 = new D.Biquad(sr, 'bandpass', 2600, 5);
      const o = new D.Osc(sr, 'sine');
      const out = zeros(n);
      for (let i = 0; i < n; i++) {
        const e = Math.exp(-i / (sr * P.decay * 0.3));
        const nz = noise.next() * (i < sr * 0.0015 ? 1 : 0.15);
        const thump = o.next(170 * (1 + 0.8 * Math.exp(-i / (sr * 0.01)))) * Math.exp(-i / (sr * 0.03)) * 0.6;
        out[i] = Math.tanh((bp.process(nz) * 5 + bp2.process(nz) * 2) * e + thump) * (0.6 + 0.4 * note.vel);
      }
      return out;
    },
  };
}

/** Metallic clank (pipe collar, belly door, chain). */
function clank(p = {}) {
  const P = Object.assign({ base: 540, decay: 0.35, ratios: [1, 2.76, 5.4, 8.93], hp: 300 }, p);
  return {
    tail: 0,
    render(note, sr, rng) {
      const n = secs(sr, P.decay);
      const oscs = P.ratios.map((r, k) => new D.Osc(sr, 'sine', k * 0.3));
      const noise = new D.Noise(rng);
      const hp = new D.Biquad(sr, 'highpass', P.hp, 0.7);
      const out = zeros(n);
      for (let i = 0; i < n; i++) {
        let v = 0;
        for (let k = 0; k < oscs.length; k++) v += oscs[k].next(P.base * P.ratios[k]) * Math.exp(-i / (sr * P.decay * (0.5 / (k + 1)))) / (k + 1);
        if (i < sr * 0.003) v += noise.next() * 0.8;
        out[i] = Math.tanh(hp.process(v) * 2.0) * (1 - i / n) * (0.6 + 0.4 * note.vel);
      }
      return out;
    },
  };
}

/** Vinyl crackle / room noise bed as an "instrument" (one note = a long bed). */
function crackle(p = {}) {
  const P = Object.assign({ density: 60, hiss: 0.05, lp: 7000 }, p);
  return {
    tail: 0,
    render(note, sr, rng) {
      const n = secs(sr, note.dur);
      const noise = new D.Noise(rng);
      const lp = new D.OnePole(sr, P.lp);
      const hp = new D.OnePole(sr, 400);
      const out = zeros(n);
      let click = 0;
      for (let i = 0; i < n; i++) {
        if (rng.float() < P.density / sr) click = rng.range(0.3, 1) * rng.sign();
        click *= 0.9;
        out[i] = lp.lp(hp.hp(noise.next()) * P.hiss + click) * note.vel;
      }
      return out;
    },
  };
}

/** Pyro whoosh / riser: filtered noise sweep as a note (dur = sweep length). */
function whoosh(p = {}) {
  const P = Object.assign({ f0: 300, f1: 4000, q: 1.2, up: true, peakAt: 0.7, color: 'pink' }, p);
  return {
    tail: 0.1,
    render(note, sr, rng) {
      const n = secs(sr, note.dur + 0.1);
      const src = P.color === 'pink' ? new D.Pink(rng) : new D.Noise(rng);
      const f = new D.SVF(sr, P.f0, P.q);
      const out = zeros(n);
      const np = Math.max(1, Math.round(n * P.peakAt));
      for (let i = 0; i < n; i++) {
        const k = i / n;
        f.set(P.up ? P.f0 * Math.pow(P.f1 / P.f0, k) : P.f1 * Math.pow(P.f0 / P.f1, k), P.q);
        const e = i < np ? Math.pow(i / np, 1.8) : Math.pow(1 - (i - np) / (n - np), 1.6);
        out[i] = f.bp(src.next()) * 2.2 * e * note.vel;
      }
      return out;
    },
  };
}

/** Crowd murmur pad: pink noise through wandering vowel bands (a soft "room full of people"). */
function murmurPad(p = {}) {
  const P = Object.assign({ a: 0.8, r: 1.2, lp: 3000 }, p);
  return {
    tail: P.r + 0.1,
    render(note, sr, rng) {
      const env = D.adsr(sr, { a: P.a, d: 0.2, s: 0.9, r: P.r, dur: note.dur, curve: 1.2 });
      const n = env.length;
      const nz = new D.Pink(rng);
      const bands = [new D.SVF(sr, 420, 2), new D.SVF(sr, 1050, 2.5), new D.SVF(sr, 2300, 3)];
      const lfos = [new D.Lfo(sr, 'sine', rng.float()), new D.Lfo(sr, 'tri', rng.float()), new D.Lfo(sr, 'sine', rng.float())];
      const lp = new D.OnePole(sr, P.lp);
      const out = zeros(n);
      for (let i = 0; i < n; i++) {
        const x = nz.next();
        let y = 0;
        for (let b = 0; b < 3; b++) { bands[b].set([420, 1050, 2300][b] * Math.pow(2, lfos[b].next(0.09 + b * 0.07) * 0.4), 2 + b * 0.5); y += bands[b].bp(x) * [1, 0.7, 0.35][b]; }
        out[i] = lp.lp(y) * env[i] * note.vel * 0.9;
      }
      return out;
    },
  };
}

const REGISTRY = {
  fmBrass, mutedTrumpet, subBass, squareBass, reeseBass, sawLead, syncLead, pulseArp, epiano, whistle, choirPad, bell,
  foghorn, sine, organ, pluck, whoosh, murmurPad,
  kick, snare, clap, hat, hatOpen: (p) => hat(Object.assign({ open: true, decay: 0.45 }, p)), tom, crash, ride, rim, shaker, gavel, clank, crackle,
};

function make(name, params) {
  const f = REGISTRY[name];
  if (!f) throw new Error('unknown instrument ' + name);
  return f(params || {});
}

module.exports = { make, REGISTRY };
