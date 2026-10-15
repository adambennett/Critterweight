'use strict';
// Impacts (AUDIO_DIRECTION.md §3.1). Bus "Impacts": never ducked, highest stealing priority.
const K = require('../lib/sfxkit');
const D = require('../lib/dsp');
const { def, alias, jit } = require('./_def');

const IMPACT = { bus: 'Impacts', group: 'impacts', priority: 90, max_voices: 8 };

function lightHit(rng, sr, k) {
  const f = rng.range(420, 900);
  const crack = K.burst(sr, rng, { dur: 0.06, filt: [{ type: 'bp', f, q: 0.9 }, { type: 'hp', f: 300 }, { type: 'lp', f: 1400 }], curve: 2.2 });
  const th = K.thump(sr, { f0: jit(rng, 150, 0.1), f1: jit(rng, 90, 0.08), sweep: 0.02, dur: 0.045, curve: 2.5, drive: 1.3 });
  const click = K.burst(sr, rng, { dur: 0.004, filt: [{ type: 'hp', f: 2500 }], curve: 3 });
  return K.tidy(K.mix(sr, [{ buf: crack, gain: 0 }, { buf: th, gain: -3 }, { buf: click, gain: -8 }]), sr);
}

function heavyHit(rng, sr, k) {
  const th = K.thump(sr, { f0: jit(rng, 170, 0.1), f1: jit(rng, 55, 0.06), sweep: 0.045, dur: 0.14, curve: 2.0, drive: 2.2, harm: 0.25 });
  const crack = K.burst(sr, rng, { dur: 0.022, filt: [{ type: 'bp', f: rng.range(2200, 4800), q: 0.8 }, { type: 'hp', f: 1800 }], curve: 2.4 });
  const body = K.burst(sr, rng, { dur: 0.09, filt: [{ type: 'bp', f: rng.range(250, 500), q: 1.0 }], curve: 2 });
  const dry = K.mix(sr, [{ buf: th, gain: 0 }, { buf: crack, gain: -4 }, { buf: body, gain: -6 }]);
  const slap = K.room(dry, sr, { size: 0.22, mix: 0.35, damp: 0.6, predelay: 0.006, gate: 0.09 });
  return K.tidy(K.mix(sr, [{ buf: dry, gain: 0 }, { buf: slap, gain: -8, at: 0.004 }], 0.05), sr);
}

