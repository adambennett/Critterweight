'use strict';
// GUSTO — the Showboat Tern (ROSTER.md §3). "Capital T with a hairdo": tall, thin, long taped
// legs, wide knife-feathered wings, bleached pompadour with a teal streak, sunglasses markings.
// Coordinates line up with game/content/core/creatures/f_gusto.json.
const H = require('../../lib/helpers');

const P = {
  primary: '#F2F2EC', shade: '#DADAD2', secondary: '#7FA4B8', tips: '#2B2B2B', accent: '#FF8A3D',
  beak_dk: '#D9702C', crest: '#35C1C9', mask: '#1E1E22', tape: '#EDE6D6', band: '#E8E4DC', eye: '#F6F6F2',
};

function wing(side) {
  const s = side > 0 ? 'l' : 'r';
  const sh = [0.22 * side, 1.24, -0.02], el = [0.62 * side, 1.3, -0.08], tip = [1.14 * side, 1.2, -0.1];
  const parts = [
    { type: 'box', seg: 'uwing_' + s, a: sh, b: el, w: 0.07, h: 0.2, round: 0.03, rot: [0, 0, 0], color: '$secondary', name: 'wing_top', blend: 0.03 },
    { type: 'sphere', seg: 'uwing_' + s, c: sh, r: 0.09, color: '$primary', name: 'shoulder', blend: 0.04 },
    { type: 'box', seg: 'lwing_' + s, a: el, b: tip, w: 0.06, h: 0.22, round: 0.025, taper: 0.45, color: '$secondary', name: 'wing_top', blend: 0.025 },
  ];
  // primary "knife" feathers trailing off the lower wing, black tips
  for (let i = 0; i < 4; i++) {
    const t = 0.25 + i * 0.22;
    const base = [el[0] + (tip[0] - el[0]) * t, 1.2 - i * 0.01, -0.13];
    const end = [base[0] + 0.1 * side, base[1] - 0.14 - i * 0.03, -0.32 - i * 0.04];
    parts.push({ type: 'cone', seg: 'lwing_' + s, a: base, b: end, ra: 0.035, rb: 0.006, color: i >= 2 ? '$tips' : '$secondary', name: 'feather', blend: 0.012 });
  }
  // secondary feathers off the upper wing
  for (let i = 0; i < 3; i++) {
    const t = 0.3 + i * 0.28;
    const base = [sh[0] + (el[0] - sh[0]) * t, 1.22, -0.1];
    parts.push({ type: 'cone', seg: 'uwing_' + s, a: base, b: [base[0] + 0.03 * side, 1.1, -0.28], ra: 0.03, rb: 0.006, color: '$primary', name: 'feather', blend: 0.012 });
  }
  return parts;
}

function leg(side) {
  const s = side > 0 ? 'l' : 'r';
  const hip = [0.12 * side, 0.92, 0], knee = [0.13 * side, 0.52, -0.08], ankle = [0.14 * side, 0.08, 0.02];
  const parts = [
    { type: 'ellipsoid', seg: 'thigh_' + s, c: [0.13 * side, 0.84, -0.01], r: [0.08, 0.12, 0.09], color: '$primary', name: 'thigh_feathers', blend: 0.04 },
    { type: 'cone', seg: 'thigh_' + s, a: hip, b: knee, ra: 0.055, rb: 0.038, color: '$accent', name: 'leg', blend: 0.02 },
    { type: 'sphere', seg: 'thigh_' + s, c: knee, r: 0.05, color: '$beak_dk', name: 'knee', blend: 0.012 },
    { type: 'cone', seg: 'shin_' + s, a: knee, b: ankle, ra: 0.036, rb: 0.03, color: '$accent', name: 'leg', blend: 0.015 },
    H.wrap({ seg: 'shin_' + s, a: [0.135 * side, 0.4, -0.05], b: [0.14 * side, 0.2, -0.005], r: 0.04, turns: 4, band: 0.012, tilt: 8, color: '$tape', name: 'tape' }),
  ];
  // three forward toes and a back toe
  const toes = [[0.0, 0.26], [0.09, 0.22], [-0.09, 0.22]];
  for (const [dx, dz] of toes) {
    parts.push({ type: 'cone', seg: 'shin_' + s, a: [ankle[0], 0.035, ankle[2]], b: [ankle[0] + dx, 0.025, ankle[2] + dz], ra: 0.028, rb: 0.012, color: '$accent', name: 'toe', blend: 0.012 });
    parts.push({ type: 'cone', seg: 'shin_' + s, a: [ankle[0] + dx * 0.95, 0.03, ankle[2] + dz * 0.95], b: [ankle[0] + dx * 1.15, 0.015, ankle[2] + dz * 1.18], ra: 0.012, rb: 0.004, color: '$tips', name: 'talon', blend: 0.005 });
  }
  parts.push({ type: 'cone', seg: 'shin_' + s, a: [ankle[0], 0.035, ankle[2]], b: [ankle[0], 0.025, ankle[2] - 0.11], ra: 0.024, rb: 0.009, color: '$accent', name: 'toe', blend: 0.012 });
  return parts;
}

