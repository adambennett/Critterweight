#!/usr/bin/env node
'use strict';
// Dependency-free audit of the delivered GLB contract, including the detachable mesh.
// Registration statistics are diagnostics, not a substitute for motion review.
const fs=require('fs'), path=require('path'), crypto=require('crypto');
const root=path.resolve(__dirname,'../..');
const manifest=JSON.parse(fs.readFileSync(path.join(__dirname,'model_manifest.json'),'utf8'));
const args=process.argv.slice(2);
let out=null, modelRoot=path.join(root,'game/assets/models'); const ids=[];
for(let i=0;i<args.length;i++) {
  if(args[i]==='--out')out=args[++i];
  else if(args[i]==='--model-root')modelRoot=path.resolve(args[++i]);
  else ids.push(args[i]);
}
const sub=(a,b)=>a.map((v,i)=>v-b[i]), dot=(a,b)=>a.reduce((s,v,i)=>s+v*b[i],0), len=a=>Math.sqrt(dot(a,a));
function distance(p,s) {
  if(s.type==='sphere')return len(sub(p,s.center))-s.radius;
  if(s.type==='capsule') {
    const ab=sub(s.b,s.a),ap=sub(p,s.a),t=Math.max(0,Math.min(1,dot(ap,ab)/dot(ab,ab)));
    return len(ap.map((v,i)=>v-ab[i]*t))-s.radius;
  }
  const q=sub(p,s.center).map((v,i)=>Math.abs(v)-s.size[i]/2);
  return len(q.map(v=>Math.max(v,0)))+Math.min(Math.max(...q),0);
}
function audit(e) {
  const file=path.join(modelRoot,e.out), raw=fs.readFileSync(file), errors=[];
  const check=(ok,msg)=>{if(!ok)errors.push(msg)};
  check(raw.readUInt32LE(0)===0x46546c67 && raw.readUInt32LE(4)===2,'Invalid GLB 2 header');
  check(raw.readUInt32LE(8)===raw.length,'GLB length mismatch');
  const jsonLen=raw.readUInt32LE(12), gltf=JSON.parse(raw.toString('utf8',20,20+jsonLen));
  const bin=raw.subarray(28+jsonLen);
  function read(index) {
    const a=gltf.accessors[index],v=gltf.bufferViews[a.bufferView];
    const n={SCALAR:1,VEC2:2,VEC3:3,VEC4:4,MAT4:16}[a.type];
    const [size,fn]={5121:[1,'readUInt8'],5123:[2,'readUInt16LE'],5125:[4,'readUInt32LE'],5126:[4,'readFloatLE']}[a.componentType];
    const stride=v.byteStride||size*n,start=(v.byteOffset||0)+(a.byteOffset||0);
    return Array.from({length:a.count},(_,i)=>Array.from({length:n},(_,j)=>bin[fn](start+i*stride+j*size)));
  }
  const creature=JSON.parse(fs.readFileSync(path.join(root,e.creature),'utf8'));
  const segments=creature.body.segments, skin=gltf.skins[0], boneNames=skin.joints.map(i=>gltf.nodes[i].name);
  check(gltf.skins.length===1,'Expected one skin');
  // v0.9.17: besides one bone per body segment, a model may carry view-only "fx_*" bones (eyes, lids,
  // brows, jaw, springs) parented under a segment bone; they never affect gameplay
  const parentOf={};
  gltf.nodes.forEach((n,i)=>(n.children||[]).forEach(c=>{parentOf[c]=i;}));
  const segOf=name=>{
    let i=gltf.nodes.findIndex(n=>n.name===name);
    while(i!==undefined&&i>=0){const nm=gltf.nodes[i].name;if(segments.some(s=>s.id===nm))return nm;i=parentOf[i];}
    return null;
  };
  const extra=boneNames.filter(b=>!segments.some(s=>s.id===b));
  check(segments.every(s=>boneNames.includes(s.id)),'Bone set lacks body segments');
  check(extra.every(b=>b.startsWith('fx_')&&segOf(b)!==null),'Unexpected bones: '+extra.filter(b=>!b.startsWith('fx_')||segOf(b)===null).join(','));
  const inverse=read(skin.inverseBindMatrices);
  for(let b=0;b<boneNames.length;b++) {
    const seg=segments.find(s=>s.id===boneNames[b]),node=gltf.nodes[skin.joints[b]];
    if(!seg)continue;
    check(len(sub(node.translation,seg.pivot))<1e-5,'Rest pivot mismatch: '+seg.id);
    const expected=[1,0,0,0,0,1,0,0,0,0,1,0,...seg.pivot.map(v=>-v),1];
    check(inverse[b].every((v,i)=>Math.abs(v-expected[i])<1e-5),'Inverse bind mismatch: '+seg.id);
  }
  check(gltf.materials.some(m=>m.name==='team'),'Missing team material');
  const gore=gltf.nodes.find(n=>n.name==='gore_piece');
  check(gore && gore.skin===undefined,'Missing or skinned gore_piece');
  check(!(gltf.animations||[]).length,'Fighter must not export keyframed animation');
  check(!(gltf.textures||[]).length,'This pipeline has no texture dependency');
  let bodyTriangles=0,goreTriangles=0,maxWeights=0,vertices=0,glowVertices=0;
  const outside=[],byBone={},outliers=[];
  for(const node of gltf.nodes.filter(n=>n.mesh!==undefined)) {
    const skinned=node.skin!==undefined,primitives=gltf.meshes[node.mesh].primitives;
    for(const p of primitives) {
      const indices=read(p.indices).flat(), count=gltf.accessors[p.attributes.POSITION].count;
      check(indices.every(i=>i<count),'Index outside vertex array');
      if(skinned)bodyTriangles+=indices.length/3;else goreTriangles+=indices.length/3;
    }
    // All surfaces emitted by this writer share attribute accessors; inspect once.
    const p=primitives[0],positions=read(p.attributes.POSITION),colors=read(p.attributes.COLOR_0),normals=read(p.attributes.NORMAL);
    const joints=skinned?read(p.attributes.JOINTS_0):[],weights=skinned?read(p.attributes.WEIGHTS_0):[];
    vertices+=positions.length;
    for(let i=0;i<positions.length;i++) {
      check(positions[i].every(Number.isFinite),'Non-finite position');
      check(Math.abs(len(normals[i])-1)<.002,'Invalid normal');
      check(colors[i].every(v=>Number.isFinite(v)&&v>=-.001&&v<=1.001),'Invalid color');
      if(colors[i][3]>.001)glowVertices++;
      if(!skinned)continue;
      const active=weights[i].filter(w=>w>1e-5).length;
      maxWeights=Math.max(maxWeights,active);
      check(active>0&&active<=4&&Math.abs(weights[i].reduce((a,b)=>a+b,0)-1)<1e-5,'Invalid normalized weights');
      check(joints[i].every(j=>j<boneNames.length),'Joint outside skin');
      const k=weights[i].indexOf(Math.max(...weights[i])),name=segOf(boneNames[joints[i][k]]);
      const seg=segments.find(s=>s.id===name);
      const d=Math.min(...seg.shapes.map(s=>distance(positions[i],s)));
      const all=Math.min(...segments.flatMap(s=>s.shapes).map(s=>distance(positions[i],s)));
      outside.push(Math.max(0,all)); if(all>.05)outliers.push({bone:name,position:positions[i],outside:all});
      byBone[name]=Math.max(byBone[name]||0,d);
    }
    for(const p of primitives) {
      const material=gltf.materials[p.material];
      const glowing=read(p.indices).some(([i])=>colors[i][3]>.001);
      if(glowing)check((material.emissiveFactor||[]).some(v=>v>0),'Glow alpha lacks emissive material hint');
    }
  }
  // fighters: 30k since the v0.9.17 art pass (docs/ART_PIPELINE.md §3); bosses 25k; minions 2k
  const triangles=bodyTriangles+goreTriangles,budget=e.id.startsWith('f_')?30000:e.id.startsWith('boss_')?25000:2000;
  check(triangles<=budget,`Triangle budget ${triangles} > ${budget}`);
  if(e.id.startsWith('f_'))check(bodyTriangles>=6000,'Fighter below the agreed 6k target');
  outside.sort((a,b)=>a-b);
  return {id:e.id,bodyTriangles,goreTriangles,triangles,budget,vertices,bytes:raw.length,maxWeights,materials:gltf.materials.map(m=>m.name),glowVertices,
    outsideCollision:{maxM:outside.at(-1)||0,p95M:outside[Math.floor(outside.length*.95)]||0,verticesOver5cm:outside.filter(d=>d>.05).length,maxByDominantBone:byBone,furthestVertices:outliers.sort((a,b)=>b.outside-a.outside).slice(0,8)},
    sha256:crypto.createHash('sha256').update(raw).digest('hex'),errors};
}
const results=manifest.filter(e=>e.creature && (!ids.length||ids.includes(e.id))).map(audit);
if(out) {fs.mkdirSync(path.dirname(path.resolve(out)),{recursive:true});fs.writeFileSync(out,JSON.stringify(results,null,2)+'\n');}
for(const r of results)console.log(`${r.id}: ${r.triangles}/${r.budget} tris; ${r.bytes} bytes; outside p95 ${(r.outsideCollision.p95M*100).toFixed(1)} cm, max ${(r.outsideCollision.maxM*100).toFixed(1)} cm; ${r.errors.length?'FAIL '+[...new Set(r.errors)].join('; '):'contract PASS'}`);
process.exitCode=results.some(r=>r.errors.length)?1:0;
