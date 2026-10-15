'use strict';
// Announcer / coach "babble" voices (docs/design/ANNOUNCER_AND_TUTORIAL.md §1, §2).
// Offline part: a bank of short formant grains per character (vowel honks, consonant clicks,
// hisses, hums, a two-syllable name fanfare, Granny's rising "eh?"). The runtime assembler lives
// in game/src/audio/babble.gd; `plan()` below is the reference implementation of the same
// algorithm, used by `node tools/audio/build.js --say "..."` to audition lines as WAV.

const D = require('./dsp');
const K = require('./sfxkit');
const { zeros, secs } = D;

const VOWEL_FORMANTS = {
  a: [[730, 1090, 2440], [1.0, 0.6, 0.2]],
  e: [[530, 1840, 2480], [1.0, 0.55, 0.25]],
  i: [[290, 2200, 2900], [0.8, 0.5, 0.3]],
  o: [[570, 840, 2410], [1.0, 0.5, 0.15]],
  u: [[320, 870, 2240], [1.0, 0.35, 0.1]],
};

const CHARACTERS = {
  barnaby: {
    speaker: 'barnaby', f0: 150, rate: 11, pouch: 460, honk: 1.9, brightness: 1.0, nasal: 0.15, jitter: 0.025, growl: 0.12,
    grainMs: [70, 105], consMs: 32, contour: 'auction', capsGain: 1.4, capsPitch: 1.3, fanfare: true, breath: 0.08,
  },
  granny: {
    speaker: 'granny', f0: 128, rate: 7, pouch: 260, honk: 1.1, brightness: 0.75, nasal: 0.45, jitter: 0.045, growl: 0.0,
    grainMs: [100, 135], consMs: 40, contour: 'flat', capsGain: 1.0, capsPitch: 1.08, fanfare: false, breath: 0.14, creak: 0.3,
  },
};

/** One vowel grain: glottal pulse -> honk resonance + 3 formants, windowed. */
function vowelGrain(sr, rng, ch, vowel, ms, variant = 0, pitchMul = 1, contour = 0) {
  const [fs, gs] = VOWEL_FORMANTS[vowel];
  const n = secs(sr, ms / 1000);
  const src = new D.Osc(sr, 'pulse');
  const nz = new D.Noise(rng);
  const bands = fs.map((f, k) => new D.SVF(sr, f * (1 + (variant ? 0.04 : 0)), 7 - k));
  const pouch = new D.SVF(sr, ch.pouch, 5);
  const nasal = new D.SVF(sr, 250, 4);
  const lp = new D.SVF(sr, 5200 * ch.brightness, 0.7);
  const hp = new D.OnePole(sr, 90);
  const growl = new D.Lfo(sr, 'sine', rng.float());
  const out = zeros(n);
  let jit = 0, last = 0;
  const creak = ch.creak || 0;
  for (let i = 0; i < n; i++) {
    const k = i / n;
    if (src.phase < last) jit = rng.range(-ch.jitter, ch.jitter) * (1 + creak * (rng.float() < 0.3 ? 3 : 0));
    last = src.phase;
    const f = ch.f0 * pitchMul * (1 + jit) * (1 + contour * (k - 0.5) * 0.3) * (1 + 0.02 * Math.sin(i / sr * 2 * Math.PI * 6.5));
    const x = src.next(f, 0.14) * (1 - ch.breath) + nz.next() * ch.breath;
    let y = 0;
    for (let b = 0; b < 3; b++) y += bands[b].bp(x) * gs[b];
    y += pouch.bp(x) * ch.honk * 0.6 + nasal.bp(x) * ch.nasal;
    const g = 1 - ch.growl * 0.5 * (1 + growl.next(28));
    y = Math.tanh(lp.lp(hp.hp(y)) * 2.2 * g);
    // window: 8 ms attack, 25 ms release
    const na = secs(sr, 0.008), nr = secs(sr, 0.025);
    const w = i < na ? i / na : i > n - nr ? (n - i) / nr : 1;
    out[i] = y * w;
  }
  return out;
}

