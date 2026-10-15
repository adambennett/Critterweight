'use strict';
// Announcer stingers (bell, brass sting, mic pop). The babble grain banks are rendered by build.js
// from lib/babble.js into game/assets/audio/announcer/<character>/.
const K = require('../lib/sfxkit');
const D = require('../lib/dsp');
const INST = require('../lib/instruments');
const { def } = require('./_def');

const ANN = { bus: 'Dialogue', group: 'announcer', priority: 85, max_voices: 2, spatial: false, pitch: [0.99, 1.01], gain: -2 };

module.exports = [
  def('ann_bell', Object.assign({ variants: 2 }, ANN), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.fmHit(sr, { f: 620, ratio: 1.58, index: 3.2, dur: 1.8, idxDecay: 0.3, detune: 5 }), gain: 0 },
    { buf: K.fmHit(sr, { f: 1240, ratio: 2.2, index: 1.5, dur: 0.6, idxDecay: 0.3 }), gain: -8 },
    { buf: K.burst(sr, rng, { dur: 0.008, filt: [{ type: 'hp', f: 3000 }], curve: 2.5 }), gain: -6 }]), sr, { fadeOut: 0.05 })),
  def('ann_bell_triple', Object.assign({ variants: 1 }, ANN), (rng, sr) => {
    const b = () => K.fmHit(sr, { f: 620, ratio: 1.58, index: 3.2, dur: 1.2, idxDecay: 0.3, detune: 5 });
    return K.tidy(K.mix(sr, [{ buf: b(), gain: 0 }, { buf: b(), gain: 0, at: 0.28 }, { buf: b(), gain: 0, at: 0.56 }]), sr, { fadeOut: 0.05 });
  }),
  def('ann_sting', Object.assign({ variants: 2 }, ANN), (rng, sr) => {
    const brass = INST.make('fmBrass', { index: 3.2, a: 0.015, d: 0.25, s: 0.6, r: 0.3 });
    const notes = [[146.83, 0], [220.0, 0], [293.66, 0], [349.23, 0.02]];
    const chord = K.mix(sr, notes.map(([f, at]) => ({ buf: brass.render({ freq: f, dur: 0.45, vel: 1 }, sr, rng), gain: -5, at })));
    const hit = K.mix(sr, [{ buf: INST.make('kick').render({ freq: 0, dur: 0.1, vel: 1 }, sr, rng), gain: -3 }, { buf: INST.make('crash', { decay: 1.2 }).render({ freq: 0, dur: 0.1, vel: 0.9 }, sr, rng), gain: -10 }]);
    return K.tidy(K.mix(sr, [{ buf: chord, gain: 0 }, { buf: hit, gain: 0 }]), sr, { fadeOut: 0.05 });
  }),
  def('ann_mic_pop', Object.assign({ variants: 1, gain: -8 }, ANN), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.thump(sr, { f0: 220, f1: 90, sweep: 0.01, dur: 0.06, drive: 1.5 }), gain: 0 },
    { buf: K.burst(sr, rng, { dur: 0.08, color: 'pink', filt: [{ type: 'bp', f: 400, q: 1 }], a: 0.002, curve: 1.8 }), gain: -4 },
    { buf: K.buzz(sr, rng, { dur: 0.25, f: 60, harmonics: 1, am: 0.3, amRate: 100, lp: 1500, wave: 'saw', jitter: 0.001, gain: 0.08 }), gain: -12, at: 0.05 }]), sr)),
];
