'use strict';
// Whooshes, movement and footsteps (AUDIO_DIRECTION.md §3.2, §3.3). Bus "Movement" (-4 dB, ducked by impacts).
const K = require('../lib/sfxkit');
const D = require('../lib/dsp');
const { def, alias, jit } = require('./_def');

const MOVE = { bus: 'Movement', group: 'movement', priority: 50, max_voices: 6 };
const STEP = { bus: 'Movement', group: 'footsteps', priority: 30, max_voices: 8, gain: -6, pitch: [0.93, 1.07] };

const SURFACES = ['canvas', 'concrete', 'steel', 'plank', 'gravel'];

/** Surface character layered under each step. */
function surfaceLayer(rng, sr, surface) {
  switch (surface) {
    case 'canvas': return K.burst(sr, rng, { dur: 0.07, color: 'pink', filt: [{ type: 'lp', f: 1500 }, { type: 'hp', f: 120 }], a: 0.003, curve: 1.8, gain: 0.7 });
    case 'concrete': return K.mix(sr, [
      { buf: K.burst(sr, rng, { dur: 0.03, filt: [{ type: 'bp', f: 2200, q: 1 }], curve: 2.4 }), gain: 0 },
      { buf: K.crackle(sr, rng, { dur: 0.06, density: 500, tone: 2500, decayMs: 2, gain: 0.35 }), gain: -6 }]);
    case 'steel': return K.mix(sr, [
      { buf: K.burst(sr, rng, { dur: 0.03, filt: [{ type: 'bp', f: 1500, q: 1 }], curve: 2.2 }), gain: -2 },
      { buf: K.fmHit(sr, { f: jit(rng, 410, 0.15), ratio: 2.76, index: 0.9, dur: 0.22, idxDecay: 0.3 }), gain: -6 }]);
    case 'plank': return K.mix(sr, [
      { buf: K.burst(sr, rng, { dur: 0.05, filt: [{ type: 'bp', f: jit(rng, 520, 0.1), q: 3 }], curve: 2 }), gain: 0 },
      { buf: K.thump(sr, { f0: 160, f1: 90, dur: 0.07, drive: 1.3 }), gain: -4 }]);
    case 'gravel': return K.crackle(sr, rng, { dur: 0.12, density: 700, tone: 1900, q: 1.2, decayMs: 3, gain: 0.8 });
    default: return D.zeros(10);
  }
}

