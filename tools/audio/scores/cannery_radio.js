'use strict';
// Track 2 — CANNERY RADIO (hub). 92 BPM, B♭ major. Lazy, warm, a radio in another room; diegetic,
// so it is rendered mono at 22.05 kHz and the game EQs it per room. A 16 → B 16 (whistled lead) →
// A 16 → C 8 (bridge). Loop bars 1–56.
const H = require('./_h');

const PROG_A = [['bb2', 'M7', 2], ['g2', 'm7', 2], ['eb2', 'M7', 2], ['f2', '7', 2]];
const PROG_C = [['eb2', 'M7', 1], ['eb2', 'm6', 1], ['bb2', 'M7', 1], ['g2', '7', 1], ['c2', 'm7', 1], ['f2', '7', 1], ['bb2', 'M7', 1], ['f2', '7', 1]];

const keys = (prog) => H.fromProg(prog, (c, root, type, b) => {
  const voicing = H.chord(H.tr(root, 12), type, 1);
  return b === 0 ? H.stab(voicing, [0, 10], '*5') : H.stab(voicing, [2, 8, 12], '*3');
});
const bassLine = (prog) => H.fromProg(prog, (c, root, type, b) => (b === 0
  ? H.bass(root, 'R . . . . . . . 5 . . . . . 7 .')
  : H.bass(root, 'R . . . . . 3 . 5 . . . O . . .')));
const guitar = (prog) => H.fromProg(prog, (c, root, type) => {
  const v = H.chord(H.tr(root, 12), type, 2);
  return H.stab(v, [4, 11, 14], ':6');
});

const WHISTLE_B = [
  '. . . . d5 . f5 . g5 - - - . . . .', 'f5 . d5 . bb4 - - - - - - - . . . .',
  '. . . . bb4 . d5 . f5 - - - . . g5 .', 'f5 - - - - - - - d5 - - - . . . .',
  '. . . . g4 . bb4 . d5 - - - . . . .', 'c5 . bb4 . g4 - - - - - - - . . . .',
  '. . . . a4 . c5 . eb5 - - - . . f5 .', 'eb5 - - - d5 - - - c5 - - - . . . .',
  '. . . . d5 . f5 . g5 - - - . . . .', 'f5 . d5 . bb4 - - - - - - - . . . .',
  '. . . . bb4 . d5 . f5 - - - . . g5 .', 'a5 - - - - - - - f5 - - - . . . .',
  '. . . . g5 . f5 . d5 - - - . . . .', 'c5 . bb4 . d5 - - - - - - - . . . .',
  '. . . . c5 . d5 . f5 - - - eb5 . . .', 'd5~ - - - - - - - - - - - . . . .',
];

module.exports = {
  id: 'cannery_radio', title: 'Cannery Radio', bpm: 92, sr: 22050, stereo: false, swing: 0.6, gain: -12, tags: ['hub', 'diegetic'],
  sections: ['A', 'B', 'A2', 'C'], bars: { A: 16, B: 16, A2: 16, C: 8 },
  loop: { startBar: 1, endBar: 56 },
  master: { lufs: -14.5, ceiling: -1, hp: 60, comp: { threshold: -18, ratio: 2.5, attack: 0.03, release: 0.25, knee: 8 }, reverb: { size: 0.4, damp: 0.6, predelay: 0.015, lowcut: 250, level: 0.6 }, eq: [{ f: 180, q: 0.8, gain: 1.5 }, { f: 4200, q: 0.9, gain: -3 }] },
  tracks: [
    { name: 'crackle', inst: 'crackle', params: { density: 45, hiss: 0.04, lp: 6000 }, gain: -22, vel: 1, gate: 1,
      patterns: { A: ['c3*896 - - - - - - - - - - - - - - -'] } },
    { name: 'kick', inst: 'kick', params: { start: 120, end: 52, decay: 0.3, drive: 1.3, click: 0.2 }, gain: -8,
      patterns: { A: ['x . . . . . . x . . x . . . . .', 'x . . . . . . x . . x . . . x .'], B: ['x . . . . . . x . . x . . . . .'], A2: ['x . . . . . . x . . x . . . . .', 'x . . . . . . x . . x . . . x .'], C: ['x . . . . . . x . . x . . . . .'] } },
    { name: 'brush', inst: 'shaker', params: { decay: 0.12, hp: 3500 }, gain: -16, swing: 0.6,
      patterns: { '*': ['o . o . x . o . o . o . x . o .'] } },
    { name: 'snare', inst: 'snare', params: { tone: 170, decay: 0.12, noiseDecay: 0.16, snap: 0.6, body: 0.4 }, gain: -12,
      fx: [{ type: 'lp', f: 5000 }],
      patterns: { A: ['. . . . x . . . . . . . x . . .'], B: ['. . . . x . . . . . . . x . . .'], A2: ['. . . . x . . . . . . . x . . .'], C: ['. . . . x . . . . . . . x . . o'] } },
    { name: 'bass', inst: 'squareBass', params: { pw: 0.5, cutoff: 900, floor: 180, q: 0.9, sub: 0.6, drive: 1.3, d: 0.3, s: 0.7, fenv: 0.35 }, gain: -8, gate: 0.75,
      fx: [{ type: 'filterLfo', f: 420, depth: 0.5, rate: 0.08, q: 0.9 }],
      patterns: { A: [...bassLine(PROG_A), ...bassLine(PROG_A)], B: [...bassLine(PROG_A), ...bassLine(PROG_A)], A2: [...bassLine(PROG_A), ...bassLine(PROG_A)], C: bassLine(PROG_C) } },
    { name: 'keys', inst: 'epiano', params: { cutoff: 2600, trem: 4.4, tremDepth: 0.25, decay: 1.4 }, gain: -10, send: 0.3, humanize: 0.25,
      patterns: { A: [...keys(PROG_A), ...keys(PROG_A)], B: [...keys(PROG_A), ...keys(PROG_A)], A2: [...keys(PROG_A), ...keys(PROG_A)], C: keys(PROG_C) } },
    { name: 'guitar', inst: 'pluck', params: { decay: 0.9, damp: 0.45, bright: 0.5 }, gain: -14, send: 0.25, humanize: 0.3,
      patterns: { A2: [...guitar(PROG_A), ...guitar(PROG_A)], C: guitar(PROG_C) } },
    { name: 'whistle', inst: 'whistle', params: { vib: 0.014, vibRate: 5.2, breath: 0.1 }, gain: -12, send: 0.35, gate: 0.95, humanize: 0.35,
      fx: [{ type: 'delay', time: '1/4', feedback: 0.2, mix: 0.12, damp: 2500 }],
      patterns: { B: WHISTLE_B } },
    { name: 'organ', inst: 'organ', params: { drawbars: [1, 0.5, 0.25], lp: 1800, trem: 0.3, a: 0.08, r: 0.2 }, gain: -18, send: 0.4,
      patterns: { C: H.fromProg(PROG_C, (c, root, type) => H.stab(H.chord(H.tr(root, 24), type), [0], '*14')) } },
  ],
};
