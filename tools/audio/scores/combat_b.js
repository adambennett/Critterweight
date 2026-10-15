'use strict';
// Track 4 — COMBAT B: MAIN CARD HEAT. 128 BPM, A minor. Heavier and more chaotic: the kit gains an
// FM tom roll, the bass is a reese, stabs sit an octave lower and a chip-arpeggio counter-lead
// answers them. A 16 → B 16 (half-time) → A' 16 → D 8 (double-time build). Loop 1–56. The mixer
// jumps to the nearest B bar for 8 bars after a JUICE activation.
const H = require('./_h');

const PROG_A = [['a2', 'm', 2], ['f2', 'M', 1], ['g2', 'M', 1], ['a2', 'm', 2], ['d2', 'm', 1], ['e2', '7', 1]];
const PROG_B = [['a2', 'm', 2], ['c2', 'M', 2], ['f2', 'M', 2], ['e2', '7', 2]];
const PROG_D = [['e2', '7', 8]];

const reese = (prog) => H.fromProg(prog, (c, root, type, b) => H.bass(root, b % 2 === 0
  ? 'R - - - - - - - R - - - . . O .'
  : 'R - - - - - - - R - - 7 - - 5 .'));
const reeseHalf = (prog) => H.fromProg(prog, (c, root, type, b) => H.bass(root, 'R - - - - - - - - - - - R . . .'));
const stabsLow = (prog) => H.fromProg(prog, (c, root, type) => H.stab(H.chord(root, type, 0), [4, 14], ':8'));
const stabsHalf = (prog) => H.fromProg(prog, (c, root, type, b) => H.stab(H.chord(root, type, 0), b === 0 ? [0] : [8, 12], ':9'));
const arp = (prog) => H.fromProg(prog, (c, root, type) => {
  const n = c.split('+');
  const seq = [n[0], n[1], n[2], n[1], n[0], n[2], n[1], n[2]].map((x) => H.tr(x, 24));
  return seq.map((x, i) => `${x}${i % 4 === 0 ? ':8' : ':6'} .`).join(' ');
});
const DRUM_A = ['x . . . x . . . x . . . x . . .', 'x . . . x . . x . . x . x . . .'];
const SNARE_A = ['. . . . x . . . . . . . x . . .', '. . . . x . . . . . . . x . o .'];

