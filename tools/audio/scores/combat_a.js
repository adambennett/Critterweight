'use strict';
// Track 3 — COMBAT A: UNDERCARD SCRAP. 128 BPM, D minor. Driving, cheeky, forward. A 16 (groove) →
// B 16 (lead) → A 16 → C 8 (breakdown: drums + crowd). Loop 1–56.
// Layers: `lead` (intensity layer, fades in when a fighter is below 50 % HP; also carries the B lead)
// and two 4-bar percussion overlays (`perc2`, `perc3`) chosen per match by seed.
const H = require('./_h');

const PROG_A = [['d2', 'm', 2], ['bb2', 'M', 1], ['c2', 'M', 1], ['d2', 'm', 2], ['g2', 'm', 1], ['a2', '7', 1]];
const PROG_B = [['d2', 'm', 1], ['f2', 'M', 1], ['bb2', 'M', 1], ['a2', '7', 1], ['g2', 'm', 1], ['d2', 'm', 1], ['bb2', 'M', 1], ['a2', '7', 1]];

// square bass with octave jumps
const bassA = (prog) => H.fromProg(prog, (c, root, type, b) => H.bass(root, b % 2 === 0
  ? 'R . R . O . R . R . O . R R . O'
  : 'R . R . O . R . 5 . O . R . 7 O'));
const bassB = (prog) => H.fromProg(prog, (c, root) => H.bass(root, 'R . . R . . O . R . . R . O . 5'));
// brass stabs on the 2 and the 4-and
const stabs = (prog) => H.fromProg(prog, (c, root, type) => H.stab(H.chord(H.tr(root, 12), type, 1), [4, 14], ':8'));
const stabsBusy = (prog) => H.fromProg(prog, (c, root, type) => H.stab(H.chord(H.tr(root, 12), type, 1), [4, 11, 14], ':8'));

const LEAD_B = [
  'd5 . . f5 . . a5 . g5 . f5 . e5 . . .', 'd5 - - - . . . . c5 . d5 . f5 . e5 .',
  'd5 . . f5 . . a5 . bb5 . a5 . g5 . . .', 'f5 - - - e5 - - - d5 - - - . . . .',
  'g5 . . bb5 . . d6 . c6 . bb5 . a5 . . .', 'g5 - - - . . . . f5 . g5 . a5 . g5 .',
  'f5 . . a5 . . c6 . bb5 . a5 . g5 . . .', 'a5 - - - - - - - g5 . f5 . e5 . . .',
  'd5 . . f5 . . a5 . g5 . f5 . e5 . . .', 'd5 - - - . . . . c5 . d5 . f5 . e5 .',
  'd5 . . f5 . . a5 . bb5 . a5 . g5 . . .', 'f5 - - - e5 - - - d5 - - - . . . .',
  'g5 . . bb5 . . d6 . c6 . bb5 . a5 . . .', 'bb5 - - - a5 - - - g5 - - - f5 . . .',
  'e5 . . g5 . . bb5 . a5 . g5 . f5 . . .', 'd5~ - - - - - - - - - - - . . . .',
];
const LEAD_A2 = [
  '. . . . . . . . d5 . f5 . a5 . . .', 'g5 - - - f5 . e5 . d5 - - - . . . .',
  '. . . . . . . . f5 . a5 . d6 . . .', 'c6 - - - bb5 . a5 . g5 - - - . . . .',
  '. . . . . . . . d5 . f5 . a5 . . .', 'g5 - - - f5 . e5 . d5 - - - . . . .',
  '. . . . bb4 . d5 . f5 . . . g5 . . .', 'a5 - - - - - - - cs5 . d5 . e5 . . .',
  '. . . . . . . . d5 . f5 . a5 . . .', 'g5 - - - f5 . e5 . d5 - - - . . . .',
  '. . . . . . . . f5 . a5 . d6 . . .', 'c6 - - - bb5 . a5 . g5 - - - . . . .',
  '. . . . d5 . f5 . a5 . . . g5 . . .', 'f5 - - - e5 - - - d5 - - - . . . .',
  '. . . . g5 . bb5 . d6 . . . c6 . . .', 'a5~ - - - - - - - - - - - . . . .',
].map((s) => s.replace('cs5', 'c#5'));

