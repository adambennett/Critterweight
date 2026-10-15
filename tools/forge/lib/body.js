'use strict';
// Reads a creature JSON (game/content/.../*.json) and returns the bone list the forge skins
// against: one bone per body segment, bone name = segment id, bind translation = segment pivot
// (fighter rest space, already multiplied by the body's `scale`). Parents are kept so the
// glb skeleton mirrors the body hierarchy (joint nodes are still written as a flat list).

const fs = require('fs');
const path = require('path');

function loadCreatureBones(file, repoRoot) {
  const full = path.isAbsolute(file) ? file : path.join(repoRoot, file);
  const json = JSON.parse(fs.readFileSync(full, 'utf8'));
  const body = json.body;
  if (!body || !Array.isArray(body.segments)) throw new Error(file + ': no body.segments');
  const scale = body.scale || 1.0;
  const bones = body.segments.map((s, i) => ({
    id: s.id,
    index: i,
    parent: s.parent || null,
    pivot: (s.pivot || [0, 0, 0]).map((x) => x * scale),
    part: s.part || 'core',
    shapes: (s.shapes || (s.shape ? [s.shape] : [])).map((sh) => scaleShape(sh, scale)),
  }));
  return { bones, creature: json, scale, file: full };
}

function scaleShape(sh, k) {
  const o = Object.assign({}, sh);
  for (const key of ['a', 'b', 'center', 'size']) if (o[key]) o[key] = o[key].map((x) => x * k);
  if (o.radius) o.radius *= k;
  return o;
}

// Bones for definitions without a creature file (hub NPCs, props): either `def.bones` or a
// single root bone at the origin.
function inlineBones(def) {
  const list = def.bones && def.bones.length ? def.bones : [{ id: 'root', pivot: [0, 0, 0] }];
  return list.map((b, i) => ({ id: b.id, index: i, parent: b.parent || null, pivot: b.pivot || [0, 0, 0], part: b.part || 'core', shapes: [] }));
}

// Mirror a segment id across the body's symmetry plane: _l <-> _r, _fl <-> _fr, _bl <-> _br.
function mirrorSegId(id) {
  const m = id.match(/^(.*)_(l|r|fl|fr|bl|br)$/);
  if (!m) return id;
  const swap = { l: 'r', r: 'l', fl: 'fr', fr: 'fl', bl: 'br', br: 'bl' };
  return m[1] + '_' + swap[m[2]];
}

module.exports = { loadCreatureBones, inlineBones, mirrorSegId };
