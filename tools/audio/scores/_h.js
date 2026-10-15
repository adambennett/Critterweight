'use strict';
// Score helpers: chord spelling, step-grid bars and bass-line templates for tools/audio/scores.

const SEMI = { c: 0, d: 2, e: 4, f: 5, g: 7, a: 9, b: 11 };
const NAMES = ['c', 'c#', 'd', 'eb', 'e', 'f', 'f#', 'g', 'ab', 'a', 'bb', 'b'];
const CHORDS = {
  M: [0, 4, 7], m: [0, 3, 7], 7: [0, 4, 7, 10], m7: [0, 3, 7, 10], M7: [0, 4, 7, 11], dim: [0, 3, 6], dim7: [0, 3, 6, 9],
  sus4: [0, 5, 7], sus2: [0, 2, 7], m9: [0, 3, 7, 10, 14], '9': [0, 4, 7, 10, 14], add9: [0, 4, 7, 14], m6: [0, 3, 7, 9], '6': [0, 4, 7, 9],
  aug: [0, 4, 8], '5': [0, 7], m7b5: [0, 3, 6, 10], '7#9': [0, 4, 7, 10, 15],
};

function midi(tok) {
  const m = /^([a-g])([#b]?)(-?\d)$/.exec(tok.toLowerCase());
  if (!m) throw new Error('bad note ' + tok);
  return SEMI[m[1]] + (m[2] === '#' ? 1 : m[2] === 'b' ? -1 : 0) + (parseInt(m[3], 10) + 1) * 12;
}
function name(n) { return NAMES[((n % 12) + 12) % 12] + (Math.floor(n / 12) - 1); }
function tr(tok, semis) { return name(midi(tok) + semis); }

/** chord('f3','m') -> 'f3+ab3+c4'. inversion shifts the lowest notes up an octave. */
function chord(root, type = 'M', inversion = 0, drop = []) {
  const iv = CHORDS[type];
  if (!iv) throw new Error('chord type ' + type);
  const base = midi(root);
  let notes = iv.map((i) => base + i);
  for (let k = 0; k < inversion; k++) notes.push(notes.shift() + 12);
  notes = notes.filter((_, i) => !drop.includes(i));
  return notes.map(name).join('+');
}

/** bar({0:'c3', 8:'g3'}) -> 16-step string (rest elsewhere). steps may be overridden. */
function bar(map, steps = 16) {
  const out = new Array(steps).fill('.');
  for (const [k, v] of Object.entries(map)) out[parseInt(k, 10)] = v;
  return out.join(' ');
}

/** stab(chordToken, [0, 10], ':8') -> chord at those steps. */
function stab(tok, at, suffix = '') { const m = {}; for (const s of at) m[s] = tok + suffix; return bar(m); }

/** bass('d2', 'R . . R . . O . R . . . R . O .') : R root, O octave up, L octave down, 5 fifth, 7 flat seventh, 3 minor third, b2 flat second */
function bass(root, template) {
  const r = midi(root);
  return template.trim().split(/\s+/).map((t) => {
    const m = /^(R|O|L|5|7|3|M3|b6|6|4|2|b2)(.*)$/.exec(t);
    if (!m) return t;
    const off = { R: 0, O: 12, L: -12, 5: 7, 7: 10, 3: 3, M3: 4, b6: 8, 6: 9, 4: 5, 2: 2, b2: 1 }[m[1]];
    return name(r + off) + m[2];
  }).join(' ');
}

/** Builds a pattern array from a chord progression: prog = [[root, type, bars]...], fn(chordToken, root, type, barInChord) -> bar string */
function fromProg(prog, fn) {
  const out = [];
  for (const [root, type, bars] of prog) for (let b = 0; b < (bars || 1); b++) out.push(fn(chord(root, type), root, type, b));
  return out;
}

function rep(x, n) { const out = []; for (let i = 0; i < n; i++) out.push(x); return out; }
function flat(arrs) { return [].concat(...arrs); }

module.exports = { midi, name, tr, chord, bar, stab, bass, fromProg, rep, flat, CHORDS };
