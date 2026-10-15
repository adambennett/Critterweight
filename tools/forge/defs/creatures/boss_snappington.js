'use strict';
// COMMISSIONER SNAPPINGTON — Her Honor (ENEMIES_BOSSES.md §2.3). "A dome with a gavel": ancient
// snapping turtle on the crab body plan, moss-green shell with gold trim, olive skin, reading
// glasses, a gavel on a chain in the right claw. Coordinates line up with
// game/content/core/bosses/boss_snappington.json.
const H = require('../../lib/helpers');

const P = {
  primary: '#4F6B3A', shell_dk: '#36492A', gold: '#C9A227', skin: '#8A8C5A', skin_dk: '#6B6D45', belly: '#C9C39A',
  eye: '#F2EFE4', pupil: '#1C1A12', beak: '#3C3A2E', gavel: '#5A3B22', gavel_hi: '#8B5E36', chain: '#7A7F85', lens: '#DDEBF2',
};

function leg(fb, side) {
  const s = fb + (side > 0 ? 'l' : 'r');
  const z = fb === 'f' ? 1 : -1;
  const hip = [0.75 * side, 0.6, 0.45 * z], knee = [1.1 * side, 0.75, 0.5 * z], foot = [1.2 * side, 0.06, 0.55 * z];
  const parts = [
    { type: 'cone', seg: 'uleg_' + s, a: hip, b: knee, ra: 0.16, rb: 0.12, color: '$skin', name: 'leg', blend: 0.04 },
    { type: 'sphere', seg: 'uleg_' + s, c: knee, r: 0.13, color: '$skin_dk', name: 'knee', blend: 0.02 },
    { type: 'cone', seg: 'lleg_' + s, a: knee, b: [foot[0], 0.14, foot[2]], ra: 0.12, rb: 0.11, color: '$skin', name: 'leg', blend: 0.03 },
    { type: 'ellipsoid', seg: 'lleg_' + s, c: [foot[0], 0.08, foot[2]], r: [0.16, 0.08, 0.18], color: '$skin', name: 'foot', blend: 0.03 },
  ];
  for (let i = -1; i <= 1; i++) {
    parts.push({ type: 'cone', seg: 'lleg_' + s, a: [foot[0] + i * 0.09 * side, 0.06, foot[2] + 0.14], b: [foot[0] + i * 0.1 * side, 0.03, foot[2] + 0.26], ra: 0.035, rb: 0.01, color: '$beak', material: 'horn', name: 'claw', blend: 0.008 });
  }
  return parts;
}

function claw(side) {
  const s = side > 0 ? 'l' : 'r';
  const sh = [0.72 * side, 0.8, 0.6], el = [1.12 * side, 0.95, 0.9], tip = [0.86 * side, 0.85, 1.48];
  const big = side < 0 ? 1.25 : 1.0;
  const parts = [
    { type: 'cone', seg: 'uclaw_' + s, a: sh, b: el, ra: 0.15 * big, rb: 0.13 * big, color: '$skin', name: 'arm', blend: 0.04 },
    { type: 'sphere', seg: 'uclaw_' + s, c: el, r: 0.15 * big, color: '$skin_dk', name: 'elbow', blend: 0.02 },
    { type: 'cone', seg: 'claw_' + s, a: el, b: [tip[0] + 0.06 * side, 0.86, 1.3], ra: 0.14 * big, rb: 0.15 * big, color: '$skin', name: 'arm', blend: 0.04 },
    { type: 'ellipsoid', seg: 'claw_' + s, c: [tip[0] + 0.04 * side, 0.85, 1.38], r: [0.2 * big, 0.12 * big, 0.2 * big], color: '$skin', name: 'hand', blend: 0.035 },
  ];
  // three thick clawed fingers
  for (let i = -1; i <= 1; i++) {
    const base = [tip[0] + i * 0.12 * big * side, 0.85, 1.5];
    parts.push({ type: 'cone', seg: 'claw_' + s, a: base, b: [base[0] + i * 0.04 * side, 0.8, 1.72 * (big > 1 ? 1.02 : 1)], ra: 0.065 * big, rb: 0.03 * big, color: '$skin', name: 'finger', blend: 0.02 });
    parts.push({ type: 'cone', seg: 'claw_' + s, a: [base[0] + i * 0.04 * side, 0.8, 1.7], b: [base[0] + i * 0.05 * side, 0.74, 1.84], ra: 0.03 * big, rb: 0.008, color: '$beak', material: 'horn', name: 'claw', blend: 0.008 });
  }
  return parts;
}

