'use strict';
// SCRAPLING — junk gremlin minion (ENEMIES_BOSSES.md §1.1). "Walking dustbin": a knee-high
// biped built from cannery scraps, trash-can lid in the left hand, pipe over the right shoulder,
// one glowing eye behind a bottle-cap goggle. Deliberately low-detail: 6 colours, <= 2k tris.
const P = { tin: '#A7A9A0', rust: '#8C3B2B', eye: '#FFD23F', dark: '#3A3A3A', lid: '#8E918C', cap: '#C9A227' };

module.exports = {
  id: 'npc_scrapling',
  creature: 'game/content/core/minions/npc_scrapling.json',
  out: 'creatures/npc_scrapling.glb',
  resolution: 0.009,
  target_tris: 1900,
  blend: 0.015,
  palette: P,
  default_color: '$tin',
  materials: {
    skin: { roughness: 0.6, metallic: 0.5 },      // dented tin
    rust: { roughness: 0.9, metallic: 0.1 },
    glow: { roughness: 0.4, metallic: 0, emissive: '#FFD23F' },
    eye: { roughness: 0.3, metallic: 0 },
  },
  parts: [
    // body: a tin can with a dent and a rust band
    { type: 'cylinder', seg: 'torso', a: [0, 0.38, 0], b: [0, 0.66, 0], r: 0.15, round: 0.02, color: '$tin', name: 'can', blend: 0.01 },
    { type: 'sphere', seg: 'torso', c: [0.17, 0.5, 0.06], r: 0.05, color: '$tin', name: 'can', op: 'subtract', blend: 0.01 },
    { type: 'torus', seg: 'torso', c: [0, 0.62, 0], axis: [0, 1, 0], R: 0.15, r: 0.014, color: '$rust', material: 'rust', name: 'rim', op: 'sharp', blend: 0 },
    { type: 'torus', seg: 'torso', c: [0, 0.4, 0], axis: [0, 1, 0], R: 0.15, r: 0.014, color: '$rust', material: 'rust', name: 'rim', op: 'sharp', blend: 0 },
    // head: a smaller can with a bottle-cap goggle and one glowing eye
    { type: 'cylinder', seg: 'head', a: [0, 0.68, 0.02], b: [0, 0.88, 0.02], r: 0.1, round: 0.02, color: '$tin', name: 'head', blend: 0.012 },
    { type: 'torus', seg: 'head', c: [0.03, 0.79, 0.11], axis: [0, 0, 1], R: 0.04, r: 0.014, color: '$cap', material: 'rust', name: 'goggle', op: 'sharp', blend: 0 },
    { type: 'sphere', seg: 'head', c: [0.03, 0.79, 0.11], r: 0.03, color: '$eye', material: 'glow', glow: 1.0, name: 'eye', op: 'sharp', blend: 0 },
    { type: 'box', seg: 'head', c: [-0.05, 0.79, 0.11], size: [0.05, 0.04, 0.02], round: 0.008, color: '$dark', name: 'eye_patch', op: 'sharp', blend: 0 },
    { type: 'box', seg: 'head', c: [0, 0.72, 0.11], size: [0.1, 0.012, 0.02], color: '$dark', paint: true, name: 'mouth' },
    { type: 'box', seg: 'head', c: [0, 0.9, 0.0], size: [0.06, 0.06, 0.03], round: 0.01, color: '$rust', material: 'rust', name: 'tab', blend: 0.006 },
    // arms: tin tubes
    { type: 'capsule', seg: 'arm_l', a: [0.2, 0.58, 0.03], b: [0.26, 0.36, 0.14], r: 0.035, color: '$tin', name: 'arm', blend: 0.012 },
    { type: 'capsule', seg: 'arm_r', a: [-0.2, 0.58, 0.03], b: [-0.26, 0.38, 0.1], r: 0.035, color: '$tin', name: 'arm', blend: 0.012 },
    { type: 'sphere', seg: 'arm_l', c: [0.19, 0.6, 0.02], r: 0.045, color: '$rust', material: 'rust', name: 'shoulder', blend: 0.01 },
    { type: 'sphere', seg: 'arm_r', c: [-0.19, 0.6, 0.02], r: 0.045, color: '$rust', material: 'rust', name: 'shoulder', blend: 0.01 },
    // trash-can lid held out front (left) with a handle; pipe over the right shoulder
    { type: 'cylinder', seg: 'arm_l', a: [0.12, 0.45, 0.22], b: [0.12, 0.45, 0.25], r: 0.17, round: 0.01, color: '$lid', name: 'lid', op: 'sharp', blend: 0 },
    { type: 'torus', seg: 'arm_l', c: [0.12, 0.45, 0.25], axis: [0, 0, 1], R: 0.16, r: 0.012, color: '$rust', material: 'rust', name: 'lid_rim', op: 'sharp', blend: 0 },
    { type: 'sphere', seg: 'arm_l', c: [0.12, 0.45, 0.26], r: 0.03, color: '$dark', name: 'lid_boss', op: 'sharp', blend: 0 },
    { type: 'capsule', seg: 'arm_l', a: [0.26, 0.36, 0.14], b: [0.12, 0.45, 0.2], r: 0.02, color: '$dark', name: 'lid_handle', blend: 0.01 },
    { type: 'cylinder', seg: 'arm_r', a: [-0.27, 0.36, 0.12], b: [-0.3, 0.95, -0.15], r: 0.025, round: 0.006, color: '$dark', name: 'pipe', blend: 0.008 },
    { type: 'cylinder', seg: 'arm_r', a: [-0.298, 0.9, -0.13], b: [-0.302, 0.96, -0.155], r: 0.034, round: 0.006, color: '$rust', material: 'rust', name: 'pipe_end', op: 'sharp', blend: 0 },
    // legs and tin-can feet
    { type: 'capsule', seg: 'thigh_l', a: [0.09, 0.3, 0], b: [0.1, 0.17, 0.03], r: 0.04, color: '$rust', material: 'rust', name: 'leg', mirror: true, blend: 0.012 },
    { type: 'capsule', seg: 'shin_l', a: [0.1, 0.15, 0.03], b: [0.1, 0.06, 0.0], r: 0.035, color: '$tin', name: 'leg', mirror: true, blend: 0.012 },
    { type: 'box', seg: 'shin_l', c: [0.1, 0.03, 0.05], size: [0.09, 0.05, 0.16], round: 0.015, color: '$dark', name: 'foot', mirror: true, blend: 0.008 },
  ],
  paints: [
    { type: 'spots', target: { zones: ['can', 'head'] }, cell: 0.1, radius: 0.025, density: 0.5, seed: 4, color: '$rust' },
  ],
  gore: {
    // the lid flies off
    resolution: 0.005, target_tris: 300,
    parts: [
      { type: 'cylinder', a: [0, -0.012, 0], b: [0, 0.012, 0], r: 0.17, round: 0.008, color: '$lid', material: 'skin' },
      { type: 'sphere', c: [0, 0.02, 0], r: 0.03, color: '$dark', material: 'skin', op: 'sharp' },
    ],
  },
};