module.exports = [
  def('hit_light', Object.assign({ variants: 6, cooldown: 0.02 }, IMPACT), lightHit),
  def('hit_heavy', Object.assign({ variants: 6, cooldown: 0.03 }, IMPACT), heavyHit),
  def('hit_layer_chitin', Object.assign({ variants: 4, gain: -3 }, IMPACT), (rng, sr) => {
    const f = jit(rng, 800, 0.12);
    const ping = K.tone(sr, { f, dur: 0.03, wave: 'sine', a: 0.0005, d: 0.02, s: 0.2, r: 0.015, gain: 0.9 });
    const res = K.burst(sr, rng, { dur: 0.04, filt: [{ type: 'bp', f, q: 12 }, { type: 'bp', f: f * 2.4, q: 8 }], curve: 2, gain: 3 });
    return K.tidy(K.mix(sr, [{ buf: ping, gain: 0 }, { buf: res, gain: -2 }]), sr);
  }),
  def('hit_layer_jelly', Object.assign({ variants: 4, gain: -3 }, IMPACT), (rng, sr) => {
    const n = D.secs(sr, 0.11);
    const nz = new D.Pink(rng);
    const f = new D.SVF(sr, 700, 2.5);
    const lfo = new D.Lfo(sr, 'sine', rng.float());
    const out = D.zeros(n);
    for (let i = 0; i < n; i++) {
      const kk = i / n;
      f.set(jit(rng, 1, 0) * 650 * (1 + 0.6 * lfo.next(22 + 14 * kk)) * (1 - 0.4 * kk), 2.5);
      out[i] = f.bp(nz.next()) * 3 * Math.pow(1 - kk, 1.5) * Math.min(1, i / 40);
    }
    const pop = K.bubbles(sr, rng, { dur: 0.08, rate: 40, fLo: 250, fHi: 600, popDur: 0.03 });
    return K.tidy(K.mix(sr, [{ buf: out, gain: 0 }, { buf: pop, gain: -6, at: 0.02 }]), sr);
  }),
  def('hit_guard', Object.assign({ variants: 4, cooldown: 0.02 }, IMPACT), (rng, sr) => {
    const th = K.thump(sr, { f0: jit(rng, 210, 0.1), f1: jit(rng, 150, 0.06), sweep: 0.015, dur: 0.08, curve: 2.2, drive: 1.5, harm: 0.05 });
    const shh = K.burst(sr, rng, { dur: 0.07, filt: [{ type: 'hp', f: 2500 }, { type: 'lp', f: 7000 }], a: 0.004, curve: 1.6, gain: 0.5 });
    return K.tidy(K.mix(sr, [{ buf: th, gain: 0 }, { buf: shh, gain: -9, at: 0.005 }]), sr);
  }),
  def('parry', Object.assign({ variants: 3, cooldown: 0.05, priority: 95 }, IMPACT), (rng, sr) => {
    const ting = K.fmHit(sr, { f: jit(rng, 1760, 0.06), ratio: 2.01, index: 2.8, dur: 0.22, idxDecay: 0.3, detune: 6 });
    const whip = K.sweep(sr, rng, { dur: 0.06, f0: 3500, f1: 900, q: 1.5, peakAt: 0.25 });
    const spark = K.burst(sr, rng, { dur: 0.012, filt: [{ type: 'hp', f: 5000 }], curve: 2 });
    return K.tidy(K.mix(sr, [{ buf: ting, gain: 0 }, { buf: whip, gain: -5 }, { buf: spark, gain: -6 }]), sr);
  }),
  def('wall_splat_fence', Object.assign({ variants: 4, priority: 85 }, IMPACT), (rng, sr) => {
    const boom = K.thump(sr, { f0: 110, f1: jit(rng, 48, 0.1), sweep: 0.05, dur: 0.32, curve: 1.8, drive: 2, harm: 0.2 });
    const rat = K.rattle(sr, rng, { dur: 0.42, f: jit(rng, 95, 0.15), density: 50 });
    const hit = K.burst(sr, rng, { dur: 0.03, filt: [{ type: 'bp', f: 1800, q: 1 }], curve: 2 });
    return K.tidy(K.mix(sr, [{ buf: boom, gain: 0 }, { buf: rat, gain: -4 }, { buf: hit, gain: -4 }]), sr);
  }),
  def('wall_splat_concrete', Object.assign({ variants: 4, priority: 85 }, IMPACT), (rng, sr) => {
    const boom = K.thump(sr, { f0: 130, f1: jit(rng, 52, 0.1), sweep: 0.04, dur: 0.26, curve: 2, drive: 2.2 });
    const grit = K.crackle(sr, rng, { dur: 0.16, density: 300, tone: 1800, decayMs: 3, gain: 0.5 });
    const body = K.burst(sr, rng, { dur: 0.1, filt: [{ type: 'bp', f: 420, q: 1.2 }], curve: 2 });
    return K.tidy(K.mix(sr, [{ buf: boom, gain: 0 }, { buf: grit, gain: -8 }, { buf: body, gain: -4 }]), sr);
  }),
  def('wall_splat_steel', Object.assign({ variants: 4, priority: 85 }, IMPACT), (rng, sr) => {
    const boom = K.thump(sr, { f0: 120, f1: jit(rng, 50, 0.1), sweep: 0.04, dur: 0.3, curve: 2, drive: 2 });
    const ring = K.fmHit(sr, { f: jit(rng, 330, 0.1), ratio: 2.76, index: 1.4, dur: 0.45, idxDecay: 0.3 });
    const plate = K.burst(sr, rng, { dur: 0.12, filt: [{ type: 'bp', f: 900, q: 6 }, { type: 'bp', f: 2100, q: 5 }], curve: 1.6, gain: 2 });
    return K.tidy(K.mix(sr, [{ buf: boom, gain: 0 }, { buf: ring, gain: -7 }, { buf: plate, gain: -6 }]), sr);
  }),
  def('wall_splat_railing', Object.assign({ variants: 4, priority: 85 }, IMPACT), (rng, sr) => {
    const boom = K.thump(sr, { f0: 115, f1: jit(rng, 55, 0.1), sweep: 0.04, dur: 0.22, curve: 2, drive: 1.8 });
    const pipe = K.fmHit(sr, { f: jit(rng, 520, 0.08), ratio: 3.2, index: 1.2, dur: 0.5, idxDecay: 0.25, detune: 9 });
    const rat = K.rattle(sr, rng, { dur: 0.25, f: 140, density: 30, gain: 0.6 });
    return K.tidy(K.mix(sr, [{ buf: boom, gain: 0 }, { buf: pipe, gain: -6 }, { buf: rat, gain: -8, at: 0.03 }]), sr);
  }),
  def('knockdown', Object.assign({ variants: 4, priority: 88 }, IMPACT), (rng, sr) => {
    const a = K.thump(sr, { f0: 140, f1: jit(rng, 70, 0.08), sweep: 0.03, dur: 0.12, curve: 2, drive: 1.8 });
    const b = K.thump(sr, { f0: 120, f1: jit(rng, 66, 0.08), sweep: 0.03, dur: 0.14, curve: 2, drive: 1.6 });
    const pff = K.burst(sr, rng, { dur: 0.16, color: 'pink', filt: [{ type: 'lp', f: 1200 }, { type: 'hp', f: 150 }], a: 0.01, curve: 1.6, gain: 0.8 });
    return K.tidy(K.mix(sr, [{ buf: a, gain: 0 }, { buf: b, gain: -2, at: jit(rng, 0.08, 0.15) }, { buf: pff, gain: -9, at: 0.03 }]), sr);
  }),
  def('ko', Object.assign({ variants: 3, priority: 100, cooldown: 0.2 }, IMPACT), (rng, sr) => {
    const heavy = heavyHit(rng, sr, 0);
    const sub = K.chirp(sr, { f0: 85, f1: 28, dur: 0.32, wave: 'sine', curve: 1.2, a: 0.005, gain: 1 });
    const crack = K.burst(sr, rng, { dur: 0.03, filt: [{ type: 'bp', f: 3200, q: 0.8 }], curve: 2 });
    const dry = K.mix(sr, [{ buf: heavy, gain: 0 }, { buf: sub, gain: -1, at: 0.01 }, { buf: crack, gain: -3 }]);
    const slap = K.room(dry, sr, { size: 0.4, mix: 0.4, damp: 0.5, predelay: 0.012, gate: 0.16 });
    return K.tidy(K.mix(sr, [{ buf: dry, gain: 0 }, { buf: slap, gain: -7 }], 0.05), sr);
  }),
  def('ko_piece', Object.assign({ variants: 3, gain: -4, priority: 70 }, IMPACT), (rng, sr) => {
    const ping = K.fmHit(sr, { f: jit(rng, 2300, 0.08), ratio: 3.5, index: 2, dur: 0.3, idxDecay: 0.25, detune: 5 });
    const parts = [{ buf: ping, gain: 0 }];
    let t = 0.22;
    for (let i = 0; i < 4; i++) {
      parts.push({ buf: K.fmHit(sr, { f: jit(rng, 1900, 0.15), ratio: 2.01, index: 1.2, dur: 0.08, idxDecay: 0.3 }), gain: -4 - i * 3, at: t });
      t += 0.1 - i * 0.015;
    }
    return K.tidy(K.mix(sr, parts), sr);
  }),
  def('glance', Object.assign({ variants: 3, gain: -8, priority: 40 }, IMPACT), (rng, sr) =>
    K.tidy(K.burst(sr, rng, { dur: 0.045, color: 'pink', filt: [{ type: 'bp', f: rng.range(900, 1600), q: 0.8 }], a: 0.006, curve: 1.5 }), sr)),
  def('guard_break', Object.assign({ variants: 2, priority: 92 }, IMPACT), (rng, sr) => {
    const shatter = K.crackle(sr, rng, { dur: 0.25, density: 400, tone: 3200, q: 1.5, decayMs: 4, gain: 0.8 });
    const drop = K.chirp(sr, { f0: 900, f1: 180, dur: 0.22, wave: 'square', curve: 1.6, gain: 0.5 });
    const th = K.thump(sr, { f0: 150, f1: 60, sweep: 0.03, dur: 0.12, drive: 1.8 });
    return K.tidy(K.mix(sr, [{ buf: th, gain: 0 }, { buf: shatter, gain: -5 }, { buf: drop, gain: -8 }]), sr);
  }),
  def('burst', Object.assign({ variants: 2, priority: 92 }, IMPACT), (rng, sr) => {
    const rise = K.sweep(sr, rng, { dur: 0.2, f0: 300, f1: 4000, q: 1.2, peakAt: 0.9, curve: 3 });
    const pop = K.thump(sr, { f0: 220, f1: 70, sweep: 0.03, dur: 0.18, drive: 2 });
    const shimmer = K.fmHit(sr, { f: 1320, ratio: 1.5, index: 3, dur: 0.35, idxDecay: 0.4, detune: 8 });
    return K.tidy(K.mix(sr, [{ buf: rise, gain: -3 }, { buf: pop, gain: 0, at: 0.19 }, { buf: shimmer, gain: -8, at: 0.19 }]), sr);
  }),
  def('grab', Object.assign({ variants: 3, priority: 80 }, IMPACT), (rng, sr) => {
    const clap1 = K.burst(sr, rng, { dur: 0.025, filt: [{ type: 'bp', f: 1300, q: 0.9 }], curve: 2 });
    const clap2 = K.burst(sr, rng, { dur: 0.05, filt: [{ type: 'bp', f: 1000, q: 0.9 }], curve: 2 });
    const cloth = K.burst(sr, rng, { dur: 0.12, color: 'pink', filt: [{ type: 'bp', f: 600, q: 0.8 }], a: 0.01, curve: 1.4, gain: 0.7 });
    return K.tidy(K.mix(sr, [{ buf: clap1, gain: 0 }, { buf: clap2, gain: -2, at: 0.018 }, { buf: cloth, gain: -8 }]), sr);
  }),
  def('throw_release', Object.assign({ variants: 2, priority: 80, bus: 'Movement', group: 'movement' }, IMPACT), (rng, sr) => {
    const w = K.sweep(sr, rng, { dur: 0.3, f0: 1200, f1: 250, q: 1.0, color: 'pink', peakAt: 0.3, curve: 1.5, gain: 1.5 });
    const wump = K.thump(sr, { f0: 90, f1: 55, sweep: 0.05, dur: 0.2, drive: 1.4, curve: 1.6 });
    return K.tidy(K.mix(sr, [{ buf: w, gain: 0 }, { buf: wump, gain: -5, at: 0.02 }]), sr);
  }),
  def('counter', Object.assign({ variants: 2, gain: -2, priority: 85 }, IMPACT), (rng, sr) => {
    const snap = K.burst(sr, rng, { dur: 0.015, filt: [{ type: 'hp', f: 3000 }], curve: 2.5 });
    const ring = K.fmHit(sr, { f: 2640, ratio: 1.41, index: 1.5, dur: 0.18, idxDecay: 0.3 });
    return K.tidy(K.mix(sr, [{ buf: snap, gain: 0 }, { buf: ring, gain: -6 }]), sr);
  }),
  def('slam', Object.assign({ variants: 3, priority: 90 }, IMPACT), (rng, sr) => {
    const boom = K.thump(sr, { f0: 120, f1: jit(rng, 42, 0.1), sweep: 0.06, dur: 0.4, curve: 1.8, drive: 2.4, harm: 0.3 });
    const rat = K.rattle(sr, rng, { dur: 0.5, f: jit(rng, 90, 0.15), density: 60, gain: 1.2 });
    const crack = K.burst(sr, rng, { dur: 0.03, filt: [{ type: 'bp', f: 2600, q: 0.8 }], curve: 2 });
    return K.tidy(K.mix(sr, [{ buf: boom, gain: 0 }, { buf: rat, gain: -3 }, { buf: crack, gain: -4 }]), sr);
  }),
  def('pummel', Object.assign({ variants: 3, gain: -2, pitch: [1.15, 1.3] }, IMPACT), lightHit),
  alias('hit_otg', 'hit_light', { gain: -4, pitch: [0.85, 0.92] }),
];
