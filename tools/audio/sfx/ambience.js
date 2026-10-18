'use strict';
// Ambience beds per arena and hub space (AUDIO_DIRECTION.md §3.7, ARENAS.md, HUB.md). 22.05 kHz loops
// on the "Ambience" bus; 8 s each with seamless crossfades.
const K = require('../lib/sfxkit');
const D = require('../lib/dsp');
const { def } = require('./_def');

const AMB = { bus: 'Ambience', group: 'ambience', sr: 22050, loop: true, priority: 20, max_voices: 2, spatial: false, pitch: [1, 1], gain: -8 };
const DUR = 8;

function gull(sr, rng) {
  const parts = [];
  const n = 2 + rng.int(3);
  for (let i = 0; i < n; i++) parts.push({ buf: K.vocal(sr, rng, { dur: 0.22, f0: [[0, 900], [0.05, 1300], [0.22, 700]], formants: [[1200, 8, 1], [2600, 9, 0.8], [3500, 9, 0.4]], breath: 0.3, growl: 0.1, growlRate: 45, jitter: 0.05, drive: 1.6, a: 0.01, d: 0.05, s: 0.7, r: 0.05, wave: 'pulse', pw: 0.1, lp: 6000 }), gain: -2, at: i * 0.3 });
  return K.mix(sr, parts);
}
function pigeon(sr, rng) {
  return K.vocal(sr, rng, { dur: 0.5, f0: [[0, 330], [0.25, 360], [0.5, 300]], formants: [[400, 8, 1], [800, 9, 0.5]], breath: 0.1, growl: 0.5, growlRate: 14, jitter: 0.02, drive: 1.2, a: 0.08, d: 0.1, s: 0.8, r: 0.1, wave: 'sine', lp: 1800 });
}
function dog(sr, rng) {
  return K.vocal(sr, rng, { dur: 0.2, f0: [[0, 160], [0.05, 200], [0.2, 120]], formants: [[600, 6, 1], [1100, 7, 0.6], [2500, 8, 0.25]], breath: 0.2, growl: 0.4, growlRate: 28, jitter: 0.04, drive: 2, a: 0.004, d: 0.06, s: 0.7, r: 0.06, wave: 'pulse', pw: 0.12, lp: 3000 });
}
function water(sr, rng, dur, gain = 1) {
  const w = K.wind(sr, rng, { dur, base: 650, wander: 1.1, q: 1.2, gusts: 0.7, rate: 0.35, gain: 0.7 * gain });
  const parts = [{ buf: w, gain: 0 }];
  for (let i = 0; i < 6; i++) parts.push({ buf: K.splash(sr, rng, { dur: 0.6, size: 0.5 }), gain: -16, at: rng.range(0, dur - 0.7) });
  return K.mix(sr, parts).slice(0, D.secs(sr, dur));
}
function far(buf, sr, amount = 0.6) { // distance: lowpass + reverb
  const lp = K.filterChain(Float64Array.from(buf), sr, [{ type: 'lp', f: 2200 }]);
  return K.room(lp, sr, { size: 0.8, mix: amount, damp: 0.6, predelay: 0.03, lowcut: 200 });
}
function sparse(sr, rng, dur, maker, count, gainDb) {
  const parts = [];
  for (let i = 0; i < count; i++) parts.push({ buf: maker(), gain: gainDb + rng.range(-4, 2), at: rng.range(0, dur - 1) });
  return parts;
}
function loopOf(sr, parts, dur, xf = 1.0) { return K.seamless(K.mix(sr, parts).slice(0, D.secs(sr, dur)), sr, xf); }

