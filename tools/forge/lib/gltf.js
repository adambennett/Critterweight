'use strict';
// Minimal glTF 2.0 binary (.glb) writer: one skinned mesh (POSITION, NORMAL, COLOR_0 rgba,
// JOINTS_0, WEIGHTS_0, indices per material), a skin whose joint nodes are flat children of a
// "rig" node (joint name = segment id, translation = segment pivot, inverse bind = -pivot),
// optional unskinned extra meshes (the detachable gore piece) and PBR material hints.
// Deterministic: same input -> byte-identical output.

const fs = require('fs');

class BinBuilder {
  constructor() { this.chunks = []; this.length = 0; this.views = []; }
  add(buf, target) {
    while (this.length % 4) { this.chunks.push(Buffer.alloc(1)); this.length += 1; }
    const view = { buffer: 0, byteOffset: this.length, byteLength: buf.byteLength };
    if (target) view.target = target;
    this.views.push(view);
    this.chunks.push(Buffer.from(buf.buffer, buf.byteOffset, buf.byteLength));
    this.length += buf.byteLength;
    return this.views.length - 1;
  }
  concat() {
    while (this.length % 4) { this.chunks.push(Buffer.alloc(1)); this.length += 1; }
    return Buffer.concat(this.chunks, this.length);
  }
}

const COMPONENT = { f32: 5126, u8: 5121, u16: 5123, u32: 5125 };

function accessor(json, bin, array, type, componentType, count, extra) {
  const view = bin.add(array, extra && extra.target);
  const a = { bufferView: view, componentType: COMPONENT[componentType], count, type };
  if (extra && extra.minmax) {
    const n = { VEC3: 3, VEC4: 4, SCALAR: 1 }[type];
    const min = new Array(n).fill(Infinity), max = new Array(n).fill(-Infinity);
    for (let i = 0; i < count; i++) for (let k = 0; k < n; k++) {
      const v = array[i * n + k];
      if (v < min[k]) min[k] = v;
      if (v > max[k]) max[k] = v;
    }
    a.min = min; a.max = max;
  }
  if (extra && extra.normalized) a.normalized = true;
  json.accessors.push(a);
  return json.accessors.length - 1;
}

// mesh: { positions: Float32Array, normals: Float32Array, colors: Float32Array (rgba),
//         joints: Uint8Array|null, weights: Float32Array|null, groups: [{material, indices: Uint32Array}] }
function addMesh(json, bin, mesh, name, materialIndex) {
  const count = mesh.positions.length / 3;
  const attrs = {
    POSITION: accessor(json, bin, mesh.positions, 'VEC3', 'f32', count, { minmax: true, target: 34962 }),
    NORMAL: accessor(json, bin, mesh.normals, 'VEC3', 'f32', count, { target: 34962 }),
    COLOR_0: accessor(json, bin, mesh.colors, 'VEC4', 'f32', count, { target: 34962 }),
  };
  if (mesh.joints) {
    attrs.JOINTS_0 = accessor(json, bin, mesh.joints, 'VEC4', 'u8', count, { target: 34962 });
    attrs.WEIGHTS_0 = accessor(json, bin, mesh.weights, 'VEC4', 'f32', count, { target: 34962 });
  }
  const primitives = mesh.groups.map((g) => {
    const idx = count < 65535 ? Uint16Array.from(g.indices) : Uint32Array.from(g.indices);
    return {
      attributes: attrs,
      indices: accessor(json, bin, idx, 'SCALAR', count < 65535 ? 'u16' : 'u32', idx.length, { target: 34963 }),
      material: materialIndex(g.material),
      mode: 4,
    };
  });
  json.meshes.push({ name, primitives });
  return json.meshes.length - 1;
}

