'use strict';
// JITTERS — the Battery Jelly (ROSTER.md §6). "Ball with ears": beach-ball jelly with a coil
// showing through, two stubby arms, two sparking antenna bulbs, a battery cap and nervous eyes.
// Coordinates line up with game/content/core/creatures/f_jitters.json.
const H = require('../../lib/helpers');

const P = {
  primary: '#BDEFFF', jelly_dk: '#8FD6F2', coil: '#FFF27A', secondary: '#B59CE0', arm_dk: '#9A82C8', bulbs: '#F7E04A',
  cap: '#3C4650', cap_hi: '#5A6672', eyes: '#1F2A33', white: '#FFFFFF', mouth: '#2A3A48', band: '#E6E2DA',
};

function arm(side) {
  const s = side > 0 ? 'l' : 'r';
  return [
    { type: 'cone', seg: 'arm_' + s, a: [0.33 * side, 0.48, 0.06], b: [0.6 * side, 0.44, 0.16], ra: 0.065, rb: 0.055, color: '$secondary', material: 'rubber', name: 'arm', blend: 0.03 },
    { type: 'ellipsoid', seg: 'arm_' + s, c: [0.64 * side, 0.43, 0.19], r: [0.075, 0.065, 0.08], rot: [0, -20 * side, 0], color: '$secondary', material: 'rubber', name: 'mitt', blend: 0.025 },
    { type: 'capsule', seg: 'arm_' + s, a: [0.6 * side, 0.46, 0.22], b: [0.62 * side, 0.46, 0.3], r: 0.028, color: '$arm_dk', material: 'rubber', name: 'thumb', blend: 0.015 },
  ];
}

function antenna(side) {
  const s = side > 0 ? 'l' : 'r';
  return [
    { type: 'cone', seg: 'antenna_' + s, a: [0.13 * side, 0.73, -0.02], b: [0.2 * side, 0.9, -0.04], ra: 0.03, rb: 0.018, color: '$cap', material: 'metal', name: 'stalk', blend: 0.012 },
    { type: 'sphere', seg: 'antenna_' + s, c: [0.21 * side, 0.925, -0.045], r: 0.048, color: '$bulbs', material: 'glow', glow: 0.8, name: 'bulb', blend: 0.012 },
  ];
}

module.exports = {
  id: 'f_jitters',
  creature: 'game/content/core/creatures/f_jitters.json',
  out: 'creatures/f_jitters.glb',
  resolution: 0.008,
  target_tris: 10000,
  blend: 0.03,
  palette: P,
  materials: {
    skin: { roughness: 0.18, metallic: 0 },      // jelly (glossy; translucency is faked by colour)
    rubber: { roughness: 0.8, metallic: 0 },
    metal: { roughness: 0.4, metallic: 0.6 },
    glow: { roughness: 0.3, metallic: 0, emissive: '#FFF27A' },
    eye: { roughness: 0.2, metallic: 0 },
    team: { roughness: 0.8, metallic: 0 },
  },
  parts: [
    // ---- jelly body with a slight squat ----
    { type: 'ellipsoid', seg: 'body', c: [0, 0.4, 0], r: [0.37, 0.35, 0.36], color: '$primary', name: 'body', blend: 0.04 },
    // coil "seen through" the jelly: a painted helix of three tilted rings in glow yellow
    { type: 'torus', seg: 'body', c: [0, 0.3, 0], axis: [0.15, 1, 0.1], R: 0.3, r: 0.022, color: '$coil', paint: true, glow: 0.45, name: 'coil' },
    { type: 'torus', seg: 'body', c: [0, 0.42, 0], axis: [-0.12, 1, 0.08], R: 0.34, r: 0.022, color: '$coil', paint: true, glow: 0.45, name: 'coil' },
    { type: 'torus', seg: 'body', c: [0, 0.54, 0], axis: [0.1, 1, -0.12], R: 0.3, r: 0.022, color: '$coil', paint: true, glow: 0.45, name: 'coil' },
    // the inner coil segment itself (a small glowing core, mostly hidden; keeps the bone meaningful)
    { type: 'sphere', seg: 'coil', c: [0, 0.42, 0], r: 0.1, color: '$coil', material: 'glow', glow: 0.9, name: 'core', blend: 0.0 },
    // ---- battery cap on top ----
    { type: 'cylinder', seg: 'body', a: [0, 0.7, 0], b: [0, 0.8, 0], r: 0.085, round: 0.015, color: '$cap', material: 'metal', name: 'cap', blend: 0.012 },
    { type: 'cylinder', seg: 'body', a: [0, 0.8, 0], b: [0, 0.83, 0], r: 0.045, round: 0.008, color: '$cap_hi', material: 'metal', name: 'cap_nub', blend: 0.006 },
    { type: 'box', seg: 'body', c: [0, 0.83, 0], size: [0.05, 0.01, 0.012], color: '$coil', paint: true, name: 'plus' },
    { type: 'box', seg: 'body', c: [0, 0.83, 0], size: [0.012, 0.01, 0.05], color: '$coil', paint: true, name: 'plus' },
    // ---- face: big nervous eyes, worried brows, small wobbly mouth ----
    H.eye({ seg: 'body', c: [0.12, 0.5, 0.31], r: 0.075, dir: [0.25, 0.2, 1], white: '$white', pupil: '$eyes', pupil_r: 0.028, material: 'eye',
      brow: { a: [0.05, 0.6, 0.34], b: [0.2, 0.57, 0.3], w: 0.028, h: 0.018, color: '$arm_dk' } }),
    H.eye({ seg: 'body', c: [-0.12, 0.5, 0.31], r: 0.075, dir: [-0.25, 0.2, 1], white: '$white', pupil: '$eyes', pupil_r: 0.028, material: 'eye',
      brow: { a: [-0.05, 0.6, 0.34], b: [-0.2, 0.57, 0.3], w: 0.028, h: 0.018, color: '$arm_dk' } }),
    { type: 'box', seg: 'body', c: [0, 0.36, 0.36], size: [0.09, 0.014, 0.04], round: 0.005, rot: [0, 0, 8], color: '$mouth', paint: true, name: 'mouth' },
    // ---- arms and antennae ----
    arm(1), arm(-1), antenna(1), antenna(-1),
  ],
  paints: [
    // fake subsurface: lighter top, deeper cyan underside
    { type: 'facing', target: { zones: ['body'] }, dir: [0, -1, 0], start: 0.2, end: 0.9, color: '$jelly_dk', strength: 0.8 },
    { type: 'facing', target: { zones: ['body'] }, dir: [0, 1, 0], start: 0.5, end: 1.0, color: '$white', strength: 0.35 },
    // team band: thin equator ring
    { type: 'band', target: { zones: ['body'] }, axis: [0, 1, 0], center: 0.24, width: 0.035, color: '$band', material: 'team' },
  ],
  gore: {
    // the battery cap pops off like a champagne cork
    resolution: 0.003, target_tris: 400,
    parts: [
      { type: 'cylinder', a: [0, -0.04, 0], b: [0, 0.03, 0], r: 0.06, round: 0.01, color: '$cap', material: 'metal' },
      { type: 'cylinder', a: [0, 0.03, 0], b: [0, 0.05, 0], r: 0.03, round: 0.005, color: '$cap_hi', material: 'metal' },
    ],
  },
};
