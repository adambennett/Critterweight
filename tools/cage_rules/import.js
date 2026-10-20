'use strict';
// Reproducible Cage Rules -> Critterweight adapter. Source is preserved verbatim.
// Only build-time data/model extraction runs JS; the shipped game uses its own authoritative sim.
const fs=require('fs'), path=require('path'), vm=require('vm');
const {writeGlb}=require('../forge/lib/gltf');
const root=path.resolve(__dirname,'../..');
const ctx={console}; ctx.window=ctx; ctx.globalThis=ctx;
vm.createContext(ctx);
for(const f of ['three.min.js','sim.js','physics.js'])
  vm.runInContext(fs.readFileSync(path.join(__dirname,'source',f),'utf8'),ctx,{filename:f});
// render.js keeps the referee's poses, tuning and rig constants in its closure. They are exposed in
// memory only, by extending the export line once (the retained file on disk stays unchanged); the
// assertion fails loudly if the original export line ever changes.
const EXPORT='root.MMARender = { Renderer, FighterModel, POSES, ceremonyEnd };';
const EXPORT_REF='root.MMARender = { Renderer, FighterModel, POSES, ceremonyEnd, REF_POSES, LINE_POSES, ceremonyTimes,'+
 ' REF_TUNING: { REF_CAGE, KD_HOLD, REF_SPEED, REF_ROOM, LUNGE_V, LUNGE_T, LUNGE_CD, LINE_X, KD_STAY: KD_T.STAY },'+
 ' REF_RIG: { HIP_H, SH_X, SH_Y, HIP_XX, HIP_Y, UPPER_L, FORE_L, THIGH_L, SHIN_L, RIG, ANKLE_PIVOT } };';
const renderSrc=fs.readFileSync(path.join(__dirname,'source','render.js'),'utf8');
if(renderSrc.split(EXPORT).length!==2) throw Error('render.js export line not found exactly once');
vm.runInContext(renderSrc.replace(EXPORT,()=>EXPORT_REF),ctx,{filename:'render.js'});
const PH=ctx.MMAPhys, THREE=ctx.THREE;
const scene=new THREE.Scene(), model=new ctx.MMARender.FighterModel(scene,0xb52d37,0xe0b48c,0,
  {look:{hair:'short',beard:'goatee',build:'athletic',gloves:0x24232a,trim:0xe6c45f}});