module.exports = [
  def('amb_gullet', AMB, (rng, sr) => loopOf(sr, [
    { buf: far(K.wind(sr, rng, { dur: DUR, base: 900, wander: 0.6, q: 1.5, gusts: 0.5, rate: 0.2, gain: 0.5 }), sr, 0.7), gain: -4 },
    ...sparse(sr, rng, DUR, () => far(K.rattle(sr, rng, { dur: 0.5, f: 110, density: 30, gain: 0.6 }), sr, 0.8), 3, -14),
  ], DUR)),
  def('amb_drydock', AMB, (rng, sr) => loopOf(sr, [
    { buf: water(sr, rng, DUR, 1), gain: -2 },
    { buf: K.wind(sr, rng, { dur: DUR, base: 380, wander: 1.3, q: 0.8, gusts: 0.6, rate: 0.25, gain: 0.5 }), gain: -8 },
    ...sparse(sr, rng, DUR, () => far(gull(sr, rng), sr, 0.5), 3, -12),
    ...sparse(sr, rng, DUR, () => far(K.fmHit(sr, { f: 220, ratio: 2.76, index: 1, dur: 0.9, idxDecay: 0.3 }), sr, 0.8), 2, -18),
  ], DUR)),
  def('amb_crusher', AMB, (rng, sr) => loopOf(sr, [
    { buf: K.wind(sr, rng, { dur: DUR, base: 300, wander: 0.8, q: 0.7, gusts: 0.5, rate: 0.2, gain: 0.5 }), gain: -8 },
    ...sparse(sr, rng, DUR, () => far(K.fmHit(sr, { f: rng.range(150, 320), ratio: 2.76, index: 1.4, dur: 1.4, idxDecay: 0.3 }), sr, 0.8), 3, -16),
    ...sparse(sr, rng, DUR, () => K.crackle(sr, rng, { dur: 0.4, density: 400, tone: 4000, decayMs: 2, gain: 0.4 }), 3, -20),
    ...sparse(sr, rng, DUR, () => far(K.mix(sr, [{ buf: dog(sr, rng), gain: 0 }, { buf: dog(sr, rng), gain: -1, at: 0.28 }]), sr, 0.85), 1, -14),
  ], DUR)),
  def('amb_rooftop', AMB, (rng, sr) => loopOf(sr, [
    { buf: K.wind(sr, rng, { dur: DUR, base: 520, wander: 1.5, q: 0.9, gusts: 0.8, rate: 0.3, gain: 0.8 }), gain: -3 },
    { buf: far(K.noise(sr, DUR, rng, { color: 'brown', filt: [{ type: 'lp', f: 500 }], gain: 0.5 }), sr, 0.5), gain: -14 },
    ...sparse(sr, rng, DUR, () => pigeon(sr, rng), 3, -16),
  ], DUR)),
  def('amb_hub_main', AMB, (rng, sr) => loopOf(sr, [
    { buf: K.wind(sr, rng, { dur: DUR, base: 700, wander: 0.4, q: 1.5, gusts: 0.3, rate: 0.15, gain: 0.35 }), gain: -10 },
    ...sparse(sr, rng, DUR, () => far(K.thump(sr, { f0: 140, f1: 70, sweep: 0.03, dur: 0.25, drive: 1.8 }), sr, 0.7), 4, -12),
    ...sparse(sr, rng, DUR, () => far(K.rattle(sr, rng, { dur: 0.6, f: 130, density: 25, gain: 0.6 }), sr, 0.8), 2, -18),
  ], DUR)),
  def('amb_hub_juice_bar', AMB, (rng, sr) => loopOf(sr, [
    ...sparse(sr, rng, DUR, () => K.fmHit(sr, { f: rng.range(2000, 3200), ratio: 2.0, index: 0.9, dur: 0.35, idxDecay: 0.3 }), 4, -18),
    ...sparse(sr, rng, DUR, () => K.crackle(sr, rng, { dur: 0.5, density: 600, tone: 5000, decayMs: 1.5, gain: 0.5 }), 2, -20),
  ], DUR)),
  def('amb_hub_dock', AMB, (rng, sr) => loopOf(sr, [
    { buf: water(sr, rng, DUR, 0.8), gain: -4 },
    { buf: K.wind(sr, rng, { dur: DUR, base: 420, wander: 1.2, q: 0.8, gusts: 0.6, rate: 0.25, gain: 0.5 }), gain: -8 },
    ...sparse(sr, rng, DUR, () => far(gull(sr, rng), sr, 0.4), 3, -10),
    ...sparse(sr, rng, DUR, () => far(K.fmHit(sr, { f: 180, ratio: 2.76, index: 1, dur: 1.2, idxDecay: 0.3 }), sr, 0.8), 1, -16),
  ], DUR)),
  def('amb_hub_office', AMB, (rng, sr) => {
    const parts = [
      { buf: K.wind(sr, rng, { dur: DUR, base: 600, wander: 0.3, q: 1.5, gusts: 0.2, rate: 0.1, gain: 0.3 }), gain: -14 },
    ];
    for (let t = 0; t < DUR; t += 1) parts.push({ buf: K.burst(sr, rng, { dur: 0.015, filt: [{ type: 'bp', f: 2600, q: 4 }], curve: 2.5, gain: 1.2 }), gain: -14, at: t + 0.1 });
    return loopOf(sr, parts, DUR);
  }),
  def('amb_hub_boiler', AMB, (rng, sr) => loopOf(sr, [
    { buf: K.noise(sr, DUR, rng, { color: 'brown', filt: [{ type: 'lp', f: 250 }], gain: 0.8 }), gain: -6 },
    ...sparse(sr, rng, DUR, () => K.drip(sr, rng, { f: rng.range(900, 1900), dur: 0.15 }), 6, -14),
    ...sparse(sr, rng, DUR, () => far(K.fmHit(sr, { f: rng.range(200, 400), ratio: 2.76, index: 1.2, dur: 0.8, idxDecay: 0.3 }), sr, 0.9), 2, -14),
  ], DUR)),
  def('amb_hub_locker', AMB, (rng, sr) => loopOf(sr, [
    { buf: K.wind(sr, rng, { dur: DUR, base: 800, wander: 0.3, q: 1.5, gusts: 0.2, rate: 0.12, gain: 0.4 }), gain: -10 },
    ...sparse(sr, rng, DUR, () => K.drip(sr, rng, { f: rng.range(1200, 2200), dur: 0.14 }), 4, -16),
    ...sparse(sr, rng, DUR, () => far(K.fmHit(sr, { f: rng.range(300, 500), ratio: 2.76, index: 1, dur: 0.5, idxDecay: 0.3 }), sr, 0.8), 2, -18),
  ], DUR)),
  def('amb_hub_booth', AMB, (rng, sr) => loopOf(sr, [
    { buf: far(K.wind(sr, rng, { dur: DUR, base: 900, wander: 0.6, q: 1.5, gusts: 0.5, rate: 0.2, gain: 0.5 }), sr, 0.8), gain: -6 },
  ], DUR)),
  def('amb_menu', AMB, (rng, sr) => loopOf(sr, [
    { buf: K.wind(sr, rng, { dur: DUR, base: 350, wander: 1.0, q: 0.8, gusts: 0.5, rate: 0.2, gain: 0.5 }), gain: -8 },
    { buf: far(water(sr, rng, DUR, 0.6), sr, 0.6), gain: -8 },
    { buf: far(K.wind(sr, rng, { dur: DUR, base: 1000, wander: 0.5, q: 1.5, gusts: 0.4, rate: 0.15, gain: 0.4 }), sr, 0.8), gain: -10 },
    ...sparse(sr, rng, DUR, () => far(gull(sr, rng), sr, 0.7), 1, -16),
  ], DUR)),
];
