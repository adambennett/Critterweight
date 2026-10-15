'use strict';
// STOKE — the Boiler Newt (ROSTER.md §1). Barrel silhouette: wide shoulders, short legs, cast-iron
// boiler belly with a glowing furnace door, stovepipe crest, bandaged fists, short newt tail.
// All coordinates are fighter rest space and line up with game/content/core/creatures/f_stoke.json.
const H = require('../../lib/helpers');

const P = {
  primary: '#D9532B', belly: '#E8743F', dark: '#B8411E', secondary: '#3A3A42', iron_hi: '#4D4D57',
  accent: '#FF7A1A', ember: '#FFB347', wraps: '#EDE6D6', wraps_dk: '#D8CEB8', eyes: '#FFD23F',
  crest: '#2B2B30', mouth: '#5A1E14', teeth: '#F4EFE2', band: '#E8E4DC',
};

module.exports = {
  id: 'f_stoke',
  creature: 'game/content/core/creatures/f_stoke.json',
  out: 'creatures/f_stoke.glb',
  resolution: 0.01,
  target_tris: 12000,
  blend: 0.035,
  palette: P,
  materials: {
    skin: { roughness: 0.72, metallic: 0 },
    iron: { roughness: 0.5, metallic: 0.6 },
    cloth: { roughness: 0.92, metallic: 0 },
    eye: { roughness: 0.25, metallic: 0 },
    ember: { roughness: 0.4, metallic: 0, emissive: '#FF7A1A' },
    team: { roughness: 0.8, metallic: 0 },
  },
  parts: [
    // ---- torso: boiler belly + shoulders ----
    { type: 'sphere', seg: 'chest', c: [0, 1.0, 0.04], r: 0.31, color: '$primary', name: 'torso', blend: 0.06 },
    { type: 'capsule', seg: 'chest', a: [-0.3, 1.16, -0.02], b: [0.3, 1.16, -0.02], r: 0.14, color: '$primary', name: 'torso', blend: 0.06 },
    { type: 'ellipsoid', seg: 'pelvis', c: [0, 0.64, 0], r: [0.25, 0.2, 0.22], color: '$primary', name: 'torso', blend: 0.06 },
    // cast-iron belly plate (front half of the boiler) with rivets and the furnace door
    { type: 'ellipsoid', seg: 'chest', c: [0, 0.95, 0.12], r: [0.27, 0.3, 0.27], color: '$secondary', material: 'iron', name: 'plate', blend: 0.012, op: 'sharp',
      clip: [{ p: [0, 0.95, 0.09], n: [0, 0, -1] }] },
    { type: 'box', seg: 'chest', c: [0, 0.93, 0.36], size: [0.26, 0.2, 0.06], round: 0.02, color: '$iron_hi', material: 'iron', name: 'door', blend: 0.006, op: 'sharp' },
    { type: 'box', seg: 'chest', c: [0, 0.93, 0.385], size: [0.18, 0.12, 0.03], round: 0.012, color: '$accent', material: 'ember', glow: 0.9, name: 'door_glow', blend: 0.0, op: 'sharp' },
    { type: 'cylinder', seg: 'chest', a: [0.13, 0.85, 0.37], b: [0.13, 0.85, 0.42], r: 0.018, color: '$iron_hi', material: 'iron', name: 'handle', op: 'sharp', blend: 0.003 },
    H.bumps({ seg: 'chest', a: [-0.2, 1.14, 0.21], b: [0.2, 1.14, 0.21], count: 5, r: 0.016, color: '$iron_hi', material: 'iron', name: 'rivet', blend: 0.004 }),
    H.bumps({ seg: 'chest', a: [-0.2, 0.76, 0.19], b: [0.2, 0.76, 0.19], count: 5, r: 0.016, color: '$iron_hi', material: 'iron', name: 'rivet', blend: 0.004 }),
    // ---- head: round newt head, wide jaw, stovepipe crest ----
    { type: 'sphere', seg: 'head', c: [0, 1.36, 0.07], r: 0.17, color: '$primary', name: 'head', blend: 0.04 },
    { type: 'ellipsoid', seg: 'head', c: [0, 1.29, 0.16], r: [0.16, 0.08, 0.14], color: '$primary', name: 'head', blend: 0.04 },
    { type: 'capsule', seg: 'head', a: [0, 1.4, 0.0], b: [0, 1.3, 0.03], r: 0.12, color: '$primary', name: 'neck', blend: 0.06 },
    // mouth line (dark decal) and two teeth
    { type: 'box', seg: 'head', c: [0, 1.265, 0.25], size: [0.2, 0.016, 0.08], round: 0.006, color: '$mouth', paint: true, name: 'mouth' },
    { type: 'box', seg: 'head', c: [0.045, 1.25, 0.265], size: [0.022, 0.03, 0.02], round: 0.006, color: '$teeth', material: 'eye', op: 'sharp', name: 'tooth', mirror: true, blend: 0.002 },
    // nostrils
    { type: 'sphere', seg: 'head', c: [0.04, 1.33, 0.29], r: 0.012, color: '$dark', paint: true, name: 'nostril', mirror: true },
    H.eye({ seg: 'head', c: [0.085, 1.41, 0.19], r: 0.052, dir: [0.25, 0.1, 1], white: '$eyes', pupil: '#2B1A10', pupil_r: 0.024, material: 'eye',
      brow: { a: [0.03, 1.47, 0.2], b: [0.15, 1.45, 0.17], w: 0.03, h: 0.022, color: '$dark' } }),
    H.eye({ seg: 'head', c: [-0.085, 1.41, 0.19], r: 0.052, dir: [-0.25, 0.1, 1], white: '$eyes', pupil: '#2B1A10', pupil_r: 0.024, material: 'eye',
      brow: { a: [-0.03, 1.47, 0.2], b: [-0.15, 1.45, 0.17], w: 0.03, h: 0.022, color: '$dark' } }),
    // stovepipe crest: an iron pipe with a rain cap, slightly raked back
    { type: 'cylinder', seg: 'head', a: [0, 1.46, 0.0], b: [0, 1.66, -0.05], r: 0.045, round: 0.01, color: '$crest', material: 'iron', name: 'pipe', blend: 0.02 },
    { type: 'cylinder', seg: 'head', a: [0, 1.64, -0.045], b: [0, 1.675, -0.055], r: 0.062, round: 0.008, color: '$crest', material: 'iron', name: 'pipe', blend: 0.004, op: 'sharp' },
    { type: 'sphere', seg: 'head', c: [0, 1.652, -0.05], r: 0.03, color: '$accent', material: 'ember', glow: 0.6, name: 'pipe_glow', op: 'sharp', blend: 0.0 },
    // ---- arms ----
    { type: 'cone', seg: 'uarm_l', a: [0.38, 1.15, 0], b: [0.38, 0.84, 0], ra: 0.1, rb: 0.08, color: '$primary', name: 'uarm_l', mirror: true, blend: 0.05 },
    { type: 'sphere', seg: 'uarm_l', c: [0.4, 1.16, 0], r: 0.11, color: '$primary', name: 'shoulder_l', mirror: true, blend: 0.05 },
    { type: 'cone', seg: 'farm_l', a: [0.38, 0.82, 0], b: [0.38, 0.6, 0.02], ra: 0.075, rb: 0.085, color: '$primary', name: 'farm_l', mirror: true, blend: 0.04 },
    H.fist({ seg: 'farm_l', c: [0.38, 0.5, 0.03], r: 0.12, fwd: [0, -0.3, 1], side: [1, 0, 0], color: '$wraps', material: 'cloth', name: 'fist_l' }),
    H.fist({ seg: 'farm_r', c: [-0.38, 0.5, 0.03], r: 0.12, fwd: [0, -0.3, 1], side: [-1, 0, 0], color: '$wraps', material: 'cloth', name: 'fist_r' }),
    H.wrap({ seg: 'farm_l', a: [0.38, 0.72, 0.01], b: [0.38, 0.6, 0.02], r: 0.082, turns: 3, color: '$wraps_dk', name: 'wrap_l' }),
    H.wrap({ seg: 'farm_r', a: [-0.38, 0.72, 0.01], b: [-0.38, 0.6, 0.02], r: 0.082, turns: 3, color: '$wraps_dk', name: 'wrap_r' }),
    // ---- legs: stubby thighs, shins, three-toed feet ----
    { type: 'cone', seg: 'thigh_l', a: [0.15, 0.6, 0], b: [0.15, 0.35, 0.055], ra: 0.11, rb: 0.085, color: '$primary', name: 'thigh_l', mirror: true, blend: 0.05 },
    { type: 'cone', seg: 'shin_l', a: [0.15, 0.33, 0.06], b: [0.15, 0.1, 0.01], ra: 0.08, rb: 0.07, color: '$primary', name: 'shin_l', mirror: true, blend: 0.04 },
    { type: 'ellipsoid', seg: 'shin_l', c: [0.15, 0.05, 0.07], r: [0.08, 0.05, 0.14], color: '$primary', name: 'foot_l', mirror: true, blend: 0.03 },
    { type: 'sphere', seg: 'shin_l', c: [0.15, 0.045, 0.2], r: 0.04, color: '$primary', name: 'foot_l', mirror: true, blend: 0.02 },
    { type: 'sphere', seg: 'shin_l', c: [0.205, 0.045, 0.185], r: 0.035, color: '$primary', name: 'foot_l', mirror: true, blend: 0.02 },
    { type: 'sphere', seg: 'shin_l', c: [0.095, 0.045, 0.185], r: 0.035, color: '$primary', name: 'foot_l', mirror: true, blend: 0.02 },
    // ---- tail ----
    { type: 'cone', seg: 'tail', a: [0, 0.6, -0.14], b: [0, 0.44, -0.42], ra: 0.075, rb: 0.03, color: '$primary', name: 'tail', blend: 0.05 },
  ],
  paints: [
    // lighter belly/throat on the organic skin
    { type: 'facing', target: { materials: ['skin'], exclude_zones: ['eye_white', 'eye_pupil'] }, dir: [0, -0.5, 1], start: 0.35, end: 0.95, color: '$belly', strength: 0.8 },
    // newt spots along the back and crown
    { type: 'spots', target: { zones: ['torso', 'head', 'uarm_l', 'uarm_r', 'thigh_l', 'thigh_r', 'tail'] }, cell: 0.11, radius: 0.028, density: 0.45, seed: 3, color: '$dark' },
    // team tint band: a tape ring around each upper arm
    { type: 'band', target: { zones: ['uarm_l', 'uarm_r'] }, axis: [0, 1, 0], center: 1.0, width: 0.05, color: '$band', material: 'team' },
    // darker tail tip
    { type: 'gradient', target: { zones: ['tail'] }, axis: [0, 0, -1], from: 0.25, to: 0.42, color: '$dark', strength: 0.7 },
  ],
  gore: {
    // the tooth that pings off on the KO hit
    resolution: 0.003, target_tris: 300, color: '$teeth',
    parts: [{ type: 'cone', a: [0, 0.02, 0], b: [0, -0.025, 0], ra: 0.016, rb: 0.005, color: '$teeth', material: 'eye' }],
  },
};