scene.updateMatrixWorld(true);
const names=PH.SEG_ORDER, scale=1.06;
const pos=v=>[v.x*scale,v.y*scale,v.z*scale];
const add=(a,b)=>a.map((x,i)=>x+b[i]);
const centers={}, pivots={};
for(const n of names){
  centers[n]=pos(model.segs[n].getWorldPosition(new THREE.Vector3()));
  pivots[n]=add(centers[n],(PH.SEGS[n].anchorSelf||[0,0,0]).map(x=>x*scale));
}
const body={id:'f_varga_body',gait:'biped',hover_height:1.08*scale,stride:.35,step_height:.12,step_time:.20,segments:[],chains:{},weapons:{},poses:{}};
function shape(s,c){const a=s[0];return a==='ball'?{type:'sphere',center:c,radius:s[1]*scale}:a==='cuboid'?{type:'box',center:c,size:s.slice(1).map(x=>x*2*scale)}:{type:'capsule',a:add(c,[0,-s[1]*scale,0]),b:add(c,[0,s[1]*scale,0]),radius:s[2]*scale};}
for(const n of names){
 const s=PH.SEGS[n], shapes=[shape(s.shape,centers[n])];
 if(s.extra) shapes.push(shape(s.extra.shape,add(centers[n],s.extra.pos.map(x=>x*scale))));
 body.segments.push({id:n,...(s.parent?{parent:s.parent}:{}),pivot:pivots[n],mass:s.mass+(s.extra?s.extra.mass:0),
 part:n==='head'?'head':n.includes('Arm')||n.includes('Forearm')?'arm':n.includes('Thigh')||n.includes('Shin')?'leg':'core',
 guard:n.includes('Arm')||n.includes('Forearm'),hurt:n==='head'?1.3:n.includes('Arm')?.55:1,w0:s.w0,shapes});
}
for(const side of ['l','r']){
 const x=side==='l'?1:-1;
 const fist=add(centers[side+'Forearm'],PH.SEGS[side+'Forearm'].extra.pos.map(x=>x*scale));
 const foot=add(centers[side+'Shin'],PH.SEGS[side+'Shin'].extra.pos.map(x=>x*scale));
 // Source hand paths become IK targets so Critterweight can aim at different-sized creatures.
 body.chains['arm_'+side]={segments:[side+'UpperArm',side+'Forearm'],effector:fist,pole:[x,0,0]};
 // Leg chains supply walking; keyed kicks own the original joint rotations.
 body.chains['leg_'+side]={segments:[side+'Thigh',side+'Shin'],effector:foot,pole:[0,0,1],leg:true,group:side==='l'?0:1,home:[x*.16,.07,x*.04]};
 for(const [wn,seg,p,r] of [[side+'Fist',side+'Forearm',fist,.10],[side+'Foot',side+'Shin',foot,.11],[side+'Shin',side+'Shin',centers[side+'Shin'],.11],[side+'Knee',side+'Shin',add(centers[side+'Shin'],[0,.18*scale,0]),.10]])
  body.weapons[wn]={segment:seg,point:p,radius:r};
}
body.weapons.shoulder={segment:'chest',point:add(centers.chest,[0,0,.19]),radius:.23};
const zero=[0,0,0];
function rootLean(p){
 const q=PH.math.qMul(PH.math.qYaw((p.pelvisYaw||0)*Math.PI/180),PH.math.qEuler(p.pelvisTilt||zero));
 const e=new THREE.Euler().setFromQuaternion(new THREE.Quaternion(q.x,q.y,q.z,q.w),'XYZ');
 return [e.x,e.y,e.z].map(v=>v*180/Math.PI);
}
function toPose(p){
 const joints={};
 for(const n of names.slice(1)) joints[n]=p[n]||zero;
 const chains={}, fk=PH.fk({...p,pelvisYaw:0});
 for(const side of ['l','r']){
  const target=pos(fk.w[side+'Fist']);target[1]-=(PH.HOVER_HEIGHT+(p.lift||0))*scale-pivots.pelvis[1];
  // Keep a tucked glove beside, rather than inside, the head/chest after IK retargeting.
  if(target[2]<.34)target[0]=(side==='l'?1:-1)*Math.max(Math.abs(target[0]),.34);
  const elbow=PH.math.vAdd(fk.p[side+'Forearm'],PH.math.qRot(fk.q[side+'Forearm'],{x:0,y:.14,z:0}));
  const shoulder=PH.math.vAdd(fk.p[side+'UpperArm'],PH.math.qRot(fk.q[side+'UpperArm'],{x:0,y:.14,z:0}));
  chains['arm_'+side]={target,pole:[elbow.x-shoulder.x,elbow.y-shoulder.y,elbow.z-shoulder.z]};
  delete joints[side+'UpperArm'];delete joints[side+'Forearm'];
 }
 return {joints,chains,height:(p.lift||0)*scale,lean:p.pelvisTilt||zero};
}
for(const [n,p] of Object.entries({stance:PH.POSES.STANCE,guard:PH.POSES.GUARD,shell:PH.POSES.GUARD_LOW,check:PH.POSES.CHECK_GUARD}))
 body.poses[n]=toPose(p);
