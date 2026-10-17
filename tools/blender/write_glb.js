'use strict';
// Reuse the game's existing, deterministic skeleton/material/vertex-alpha contract.
const fs = require('fs');
const { writeGlb } = require('../forge/lib/gltf');
const model = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
for (const mesh of [model.mesh, model.gore.mesh]) {
  for (const field of ['positions', 'normals', 'colors', 'weights']) {
    if (mesh[field]) mesh[field] = Float32Array.from(mesh[field]);
  }
  if (mesh.joints) mesh.joints = Uint8Array.from(mesh.joints);
  for (const group of mesh.groups) group.indices = Uint32Array.from(group.indices);
}
const result = writeGlb(process.argv[3], model);
const triangles = model.mesh.groups.reduce((sum, group) => sum + group.indices.length / 3, 0);
console.log(JSON.stringify({ id: model.name, triangles, ...result }));
