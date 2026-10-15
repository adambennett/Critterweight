'use strict';
// Crowd (AUDIO_DIRECTION.md §3.7): three heat layers plus one-shots. Rendered at 22.05 kHz on the
// "Crowd" bus (routed to Ambience). Arena character comes from the bus reverb at runtime.
const K = require('../lib/sfxkit');
const D = require('../lib/dsp');
const { def, jit } = require('./_def');

const CROWD = { bus: 'Crowd', group: 'crowd', sr: 22050, priority: 40, max_voices: 3, spatial: false, pitch: [0.98, 1.02] };

/** A crowd "voice cloud": N formant voices with random pitch/timing, summed. */
function cloud(sr, rng, { dur = 1, voices = 18, f0 = [110, 240], vowel = 'a', contour = [[0, 1], [1, 0.9]], env = { a: 0.1, d: 0.2, s: 0.8, r: 0.3 }, spreadStart = 0.1, breath = 0.2, growl = 0.05 } = {}) {
  const F = { a: [[700, 5, 1], [1200, 6, 0.6], [2600, 7, 0.25]], o: [[500, 5, 1], [900, 6, 0.5], [2400, 7, 0.15]], u: [[330, 5, 1], [800, 6, 0.35], [2300, 7, 0.1]], e: [[520, 5, 1], [1800, 6, 0.5], [2500, 7, 0.25]], i: [[300, 5, 0.8], [2200, 6, 0.5], [2900, 7, 0.3]] };
  const parts = [];
  for (let v = 0; v < voices; v++) {
    const base = rng.range(f0[0], f0[1]) * (rng.bool(0.5) ? 1 : 1.5);
    const f0c = contour.map(([t, m]) => [t * dur, base * m * rng.range(0.97, 1.03)]);
    const vo = K.vocal(sr, rng, { dur: dur * rng.range(0.85, 1), f0: f0c, formants: F[vowel].map(([f, q, g]) => [f * rng.range(0.9, 1.1), q, g]), breath, growl, growlRate: 25, jitter: 0.02, drive: 1.3, a: env.a * rng.range(0.6, 1.4), d: env.d, s: env.s, r: env.r, lp: 4500, wave: 'pulse', pw: 0.15 });
    parts.push({ buf: vo, gain: -8 + rng.range(-4, 2), at: rng.range(0, spreadStart) });
  }
  return K.mix(sr, parts, 0.05);
}

function murmur(sr, rng, dur, intensity) {
  // broadband crowd bed: pink noise through 3 wandering "vowel" bands + sparse voice blips
  const n = D.secs(sr, dur);
  const nz = new D.Pink(rng);
  const bands = [new D.SVF(sr, 400, 2), new D.SVF(sr, 1100, 2.5), new D.SVF(sr, 2400, 3)];
  const lfos = [new D.Lfo(sr, 'sine', rng.float()), new D.Lfo(sr, 'tri', rng.float()), new D.Lfo(sr, 'sine', rng.float())];
  const out = D.zeros(n);
  for (let i = 0; i < n; i++) {
    const x = nz.next();
    let y = 0;
    for (let b = 0; b < 3; b++) {
      const base = [400, 1100, 2400][b];
      bands[b].set(base * Math.pow(2, lfos[b].next(0.07 + b * 0.05) * 0.4), 2 + b * 0.5);
      y += bands[b].bp(x) * [1, 0.7, 0.35][b];
    }
    out[i] = y * (0.8 + 0.2 * Math.sin(i / sr * 2 * Math.PI * 0.21)) * (0.6 + 0.4 * intensity);
  }
  const parts = [{ buf: out, gain: 0 }];
  const blips = Math.round(6 + intensity * 30);
  for (let b = 0; b < blips; b++) {
    parts.push({ buf: cloud(sr, rng, { dur: rng.range(0.25, 0.7), voices: 2 + Math.round(intensity * 6), vowel: rng.pick(['a', 'o', 'e', 'u']), f0: [110, 260], env: { a: 0.08, d: 0.1, s: 0.8, r: 0.15 }, breath: 0.3 }), gain: -14 + intensity * 8 + rng.range(-3, 2), at: rng.range(0, dur - 0.8) });
  }
  return K.seamless(K.mix(sr, parts).slice(0, n), sr, 0.8);
}