function consonantGrain(sr, rng, ch, cls, variant = 0) {
  const ms = ch.consMs * (variant ? 1.15 : 1);
  switch (cls) {
    case 'plosive': { // click + tiny voiced onset
      const b = K.burst(sr, rng, { dur: 0.012, filt: [{ type: 'hp', f: 1500 }, { type: 'bp', f: 2600, q: 1.2 }], curve: 2.5 });
      const v = vowelGrain(sr, rng, ch, 'u', ms * 0.6, variant, 0.9);
      return K.mix(sr, [{ buf: b, gain: -2 }, { buf: v, gain: -10, at: 0.006 }]);
    }
    case 'sibilant': return K.burst(sr, rng, { dur: ms / 1000 * 1.8, filt: [{ type: 'bp', f: 5200, q: 1.0 }, { type: 'hp', f: 3000 }], a: 0.01, curve: 1.2, gain: 0.7 });
    case 'sh': return K.burst(sr, rng, { dur: ms / 1000 * 1.6, filt: [{ type: 'bp', f: 3000, q: 1.2 }, { type: 'hp', f: 1800 }], a: 0.012, curve: 1.2, gain: 0.8 });
    case 'fric': return K.burst(sr, rng, { dur: ms / 1000 * 1.3, filt: [{ type: 'bp', f: 1800, q: 0.7 }], a: 0.01, curve: 1.4, gain: 0.55 });
    case 'nasal': { // hum
      const v = vowelGrain(sr, rng, ch, 'u', ms * 1.6, variant, 0.95);
      return K.filterChain(v, sr, [{ type: 'lp', f: 700 }]);
    }
    case 'liquid': return vowelGrain(sr, rng, ch, 'o', ms * 1.3, variant, 1.0, -0.4);
    default: return K.burst(sr, rng, { dur: 0.01, filt: [{ type: 'hp', f: 2000 }], curve: 2 });
  }
}

/** Two-honk ascending fanfare used for fighter names. */
function fanfareGrain(sr, rng, ch) {
  const a = vowelGrain(sr, rng, ch, 'a', 110, 0, 1.0, 0.2);
  const b = vowelGrain(sr, rng, ch, 'a', 160, 1, 1.26, 0.35);
  return K.mix(sr, [{ buf: a, gain: 0 }, { buf: b, gain: 1.5, at: 0.1 }]);
}

/** Granny's rising "eh?" */
function ehGrain(sr, rng, ch) {
  return vowelGrain(sr, rng, ch, 'e', 190, 0, 1.05, 1.1);
}

/** Renders the full grain bank for a character: returns [{id, buf}] */
function renderBank(sr, rng, chId) {
  const ch = CHARACTERS[chId];
  const out = [];
  for (const v of ['a', 'e', 'i', 'o', 'u']) {
    for (let k = 0; k < 2; k++) {
      const ms = ch.grainMs[0] + (ch.grainMs[1] - ch.grainMs[0]) * (k === 0 ? 0.35 : 0.9);
      out.push({ id: `v_${v}_${k}`, buf: vowelGrain(sr, rng.fork(`v${v}${k}`), ch, v, ms, k) });
    }
  }
  for (const c of ['plosive', 'sibilant', 'sh', 'fric', 'nasal', 'liquid']) {
    for (let k = 0; k < 2; k++) out.push({ id: `c_${c}_${k}`, buf: consonantGrain(sr, rng.fork(`c${c}${k}`), ch, c, k) });
  }
  if (ch.fanfare) out.push({ id: 'fanfare', buf: fanfareGrain(sr, rng.fork('fanfare'), ch) });
  if (chId === 'granny') out.push({ id: 'eh', buf: ehGrain(sr, rng.fork('eh'), ch) });
  return out;
}

// ---------------------------------------------------------------------------------------
// Reference line planner (mirrors game/src/audio/babble.gd)
// ---------------------------------------------------------------------------------------