const moves={};
for(const [key,d] of Object.entries(PH.STRIKES)){
 const keys=d.frames.map(f=>{const p=PH.resolveFrameExport(d,f,PH.POSES.STANCE),q=toPose(p); if(d.kind==='lkick')p.pelvisYaw*=1.3; if(!d.isKick){for(const n of ["lThigh","lShin","rThigh","rShin"])delete q.joints[n];}else{q.chains={};for(const n of ["lUpperArm","lForearm","rUpperArm","rForearm"])q.joints[n]=[...(p[n]||zero)];for(const side of ["l","r"]){q.joints[side+"UpperArm"][2]+=(side==="l"?45:-45);q.joints[side+"Forearm"][0]=Math.max(-100,q.joints[side+"Forearm"][0]);}} return {t:f.t,...q,lean:rootLean(p)};});
 moves[key]={name:d.name,duration:d.dur,cancel:d.active[1],damage:5.7*d.weaponMult,knockback:d.kind==='teep'?4:1.5,
 stun:.18,poise:d.isKick?16:11,stamina:d.cost,speed:d.kind==='teep'?2.4:d.speed,vmin:1.1,vref:5,move_mult:.5,
 element:'scrap',buildup:d.isKick?21:16,class:d.isKick||d.kind==='overhand'?'heavy':'light',
 lunge:d.lunge?[[Math.max(0,d.active[0]-.08),d.active[1],d.kind==='uppercut'?1.8:d.kind==='lkick'?1.8:d.lunge]]:[],
 hit:[{t0:d.active[0],t1:d.active[1]+(d.kind==='lkick'?.07:0),weapons:d.kind==='knee'?[d.weapon[0]+'Knee']:d.weapons}],keys};
}
const clone=x=>JSON.parse(JSON.stringify(x));
const swap=n=>n.startsWith('l')?'r'+n.slice(1):n.startsWith('r')?'l'+n.slice(1):n;
for(const [key,m] of Object.entries(moves)){
 const sp=clone(m);sp.hit.forEach(h=>h.weapons=h.weapons.map(swap));
 sp.keys.forEach(k=>{const js={};for(const [n,v] of Object.entries(k.joints||{}))js[swap(n)]=[v[0],-v[1],-v[2]];k.joints=js;const cs={};for(const [n,v] of Object.entries(k.chains||{}))cs[n.endsWith('_l')?n.slice(0,-1)+'r':n.slice(0,-1)+'l']={target:[-v.target[0],v.target[1],v.target[2]],pole:[-v.pole[0],v.pole[1],v.pole[2]]};k.chains=cs;if(k.lean)k.lean=[k.lean[0],-k.lean[1],-k.lean[2]];});
 moves[key+'@southpaw']=sp;
}
for(const [alias,key] of Object.entries({l1:'lh_straight',l2:'rh_straight',l3:'lh_hook',heavy:'rl_hkick',heavy_charged:'rl_hkick',finisher:'rh_uppercut',dash_attack:'ll_teep',pummel:'rh_uppercut'})) moves[alias]=clone(moves[key]);
moves.grab={...clone(moves.rh_straight),name:'Double-leg entry',kind:'grab',duration:.65,damage:0,stamina:12,lunge:[[.05,.25,3]],hit:[{t0:.12,t1:.35,weapons:['lFist','rFist','shoulder']}],keys:[{t:0},{t:.12,lean:[40,0,0],height:-.18},{t:.35,lean:[35,0,0],height:-.12},{t:.65}]};
moves.taunt={name:'Touch gloves',kind:'taunt',duration:.85,keys:[{t:0},{t:.4,joints:{lUpperArm:[-100,0,0],lForearm:[-45,0,0],rUpperArm:[-100,0,0],rForearm:[-45,0,0]}},{t:.85}]};
moves.pummel.interval=.4;
const c={id:'f_varga',name:'Varga',title:'the Cage Rules Guest',element:'scrap',npc_only:false,tags:['fighter','martial','guest'],
 blurb:"Jeremy's Cage Rules guest. Four independent limbs, three held strike modifiers, stance switching and opponent-relative footwork. Read the Cage Rules controls below; this fighter uses a different layout.",
 stats:{health:110,walk_speed:3.4,stamina:105,stamina_regen:12,poise:60,poise_regen:15,power:1,defense:1,weight:1,dodge_distance:1.7,dodge_time:.25},
 body,moves,string:['lh_straight','rh_straight','lh_hook'],abilities:{
 ability1:{name:'Cut the Angle',duration:.4,cooldown:7,stamina:12,keys:[{t:0},{t:.16,lean:[0,0,18]},{t:.4}],effects:[{t:.08,type:'dash',speed:5,dir:'stick',time:.18},{t:.08,type:'buff',status:{id:'angle',name:'Cut the Angle',duration:2,damage_dealt:1.18}}],invuln:[[.06,.22]]},
 ability2:{name:'Second Wind',duration:.7,cooldown:15,stamina:0,keys:[{t:0},{t:.3,height:.05},{t:.7}],effects:[{t:.3,type:'buff',status:{id:'second_wind',name:'Second Wind',duration:4,stamina_regen:2,poise_regen:1.5}}]},
 juice:{name:'Championship Rounds',duration:.7,stamina:0,keys:clone(moves.taunt.keys),effects:[{t:.15,type:'buff',status:{id:'championship',name:'Championship Rounds',duration:7,move_speed:1.2,damage_dealt:1.2,stamina_regen:1.5}},{t:.15,type:'area',radius:1.3,damage:3,knockback:3,element:'scrap',buildup:35}]}
 },juice:{duration:7},throws:{throw_fwd:{distance:2,damage:10,up:1.4,knockdown:true,buildup:25},throw_side:{distance:2.5,damage:9,up:1.2,knockdown:true},throw_back:{distance:2,damage:11,up:1.5,knockdown:true}},
 art:{model:'res://assets/models/creatures/f_varga.glb',outline:.007,roughness:.7},ai:{aggression:.1,attack_range:1.2,reach:{l1:1.15,heavy:1.45,grab:1.15},abilities:{ability1:{chance:3,when:[{max:2,chance:.3}]},ability2:{chance:3,when:[{self_health_below:.65,chance:.6}]}}}};
