'use strict';
// KID LAMPREY — the tutorial sparring partner and Ring Sparring opponent (HUB.md §2, GAME_PITCH):
// "lamprey in a hoodie, hood always up, mouthful of teeth". The fighting body (npc_kid_lamprey.json)
// is an upright eel trunk in a hoodie: sleeve fists, the round toothed sucker mouth inside the hood,
// a two-segment eel tail curling behind, and sneakers that just are there under the trunk,
// unexplained (same joke as the hub model, hub/kid_lamprey.glb). ~1.4 m, 60 kg.
// Coordinates line up with game/content/core/creatures/npc_kid_lamprey.json.
const H = require('../../lib/helpers');

const P = {
  hoodie: '#3F4A5C', hoodie_dk: '#2C3340', string: '#EDE6D6', skin: '#6E8B8E', skin_lt: '#A9C4C2', skin_dk: '#4E676A',
  mouth: '#4A1A2A', teeth: '#F2EFE4', eye: '#F6F4EE', pupil: '#101418', sneaker: '#F2F2EC', sole: '#C23A2B', band: '#E6E2DA',
};

function teethRing(c, R, n, len, inward, seg) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2;
    const base = [c[0] + Math.cos(a) * R, c[1] + Math.sin(a) * R, c[2]];
    const tip = [c[0] + Math.cos(a) * (R - inward), c[1] + Math.sin(a) * (R - inward), c[2] + len];
    out.push({ type: 'cone', seg, a: base, b: tip, ra: 0.011, rb: 0.003, color: '$teeth', material: 'eye', name: 'tooth', op: 'sharp', blend: 0, skin_soft: 0.01 });
  }
  return out;
}

function arm(side) {
  const s = side > 0 ? 'l' : 'r';
  return [
    { type: 'cone', seg: 'uarm_' + s, a: [0.24 * side, 1.0, 0], b: [0.25 * side, 0.76, 0], ra: 0.078, rb: 0.068, color: '$hoodie', material: 'cloth', name: 'sleeve', blend: 0.04 },
    { type: 'cone', seg: 'farm_' + s, a: [0.25 * side, 0.75, 0], b: [0.26 * side, 0.6, 0.03], ra: 0.068, rb: 0.064, color: '$hoodie', material: 'cloth', name: 'sleeve', blend: 0.035 },
    { type: 'torus', seg: 'farm_' + s, c: [0.26 * side, 0.6, 0.03], axis: [0, 1, 0.15], R: 0.058, r: 0.018, color: '$hoodie_dk', material: 'cloth', name: 'cuff', blend: 0.008 },
    H.fist({ seg: 'farm_' + s, c: [0.26 * side, 0.51, 0.04], r: 0.075, fwd: [0, -0.3, 1], side: [side, 0, 0], color: '$skin', name: 'fist', blend: 0.015 }),
  ];
}

