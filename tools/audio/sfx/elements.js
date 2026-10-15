'use strict';
// Element layers, status triggers, zone loops, reactions, projectiles, hazards and props
// (AUDIO_DIRECTION.md §3.4, ELEMENTS.md). Bus "Zones" for loops (-8 dB), "Impacts" for reaction hits.
const K = require('../lib/sfxkit');
const D = require('../lib/dsp');
const { def, alias, jit } = require('./_def');

const EL = { bus: 'Impacts', group: 'elements', priority: 75, max_voices: 6, gain: -4 };
const ST = { bus: 'Impacts', group: 'elements', priority: 80, max_voices: 4, gain: -2 };
const ZONE = { bus: 'Zones', group: 'zones', priority: 30, max_voices: 6, loop: true, pitch: [0.97, 1.03], gain: -6 };
const RX = { bus: 'Impacts', group: 'reactions', priority: 88, max_voices: 4 };
const PR = { bus: 'Movement', group: 'projectiles', priority: 60, max_voices: 6, gain: -3 };
const HZ = { bus: 'Zones', group: 'hazards', priority: 70, max_voices: 4, gain: -2 };

// ---- element hit layers -------------------------------------------------------------------
const elHit = {
  scorch: (rng, sr) => K.tidy(K.crackle(sr, rng, { dur: 0.16, density: 260, tone: 2600, q: 1.6, decayMs: 5, gain: 1 }), sr),
  brine: (rng, sr) => K.tidy(K.splash(sr, rng, { dur: 0.2, size: 0.7 }), sr),
  static: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.burst(sr, rng, { dur: 0.002, filt: [{ type: 'hp', f: 3000 }], curve: 3, gain: 1.5 }), gain: 0 },
    { buf: K.zap(sr, rng, { dur: 0.09, f: 4000, buzz: 140 }), gain: -2, at: 0.002 }]), sr),
  sludge: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.burst(sr, rng, { dur: 0.09, color: 'pink', filt: [{ type: 'bp', f: 480, q: 1.1 }], a: 0.003, curve: 1.8 }), gain: 0 },
    { buf: K.bubbles(sr, rng, { dur: 0.12, rate: 35, fLo: 150, fHi: 500, popDur: 0.04, wet: 0.9 }), gain: -3, at: 0.01 }]), sr),
  grit: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.crackle(sr, rng, { dur: 0.14, density: 600, tone: 1500, q: 1.2, decayMs: 3, gain: 1 }), gain: 0 },
    { buf: K.thump(sr, { f0: 200, f1: 110, sweep: 0.02, dur: 0.06, drive: 1.3 }), gain: -6 }]), sr),
  gale: (rng, sr) => K.tidy(K.sweep(sr, rng, { dur: 0.11, f0: 2600, f1: 900, q: 1.8, peakAt: 0.3, gain: 1.2 }), sr),
};

// ---- status triggers ----------------------------------------------------------------------
const status = {
  sizzle: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.thump(sr, { f0: 90, f1: 45, sweep: 0.08, dur: 0.3, drive: 1.5, curve: 1.4, harm: 0.3 }), gain: 0 },
    { buf: K.sweep(sr, rng, { dur: 0.3, f0: 300, f1: 1800, q: 0.9, color: 'pink', peakAt: 0.5, gain: 1.4 }), gain: -3 },
    { buf: K.crackle(sr, rng, { dur: 0.5, density: 200, tone: 2400, decayMs: 5, gain: 0.8 }), gain: -6, at: 0.08 }]), sr),
  soaked: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.splash(sr, rng, { dur: 0.45, size: 1.3 }), gain: 0 },
    { buf: K.drip(sr, rng, { f: 1300, dur: 0.15 }), gain: -8, at: 0.4 },
    { buf: K.drip(sr, rng, { f: 1900, dur: 0.12 }), gain: -10, at: 0.55 }], 0.05), sr),
  jolted: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.buzz(sr, rng, { dur: 0.3, f: 70, am: 0.4, amRate: 25, lp: 3000, gain: 0.6, wave: 'saw', jitter: 0.08 }), gain: 0 },
    { buf: K.chirp(sr, { f0: 400, f1: 2400, dur: 0.3, wave: 'square', curve: 0.8, gain: 0.3 }), gain: -8 },
    { buf: K.zap(sr, rng, { dur: 0.1, f: 3500, buzz: 180 }), gain: -1, at: 0.3 }]), sr),
  gunked: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.bubbles(sr, rng, { dur: 0.5, rate: 18, fLo: 110, fHi: 420, popDur: 0.06, wet: 0.8 }), gain: 0 },
    { buf: K.noise(sr, 0.45, rng, { color: 'brown', filt: [{ type: 'lp', f: 500 }], gain: 0.5 }), gain: -6 }]), sr),
  caked: (rng, sr) => {
    const parts = [{ buf: K.crackle(sr, rng, { dur: 0.55, density: 180, tone: 1200, q: 1.5, decayMs: 6, gain: 1 }), gain: -2 }];
    for (let i = 0; i < 5; i++) parts.push({ buf: K.thump(sr, { f0: jit(rng, 180, 0.2), f1: jit(rng, 90, 0.2), sweep: 0.02, dur: 0.1, drive: 1.5 }), gain: -3 - i, at: 0.05 + i * jit(rng, 0.08, 0.3) });
    return K.tidy(K.mix(sr, parts), sr);
  },
  winded: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.chirp(sr, { f0: 1800, f1: 3200, dur: 0.35, wave: 'sine', curve: 1.2, a: 0.03, gain: 0.35 }), gain: -4 },
    { buf: K.sweep(sr, rng, { dur: 0.45, f0: 500, f1: 2500, q: 1.1, color: 'pink', peakAt: 0.5, gain: 1.3 }), gain: 0 }]), sr),
};