module.exports = [
  def('crowd_murmur', Object.assign({ loop: true, gain: -8 }, CROWD), (rng, sr) => murmur(sr, rng, 8, 0.15)),
  def('crowd_excited', Object.assign({ loop: true, gain: -6 }, CROWD), (rng, sr) => murmur(sr, rng, 8, 0.55)),
  def('crowd_roar', Object.assign({ loop: true, gain: -4 }, CROWD), (rng, sr) => {
    const bed = murmur(sr, rng, 8, 1.0);
    const roar = K.seamless(cloud(sr, rng, { dur: 8, voices: 40, vowel: 'a', f0: [120, 300], contour: [[0, 1], [0.5, 1.05], [1, 0.98]], env: { a: 0.5, d: 0.5, s: 0.9, r: 0.5 }, spreadStart: 1.5, breath: 0.25, growl: 0.1 }).slice(0, bed.length), sr, 1.0);
    return K.mix(sr, [{ buf: bed, gain: 0 }, { buf: roar, gain: 2 }]).slice(0, bed.length);
  }),
  def('crowd_ooh', Object.assign({ variants: 3, cooldown: 8, priority: 60 }, CROWD), (rng, sr) =>
    K.tidy(cloud(sr, rng, { dur: 1.1, voices: 24, vowel: 'u', f0: [140, 320], contour: [[0, 1.0], [0.3, 1.1], [1, 0.8]], env: { a: 0.06, d: 0.2, s: 0.8, r: 0.35 }, spreadStart: 0.08 }), sr, { fadeOut: 0.05 })),
  def('crowd_aww', Object.assign({ variants: 3, cooldown: 8, priority: 60 }, CROWD), (rng, sr) =>
    K.tidy(cloud(sr, rng, { dur: 1.3, voices: 22, vowel: 'a', f0: [140, 300], contour: [[0, 1.05], [1, 0.72]], env: { a: 0.08, d: 0.3, s: 0.8, r: 0.4 }, spreadStart: 0.1 }), sr, { fadeOut: 0.05 })),
  def('crowd_boo', Object.assign({ variants: 2, cooldown: 8, priority: 60 }, CROWD), (rng, sr) =>
    K.tidy(cloud(sr, rng, { dur: 1.6, voices: 26, vowel: 'u', f0: [100, 220], contour: [[0, 1], [0.6, 0.98], [1, 0.9]], env: { a: 0.12, d: 0.2, s: 0.9, r: 0.4 }, spreadStart: 0.25, breath: 0.15 }), sr, { fadeOut: 0.05 })),
  def('crowd_gasp', Object.assign({ variants: 2, cooldown: 8, priority: 60 }, CROWD), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.burst(sr, rng, { dur: 0.35, color: 'pink', filt: [{ type: 'bp', f: 1800, q: 0.6 }, { type: 'hp', f: 600 }], a: 0.15, curve: 2, gain: 1.2 }), gain: 0 },
    { buf: cloud(sr, rng, { dur: 0.3, voices: 10, vowel: 'a', f0: [160, 340], contour: [[0, 0.9], [1, 1.1]], env: { a: 0.1, d: 0.05, s: 0.8, r: 0.1 }, spreadStart: 0.05, breath: 0.6 }), gain: -6 }]), sr, { fadeOut: 0.05 })),
  def('crowd_laugh', Object.assign({ variants: 2, cooldown: 8, priority: 60 }, CROWD), (rng, sr) => {
    const parts = [];
    for (let i = 0; i < 6; i++) parts.push({ buf: cloud(sr, rng, { dur: 0.16, voices: 12, vowel: 'a', f0: [150, 330], contour: [[0, 1.08], [1, 0.95]], env: { a: 0.01, d: 0.05, s: 0.7, r: 0.06 }, spreadStart: 0.05, breath: 0.3 }), gain: -i * 0.6, at: i * 0.19 });
    return K.tidy(K.mix(sr, parts), sr, { fadeOut: 0.05 });
  }),
  def('crowd_cheer', Object.assign({ variants: 3, cooldown: 6, priority: 70 }, CROWD), (rng, sr) => {
    const c = cloud(sr, rng, { dur: 2.0, voices: 34, vowel: 'a', f0: [140, 340], contour: [[0, 1], [0.4, 1.12], [1, 1.0]], env: { a: 0.15, d: 0.4, s: 0.85, r: 0.6 }, spreadStart: 0.3, breath: 0.25, growl: 0.08 });
    const parts = [{ buf: c, gain: 0 }];
    for (let w = 0; w < 4; w++) parts.push({ buf: K.chirp(sr, { f0: jit(rng, 2200, 0.1), f1: jit(rng, 3200, 0.1), dur: 0.35, wave: 'sine', curve: 1.3, a: 0.03, gain: 0.25 }), gain: -12, at: rng.range(0.2, 1.4) });
    return K.tidy(K.mix(sr, parts), sr, { fadeOut: 0.08 });
  }),
  def('crowd_chant', Object.assign({ loop: true, gain: -5, priority: 65, pitch: [1, 1] }, CROWD), (rng, sr) => {
    // 2 bars at 128 BPM = 3.75 s: "OH - OH - OH-OH-OH" style pulses on beats 1, 2, 3, 3-and, 4
    const beat = 60 / 128;
    const n = Math.round(beat * 8 * sr);
    const hits = [0, 1, 2, 2.5, 3, 4, 5, 6, 6.5, 7];
    const parts = [];
    for (const h of hits) parts.push({ buf: cloud(sr, rng, { dur: 0.3, voices: 20, vowel: 'o', f0: [120, 280], contour: [[0, 1], [1, 0.95]], env: { a: 0.03, d: 0.1, s: 0.8, r: 0.12 }, spreadStart: 0.04, breath: 0.2 }), gain: h % 1 ? -3 : 0, at: h * beat });
    return K.seamless(K.mix(sr, parts).slice(0, n), sr, 0.1);
  }),
  def('crowd_can_shower', Object.assign({ variants: 2, cooldown: 10, priority: 60 }, CROWD), (rng, sr) => {
    const parts = [];
    for (let i = 0; i < 28; i++) parts.push({ buf: K.fmHit(sr, { f: rng.range(600, 1800), ratio: 2.76, index: 1.2, dur: rng.range(0.08, 0.2), idxDecay: 0.3 }), gain: -6 + rng.range(-6, 0), at: rng.range(0, 1.6) });
    parts.push({ buf: K.rattle(sr, rng, { dur: 1.8, f: 160, density: 80, gain: 0.8, hp: 700 }), gain: -6 });
    return K.tidy(K.mix(sr, parts), sr, { fadeOut: 0.1 });
  }),
  def('crowd_whistle', Object.assign({ variants: 2, cooldown: 5, priority: 50, gain: -8 }, CROWD), (rng, sr) =>
    K.tidy(K.mix(sr, [{ buf: K.chirp(sr, { f0: 2400, f1: 3100, dur: 0.25, wave: 'sine', curve: 1.2, a: 0.02, gain: 0.5 }), gain: 0 }, { buf: K.chirp(sr, { f0: 3100, f1: 2300, dur: 0.3, wave: 'sine', curve: 1.2, a: 0.01, gain: 0.5 }), gain: 0, at: 0.25 }]), sr)),
];
