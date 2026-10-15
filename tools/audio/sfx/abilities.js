'use strict';
// Signature ability and JUICE sounds per fighter (ROSTER.md sound palettes). Generic abilities map
// to element/projectile sounds through aliases; these are the designed one-offs.
const K = require('../lib/sfxkit');
const D = require('../lib/dsp');
const INST = require('../lib/instruments');
const { def, alias, jit } = require('./_def');

const AB = { bus: 'Impacts', group: 'abilities', priority: 82, max_voices: 4 };
const JU = { bus: 'Impacts', group: 'juice', priority: 98, max_voices: 2, cooldown: 0.5 };

function siren(sr, rng, { dur = 1.4, f0 = 500, f1 = 900, rate = 1.6 } = {}) {
  const n = D.secs(sr, dur);
  const o = new D.Osc(sr, 'saw'), lfo = new D.Lfo(sr, 'tri');
  const lp = new D.SVF(sr, 2200, 1.2);
  const out = D.zeros(n);
  for (let i = 0; i < n; i++) {
    const m = 0.5 + 0.5 * lfo.next(rate);
    const k = i / n;
    out[i] = Math.tanh(lp.lp(o.next(f0 * Math.pow(f1 / f0, m))) * 2) * Math.min(1, i / (sr * 0.05)) * (k > 0.8 ? (1 - k) / 0.2 : 1);
  }
  return out;
}

function kettle(sr, rng, { dur = 1.2, f0 = 1800, f1 = 3400 } = {}) {
  const n = D.secs(sr, dur);
  const o = new D.Osc(sr, 'sine'), nz = new D.Noise(rng);
  const bp = new D.SVF(sr, f0, 6);
  const out = D.zeros(n);
  for (let i = 0; i < n; i++) {
    const k = i / n;
    const f = f0 * Math.pow(f1 / f0, Math.pow(k, 0.7));
    bp.set(f, 6);
    out[i] = (o.next(f) * 0.6 + bp.bp(nz.next()) * 2) * Math.pow(k, 0.6) * (1 + 0.1 * Math.sin(i / sr * 2 * Math.PI * 11));
  }
  return out;
}