// ---- zone loops ---------------------------------------------------------------------------
function zoneLoop(kind, rng, sr) {
  const dur = 2.4;
  switch (kind) {
    case 'scorch': return K.seamless(K.mix(sr, [
      { buf: K.crackle(sr, rng, { dur, density: 90, tone: 2200, q: 1.4, decayMs: 7, gain: 0.8, lp: 7000 }), gain: 0 },
      { buf: K.wind(sr, rng, { dur, base: 320, wander: 0.5, q: 0.7, gusts: 0.5, rate: 0.6, gain: 0.5 }), gain: -6 }]).slice(0, D.secs(sr, dur)), sr, 0.4);
    case 'brine': {
      const w = K.wind(sr, rng, { dur, base: 800, wander: 1.0, q: 1.3, gusts: 0.7, rate: 0.5, gain: 0.7 });
      const parts = [{ buf: w, gain: 0 }];
      for (let i = 0; i < 5; i++) parts.push({ buf: K.drip(sr, rng, { f: rng.range(900, 2200), dur: 0.12 }), gain: -10, at: rng.range(0, dur - 0.2) });
      return K.seamless(K.mix(sr, parts).slice(0, D.secs(sr, dur)), sr, 0.4);
    }
    case 'static': {
      const hum = K.buzz(sr, rng, { dur, f: 60, harmonics: 3, am: 0.15, amRate: 2, lp: 1800, q: 1.2, jitter: 0.005, gain: 0.5 });
      const parts = [{ buf: hum, gain: 0 }];
      for (let i = 0; i < 12; i++) parts.push({ buf: K.zap(sr, rng, { dur: 0.03, f: rng.range(2500, 6000), buzz: 300, gain: 0.5 }), gain: -8, at: rng.range(0, dur - 0.05) });
      return K.seamless(K.mix(sr, parts).slice(0, D.secs(sr, dur)), sr, 0.3);
    }
    case 'sludge': return K.seamless(K.mix(sr, [
      { buf: K.bubbles(sr, rng, { dur, rate: 7, fLo: 100, fHi: 360, popDur: 0.07, wet: 0.7 }), gain: 0 },
      { buf: K.noise(sr, dur, rng, { color: 'brown', filt: [{ type: 'lp', f: 400 }], gain: 0.4 }), gain: -8 }]).slice(0, D.secs(sr, dur)), sr, 0.4);
    case 'grit': return K.seamless(K.crackle(sr, rng, { dur, density: 140, tone: 1400, q: 1.5, decayMs: 5, gain: 0.8 }), sr, 0.4);
    case 'gale': return K.seamless(K.wind(sr, rng, { dur, base: 700, wander: 1.4, q: 1.1, gusts: 0.5, rate: 1.1, gain: 0.9 }), sr, 0.4);
    case 'mud': return K.seamless(K.mix(sr, [
      { buf: K.bubbles(sr, rng, { dur, rate: 4, fLo: 70, fHi: 220, popDur: 0.1, wet: 0.5 }), gain: 0 },
      { buf: K.noise(sr, dur, rng, { color: 'brown', filt: [{ type: 'lp', f: 300 }], gain: 0.5 }), gain: -6 }]).slice(0, D.secs(sr, dur)), sr, 0.4);
    case 'steam': {
      const h = K.noise(sr, dur, rng, { filt: [{ type: 'bp', f: 3500, q: 0.6 }, { type: 'lp', f: 6000 }], gain: 0.5 });
      const lfo = new D.Lfo(sr, 'sine');
      for (let i = 0; i < h.length; i++) h[i] *= 0.7 + 0.3 * lfo.next(3);
      return K.seamless(h, sr, 0.4);
    }
    default: return D.zeros(sr);
  }
}