module.exports = {
  id: 'f_gusto',
  creature: 'game/content/core/creatures/f_gusto.json',
  out: 'creatures/f_gusto.glb',
  resolution: 0.0095,
  target_tris: 12000,
  blend: 0.035,
  palette: P,
  materials: {
    skin: { roughness: 0.8, metallic: 0 },      // soft matte feathers
    beak: { roughness: 0.35, metallic: 0 },
    cloth: { roughness: 0.92, metallic: 0 },
    eye: { roughness: 0.25, metallic: 0 },
    team: { roughness: 0.85, metallic: 0 },
  },
  parts: [
    // ---- torso: egg body with a puffed chest ----
    { type: 'ellipsoid', seg: 'torso', c: [0, 1.1, 0], r: [0.21, 0.27, 0.24], color: '$primary', name: 'body', blend: 0.05 },
    { type: 'ellipsoid', seg: 'torso', c: [0, 1.16, 0.1], r: [0.17, 0.18, 0.17], color: '$primary', name: 'body', blend: 0.05 },
    // ---- neck + head + beak ----
    { type: 'cone', seg: 'neck', a: [0, 1.3, 0.1], b: [0, 1.58, 0.14], ra: 0.085, rb: 0.07, color: '$primary', name: 'neck', blend: 0.05 },
    { type: 'sphere', seg: 'head', c: [0, 1.7, 0.17], r: 0.15, color: '$primary', name: 'head', blend: 0.04 },
    { type: 'cone', seg: 'head', a: [0, 1.665, 0.27], b: [0, 1.635, 0.55], ra: 0.058, rb: 0.012, color: '$accent', material: 'beak', name: 'beak', blend: 0.012 },
    { type: 'cone', seg: 'head', a: [0, 1.635, 0.27], b: [0, 1.62, 0.48], ra: 0.045, rb: 0.01, color: '$beak_dk', material: 'beak', name: 'beak_lower', blend: 0.012 },
    { type: 'box', seg: 'head', c: [0, 1.645, 0.36], size: [0.09, 0.008, 0.2], color: '$tips', paint: true, name: 'beak_line' },
    // sunglasses-shaped black markings with white eyes inside
    { type: 'ellipsoid', seg: 'head', c: [0.085, 1.74, 0.27], r: [0.065, 0.045, 0.06], color: '$mask', paint: true, name: 'mask', mirror: true },
    { type: 'box', seg: 'head', c: [0, 1.745, 0.3], size: [0.07, 0.03, 0.06], color: '$mask', paint: true, name: 'mask_bridge' },
    H.eye({ seg: 'head', c: [0.075, 1.74, 0.27], r: 0.03, dir: [0.35, 0.05, 1], white: '$eye', pupil: '$tips', pupil_r: 0.013, material: 'eye', shine: false }),
    H.eye({ seg: 'head', c: [-0.075, 1.74, 0.27], r: 0.03, dir: [-0.35, 0.05, 1], white: '$eye', pupil: '$tips', pupil_r: 0.013, material: 'eye', shine: false }),
    // pompadour: a bleached quiff swept up and back with a teal streak
    { type: 'ellipsoid', seg: 'head', c: [0, 1.86, 0.12], r: [0.11, 0.1, 0.18], rot: [-28, 0, 0], color: '$primary', name: 'crest', blend: 0.03 },
    { type: 'ellipsoid', seg: 'head', c: [0, 1.9, 0.0], r: [0.08, 0.07, 0.13], rot: [-45, 0, 0], color: '$primary', name: 'crest', blend: 0.03 },
    { type: 'box', seg: 'head', c: [0.03, 1.9, 0.08], size: [0.035, 0.2, 0.36], rot: [-28, 0, 0], color: '$crest', paint: true, name: 'streak' },
    // ---- wings, legs, tail ----
    wing(1), wing(-1),
    leg(1), leg(-1),
    H.crest({ seg: 'tail', a: [-0.05, 0.98, -0.22], b: [0.05, 0.98, -0.22], count: 3, h0: 0.3, h1: 0.3, up: [0, -0.25, -1], ra: 0.035, rb: 0.008, color: '$primary', name: 'tail_feather', blend: 0.012 }),
    { type: 'ellipsoid', seg: 'tail', c: [0, 0.99, -0.2], r: [0.09, 0.06, 0.1], color: '$primary', name: 'tail', blend: 0.04 },
  ],
  paints: [
    { type: 'facing', target: { zones: ['wing_top'] }, dir: [0, -1, 0], start: 0.2, end: 0.8, color: '$primary', strength: 1.0 },
    { type: 'facing', target: { zones: ['body', 'neck', 'head'] }, dir: [0, 1, 0], start: 0.3, end: 0.95, color: '$shade', strength: 0.5 },
    { type: 'band', target: { zones: ['neck'] }, axis: [0, 1, 0], center: 1.42, width: 0.06, color: '$band', material: 'team' },
    { type: 'edge', target: { zones: ['feather'] }, width: 0.01, lighten: 0.3 },
  ],
  gore: {
    // three tail feathers burst out
    resolution: 0.004, target_tris: 360,
    parts: [
      { type: 'cone', a: [0, 0, -0.07], b: [0, 0.01, 0.07], ra: 0.025, rb: 0.006, color: '$primary', material: 'skin' },
      { type: 'cone', a: [0.03, 0, -0.06], b: [0.05, 0.005, 0.06], ra: 0.02, rb: 0.005, color: '$primary', material: 'skin' },
      { type: 'cone', a: [-0.03, 0, -0.06], b: [-0.05, 0.005, 0.06], ra: 0.02, rb: 0.005, color: '$secondary', material: 'skin' },
    ],
  },
};