function biped(rng, sr, surface) {
  const slap = K.burst(sr, rng, { dur: 0.04, filt: [{ type: 'lp', f: 2200 }, { type: 'bp', f: 700, q: 0.8 }], curve: 2.2 });
  const th = K.thump(sr, { f0: 180, f1: jit(rng, 120, 0.08), sweep: 0.012, dur: 0.06, drive: 1.4, curve: 2.4 });
  return K.tidy(K.mix(sr, [{ buf: slap, gain: 0 }, { buf: th, gain: -2 }, { buf: surfaceLayer(rng, sr, surface), gain: -6, at: 0.003 }]), sr);
}
function crab(rng, sr, surface) {
  const t1 = K.burst(sr, rng, { dur: 0.012, filt: [{ type: 'bp', f: jit(rng, 1000, 0.08), q: 6 }], curve: 2.5, gain: 2 });
  const t2 = K.burst(sr, rng, { dur: 0.014, filt: [{ type: 'bp', f: jit(rng, 1250, 0.08), q: 6 }], curve: 2.5, gain: 2 });
  const parts = [{ buf: t1, gain: 0 }, { buf: t2, gain: -1, at: jit(rng, 0.06, 0.2) }, { buf: surfaceLayer(rng, sr, surface), gain: -12, at: 0.002 }];
  if (surface === 'plank') parts.push({ buf: K.drip(sr, rng, { f: 1800, dur: 0.07 }), gain: -10, at: 0.03 });
  return K.tidy(K.mix(sr, parts), sr);
}
function avian(rng, sr, surface) {
  const tap = K.burst(sr, rng, { dur: 0.01, filt: [{ type: 'bp', f: 2800, q: 2 }], curve: 2.5, gain: 1.5 });
  const scrape = K.sweep(sr, rng, { dur: 0.05, f0: 5000, f1: 2500, q: 1.5, peakAt: 0.2, gain: 0.35 });
  return K.tidy(K.mix(sr, [{ buf: tap, gain: 0 }, { buf: scrape, gain: -8, at: 0.008 }, { buf: surfaceLayer(rng, sr, surface), gain: -12 }]), sr);
}
function quadruped(rng, sr, surface) {
  const th = K.thump(sr, { f0: 150, f1: jit(rng, 85, 0.08), sweep: 0.03, dur: 0.13, drive: 1.9, curve: 2, harm: 0.2 });
  const body = K.burst(sr, rng, { dur: 0.05, color: 'pink', filt: [{ type: 'bp', f: 350, q: 0.9 }], curve: 2 });
  const parts = [{ buf: th, gain: 0 }, { buf: body, gain: -5 }, { buf: surfaceLayer(rng, sr, surface), gain: -5, at: 0.004 }];
  if (surface === 'gravel') parts.push({ buf: K.crackle(sr, rng, { dur: 0.2, density: 400, tone: 1600, decayMs: 4, gain: 0.6 }), gain: -8, at: 0.02 });
  return K.tidy(K.mix(sr, parts), sr);
}
function serpentDrag(rng, sr, surface) {
  const dur = 1.4;
  const n = D.secs(sr, dur);
  const nz = new D.Pink(rng);
  const f = new D.SVF(sr, 900, 0.9);
  const am = new D.Lfo(sr, 'sine', rng.float());
  const out = D.zeros(n);
  const base = { canvas: 700, concrete: 1400, steel: 1800, plank: 900, gravel: 1200 }[surface] || 900;
  for (let i = 0; i < n; i++) {
    const a = 0.55 + 0.45 * am.next(1.6);
    f.set(base * (1 + 0.2 * Math.sin(i / sr * 2.3)), 0.9);
    out[i] = f.bp(nz.next()) * 2.2 * a;
  }
  let loop = K.seamless(out, sr, 0.3);
  if (surface === 'gravel') loop = K.mix(sr, [{ buf: loop, gain: 0 }, { buf: K.seamless(K.crackle(sr, rng, { dur: loop.length / sr, density: 250, tone: 1700, decayMs: 3, gain: 0.5 }), sr, 0.2), gain: -8 }]).slice(0, loop.length);
  return loop;
}

const steps = [];
for (const s of SURFACES) {
  steps.push(def(`step_biped_${s}`, Object.assign({ variants: 3 }, STEP), (rng, sr) => biped(rng, sr, s)));
  steps.push(def(`step_crab_${s}`, Object.assign({ variants: 3 }, STEP), (rng, sr) => crab(rng, sr, s)));
  steps.push(def(`step_avian_${s}`, Object.assign({ variants: 3, gain: -9 }, STEP), (rng, sr) => avian(rng, sr, s)));
  steps.push(def(`step_quadruped_${s}`, Object.assign({ variants: 3, gain: -4 }, STEP), (rng, sr) => quadruped(rng, sr, s)));
  steps.push(def(`drag_serpent_${s}`, Object.assign({ loop: true, gain: -10, max_voices: 4, pitch: [1, 1] }, STEP), (rng, sr) => serpentDrag(rng, sr, s)));
  steps.push(def(`hop_land_${s}`, Object.assign({ variants: 3, gain: -5 }, STEP), (rng, sr) => {
    const pat = K.burst(sr, rng, { dur: 0.05, filt: [{ type: 'bp', f: 500, q: 0.8 }, { type: 'lp', f: 2500 }], curve: 2 });
    const th = K.thump(sr, { f0: 220, f1: 110, sweep: 0.015, dur: 0.07, drive: 1.5 });
    return K.tidy(K.mix(sr, [{ buf: pat, gain: 0 }, { buf: th, gain: -3 }, { buf: surfaceLayer(rng, sr, s), gain: -7, at: 0.003 }]), sr);
  }));
}