// ---- reactions ----------------------------------------------------------------------------
const reactions = {
  steam_burst: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.sweep(sr, rng, { dur: 0.7, f0: 1500, f1: 4500, q: 0.8, peakAt: 0.35, curve: 1.2, gain: 1.4 }), gain: 0 },
    { buf: K.chirp(sr, { f0: 2200, f1: 2900, dur: 0.6, wave: 'sine', curve: 1.3, a: 0.08, gain: 0.3 }), gain: -6, at: 0.1 },
    { buf: K.thump(sr, { f0: 120, f1: 60, sweep: 0.05, dur: 0.2, drive: 1.6 }), gain: -4 }]), sr),
  flare_up: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.thump(sr, { f0: 160, f1: 40, sweep: 0.08, dur: 0.5, drive: 2.5, curve: 1.6, harm: 0.4 }), gain: 0 },
    { buf: K.burst(sr, rng, { dur: 0.25, color: 'pink', filt: [{ type: 'lp', f: 2500 }], a: 0.004, curve: 1.6, gain: 1.2 }), gain: -3 },
    { buf: K.crackle(sr, rng, { dur: 0.7, density: 300, tone: 2600, decayMs: 5, gain: 1 }), gain: -5, at: 0.05 }]), sr),
  backdraft: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.sweep(sr, rng, { dur: 0.8, f0: 250, f1: 1600, q: 0.8, color: 'pink', peakAt: 0.45, curve: 1.3, gain: 1.5 }), gain: 0 },
    { buf: K.crackle(sr, rng, { dur: 0.8, density: 350, tone: 2000, decayMs: 6, gain: 1 }), gain: -4, at: 0.15 },
    { buf: K.thump(sr, { f0: 100, f1: 50, sweep: 0.1, dur: 0.4, drive: 1.6, curve: 1.3 }), gain: -5, at: 0.2 }]), sr),
  short_out: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.buzz(sr, rng, { dur: 0.25, f: 55, harmonics: 4, am: 0.6, amRate: 30, lp: 4000, wave: 'saw', jitter: 0.1, gain: 0.8 }), gain: -2 },
    { buf: K.zap(sr, rng, { dur: 0.18, f: 3200, buzz: 90 }), gain: 0, at: 0.02 },
    { buf: K.zap(sr, rng, { dur: 0.12, f: 5200, buzz: 160 }), gain: -3, at: 0.14 },
    { buf: K.splash(sr, rng, { dur: 0.35, size: 1 }), gain: -4, at: 0.05 }]), sr),
  mudbound: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.bubbles(sr, rng, { dur: 0.5, rate: 14, fLo: 70, fHi: 260, popDur: 0.09, wet: 0.9 }), gain: 0 },
    { buf: K.burst(sr, rng, { dur: 0.3, color: 'brown', filt: [{ type: 'lp', f: 450 }], a: 0.01, curve: 1.4, gain: 1.5 }), gain: -2 },
    { buf: K.thump(sr, { f0: 110, f1: 60, sweep: 0.06, dur: 0.3, drive: 1.4 }), gain: -4 }]), sr),
  dilute: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.sweep(sr, rng, { dur: 0.6, f0: 2400, f1: 700, q: 1.0, color: 'pink', peakAt: 0.3, curve: 1.3, gain: 1.4 }), gain: 0 },
    { buf: K.bubbles(sr, rng, { dur: 0.5, rate: 25, fLo: 300, fHi: 1200, popDur: 0.035, wet: 0.5 }), gain: -6, at: 0.05 }]), sr),
  catalyze: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.crackle(sr, rng, { dur: 0.6, density: 900, tone: 4500, q: 1.2, decayMs: 2, gain: 0.9 }), gain: 0 },
    { buf: K.noise(sr, 0.5, rng, { filt: [{ type: 'hp', f: 3000 }], gain: 0.35 }), gain: -6 },
    { buf: K.zap(sr, rng, { dur: 0.08, f: 4200, buzz: 200 }), gain: -4 }]), sr),
  stormfront_mark: (rng, sr) => {
    const parts = [];
    let t = 0, gap = 0.12;
    for (let i = 0; i < 9 && t < 0.58; i++) { parts.push({ buf: K.tone(sr, { f: 1100 + i * 90, dur: 0.04, wave: 'sine', a: 0.001, d: 0.03, s: 0.2, r: 0.02 }), gain: -2 - (8 - i), at: t }); t += gap; gap *= 0.82; }
    parts.push({ buf: K.buzz(sr, rng, { dur: 0.6, f: 90, am: 0.3, amRate: 12, lp: 1500, gain: 0.3, wave: 'saw' }), gain: -10 });
    return K.tidy(K.mix(sr, parts), sr);
  },
  stormfront_strike: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.burst(sr, rng, { dur: 0.35, filt: [{ type: 'hp', f: 600 }], a: 0.001, curve: 1.8, gain: 1.4 }), gain: 0 },
    { buf: K.thump(sr, { f0: 90, f1: 38, sweep: 0.1, dur: 0.6, drive: 2.4, curve: 1.4, harm: 0.3 }), gain: 0, at: 0.01 },
    { buf: K.zap(sr, rng, { dur: 0.15, f: 2800, buzz: 70 }), gain: -3 },
    { buf: K.noise(sr, 0.9, rng, { color: 'brown', filt: [{ type: 'lp', f: 700 }], gain: 0.8 }), gain: -8, at: 0.1 }]), sr),
  crust: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.crackle(sr, rng, { dur: 0.6, density: 160, tone: 1600, q: 2, decayMs: 8, gain: 1 }), gain: 0 },
    { buf: K.thump(sr, { f0: 240, f1: 130, sweep: 0.02, dur: 0.12, drive: 1.8 }), gain: -3, at: 0.35 },
    { buf: K.burst(sr, rng, { dur: 0.08, filt: [{ type: 'bp', f: 700, q: 4 }], curve: 2, gain: 1.5 }), gain: -5, at: 0.35 }]), sr),
  spray: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.burst(sr, rng, { dur: 0.3, color: 'pink', filt: [{ type: 'bp', f: 1800, q: 0.6 }], a: 0.006, curve: 1.5, gain: 1.3 }), gain: 0 },
    { buf: K.bubbles(sr, rng, { dur: 0.35, rate: 40, fLo: 200, fHi: 900, popDur: 0.03, wet: 0.9 }), gain: -4, at: 0.02 }]), sr),
  sandblast: (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.burst(sr, rng, { dur: 0.45, filt: [{ type: 'bp', f: 3800, q: 0.5 }, { type: 'hp', f: 1500 }], a: 0.01, curve: 1.3, gain: 1.2 }), gain: 0 },
    { buf: K.crackle(sr, rng, { dur: 0.4, density: 1200, tone: 2500, decayMs: 1.5, gain: 0.7 }), gain: -6 },
    { buf: K.burst(sr, rng, { dur: 0.04, filt: [{ type: 'bp', f: 1200, q: 1 }], curve: 2.5, gain: 1.4 }), gain: -1, at: 0.08 }]), sr),
};

