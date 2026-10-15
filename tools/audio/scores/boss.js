'use strict';
// Track 5 — BOSS: HER HONOR. 132 BPM, C minor. Ominous pomp, then unhinged. Intro 8 (bell + pad) →
// A 16 (march) → B 16 (brass theme). Loop 9–40. The `p2` layer (screaming hard-sync lead + double-
// time hats) crossfades in on the phase-change cinematic; the boss-specific 2-bar layers (`bilge`
// wet toms, `conduit` 60 Hz buzz, `snappington` gavel on beat 1) are enabled per boss.
const H = require('./_h');

const PROG_A = [['c2', 'm', 2], ['ab2', 'M', 1], ['g2', '7', 1], ['c2', 'm', 2], ['f2', 'm', 1], ['g2', '7', 1]];
const PROG_B = [['c2', 'm', 1], ['eb2', 'M', 1], ['ab2', 'M', 1], ['g2', '7', 1], ['c2', 'm', 1], ['bb2', 'M', 1], ['ab2', 'M', 1], ['g2', '7', 1]];

const sub = (prog) => H.fromProg(prog, (c, root) => H.bass(root, 'R . . . R . . . R . . . R . . .'));
const subB = (prog) => H.fromProg(prog, (c, root) => H.bass(root, 'R . . . R . . . R . . . R . O .'));
const cluster = (prog) => H.fromProg(prog, (c, root, type) => H.stab(H.chord(root, type, 0) + '+' + H.tr(root, 13), [0], '*16'));
const padB = (prog) => H.fromProg(prog, (c, root, type) => H.stab(H.chord(H.tr(root, 12), type, 1), [0], '*16'));
const themeStabs = (prog) => H.fromProg(prog, (c, root, type) => H.stab(H.chord(H.tr(root, 12), type, 1), [0, 6, 10], ':8'));

// brass theme (B): a stately, slightly deranged march melody
const THEME = [
  'c5 - - - eb5 - - - g5 - - - - - - -', 'f5 - - - eb5 - - - d5 - - - . . . .',
  'ab4 - - - c5 - - - eb5 - - - - - - -', 'd5 - - - b4 - - - g4 - - - . . . .',
  'c5 - - - eb5 - - - g5 - - - - - - -', 'bb5 - - - ab5 - - - g5 - - - f5 - - -',
  'eb5 - - - c5 - - - ab4 - - - - - - -', 'g4 - - - - - - - b4 - - - d5 - - -',
  'c5 - - - eb5 - - - g5 - - - - - - -', 'f5 - - - eb5 - - - d5 - - - . . . .',
  'ab4 - - - c5 - - - eb5 - - - - - - -', 'd5 - - - b4 - - - g4 - - - . . . .',
  'c6 - - - bb5 - - - ab5 - - - g5 - - -', 'f5 - - - eb5 - - - d5 - - - eb5 - - -',
  'c5 - - - - - - - eb5 - - - d5 - - -', 'c5~ - - - - - - - - - - - - - - -',
];
// phase-2 screaming lead: frantic answers over A and B
const SCREAM_A = [
  'c5 . eb5 . g5 . c6 . bb5 . g5 . eb5 . c5 .', 'g5 - - - f5 . eb5 . d5 - - - . . . .',
  'ab4 . c5 . eb5 . ab5 . g5 . eb5 . c5 . ab4 .', 'g5 - - - - - - - b4 . d5 . g5 - - -',
  'c5 . eb5 . g5 . c6 . bb5 . g5 . eb5 . c5 .', 'g5 - - - f5 . eb5 . d5 - - - . . . .',
  'f5 . ab5 . c6 . f6 . eb6 . c6 . ab5 . f5 .', 'g5 - - - b5 - - - d6 - - - g6~ - - -',
];
const SCREAM_B = [
  'g5 - - - - - - - c6 . bb5 . ab5 . g5 .', 'f5 . g5 . ab5 . bb5 . c6 - - - - - - -',
  'eb6 - - - c6 - - - ab5 - - - c6 - - -', 'd6 - - - b5 - - - g5 - - - - - - -',
  'g5 - - - - - - - c6 . bb5 . ab5 . g5 .', 'bb5 . c6 . d6 . eb6 . f6 - - - - - - -',
  'eb6 - - - c6 - - - ab5 - - - eb5 - - -', 'g5 - - - b5 - - - d6 - - - g6~ - - -',
];

