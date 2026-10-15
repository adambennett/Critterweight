'use strict';
// BILGE — the Cannery Hound (ENEMIES_BOSSES.md §2.1). Bloated, rust-stained, sludge-soaked guard
// dog with a neck longer than it should be, chained collar with one red light, sweet eyes.
// Coordinates line up with game/content/core/bosses/boss_bilge.json.
const H = require('../../lib/helpers');

const P = {
  primary: '#5A4E45', hide_dk: '#3F3630', belly: '#7A6C60', sludge: '#8BD426', chain: '#8C3B2B', light: '#E03A2B',
  nose: '#2A2320', eye: '#F2EDE2', pupil: '#2A1F18', tongue: '#C2506A', teeth: '#E8DFC8', collar: '#5A2A20', pad: '#2E2825',
};

function leg(prefix, side, hipZ, kneeZ, pawZ, hipY) {
  const s = prefix + (side > 0 ? 'l' : 'r');
  const x = (prefix === 'f' ? 0.42 : 0.4) * side;
  const hip = [x, hipY, hipZ], knee = [x + 0.02 * side, 0.52, kneeZ], paw = [x + 0.03 * side, 0.1, pawZ];
  const parts = [
    { type: 'cone', seg: 'thigh_' + s, a: hip, b: knee, ra: 0.2, rb: 0.14, color: '$primary', name: 'leg', blend: 0.06 },
    { type: 'cone', seg: 'shin_' + s, a: knee, b: [paw[0], 0.18, paw[2]], ra: 0.13, rb: 0.12, color: '$primary', name: 'leg', blend: 0.04 },
    { type: 'ellipsoid', seg: 'shin_' + s, c: [paw[0], 0.11, paw[2] + 0.04], r: [0.17, 0.1, 0.2], color: '$primary', name: 'paw', blend: 0.03 },
  ];
  for (let i = -1; i <= 1; i++) {
    parts.push({ type: 'sphere', seg: 'shin_' + s, c: [paw[0] + i * 0.1, 0.09, paw[2] + 0.2], r: 0.065, color: '$primary', name: 'paw', blend: 0.03 });
    parts.push({ type: 'cone', seg: 'shin_' + s, a: [paw[0] + i * 0.1, 0.07, paw[2] + 0.24], b: [paw[0] + i * 0.1, 0.03, paw[2] + 0.31], ra: 0.028, rb: 0.008, color: '$nose', material: 'pad', name: 'claw', blend: 0.008 });
  }
  return parts;
}