fs.writeFileSync(path.join(root,'game/content/core/creatures/f_varga.json'),JSON.stringify(c,null,2)+'\n');
// Flatten the original continuous skinned mesh AND the original face/gloves into the game's segment rig.
const bones=names.map(n=>({id:n,pivot:pivots[n]})), sourceBones=names.concat(['lFoot','rFoot']);
function exportGlb(model,id,rel,generator,doubleSided){
const out={positions:[],normals:[],colors:[],joints:[],weights:[],groups:[]},materials={};
function append(mesh,rigid){
 const g=mesh.geometry, idx=g.index?Array.from(g.index.array):Array.from({length:g.attributes.position.count},(_,i)=>i);
 const groups=g.groups.length?g.groups:[{start:0,count:idx.length,materialIndex:0}];
 const mats=Array.isArray(mesh.material)?mesh.material:[mesh.material];
 for(const group of groups){
  const mat=mats[group.materialIndex||0]||mats[0], tag='detail_source_'+Object.keys(materials).length;
  materials[tag]={roughness:mat.roughness||.7,metallic:mat.metalness||0};
  if(doubleSided&&mat.side===THREE.DoubleSide)doubleSided.push(tag);
  const indices=[];
  for(let k=group.start;k<group.start+group.count;k++){
   const i=idx[k], v=new THREE.Vector3().fromBufferAttribute(g.attributes.position,i).applyMatrix4(mesh.matrixWorld).multiplyScalar(scale);
   const n=new THREE.Vector3().fromBufferAttribute(g.attributes.normal,i).transformDirection(mesh.matrixWorld);
   indices.push(out.positions.length/3);out.positions.push(v.x,v.y,v.z);out.normals.push(n.x,n.y,n.z);
   const col=mat.color.clone().convertSRGBToLinear();out.colors.push(col.r,col.g,col.b,0);
   if(rigid!==undefined){out.joints.push(rigid,0,0,0);out.weights.push(1,0,0,0);}
   else for(let j=0;j<4;j++){let bn=sourceBones[g.attributes.skinIndex.array[i*4+j]]; if(bn.endsWith('Foot'))bn=bn[0]+'Shin';out.joints.push(names.indexOf(bn));out.weights.push(g.attributes.skinWeight.array[i*4+j]);}
  }
  out.groups.push({material:tag,indices:Uint32Array.from(indices)});
 }
}
append(model.skinMesh);
for(const name of names)model.segs[name].traverse(m=>{if(m.isMesh&&m.visible)append(m,names.indexOf(name));});
writeGlb(path.join(root,'game/assets/models',rel),{name:id,bones,materials,mesh:{
 positions:Float32Array.from(out.positions),normals:Float32Array.from(out.normals),colors:Float32Array.from(out.colors),
 joints:Uint8Array.from(out.joints),weights:Float32Array.from(out.weights),groups:out.groups},generator});
return out.positions.length/3;
}
// v0.9.17: this adapter's Varga is the LEGACY skin ("Legacy Varga skin" in Settings). It is written to
// f_varga_legacy.glb only (f_varga.glb is the upgraded Blender-owned default) and must stay byte-identical to the
// v0.9.16 original: a different result is refused (restored) unless --allow-legacy-change is passed deliberately.
const LEGACY_SHA256='4fa78a8a66cb46739b793bc095501e3957a5aed27bafe1901141ba4c90d460fc';
const legacyPath=path.join(root,'game/assets/models/creatures/f_varga_legacy.glb');
const legacyBefore=fs.existsSync(legacyPath)?fs.readFileSync(legacyPath):null;
const vargaVerts=exportGlb(model,'f_varga','creatures/f_varga_legacy.glb','Cage Rules original procedural fighter, adapted by tools/cage_rules/import.js');
{
 const got=require('crypto').createHash('sha256').update(fs.readFileSync(legacyPath)).digest('hex');
 if(got!==LEGACY_SHA256&&!process.argv.includes('--allow-legacy-change')){
  if(legacyBefore)fs.writeFileSync(legacyPath,legacyBefore);
  throw new Error('f_varga_legacy.glb would change ('+got+' != '+LEGACY_SHA256+'); restored. Pass --allow-legacy-change only to replace the legacy skin on purpose.');
 }
}