module.exports = {
  id: 'combat_b', title: 'Main Card Heat', bpm: 128, sr: 44100, stereo: true, gain: -8, tags: ['combat'],
  sections: ['A', 'B', 'A2', 'D'], bars: { A: 16, B: 16, A2: 16, D: 8 },
  loop: { startBar: 1, endBar: 56 },
  layers: [
    { id: 'arp', tracks: ['arp'], mono: true, sr: 22050, defaultDb: 0, kind: 'lead' },
    { id: 'perc2', tracks: ['perc2'], mono: true, sr: 44100, loopBars: 4, defaultDb: -80, kind: 'variant' },
    { id: 'perc3', tracks: ['perc3'], mono: true, sr: 44100, loopBars: 4, defaultDb: -80, kind: 'variant' },
  ],
  master: { lufs: -14.5, ceiling: -1, hp: 32, comp: { threshold: -13, ratio: 2.8, attack: 0.012, release: 0.15, knee: 6 }, reverb: { size: 0.58, damp: 0.5, predelay: 0.02, lowcut: 220, level: 0.8 }, eq: [{ f: 70, q: 1, gain: 1.5 }, { f: 3500, q: 0.9, gain: 0.8 }] },
  tracks: [
    { name: 'kick', inst: 'kick', params: { start: 180, end: 42, sweep: 0.045, decay: 0.42, drive: 2.5, click: 0.7 }, gain: -2,
      patterns: { A: DRUM_A, B: ['x . . . . . . . . . x . . . . .', 'x . . . . . . x . . x . . . . .'], A2: DRUM_A, D: ['x . . . x . . . x . . . x . . .', 'x . x . x . x . x . x . x . x .'] } },
    { name: 'snare', inst: 'snare', params: { tone: 190, decay: 0.22, noiseDecay: 0.28, snap: 1.3, body: 0.8 }, gain: -4.5, pan: 0.04, send: 0.15,
      fx: [{ type: 'reverb', size: 0.5, damp: 0.45, mix: 0.32, predelay: 0.008, gate: 0.14 }],
      patterns: { A: SNARE_A, B: ['. . . . . . . . x . . . . . . .', '. . . . . . . . x . . . . . o .'], A2: SNARE_A, D: ['. . . . x . . . . . . . x . . .', '. . . . x . . . . . . . x . . .', '. . . . x . . . . . . . x . . .', '. . . . x . . . . . . . x . x .', '. . . . x . . . x . . . x . . .', '. . x . x . . . x . . . x . x .', 'x . x . x . x . x . x . x . x .', 'r r r r r r r r r r r r r r r r'] } },
    { name: 'toms', inst: 'tom', params: { tune: 95, decay: 0.3, fm: 2.2, fmRatio: 1.4 }, gain: -9, pan: -0.2, send: 0.1,
      patterns: { A: [null, null, null, '. . . . . . . . . . . . x x . x', null, null, null, '. . . . . . . . x . x x . x x x'], B: ['. . . . . . . . . . . . . . x x'], A2: [null, null, null, '. . . . . . . . . . . . x x . x', null, null, null, '. . . . . . . . x . x x . x x x'], D: [null, null, null, '. . . . . . . . r r r r x x x x', null, null, 'x . x . x . x . x x x x r r r r', 'r r r r r r r r r r r r r r r r'] } },
    { name: 'hat', inst: 'hat', params: { decay: 0.04, hp: 8000 }, gain: -13, pan: 0.2,
      patterns: { A: ['x o x o x o x o x o x o x o x o'], B: ['x . . . x . . . x . . . x . . o'], A2: ['x o x o x o x o x o x o x o x o'], D: ['x o x o x o x o x o x o x o x o', 'x x x x x x x x x x x x x x x x'] } },
    { name: 'hatopen', inst: 'hatOpen', params: { decay: 0.3 }, gain: -17, pan: -0.3,
      patterns: { A: ['. . . . . . o . . . . . . . x .'], A2: ['. . o . . . . . . . o . . . . .'], D: ['. . . . . . . . . . . . . . x .'] } },
    { name: 'crash', inst: 'crash', params: { decay: 1.6 }, gain: -14, pan: 0.1, send: 0.2,
      patterns: { A: ['x . . . . . . . . . . . . . . .', null, null, null, null, null, null, null, 'x . . . . . . . . . . . . . . .'], B: ['x . . . . . . . . . . . . . . .'], A2: ['x . . . . . . . . . . . . . . .'] } },
    { name: 'bass', inst: 'reeseBass', params: { detune: 38, cutoff: 700, q: 1.0, sub: 0.55, drive: 1.7 }, gain: -6.5, gate: 0.95,
      fx: [{ type: 'sidechain', source: 'kick', amount: 0.45, release: 0.13 }],
      patterns: { A: [...reese(PROG_A), ...reese(PROG_A)], B: [...reeseHalf(PROG_B), ...reeseHalf(PROG_B)], A2: [...reese(PROG_A), ...reese(PROG_A)], D: reese(PROG_D) } },
    { name: 'stabs', inst: 'fmBrass', params: { index: 3.2, feedback: 0.3, a: 0.01, d: 0.16, s: 0.5, r: 0.12, cutoff: 4800, drive: 1.7 }, gain: -9, pan: -0.1, send: 0.3, gate: 0.5,
      fx: [{ type: 'chorus', rate: 0.5, depth: 2.5, mix: 0.2 }],
      patterns: { A: [...stabsLow(PROG_A), ...stabsLow(PROG_A)], B: [...stabsHalf(PROG_B), ...stabsHalf(PROG_B)], A2: [...stabsLow(PROG_A), ...stabsLow(PROG_A)],
        D: H.fromProg(PROG_D, (c, root, type, b) => H.stab(H.chord(H.tr(root, 12 * (b >= 4 ? 2 : 1)), type, 1), b >= 6 ? [0, 4, 8, 12] : [4, 14], ':9')) } },
    { name: 'arp', inst: 'pulseArp', params: { pw: 0.25, d: 0.14, cutoff: 5000 }, gain: -13, send: 0.25, gate: 0.6,
      fx: [{ type: 'delay', time: '1/16', feedback: 0.25, mix: 0.2, damp: 5000 }],
      patterns: { A: [null, null, null, null, null, null, null, null, ...arp(PROG_A)], B: [...arp(PROG_B), ...arp(PROG_B)], A2: [...arp(PROG_A), ...arp(PROG_A)], D: arp(PROG_D) } },
    { name: 'riser', inst: 'whoosh', params: { f0: 150, f1: 6000, peakAt: 0.92 }, gain: -12, vel: 1,
      patterns: { D: [null, null, null, null, 'c3*64 - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -'] } },
    { name: 'perc2', inst: 'clap', gain: -11,
      patterns: { A: ['. . . . x . . . . . . . x . . .', '. . . . x . . . . . . . x . . x', '. . . . x . . . . . . . x . . .', '. . . . x . . x . . . . x . x .'] } },
    { name: 'perc3', inst: 'rim', params: { tone: 480 }, gain: -12,
      patterns: { A: ['. . . x . . x . . . x . . x . .', '. . . x . . x . . . x . . . x .', '. . . x . . x . . . x . . x . .', '. . . x . . x . x . x . x . . x'] } },
  ],
};
