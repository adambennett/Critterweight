'use strict';
// DOZER — the Shovelsnout (ROSTER.md §4). "Doorstop with a lamp": long low wedge, steel
// shovel-blade snout, one short horn, cracked-stone shoulder plates, mining headlamp on a strap.
// Coordinates line up with game/content/core/creatures/f_dozer.json.
const H = require('../../lib/helpers');

const P = {
  primary: '#6E6A66', hide_dk: '#575350', belly: '#8C8782', secondary: '#C7A160', plate_dk: '#9E7D44', snout: '#9FA6AD',
  snout_dk: '#7C838A', accent: '#FFE066', horn: '#D8D3C8', hoof: '#3A3634', eyes: '#111111', dust: '#D9C7A3', strap: '#4A3F33', band: '#E6E2DA',
};

function leg(prefix, side, z, hipY) {
  const s = prefix + (side > 0 ? 'l' : 'r');
  const hip = [0.3 * side, hipY, z], knee = [0.31 * side, 0.3, z + (z > 0 ? 0.06 : -0.06)], hoof = [0.31 * side, 0.05, z];
  return [
    { type: 'cone', seg: 'thigh_' + s, a: hip, b: knee, ra: 0.12, rb: 0.085, color: '$primary', name: 'leg', blend: 0.05 },
    { type: 'cone', seg: 'shin_' + s, a: knee, b: [hoof[0], 0.12, hoof[2]], ra: 0.08, rb: 0.075, color: '$primary', name: 'leg', blend: 0.03 },
    { type: 'ellipsoid', seg: 'shin_' + s, c: [hoof[0], 0.07, hoof[2] + 0.01], r: [0.095, 0.07, 0.1], color: '$hoof', material: 'hoof', name: 'hoof', blend: 0.012, op: 'sharp' },
  ];
}

