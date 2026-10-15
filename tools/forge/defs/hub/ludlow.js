'use strict';
// LUDLOW — elderly walrus janitor (HUB.md): mop, ring-crew jacket from decades ago, slow and
// kind. Pose: leaning on the mop, head tilted, one flipper on the hip.
const H = require('../../lib/helpers');
const C = require('./_hub_common');

const P = { hide: '#8C6E58', hide_lt: '#B89A82', jacket: '#2B3550', patch: '#C9A227', tusk: '#EDE6D6', eye: '#F6F4EE', pupil: '#2A1F18', mop: '#B08A3E', mop_head: '#D8D0BC', bucket: '#5B6168', whisker: '#D8D0BC' };

module.exports = {
  id: 'hub_ludlow',
  out: 'hub/ludlow.glb',
  resolution: 0.011,
  target_tris: 9000,
  blend: 0.045,
  palette: P,
  default_color: '$hide',
  materials: C.materials(),
  parts: [
    // big blubbery body in an old ring-crew jacket
    { type: 'ellipsoid', c: [0, 0.85, 0], r: [0.42, 0.52, 0.38], color: '$jacket', material: 'cloth', name: 'jacket', blend: 0.06 },
    { type: 'ellipsoid', c: [0, 0.4, 0.02], r: [0.4, 0.3, 0.36], color: '$hide', name: 'belly', blend: 0.06 },
    { type: 'box', c: [0.2, 1.1, 0.33], size: [0.14, 0.1, 0.02], round: 0.01, color: '$patch', material: 'cloth', name: 'patch', op: 'sharp', blend: 0 },
    { type: 'box', c: [0, 0.95, 0.37], size: [0.016, 0.5, 0.04], color: '$patch', paint: true, name: 'zip' },
    // flippers: left on the hip, right holding the mop
    { type: 'cone', a: [0.4, 1.0, 0.04], b: [0.5, 0.62, 0.12], ra: 0.1, rb: 0.09, color: '$jacket', material: 'cloth', name: 'sleeve', blend: 0.04 },
    { type: 'ellipsoid', c: [0.46, 0.56, 0.16], r: [0.08, 0.05, 0.14], rot: [0, 30, 0], color: '$hide', name: 'flipper', blend: 0.03 },
    { type: 'cone', a: [-0.4, 1.0, 0.04], b: [-0.56, 0.9, 0.26], ra: 0.1, rb: 0.09, color: '$jacket', material: 'cloth', name: 'sleeve', blend: 0.04 },
    { type: 'ellipsoid', c: [-0.6, 0.9, 0.32], r: [0.08, 0.06, 0.13], rot: [0, -20, 0], color: '$hide', name: 'flipper', blend: 0.03 },
    // rear flippers splayed on the floor
    { type: 'ellipsoid', c: [0.22, 0.05, 0.3], r: [0.14, 0.04, 0.22], rot: [0, 15, 0], color: '$hide', name: 'flipper', blend: 0.03, mirror: true },
    // head: broad walrus face, drooping whisker pad, tusks, small tired eyes, a cap
    { type: 'sphere', c: [0, 1.45, 0.12], r: 0.26, color: '$hide', name: 'head', blend: 0.06 },
    { type: 'ellipsoid', c: [0, 1.32, 0.3], r: [0.22, 0.14, 0.16], color: '$hide_lt', name: 'muzzle', blend: 0.04 },
    { type: 'cone', a: [0.1, 1.26, 0.36], b: [0.11, 0.98, 0.38], ra: 0.035, rb: 0.012, color: '$tusk', material: 'eye', name: 'tusk', mirror: true, blend: 0.006 },
    H.bumps({ a: [-0.17, 1.3, 0.42], b: [0.17, 1.3, 0.42], count: 6, r: 0.012, color: '$whisker', name: 'whisker', blend: 0.004, jitter: 0.02, seed: 3 }),
    { type: 'sphere', c: [0, 1.38, 0.44], r: 0.045, color: '$pupil', name: 'nose', op: 'sharp', blend: 0.004 },
    H.eye({ c: [0.1, 1.5, 0.3], r: 0.035, dir: [0.3, -0.1, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.018, material: 'eye', lid: 0.5, lid_color: '$hide' }),
    H.eye({ c: [-0.1, 1.5, 0.3], r: 0.035, dir: [-0.3, -0.1, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.018, material: 'eye', lid: 0.5, lid_color: '$hide' }),
    { type: 'cylinder', a: [0, 1.6, 0.08], b: [0, 1.72, 0.08], r: 0.2, round: 0.03, color: '$jacket', material: 'cloth', name: 'cap', blend: 0.015 },
    { type: 'box', c: [0, 1.62, 0.3], size: [0.3, 0.02, 0.18], round: 0.01, color: '$jacket', material: 'cloth', name: 'cap', blend: 0.01 },
    // the mop (and the bucket) — the human-scale object he carries
    { type: 'cylinder', a: [-0.62, 0.1, 0.3], b: [-0.62, 1.7, 0.3], r: 0.02, round: 0.005, color: '$mop', material: 'wood', name: 'mop', op: 'sharp', blend: 0 },
    H.bumps({ a: [-0.72, 0.1, 0.22], b: [-0.52, 0.1, 0.38], count: 6, r: 0.03, color: '$mop_head', material: 'cloth', name: 'mop_head', blend: 0.02, jitter: 0.05, seed: 7 }),
    { type: 'cone', a: [-0.62, 0.3, 0.3], b: [-0.62, 0.06, 0.3], ra: 0.05, rb: 0.1, color: '$mop_head', material: 'cloth', name: 'mop_head', blend: 0.03 },
    { type: 'cylinder', a: [0.75, 0.0, 0.1], b: [0.75, 0.3, 0.1], r: 0.16, round: 0.01, color: '$bucket', material: 'metal', name: 'bucket', op: 'sharp', blend: 0 },
    { type: 'cylinder', a: [0.75, 0.22, 0.1], b: [0.75, 0.32, 0.1], r: 0.13, op: 'subtract', blend: 0.0, name: 'bucket_hole' },
  ],
  paints: [
    { type: 'facing', target: { zones: ['head', 'belly', 'muzzle'] }, dir: [0, -0.5, 1], start: 0.4, end: 0.95, color: '$hide_lt', strength: 0.6 },
    { type: 'spots', target: { zones: ['head', 'belly'] }, cell: 0.12, radius: 0.02, density: 0.4, seed: 2, color: '$hide_lt' },
  ],
};