function writeGlb(outPath, model) {
  const json = {
    asset: { version: '2.0', generator: 'critterweight-forge 1.0 (tools/forge) - original procedural art' },
    scene: 0, scenes: [{ name: model.name, nodes: [0] }],
    nodes: [], meshes: [], skins: [], materials: [], accessors: [], bufferViews: [], buffers: [],
  };
  const bin = new BinBuilder();
  const matIndex = new Map();
  const materialIndex = (name) => {
    if (matIndex.has(name)) return matIndex.get(name);
    const m = model.materials[name] || {};
    const entry = {
      name,
      pbrMetallicRoughness: { baseColorFactor: [1, 1, 1, 1], metallicFactor: m.metallic == null ? 0 : m.metallic, roughnessFactor: m.roughness == null ? 0.7 : m.roughness },
      doubleSided: false,
    };
    if (m.emissive) entry.emissiveFactor = m.emissive;
    if (m.alpha != null && m.alpha < 1) { entry.alphaMode = 'BLEND'; entry.pbrMetallicRoughness.baseColorFactor[3] = m.alpha; }
    json.materials.push(entry);
    matIndex.set(name, json.materials.length - 1);
    return matIndex.get(name);
  };
  // nodes: 0 root, 1 rig, joints..., then mesh nodes
  json.nodes.push({ name: 'model', children: [1] });
  json.nodes.push({ name: 'rig', children: [] });
  const jointNodes = [];
  for (const b of model.bones) {
    json.nodes.push({ name: b.id, translation: b.pivot.map((x) => +x.toFixed(6)) });
    const idx = json.nodes.length - 1;
    json.nodes[1].children.push(idx);
    jointNodes.push(idx);
  }
  const ibm = new Float32Array(model.bones.length * 16);
  model.bones.forEach((b, i) => {
    const o = i * 16;
    ibm[o] = 1; ibm[o + 5] = 1; ibm[o + 10] = 1; ibm[o + 15] = 1;
    ibm[o + 12] = -b.pivot[0]; ibm[o + 13] = -b.pivot[1]; ibm[o + 14] = -b.pivot[2];
  });
  json.skins.push({ name: model.name + '_skin', joints: jointNodes, skeleton: 1, inverseBindMatrices: accessor(json, bin, ibm, 'MAT4', 'f32', model.bones.length) });
  const meshIdx = addMesh(json, bin, model.mesh, model.name + '_mesh', materialIndex);
  json.nodes.push({ name: model.name + '_mesh', mesh: meshIdx, skin: 0 });
  json.nodes[0].children.push(json.nodes.length - 1);
  if (model.gore) {
    const gi = addMesh(json, bin, model.gore.mesh, 'gore_piece_mesh', materialIndex);
    json.nodes.push({ name: 'gore_piece', mesh: gi, translation: (model.gore.translation || [0, 0, 0]).map((x) => +x.toFixed(6)) });
    json.nodes[0].children.push(json.nodes.length - 1);
  }
  if (model.extras) json.nodes[0].extras = model.extras;
  const binBuf = bin.concat();
  json.bufferViews = bin.views;
  json.buffers.push({ byteLength: binBuf.length });
  let jsonStr = JSON.stringify(json);
  while (jsonStr.length % 4) jsonStr += ' ';
  const jsonBuf = Buffer.from(jsonStr, 'utf8');
  const total = 12 + 8 + jsonBuf.length + 8 + binBuf.length;
  const out = Buffer.alloc(total);
  let o = 0;
  out.writeUInt32LE(0x46546c67, o); o += 4; // glTF
  out.writeUInt32LE(2, o); o += 4;
  out.writeUInt32LE(total, o); o += 4;
  out.writeUInt32LE(jsonBuf.length, o); o += 4;
  out.writeUInt32LE(0x4e4f534a, o); o += 4; // JSON
  jsonBuf.copy(out, o); o += jsonBuf.length;
  out.writeUInt32LE(binBuf.length, o); o += 4;
  out.writeUInt32LE(0x004e4942, o); o += 4; // BIN
  binBuf.copy(out, o);
  fs.writeFileSync(outPath, out);
  return { bytes: total, materials: json.materials.map((m) => m.name) };
}

module.exports = { writeGlb };