// ---- The original referee (render.js class Referee). He is the same procedural body and bind skeleton as the
// fighter (body width 1, short hair), dressed by opts.ref (shirt, slacks, shoes, open nitrile hands), built with
// Referee's own constructor arguments. View-only: his model and data live under game/assets, never as a content
// creature (no gameplay kind, so the multiplayer content hash is unchanged).
const R=ctx.MMARender;
const refScene=new THREE.Scene(), refModel=new R.FighterModel(refScene,0x1e2028,0xc99a74,2,{ref:true});
refScene.updateMatrixWorld(true);
// Varga's bone pivots are reused, so the referee's bind frames must match them exactly
for(const n of names){const c=pos(refModel.segs[n].getWorldPosition(new THREE.Vector3()));if(c.some((x,i)=>Math.abs(x-centers[n][i])>1e-9))throw Error('referee bind differs from Varga at '+n);}
fs.mkdirSync(path.join(root,'game/assets/models/referee'),{recursive:true});
const refDouble=[]; // surfaces Cage Rules draws double-sided (the slacks' open tubes); glTF keeps them single-sided
const refVerts=exportGlb(refModel,'cage_referee','referee/cage_referee.glb','Cage Rules original referee, adapted by tools/cage_rules/import.js',refDouble);
// Baked segment transforms from the original pose evaluator (FighterModel.update, forced path: P() pose, lerpPose,
// two-bone IK, hierarchy, _applySkeleton, breathing bob, stepping) on a separate model, in Critterweight's segment
// convention (origin on the pivot = scale*(centre + q*anchorSelf), world, metres). The view's GDScript port is
// tested against these (game/src/test/core/test_referee_view.gd).
const RR=R.REF_RIG, r6=x=>Math.round(x*1e6)/1e6, clone2=x=>JSON.parse(JSON.stringify(x));
const ANCHOR={}; for(const n of names) ANCHOR[n]=(PH.SEGS[n].anchorSelf||[0,0,0]).slice();
const bakeModel=new R.FighterModel(new THREE.Scene(),0x1e2028,0xc99a74,2,{ref:true});
const actor={idx:2,x:0,z:0,act:{type:'idle',name:'',t:0},ground:null,rocked:0,pose:null};
const animated=(kind,u)=>{ // the per-frame hands of Referee.update (render.js waveOff / waveUp)
 const p=clone2(R.REF_POSES[kind]);
 if(kind==='waveOff'){p.lh=[0.45-0.6*u,0.86,0.32];p.rh=[-0.45+0.6*u,0.86,0.24];}
 else{p.lh=[0.2,0.05+0.6*u,0.46-0.1*u];p.rh=[-0.2,0.05+0.6*u,0.46-0.1*u];}
 return p;
};
const baked=[];
function bake(id,s){
 const m=bakeModel, pose=s.anim?animated(s.pose,s.u):R.REF_POSES[s.pose];
 if(s.start){m.initialized=true;m.snap=false;m.physMode=false;m.px=s.start.px;m.pz=s.start.pz;m.yaw=s.start.yaw;m.vx=s.start.vx;m.vz=s.start.vz;
  m.stepPhase=s.start.step;m.pose=clone2(R.REF_POSES[s.start.pose]);}
 else m.snap=true;
 m.forced={x:s.x,z:s.z,yaw:s.yaw,pose,moving:s.moving,speed:s.speed};
 m.update(actor,{},null,s.dt,s.time,new THREE.Vector3(1,0,0),1000);
 const segs={};
 for(const n of names){const g=m.segs[n],q=g.quaternion,o=new THREE.Vector3(...ANCHOR[n]).applyQuaternion(q).add(g.position).multiplyScalar(scale);
  segs[n]={p:[o.x,o.y,o.z].map(r6),q:[q.x,q.y,q.z,q.w].map(r6)};}
 baked.push({id,...s,segs});
}
const still={x:0,z:0,yaw:0,time:0,dt:1/60,moving:false,speed:12};
for(const k of Object.keys(R.REF_POSES)) bake(k,{pose:k,...still});
for(const k of ['waveOff','waveUp']) for(const u of [0,1]) bake(k+'@u'+u,{pose:k,anim:true,u,...still});
bake('watch@placed',{...still,pose:'watch',x:1.2,z:-0.7,yaw:0.8,time:0.4});
bake('stop@lerp',{...still,pose:'stop',dt:0.05,speed:20,start:{px:0,pz:0,yaw:0,vx:0,vz:0,step:0,pose:'watch'}});
bake('watch@step',{pose:'watch',x:0.015,z:0.004,yaw:0.5,time:0.7,dt:1/60,moving:true,speed:10,start:{px:0,pz:0,yaw:0.3,vx:0.8,vz:0.2,step:1.1,pose:'watch'}});
const segOff={pelvis:0,chest:RR.RIG.chestUp,head:0,lUpperArm:-RR.RIG.upperArm[0]-0.02,lForearm:-RR.RIG.forearm[0]-0.02,
 rUpperArm:-RR.RIG.upperArm[0]-0.02,rForearm:-RR.RIG.forearm[0]-0.02,lThigh:-RR.RIG.thigh[0]-0.03,lShin:-RR.RIG.shin[0]-0.03,
 rThigh:-RR.RIG.thigh[0]-0.03,rShin:-RR.RIG.shin[0]-0.03};
