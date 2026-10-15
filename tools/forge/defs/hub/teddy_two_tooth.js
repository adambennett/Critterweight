'use strict';
// TEDDY TWO-TOOTH — rat bookie (HUB.md): tiny visor, enormous ledger, wheedling and cheerful,
// always counting. Pose: hunched over the ledger held against his chest, one hand raised.
const H = require('../../lib/helpers');
const C = require('./_hub_common');

const P = { fur: '#7A6A5E', fur_lt: '#C8B8A6', ear: '#D98CA0', vest: '#8C3B2B', shirt: '#EDE6D6', visor: '#2E8B57', ledger: '#4A3F33', pages: '#EDE6D6', tooth: '#F2EFE4', eye: '#F6F4EE', pupil: '#1C1A1A', tail: '#D9A8A0' };

module.exports = {
  id: 'hub_teddy_two_tooth',
  out: 'hub/teddy_two_tooth.glb',
  resolution: 0.008,
  target_tris: 7000,
  blend: 0.03,
  palette: P,
  default_color: '$fur',
  materials: C.materials({ visor: { roughness: 0.2, metallic: 0.1 } }),
  parts: [
    // small hunched rat in a vest over a shirt
    { type: 'ellipsoid', c: [0, 0.56, 0.0], r: [0.17, 0.22, 0.16], color: '$vest', material: 'cloth', name: 'vest', blend: 0.04 },
    { type: 'ellipsoid', c: [0, 0.54, 0.05], r: [0.13, 0.2, 0.14], color: '$shirt', material: 'cloth', name: 'shirt', blend: 0.03, clip: [{ p: [0, 0.54, 0.06], n: [0, 0, -1] }] },
    C.legs({ x: 0.07, hip: 0.36, r: 0.05, color: '$fur', material: 'fur', foot: '$fur_lt' }),
    // arms: left holds the ledger, right raised with a finger up
    { type: 'cone', a: [0.17, 0.7, 0.02], b: [0.2, 0.5, 0.2], ra: 0.05, rb: 0.045, color: '$shirt', material: 'cloth', name: 'sleeve', blend: 0.03 },
    { type: 'sphere', c: [0.18, 0.5, 0.24], r: 0.05, color: '$fur_lt', material: 'fur', name: 'hand', blend: 0.02 },
    { type: 'cone', a: [-0.17, 0.7, 0.02], b: [-0.3, 0.9, 0.12], ra: 0.05, rb: 0.045, color: '$shirt', material: 'cloth', name: 'sleeve', blend: 0.03 },
    { type: 'sphere', c: [-0.32, 0.94, 0.14], r: 0.05, color: '$fur_lt', material: 'fur', name: 'hand', blend: 0.02 },
    { type: 'capsule', a: [-0.32, 0.96, 0.14], b: [-0.33, 1.06, 0.15], r: 0.016, color: '$fur_lt', material: 'fur', name: 'finger', blend: 0.01 },
    // the enormous ledger
    { type: 'box', c: [0.1, 0.5, 0.26], size: [0.36, 0.46, 0.07], round: 0.012, rot: [0, 0, 8], color: '$ledger', material: 'cloth', name: 'ledger', op: 'sharp', blend: 0 },
    { type: 'box', c: [0.1, 0.5, 0.26], size: [0.33, 0.42, 0.05], round: 0.004, rot: [0, 0, 8], color: '$pages', material: 'cloth', name: 'pages', op: 'sharp', blend: 0 },
    { type: 'box', c: [0.1, 0.5, 0.3], size: [0.33, 0.42, 0.012], round: 0.004, rot: [0, 0, 8], color: '$ledger', material: 'cloth', name: 'ledger', op: 'sharp', blend: 0 },
    { type: 'box', c: [0.1, 0.56, 0.31], size: [0.2, 0.012, 0.01], rot: [0, 0, 8], color: '$visor', paint: true, name: 'title' },
    // rat head: pointed snout, big round ears, two big front teeth, beady eyes, green visor
    { type: 'sphere', c: [0, 0.88, 0.06], r: 0.13, color: '$fur', material: 'fur', name: 'head', blend: 0.035 },
    { type: 'cone', a: [0, 0.84, 0.12], b: [0, 0.78, 0.32], ra: 0.09, rb: 0.025, color: '$fur', material: 'fur', name: 'snout', blend: 0.03 },
    { type: 'sphere', c: [0, 0.785, 0.33], r: 0.022, color: '$ear', name: 'nose', op: 'sharp', blend: 0.004 },
    { type: 'box', c: [0.016, 0.74, 0.29], size: [0.022, 0.05, 0.012], round: 0.004, color: '$tooth', material: 'eye', name: 'tooth', op: 'sharp', blend: 0, mirror: true },
    { type: 'sphere', c: [0.13, 0.98, -0.02], r: 0.07, color: '$fur', material: 'fur', name: 'ear', mirror: true, blend: 0.012 },
    { type: 'sphere', c: [0.13, 0.98, 0.0], r: 0.045, color: '$ear', paint: true, name: 'ear_in', mirror: true },
    H.eye({ c: [0.05, 0.9, 0.17], r: 0.028, dir: [0.3, 0, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.015, material: 'eye' }),
    H.eye({ c: [-0.05, 0.9, 0.17], r: 0.028, dir: [-0.3, 0, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.015, material: 'eye' }),
    { type: 'torus', c: [0, 0.97, 0.06], axis: [0, 1, 0], R: 0.13, r: 0.012, color: '$visor', material: 'visor', name: 'visor', op: 'sharp', blend: 0 },
    { type: 'box', a: [0, 0.97, 0.12], b: [0, 0.95, 0.3], w: 0.26, h: 0.012, round: 0.004, taper: 0.7, color: '$visor', material: 'visor', name: 'visor', op: 'sharp', blend: 0 },
    H.bumps({ a: [-0.1, 0.8, 0.26], b: [0.1, 0.8, 0.26], count: 4, r: 0.006, color: '$fur_lt', name: 'whisker', blend: 0.003 }),
    // long pink tail
    { type: 'cone', a: [0, 0.4, -0.14], b: [0.25, 0.08, -0.4], ra: 0.025, rb: 0.008, color: '$tail', name: 'tail', blend: 0.02 },
  ],
  paints: [
    { type: 'facing', target: { zones: ['head', 'snout', 'leg'] }, dir: [0, -0.4, 1], start: 0.4, end: 0.95, color: '$fur_lt', strength: 0.6 },
  ],
};
