'use strict';
// DREDGE — the Dock Crab (ROSTER.md §2). "Rusty anvil with a fist": low, very wide barnacled
// shell, one huge chain-wrapped crusher claw (right), a quick cutter (left), eyestalks.
// Coordinates line up with game/content/core/creatures/f_dredge.json.
const H = require('../../lib/helpers');

const P = {
  primary: '#8C3B2B', shell_dk: '#6E2D21', secondary: '#B9B3A6', belly: '#E8D9B8', tips: '#2E2A28',
  chain: '#7A7F85', eyes: '#DDF3FF', pupil: '#1A1D22', accent: '#2E9BE0', joint: '#A6503D', band: '#E6E2DA',
};

function barnacles() {
  // clusters of barnacle cones on the shell dome with a faint blue glow in the opening
  const out = [];
  const spots = [[-0.42, 0.78, 0.1], [-0.2, 0.9, -0.12], [0.05, 0.92, 0.2], [0.3, 0.88, -0.05], [0.52, 0.76, 0.2],
    [-0.55, 0.7, -0.25], [0.2, 0.84, -0.32], [-0.08, 0.86, -0.36], [0.6, 0.7, -0.18], [-0.3, 0.84, 0.3]];
  spots.forEach((s, i) => {
    const r = 0.04 + (i % 3) * 0.012;
    const tip = [s[0] * 1.02, s[1] + r * 1.1, s[2] * 1.02];
    out.push({ type: 'cone', seg: 'shell', a: [s[0], s[1] - r, s[2]], b: tip, ra: r, rb: r * 0.55, color: '$secondary', name: 'barnacle', blend: 0.012 });
    out.push({ type: 'sphere', seg: 'shell', c: [tip[0], tip[1] + 0.002, tip[2]], r: r * 0.32, color: '$accent', material: 'glow', glow: 0.7, name: 'barnacle_glow', op: 'sharp', blend: 0 });
  });
  return out;
}

function leg(side, fb) {
  // side: 1 = left (+x), -1 = right; fb: 'f' | 'b'
  const z = fb === 'f' ? 1 : -1;
  const u = `uleg_${fb}${side > 0 ? 'l' : 'r'}`, l = `lleg_${fb}${side > 0 ? 'l' : 'r'}`;
  const hip = [0.5 * side, 0.5, 0.25 * z], knee = [0.82 * side, 0.78, 0.3 * z], foot = [1.0 * side, 0.06, 0.36 * z];
  return [
    { type: 'cone', seg: u, a: hip, b: knee, ra: 0.085, rb: 0.07, color: '$primary', name: 'leg', blend: 0.03 },
    { type: 'sphere', seg: u, c: knee, r: 0.09, color: '$joint', name: 'knee', blend: 0.015 },
    { type: 'cone', seg: l, a: knee, b: [foot[0] * 0.99, 0.12, foot[2]], ra: 0.065, rb: 0.035, color: '$primary', name: 'leg', blend: 0.025 },
    { type: 'cone', seg: l, a: [foot[0] * 0.99, 0.13, foot[2]], b: [foot[0], 0.0, foot[2]], ra: 0.04, rb: 0.012, color: '$tips', name: 'leg_tip', blend: 0.01 },
  ];
}