module.exports = [
  def('whoosh_light', Object.assign({ variants: 5, gain: -3 }, MOVE), (rng, sr) =>
    K.tidy(K.sweep(sr, rng, { dur: jit(rng, 0.085, 0.1), f0: jit(rng, 2000, 0.1), f1: jit(rng, 500, 0.1), q: 1.3, peakAt: 0.35 }), sr)),
  def('whoosh_heavy', Object.assign({ variants: 5 }, MOVE), (rng, sr) => {
    const sw = K.sweep(sr, rng, { dur: jit(rng, 0.17, 0.1), f0: jit(rng, 1500, 0.1), f1: jit(rng, 320, 0.1), q: 1.1, color: 'pink', peakAt: 0.4, gain: 1.4 });
    const wump = K.thump(sr, { f0: 130, f1: jit(rng, 95, 0.05), sweep: 0.03, dur: 0.16, drive: 1.3, curve: 1.6, harm: 0.1 });
    return K.tidy(K.mix(sr, [{ buf: sw, gain: 0 }, { buf: wump, gain: -7, at: 0.05 }]), sr);
  }),
  def('whoosh_spin', Object.assign({ loop: true, gain: -4, pitch: [1, 1] }, MOVE), (rng, sr) => {
    const n = D.secs(sr, 0.9);
    const nz = new D.Noise(rng);
    const f = new D.SVF(sr, 1200, 1.2);
    const lfo = new D.Lfo(sr, 'sine');
    const out = D.zeros(n);
    for (let i = 0; i < n; i++) {
      const m = lfo.next(5.5);
      f.set(900 * Math.pow(2, m * 0.9), 1.3);
      out[i] = f.bp(nz.next()) * 2 * (0.55 + 0.45 * m);
    }
    return K.seamless(out, sr, 0.2);
  }),
  def('charge_loop', Object.assign({ loop: true, gain: -3, pitch: [1, 1], priority: 60 }, MOVE), (rng, sr) => {
    const dur = 1.5;
    const n = D.secs(sr, dur);
    const bed = K.wind(sr, rng, { dur, base: 650, wander: 0.8, q: 1.0, gusts: 0.2, rate: 1.2, gain: 0.8 });
    const parts = [{ buf: bed, gain: -2 }];
    const period = 60 / 150; // gallop ~ 2.5 beats per second with a 3-hoof cluster
    for (let t = 0; t < dur - 0.05; t += period) {
      for (let h = 0; h < 3; h++) {
        parts.push({ buf: K.thump(sr, { f0: 150, f1: jit(rng, 80, 0.1), sweep: 0.02, dur: 0.1, drive: 1.8 }), gain: -2 - h * 2, at: t + h * 0.065 });
      }
    }
    return K.seamless(K.mix(sr, parts).slice(0, n), sr, 0.25);
  }),
  def('charge_release', Object.assign({ variants: 2, priority: 70 }, MOVE), (rng, sr) => {
    const sw = K.sweep(sr, rng, { dur: 0.26, f0: 1400, f1: 260, q: 1.0, color: 'pink', peakAt: 0.3, gain: 1.6 });
    const wump = K.thump(sr, { f0: 110, f1: 60, sweep: 0.05, dur: 0.22, drive: 1.6, curve: 1.6 });
    return K.tidy(K.mix(sr, [{ buf: sw, gain: 0 }, { buf: wump, gain: -4, at: 0.03 }]), sr);
  }),
  def('leap', Object.assign({ variants: 3, gain: -4 }, MOVE), (rng, sr) => {
    const hup = K.burst(sr, rng, { dur: 0.06, color: 'pink', filt: [{ type: 'bp', f: 800, q: 1.2 }], a: 0.004, curve: 1.8 });
    const flap = K.burst(sr, rng, { dur: 0.05, filt: [{ type: 'lp', f: 900 }], a: 0.01, curve: 1.4 });
    const boing = K.chirp(sr, { f0: 180, f1: 420, dur: 0.11, wave: 'tri', curve: 1.5, gain: 0.5 });
    return K.tidy(K.mix(sr, [{ buf: hup, gain: 0 }, { buf: flap, gain: -3, at: 0.03 }, { buf: boing, gain: -9, at: 0.01 }]), sr);
  }),
  def('hover_loop', Object.assign({ loop: true, gain: -10, pitch: [1, 1] }, MOVE), (rng, sr) => {
    const w = K.wind(sr, rng, { dur: 1.6, base: 1100, wander: 0.5, q: 1.4, gusts: 0.3, rate: 2.5, gain: 1 });
    const n = w.length;
    const lfo = new D.Lfo(sr, 'sine');
    for (let i = 0; i < n; i++) w[i] *= 0.7 + 0.3 * lfo.next(8);
    return K.seamless(w, sr, 0.3);
  }),
  def('dodge', Object.assign({ variants: 4, gain: -4 }, MOVE), (rng, sr) =>
    K.tidy(K.sweep(sr, rng, { dur: 0.1, f0: jit(rng, 3200, 0.1), f1: 1100, q: 1.6, peakAt: 0.3, gain: 1.1 }), sr)),
  def('blink_down', Object.assign({ variants: 2, priority: 70 }, MOVE), (rng, sr) => {
    const gurgle = K.bubbles(sr, rng, { dur: 0.3, rate: 28, fLo: 120, fHi: 500, popDur: 0.05, wet: 0.7 });
    const n = gurgle.length;
    const f = new D.SVF(sr, 3000, 0.8);
    for (let i = 0; i < n; i++) { f.set(3000 * Math.pow(0.08, i / n), 0.8); gurgle[i] = f.lp(gurgle[i]); }
    const suck = K.sweep(sr, rng, { dur: 0.3, f0: 1800, f1: 150, q: 1.2, color: 'pink', peakAt: 0.2, gain: 1.2 });
    return K.tidy(K.mix(sr, [{ buf: gurgle, gain: 0 }, { buf: suck, gain: -4 }]), sr);
  }),
  def('blink_up', Object.assign({ variants: 2, priority: 70 }, MOVE), (rng, sr) => {
    const pop = K.thump(sr, { f0: 320, f1: 120, sweep: 0.02, dur: 0.1, drive: 1.5, wave: 'sine' });
    const rise = K.bubbles(sr, rng, { dur: 0.22, rate: 30, fLo: 300, fHi: 1100, popDur: 0.035, wet: 0.6 });
    const sp = K.splash(sr, rng, { dur: 0.25, size: 0.7 });
    return K.tidy(K.mix(sr, [{ buf: pop, gain: 0 }, { buf: rise, gain: -4, at: 0.03 }, { buf: sp, gain: -7, at: 0.01 }]), sr);
  }),
  def('spring_pad', Object.assign({ variants: 3, priority: 65 }, MOVE), (rng, sr) => {
    const n = D.secs(sr, 0.28);
    const o = new D.Osc(sr, 'tri'), o2 = new D.Osc(sr, 'sine', 0.3);
    const out = D.zeros(n);
    for (let i = 0; i < n; i++) {
      const k = i / n;
      const f = 160 * Math.pow(3.6, Math.min(1, k * 2.2)) * (1 + 0.08 * Math.sin(k * 60));
      out[i] = (o.next(f) + o2.next(f * 2.02) * 0.4) * Math.pow(1 - k, 1.3) * Math.min(1, i / 40);
    }
    const clank = K.fmHit(sr, { f: 880, ratio: 2.76, index: 1, dur: 0.15, idxDecay: 0.3 });
    return K.tidy(K.mix(sr, [{ buf: out, gain: 0 }, { buf: clank, gain: -10 }]), sr);
  }),
  def('land_soft', Object.assign({ variants: 3, gain: -4 }, MOVE), (rng, sr) => biped(rng, sr, 'canvas')),
  def('land_heavy', Object.assign({ variants: 3, gain: -1, priority: 60 }, MOVE), (rng, sr) => {
    const th = K.thump(sr, { f0: 140, f1: 62, sweep: 0.04, dur: 0.2, drive: 2, harm: 0.2 });
    const dust = K.burst(sr, rng, { dur: 0.15, color: 'pink', filt: [{ type: 'lp', f: 1500 }], a: 0.01, curve: 1.6, gain: 0.7 });
    return K.tidy(K.mix(sr, [{ buf: th, gain: 0 }, { buf: dust, gain: -8, at: 0.02 }]), sr);
  }),
  def('hop_takeoff', Object.assign({ variants: 3, gain: -6 }, STEP), (rng, sr) =>
    K.tidy(K.chirp(sr, { f0: jit(rng, 170, 0.1), f1: 520, dur: 0.1, wave: 'tri', curve: 1.6, gain: 0.7 }), sr)),
  def('hop_land_wet', Object.assign({ variants: 3, gain: -5 }, STEP), (rng, sr) => {
    const splat = K.burst(sr, rng, { dur: 0.07, color: 'pink', filt: [{ type: 'bp', f: 600, q: 1 }], curve: 2 });
    const pop = K.bubbles(sr, rng, { dur: 0.09, rate: 40, fLo: 200, fHi: 700, popDur: 0.03, wet: 0.8 });
    return K.tidy(K.mix(sr, [{ buf: splat, gain: 0 }, { buf: pop, gain: -4, at: 0.01 }]), sr);
  }),
  def('step_stoke_clank', Object.assign({ variants: 2, gain: -12 }, STEP), (rng, sr) =>
    K.tidy(K.fmHit(sr, { f: jit(rng, 470, 0.08), ratio: 2.76, index: 1.1, dur: 0.18, idxDecay: 0.3 }), sr)),
  def('flap', Object.assign({ variants: 3, gain: -7 }, STEP), (rng, sr) => {
    const a = K.burst(sr, rng, { dur: 0.06, filt: [{ type: 'lp', f: 1000 }, { type: 'hp', f: 150 }], a: 0.012, curve: 1.3 });
    const b = K.burst(sr, rng, { dur: 0.05, filt: [{ type: 'lp', f: 800 }, { type: 'hp', f: 150 }], a: 0.01, curve: 1.3 });
    return K.tidy(K.mix(sr, [{ buf: a, gain: 0 }, { buf: b, gain: -2, at: 0.09 }]), sr);
  }),
  def('serpent_drip', Object.assign({ variants: 3, gain: -12 }, STEP), (rng, sr) => K.tidy(K.drip(sr, rng, { f: 1400, dur: 0.14 }), sr)),
  def('serpent_tick', Object.assign({ variants: 3, gain: -10 }, STEP), (rng, sr) => K.tidy(K.zap(sr, rng, { dur: 0.03, f: 5000, buzz: 200, gain: 0.8 }), sr)),
  def('gravel_scatter', Object.assign({ variants: 3, gain: -8 }, STEP), (rng, sr) =>
    K.tidy(K.crackle(sr, rng, { dur: 0.25, density: 350, tone: 1500, decayMs: 4, gain: 0.8 }), sr)),
  ...steps,
  alias('dash_attack', 'whoosh_heavy', { gain: -1 }),
  alias('taunt', 'whoosh_light', { gain: -6, pitch: [0.8, 0.9] }),
];
module.exports.SURFACES = SURFACES;
