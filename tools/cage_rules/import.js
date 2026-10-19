'use strict';
// Reproducible Cage Rules -> Critterweight adapter. Source is preserved verbatim.
// Only build-time data/model extraction runs JS; the shipped game uses its own authoritative sim.
const fs=require('fs'), path=require('path'), vm=require('vm');
const {writeGlb}=require('../forge/lib/gltf');
const root=path.resolve(__dirname,'../..');
const ctx={console}; ctx.window=ctx; ctx.globalThis=ctx;
vm.createContext(ctx);
for(const f of ['three.min.js','sim.js','physics.js','render.js'])
  vm.runInContext(fs.readFileSync(path.join(__dirname,'source',f),'utf8'),ctx,{filename:f});
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
const out={positions:[],normals:[],colors:[],joints:[],weights:[],groups:[]},materials={};
const bones=names.map(n=>({id:n,pivot:pivots[n]})), sourceBones=names.concat(['lFoot','rFoot']);
function append(mesh,rigid){
 const g=mesh.geometry, idx=g.index?Array.from(g.index.array):Array.from({length:g.attributes.position.count},(_,i)=>i);
 const groups=g.groups.length?g.groups:[{start:0,count:idx.length,materialIndex:0}];
 const mats=Array.isArray(mesh.material)?mesh.material:[mesh.material];
 for(const group of groups){
  const mat=mats[group.materialIndex||0]||mats[0], tag='detail_source_'+Object.keys(materials).length;
  materials[tag]={roughness:mat.roughness||.7,metallic:mat.metalness||0};
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
writeGlb(path.join(root,'game/assets/models/creatures/f_varga.glb'),{name:'f_varga',bones,materials,mesh:{
 positions:Float32Array.from(out.positions),normals:Float32Array.from(out.normals),colors:Float32Array.from(out.colors),
 joints:Uint8Array.from(out.joints),weights:Float32Array.from(out.weights),groups:out.groups},
 generator:'Cage Rules original procedural fighter, adapted by tools/cage_rules/import.js'});
console.log('Imported Varga: '+Object.keys(PH.STRIKES).length+' source strikes; '+out.positions.length/3+' mesh vertices.');
