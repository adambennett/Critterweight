'use strict';
// Track 1 — FIGHT NIGHT POSTER (main menu). 104 BPM, F minor. Big, brassy, slightly sleazy: the
// promo you don't trust. Intro 4 (foghorn + crowd) → A 16 (stabs, bass) → B 16 (muted-trumpet lead)
// → A' 16 (stabs + lead) → tag 4. Loop bars 5–56 (the intro plays once).
const H = require('./_h');

// 8-bar progressions (bars) — the A section runs it twice, B modulates to the relative major.
const PROG_A = [['f2', 'm', 2], ['db2', 'M', 1], ['eb2', 'M', 1], ['f2', 'm', 2], ['bb2', 'm', 1], ['c2', '7', 1]];
const PROG_B = [['ab2', 'M', 2], ['db2', 'M', 2], ['f2', 'm', 1], ['bb2', 'm', 1], ['c2', '7', 2]];
const PROG_TAG = [['f2', 'm', 1], ['db2', 'M', 1], ['c2', '7', 1], ['f2', 'm', 1]];

// brass stabs: "1" and the "3-and", sleazier on the turnaround bar
const stabs = (prog) => H.fromProg(prog, (c, root, type, b) => {
  const up = H.chord(H.tr(root, 12), type, 1);
  return type === '7' ? H.stab(up, [0, 6, 10, 12], ':9') : H.stab(up, [0, 10], ':8');
});
const bassA = (prog) => H.fromProg(prog, (c, root, type, b) => (b % 2 === 0
  ? H.bass(root, 'R . . . . . O . . . R . . . 5 .')
  : H.bass(root, 'R . . . R . O . . . R . L . 7 .')));
const bassB = (prog) => H.fromProg(prog, (c, root) => H.bass(root, 'R . . . . . . . R . . . O . 5 .'));
const pad = (prog) => H.fromProg(prog, (c, root, type) => H.stab(H.chord(H.tr(root, 12), type), [0], '*16'));

// the muted trumpet lead (B section, 16 bars) — a sleazy pentatonic swagger with blue notes
const LEAD_B = [
  'c5 . . . eb5 . f5 . . . eb5 . c5 . . .', 'ab4 - - - - - - - . . bb4 . c5 . . .',
  'c5 . . . eb5 . f5 . . . g5 . f5 . . .', 'eb5 - - - - - c5 . . . bb4 . ab4 - - -',
  'f4 . . . ab4 . bb4 . . . ab4 . f4 . . .', 'eb4 - - - - - - - . . f4 . ab4 . . .',
  'bb4 . . . c5 . eb5 . . . db5 . c5 . . .', 'bb4 - - - - - - - - - - - . . . .',
  'c5 . . . eb5 . f5 . . . eb5 . c5 . . .', 'ab4 - - - - - - - . . bb4 . c5 . . .',
  'f5 . . . eb5 . c5 . . . eb5 . f5 . . .', 'g5 - - - - - f5 . . . eb5 . c5 - - -',
  'ab4 . . . c5 . eb5 . . . f5 . eb5 . . .', 'c5 - - - - - - - . . bb4 . ab4 . . .',
  'g4 . . . bb4 . c5 . . . eb5 . c5 . . .', 'c5~ - - - - - - - - - - - . . . .',
];
// A' lead: answers the stabs with short licks (sparser than B)
const LEAD_A2 = [
  '. . . . c5 . eb5 . f5 . . . . . . .', '. . . . . . . . eb5 . c5 . ab4 - - -',
  '. . . . c5 . eb5 . f5 . g5 . . . . .', 'f5 - - - eb5 - - - c5 - - - . . . .',
  '. . . . f4 . ab4 . bb4 . . . . . . .', '. . . . . . . . ab4 . f4 . eb4 - - -',
  '. . . . bb4 . c5 . eb5 . . . db5 . c5 .', 'bb4 - - - - - - - - - - - . . . .',
  '. . . . c5 . eb5 . f5 . . . . . . .', '. . . . . . . . eb5 . c5 . ab4 - - -',
  '. . . . f5 . eb5 . c5 . . . . . . .', 'g5 - - - f5 - - - eb5 - - - c5 - - -',
  '. . . . ab4 . c5 . eb5 . . . . . . .', '. . . . . . . . c5 . bb4 . ab4 - - -',
  '. . . . g4 . bb4 . c5 . eb5 . . . . .', 'c5~ - - - - - - - - - - - - - - -',
];

