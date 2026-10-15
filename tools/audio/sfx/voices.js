'use strict';
// Creature voices (ROSTER.md sound palettes, AUDIO_DIRECTION.md §3.5). Rendered at 22.05 kHz on the
// "Creatures" bus. Types per fighter: grunt (effort), hurt, ko, taunt, juice, idle.
const K = require('../lib/sfxkit');
const D = require('../lib/dsp');
const { def, jit } = require('./_def');

const VOICE = { bus: 'Creatures', group: 'voices', sr: 22050, priority: 60, max_voices: 6, gain: -3, pitch: [0.95, 1.05] };
const TYPES = { grunt: { variants: 3, cooldown: 0.3 }, hurt: { variants: 3, cooldown: 0.3 }, ko: { variants: 2, priority: 95 }, taunt: { variants: 2, cooldown: 3 }, juice: { variants: 1, priority: 90 }, idle: { variants: 2, cooldown: 4, gain: -8 } };

// shared: formant sets
const F = {
  a: [[700, 6, 1], [1150, 7, 0.6], [2600, 8, 0.25]],
  o: [[500, 6, 1], [900, 7, 0.5], [2400, 8, 0.15]],
  u: [[320, 6, 1], [800, 7, 0.35], [2300, 8, 0.1]],
  e: [[520, 6, 1], [1800, 7, 0.5], [2500, 8, 0.25]],
  i: [[300, 6, 0.8], [2200, 7, 0.5], [2900, 8, 0.3]],
};
const lowF = (set, mul) => set.map(([f, q, g]) => [f * mul, q, g]);

function voc(sr, rng, o) { return K.vocal(sr, rng, o); }
function growlRoom(buf, sr, amt = 0.2, size = 0.5) { return K.mix(sr, [{ buf, gain: 0 }, { buf: K.room(buf, sr, { size, mix: 0.5, damp: 0.5, predelay: 0.01 }), lin: amt }]); }

