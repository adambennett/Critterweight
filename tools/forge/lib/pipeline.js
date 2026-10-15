'use strict';
// The forge pipeline for one definition:
//   parts (SDF) -> voxel field -> surface nets -> QEM decimation -> gradient normals ->
//   zone/paint colours (crisp splits) -> skin weights -> glb.

const path = require('path');
const V = require('./vec');
const SDF = require('./sdf');
const { makeGrid, surfaceNets, smooth } = require('./mesher');
const { decimate } = require('./decimate');
const { makePainter } = require('./paint');
const { makeSkinner, smoothWeights } = require('./skin');
const { loadCreatureBones, inlineBones } = require('./body');
const { writeGlb } = require('./gltf');

function buildSurface(def, bones, opts, log) {
  const res = opts.res;
  const compiled = SDF.compile(def, bones, { res, skinSoft: def.skin_soft });
  const grid = makeGrid(compiled.bounds, res);
  const voxels = grid.nx * grid.ny * grid.nz;
  if (voxels > 60e6) throw new Error(`${def.id}: grid too large (${grid.nx}x${grid.ny}x${grid.nz}); raise resolution`);
  let t = Date.now();
  SDF.splat(compiled.prims, grid);
  log(`  field ${grid.nx}x${grid.ny}x${grid.nz} (${(voxels / 1e6).toFixed(2)}M voxels, ${compiled.prims.length} parts) ${Date.now() - t} ms`);
  t = Date.now();
  let mesh = surfaceNets(grid);
  if (mesh.tris.length === 0) throw new Error(`${def.id}: empty surface`);
  const rawTris = mesh.tris.length / 3;
  if (opts.smooth > 0) mesh.positions = smooth(mesh.positions, mesh.tris, opts.smooth, 0.5);
  log(`  surface nets ${mesh.positions.length / 3} verts / ${rawTris} tris ${Date.now() - t} ms`);
  const painter = makePainter(def, compiled);
  t = Date.now();
  const n0 = mesh.positions.length / 3;
  const zones = new Int32Array(n0);
  if (opts.targetTris > 0 && rawTris > opts.targetTris) {
    // Decimate against the full CRISP KEY of each dense vertex (zone group + decals + discrete
    // paint layers), so colour boundaries keep their dense-mesh edges instead of smearing
    // along long decimated triangles. Normals here only feed the paint (cheap face normals).
    const keyIds = new Map();
    const fn = require('./mesher').faceNormals(mesh.positions, mesh.tris);
    for (let i = 0; i < n0; i++) {
      const p = [mesh.positions[i * 3], mesh.positions[i * 3 + 1], mesh.positions[i * 3 + 2]];
      const info = painter.colorAt(p, [fn[i * 3], fn[i * 3 + 1], fn[i * 3 + 2]], null);
      if (!keyIds.has(info.key)) keyIds.set(info.key, keyIds.size);
      zones[i] = keyIds.get(info.key);
    }
    mesh = decimate(mesh.positions, mesh.tris, zones, opts.targetTris, { zonePenalty: def.zone_penalty });
    mesh.zones = null;
    log(`  decimated to ${mesh.positions.length / 3} verts / ${mesh.tris.length / 3} tris (${keyIds.size} colour keys) ${Date.now() - t} ms`);
  } else {
    for (let i = 0; i < n0; i++) zones[i] = painter.nearestZone([mesh.positions[i * 3], mesh.positions[i * 3 + 1], mesh.positions[i * 3 + 2]]);
    mesh.zones = zones;
  }
  return { compiled, mesh, painter, grid };
}