module.exports = {
  id: 'fight_night_poster', title: 'Fight Night Poster', bpm: 104, sr: 44100, stereo: true, swing: 0.5, gain: -6, tags: ['menu'],
  sections: ['intro', 'A', 'B', 'A2', 'tag'], bars: { intro: 4, A: 16, B: 16, A2: 16, tag: 4 },
  loop: { startBar: 5, endBar: 56 },
  master: { lufs: -15, ceiling: -1, hp: 30, comp: { threshold: -15, ratio: 2.2, attack: 0.02, release: 0.2, knee: 6 }, reverb: { size: 0.62, damp: 0.45, predelay: 0.025, lowcut: 200, level: 0.9 }, eq: [{ f: 3200, q: 0.8, gain: 1.2 }] },
  tracks: [
    { name: 'foghorn', inst: 'foghorn', params: { a: 0.4, r: 0.8, cutoff: 380 }, gain: -9, pan: 0, send: 0.35,
      patterns: { intro: ['f1*12 - - - - - - - - - - - . . . .', '. . . . . . . . . . . . . . . .', 'c2*10 - - - - - - - - - . . . . . .', '. . . . . . . . . . . . . . . .'] } },
    { name: 'crowd', inst: 'murmurPad', params: { a: 1.2, r: 1.5, lp: 2600 }, gain: -24, pan: 0, send: 0.4,
      patterns: { intro: ['c3*64 - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -'], tag: ['c3*64 - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -', '- - - - - - - - - - - - - - - -'] } },
    { name: 'kick', inst: 'kick', params: { start: 150, end: 48, decay: 0.4, drive: 2 }, gain: -3, pan: 0,
      patterns: { intro: [null, null, null, '. . . . . . . . . . . . x . x .'], A: ['x . . . . . x . x . . . . . . .', 'x . . . . . x . x . . x . . . .'], B: ['x . . . . . x . x . . . . . . .', 'x . . . . . x . x . . x . . x .'], A2: ['x . . . . . x . x . . . . . . .', 'x . . . . . x . x . . x . . . .'], tag: ['x . . . . . x . x . . . . . . .', 'x . . . . . x . x . . x . . . .', 'x . . . . . x . x . . . . . . .', 'x . . . . . . . . . . . x . x x'] } },
    { name: 'snare', inst: 'snare', params: { tone: 185, decay: 0.2, noiseDecay: 0.3, snap: 1.1 }, gain: -5, pan: 0.05, send: 0.1,
      fx: [{ type: 'reverb', size: 0.55, damp: 0.4, mix: 0.4, predelay: 0.01, gate: 0.15 }],
      patterns: { intro: [null, null, null, '. . . . . . . . . . . . . . r .'], A: ['. . . . x . . . . . . . x . . .', '. . . . x . . . . . . . x . . o'], B: ['. . . . x . . . . . . . x . . .', '. . . . x . . . . . . . x . o .'], A2: ['. . . . x . . . . . . . x . . .', '. . . . x . . . . . . . x . . o'], tag: ['. . . . x . . . . . . . x . . .', '. . . . x . . . . . . . x . . o', '. . . . x . . . . . . . x . . .', '. . . . x . . . . . . . r r r r'] } },
    { name: 'hat', inst: 'hat', params: { decay: 0.05 }, gain: -14, pan: -0.25, swing: 0.55,
      patterns: { A: ['x . x . x . x o x . x . x . x o'], B: ['x . x . x . x o x . x . x . x o'], A2: ['x . x . x . x o x . x . x . x o'], tag: ['x . x . x . x o x . x . x . x o'] } },
    { name: 'hatopen', inst: 'hatOpen', params: { decay: 0.3 }, gain: -18, pan: 0.3, swing: 0.55,
      patterns: { A: ['. . . . . . . . . . . . . . x .'], B: ['. . . . . . . . . . x . . . . .'], A2: ['. . . . . . . . . . . . . . x .'] } },
    { name: 'bass', inst: 'subBass', params: { drive: 1.9, harm: 0.18, r: 0.07 }, gain: -6, pan: 0, gate: 0.8,
      fx: [{ type: 'sidechain', source: 'kick', amount: 0.35, release: 0.14 }],
      patterns: { A: [...bassA(PROG_A), ...bassA(PROG_A)], B: [...bassB(PROG_B), ...bassB(PROG_B)], A2: [...bassA(PROG_A), ...bassA(PROG_A)], tag: bassA(PROG_TAG) } },
    { name: 'stabs', inst: 'fmBrass', params: { index: 3.0, feedback: 0.3, a: 0.012, d: 0.16, s: 0.55, r: 0.12, cutoff: 5600, drive: 1.5 }, gain: -9, pan: 0.1, send: 0.35, gate: 0.55,
      fx: [{ type: 'chorus', rate: 0.6, depth: 2.5, mix: 0.25 }],
      patterns: { intro: [null, null, null, H.stab(H.chord('c4', '7', 1), [12, 14], ':9')], A: [...stabs(PROG_A), ...stabs(PROG_A)], B: [...stabs(PROG_B), ...stabs(PROG_B)], A2: [...stabs(PROG_A), ...stabs(PROG_A)], tag: stabs(PROG_TAG) } },
    { name: 'pad', inst: 'fmBrass', params: { index: 1.2, feedback: 0.15, a: 0.5, d: 0.3, s: 0.9, r: 0.6, cutoff: 2400, drive: 1.1 }, gain: -20, pan: -0.15, send: 0.5, gate: 1,
      patterns: { B: [...pad(PROG_B), ...pad(PROG_B)], tag: pad(PROG_TAG) } },
    { name: 'lead', inst: 'mutedTrumpet', params: { index: 1.5, formant: 1150, flat: -4, vib: 0.007, breath: 0.04 }, gain: -8, pan: 0.2, send: 0.4, gate: 0.9, humanize: 0.3,
      fx: [{ type: 'delay', time: '1/8d', feedback: 0.25, mix: 0.18, pingpong: true, damp: 3500 }],
      patterns: { B: LEAD_B, A2: LEAD_A2 } },
  ],
};
