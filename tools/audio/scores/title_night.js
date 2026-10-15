'use strict';
// Track 8 — TITLE NIGHT (bonus). 112 BPM, G major. Over-the-top broadcast: Fight Night Poster's
// brass at full size, pyro whooshes on bar 1, a choir-ish pad through vowel formants, and the crowd
// at max (crowd system). Intro 4 → A 16 → B 8. Loop bars 5–28.
const H = require('./_h');

const PROG_A = [['g2', 'M', 2], ['c2', 'M', 1], ['d2', 'M', 1], ['g2', 'M', 1], ['e2', 'm', 1], ['c2', 'M', 1], ['d2', 'M', 1]];
const PROG_B = [['c2', 'M', 1], ['d2', 'M', 1], ['g2', 'M', 1], ['e2', 'm', 1], ['c2', 'M', 1], ['d2', 'M', 1], ['g2', 'M', 2]];

const stabs = (prog) => H.fromProg(prog, (c, root, type) => H.stab(H.chord(H.tr(root, 12), type, 1), [0, 6, 10], ':9'));
const bass = (prog) => H.fromProg(prog, (c, root, type, b) => H.bass(root, b % 2 === 0 ? 'R . . . R . O . R . . . R . 5 .' : 'R . . . R . O . R . . . 5 . O .'));
const choir = (prog) => H.fromProg(prog, (c, root, type) => H.stab(H.chord(H.tr(root, 12), type, 1), [0], '*16'));
const MELODY_A = [
  'd5 . . . g5 . . . b5 - - - a5 . g5 .', 'a5 - - - - - - - . . . . . . . .',
  'c5 . . . e5 . . . g5 - - - a5 . g5 .', 'fs5 - - - - - - - d5 - - - . . . .',
  'd5 . . . g5 . . . b5 - - - a5 . g5 .', 'b5 - - - - - - - g5 . e5 . . . . .',
  'c5 . . . e5 . . . g5 - - - a5 . b5 .', 'a5 - - - - - - - - - - - . . . .',
  'd5 . . . g5 . . . b5 - - - a5 . g5 .', 'a5 - - - - - - - . . . . . . . .',
  'c5 . . . e5 . . . g5 - - - a5 . g5 .', 'fs5 - - - - - - - d5 - - - . . . .',
  'g5 . . . b5 . . . d6 - - - c6 . b5 .', 'a5 - - - - - - - g5 . e5 . . . . .',
  'c6 . . . b5 . . . a5 - - - g5 . fs5 .', 'g5~ - - - - - - - - - - - . . . .',
].map((s) => s.replace(/fs5/g, 'f#5'));