module.exports = {
  id: 'f_dozer',
  creature: 'game/content/core/creatures/f_dozer.json',
  out: 'creatures/f_dozer.glb',
  resolution: 0.012,
  target_tris: 14000,
  blend: 0.04,
  palette: P,
  materials: {
    skin: { roughness: 0.85, metallic: 0 },      // coarse matte hide
    clay: { roughness: 0.9, metallic: 0 },
    steel: { roughness: 0.35, metallic: 0.7 },
    hoof: { roughness: 0.6, metallic: 0 },
    glow: { roughness: 0.3, metallic: 0, emissive: '#FFE066' },
    eye: { roughness: 0.2, metallic: 0 },
    team: { roughness: 0.85, metallic: 0 },
  },
  parts: [
    // ---- body: barrel chest, round rump, hump over the shoulders ----
    { type: 'capsule', seg: 'chest', a: [0, 0.82, -0.08], b: [0, 0.82, 0.42], r: 0.37, color: '$primary', name: 'body', blend: 0.07 },
    { type: 'ellipsoid', seg: 'chest', c: [0, 1.0, 0.25], r: [0.4, 0.22, 0.32], color: '$primary', name: 'body', blend: 0.07 },
    { type: 'capsule', seg: 'pelvis', a: [0, 0.76, -0.34], b: [0, 0.76, -0.6], r: 0.31, color: '$primary', name: 'body', blend: 0.07 },
    // cracked-stone shoulder plates
    { type: 'box', seg: 'chest', c: [0.33, 1.03, 0.28], size: [0.3, 0.14, 0.42], round: 0.05, rot: [0, 8, -30], color: '$secondary', material: 'clay', name: 'plate', mirror: true, blend: 0.015 },
    { type: 'box', seg: 'chest', c: [0.3, 1.05, -0.06], size: [0.22, 0.1, 0.3], round: 0.04, rot: [0, -6, -26], color: '$secondary', material: 'clay', name: 'plate', mirror: true, blend: 0.015 },
    { type: 'box', seg: 'chest', c: [0.36, 1.08, 0.3], size: [0.3, 0.012, 0.012], rot: [20, 30, -28], color: '$plate_dk', paint: true, name: 'crack', mirror: true },
    { type: 'box', seg: 'chest', c: [0.33, 1.12, 0.18], size: [0.012, 0.012, 0.26], rot: [0, -25, -28], color: '$plate_dk', paint: true, name: 'crack', mirror: true },
    // ---- neck and head ----
    { type: 'cone', seg: 'neck', a: [0, 0.82, 0.58], b: [0, 0.79, 0.86], ra: 0.24, rb: 0.2, color: '$primary', name: 'neck', blend: 0.06 },
    { type: 'sphere', seg: 'head', c: [0, 0.78, 0.96], r: 0.21, color: '$primary', name: 'head', blend: 0.05 },
    { type: 'ellipsoid', seg: 'head', c: [0, 0.86, 0.98], r: [0.19, 0.14, 0.2], color: '$primary', name: 'head', blend: 0.05 },
    // shovel-blade snout: wide tapered steel plate with a lip
    { type: 'box', seg: 'head', a: [0, 0.68, 0.98], b: [0, 0.62, 1.3], w: 0.3, h: 0.1, round: 0.03, taper: 1.6, color: '$snout', material: 'steel', name: 'snout', blend: 0.015 },
    { type: 'box', seg: 'head', c: [0, 0.66, 1.27], size: [0.5, 0.05, 0.05], round: 0.02, color: '$snout_dk', material: 'steel', name: 'snout_lip', blend: 0.008 },
    { type: 'ellipsoid', seg: 'head', c: [0, 0.72, 1.12], r: [0.16, 0.05, 0.16], color: '$primary', name: 'snout_hide', blend: 0.03 },
    H.bumps({ seg: 'head', a: [-0.1, 0.705, 1.06], b: [0.1, 0.705, 1.06], count: 3, r: 0.014, color: '$snout_dk', material: 'steel', name: 'bolt', blend: 0.004 }),
    // nostrils
    { type: 'sphere', seg: 'head', c: [0.07, 0.745, 1.2], r: 0.02, color: '$hide_dk', paint: true, name: 'nostril', mirror: true },
    // horn: short stout cone above the snout, bone-coloured with a darker base
    { type: 'cone', seg: 'head', a: [0, 0.86, 0.98], b: [0, 1.1, 1.26], ra: 0.085, rb: 0.014, color: '$horn', material: 'hoof', name: 'horn', blend: 0.02 },
    // headlamp on a strap
    { type: 'torus', seg: 'head', c: [0, 0.93, 0.96], axis: [0, 0.35, 1], R: 0.195, r: 0.02, color: '$strap', material: 'hoof', name: 'strap', blend: 0.008 },
    { type: 'cylinder', seg: 'head', a: [0, 0.99, 1.02], b: [0, 1.04, 1.12], r: 0.08, round: 0.012, color: '$snout_dk', material: 'steel', name: 'lamp', blend: 0.01 },
    { type: 'cylinder', seg: 'head', a: [0, 1.035, 1.11], b: [0, 1.045, 1.13], r: 0.062, round: 0.004, color: '$accent', material: 'glow', glow: 1.0, name: 'lamp_lens', op: 'sharp', blend: 0 },
    // small eyes (black beads) and ears
    { type: 'sphere', seg: 'head', c: [0.14, 0.86, 1.08], r: 0.03, color: '$eyes', material: 'eye', op: 'sharp', name: 'eye', mirror: true, blend: 0.004 },
    { type: 'sphere', seg: 'head', c: [0.15, 0.872, 1.102], r: 0.008, color: '#FFFFFF', material: 'eye', op: 'sharp', name: 'eye_shine', mirror: true, blend: 0 },
    { type: 'cone', seg: 'head', a: [0.14, 0.92, 0.84], b: [0.22, 1.05, 0.78], ra: 0.05, rb: 0.015, color: '$primary', name: 'ear', mirror: true, blend: 0.02 },
    // ---- legs and tail ----
    leg('f', 1, 0.44, 0.54), leg('f', -1, 0.44, 0.54), leg('b', 1, -0.5, 0.52), leg('b', -1, -0.5, 0.52),
    { type: 'cone', seg: 'tail', a: [0, 0.78, -0.68], b: [0, 0.64, -0.98], ra: 0.06, rb: 0.02, color: '$primary', name: 'tail', blend: 0.04 },
    { type: 'sphere', seg: 'tail', c: [0, 0.63, -1.0], r: 0.035, color: '$hide_dk', name: 'tail_tuft', blend: 0.015 },
  ],
  paints: [
    { type: 'facing', target: { zones: ['body', 'neck', 'head', 'leg'] }, dir: [0, -1, 0], start: 0.2, end: 0.9, color: '$belly', strength: 0.8 },
    { type: 'facing', target: { zones: ['body', 'neck', 'head'] }, dir: [0, 1, 0], start: 0.5, end: 1.0, color: '$hide_dk', strength: 0.35 },
    // dust caked on the lower legs
    { type: 'gradient', target: { zones: ['leg'] }, axis: [0, -1, 0], from: -0.4, to: -0.12, color: '$dust', strength: 0.55 },
    { type: 'spots', target: { zones: ['body'] }, cell: 0.2, radius: 0.05, density: 0.4, seed: 5, color: '$dust' },
    // team band: a harness strap around the girth
    { type: 'band', target: { zones: ['body'] }, axis: [0, 0, 1], center: 0.04, width: 0.08, color: '$band', material: 'team' },
    { type: 'edge', target: { zones: ['plate'] }, width: 0.015, lighten: 0.25 },
  ],
  gore: {
    resolution: 0.004, target_tris: 300,
    parts: [{ type: 'cone', a: [0, -0.04, 0], b: [0, 0.05, 0], ra: 0.03, rb: 0.006, color: '$horn', material: 'hoof' }],
  },
};