// ---- projectiles --------------------------------------------------------------------------
const projLaunch = {
  scorch: (rng, sr) => K.tidy(K.mix(sr, [{ buf: K.sweep(sr, rng, { dur: 0.2, f0: 600, f1: 2400, q: 1, color: 'pink', peakAt: 0.4, gain: 1.3 }), gain: 0 }, { buf: K.crackle(sr, rng, { dur: 0.2, density: 300, tone: 2800, decayMs: 4, gain: 0.7 }), gain: -6 }]), sr),
  brine: (rng, sr) => K.tidy(K.mix(sr, [{ buf: K.chirp(sr, { f0: 300, f1: 900, dur: 0.12, wave: 'sine', curve: 1.5, gain: 0.5 }), gain: -4 }, { buf: K.splash(sr, rng, { dur: 0.18, size: 0.6 }), gain: 0 }]), sr),
  static: (rng, sr) => K.tidy(K.mix(sr, [{ buf: K.zap(sr, rng, { dur: 0.12, f: 3000, buzz: 110 }), gain: 0 }, { buf: K.chirp(sr, { f0: 500, f1: 1800, dur: 0.15, wave: 'square', curve: 1.5, gain: 0.3 }), gain: -8 }]), sr),
  sludge: (rng, sr) => K.tidy(K.mix(sr, [{ buf: K.burst(sr, rng, { dur: 0.12, color: 'pink', filt: [{ type: 'bp', f: 400, q: 1.2 }], curve: 1.8, gain: 1.2 }), gain: 0 }, { buf: K.bubbles(sr, rng, { dur: 0.15, rate: 30, fLo: 120, fHi: 400, popDur: 0.05, wet: 0.9 }), gain: -3 }]), sr),
  grit: (rng, sr) => K.tidy(K.mix(sr, [{ buf: K.crackle(sr, rng, { dur: 0.2, density: 500, tone: 1500, decayMs: 4, gain: 1 }), gain: 0 }, { buf: K.sweep(sr, rng, { dur: 0.15, f0: 900, f1: 2200, q: 1, peakAt: 0.4, gain: 0.8 }), gain: -5 }]), sr),
  gale: (rng, sr) => K.tidy(K.mix(sr, [{ buf: K.burst(sr, rng, { dur: 0.12, filt: [{ type: 'bp', f: 1500, q: 0.6 }], a: 0.004, curve: 1.6, gain: 1.2 }), gain: 0 }, { buf: K.sweep(sr, rng, { dur: 0.2, f0: 800, f1: 3000, q: 1.2, peakAt: 0.5, gain: 1 }), gain: -3 }]), sr),
};
function projLoop(el, rng, sr) {
  const dur = 1.0;
  const base = { scorch: 420, brine: 650, static: 2400, sludge: 260, grit: 900, gale: 1300 }[el];
  const w = K.wind(sr, rng, { dur, base, wander: 0.4, q: 1.6, gusts: 0.4, rate: 3, gain: 0.8 });
  const parts = [{ buf: w, gain: 0 }];
  if (el === 'scorch') parts.push({ buf: K.crackle(sr, rng, { dur, density: 120, tone: 2400, decayMs: 5, gain: 0.6 }), gain: -6 });
  if (el === 'static') parts.push({ buf: K.buzz(sr, rng, { dur, f: 110, am: 0.5, amRate: 40, lp: 5000, wave: 'saw', jitter: 0.1, gain: 0.4 }), gain: -6 });
  if (el === 'sludge' || el === 'brine') parts.push({ buf: K.bubbles(sr, rng, { dur, rate: 10, fLo: 150, fHi: 500, popDur: 0.05, wet: 0.5 }), gain: -8 });
  return K.seamless(K.mix(sr, parts).slice(0, D.secs(sr, dur)), sr, 0.25);
}