module.exports = {
  id: 'boss_bilge',
  creature: 'game/content/core/bosses/boss_bilge.json',
  out: 'creatures/boss_bilge.glb',
  resolution: 0.018,
  target_tris: 18000,
  blend: 0.07,
  palette: P,
  materials: {
    skin: { roughness: 0.72, metallic: 0 },      // wet hide (toon spec stays soft)
    pad: { roughness: 0.8, metallic: 0 },
    metal: { roughness: 0.6, metallic: 0.6 },
    eye: { roughness: 0.2, metallic: 0 },
    glow: { roughness: 0.4, metallic: 0, emissive: '#E03A2B' },
    drool: { roughness: 0.2, metallic: 0, emissive: '#8BD426' },
  },
  parts: [
    // ---- bloated body ----
    { type: 'capsule', seg: 'chest', a: [0, 1.42, -0.15], b: [0, 1.42, 0.65], r: 0.62, color: '$primary', name: 'body', blend: 0.1 },
    { type: 'ellipsoid', seg: 'chest', c: [0, 1.2, 0.3], r: [0.66, 0.5, 0.75], color: '$primary', name: 'body', blend: 0.1 },
    { type: 'capsule', seg: 'pelvis', a: [0, 1.3, -0.6], b: [0, 1.28, -1.05], r: 0.5, color: '$primary', name: 'body', blend: 0.1 },
    { type: 'ellipsoid', seg: 'chest', c: [0, 1.72, 0.55], r: [0.5, 0.3, 0.4], color: '$primary', name: 'body', blend: 0.1 },
    // ---- the too-long neck, collar, chain ----
    { type: 'cone', seg: 'neck1', a: [0, 1.5, 0.92], b: [0, 1.6, 1.32], ra: 0.3, rb: 0.26, color: '$primary', name: 'neck', blend: 0.08 },
    { type: 'cone', seg: 'neck2', a: [0, 1.62, 1.32], b: [0, 1.7, 1.68], ra: 0.26, rb: 0.24, color: '$primary', name: 'neck', blend: 0.08 },
    { type: 'torus', seg: 'neck1', c: [0, 1.56, 1.12], axis: [0, 0.3, 1], R: 0.32, r: 0.05, color: '$collar', material: 'pad', name: 'collar', blend: 0.012 },
    { type: 'sphere', seg: 'neck1', c: [0, 1.88, 1.03], r: 0.06, color: '$light', material: 'glow', glow: 1.0, name: 'collar_light', op: 'sharp', blend: 0 },
    H.bumps({ seg: 'neck1', a: [-0.3, 1.58, 1.02], b: [0.3, 1.58, 1.02], count: 5, r: 0.03, color: '$chain', material: 'metal', name: 'stud', blend: 0.006 }),
    H.chain({ seg: 'chain', a: [0, 1.26, 1.1], b: [0, 0.76, 1.0], links: 6, R: 0.07, r: 0.02, color: '$chain' }),
    // ---- head: big skull, muzzle, jowls, floppy ears, sweet eyes ----
    { type: 'sphere', seg: 'head', c: [0, 1.8, 1.88], r: 0.32, color: '$primary', name: 'head', blend: 0.07 },
    { type: 'ellipsoid', seg: 'head', c: [0, 1.7, 2.12], r: [0.24, 0.18, 0.3], color: '$primary', name: 'muzzle', blend: 0.06 },
    { type: 'ellipsoid', seg: 'head', c: [0, 1.55, 2.0], r: [0.28, 0.14, 0.3], color: '$primary', name: 'jowl', blend: 0.06 },
    { type: 'sphere', seg: 'head', c: [0, 1.74, 2.4], r: 0.08, color: '$nose', material: 'pad', name: 'nose', blend: 0.015 },
    { type: 'box', seg: 'head', c: [0, 1.6, 2.26], size: [0.36, 0.02, 0.2], color: '$nose', paint: true, name: 'mouth' },
    { type: 'cone', seg: 'head', a: [0.11, 1.62, 2.3], b: [0.11, 1.5, 2.3], ra: 0.03, rb: 0.008, color: '$teeth', material: 'eye', name: 'tooth', mirror: true, blend: 0.004, op: 'sharp' },
    { type: 'ellipsoid', seg: 'head', c: [0.07, 1.5, 2.32], r: [0.08, 0.04, 0.12], rot: [20, 0, 0], color: '$tongue', name: 'tongue', blend: 0.015 },
    H.eye({ seg: 'head', c: [0.17, 1.9, 2.1], r: 0.08, dir: [0.3, 0.1, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.045, iris: '#6B4A2E', material: 'eye',
      brow: { a: [0.08, 2.0, 2.1], b: [0.27, 1.97, 2.05], w: 0.05, h: 0.03, color: '$hide_dk' } }),
    H.eye({ seg: 'head', c: [-0.17, 1.9, 2.1], r: 0.08, dir: [-0.3, 0.1, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.045, iris: '#6B4A2E', material: 'eye',
      brow: { a: [-0.08, 2.0, 2.1], b: [-0.27, 1.97, 2.05], w: 0.05, h: 0.03, color: '$hide_dk' } }),
    { type: 'box', seg: 'head', a: [0.3, 2.0, 1.78], b: [0.42, 1.6, 1.74], w: 0.2, h: 0.06, round: 0.025, color: '$hide_dk', name: 'ear', mirror: true, blend: 0.03 },
    // drool (glowing sludge) hanging from the jowls
    { type: 'cone', seg: 'head', a: [0.18, 1.5, 2.18], b: [0.2, 1.28, 2.2], ra: 0.04, rb: 0.012, color: '$sludge', material: 'drool', glow: 0.7, name: 'drool', blend: 0.012 },
    { type: 'sphere', seg: 'head', c: [0.2, 1.26, 2.2], r: 0.035, color: '$sludge', material: 'drool', glow: 0.7, name: 'drool', blend: 0.012 },
    { type: 'cone', seg: 'head', a: [-0.12, 1.48, 2.26], b: [-0.13, 1.34, 2.28], ra: 0.03, rb: 0.01, color: '$sludge', material: 'drool', glow: 0.7, name: 'drool', blend: 0.012 },
    // sludge puddle stains on the chest and belly
    { type: 'sphere', seg: 'chest', c: [0.3, 0.85, 0.5], r: 0.2, color: '$sludge', paint: true, name: 'stain' },
    { type: 'sphere', seg: 'chest', c: [-0.2, 0.9, 0.1], r: 0.16, color: '$sludge', paint: true, name: 'stain' },
    // ---- legs, tail ----
    leg('f', 1, 0.55, 0.62, 0.55, 0.95), leg('f', -1, 0.55, 0.62, 0.55, 0.95),
    leg('b', 1, -0.85, -0.95, -0.85, 0.92), leg('b', -1, -0.85, -0.95, -0.85, 0.92),
    { type: 'cone', seg: 'tail', a: [0, 1.4, -1.12], b: [0, 1.1, -1.6], ra: 0.09, rb: 0.04, color: '$primary', name: 'tail', blend: 0.05 },
  ],
  paints: [
    { type: 'facing', target: { zones: ['body', 'neck', 'head', 'muzzle', 'jowl', 'leg'] }, dir: [0, -1, 0], start: 0.2, end: 0.9, color: '$belly', strength: 0.7 },
    { type: 'facing', target: { zones: ['body', 'neck', 'head'] }, dir: [0, 1, 0], start: 0.5, end: 1.0, color: '$hide_dk', strength: 0.4 },
    { type: 'spots', target: { zones: ['body', 'neck', 'leg'] }, cell: 0.3, radius: 0.09, density: 0.4, seed: 8, color: '$chain' },
  ],
  gore: {
    resolution: 0.005, target_tris: 300,
    parts: [{ type: 'cone', a: [0, 0.05, 0], b: [0, -0.05, 0], ra: 0.03, rb: 0.008, color: '$teeth', material: 'eye' }],
  },
};