const palettes = {
  stoke: {
    base: { formants: F.a, growl: 0.4, growlRate: 34, jitter: 0.035, drive: 2.2, ring: 1900, ringGain: 0.35, breath: 0.15, wave: 'pulse', pw: 0.1 },
    grunt: (rng, sr) => voc(sr, rng, Object.assign({}, palettes.stoke.base, { dur: jit(rng, 0.22, 0.2), f0: [[0, 150], [0.08, 125], [0.25, 95]], a: 0.015, d: 0.08, s: 0.7, r: 0.06 })),
    hurt: (rng, sr) => voc(sr, rng, Object.assign({}, palettes.stoke.base, { dur: jit(rng, 0.3, 0.2), f0: [[0, 200], [0.1, 175], [0.3, 120]], formants: F.e, a: 0.01, d: 0.1, s: 0.6, r: 0.08 })),
    ko: (rng, sr) => voc(sr, rng, Object.assign({}, palettes.stoke.base, { dur: 0.75, f0: [[0, 170], [0.3, 140], [0.75, 70]], formants: F.o, growl: 0.5, a: 0.02, d: 0.2, s: 0.7, r: 0.15 })),
    taunt: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.stoke.base, { dur: 0.18, f0: [[0, 140], [0.18, 160]], a: 0.01, r: 0.04 })), gain: 0 },
      { buf: voc(sr, rng, Object.assign({}, palettes.stoke.base, { dur: 0.32, f0: [[0, 175], [0.15, 190], [0.32, 120]], formants: F.o, a: 0.01, r: 0.08 })), gain: 0, at: 0.24 }]),
    juice: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.stoke.base, { dur: 1.0, f0: [[0, 130], [0.6, 180], [1.0, 210]], growl: 0.55, drive: 2.8, a: 0.05, d: 0.3, s: 0.9, r: 0.15 })), gain: 0 },
      { buf: K.chirp(sr, { f0: 1600, f1: 3200, dur: 1.0, wave: 'sine', curve: 1, a: 0.3, gain: 0.25 }), gain: -8 }]),
    idle: (rng, sr) => K.mix(sr, [{ buf: K.burst(sr, rng, { dur: 0.18, filt: [{ type: 'bp', f: 2400, q: 0.7 }], a: 0.02, curve: 1.4, gain: 0.5 }), gain: 0 },
      { buf: K.burst(sr, rng, { dur: 0.16, filt: [{ type: 'bp', f: 2600, q: 0.7 }], a: 0.02, curve: 1.4, gain: 0.45 }), gain: -1, at: 0.22 }]),
  },
  dredge: {
    base: { formants: lowF(F.o, 0.7), growl: 0.3, growlRate: 18, jitter: 0.02, drive: 2.0, breath: 0.1, wave: 'pulse', pw: 0.18, lp: 3000 },
    grunt: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.dredge.base, { dur: jit(rng, 0.3, 0.2), f0: [[0, 75], [0.3, 58]], a: 0.03, r: 0.08 })), gain: 0 },
      { buf: K.bubbles(sr, rng, { dur: 0.3, rate: 16, fLo: 90, fHi: 300, popDur: 0.06, wet: 0.6 }), gain: -9 }]),
    hurt: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.dredge.base, { dur: 0.35, f0: [[0, 95], [0.1, 110], [0.35, 60]], formants: lowF(F.a, 0.75), a: 0.01, r: 0.1 })), gain: 0 },
      { buf: K.burst(sr, rng, { dur: 0.02, filt: [{ type: 'bp', f: 1800, q: 3 }], curve: 2.5, gain: 1.3 }), gain: -6, at: 0.02 }]),
    ko: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.dredge.base, { dur: 0.9, f0: [[0, 90], [0.5, 70], [0.9, 40]], growl: 0.45, a: 0.03, d: 0.3, s: 0.8, r: 0.2 })), gain: 0 },
      { buf: K.bubbles(sr, rng, { dur: 0.9, rate: 12, fLo: 70, fHi: 250, popDur: 0.08, wet: 0.7 }), gain: -6 }]),
    taunt: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.dredge.base, { dur: 0.7, f0: [[0, 62], [0.35, 68], [0.7, 58]], formants: lowF(F.u, 0.8), growl: 0.15, a: 0.1, d: 0.2, s: 0.9, r: 0.15, lp: 1500 })), gain: 0 },
      { buf: K.burst(sr, rng, { dur: 0.015, filt: [{ type: 'bp', f: 2000, q: 3 }], curve: 2.5, gain: 1.2 }), gain: -8, at: 0.72 },
      { buf: K.burst(sr, rng, { dur: 0.015, filt: [{ type: 'bp', f: 2300, q: 3 }], curve: 2.5, gain: 1.2 }), gain: -9, at: 0.8 }]),
    juice: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.dredge.base, { dur: 1.1, f0: [[0, 60], [0.5, 80], [1.1, 85]], growl: 0.5, drive: 2.6, a: 0.1, d: 0.3, s: 0.95, r: 0.2 })), gain: 0 },
      { buf: K.bubbles(sr, rng, { dur: 1.1, rate: 20, fLo: 80, fHi: 350, popDur: 0.07, wet: 0.8 }), gain: -5 }]),
    idle: (rng, sr) => K.bubbles(sr, rng, { dur: 0.5, rate: 6, fLo: 120, fHi: 380, popDur: 0.09, wet: 0.5 }),
  },
  gusto: {
    base: { formants: [[800, 7, 0.8], [2300, 9, 1], [3200, 9, 0.5]], growl: 0.1, growlRate: 50, jitter: 0.06, drive: 2.0, breath: 0.22, wave: 'pulse', pw: 0.08, lp: 7000, vib: 0.06, vibRate: 24 },
    grunt: (rng, sr) => voc(sr, rng, Object.assign({}, palettes.gusto.base, { dur: jit(rng, 0.16, 0.25), f0: [[0, 520], [0.05, 700], [0.16, 420]], a: 0.005, d: 0.05, s: 0.7, r: 0.04 })),
    hurt: (rng, sr) => voc(sr, rng, Object.assign({}, palettes.gusto.base, { dur: jit(rng, 0.28, 0.2), f0: [[0, 650], [0.08, 820], [0.28, 380]], a: 0.005, d: 0.08, s: 0.65, r: 0.06 })),
    ko: (rng, sr) => voc(sr, rng, Object.assign({}, palettes.gusto.base, { dur: 0.8, f0: [[0, 700], [0.25, 560], [0.8, 220]], vib: 0.1, vibRate: 12, a: 0.01, d: 0.2, s: 0.7, r: 0.15 })),
    taunt: (rng, sr) => { // laugh: repeated squawk pulses
      const parts = [];
      for (let i = 0; i < 5; i++) parts.push({ buf: voc(sr, rng, Object.assign({}, palettes.gusto.base, { dur: 0.09, f0: [[0, 600 - i * 30], [0.09, 520 - i * 30]], a: 0.004, d: 0.04, s: 0.6, r: 0.03 })), gain: -i * 0.8, at: i * 0.13 });
      return K.mix(sr, parts);
    },
    juice: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.gusto.base, { dur: 0.9, f0: [[0, 480], [0.4, 760], [0.9, 900]], vib: 0.08, vibRate: 16, a: 0.03, d: 0.2, s: 0.9, r: 0.12 })), gain: 0 },
      { buf: K.sweep(sr, rng, { dur: 0.9, f0: 400, f1: 3000, q: 1, color: 'pink', peakAt: 0.8, curve: 1.4, gain: 1 }), gain: -6 }]),
    idle: (rng, sr) => voc(sr, rng, Object.assign({}, palettes.gusto.base, { dur: 0.2, f0: [[0, 560], [0.1, 640], [0.2, 500]], breath: 0.3, a: 0.01, r: 0.05 })),
  },
  dozer: {
    base: { formants: lowF(F.u, 0.85), growl: 0.2, growlRate: 20, jitter: 0.03, drive: 1.8, breath: 0.45, wave: 'pulse', pw: 0.2, lp: 2600 },
    grunt: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.dozer.base, { dur: jit(rng, 0.28, 0.2), f0: [[0, 95], [0.1, 110], [0.28, 70]], a: 0.01, d: 0.1, s: 0.6, r: 0.08 })), gain: 0 },
      { buf: K.burst(sr, rng, { dur: 0.1, color: 'pink', filt: [{ type: 'bp', f: 500, q: 1 }], a: 0.005, curve: 1.8 }), gain: -4 }]),
    hurt: (rng, sr) => voc(sr, rng, Object.assign({}, palettes.dozer.base, { dur: 0.35, f0: [[0, 130], [0.1, 150], [0.35, 80]], formants: lowF(F.a, 0.85), breath: 0.3, a: 0.01, d: 0.1, s: 0.6, r: 0.1 })),
    ko: (rng, sr) => voc(sr, rng, Object.assign({}, palettes.dozer.base, { dur: 0.9, f0: [[0, 120], [0.4, 95], [0.9, 50]], formants: lowF(F.o, 0.85), growl: 0.35, a: 0.02, d: 0.3, s: 0.7, r: 0.2 })),
    taunt: (rng, sr) => { // happy snorts
      const parts = [];
      for (let i = 0; i < 3; i++) parts.push({ buf: voc(sr, rng, Object.assign({}, palettes.dozer.base, { dur: 0.14, f0: [[0, 100 + i * 10], [0.14, 85]], breath: 0.6, a: 0.005, d: 0.06, s: 0.5, r: 0.04 })), gain: -i, at: i * 0.2 });
      return K.mix(sr, parts);
    },
    juice: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.dozer.base, { dur: 1.0, f0: [[0, 85], [0.5, 120], [1.0, 130]], growl: 0.4, drive: 2.4, breath: 0.3, a: 0.05, d: 0.3, s: 0.95, r: 0.2 })), gain: 0 }]),
    idle: (rng, sr) => K.mix(sr, [ // sneeze: intake + burst
      { buf: K.burst(sr, rng, { dur: 0.25, filt: [{ type: 'bp', f: 1500, q: 0.8 }], a: 0.2, curve: 1, gain: 0.5 }), gain: -6 },
      { buf: voc(sr, rng, Object.assign({}, palettes.dozer.base, { dur: 0.2, f0: [[0, 160], [0.05, 120], [0.2, 80]], breath: 0.6, a: 0.003, d: 0.08, s: 0.4, r: 0.06 })), gain: 0, at: 0.26 }]),
  },
  slurry: {
    base: { formants: [[400, 7, 0.9], [1400, 8, 0.5], [3000, 9, 0.4]], growl: 0.0, jitter: 0.03, drive: 1.6, breath: 0.55, wave: 'saw', lp: 7500 },
    grunt: (rng, sr) => K.mix(sr, [{ buf: K.burst(sr, rng, { dur: 0.25, filt: [{ type: 'bp', f: 3800, q: 0.9 }, { type: 'hp', f: 2000 }], a: 0.02, curve: 1.4, gain: 0.9 }), gain: 0 },
      { buf: K.bubbles(sr, rng, { dur: 0.22, rate: 24, fLo: 150, fHi: 500, popDur: 0.05, wet: 0.9 }), gain: -6, at: 0.03 }]),
    hurt: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.slurry.base, { dur: 0.3, f0: [[0, 200], [0.1, 240], [0.3, 140]], a: 0.01, d: 0.1, s: 0.6, r: 0.08 })), gain: 0 },
      { buf: K.bubbles(sr, rng, { dur: 0.3, rate: 30, fLo: 120, fHi: 450, popDur: 0.05, wet: 1 }), gain: -4 }]),
    ko: (rng, sr) => K.mix(sr, [{ buf: K.burst(sr, rng, { dur: 0.9, filt: [{ type: 'bp', f: 3200, q: 0.8 }, { type: 'hp', f: 1500 }], a: 0.03, curve: 1.3, gain: 0.9 }), gain: -2 },
      { buf: K.bubbles(sr, rng, { dur: 0.9, rate: 14, fLo: 80, fHi: 300, popDur: 0.09, wet: 0.9 }), gain: 0 }]),
    taunt: (rng, sr) => { // bubbly chuckle
      const parts = [];
      for (let i = 0; i < 4; i++) parts.push({ buf: K.bubbles(sr, rng, { dur: 0.09, rate: 60, fLo: 220 + i * 40, fHi: 520 + i * 40, popDur: 0.04, wet: 0.9 }), gain: -i * 0.7, at: i * 0.14 });
      parts.push({ buf: K.burst(sr, rng, { dur: 0.5, filt: [{ type: 'bp', f: 3000, q: 1 }], a: 0.05, curve: 1.2, gain: 0.3 }), gain: -10 });
      return K.mix(sr, parts);
    },
    juice: (rng, sr) => K.mix(sr, [{ buf: K.bubbles(sr, rng, { dur: 1.0, rate: 26, fLo: 70, fHi: 300, popDur: 0.09, wet: 0.9 }), gain: 0 },
      { buf: K.sweep(sr, rng, { dur: 1.0, f0: 2000, f1: 5000, q: 1, peakAt: 0.8, curve: 1.4, gain: 1 }), gain: -8 }]),
    idle: (rng, sr) => K.mix(sr, [{ buf: K.bubbles(sr, rng, { dur: 0.15, rate: 30, fLo: 200, fHi: 500, popDur: 0.06, wet: 0.8 }), gain: 0 },
      { buf: K.burst(sr, rng, { dur: 0.04, color: 'pink', filt: [{ type: 'bp', f: 700, q: 1 }], curve: 2 }), gain: -3, at: 0.16 }]),
  },
  jitters: {
    base: { formants: [[600, 6, 0.6], [2200, 9, 1], [3600, 9, 0.6]], growl: 0.0, jitter: 0.05, drive: 1.5, breath: 0.1, wave: 'pulse', pw: 0.3, lp: 8000, vib: 0.04, vibRate: 30 },
    grunt: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.jitters.base, { dur: jit(rng, 0.14, 0.25), f0: [[0, 650], [0.14, 560]], a: 0.005, d: 0.05, s: 0.7, r: 0.04 })), gain: 0 },
      { buf: K.crackle(sr, rng, { dur: 0.14, density: 300, tone: 5000, decayMs: 2, gain: 0.5 }), gain: -10 }]),
    hurt: (rng, sr) => voc(sr, rng, Object.assign({}, palettes.jitters.base, { dur: 0.2, f0: [[0, 700], [0.06, 1100], [0.2, 800]], formants: [[400, 6, 0.6], [2600, 9, 1], [3400, 9, 0.5]], a: 0.004, d: 0.06, s: 0.7, r: 0.05 })),
    ko: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.jitters.base, { dur: 0.8, f0: [[0, 800], [0.4, 600], [0.8, 180]], vib: 0.08, vibRate: 18, a: 0.01, d: 0.2, s: 0.7, r: 0.15 })), gain: 0 },
      { buf: K.crackle(sr, rng, { dur: 0.8, density: 200, tone: 4500, decayMs: 2, gain: 0.5 }), gain: -8 }]),
    taunt: (rng, sr) => { // kazoo giggle
      const parts = [];
      for (let i = 0; i < 5; i++) parts.push({ buf: voc(sr, rng, Object.assign({}, palettes.jitters.base, { dur: 0.08, f0: [[0, 520 + i * 25], [0.08, 480 + i * 25]], wave: 'saw', breath: 0.05, formants: [[900, 5, 1], [1900, 6, 0.8], [3000, 7, 0.4]], a: 0.004, d: 0.03, s: 0.7, r: 0.02 })), gain: -i * 0.6, at: i * 0.11 });
      return K.mix(sr, parts);
    },
    juice: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.jitters.base, { dur: 1.0, f0: [[0, 500], [0.5, 900], [1.0, 1200]], vib: 0.06, vibRate: 22, a: 0.05, d: 0.3, s: 0.95, r: 0.15 })), gain: 0 },
      { buf: K.crackle(sr, rng, { dur: 1.0, density: 400, tone: 5500, decayMs: 2, gain: 0.6 }), gain: -8 }]),
    idle: (rng, sr) => voc(sr, rng, Object.assign({}, palettes.jitters.base, { dur: 0.35, f0: [[0, 600], [0.35, 620]], a: 0.05, d: 0.1, s: 0.8, r: 0.1, breath: 0.05 })),
  },
  scrapling: {
    base: { formants: [[900, 8, 1], [1900, 9, 0.7], [3300, 9, 0.5]], growl: 0.3, growlRate: 45, jitter: 0.05, drive: 2.5, breath: 0.15, wave: 'square', lp: 6000 },
    post: (b, sr) => K.filterChain(D.bitcrush(b, 7, 2), sr, [{ type: 'bp', f: 1800, q: 0.6 }, { type: 'hp', f: 500 }]),
    grunt: (rng, sr) => palettes.scrapling.post(voc(sr, rng, Object.assign({}, palettes.scrapling.base, { dur: 0.18, f0: [[0, 260], [0.18, 200]], a: 0.005, r: 0.04 })), sr),
    hurt: (rng, sr) => palettes.scrapling.post(voc(sr, rng, Object.assign({}, palettes.scrapling.base, { dur: 0.25, f0: [[0, 320], [0.1, 380], [0.25, 220]], a: 0.005, r: 0.05 })), sr),
    ko: (rng, sr) => palettes.scrapling.post(K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.scrapling.base, { dur: 0.5, f0: [[0, 300], [0.5, 120]], a: 0.01, r: 0.1 })), gain: 0 },
      { buf: K.rattle(sr, rng, { dur: 0.4, f: 200, density: 90, gain: 0.8, hp: 600 }), gain: -5, at: 0.2 }]), sr),
    taunt: (rng, sr) => { const parts = []; for (let i = 0; i < 4; i++) parts.push({ buf: voc(sr, rng, Object.assign({}, palettes.scrapling.base, { dur: 0.07, f0: [[0, 280 + i * 40], [0.07, 260]], a: 0.003, r: 0.02 })), gain: 0, at: i * 0.1 }); return palettes.scrapling.post(K.mix(sr, parts), sr); },
    juice: (rng, sr) => palettes.scrapling.post(voc(sr, rng, Object.assign({}, palettes.scrapling.base, { dur: 0.5, f0: [[0, 240], [0.5, 400]], a: 0.02, r: 0.1 })), sr),
    idle: (rng, sr) => palettes.scrapling.post(K.rattle(sr, rng, { dur: 0.25, f: 240, density: 60, gain: 0.7, hp: 700 }), sr),
  },
  blister: {
    base: { formants: [[500, 7, 0.8], [1500, 8, 0.6], [2800, 9, 0.3]], growl: 0, jitter: 0.03, drive: 1.4, breath: 0.4, wave: 'sine', lp: 6000 },
    grunt: (rng, sr) => K.chirp(sr, { f0: 900, f1: 1500, dur: 0.3, wave: 'sine', curve: 1.2, a: 0.03, gain: 0.6 }),
    hurt: (rng, sr) => K.mix(sr, [{ buf: K.chirp(sr, { f0: 1400, f1: 900, dur: 0.2, wave: 'sine', curve: 1.5, a: 0.005, gain: 0.6 }), gain: 0 }, { buf: K.bubbles(sr, rng, { dur: 0.15, rate: 30, fLo: 200, fHi: 600, popDur: 0.04, wet: 0.9 }), gain: -6 }]),
    ko: (rng, sr) => K.mix(sr, [{ buf: K.chirp(sr, { f0: 1200, f1: 3200, dur: 0.9, wave: 'sine', curve: 0.8, a: 0.1, gain: 0.5 }), gain: 0 },
      { buf: K.thump(sr, { f0: 260, f1: 90, sweep: 0.02, dur: 0.15, drive: 1.8 }), gain: 0, at: 0.9 }, { buf: K.splash(sr, rng, { dur: 0.3, size: 0.9 }), gain: -3, at: 0.9 }]),
    taunt: (rng, sr) => K.chirp(sr, { f0: 800, f1: 1100, dur: 0.4, wave: 'sine', curve: 1, a: 0.05, gain: 0.5 }),
    juice: (rng, sr) => K.chirp(sr, { f0: 700, f1: 2800, dur: 1.2, wave: 'sine', curve: 0.7, a: 0.1, gain: 0.5 }), // the inflating whistle telegraph
    idle: (rng, sr) => K.bubbles(sr, rng, { dur: 0.2, rate: 25, fLo: 300, fHi: 700, popDur: 0.05, wet: 0.7 }),
  },
  bilge: {
    base: { formants: lowF(F.a, 0.8), growl: 0.5, growlRate: 26, jitter: 0.04, drive: 2.6, breath: 0.2, wave: 'pulse', pw: 0.12, lp: 4000 },
    post: (b, sr) => growlRoom(b, sr, 0.5, 0.75),
    grunt: (rng, sr) => palettes.bilge.post(voc(sr, rng, Object.assign({}, palettes.bilge.base, { dur: 0.22, f0: [[0, 140], [0.05, 170], [0.22, 100]], a: 0.004, d: 0.06, s: 0.7, r: 0.06 })), sr), // bark
    hurt: (rng, sr) => palettes.bilge.post(voc(sr, rng, Object.assign({}, palettes.bilge.base, { dur: 0.4, f0: [[0, 200], [0.1, 230], [0.4, 120]], formants: lowF(F.e, 0.85), a: 0.01, d: 0.1, s: 0.6, r: 0.1 })), sr),
    ko: (rng, sr) => palettes.bilge.post(voc(sr, rng, Object.assign({}, palettes.bilge.base, { dur: 1.1, f0: [[0, 180], [0.5, 150], [1.1, 60]], formants: lowF(F.o, 0.8), a: 0.02, d: 0.3, s: 0.7, r: 0.25 })), sr),
    taunt: (rng, sr) => { // pant
      const parts = [];
      for (let i = 0; i < 4; i++) parts.push({ buf: K.burst(sr, rng, { dur: 0.12, color: 'pink', filt: [{ type: 'bp', f: 900, q: 0.8 }], a: 0.02, curve: 1.3, gain: 0.8 }), gain: -1, at: i * 0.22 });
      return palettes.bilge.post(K.mix(sr, parts), sr);
    },
    juice: (rng, sr) => palettes.bilge.post(K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.bilge.base, { dur: 1.2, f0: [[0, 120], [0.6, 180], [1.2, 160]], growl: 0.6, drive: 3, a: 0.05, d: 0.3, s: 0.95, r: 0.2 })), gain: 0 },
      { buf: K.rattle(sr, rng, { dur: 1.2, f: 70, density: 60, gain: 1 }), gain: -6 }]), sr),
    idle: (rng, sr) => palettes.bilge.post(voc(sr, rng, Object.assign({}, palettes.bilge.base, { dur: 0.5, f0: [[0, 110], [0.5, 90]], formants: lowF(F.u, 0.8), growl: 0.5, a: 0.05, r: 0.15, lp: 1500 })), sr),
  },
  conduit: {
    base: { formants: [[700, 6, 0.8], [1600, 8, 0.8], [3200, 9, 0.6]], growl: 0.6, growlRate: 60, jitter: 0.1, drive: 2.8, breath: 0.2, wave: 'saw', lp: 8000, vib: 0.1, vibRate: 40 },
    grunt: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.conduit.base, { dur: 0.25, f0: [[0, 180], [0.25, 240]], a: 0.005, r: 0.05 })), gain: 0 }, { buf: K.zap(sr, rng, { dur: 0.12, f: 3500, buzz: 150 }), gain: -4 }]),
    hurt: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.conduit.base, { dur: 0.3, f0: [[0, 300], [0.1, 420], [0.3, 200]], a: 0.005, r: 0.06 })), gain: 0 }, { buf: K.zap(sr, rng, { dur: 0.2, f: 2800, buzz: 90 }), gain: -3, at: 0.05 }]),
    ko: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.conduit.base, { dur: 1.0, f0: [[0, 260], [0.5, 200], [1.0, 60]], a: 0.01, d: 0.3, s: 0.7, r: 0.2 })), gain: 0 },
      { buf: K.buzz(sr, rng, { dur: 1.0, f: 90, harmonics: 3, am: 0.6, amRate: 20, lp: 3000, wave: 'saw', jitter: 0.2, gain: 0.5 }), gain: -6 }]),
    taunt: (rng, sr) => { const parts = []; for (let i = 0; i < 6; i++) parts.push({ buf: K.zap(sr, rng, { dur: 0.08, f: 2000 + i * 500, buzz: 120 }), gain: -2, at: i * 0.09 }); return K.mix(sr, parts); },
    juice: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.conduit.base, { dur: 1.2, f0: [[0, 150], [0.6, 320], [1.2, 400]], a: 0.05, d: 0.3, s: 0.95, r: 0.2 })), gain: 0 },
      { buf: K.chirp(sr, { f0: 200, f1: 3000, dur: 1.2, wave: 'square', curve: 1, a: 0.1, gain: 0.3 }), gain: -8 }]),
    idle: (rng, sr) => K.buzz(sr, rng, { dur: 0.5, f: 60, harmonics: 2, am: 0.4, amRate: 11, lp: 2500, wave: 'saw', jitter: 0.05, gain: 0.5 }),
  },
  snappington: {
    base: { formants: lowF(F.a, 0.9), growl: 0.25, growlRate: 22, jitter: 0.08, drive: 1.8, breath: 0.3, wave: 'pulse', pw: 0.1, lp: 4500 },
    gav: (rng, sr) => K.mix(sr, [{ buf: K.burst(sr, rng, { dur: 0.012, filt: [{ type: 'bp', f: 1150, q: 3.5 }], curve: 2.5, gain: 2 }), gain: 0 }, { buf: K.thump(sr, { f0: 220, f1: 150, sweep: 0.01, dur: 0.05, drive: 1.4 }), gain: -4 }]),
    grunt: (rng, sr) => voc(sr, rng, Object.assign({}, palettes.snappington.base, { dur: 0.25, f0: [[0, 100], [0.25, 80]], a: 0.01, r: 0.06 })),
    hurt: (rng, sr) => voc(sr, rng, Object.assign({}, palettes.snappington.base, { dur: 0.3, f0: [[0, 130], [0.08, 150], [0.3, 90]], formants: lowF(F.e, 0.9), a: 0.005, r: 0.08 })),
    ko: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.snappington.base, { dur: 0.9, f0: [[0, 110], [0.5, 90], [0.9, 50]], a: 0.02, d: 0.3, s: 0.7, r: 0.2 })), gain: 0 }, { buf: palettes.snappington.gav(rng, sr), gain: -2, at: 0.95 }]),
    taunt: (rng, sr) => K.mix(sr, [{ buf: palettes.snappington.gav(rng, sr), gain: 0 }, { buf: palettes.snappington.gav(rng, sr), gain: -1, at: 0.16 },
      { buf: voc(sr, rng, Object.assign({}, palettes.snappington.base, { dur: 0.4, f0: [[0, 95], [0.4, 85]], formants: lowF(F.u, 0.9), a: 0.03, r: 0.1 })), gain: -2, at: 0.3 }]),
    juice: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.snappington.base, { dur: 1.0, f0: [[0, 90], [0.5, 140], [1.0, 150]], growl: 0.5, drive: 2.6, a: 0.05, d: 0.3, s: 0.95, r: 0.2 })), gain: 0 },
      { buf: K.bubbles(sr, rng, { dur: 0.6, rate: 30, fLo: 150, fHi: 500, popDur: 0.05, wet: 0.7 }), gain: -6, at: 0.1 }, { buf: palettes.snappington.gav(rng, sr), gain: 0, at: 1.02 }]),
    idle: (rng, sr) => K.mix(sr, [{ buf: palettes.snappington.gav(rng, sr), gain: 0 }, { buf: K.burst(sr, rng, { dur: 0.3, filt: [{ type: 'bp', f: 1200, q: 0.7 }], a: 0.05, curve: 1.2, gain: 0.3 }), gain: -8, at: 0.1 }]),
  },
  lamprey: {
    base: { formants: [[600, 6, 0.9], [1700, 8, 0.7], [3200, 9, 0.5]], growl: 0.35, growlRate: 40, jitter: 0.05, drive: 2.2, breath: 0.4, wave: 'saw', lp: 7000 },
    grunt: (rng, sr) => K.mix(sr, [{ buf: voc(sr, rng, Object.assign({}, palettes.lamprey.base, { dur: 0.2, f0: [[0, 190], [0.2, 150]], a: 0.005, r: 0.05 })), gain: 0 }, { buf: K.burst(sr, rng, { dur: 0.015, filt: [{ type: 'bp', f: 2500, q: 3 }], curve: 2.5, gain: 1.2 }), gain: -6 }]),
    hurt: (rng, sr) => voc(sr, rng, Object.assign({}, palettes.lamprey.base, { dur: 0.3, f0: [[0, 260], [0.1, 300], [0.3, 170]], a: 0.005, r: 0.08 })),
    ko: (rng, sr) => voc(sr, rng, Object.assign({}, palettes.lamprey.base, { dur: 0.8, f0: [[0, 220], [0.4, 180], [0.8, 70]], a: 0.02, d: 0.3, s: 0.7, r: 0.2 })),
    taunt: (rng, sr) => { const parts = []; for (let i = 0; i < 3; i++) parts.push({ buf: K.burst(sr, rng, { dur: 0.012, filt: [{ type: 'bp', f: 2600, q: 3 }], curve: 2.5, gain: 1.3 }), gain: -1, at: i * 0.09 }); parts.push({ buf: voc(sr, rng, Object.assign({}, palettes.lamprey.base, { dur: 0.3, f0: [[0, 200], [0.15, 230], [0.3, 170]], a: 0.01, r: 0.08 })), gain: 0, at: 0.3 }); return K.mix(sr, parts); },
    juice: (rng, sr) => voc(sr, rng, Object.assign({}, palettes.lamprey.base, { dur: 0.9, f0: [[0, 170], [0.5, 260], [0.9, 280]], a: 0.05, d: 0.3, s: 0.95, r: 0.2 })),
    idle: (rng, sr) => K.burst(sr, rng, { dur: 0.3, filt: [{ type: 'bp', f: 3500, q: 0.8 }, { type: 'hp', f: 2000 }], a: 0.03, curve: 1.3, gain: 0.6 }),
  },
};

const out = [];
for (const [fighter, pal] of Object.entries(palettes)) {
  for (const [type, opts] of Object.entries(TYPES)) {
    out.push(def(`voice_${fighter}_${type}`, Object.assign({}, VOICE, opts), (rng, sr) => K.tidy(pal[type](rng, sr), sr, { fadeOut: 0.02 })));
  }
}
module.exports = out;
module.exports.FIGHTERS = Object.keys(palettes);