module.exports = {
  id: 'title_night', title: 'Title Night', bpm: 112, sr: 44100, stereo: true, swing: 0.3, gain: -6, tags: ['title', 'menu_bonus'],
  sections: ['intro', 'A', 'B'], bars: { intro: 4, A: 16, B: 8 },
  loop: { startBar: 5, endBar: 28 },
  master: { lufs: -14, ceiling: -1, hp: 30, comp: { threshold: -14, ratio: 2.5, attack: 0.015, release: 0.18, knee: 6 }, reverb: { size: 0.68, damp: 0.42, predelay: 0.03, lowcut: 200, level: 1.0 }, eq: [{ f: 3000, q: 0.8, gain: 1.5 }] },
  tracks: [
    { name: 'pyro', inst: 'whoosh', params: { f0: 400, f1: 7000, peakAt: 0.25, up: true, q: 1.0 }, gain: -8, pan: -0.4, vel: 1,
      patterns: { intro: ['c3*6 - - - - - . . c3*6 - - - - - . .', null, null, null] } },
    { name: 'pyro2', inst: 'whoosh', params: { f0: 300, f1: 6000, peakAt: 0.3, up: true, q: 1.0 }, gain: -9, pan: 0.4, vel: 1,
      patterns: { intro: ['. . . . c3*6 - - - - - . . c3*6 - - -', null, null, null] } },
    { name: 'crowdpad', inst: 'murmurPad', params: { a: 0.8, r: 1.5, lp: 2800 }, gain: -22, send: 0.5,
      patterns: { intro: ['c3*64 - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -'] } },
    { name: 'kick', inst: 'kick', params: { start: 150, end: 46, decay: 0.42, drive: 2.2 }, gain: -3,
      patterns: { intro: [null, null, '. . . . . . . . . . . . x . x .', 'x . . . x . . . x . . . x x x x'], A: ['x . . . . . x . x . . . . . . .', 'x . . . . . x . x . . x . . x .'], B: ['x . . . x . . . x . . . x . . .', 'x . . . x . . . x . . x . . x .'] } },
    { name: 'snare', inst: 'snare', params: { tone: 190, decay: 0.2, noiseDecay: 0.3, snap: 1.2 }, gain: -5, pan: 0.05, send: 0.15,
      fx: [{ type: 'reverb', size: 0.55, damp: 0.4, mix: 0.4, predelay: 0.01, gate: 0.16 }],
      patterns: { intro: [null, null, null, 'r r r r r r r r r r r r r r r r'], A: ['. . . . x . . . . . . . x . . .', '. . . . x . . . . . . . x . . o'], B: ['. . . . x . . . . . . . x . . .', '. . . . x . . . . . . . x . r r'] } },
    { name: 'hat', inst: 'hat', params: { decay: 0.05 }, gain: -14, pan: 0.25, swing: 0.4,
      patterns: { A: ['x . x . x . x o x . x . x . x o'], B: ['x o x o x o x o x o x o x o x o'] } },
    { name: 'crash', inst: 'crash', params: { decay: 2.2 }, gain: -12, send: 0.3,
      patterns: { A: ['X . . . . . . . . . . . . . . .'], B: ['X . . . . . . . . . . . . . . .'] } },
    { name: 'bass', inst: 'subBass', params: { drive: 2, harm: 0.2, r: 0.06 }, gain: -6, gate: 0.8,
      fx: [{ type: 'sidechain', source: 'kick', amount: 0.35, release: 0.14 }],
      patterns: { A: [...bass(PROG_A), ...bass(PROG_A)], B: bass(PROG_B) } },
    { name: 'stabs', inst: 'fmBrass', params: { index: 3.4, feedback: 0.3, a: 0.012, d: 0.18, s: 0.6, r: 0.15, cutoff: 6000, drive: 1.6 }, gain: -8, pan: 0.1, send: 0.4, gate: 0.6,
      fx: [{ type: 'chorus', rate: 0.6, depth: 2.5, mix: 0.25 }],
      patterns: { intro: [null, null, null, H.stab(H.chord('d4', '7', 1), [8, 12, 14], ':9')], A: [...stabs(PROG_A), ...stabs(PROG_A)], B: stabs(PROG_B) } },
    { name: 'lowbrass', inst: 'fmBrass', params: { index: 2.4, feedback: 0.25, a: 0.02, d: 0.2, s: 0.8, r: 0.2, cutoff: 3000, drive: 1.5 }, gain: -11, pan: -0.1, send: 0.3, gate: 0.9,
      patterns: { A: H.fromProg([...PROG_A, ...PROG_A], (c, root) => H.bass(root, 'R - - - - - - - R - - - - - 5 -')), B: H.fromProg(PROG_B, (c, root) => H.bass(root, 'R - - - - - - - R - - - - - 5 -')) }, octave: 1 },
    { name: 'choir', inst: 'choirPad', params: { vowel: 'ah', a: 0.5, r: 1.0, voices: 5, detune: 11 }, gain: -15, send: 0.6, gate: 1,
      fx: [{ type: 'chorus', rate: 0.3, depth: 4, mix: 0.4 }],
      patterns: { A: [...choir(PROG_A), ...choir(PROG_A)], B: choir(PROG_B) } },
    { name: 'lead', inst: 'mutedTrumpet', params: { index: 1.6, formant: 1200, flat: -2, vib: 0.008, breath: 0.03 }, gain: -8, pan: 0.2, send: 0.4, gate: 0.9, humanize: 0.25,
      fx: [{ type: 'delay', time: '1/8d', feedback: 0.25, mix: 0.18, pingpong: true, damp: 3500 }],
      patterns: { A: MELODY_A } },
  ],
};
