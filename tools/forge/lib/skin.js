'use strict';
// Skin weights from the art parts themselves: every solid part is bound to a body segment, so a
// vertex is influenced by the segments of the parts it is close to. Influence falls off as a
// gaussian of the part's surface distance (sigma = part.skin_soft, default 3.5 cm), which makes
// a limb's joint crease blend over a few centimetres and keeps everything else rigid. Up to 4
// influences per vertex (glTF JOINTS_0/WEIGHTS_0); the game's Skeleton3D bones = segment ids.

function makeSkinner(compiled, bones) {
  const prims = compiled.prims.filter((p) => p.skin && !p.paint && p.op !== 'subtract' && p.op !== 'intersect');
  const boneIndex = new Map(bones.map((b) => [b.id, b.index]));
  const acc = new Float64Array(bones.length);

  function weightsAt(p) {
    acc.fill(0);
    let nearest = -1, nd = Infinity;
    for (let i = 0; i < prims.length; i++) {
      const q = prims[i];
      const bb = q.aabb;
      const s = q.skinSoft;
      const reach = s * 3.5;
      if (p[0] < bb[0][0] - reach || p[0] > bb[1][0] + reach || p[1] < bb[0][1] - reach || p[1] > bb[1][1] + reach || p[2] < bb[0][2] - reach || p[2] > bb[1][2] + reach) continue;
      const d = q.dist(p);
      if (d < nd) { nd = d; nearest = i; }
      const dd = d > 0 ? d : 0;
      if (dd > reach) continue;
      const u = Math.exp(-(dd * dd) / (s * s)) * q.weight;
      acc[boneIndex.get(q.seg)] += u;
    }
    const idx = [];
    for (let b = 0; b < acc.length; b++) if (acc[b] > 1e-6) idx.push(b);
    if (idx.length === 0) {
      const b = nearest >= 0 ? boneIndex.get(prims[nearest].seg) : 0;
      return { joints: [b, 0, 0, 0], weights: [1, 0, 0, 0] };
    }
    idx.sort((a, b) => acc[b] - acc[a]);
    const top = idx.slice(0, 4);
    let sum = 0;
    for (const b of top) sum += acc[b];
    const joints = [0, 0, 0, 0], weights = [0, 0, 0, 0];
    top.forEach((b, i) => { joints[i] = b; weights[i] = acc[b] / sum; });
    return { joints, weights };
  }
  return { weightsAt };
}

// One Laplacian pass over per-vertex weight vectors (dense per bone) so neighbouring vertices
// never jump between bones; keeps the top 4 and renormalises.
function smoothWeights(joints, weights, tris, nBones, vertexCount, lambda) {
  const dense = new Float32Array(vertexCount * nBones);
  for (let v = 0; v < vertexCount; v++) for (let k = 0; k < 4; k++) dense[v * nBones + joints[v * 4 + k]] += weights[v * 4 + k];
  const adj = new Array(vertexCount);
  for (let i = 0; i < vertexCount; i++) adj[i] = [];
  for (let t = 0; t < tris.length; t += 3) {
    const a = tris[t], b = tris[t + 1], c = tris[t + 2];
    adj[a].push(b, c); adj[b].push(a, c); adj[c].push(a, b);
  }
  const out = new Float32Array(dense.length);
  for (let v = 0; v < vertexCount; v++) {
    const nb = adj[v];
    for (let b = 0; b < nBones; b++) {
      let s = 0;
      for (const j of nb) s += dense[j * nBones + b];
      const avg = nb.length ? s / nb.length : dense[v * nBones + b];
      out[v * nBones + b] = dense[v * nBones + b] + lambda * (avg - dense[v * nBones + b]);
    }
  }
  for (let v = 0; v < vertexCount; v++) {
    const order = [];
    for (let b = 0; b < nBones; b++) if (out[v * nBones + b] > 1e-5) order.push(b);
    order.sort((a, b) => out[v * nBones + b] - out[v * nBones + a]);
    const top = order.slice(0, 4);
    let sum = 0;
    for (const b of top) sum += out[v * nBones + b];
    for (let k = 0; k < 4; k++) {
      joints[v * 4 + k] = k < top.length ? top[k] : 0;
      weights[v * 4 + k] = k < top.length ? out[v * nBones + top[k]] / sum : 0;
    }
  }
}

module.exports = { makeSkinner, smoothWeights };