// ---- hazards and props --------------------------------------------------------------------
const hazards = [
  def('hazard_gutter_telegraph', Object.assign({ variants: 1 }, HZ), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.bubbles(sr, rng, { dur: 1.4, rate: 12, fLo: 90, fHi: 350, popDur: 0.07, wet: 0.7 }), gain: 0 },
    { buf: K.sweep(sr, rng, { dur: 1.5, f0: 300, f1: 1500, q: 0.8, color: 'pink', peakAt: 0.9, curve: 1.2, gain: 1 }), gain: -4 }]), sr)),
  def('hazard_gutter_flood', Object.assign({ loop: true }, HZ), (rng, sr) => K.seamless(K.wind(sr, rng, { dur: 3, base: 500, wander: 1.2, q: 1.1, gusts: 0.6, rate: 0.9, gain: 1 }), sr, 0.5)),
  def('hazard_crane_telegraph', Object.assign({ variants: 1 }, HZ), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.rattle(sr, rng, { dur: 1.4, f: 70, density: 25, gain: 1.2, hp: 300 }), gain: 0 },
    { buf: K.buzz(sr, rng, { dur: 1.5, f: 100, am: 0.1, amRate: 1, lp: 900, gain: 0.3, wave: 'saw' }), gain: -8 }]), sr)),
  def('hazard_crane_drop', Object.assign({ variants: 1, bus: 'Impacts', priority: 85 }, HZ), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.rattle(sr, rng, { dur: 0.6, f: 80, density: 70, gain: 1.4 }), gain: -2 },
    { buf: K.thump(sr, { f0: 130, f1: 50, sweep: 0.06, dur: 0.4, drive: 2.2, harm: 0.3 }), gain: 0, at: 0.3 }]), sr)),
  def('hazard_plate_telegraph', Object.assign({ variants: 1 }, HZ), (rng, sr) => K.tidy(K.buzz(sr, rng, { dur: 1.0, f: 60, harmonics: 3, am: 0.5, amRate: 8, lp: 2500, wave: 'saw', jitter: 0.02, gain: 0.7 }), sr)),
  def('hazard_plate_live', Object.assign({ loop: true }, HZ), (rng, sr) => zoneLoop('static', rng, sr)),
  def('hazard_magnet_telegraph', Object.assign({ variants: 1 }, HZ), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.chirp(sr, { f0: 80, f1: 420, dur: 1.5, wave: 'saw', curve: 0.6, a: 0.1, gain: 0.4 }), gain: 0 },
    { buf: K.buzz(sr, rng, { dur: 1.5, f: 50, harmonics: 2, am: 0.3, amRate: 6, lp: 1200, gain: 0.5 }), gain: -4 }]), sr)),
  def('hazard_magnet_pull', Object.assign({ loop: true }, HZ), (rng, sr) => K.seamless(K.buzz(sr, rng, { dur: 2, f: 48, harmonics: 3, am: 0.25, amRate: 9, lp: 2000, wave: 'saw', jitter: 0.01, gain: 0.7 }), sr, 0.3)),
  def('hazard_wind_telegraph', Object.assign({ variants: 1 }, HZ), (rng, sr) => {
    const parts = [{ buf: K.wind(sr, rng, { dur: 1.5, base: 600, wander: 1, q: 1, gusts: 0.3, rate: 2, gain: 0.6 }), gain: -2 }];
    for (let i = 0; i < 6; i++) parts.push({ buf: K.burst(sr, rng, { dur: 0.05, filt: [{ type: 'bp', f: 900, q: 1 }], a: 0.004, curve: 1.6 }), gain: -4, at: 0.1 + i * jit(rng, 0.2, 0.3) });
    return K.tidy(K.mix(sr, parts), sr);
  }),
  def('hazard_wind_gust', Object.assign({ variants: 2, priority: 80 }, HZ), (rng, sr) => K.tidy(K.sweep(sr, rng, { dur: 1.3, f0: 300, f1: 1800, q: 0.8, color: 'pink', peakAt: 0.4, curve: 1.3, gain: 1.6 }), sr)),
  def('prop_break_wood', Object.assign({ variants: 3, bus: 'Impacts', group: 'props', priority: 75 }, HZ), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.crackle(sr, rng, { dur: 0.3, density: 260, tone: 900, q: 1.8, decayMs: 8, gain: 1 }), gain: 0 },
    { buf: K.thump(sr, { f0: 160, f1: 70, sweep: 0.03, dur: 0.2, drive: 1.8 }), gain: -2 },
    { buf: K.burst(sr, rng, { dur: 0.1, filt: [{ type: 'bp', f: 480, q: 2.5 }], curve: 1.8, gain: 1.5 }), gain: -4 }]), sr)),
  def('prop_break_metal', Object.assign({ variants: 3, bus: 'Impacts', group: 'props', priority: 75 }, HZ), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.fmHit(sr, { f: jit(rng, 300, 0.1), ratio: 2.76, index: 1.6, dur: 0.6, idxDecay: 0.3, detune: 7 }), gain: -3 },
    { buf: K.thump(sr, { f0: 150, f1: 60, sweep: 0.04, dur: 0.25, drive: 2 }), gain: 0 },
    { buf: K.rattle(sr, rng, { dur: 0.4, f: 110, density: 50, gain: 0.8 }), gain: -6, at: 0.05 }]), sr)),
  def('bumper_ding', Object.assign({ variants: 2, bus: 'Impacts', group: 'props', priority: 70, gain: -4 }, HZ), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.fmHit(sr, { f: 1320, ratio: 2.0, index: 1.5, dur: 0.35, idxDecay: 0.3 }), gain: 0 },
    { buf: K.thump(sr, { f0: 200, f1: 100, sweep: 0.02, dur: 0.08, drive: 1.5 }), gain: -4 }]), sr)),
  def('pickup_health', Object.assign({ variants: 2, bus: 'UI', group: 'props', priority: 70, spatial: false, gain: -4 }, HZ), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.bubbles(sr, rng, { dur: 0.25, rate: 20, fLo: 200, fHi: 600, popDur: 0.06, wet: 0.6 }), gain: -2 },
    { buf: K.chirp(sr, { f0: 400, f1: 800, dur: 0.25, wave: 'sine', curve: 1.2, a: 0.02, gain: 0.5 }), gain: -4 }]), sr)),
  def('pickup_hype', Object.assign({ variants: 2, bus: 'UI', group: 'props', priority: 70, spatial: false, gain: -4 }, HZ), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.burst(sr, rng, { dur: 0.02, filt: [{ type: 'hp', f: 2500 }], curve: 2.5 }), gain: 0 },
    { buf: K.crackle(sr, rng, { dur: 0.4, density: 500, tone: 5000, decayMs: 2, gain: 0.6 }), gain: -6, at: 0.02 },
    { buf: K.fmHit(sr, { f: 1760, ratio: 2, index: 1.5, dur: 0.3, idxDecay: 0.3 }), gain: -6, at: 0.05 }]), sr)),
  def('drain_teleport', Object.assign({ variants: 2, bus: 'Movement', group: 'props', priority: 65 }, HZ), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.bubbles(sr, rng, { dur: 0.3, rate: 30, fLo: 120, fHi: 500, popDur: 0.05, wet: 0.7 }), gain: 0 },
    { buf: K.sweep(sr, rng, { dur: 0.35, f0: 2000, f1: 200, q: 1.1, color: 'pink', peakAt: 0.2, gain: 1.2 }), gain: -3 }]), sr)),
];