module.exports = [
  def('ab_steam_vent', Object.assign({ variants: 2 }, AB), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.burst(sr, rng, { dur: 0.45, filt: [{ type: 'bp', f: 3200, q: 0.5 }, { type: 'hp', f: 1000 }], a: 0.01, curve: 1.3, gain: 1.4 }), gain: 0 },
    { buf: K.thump(sr, { f0: 110, f1: 60, sweep: 0.05, dur: 0.25, drive: 1.6 }), gain: -4 },
    { buf: K.fmHit(sr, { f: 420, ratio: 2.76, index: 0.9, dur: 0.3, idxDecay: 0.3 }), gain: -10 }]), sr)),
  def('ab_stoke_fire', Object.assign({ variants: 1 }, AB), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.sweep(sr, rng, { dur: 0.9, f0: 200, f1: 1400, q: 0.8, color: 'pink', peakAt: 0.6, curve: 1.3, gain: 1.4 }), gain: 0 },
    { buf: K.crackle(sr, rng, { dur: 0.9, density: 220, tone: 2300, decayMs: 5, gain: 0.8 }), gain: -5, at: 0.1 },
    { buf: K.thump(sr, { f0: 80, f1: 45, sweep: 0.2, dur: 0.6, drive: 1.5, curve: 1.2 }), gain: -4, at: 0.3 }]), sr)),
  def('ab_anchor_drop', Object.assign({ variants: 1 }, AB), (rng, sr) => {
    const parts = [{ buf: K.rattle(sr, rng, { dur: 0.5, f: 85, density: 60, gain: 1.3 }), gain: -2 }];
    for (let i = 0; i < 4; i++) parts.push({ buf: K.thump(sr, { f0: 150, f1: 70, sweep: 0.03, dur: 0.15, drive: 2 }), gain: -1 - i, at: 0.15 + i * 0.07 });
    parts.push({ buf: K.fmHit(sr, { f: 260, ratio: 2.76, index: 1.2, dur: 0.5, idxDecay: 0.3 }), gain: -8, at: 0.3 });
    return K.tidy(K.mix(sr, parts), sr);
  }),
  def('ab_dust_bowl', Object.assign({ loop: true, bus: 'Zones', gain: -6, pitch: [1, 1], priority: 50 }, AB), (rng, sr) => K.seamless(K.mix(sr, [
    { buf: K.crackle(sr, rng, { dur: 2, density: 200, tone: 1300, q: 1.5, decayMs: 4, gain: 0.8 }), gain: 0 },
    { buf: K.wind(sr, rng, { dur: 2, base: 450, wander: 0.6, q: 0.8, gusts: 0.5, rate: 1.5, gain: 0.7 }), gain: -3 }]).slice(0, D.secs(sr, 2)), sr, 0.4)),
  def('ab_bulldoze_start', Object.assign({ variants: 2 }, AB), (rng, sr) => {
    const parts = [];
    for (let i = 0; i < 3; i++) parts.push({ buf: K.crackle(sr, rng, { dur: 0.12, density: 500, tone: 1500, decayMs: 3, gain: 0.9 }), gain: -i, at: i * 0.1 });
    parts.push({ buf: K.burst(sr, rng, { dur: 0.3, color: 'pink', filt: [{ type: 'bp', f: 300, q: 1 }], a: 0.05, curve: 1.2 }), gain: -6, at: 0.05 });
    return K.tidy(K.mix(sr, parts), sr);
  }),
  def('ab_spring_pad_place', Object.assign({ variants: 1, gain: -4 }, AB), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.fmHit(sr, { f: 660, ratio: 2.76, index: 1.3, dur: 0.3, idxDecay: 0.3 }), gain: 0 },
    { buf: K.chirp(sr, { f0: 200, f1: 420, dur: 0.15, wave: 'tri', curve: 1.5, gain: 0.5 }), gain: -6, at: 0.05 }]), sr)),
  def('juice_pulse', Object.assign({ variants: 2 }, JU), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.thump(sr, { f0: 140, f1: 36, sweep: 0.1, dur: 0.7, drive: 2.5, curve: 1.5, harm: 0.4 }), gain: 0 },
    { buf: K.sweep(sr, rng, { dur: 0.5, f0: 400, f1: 4000, q: 0.9, peakAt: 0.3, curve: 1.5, gain: 1.3 }), gain: -5 },
    { buf: K.fmHit(sr, { f: 880, ratio: 1.5, index: 3, dur: 0.6, idxDecay: 0.4, detune: 10 }), gain: -9 }]), sr)),
  def('juice_stoke', Object.assign({ variants: 1 }, JU), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: kettle(sr, rng, { dur: 1.1 }), gain: -4 },
    { buf: K.thump(sr, { f0: 160, f1: 40, sweep: 0.08, dur: 0.6, drive: 2.6, harm: 0.4 }), gain: 0, at: 1.1 },
    { buf: K.crackle(sr, rng, { dur: 0.8, density: 350, tone: 2500, decayMs: 5, gain: 1 }), gain: -5, at: 1.1 },
    { buf: K.fmHit(sr, { f: 300, ratio: 2.76, index: 1.5, dur: 0.6, idxDecay: 0.3 }), gain: -8, at: 1.1 }]), sr)),
  def('juice_dredge', Object.assign({ variants: 1 }, JU), (rng, sr) => {
    const fh = INST.make('foghorn', { a: 0.25, r: 0.5, cutoff: 380 }).render({ freq: 58, dur: 1.0, vel: 1 }, sr, rng);
    return K.tidy(K.mix(sr, [
      { buf: fh, gain: -2 },
      { buf: K.sweep(sr, rng, { dur: 1.6, f0: 250, f1: 1600, q: 0.8, color: 'pink', peakAt: 0.55, curve: 1.3, gain: 1.5 }), gain: -3, at: 0.6 },
      { buf: K.splash(sr, rng, { dur: 0.6, size: 1.6 }), gain: -2, at: 1.3 }]), sr);
  }),
  def('juice_gusto', Object.assign({ variants: 1 }, JU), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.sweep(sr, rng, { dur: 1.5, f0: 300, f1: 2800, q: 0.9, color: 'pink', peakAt: 0.7, curve: 1.3, gain: 1.6 }), gain: 0 },
    { buf: K.chirp(sr, { f0: 900, f1: 2200, dur: 1.2, wave: 'sine', curve: 1.2, a: 0.2, gain: 0.3 }), gain: -8, at: 0.2 },
    { buf: K.burst(sr, rng, { dur: 0.25, filt: [{ type: 'bp', f: 1800, q: 0.6 }], a: 0.005, curve: 1.5, gain: 1.4 }), gain: -1, at: 1.4 }]), sr)),
  def('juice_dozer', Object.assign({ variants: 1 }, JU), (rng, sr) => {
    const parts = [{ buf: siren(sr, rng, { dur: 1.6, f0: 420, f1: 760, rate: 1.4 }), gain: -8 }];
    for (let i = 0; i < 9; i++) parts.push({ buf: K.thump(sr, { f0: jit(rng, 150, 0.2), f1: jit(rng, 55, 0.2), sweep: 0.04, dur: 0.25, drive: 2 }), gain: -2 - rng.range(0, 4), at: 0.2 + i * jit(rng, 0.13, 0.3) });
    parts.push({ buf: K.crackle(sr, rng, { dur: 1.6, density: 250, tone: 1300, q: 1.5, decayMs: 6, gain: 1 }), gain: -4, at: 0.1 });
    return K.tidy(K.mix(sr, parts), sr);
  }),
  def('juice_slurry', Object.assign({ variants: 1 }, JU), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.bubbles(sr, rng, { dur: 1.0, rate: 22, fLo: 80, fHi: 320, popDur: 0.08, wet: 0.9 }), gain: 0 },
    { buf: K.sweep(sr, rng, { dur: 1.0, f0: 150, f1: 900, q: 0.8, color: 'brown', peakAt: 0.9, curve: 1.2, gain: 2 }), gain: -2 },
    { buf: K.splash(sr, rng, { dur: 0.7, size: 1.8 }), gain: 0, at: 1.0 },
    { buf: K.bubbles(sr, rng, { dur: 0.6, rate: 40, fLo: 150, fHi: 700, popDur: 0.04, wet: 0.8 }), gain: -4, at: 1.1 }]), sr)),
  def('juice_jitters', Object.assign({ variants: 1 }, JU), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.chirp(sr, { f0: 600, f1: 5200, dur: 1.1, wave: 'sine', curve: 0.9, a: 0.05, gain: 0.5 }), gain: -6 },
    { buf: K.buzz(sr, rng, { dur: 1.1, f: 110, harmonics: 4, am: 0.3, amRate: 14, lp: 3500, wave: 'saw', jitter: 0.03, gain: 0.4 }), gain: -8 },
    { buf: K.zap(sr, rng, { dur: 0.35, f: 2600, buzz: 60, curve: 1.6 }), gain: 0, at: 1.1 },
    { buf: K.thump(sr, { f0: 120, f1: 40, sweep: 0.06, dur: 0.5, drive: 2.4 }), gain: -1, at: 1.1 }]), sr)),
  def('juice_generic', Object.assign({ variants: 1 }, JU), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.sweep(sr, rng, { dur: 0.9, f0: 200, f1: 3000, q: 0.9, peakAt: 0.85, curve: 2, gain: 1.4 }), gain: -2 },
    { buf: K.thump(sr, { f0: 150, f1: 38, sweep: 0.1, dur: 0.6, drive: 2.5, harm: 0.3 }), gain: 0, at: 0.85 },
    { buf: K.fmHit(sr, { f: 660, ratio: 1.5, index: 3, dur: 0.7, idxDecay: 0.4, detune: 12 }), gain: -8, at: 0.85 }]), sr)),
  def('juice_end', Object.assign({ variants: 1, priority: 70 }, JU), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.sweep(sr, rng, { dur: 0.6, f0: 2500, f1: 300, q: 1, color: 'pink', peakAt: 0.15, curve: 1.4, gain: 1.2 }), gain: 0 },
    { buf: K.chirp(sr, { f0: 500, f1: 120, dur: 0.5, wave: 'square', curve: 1.5, gain: 0.3 }), gain: -10 }]), sr)),
  def('taunt_sting', Object.assign({ variants: 2, gain: -6, priority: 50, bus: 'Movement' }, AB), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.rattle(sr, rng, { dur: 0.3, f: 180, density: 80, gain: 0.8, hp: 800 }), gain: 0 },
    { buf: K.fmHit(sr, { f: 1320, ratio: 2, index: 1.5, dur: 0.25, idxDecay: 0.3 }), gain: -6, at: 0.1 }]), sr)),
  def('hype_tick', Object.assign({ variants: 2, gain: -10, priority: 30, bus: 'UI', spatial: false }, AB), (rng, sr) =>
    K.tidy(K.fmHit(sr, { f: 2200, ratio: 2, index: 1.2, dur: 0.08, idxDecay: 0.3 }), sr)),
  alias('ab_tide_spit', 'proj_launch_brine'), alias('ab_gust_bomb', 'proj_launch_gale'), alias('ab_sludge_lob', 'proj_launch_sludge'),
  alias('ab_arc_lash', 'proj_launch_static'), alias('ab_hang_time', 'hover_loop'), alias('ab_drain_dive', 'blink_down'),
  alias('ab_drain_emerge', 'blink_up'), alias('ab_bulldoze_loop', 'charge_loop'), alias('ab_bulldoze_hit', 'charge_release'),
  alias('ab_generic', 'whoosh_heavy', { gain: -2 }),
];