const VOWELS = 'aeiouy';
function letterClass(c) {
  c = c.toLowerCase();
  if (VOWELS.includes(c)) return 'vowel';
  if ('pbtdkgq'.includes(c)) return 'plosive';
  if ('szxc'.includes(c)) return 'sibilant';
  if ('h'.includes(c)) return 'sh';
  if ('fvjw'.includes(c)) return 'fric';
  if ('mn'.includes(c)) return 'nasal';
  if ('lr'.includes(c)) return 'liquid';
  return 'none';
}
function vowelOf(c) { c = c.toLowerCase(); return c === 'y' ? 'i' : VOWELS.includes(c) ? c : 'a'; }

/** Splits a word into syllables [{onset: cls|null, vowel: 'a'..'u', coda: cls|null}] */
function syllabify(word) {
  const letters = word.replace(/[^A-Za-z']/g, '');
  const syl = [];
  let onset = null, i = 0;
  while (i < letters.length) {
    const c = letters[i];
    const cls = letterClass(c);
    if (cls === 'vowel') {
      let v = vowelOf(c);
      let j = i + 1;
      while (j < letters.length && letterClass(letters[j]) === 'vowel') j++;
      // trailing silent e
      if (c.toLowerCase() === 'e' && i === letters.length - 1 && syl.length > 0) break;
      syl.push({ onset, vowel: v, coda: null });
      onset = null;
      i = j;
    } else {
      if (cls !== 'none') onset = cls;
      i++;
    }
  }
  if (syl.length === 0) syl.push({ onset: onset || 'plosive', vowel: 'u', coda: null });
  const lastCls = letterClass(letters[letters.length - 1] || 'a');
  if (lastCls !== 'vowel' && lastCls !== 'none') syl[syl.length - 1].coda = lastCls;
  return syl;
}

/**
 * Builds a grain plan for a line. Returns { duration, grains: [{t, id, pitch, gain, dur}] }.
 * Mirrors babble.gd (keep both in sync).
 */
function plan(text, chId, { seed = 1, reduced = false, names = [], mood = '' } = {}) {
  const ch = CHARACTERS[chId];
  const { Rng } = require('./rng');
  const rng = new Rng(seed + ':' + text);
  const words = text.split(/\s+/).filter((w) => w.length);
  // sentence segmentation by terminal punctuation
  const sentences = [];
  let cur = [];
  for (const w of words) {
    cur.push(w);
    if (/[.!?…]$|\.\.\.$/.test(w)) { sentences.push(cur); cur = []; }
  }
  if (cur.length) sentences.push(cur);
  const slot = 1 / ch.rate;
  const grains = [];
  let t = 0;
  for (const sentence of sentences) {
    const lastWord = sentence[sentence.length - 1];
    const term = /…$|\.\.\.$/.test(lastWord) ? '…' : /!$/.test(lastWord) ? '!' : /\?$/.test(lastWord) ? '?' : '.';
    // count syllables in the sentence for the contour position
    const sylCounts = sentence.map((w) => syllabify(w).length);
    const total = sylCounts.reduce((a, c) => a + c, 0);
    let sylIndex = 0;
    for (let wi = 0; wi < sentence.length; wi++) {
      const word = sentence[wi];
      const bare = word.replace(/[^A-Za-z']/g, '');
      const caps = bare.length >= 2 && bare === bare.toUpperCase();
      const isName = names.some((nm) => nm && bare.toLowerCase() === nm.toLowerCase());
      const isLast = wi === sentence.length - 1;
      const syls = syllabify(word);
      if (ch.fanfare && (isName || (caps && names.length === 0 && /^[A-Z]{4,}!?$/.test(word) && isLast))) {
        // fighter name -> fanfare grain
        const u = total > 0 ? sylIndex / total : 0;
        grains.push({ t, id: 'fanfare', pitch: contourPitch(ch, term, u, caps) * rng.range(0.97, 1.03), gain: ch.capsGain, dur: 0.27 });
        t += 0.29;
        sylIndex += syls.length;
      } else {
        for (let si = 0; si < syls.length; si++) {
          const s = syls[si];
          const u = total > 1 ? sylIndex / (total - 1) : 0.5;
          let pm = contourPitch(ch, term, u, caps);
          if (caps) pm *= ch.capsPitch;
          if (si === 0 && syls.length > 1) pm *= 1.04;
          if (isLast && si === syls.length - 1 && ch.contour === 'auction') pm *= term === '!' ? 1.12 : term === '?' ? 0.94 : 0.9;
          pm *= 1 + rng.range(-0.04, 0.04);
          let g = caps ? ch.capsGain : 1.0;
          if (isLast && ch.contour === 'auction') g *= 1.15;
          let slotLen = slot * (caps ? 1.25 : 1) * (isLast && si === syls.length - 1 ? 1.3 : 1);
          if (s.onset) grains.push({ t, id: `c_${s.onset}_${rng.int(2)}`, pitch: pm, gain: g * 0.9, dur: ch.consMs / 1000 });
          const vid = chId === 'granny' && term === '?' && isLast && si === syls.length - 1 ? 'eh' : `v_${s.vowel}_${rng.int(2)}`;
          grains.push({ t: t + (s.onset ? 0.018 : 0), id: vid, pitch: pm, gain: g, dur: Math.max(0.05, slotLen * 0.95), vib: mood === 'pleased' && chId === 'granny' ? 0.03 : 0 });
          t += slotLen;
          if (s.coda && si === syls.length - 1 && (s.coda === 'sibilant' || s.coda === 'sh' || s.coda === 'fric')) {
            grains.push({ t: t - 0.01, id: `c_${s.coda}_0`, pitch: pm, gain: g * 0.7, dur: 0.05 });
            t += 0.03;
          }
          sylIndex++;
        }
      }
      // pauses
      t += 0.025;
      if (/,$/.test(word)) t += 0.12;
      else if (/[—–-]$/.test(word)) t += 0.1;
      else if (/[;:]$/.test(word)) t += 0.16;
      else if (/[.!?]$/.test(word) && !isLast) t += 0.18;
    }
    t += 0.2;
  }
  let duration = t;
  const cap = 4.0;
  let scale = 1;
  if (duration > cap) scale = cap / duration;
  if (reduced) scale *= 0.5;
  if (scale !== 1) {
    for (const g of grains) { g.t *= scale; g.dur *= Math.max(scale, 0.6); }
    duration *= scale;
  }
  if (reduced) for (const g of grains) g.gain *= 0.5;
  return { duration, grains };
}

function contourPitch(ch, term, u, caps) {
  if (ch.contour === 'flat') return 1 - 0.03 * u;
  switch (term) {
    case '!': return 1 + 0.22 * u;
    case '?': return 1 + 0.28 * Math.sin(Math.PI * Math.min(1, u * 1.1)) - 0.05 * u;
    case '…': return 0.97;
    default: return 1.06 - 0.18 * u;
  }
}

/** Offline assembly of a plan with a rendered bank (for auditioning). bank: {id -> Float64Array} at sr. */
function assemble(planned, bank, sr) {
  const n = secs(sr, planned.duration + 0.3);
  const out = zeros(n);
  for (const g of planned.grains) {
    const src = bank[g.id];
    if (!src) continue;
    const start = Math.round(g.t * sr);
    const maxLen = Math.min(Math.round(g.dur * sr) + secs(sr, 0.03), Math.floor((src.length - 1) / g.pitch));
    const rel = secs(sr, 0.01);
    for (let i = 0; i < maxLen && start + i < n; i++) {
      const pos = i * g.pitch * (g.vib ? 1 + g.vib * Math.sin(i / sr * 2 * Math.PI * 6) : 1);
      const j = Math.floor(pos), f = pos - j;
      if (j + 1 >= src.length) break;
      const v = src[j] + (src[j + 1] - src[j]) * f;
      const w = i > maxLen - rel ? (maxLen - i) / rel : 1;
      out[start + i] += v * g.gain * w;
    }
  }
  return out;
}

module.exports = { CHARACTERS, renderBank, plan, assemble, syllabify, letterClass };
