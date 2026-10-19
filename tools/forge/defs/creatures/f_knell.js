'use strict';
// KNELL: an empty antique diving suit, bronze porthole, violet soul, split coat and weighted boots.
const H=require('../../lib/helpers');
const P={cloth:'#283B43',edge:'#52727A',bronze:'#927453',trim:'#D2B483',dark:'#111B29',light:'#C3A5FF',eye:'#D9FCF4',rust:'#634B49'};
const parts=[
 {type:'ellipsoid',seg:'chest',c:[0,1.15,0],r:[.25,.31,.19],color:'$cloth',name:'torso',blend:.04},
 {type:'ellipsoid',seg:'pelvis',c:[0,.82,0],r:[.24,.2,.19],color:'$cloth',name:'hips',blend:.04},
 {type:'ellipsoid',seg:'head',c:[0,1.55,.02],r:[.255,.25,.235],color:'$bronze',material:'iron',name:'helmet',op:'sharp'},
 {type:'cylinder',seg:'head',a:[0,1.51,.18],b:[0,1.51,.255],r:.19,color:'$trim',material:'iron',name:'port',op:'sharp'},
 {type:'cylinder',seg:'head',a:[0,1.51,.25],b:[0,1.51,.268],r:.153,color:'$dark',name:'glass',op:'sharp'},
 {type:'ellipsoid',seg:'head',c:[0,1.51,.27],r:[.12,.125,.014],color:'$light',material:'soul',glow:.7,name:'soul',op:'sharp'},
 {type:'ellipsoid',seg:'head',c:[.045,1.535,.291],r:[.023,.035,.01],color:'$eye',material:'soul',glow:1,name:'eye_l',op:'sharp',mirror:true},
 {type:'box',seg:'head',c:[0,1.485,.291],size:[.055,.02,.012],round:.004,color:'$dark',name:'mouth',op:'sharp'},
 {type:'cylinder',seg:'chest',a:[0,1.32,0],b:[0,1.37,0],r:.24,color:'$bronze',material:'iron',name:'collar',op:'sharp'},
 {type:'box',seg:'chest',c:[0,1.12,.20],size:[.19,.22,.06],round:.02,color:'$bronze',material:'iron',name:'chestplate',op:'sharp'},
 {type:'sphere',seg:'chest',c:[0,1.15,.24],r:.055,color:'$light',material:'soul',glow:.8,name:'gauge',op:'sharp'},
 {type:'box',seg:'chest',c:[0,1.02,-.20],size:[.24,.38,.13],round:.06,color:'$bronze',material:'iron',name:'tank',op:'sharp'},
 {type:'box',seg:'pelvis',c:[0,.83,.18],size:[.41,.065,.04],round:.01,color:'$trim',material:'iron',name:'belt',op:'sharp'},
 {type:'cone',seg:'pelvis',a:[.14,.8,.04],b:[.19,.48,.05],ra:.12,rb:.08,color:'$cloth',name:'coat_l',mirror:true,blend:.02},
];
for(let i=0;i<8;i++){const a=i*Math.PI/4;parts.push({type:'sphere',seg:'head',c:[Math.cos(a)*.172,1.51+Math.sin(a)*.172,.27],r:.017,color:'$bronze',material:'iron',name:'bolt'+i,op:'sharp'});}
for(const side of ['l','r']){
 const s=side==='l'?1:-1;
 parts.push(
 {type:'sphere',seg:'uarm_'+side,c:[s*.3,1.32,0],r:.125,color:'$bronze',material:'iron',name:'shoulder_'+side,blend:.02},
 {type:'capsule',seg:'uarm_'+side,a:[s*.3,1.29,0],b:[s*.3,1.08,0],r:.095,color:'$cloth',name:'upper_'+side,blend:.025},
 {type:'capsule',seg:'farm_'+side,a:[s*.3,1.03,0],b:[s*.3,.84,0],r:.085,color:'$cloth',name:'lower_'+side,blend:.02},
 H.fist({seg:'farm_'+side,c:[s*.3,.78,0],r:.11,fwd:[0,-.5,1],side:[s,0,0],color:'$bronze',material:'iron',name:'glove_'+side}),
 {type:'capsule',seg:'thigh_'+side,a:[s*.12,.8,0],b:[s*.12,.47,0],r:.11,color:'$cloth',name:'thigh_'+side,blend:.03},
 {type:'capsule',seg:'shin_'+side,a:[s*.12,.43,0],b:[s*.12,.14,0],r:.085,color:'$cloth',name:'shin_'+side,blend:.02},
 {type:'box',seg:'shin_'+side,c:[s*.12,.07,.065],size:[.19,.14,.30],round:.045,color:'$bronze',material:'iron',name:'boot_'+side,blend:.02},
 {type:'box',seg:'shin_'+side,c:[s*.12,.025,.065],size:[.20,.045,.32],round:.02,color:'$dark',name:'sole_'+side,op:'sharp'},
 H.wrap({seg:'farm_'+side,a:[s*.3,.97,0],b:[s*.3,.85,0],r:.09,turns:3,color:'$edge',name:'rib_'+side}));
}
module.exports={id:'f_knell',creature:'game/content/core/creatures/f_knell.json',out:'creatures/f_knell.glb',resolution:.009,target_tris:14000,blend:.025,palette:P,
 materials:{cloth:{roughness:.9},skin:{roughness:.85},iron:{roughness:.48,metallic:.65},soul:{roughness:.22,emissive:'#AC8DFF'}},parts,
 paints:[{type:'spots',target:{materials:['iron']},cell:.07,radius:.013,density:.18,seed:15,color:'$rust'}],
 gore:{resolution:.004,target_tris:250,color:'$bronze',parts:[{type:'cylinder',a:[0,0,0],b:[0,.09,0],r:.055,color:'$bronze',material:'iron'}]}};
