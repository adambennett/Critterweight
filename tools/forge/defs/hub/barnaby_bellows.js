'use strict';
// BARNABY BELLOWS — pelican announcer (HUB.md): sequined jacket, gullet pouch like a megaphone,
// boundless enthusiasm. Pose: wings flung wide, beak open mid-"WELCOME", bow tie.
const H = require('../../lib/helpers');
const C = require('./_hub_common');

const P = { feather: '#F2F2EC', feather_sh: '#D4D6D0', jacket: '#B06BFF', sequin: '#FFE6FF', pouch: '#FFB27A', beak: '#FF8A3D', beak_dk: '#D9702C', eye: '#F6F4EE', pupil: '#1C1A1A', tie: '#C23A2B', legs: '#FF8A3D', mic: '#3A3A42' };

module.exports = {
  id: 'hub_barnaby_bellows',
  out: 'hub/barnaby_bellows.glb',
  resolution: 0.01,
  target_tris: 9000,
  blend: 0.04,
  palette: P,
  default_color: '$feather',
  materials: C.materials({ sequin: { roughness: 0.25, metallic: 0.4 }, beak: { roughness: 0.35, metallic: 0 } }),
  parts: [
    // plump body in a sequined jacket, white shirt front
    { type: 'ellipsoid', c: [0, 1.0, 0], r: [0.3, 0.36, 0.28], color: '$jacket', material: 'sequin', name: 'jacket', blend: 0.05 },
    { type: 'ellipsoid', c: [0, 1.0, 0.1], r: [0.14, 0.3, 0.22], color: '$feather', name: 'shirt', blend: 0.03, clip: [{ p: [0, 1.0, 0.12], n: [0, 0, -1] }] },
    { type: 'box', c: [0, 1.26, 0.27], size: [0.14, 0.05, 0.03], round: 0.012, color: '$tie', material: 'cloth', name: 'bowtie', op: 'sharp', blend: 0 },
    { type: 'sphere', c: [0, 1.26, 0.28], r: 0.022, color: '$tie', material: 'cloth', name: 'bowtie', op: 'sharp', blend: 0 },
    // wings flung wide in the sequined sleeves
    { type: 'cone', a: [0.3, 1.12, 0.0], b: [0.72, 1.3, 0.05], ra: 0.09, rb: 0.07, color: '$jacket', material: 'sequin', name: 'sleeve', mirror: true, blend: 0.04 },
    { type: 'box', a: [0.72, 1.3, 0.05], b: [1.05, 1.42, 0.08], w: 0.06, h: 0.16, round: 0.025, taper: 0.5, color: '$feather', name: 'wing', mirror: true, blend: 0.03 },
    { type: 'cone', a: [0.9, 1.33, 0.02], b: [1.0, 1.2, -0.08], ra: 0.025, rb: 0.006, color: '$feather_sh', name: 'feather', mirror: true, blend: 0.01 },
    { type: 'cone', a: [1.0, 1.37, 0.03], b: [1.12, 1.26, -0.06], ra: 0.025, rb: 0.006, color: '$feather_sh', name: 'feather', mirror: true, blend: 0.01 },
    // long orange legs with webbed feet
    { type: 'cone', a: [0.1, 0.68, 0], b: [0.11, 0.06, 0.02], ra: 0.045, rb: 0.035, color: '$legs', name: 'leg', mirror: true, blend: 0.02 },
    { type: 'box', a: [0.11, 0.03, -0.02], b: [0.11, 0.025, 0.22], w: 0.08, h: 0.03, round: 0.01, taper: 2.0, color: '$legs', name: 'foot', mirror: true, blend: 0.01 },
    // head: a huge pelican beak with a megaphone pouch, wide eyes, a slicked tuft
    { type: 'sphere', c: [0, 1.5, 0.1], r: 0.17, color: '$feather', name: 'head', blend: 0.04 },
    { type: 'cone', a: [0, 1.5, 0.2], b: [0, 1.44, 0.72], ra: 0.075, rb: 0.03, color: '$beak', material: 'beak', name: 'beak', blend: 0.015 },
    { type: 'box', a: [0, 1.36, 0.22], b: [0, 1.2, 0.68], w: 0.14, h: 0.03, round: 0.012, taper: 0.4, color: '$beak_dk', material: 'beak', name: 'beak_lower', blend: 0.015 },
    { type: 'box', a: [0, 1.36, 0.22], b: [0, 1.2, 0.68], w: 0.13, h: 0.24, round: 0.04, taper: 0.5, color: '$pouch', name: 'pouch', blend: 0.03, clip: [{ p: [0, 1.37, 0.2], n: [0, 1, 0] }] },
    H.eye({ c: [0.09, 1.56, 0.22], r: 0.045, dir: [0.35, 0.1, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.02, material: 'eye',
      brow: { a: [0.04, 1.63, 0.24], b: [0.15, 1.6, 0.2], w: 0.03, h: 0.016, color: '$feather_sh' } }),
    H.eye({ c: [-0.09, 1.56, 0.22], r: 0.045, dir: [-0.35, 0.1, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.02, material: 'eye',
      brow: { a: [-0.04, 1.63, 0.24], b: [-0.15, 1.6, 0.2], w: 0.03, h: 0.016, color: '$feather_sh' } }),
    { type: 'ellipsoid', c: [0, 1.68, 0.02], r: [0.07, 0.06, 0.12], rot: [-30, 0, 0], color: '$feather', name: 'tuft', blend: 0.02 },
    // a hand mic clipped to the jacket, because of course
    { type: 'cylinder', a: [-0.2, 1.1, 0.22], b: [-0.2, 1.24, 0.24], r: 0.016, round: 0.004, color: '$mic', material: 'metal', name: 'mic', op: 'sharp', blend: 0 },
    { type: 'sphere', c: [-0.2, 1.26, 0.245], r: 0.03, color: '$mic', material: 'metal', name: 'mic', op: 'sharp', blend: 0 },
  ],
  paints: [
    { type: 'spots', target: { zones: ['jacket', 'sleeve'] }, cell: 0.04, radius: 0.009, density: 0.8, seed: 5, color: '$sequin' },
    { type: 'facing', target: { zones: ['head', 'shirt', 'wing'] }, dir: [0, -1, 0], start: 0.3, end: 0.9, color: '$feather_sh', strength: 0.5 },
  ],
};