const out = [];
for (const el of Object.keys(elHit)) out.push(def(`el_hit_${el}`, Object.assign({ variants: 3 }, EL), elHit[el]));
for (const st of Object.keys(status)) out.push(def(`status_${st}`, Object.assign({ variants: 2 }, ST), status[st]));
for (const z of ['scorch', 'brine', 'static', 'sludge', 'grit', 'gale', 'mud', 'steam']) out.push(def(`zone_${z}`, Object.assign({}, ZONE), (rng, sr) => zoneLoop(z, rng, sr)));
for (const r of Object.keys(reactions)) out.push(def(`react_${r}`, Object.assign({ variants: 2 }, RX), reactions[r]));
for (const el of Object.keys(projLaunch)) {
  out.push(def(`proj_launch_${el}`, Object.assign({ variants: 2 }, PR), projLaunch[el]));
  out.push(def(`proj_loop_${el}`, Object.assign({ loop: true, gain: -10, pitch: [1, 1], priority: 40 }, PR), (rng, sr) => projLoop(el, rng, sr)));
  out.push(alias(`proj_hit_${el}`, `el_hit_${el}`, { gain: -1, pitch: [0.9, 1.0] }));
}
out.push(def('proj_reflect', Object.assign({ variants: 2, bus: 'Impacts', priority: 80 }, PR), (rng, sr) => K.tidy(K.mix(sr, [
  { buf: K.fmHit(sr, { f: 1500, ratio: 2.01, index: 2.2, dur: 0.2, idxDecay: 0.3 }), gain: 0 },
  { buf: K.sweep(sr, rng, { dur: 0.15, f0: 900, f1: 3200, q: 1.3, peakAt: 0.5, gain: 1 }), gain: -4 }]), sr)));
out.push(...hazards);
out.push(alias('zone_burning_puddle', 'zone_scorch', { gain: -4 }), alias('zone_live_puddle', 'zone_static', { gain: -5 }),
  alias('zone_fizzing_puddle', 'zone_static', { gain: -6, pitch: [1.1, 1.15] }), alias('zone_storm', 'zone_gale', { gain: -5 }),
  alias('zone_scorch_patch', 'zone_scorch'), alias('zone_brine_puddle', 'zone_brine'), alias('zone_static_field', 'zone_static'),
  alias('zone_sludge_puddle', 'zone_sludge'), alias('zone_grit_rubble', 'zone_grit'), alias('zone_gale_vortex', 'zone_gale'),
  alias('prop_burst_scorch', 'status_sizzle'), alias('prop_burst_brine', 'status_soaked'), alias('prop_burst_static', 'status_jolted'),
  alias('prop_burst_sludge', 'status_gunked'), alias('prop_burst_grit', 'status_caked'), alias('prop_burst_gale', 'status_winded'));
module.exports = out;