module.exports = {
  id: 'boss_snappington',
  creature: 'game/content/core/bosses/boss_snappington.json',
  out: 'creatures/boss_snappington.glb',
  resolution: 0.015,
  target_tris: 18000,
  blend: 0.06,
  palette: P,
  materials: {
    skin: { roughness: 0.75, metallic: 0 },
    shell: { roughness: 0.35, metallic: 0.05 },    // slight clearcoat chitin
    gold: { roughness: 0.3, metallic: 0.9 },
    metal: { roughness: 0.5, metallic: 0.7 },
    horn: { roughness: 0.5, metallic: 0 },
    wood: { roughness: 0.6, metallic: 0 },
    eye: { roughness: 0.2, metallic: 0 },
    lens: { roughness: 0.1, metallic: 0.3 },
  },
  parts: [
    // ---- shell: dome with a scute pattern, gold rim, skirt plates ----
    { type: 'ellipsoid', seg: 'shell', c: [0, 0.82, 0], r: [1.15, 0.6, 1.0], color: '$primary', material: 'shell', name: 'shell', blend: 0.05, clip: [{ p: [0, 0.44, 0], n: [0, -1, 0] }] },
    { type: 'ellipsoid', seg: 'shell', c: [0, 0.98, -0.1], r: [0.85, 0.62, 0.75], color: '$primary', material: 'shell', name: 'shell', blend: 0.05, clip: [{ p: [0, 0.44, 0], n: [0, -1, 0] }] },
    { type: 'ellipsoid', seg: 'shell', c: [0, 0.5, 0], r: [1.0, 0.22, 0.88], color: '$belly', name: 'plastron', blend: 0.04 },
    { type: 'torus', seg: 'shell', c: [0, 0.62, 0], axis: [0, 1, 0], R: 1.05, r: 0.05, color: '$gold', material: 'gold', name: 'trim', op: 'sharp', blend: 0 },
    { type: 'torus', seg: 'shell', c: [0, 0.6, -0.02], axis: [0, 1, 0.12], R: 0.88, r: 0.04, color: '$gold', material: 'gold', name: 'trim', op: 'sharp', blend: 0 },
    // ---- neck and head ----
    { type: 'cone', seg: 'neck', a: [0, 0.95, 1.0], b: [0, 1.1, 1.48], ra: 0.21, rb: 0.17, color: '$skin', name: 'neck', blend: 0.05 },
    { type: 'torus', seg: 'neck', c: [0, 1.0, 1.15], axis: [0, 0.3, 1], R: 0.2, r: 0.025, color: '$skin_dk', name: 'wrinkle', blend: 0.015 },
    { type: 'torus', seg: 'neck', c: [0, 1.05, 1.32], axis: [0, 0.3, 1], R: 0.18, r: 0.025, color: '$skin_dk', name: 'wrinkle', blend: 0.015 },
    { type: 'sphere', seg: 'head', c: [0, 1.2, 1.68], r: 0.25, color: '$skin', name: 'head', blend: 0.05 },
    { type: 'cone', seg: 'head', a: [0, 1.14, 1.8], b: [0, 1.06, 2.08], ra: 0.17, rb: 0.07, color: '$beak', material: 'horn', name: 'beak', blend: 0.02 },
    { type: 'cone', seg: 'head', a: [0, 1.06, 1.8], b: [0, 1.0, 2.0], ra: 0.13, rb: 0.05, color: '$beak', material: 'horn', name: 'beak', blend: 0.02 },
    { type: 'box', seg: 'head', c: [0, 1.07, 1.92], size: [0.3, 0.016, 0.3], color: '#15140F', paint: true, name: 'mouth' },
    // small stern eyes behind half-moon reading glasses
    H.eye({ seg: 'head', c: [0.13, 1.29, 1.85], r: 0.065, dir: [0.3, 0.1, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.028, material: 'eye', lid: 0.35, lid_color: '$skin',
      brow: { a: [0.06, 1.36, 1.88], b: [0.2, 1.33, 1.84], w: 0.04, h: 0.025, color: '$skin_dk' } }),
    H.eye({ seg: 'head', c: [-0.13, 1.29, 1.85], r: 0.065, dir: [-0.3, 0.1, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.028, material: 'eye', lid: 0.35, lid_color: '$skin',
      brow: { a: [-0.06, 1.36, 1.88], b: [-0.2, 1.33, 1.84], w: 0.04, h: 0.025, color: '$skin_dk' } }),
    { type: 'torus', seg: 'head', c: [0.13, 1.26, 1.92], axis: [0.3, 0.1, 1], R: 0.085, r: 0.016, color: '$gold', material: 'gold', name: 'glasses', op: 'sharp', blend: 0, mirror: true },
    { type: 'cylinder', seg: 'head', a: [0.13, 1.26, 1.9], b: [0.13, 1.26, 1.92], r: 0.075, round: 0.004, color: '$lens', material: 'lens', name: 'lens', op: 'sharp', blend: 0, mirror: true },
    { type: 'capsule', seg: 'head', a: [-0.05, 1.27, 1.93], b: [0.05, 1.27, 1.93], r: 0.014, color: '$gold', material: 'gold', name: 'glasses', op: 'sharp', blend: 0 },
    { type: 'capsule', seg: 'head', a: [0.21, 1.26, 1.88], b: [0.3, 1.27, 1.6], r: 0.014, color: '$gold', material: 'gold', name: 'glasses', op: 'sharp', blend: 0, mirror: true },
    // ---- claws (right one holds the gavel on a chain) ----
    claw(1), claw(-1),
    { type: 'cylinder', seg: 'claw_r', a: [-0.98, 1.3, 1.3], b: [-0.98, 1.3, 1.66], r: 0.1, round: 0.02, color: '$gavel', material: 'wood', name: 'gavel_head', blend: 0.01 },
    { type: 'torus', seg: 'claw_r', c: [-0.98, 1.3, 1.36], axis: [0, 0, 1], R: 0.1, r: 0.012, color: '$gold', material: 'gold', name: 'gavel_band', op: 'sharp', blend: 0 },
    { type: 'torus', seg: 'claw_r', c: [-0.98, 1.3, 1.6], axis: [0, 0, 1], R: 0.1, r: 0.012, color: '$gold', material: 'gold', name: 'gavel_band', op: 'sharp', blend: 0 },
    { type: 'cylinder', seg: 'claw_r', a: [-0.98, 1.3, 1.48], b: [-0.9, 0.95, 1.46], r: 0.035, round: 0.008, color: '$gavel_hi', material: 'wood', name: 'gavel_handle', blend: 0.01 },
    H.chain({ seg: 'claw_r', a: [-0.9, 0.95, 1.46], b: [-0.74, 0.92, 1.1], links: 5, R: 0.04, r: 0.012, color: '$chain' }),
    // ---- legs and tail ----
    leg('f', 1), leg('f', -1), leg('b', 1), leg('b', -1),
    { type: 'cone', seg: 'tail', a: [0, 0.7, -0.94], b: [0, 0.5, -1.3], ra: 0.11, rb: 0.03, color: '$skin', name: 'tail', blend: 0.04 },
  ],
  paints: [
    // scutes: a coarse cell pattern of darker green on the dome
    { type: 'spots', target: { zones: ['shell'] }, cell: 0.42, radius: 0.16, density: 0.9, seed: 13, color: '$shell_dk' },
    { type: 'facing', target: { zones: ['neck', 'head', 'leg', 'arm', 'hand', 'tail'] }, dir: [0, -1, 0], start: 0.3, end: 0.95, color: '$belly', strength: 0.5 },
    { type: 'edge', target: { zones: ['shell'] }, width: 0.03, lighten: 0.2 },
  ],
  gore: {
    // the reading glasses fly off
    resolution: 0.004, target_tris: 500,
    parts: [
      { type: 'torus', c: [0.07, 0, 0], axis: [0, 0, 1], R: 0.06, r: 0.01, color: '$gold', material: 'gold', op: 'sharp' },
      { type: 'torus', c: [-0.07, 0, 0], axis: [0, 0, 1], R: 0.06, r: 0.01, color: '$gold', material: 'gold', op: 'sharp' },
      { type: 'capsule', a: [-0.02, 0.0, 0], b: [0.02, 0.0, 0], r: 0.008, color: '$gold', material: 'gold', op: 'sharp' },
    ],
  },
};