const refData={_doc:'Generated by tools/cage_rules/import.js from the retained Cage Rules js/render.js (class Referee, REF_POSES, '+
 'FighterModel). View-only data for src/view/referee_view.gd, never a content creature. Poses are the source P() format in '+
 'source units (metres, radians, unscaled); body pivots and baked transforms are scaled by `scale`.',
 id:'cage_referee',name:'Referee',scale,model:'res://assets/models/referee/cage_referee.glb',art:{outline:.007,roughness:.7},double_sided:refDouble,
 body:{id:'cage_referee_body',gait:body.gait,hover_height:body.hover_height,stride:body.stride,step_height:body.step_height,
  step_time:body.step_time,segments:body.segments,chains:body.chains,weapons:{},poses:{stance:body.poses.stance}},
 rig:{hip_h:RR.HIP_H,sh_x:RR.SH_X,sh_y:RR.SH_Y,hip_xx:RR.HIP_XX,hip_y:RR.HIP_Y,upper_l:RR.UPPER_L,fore_l:RR.FORE_L,thigh_l:RR.THIGH_L,
  shin_l:RR.SHIN_L,neck_y:RR.RIG.chestUp+RR.RIG.headUp,seg_offset:segOff,anchor_self:ANCHOR},
 poses:R.REF_POSES,line_poses:R.LINE_POSES,tuning:R.REF_TUNING,
 ceremony:{stoppage:R.ceremonyTimes({method:'KO'}),decision:R.ceremonyTimes({method:'Decision'})},baked};
// numeric arrays on one line, so the file stays readable and diffs small
const refJson=JSON.stringify(refData,null,1).replace(/\[[\d\s.,eE+-]*\]/g,m=>m.replace(/\s+/g,'').replace(/,/g,', '))+'\n';
fs.writeFileSync(path.join(root,'game/assets/data/cage_referee.json'),refJson);
console.log('Imported Varga: '+Object.keys(PH.STRIKES).length+' source strikes; '+vargaVerts+' mesh vertices. Referee: '+refVerts+
 ' mesh vertices, '+Object.keys(R.REF_POSES).length+' poses, '+baked.length+' baked pose checks.');
