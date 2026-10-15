'use strict';
// GRANNY HAYMAKER — possum head coach (HUB.md): 4 feet tall, tracksuit, one gold tooth. Gruff,
// warm, bare-knuckle champ of the cannery era. Pose: fists half up, chin down, weight forward.
const H = require('../../lib/helpers');
const C = require('./_hub_common');

const P = { fur: '#9C9A96', fur_dk: '#6F6D6A', face: '#EDE8E0', nose: '#D98CA0', suit: '#5B3F8C', stripe: '#F2F2EC', tooth: '#C9A227', eye: '#F6F4EE', pupil: '#1C1A1A', tail: '#C9B8A8' };

module.exports = {
  id: 'hub_granny_haymaker',
  out: 'hub/granny_haymaker.glb',
  resolution: 0.009,
  target_tris: 7000,
  blend: 0.035,
  palette: P,
  default_color: '$fur',
  materials: C.materials(),
  parts: [
    // tracksuit body, hunched forward
    C.torso({ y: 0.72, w: 0.24, h: 0.26, d: 0.22, color: '$suit', material: 'cloth' }),
    { type: 'box', c: [0, 0.74, 0.19], size: [0.012, 0.4, 0.08], color: '$stripe', paint: true, name: 'zip' },
    C.legs({ x: 0.1, hip: 0.5, r: 0.085, color: '$suit', material: 'cloth', foot: '$stripe', foot_material: 'cloth' }),
    { type: 'box', c: [0.1, 0.3, 0.0], size: [0.03, 0.3, 0.2], color: '$stripe', paint: true, name: 'leg_stripe', mirror: true },
    C.arms({ sx: 0.26, sy: 0.9, ex: 0.36, ey: 0.68, ez: 0.1, hx: 0.22, hy: 0.86, hz: 0.3, r: 0.07, color: '$suit', material: 'cloth', hand: '$face', hand_scale: 1.3 }),
    // possum head: long pale snout, pink nose, round ears, beady eyes, gold tooth
    { type: 'sphere', c: [0, 1.08, 0.08], r: 0.15, color: '$fur', material: 'fur', name: 'head', blend: 0.04 },
    { type: 'cone', a: [0, 1.04, 0.14], b: [0, 0.98, 0.36], ra: 0.11, rb: 0.035, color: '$face', material: 'fur', name: 'snout', blend: 0.03 },
    { type: 'sphere', c: [0, 0.985, 0.37], r: 0.03, color: '$nose', name: 'nose', op: 'sharp', blend: 0.004 },
    { type: 'ellipsoid', c: [0, 1.1, 0.14], r: [0.11, 0.1, 0.1], color: '$face', paint: true, name: 'mask' },
    { type: 'sphere', c: [0.12, 1.2, 0.0], r: 0.055, color: '$fur_dk', material: 'fur', name: 'ear', mirror: true, blend: 0.015 },
    { type: 'sphere', c: [0.12, 1.2, 0.015], r: 0.035, color: '$nose', paint: true, name: 'ear_in', mirror: true },
    H.eye({ c: [0.06, 1.1, 0.2], r: 0.03, dir: [0.3, -0.1, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.016, material: 'eye', lid: 0.45, lid_color: '$fur',
      brow: { a: [0.02, 1.14, 0.22], b: [0.1, 1.15, 0.2], w: 0.025, h: 0.015, color: '$fur_dk' } }),
    H.eye({ c: [-0.06, 1.1, 0.2], r: 0.03, dir: [-0.3, -0.1, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.016, material: 'eye', lid: 0.45, lid_color: '$fur',
      brow: { a: [-0.02, 1.14, 0.22], b: [-0.1, 1.15, 0.2], w: 0.025, h: 0.015, color: '$fur_dk' } }),
    { type: 'box', c: [0, 0.96, 0.3], size: [0.1, 0.01, 0.1], color: '#4A2A30', paint: true, name: 'mouth' },
    { type: 'box', c: [0.025, 0.945, 0.32], size: [0.02, 0.02, 0.015], round: 0.004, color: '$tooth', material: 'gold', name: 'gold_tooth', op: 'sharp', blend: 0 },
    // hair curlers... no: a grey bun and whisker bristles
    { type: 'sphere', c: [0, 1.22, -0.04], r: 0.06, color: '$fur_dk', material: 'fur', name: 'bun', blend: 0.015 },
    { type: 'cone', a: [0.06, 1.0, 0.3], b: [0.2, 1.02, 0.28], ra: 0.006, rb: 0.002, color: '$stripe', name: 'whisker', mirror: true, blend: 0.003, op: 'sharp' },
    // skinny possum tail curling behind
    { type: 'cone', a: [0, 0.55, -0.2], b: [0, 0.3, -0.5], ra: 0.035, rb: 0.012, color: '$tail', name: 'tail', blend: 0.03 },
  ],
  paints: [
    { type: 'stripes', target: { zones: ['arm'] }, axis: [1, 0, 0], period: 0.08, duty: 0.25, color: '$stripe' },
  ],
};