module.exports = {
  id: 'boss', title: 'Her Honor', bpm: 132, sr: 44100, stereo: true, gain: -8, tags: ['boss'],
  sections: ['intro', 'A', 'B'], bars: { intro: 8, A: 16, B: 16 },
  loop: { startBar: 9, endBar: 40 },
  layers: [
    { id: 'p2', tracks: ['scream', 'hat2'], mono: true, sr: 22050, defaultDb: -80, kind: 'phase' },
    { id: 'bilge', tracks: ['wettoms'], mono: true, sr: 44100, loopBars: 2, defaultDb: -80, kind: 'boss' },
    { id: 'conduit', tracks: ['buzz'], mono: true, sr: 44100, loopBars: 2, defaultDb: -80, kind: 'boss' },
    { id: 'snappington', tracks: ['gavel'], mono: true, sr: 44100, loopBars: 2, defaultDb: -80, kind: 'boss' },
  ],
  master: { lufs: -14.5, ceiling: -1, hp: 30, comp: { threshold: -14, ratio: 2.5, attack: 0.015, release: 0.18, knee: 6 }, reverb: { size: 0.72, damp: 0.4, predelay: 0.03, lowcut: 200, level: 1.0 }, eq: [{ f: 60, q: 1, gain: 1.2 }] },
  tracks: [
    { name: 'bell', inst: 'bell', params: { ratio: 3.5, index: 2.4, decay: 3.2, detune: 5 }, gain: -8, pan: -0.1, send: 0.5,
      patterns: { intro: ['c3 . . . . . . . . . . . . . . .', null, 'c3 . . . . . . . . . . . . . . .', null, 'c3 . . . . . . . . . . . . . . .', null, 'c3 . . . . . . . . g2 . . . . . .', null], B: [null, null, null, 'g3 . . . . . . . . . . . . . . .', null, null, null, 'g3 . . . . . . . . . . . . . . .'] } },
    { name: 'pad', inst: 'fmBrass', params: { index: 1.4, feedback: 0.2, a: 0.9, d: 0.5, s: 0.9, r: 1.2, cutoff: 1800, drive: 1.2, vib: 0.002 }, gain: -14, pan: 0, send: 0.6, gate: 1,
      patterns: { intro: [...cluster([['c2', 'm', 4], ['ab2', 'M', 2], ['g2', '7', 2]])], A: [...cluster(PROG_A), ...cluster(PROG_A)], B: [...padB(PROG_B), ...padB(PROG_B)] } },
    { name: 'snare', inst: 'snare', params: { tone: 210, decay: 0.16, noiseDecay: 0.22, snap: 1.3, body: 0.5 }, gain: -6, pan: 0.05, send: 0.25,
      patterns: { intro: [null, null, null, null, null, null, null, '. . . . . . . . r r r r r r r r'], A: ['x . . . x . r . x . . . x . r r', 'x . . . x . r . x . . . r r r r'], B: ['x . . . x . r . x . . . x . r r', 'x . . . x . r . x . . . r r r r'] } },
    { name: 'kick', inst: 'kick', params: { start: 150, end: 46, decay: 0.4, drive: 2.2 }, gain: -3,
      patterns: { A: ['x . . . x . . . x . . . x . . .'], B: ['x . . . x . . . x . . . x . . x'] } },
    { name: 'sub', inst: 'subBass', params: { drive: 2, harm: 0.15, d: 0.1, s: 0.8, r: 0.06 }, gain: -6, gate: 0.6,
      patterns: { A: [...sub(PROG_A), ...sub(PROG_A)], B: [...subB(PROG_B), ...subB(PROG_B)] } },
    { name: 'hat', inst: 'hat', params: { decay: 0.04 }, gain: -15, pan: 0.2,
      patterns: { A: ['x . x . x . x . x . x . x . x .'], B: ['x . x . x . x . x . x . x . x o'] } },
    { name: 'crash', inst: 'crash', params: { decay: 2 }, gain: -13, pan: 0.15, send: 0.3,
      patterns: { A: ['x . . . . . . . . . . . . . . .'], B: ['x . . . . . . . . . . . . . . .', null, null, null, null, null, null, null, 'x . . . . . . . . . . . . . . .'] } },
    { name: 'brass', inst: 'fmBrass', params: { index: 3.2, feedback: 0.3, a: 0.02, d: 0.2, s: 0.75, r: 0.18, cutoff: 5400, drive: 1.6 }, gain: -9, pan: 0.1, send: 0.4, gate: 0.92, humanize: 0.15,
      fx: [{ type: 'chorus', rate: 0.4, depth: 3, mix: 0.25 }],
      patterns: { B: THEME } },
    { name: 'stabs', inst: 'fmBrass', params: { index: 2.6, feedback: 0.25, a: 0.01, d: 0.12, s: 0.5, r: 0.1, cutoff: 4500, drive: 1.5 }, gain: -13, pan: -0.15, send: 0.35, gate: 0.5,
      patterns: { A: [...themeStabs(PROG_A), ...themeStabs(PROG_A)] } },
    { name: 'scream', inst: 'syncLead', params: { ratioLow: 1.7, ratioHigh: 3.6, sweep: 0.35, cutoff: 7500, vib: 0.01, drive: 1.8 }, gain: -10, send: 0.3, gate: 0.85, humanize: 0.2,
      fx: [{ type: 'delay', time: '1/8', feedback: 0.28, mix: 0.18, pingpong: true, damp: 4500 }],
      patterns: { A: [...SCREAM_A, ...SCREAM_A], B: [...SCREAM_B, ...SCREAM_B] } },
    { name: 'hat2', inst: 'hat', params: { decay: 0.03, hp: 9000 }, gain: -16,
      patterns: { A: ['x x x x x x x x x x x x x x x x'], B: ['x x x x x x x x x x x x x x x x'] } },
    { name: 'wettoms', inst: 'tom', params: { tune: 80, decay: 0.4, fm: 0.8, fmRatio: 1.5, wet: 0.9 }, gain: -10,
      patterns: { A: ['. . . . . . x . . . x . . . . .', '. . . . . . x . . . x . x . x .'] } },
    { name: 'buzz', inst: 'organ', params: { drawbars: [1, 0.9, 0.6, 0.4], lp: 1400, trem: 0.6, a: 0.02, r: 0.05 }, gain: -16,
      patterns: { A: ['c1*32 - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -'] } },
    { name: 'gavel', inst: 'gavel', params: { tone: 1150, decay: 0.1 }, gain: -8,
      patterns: { A: ['X . . . . . . . . . . . . . . .', 'X . . . . . . . . . . . . . . .'] } },
  ],
};