module.exports = {
  id: 'combat_a', title: 'Undercard Scrap', bpm: 128, sr: 44100, stereo: true, gain: -8, tags: ['combat'],
  sections: ['A', 'B', 'A2', 'C'], bars: { A: 16, B: 16, A2: 16, C: 8 },
  loop: { startBar: 1, endBar: 56 },
  layers: [
    { id: 'lead', tracks: ['lead'], mono: true, sr: 22050, defaultDb: -80, kind: 'intensity' },
    { id: 'perc2', tracks: ['perc2'], mono: true, sr: 44100, loopBars: 4, defaultDb: -80, kind: 'variant' },
    { id: 'perc3', tracks: ['perc3'], mono: true, sr: 44100, loopBars: 4, defaultDb: -80, kind: 'variant' },
  ],
  master: { lufs: -14.5, ceiling: -1, hp: 32, comp: { threshold: -14, ratio: 2.5, attack: 0.015, release: 0.16, knee: 6 }, reverb: { size: 0.5, damp: 0.5, predelay: 0.02, lowcut: 220, level: 0.8 }, eq: [{ f: 90, q: 1, gain: 1 }, { f: 2800, q: 0.9, gain: 1 }] },
  tracks: [
    { name: 'kick', inst: 'kick', params: { start: 170, end: 44, sweep: 0.04, decay: 0.38, drive: 2.2, click: 0.6 }, gain: -2.5,
      patterns: { A: ['x . . . x . . . x . . . x . . .', 'x . . . x . . . x . . x . . x .'], B: ['x . . . x . . . x . . . x . . .', 'x . . . x . . . x . . x . . . .'], A2: ['x . . . x . . . x . . . x . . .', 'x . . . x . . . x . . x . . x .'], C: ['x . . . . . x . . . x . . . . .', 'x . . . . . x . . . x . . x . .'] } },
    { name: 'snare', inst: 'snare', params: { tone: 200, decay: 0.2, noiseDecay: 0.24, snap: 1.2, body: 0.7 }, gain: -5, pan: 0.04, send: 0.12,
      fx: [{ type: 'reverb', size: 0.45, damp: 0.5, mix: 0.3, predelay: 0.008, gate: 0.12 }],
      patterns: { A: ['. . . . x . . . . . . . x . . .', '. . . . x . . . . . . . x . . o'], B: ['. . . . x . . . . . . . x . . .', '. . . . x . . o . . . . x . . .'], A2: ['. . . . x . . . . . . . x . . .', '. . . . x . . . . . . . x . o o'], C: ['. . . . x . . . . . . . x . . .', '. . . . x . . . . . . . x . r .'] } },
    { name: 'clap', inst: 'clap', gain: -12, pan: -0.1, send: 0.15, patterns: { B: ['. . . . x . . . . . . . x . . .'], C: ['. . . . x . . . . . . . x . . .'] } },
    { name: 'hat', inst: 'hat', params: { decay: 0.045, hp: 7500 }, gain: -13, pan: 0.2,
      patterns: { A: ['x o x o x o x o x o x o x o x o'], B: ['x o x o x o x o x o x o x o x X'], A2: ['x o x o x o x o x o x o x o x o'], C: ['x o x o x o x o x o x o x o x o'] } },
    { name: 'hatopen', inst: 'hatOpen', params: { decay: 0.28 }, gain: -17, pan: -0.3,
      patterns: { A: ['. . . . . . o . . . . . . . x .'], B: ['. . o . . . . . . . o . . . . .'], A2: ['. . . . . . o . . . . . . . x .'] } },
    { name: 'bass', inst: 'squareBass', params: { pw: 0.5, cutoff: 2800, floor: 240, q: 1.4, sub: 0.5, drive: 1.6, d: 0.12, s: 0.5 }, gain: -7, gate: 0.6,
      fx: [{ type: 'sidechain', source: 'kick', amount: 0.4, release: 0.12 }],
      patterns: { A: [...bassA(PROG_A), ...bassA(PROG_A)], B: [...bassB(PROG_B), ...bassB(PROG_B)], A2: [...bassA(PROG_A), ...bassA(PROG_A)] } },
    { name: 'stabs', inst: 'fmBrass', params: { index: 2.8, feedback: 0.28, a: 0.01, d: 0.14, s: 0.5, r: 0.1, cutoff: 6000, drive: 1.5 }, gain: -10, pan: 0.12, send: 0.3, gate: 0.5,
      fx: [{ type: 'chorus', rate: 0.7, depth: 2, mix: 0.2 }],
      patterns: { A: [...stabs(PROG_A), ...stabs(PROG_A)], B: [...stabs(PROG_B), ...stabs(PROG_B)], A2: [...stabsBusy(PROG_A), ...stabsBusy(PROG_A)] } },
    { name: 'crowdpad', inst: 'murmurPad', params: { a: 1.0, r: 1.5, lp: 2200 }, gain: -26, send: 0.4,
      patterns: { C: ['c3*128 - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -'] } },
    { name: 'riser', inst: 'whoosh', params: { f0: 200, f1: 5000, peakAt: 0.9 }, gain: -14, vel: 1,
      patterns: { C: [null, null, null, null, null, null, 'c3*32 - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -'] } },
    { name: 'lead', inst: 'sawLead', params: { voices: 5, detune: 15, cutoff: 6500, floor: 1000, vib: 0.007 }, gain: -10, send: 0.3, gate: 0.9, humanize: 0.2,
      fx: [{ type: 'delay', time: '1/8d', feedback: 0.3, mix: 0.2, pingpong: true, damp: 4000 }],
      patterns: { B: LEAD_B, A2: LEAD_A2 } },
    { name: 'perc2', inst: 'tom', params: { tune: 120, decay: 0.28, fm: 1.5, fmRatio: 1.4 }, gain: -12,
      patterns: { A: ['. . . . . . . . . . x . x . . .', '. . . . . . . . . . . . . . x x', '. . . . . . . . . . x . x . . .', '. . x . . . . . . . x x . x . x'] } },
    { name: 'perc3', inst: 'shaker', params: { decay: 0.08, hp: 6500 }, gain: -15,
      patterns: { A: ['. . x . . . x . . . x . . . x x', '. . x . . . x . . . x . . . x .', '. . x . . . x . . . x . . . x x', '. . x . . . x . x . x . . x . .'] } },
  ],
};