// Colours every vertex, splitting triangles whose corners disagree on the crisp key.
function colourMesh(def, compiled, mesh, painter, opts, log) {
  const t = Date.now();
  const n = mesh.positions.length / 3;
  const pos = mesh.positions;
  const h = opts.res * 0.5;
  const normals = new Float64Array(n * 3);
  const info = new Array(n);
  for (let i = 0; i < n; i++) {
    const p = [pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]];
    const g = SDF.gradient(compiled.prims, p, h);
    normals[i * 3] = g[0]; normals[i * 3 + 1] = g[1]; normals[i * 3 + 2] = g[2];
    info[i] = painter.colorAt(p, g, mesh.zones ? mesh.zones[i] : null);
  }
  // crisp splitting
  const outPos = Array.from(pos), outNrm = Array.from(normals), outInfo = info.slice();
  const outTris = [];
  let splits = 0;
  for (let f = 0; f < mesh.tris.length; f += 3) {
    const a = mesh.tris[f], b = mesh.tris[f + 1], c = mesh.tris[f + 2];
    if (info[a].key === info[b].key && info[a].key === info[c].key) { outTris.push(a, b, c); continue; }
    const cx = (pos[a * 3] + pos[b * 3] + pos[c * 3]) / 3, cy = (pos[a * 3 + 1] + pos[b * 3 + 1] + pos[c * 3 + 1]) / 3, cz = (pos[a * 3 + 2] + pos[b * 3 + 2] + pos[c * 3 + 2]) / 3;
    const g = SDF.gradient(compiled.prims, [cx, cy, cz], h);
    const ci = painter.colorAt([cx, cy, cz], g, null);
    const ids = [];
    for (const v of [a, b, c]) {
      // corner already matching the centroid key keeps its vertex (avoids needless duplicates)
      if (info[v].key === ci.key) { ids.push(v); continue; }
      const nv = outPos.length / 3;
      outPos.push(pos[v * 3], pos[v * 3 + 1], pos[v * 3 + 2]);
      outNrm.push(normals[v * 3], normals[v * 3 + 1], normals[v * 3 + 2]);
      const copy = Object.assign({}, ci);
      // continuous shading still evaluated at the corner so gradients stay smooth
      const own = painter.colorAt([pos[v * 3], pos[v * 3 + 1], pos[v * 3 + 2]], [normals[v * 3], normals[v * 3 + 1], normals[v * 3 + 2]], null);
      copy.color = own.key === ci.key ? own.color : ci.color;
      outInfo.push(copy);
      ids.push(nv);
    }
    outTris.push(ids[0], ids[1], ids[2]);
    splits++;
  }
  log(`  coloured ${outPos.length / 3} verts (${splits} crisp splits) ${Date.now() - t} ms`);
  return { positions: Float64Array.from(outPos), normals: Float64Array.from(outNrm), info: outInfo, tris: Int32Array.from(outTris) };
}

function skinMesh(compiled, bones, coloured, log) {
  const t = Date.now();
  const n = coloured.positions.length / 3;
  const skinner = makeSkinner(compiled, bones);
  const joints = new Uint8Array(n * 4);
  const weights = new Float32Array(n * 4);
  for (let i = 0; i < n; i++) {
    const w = skinner.weightsAt([coloured.positions[i * 3], coloured.positions[i * 3 + 1], coloured.positions[i * 3 + 2]]);
    for (let k = 0; k < 4; k++) { joints[i * 4 + k] = w.joints[k]; weights[i * 4 + k] = w.weights[k]; }
  }
  if (bones.length > 1) smoothWeights(joints, weights, coloured.tris, bones.length, n, 0.5);
  // exact normalisation (glTF requires the 4 weights to sum to 1)
  for (let i = 0; i < n; i++) {
    let s = 0;
    for (let k = 0; k < 4; k++) s += weights[i * 4 + k];
    if (s <= 0) { weights[i * 4] = 1; s = 1; }
    for (let k = 0; k < 4; k++) weights[i * 4 + k] /= s;
  }
  log(`  skinned ${n} verts ${Date.now() - t} ms`);
  return { joints, weights };
}

function packMesh(coloured, skin) {
  const n = coloured.positions.length / 3;
  const colors = new Float32Array(n * 4);
  for (let i = 0; i < n; i++) {
    const c = coloured.info[i].color;
    colors[i * 4] = c[0]; colors[i * 4 + 1] = c[1]; colors[i * 4 + 2] = c[2]; colors[i * 4 + 3] = coloured.info[i].glow || 0;
  }
  const byMat = new Map();
  for (let f = 0; f < coloured.tris.length; f += 3) {
    const a = coloured.tris[f];
    const m = coloured.info[a].material;
    if (!byMat.has(m)) byMat.set(m, []);
    byMat.get(m).push(coloured.tris[f], coloured.tris[f + 1], coloured.tris[f + 2]);
  }
  const groups = Array.from(byMat.keys()).sort().map((m) => ({ material: m, indices: byMat.get(m) }));
  return {
    positions: Float32Array.from(coloured.positions),
    normals: Float32Array.from(coloured.normals),
    colors,
    joints: skin ? skin.joints : null,
    weights: skin ? skin.weights : null,
    groups,
  };
}

