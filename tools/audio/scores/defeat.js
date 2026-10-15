'use strict';
// Track 7 — DEFEAT STING: CUT MAN. 70 BPM, F minor, 4 bars, non-looping. Deflated, affectionate:
// a solo muted trumpet (slightly flat), one sub-bass note, a sad slide-whistle grain and a distant
// choir "aww" (the crowd system adds the real crowd).
module.exports = {
  id: 'defeat', title: 'Cut Man', bpm: 70, sr: 44100, stereo: true, gain: -6, tags: ['sting', 'loss'], stinger: true, tail: 4,
  sections: ['A'], bars: { A: 4 },
  loop: null,
  master: { lufs: -17, ceiling: -1, hp: 30, comp: null, reverb: { size: 0.75, damp: 0.5, predelay: 0.04, lowcut: 200, level: 1.0 } },
  tracks: [
    { name: 'trumpet', inst: 'mutedTrumpet', params: { index: 1.3, flat: -14, vib: 0.01, vibRate: 4.6, breath: 0.06, a: 0.06, r: 0.3 }, gain: -8, pan: 0.1, send: 0.55, gate: 0.92, humanize: 0.35,
      patterns: { A: ['. . ab4 . g4 . f4 - - - . . eb4 . db4 .', 'c4 - - - - - - - . . . . . . . .', '. . f4 . eb4 . db4 - - - c4 - - - bb3 .', 'ab3~ - - - - - - - - - - - - - - -'] } },
    { name: 'sub', inst: 'subBass', params: { drive: 1.5, a: 0.02, r: 1.2, s: 0.95 }, gain: -9, gate: 1,
      patterns: { A: [null, null, null, 'f1*14 - - - - - - - - - - - - - . .'] } },
    { name: 'slide', inst: 'whistle', params: { vib: 0.02, vibRate: 5.5, breath: 0.12, a: 0.08, r: 0.4 }, gain: -16, pan: -0.3, send: 0.6, gate: 0.95,
      patterns: { A: [null, 'c6 . . . . . . . . . . . . . . .', 'ab5~ . . . . . . . . . . . . . . .', 'f4~ - - - - - - - . . . . . . . .'] } },
    { name: 'choir', inst: 'choirPad', params: { vowel: 'oh', a: 0.5, r: 1.5, voices: 4, detune: 8, lp: 2500 }, gain: -20, send: 0.7, gate: 1,
      patterns: { A: [null, null, 'f3+ab3+c4*20 - - - - - - - - - - - - - - -', '- - - - . . . . . . . . . . . .'] } },
    { name: 'kick', inst: 'kick', params: { start: 100, end: 40, decay: 0.5, drive: 1.3, click: 0.1 }, gain: -8,
      patterns: { A: [null, null, null, 'x . . . . . . . . . . . . . . .'] } },
  ],
};