module.exports = {
  id: 'npc_kid_lamprey',
  creature: 'game/content/core/creatures/npc_kid_lamprey.json',
  out: 'creatures/npc_kid_lamprey.glb',
  resolution: 0.009,
  target_tris: 9000,
  blend: 0.03,
  palette: P,
  default_color: '$skin',
  materials: {
    skin: { roughness: 0.42, metallic: 0 },      // wet eel skin
    cloth: { roughness: 0.92, metallic: 0 },
    eye: { roughness: 0.2, metallic: 0 },
    glow: { roughness: 0.4, metallic: 0, emissive: '#C23A2B' },
    team: { roughness: 0.85, metallic: 0 },
  },
  parts: [
    // ---- eel trunk below the hoodie, tail curling behind ----
    { type: 'cone', seg: 'pelvis', a: [0, 0.68, 0.0], b: [0, 0.22, 0.01], ra: 0.15, rb: 0.115, color: '$skin', name: 'trunk', blend: 0.05 },
    { type: 'cone', seg: 'tail1', a: [0, 0.36, -0.1], b: [0, 0.2, -0.36], ra: 0.085, rb: 0.065, color: '$skin', name: 'tail', blend: 0.05 },
    { type: 'cone', seg: 'tail2', a: [0, 0.19, -0.37], b: [0, 0.13, -0.62], ra: 0.06, rb: 0.028, color: '$skin', name: 'tail', blend: 0.04 },
    { type: 'box', seg: 'tail2', a: [0, 0.19, -0.4], b: [0, 0.14, -0.66], w: 0.018, h: 0.1, round: 0.006, color: '$skin_lt', name: 'fin', blend: 0.015 },
    { type: 'box', seg: 'tail1', a: [0, 0.4, -0.16], b: [0, 0.25, -0.36], w: 0.016, h: 0.07, round: 0.006, color: '$skin_lt', name: 'fin', blend: 0.015 },
    // ---- hoodie: torso tube, shoulders, kangaroo pocket, hem, drawstrings ----
    { type: 'cone', seg: 'chest', a: [0, 0.6, 0.0], b: [0, 0.99, 0.0], ra: 0.19, rb: 0.175, color: '$hoodie', material: 'cloth', name: 'hoodie', blend: 0.04 },
    { type: 'capsule', seg: 'chest', a: [-0.18, 1.01, 0], b: [0.18, 1.01, 0], r: 0.1, color: '$hoodie', material: 'cloth', name: 'hoodie', blend: 0.05 },
    { type: 'box', seg: 'chest', c: [0, 0.75, 0.175], size: [0.27, 0.14, 0.05], round: 0.02, color: '$hoodie_dk', material: 'cloth', name: 'pocket', blend: 0.01 },
    { type: 'torus', seg: 'chest', c: [0, 0.6, 0.0], axis: [0, 1, 0], R: 0.18, r: 0.025, color: '$hoodie_dk', material: 'cloth', name: 'hem', blend: 0.01 },
    { type: 'capsule', seg: 'chest', a: [0.065, 1.06, 0.17], b: [0.08, 0.88, 0.19], r: 0.008, color: '$string', material: 'cloth', name: 'string', mirror: true, blend: 0.004 },
    { type: 'sphere', seg: 'chest', c: [0.08, 0.875, 0.192], r: 0.013, color: '$string', material: 'cloth', name: 'string', mirror: true, blend: 0.004 },
    // ---- hood (always up) around the lamprey head ----
    { type: 'ellipsoid', seg: 'head', c: [0, 1.27, -0.01], r: [0.2, 0.2, 0.19], color: '$hoodie', material: 'cloth', name: 'hood', blend: 0.04 },
    { type: 'sphere', seg: 'head', c: [0.13, 1.2, 0.0], r: 0.13, color: '$hoodie', material: 'cloth', name: 'hood', mirror: true, blend: 0.04 },
    { type: 'ellipsoid', seg: 'head', c: [0, 1.22, 0.16], r: [0.125, 0.14, 0.14], op: 'subtract', blend: 0.015, name: 'hood_hole' },
    { type: 'torus', seg: 'head', c: [0, 1.22, 0.135], axis: [0, 0.15, 1], R: 0.125, r: 0.02, color: '$hoodie_dk', material: 'cloth', name: 'hood_rim', blend: 0.01 },
    // ---- the lamprey face: round sucker mouth with rings of teeth, tiny eyes ----
    { type: 'sphere', seg: 'head', c: [0, 1.22, 0.05], r: 0.125, color: '$skin', name: 'face', blend: 0.03 },
    { type: 'cylinder', seg: 'head', a: [0, 1.19, 0.12], b: [0, 1.19, 0.185], r: 0.085, round: 0.02, color: '$skin_lt', name: 'lips', blend: 0.015 },
    { type: 'cylinder', seg: 'head', a: [0, 1.19, 0.16], b: [0, 1.19, 0.22], r: 0.058, op: 'subtract', blend: 0.01, name: 'mouth_hole' },
    { type: 'sphere', seg: 'head', c: [0, 1.19, 0.15], r: 0.056, color: '$mouth', paint: true, name: 'mouth' },
    teethRing([0, 1.19, 0.17], 0.064, 10, 0.026, 0.026, 'head'),
    teethRing([0, 1.19, 0.16], 0.04, 7, 0.02, 0.016, 'head'),
    H.eye({ seg: 'head', c: [0.075, 1.29, 0.135], r: 0.02, dir: [0.3, 0.1, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.009, material: 'eye', shine: false }),
    H.eye({ seg: 'head', c: [-0.075, 1.29, 0.135], r: 0.02, dir: [-0.3, 0.1, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.009, material: 'eye', shine: false }),
    // ---- sleeves and fists ----
    arm(1), arm(-1),
    // ---- sneakers (on the shins, poking out under the trunk) ----
    { type: 'ellipsoid', seg: 'shin_l', c: [0.09, 0.055, 0.06], r: [0.062, 0.05, 0.125], color: '$sneaker', material: 'cloth', name: 'sneaker', mirror: true, blend: 0.012 },
    { type: 'box', seg: 'shin_l', c: [0.09, 0.016, 0.06], size: [0.12, 0.022, 0.26], round: 0.008, color: '$sole', material: 'cloth', name: 'sole', mirror: true, blend: 0.004, op: 'sharp' },
    { type: 'capsule', seg: 'shin_l', a: [0.055, 0.085, 0.07], b: [0.125, 0.085, 0.07], r: 0.008, color: '$sole', material: 'cloth', name: 'lace', mirror: true, blend: 0.002 },
  ],
  paints: [
    // lighter belly on the eel skin, darker back and tail tip, mottled spots
    { type: 'facing', target: { zones: ['trunk', 'tail', 'face', 'fist'] }, dir: [0, -0.3, 1], start: 0.35, end: 0.95, color: '$skin_lt', strength: 0.6 },
    { type: 'spots', target: { zones: ['trunk', 'tail'] }, cell: 0.09, radius: 0.022, density: 0.45, seed: 11, color: '$skin_dk' },
    { type: 'gradient', target: { zones: ['tail'] }, axis: [0, 0, -1], from: 0.4, to: 0.62, color: '$skin_dk', strength: 0.7 },
    // hoodie: darker underside folds
    { type: 'facing', target: { zones: ['hoodie', 'hood', 'sleeve'] }, dir: [0, -1, 0], start: 0.3, end: 0.9, color: '$hoodie_dk', strength: 0.5 },
    // team tint: a varsity stripe around each sleeve
    { type: 'band', target: { zones: ['sleeve'] }, axis: [0, 1, 0], center: 0.86, width: 0.045, color: '$band', material: 'team' },
  ],
  gore: {
    // one of his many teeth pings off on the KO hit
    resolution: 0.003, target_tris: 300, color: '$teeth',
    parts: [{ type: 'cone', a: [0, 0.018, 0], b: [0, -0.022, 0], ra: 0.013, rb: 0.004, color: '$teeth', material: 'eye' }],
  },
};