function buildGore(def, opts, log) {
  const g = def.gore;
  if (!g || !g.parts) return null;
  const sub = { id: def.id + '_gore', palette: def.palette, materials: def.materials, parts: g.parts, paints: g.paints || [], blend: g.blend == null ? 0.01 : g.blend, default_color: g.color || def.default_color };
  const bones = [{ id: 'piece', index: 0, parent: null, pivot: [0, 0, 0], part: 'core', shapes: [] }];
  const gopts = { res: g.resolution || 0.004, targetTris: g.target_tris || 400, smooth: 0 };
  log('  gore piece:');
  const { compiled, mesh, painter } = buildSurface(sub, bones, gopts, log);
  const coloured = colourMesh(sub, compiled, mesh, painter, gopts, log);
  return { mesh: packMesh(coloured, null), translation: g.offset || [0, 0, 0] };
}

function forgeDefinition(def, ctx) {
  const log = ctx.log || (() => {});
  const bones = def.creature ? loadCreatureBones(def.creature, ctx.repoRoot).bones : inlineBones(def);
  const opts = {
    res: ctx.res || def.resolution || 0.01,
    targetTris: ctx.targetTris || def.target_tris || 12000,
    smooth: def.smooth == null ? 0 : def.smooth,
  };
  log(`${def.id}: ${bones.length} bones, res ${opts.res} m, target ${opts.targetTris} tris`);
  const t0 = Date.now();
  const { compiled, mesh, painter, grid } = buildSurface(def, bones, opts, log);
  const coloured = colourMesh(def, compiled, mesh, painter, opts, log);
  const skin = skinMesh(compiled, bones, coloured, log);
  const packed = packMesh(coloured, skin);
  const gore = buildGore(def, opts, log);
  const materials = {};
  for (const [name, m] of Object.entries(compiled.materials)) {
    materials[name] = { roughness: m.roughness, metallic: m.metallic, alpha: m.alpha };
    if (m.emissive) materials[name].emissive = Array.isArray(m.emissive) ? m.emissive : require('./color').hexToLinear(m.emissive);
  }
  const outRel = def.out || `creatures/${def.id}.glb`;
  const outPath = path.join(ctx.outDir, outRel);
  require('fs').mkdirSync(path.dirname(outPath), { recursive: true });
  const bonesOut = bones.map((b) => ({ id: b.id, pivot: b.pivot, parent: b.parent }));
  const result = writeGlb(outPath, { name: def.id, bones: bonesOut, mesh: packed, gore, materials,
    extras: { forge: 'critterweight-forge', definition: def.id, bones: bones.map((b) => b.id) } });
  // stats
  const perBone = new Array(bones.length).fill(0);
  for (let i = 0; i < packed.joints.length; i += 4) perBone[packed.joints[i]]++;
  const stats = {
    id: def.id, out: outRel.replace(/\\/g, '/'), bytes: result.bytes, vertices: packed.positions.length / 3,
    triangles: packed.groups.reduce((s, g) => s + g.indices.length / 3, 0),
    materials: packed.groups.map((g) => g.material),
    gore_triangles: gore ? gore.mesh.groups.reduce((s, g) => s + g.indices.length / 3, 0) : 0,
    bounds: { min: compiled.bounds[0].map((x) => +x.toFixed(3)), max: compiled.bounds[1].map((x) => +x.toFixed(3)) },
    bones: bones.map((b, i) => ({ id: b.id, dominant_vertices: perBone[i] })),
    resolution: opts.res, grid: [grid.nx, grid.ny, grid.nz], ms: Date.now() - t0,
  };
  log(`  wrote ${outRel} (${(result.bytes / 1024).toFixed(0)} KB, ${stats.triangles} tris, ${stats.vertices} verts) in ${stats.ms} ms`);
  return stats;
}

module.exports = { forgeDefinition };
