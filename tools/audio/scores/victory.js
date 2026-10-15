'use strict';
// Track 6 — VICTORY STING: BELT UP. 120 BPM, E♭ major, 6 bars, non-looping. Full brass fanfare
// (four FM voices), snare roll, crash, a choir swell standing in for the crowd roar, then a two-bar
// swung tag with the muted trumpet.
const H = require('./_h');

const V1 = ['eb5 . . eb5 eb5 . eb5 . g5 - - - . . . .', 'ab5 . . ab5 ab5 . bb5 . c6 - - - - - - -', 'bb5 . . bb5 bb5 . bb5 . eb6 - - - - - - -', 'eb6 - - - - - - - - - - - - - - -'];
const V2 = ['bb4 . . bb4 bb4 . bb4 . eb5 - - - . . . .', 'c5 . . c5 c5 . eb5 . eb5 - - - - - - -', 'f5 . . f5 f5 . g5 . g5 - - - - - - -', 'g5 - - - - - - - - - - - - - - -'];
const V3 = ['g4 . . g4 g4 . g4 . bb4 - - - . . . .', 'ab4 . . ab4 ab4 . g4 . ab4 - - - - - - -', 'd5 . . d5 d5 . d5 . bb4 - - - - - - -', 'bb4 - - - - - - - - - - - - - - -'];
const V4 = ['eb3 . . eb3 eb3 . eb3 . eb3 - - - . . . .', 'ab2 . . ab2 ab2 . ab2 . ab2 - - - - - - -', 'bb2 . . bb2 bb2 . bb2 . bb2 - - - - - - -', 'eb3 - - - - - - - - - - - - - - -'];

module.exports = {
  id: 'victory', title: 'Belt Up', bpm: 120, sr: 44100, stereo: true, gain: -6, tags: ['sting', 'win'], stinger: true, tail: 3.5,
  sections: ['fanfare', 'tag'], bars: { fanfare: 4, tag: 2 },
  loop: null,
  master: { lufs: -14, ceiling: -1, hp: 30, comp: { threshold: -14, ratio: 2.5, attack: 0.015, release: 0.2, knee: 6 }, reverb: { size: 0.7, damp: 0.4, predelay: 0.03, lowcut: 200, level: 1.0 } },
  tracks: [
    { name: 'brass1', inst: 'fmBrass', params: { index: 3.4, feedback: 0.3, a: 0.015, d: 0.2, s: 0.8, r: 0.3, cutoff: 6000, drive: 1.6 }, gain: -9, pan: 0.15, send: 0.45, gate: 0.9, patterns: { fanfare: V1 } },
    { name: 'brass2', inst: 'fmBrass', params: { index: 3.0, feedback: 0.3, a: 0.015, d: 0.2, s: 0.8, r: 0.3, cutoff: 5200, drive: 1.5, detune: -0.4 }, gain: -11, pan: -0.15, send: 0.45, gate: 0.9, patterns: { fanfare: V2 } },
    { name: 'brass3', inst: 'fmBrass', params: { index: 2.6, feedback: 0.25, a: 0.02, d: 0.2, s: 0.8, r: 0.3, cutoff: 4200, drive: 1.4, detune: 0.5 }, gain: -12, pan: 0.3, send: 0.45, gate: 0.9, patterns: { fanfare: V3 } },
    { name: 'brass4', inst: 'fmBrass', params: { index: 2.2, feedback: 0.2, a: 0.02, d: 0.25, s: 0.85, r: 0.35, cutoff: 2800, drive: 1.6 }, gain: -8, pan: -0.05, send: 0.3, gate: 0.95, patterns: { fanfare: V4 } },
    { name: 'sub', inst: 'subBass', params: { drive: 1.8, r: 0.3 }, gain: -8, gate: 0.95, patterns: { fanfare: V4, tag: ['eb2*8 - - - - - - - . . . . . . . .', '. . . . . . . . eb2*6 - - - - - . .'] } },
    { name: 'snare', inst: 'snare', params: { tone: 200, decay: 0.18, noiseDecay: 0.25, snap: 1.2 }, gain: -6, send: 0.2,
      patterns: { fanfare: ['r r r r r r r r r r r r r r r r', 'x . . . r r r r x . . . r r r r', 'x . . . x . . . r r r r r r r r', 'X . . . . . . . . . . . . . . .'], tag: ['. . . . x . . . . . . . x . . .', '. . . . x . . . . . . . x . . X'] } },
    { name: 'kick', inst: 'kick', params: { start: 150, end: 46, decay: 0.45, drive: 2 }, gain: -3,
      patterns: { fanfare: ['x . . . x . . . x . . . x . . .', 'x . . . x . . . x . . . x . . .', 'x . . . x . . . x . . . x . . .', 'X . . . . . . . . . . . . . . .'], tag: ['x . . . . . x . x . . . . . . .', 'x . . . . . x . x . . . . . x .'] } },
    { name: 'crash', inst: 'crash', params: { decay: 2.4 }, gain: -10, pan: 0.1, send: 0.3, patterns: { fanfare: [null, null, null, 'X . . . . . . . . . . . . . . .'], tag: [null, '. . . . . . . . . . . . . . . X'] } },
    { name: 'choir', inst: 'choirPad', params: { vowel: 'ah', a: 0.6, r: 1.2, voices: 5, detune: 10 }, gain: -16, send: 0.6, gate: 1,
      patterns: { fanfare: [null, 'eb4+g4+bb4+eb5*44 - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -'] } },
    { name: 'hat', inst: 'hat', params: { decay: 0.05 }, gain: -14, swing: 0.6, patterns: { tag: ['x . x . x . x o x . x . x . x o'] } },
    { name: 'trumpet', inst: 'mutedTrumpet', params: { index: 1.5, flat: -3, vib: 0.008 }, gain: -8, pan: 0.2, send: 0.4, gate: 0.9, swing: 0.6, humanize: 0.3,
      patterns: { tag: ['. . . . bb4 . c5 . eb5 . f5 . g5 - - -', 'eb5 . g5 . bb5 - - - - - - - . . . .'] } },
    { name: 'stabtag', inst: 'fmBrass', params: { index: 3, a: 0.01, d: 0.15, s: 0.5, r: 0.2, cutoff: 5000, drive: 1.5 }, gain: -11, send: 0.35, gate: 0.5,
      patterns: { tag: [H.stab(H.chord('ab3', 'M', 1), [0, 10], ':8'), H.stab(H.chord('eb4', 'M', 0), [0, 8], ':9')] } },
  ],
};
