'use strict';
// BLISTER — a bulging sac of Glandco runoff (ENEMIES_BOSSES.md §1.2). "A lumpy egg on no legs":
// sickly green sac with darker veins and two flappy nubs. Variants recolour via art.palette.
const P = { sac: '#8BD426', vein: '#4F7F1A', hi: '#C7E66B', mouth: '#3E6414', eye: '#F6F6E8', pupil: '#1D2A10' };

module.exports = {
  id: 'npc_blister',
  creature: 'game/content/core/minions/npc_blister.json',
  out: 'creatures/npc_blister.glb',
  resolution: 0.008,
  target_tris: 1500,
  blend: 0.03,
  palette: P,
  default_color: '$sac',
  materials: {
    skin: { roughness: 0.3, metallic: 0 },
    eye: { roughness: 0.25, metallic: 0 },
  },
  parts: [
    { type: 'ellipsoid', seg: 'core', c: [0, 0.34, 0], r: [0.26, 0.32, 0.25], color: '$sac', name: 'sac', blend: 0.04 },
    { type: 'sphere', seg: 'core', c: [0.14, 0.5, 0.1], r: 0.1, color: '$sac', name: 'sac', blend: 0.05 },
    { type: 'sphere', seg: 'core', c: [-0.12, 0.2, 0.14], r: 0.11, color: '$sac', name: 'sac', blend: 0.05 },
    { type: 'sphere', seg: 'core', c: [-0.08, 0.52, -0.12], r: 0.09, color: '$sac', name: 'sac', blend: 0.05 },
    { type: 'sphere', seg: 'core', c: [0.12, 0.24, -0.16], r: 0.1, color: '$sac', name: 'sac', blend: 0.05 },
    // veins (paint decals) and a puckered mouth
    { type: 'capsule', seg: 'core', a: [0.05, 0.62, 0.1], b: [0.2, 0.4, 0.2], r: 0.012, color: '$vein', paint: true, name: 'vein' },
    { type: 'capsule', seg: 'core', a: [-0.1, 0.6, 0.0], b: [-0.24, 0.3, -0.1], r: 0.012, color: '$vein', paint: true, name: 'vein' },
    { type: 'capsule', seg: 'core', a: [0.0, 0.64, -0.1], b: [0.14, 0.38, -0.22], r: 0.012, color: '$vein', paint: true, name: 'vein' },
    { type: 'capsule', seg: 'core', a: [-0.2, 0.44, 0.14], b: [-0.05, 0.2, 0.24], r: 0.012, color: '$vein', paint: true, name: 'vein' },
    { type: 'torus', seg: 'core', c: [0, 0.3, 0.25], axis: [0, 0.2, 1], R: 0.035, r: 0.015, color: '$mouth', name: 'mouth', blend: 0.01 },
    // two small anxious eyes
    { type: 'sphere', seg: 'core', c: [0.07, 0.42, 0.23], r: 0.03, color: '$eye', material: 'eye', op: 'sharp', name: 'eye', mirror: true, blend: 0 },
    { type: 'sphere', seg: 'core', c: [0.075, 0.42, 0.255], r: 0.013, color: '$pupil', material: 'eye', op: 'sharp', name: 'pupil', mirror: true, blend: 0 },
    // flappy nubs
    { type: 'cone', seg: 'nub_l', a: [0.24, 0.48, 0], b: [0.37, 0.61, -0.04], ra: 0.055, rb: 0.03, color: '$sac', name: 'nub', mirror: true, blend: 0.03 },
  ],
  paints: [
    { type: 'facing', target: { zones: ['sac', 'nub'] }, dir: [0, 1, 0], start: 0.3, end: 1.0, color: '$hi', strength: 0.5 },
    { type: 'facing', target: { zones: ['sac'] }, dir: [0, -1, 0], start: 0.3, end: 1.0, color: '$vein', strength: 0.5 },
  ],
  gore: {
    resolution: 0.005, target_tris: 200,
    parts: [{ type: 'cone', a: [0, 0, -0.05], b: [0, 0.02, 0.06], ra: 0.05, rb: 0.028, color: '$sac', material: 'skin' }],
  },
};