module.exports = {
  id: 'f_dredge',
  creature: 'game/content/core/creatures/f_dredge.json',
  out: 'creatures/f_dredge.glb',
  resolution: 0.012,
  target_tris: 14000,
  blend: 0.035,
  palette: P,
  materials: {
    skin: { roughness: 0.45, metallic: 0.05 },       // wet chitin / chipped painted iron
    crust: { roughness: 0.9, metallic: 0 },
    metal: { roughness: 0.5, metallic: 0.7 },
    eye: { roughness: 0.2, metallic: 0 },
    glow: { roughness: 0.3, metallic: 0, emissive: '#2E9BE0' },
    team: { roughness: 0.8, metallic: 0 },
  },
  parts: [
    // ---- shell: lumpy low dome, flat-ish underbelly, front rim spikes ----
    { type: 'ellipsoid', seg: 'shell', c: [0, 0.6, 0], r: [0.72, 0.33, 0.5], color: '$primary', name: 'shell', blend: 0.06 },
    { type: 'ellipsoid', seg: 'shell', c: [0, 0.56, -0.12], r: [0.6, 0.3, 0.46], color: '$primary', name: 'shell', blend: 0.06 },
    { type: 'ellipsoid', seg: 'shell', c: [0, 0.44, 0.02], r: [0.64, 0.2, 0.44], color: '$belly', name: 'belly', blend: 0.03 },
    H.bumps({ seg: 'shell', a: [-0.55, 0.6, 0.42], b: [0.55, 0.6, 0.42], count: 7, r: 0.05, color: '$primary', name: 'shell', blend: 0.02 }),
    H.bumps({ seg: 'shell', a: [-0.74, 0.58, 0.1], b: [-0.74, 0.58, -0.3], count: 3, r: 0.045, color: '$primary', name: 'shell', blend: 0.02 }),
    H.bumps({ seg: 'shell', a: [0.74, 0.58, 0.1], b: [0.74, 0.58, -0.3], count: 3, r: 0.045, color: '$primary', name: 'shell', blend: 0.02 }),
    barnacles(),
    // ---- eyestalks + mouthparts ----
    { type: 'cylinder', seg: 'head', a: [0.1, 0.82, 0.4], b: [0.12, 1.02, 0.42], r: 0.035, round: 0.01, color: '$primary', name: 'stalk', mirror: true, blend: 0.03 },
    { type: 'sphere', seg: 'head', c: [0.12, 1.06, 0.42], r: 0.062, color: '$eyes', material: 'eye', op: 'sharp', name: 'eye_white', mirror: true, blend: 0.01 },
    { type: 'sphere', seg: 'head', c: [0.125, 1.065, 0.47], r: 0.028, color: '$pupil', material: 'eye', op: 'sharp', name: 'eye_pupil', mirror: true, blend: 0 },
    { type: 'sphere', seg: 'head', c: [0.11, 1.08, 0.485], r: 0.009, color: '#FFFFFF', material: 'eye', op: 'sharp', name: 'eye_shine', mirror: true, blend: 0 },
    { type: 'cone', seg: 'shell', a: [0.09, 0.62, 0.48], b: [0.13, 0.5, 0.6], ra: 0.035, rb: 0.015, color: '$tips', name: 'mandible', mirror: true, blend: 0.015 },
    // ---- walking legs ----
    leg(1, 'f'), leg(1, 'b'), leg(-1, 'f'), leg(-1, 'b'),
    // ---- crusher (right): chain-wrapped arm, fat palm, two pincers ----
    { type: 'cone', seg: 'uclaw_r', a: [-0.42, 0.62, 0.38], b: [-0.74, 0.74, 0.62], ra: 0.11, rb: 0.1, color: '$primary', name: 'uclaw_r', blend: 0.04 },
    { type: 'sphere', seg: 'uclaw_r', c: [-0.74, 0.74, 0.62], r: 0.12, color: '$joint', name: 'elbow_r', blend: 0.02 },
    H.chain({ seg: 'uclaw_r', a: [-0.5, 0.78, 0.4], b: [-0.7, 0.86, 0.58], links: 5, R: 0.05, r: 0.014, color: '$chain' }),
    H.chain({ seg: 'claw_r', a: [-0.72, 0.6, 0.66], b: [-0.6, 0.52, 0.86], links: 5, R: 0.05, r: 0.014, color: '$chain' }),
    { type: 'ellipsoid', seg: 'claw_r', c: [-0.6, 0.68, 0.8], r: [0.2, 0.17, 0.22], rot: [0, -20, 0], color: '$primary', name: 'claw_r', blend: 0.04 },
    { type: 'cone', seg: 'claw_r', a: [-0.56, 0.64, 0.9], b: [-0.4, 0.6, 1.18], ra: 0.11, rb: 0.035, color: '$primary', name: 'claw_r', blend: 0.03 },
    { type: 'cone', seg: 'claw_r', a: [-0.44, 0.61, 1.12], b: [-0.36, 0.59, 1.24], ra: 0.04, rb: 0.012, color: '$tips', name: 'claw_tip', blend: 0.008 },
    { type: 'cone', seg: 'claw_r', a: [-0.66, 0.74, 0.92], b: [-0.56, 0.82, 1.16], ra: 0.09, rb: 0.03, color: '$primary', name: 'claw_r', blend: 0.03 },
    { type: 'cone', seg: 'claw_r', a: [-0.58, 0.8, 1.1], b: [-0.52, 0.84, 1.22], ra: 0.035, rb: 0.01, color: '$tips', name: 'claw_tip', blend: 0.008 },
    H.bumps({ seg: 'claw_r', a: [-0.7, 0.84, 0.7], b: [-0.5, 0.82, 0.95], count: 3, r: 0.04, color: '$secondary', name: 'barnacle', blend: 0.012 }),
    // ---- cutter (left): slim arm, long thin pincers ----
    { type: 'cone', seg: 'uclaw_l', a: [0.42, 0.62, 0.38], b: [0.7, 0.72, 0.6], ra: 0.075, rb: 0.065, color: '$primary', name: 'uclaw_l', blend: 0.035 },
    { type: 'sphere', seg: 'uclaw_l', c: [0.7, 0.72, 0.6], r: 0.08, color: '$joint', name: 'elbow_l', blend: 0.02 },
    { type: 'ellipsoid', seg: 'claw_l', c: [0.56, 0.71, 0.78], r: [0.1, 0.09, 0.15], rot: [0, 25, 0], color: '$primary', name: 'claw_l', blend: 0.03 },
    { type: 'cone', seg: 'claw_l', a: [0.52, 0.7, 0.86], b: [0.4, 0.68, 1.12], ra: 0.055, rb: 0.018, color: '$primary', name: 'claw_l', blend: 0.02 },
    { type: 'cone', seg: 'claw_l', a: [0.42, 0.68, 1.08], b: [0.37, 0.67, 1.18], ra: 0.02, rb: 0.007, color: '$tips', name: 'claw_tip', blend: 0.006 },
    { type: 'cone', seg: 'claw_l', a: [0.6, 0.74, 0.86], b: [0.52, 0.78, 1.1], ra: 0.045, rb: 0.015, color: '$primary', name: 'claw_l', blend: 0.02 },
    { type: 'cone', seg: 'claw_l', a: [0.53, 0.78, 1.06], b: [0.5, 0.8, 1.16], ra: 0.018, rb: 0.006, color: '$tips', name: 'claw_tip', blend: 0.006 },
  ],
  paints: [
    { type: 'facing', target: { zones: ['shell', 'leg', 'uclaw_r', 'uclaw_l', 'claw_r', 'claw_l'] }, dir: [0, -1, 0], start: 0.3, end: 0.9, color: '$belly', strength: 0.75 },
    // painted iron chips / rust streaks on the shell top
    { type: 'spots', target: { zones: ['shell'] }, cell: 0.16, radius: 0.045, density: 0.5, seed: 11, color: '$shell_dk' },
    // team band: a painted stripe across the rear of the shell
    { type: 'band', target: { zones: ['shell'] }, axis: [0, 0, 1], center: -0.28, width: 0.09, color: '$band', material: 'team' },
    { type: 'edge', target: { zones: ['claw_r', 'claw_l'] }, width: 0.012, lighten: 0.35 },
  ],
  gore: {
    resolution: 0.004, target_tris: 300,
    parts: [{ type: 'cone', a: [0, 0.03, 0], b: [0, -0.04, 0], ra: 0.022, rb: 0.006, color: '$tips', material: 'skin' }],
  },
};
