'use strict';
// CONDUIT — the Live Wire (ENEMIES_BOSSES.md §2.2). "A tall S with a hazard-striped body and a
// plug on the tail": insulation-black cable serpent, yellow warning stripes, copper head crest,
// cyan-white glowing seams between segments, a three-pin plug for a tail.
// Coordinates line up with game/content/core/bosses/boss_conduit.json.
const H = require('../../lib/helpers');

const P = {
  primary: '#1E1E24', rubber_hi: '#34343C', stripe: '#F7E04A', copper: '#B87333', copper_dk: '#7E4E22', seam: '#CFF4FF',
  eye: '#CFF4FF', pupil: '#0A1A22', plug: '#2C2C33', pin: '#C9A227', teeth: '#E8F6FF',
};

// glowing seam ring where two body segments meet
function seam(seg, c, axis, R) {
  return { type: 'torus', seg, c, axis, R, r: 0.035, color: '$seam', material: 'glow', glow: 0.9, name: 'seam', op: 'sharp', blend: 0 };
}

module.exports = {
  id: 'boss_conduit',
  creature: 'game/content/core/bosses/boss_conduit.json',
  out: 'creatures/boss_conduit.glb',
  resolution: 0.02,
  target_tris: 16000,
  blend: 0.06,
  palette: P,
  materials: {
    skin: { roughness: 0.5, metallic: 0.05 },     // insulation rubber
    copper: { roughness: 0.35, metallic: 0.85 },
    glow: { roughness: 0.3, metallic: 0, emissive: '#CFF4FF' },
    eye: { roughness: 0.2, metallic: 0 },
    plug: { roughness: 0.6, metallic: 0.3 },
  },
  parts: [
    // ---- cable body ----
    { type: 'cone', seg: 'body4', a: [0, 0.31, -0.68], b: [0, 0.42, -0.02], ra: 0.26, rb: 0.27, color: '$primary', name: 'cable', blend: 0.08 },
    { type: 'cone', seg: 'body4', a: [0, 0.42, 0.0], b: [0, 1.02, 0.2], ra: 0.27, rb: 0.25, color: '$primary', name: 'cable', blend: 0.08 },
    { type: 'cone', seg: 'body3', a: [0, 1.05, 0.2], b: [0, 1.68, 0.3], ra: 0.25, rb: 0.23, color: '$primary', name: 'cable', blend: 0.08 },
    { type: 'cone', seg: 'body2', a: [0, 1.7, 0.3], b: [0, 2.33, 0.26], ra: 0.23, rb: 0.21, color: '$primary', name: 'cable', blend: 0.08 },
    { type: 'cone', seg: 'body1', a: [0, 2.35, 0.25], b: [0, 2.88, 0.12], ra: 0.21, rb: 0.2, color: '$primary', name: 'cable', blend: 0.08 },
    { type: 'cone', seg: 'body5', a: [0, 0.3, -0.7], b: [0, 0.28, -1.5], ra: 0.26, rb: 0.24, color: '$primary', name: 'cable', blend: 0.08 },
    { type: 'cone', seg: 'body6', a: [0, 0.28, -1.5], b: [0, 0.28, -2.3], ra: 0.24, rb: 0.22, color: '$primary', name: 'cable', blend: 0.08 },
    { type: 'cone', seg: 'body7', a: [0, 0.28, -2.3], b: [0, 0.28, -3.1], ra: 0.22, rb: 0.18, color: '$primary', name: 'cable', blend: 0.08 },
    { type: 'cone', seg: 'plug', a: [0, 0.28, -3.1], b: [0, 0.27, -3.46], ra: 0.18, rb: 0.16, color: '$primary', name: 'cable', blend: 0.06 },
    // seams glow where the segments join
    seam('body4', [0, 1.03, 0.2], [0, 1, 0.3], 0.25), seam('body3', [0, 1.69, 0.3], [0, 1, 0.1], 0.23),
    seam('body2', [0, 2.34, 0.26], [0, 1, -0.1], 0.21), seam('body1', [0, 2.89, 0.12], [0, 1, -0.3], 0.2),
    seam('body4', [0, 0.31, -0.7], [0, 0.05, 1], 0.26), seam('body5', [0, 0.28, -1.5], [0, 0, 1], 0.24),
    seam('body6', [0, 0.28, -2.3], [0, 0, 1], 0.22), seam('body7', [0, 0.28, -3.1], [0, 0, 1], 0.19),
    // ---- head: cable terminal head with jaws, copper crest, cyan eyes ----
    { type: 'sphere', seg: 'head', c: [0, 3.05, 0.3], r: 0.27, color: '$primary', name: 'head', blend: 0.06 },
    { type: 'cone', seg: 'head', a: [0, 3.02, 0.4], b: [0, 2.93, 0.82], ra: 0.22, rb: 0.12, color: '$primary', name: 'head', blend: 0.06 },
    { type: 'cone', seg: 'head', a: [0, 2.86, 0.4], b: [0, 2.8, 0.74], ra: 0.15, rb: 0.08, color: '$primary', name: 'jaw', blend: 0.05 },
    { type: 'box', seg: 'head', c: [0, 2.885, 0.62], size: [0.34, 0.02, 0.34], color: '#06080C', paint: true, name: 'mouth' },
    { type: 'cone', seg: 'head', a: [0.09, 2.92, 0.72], b: [0.085, 2.84, 0.74], ra: 0.025, rb: 0.006, color: '$teeth', material: 'eye', name: 'fang', mirror: true, op: 'sharp', blend: 0 },
    H.eye({ seg: 'head', c: [0.17, 3.12, 0.44], r: 0.07, dir: [0.5, 0.15, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.02, material: 'glow', shine: false }),
    H.eye({ seg: 'head', c: [-0.17, 3.12, 0.44], r: 0.07, dir: [-0.5, 0.15, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.02, material: 'glow', shine: false }),
    H.crest({ seg: 'head', a: [0, 3.3, 0.3], b: [0, 3.2, -0.05], count: 4, h0: 0.22, h1: 0.14, up: [0, 1, -0.3], ra: 0.05, rb: 0.012, color: '$copper', material: 'copper', name: 'crest', blend: 0.015 }),
    { type: 'box', seg: 'head', c: [0, 3.28, 0.12], size: [0.03, 0.3, 0.42], round: 0.01, rot: [-10, 0, 0], color: '$copper', material: 'copper', name: 'crest', blend: 0.02 },
    { type: 'torus', seg: 'head', c: [0, 3.0, 0.2], axis: [0, 0.2, 1], R: 0.29, r: 0.03, color: '$copper_dk', material: 'copper', name: 'ferrule', op: 'sharp', blend: 0 },
    // ---- plug tail: housing + three pins ----
    { type: 'box', seg: 'plug', c: [0, 0.28, -3.66], size: [0.44, 0.34, 0.4], round: 0.06, color: '$plug', material: 'plug', name: 'plug', blend: 0.02 },
    { type: 'cylinder', seg: 'plug', a: [0.12, 0.24, -3.84], b: [0.12, 0.24, -4.05], r: 0.035, round: 0.008, color: '$pin', material: 'copper', name: 'pin', op: 'sharp', blend: 0 },
    { type: 'cylinder', seg: 'plug', a: [-0.12, 0.24, -3.84], b: [-0.12, 0.24, -4.05], r: 0.035, round: 0.008, color: '$pin', material: 'copper', name: 'pin', op: 'sharp', blend: 0 },
    { type: 'cylinder', seg: 'plug', a: [0, 0.36, -3.84], b: [0, 0.36, -4.05], r: 0.035, round: 0.008, color: '$pin', material: 'copper', name: 'pin', op: 'sharp', blend: 0 },
  ],
  paints: [
    // yellow hazard stripes wound along the cable
    { type: 'stripes', target: { zones: ['cable'] }, axis: [0, 0.3, 1], period: 0.5, duty: 0.3, color: '$stripe', origin: [0, 0, 0.1] },
    { type: 'facing', target: { zones: ['cable', 'head'] }, dir: [0, 1, 0], start: 0.6, end: 1.0, color: '$rubber_hi', strength: 0.5 },
  ],
  gore: {
    resolution: 0.005, target_tris: 300,
    parts: [{ type: 'cone', a: [0, 0.05, 0], b: [0, -0.05, 0], ra: 0.03, rb: 0.008, color: '$teeth', material: 'eye' }],
  },
};
