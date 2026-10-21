const fs=require('fs'),path=require('path'),cp=require('child_process');
const root=path.resolve(__dirname,'../..');
function verify(args,expect){
 const result=cp.spawnSync(process.execPath,[path.join(root,'tools/forge/forge.js'),...args],{cwd:root,encoding:'utf8'});
 const output=result.stdout+result.stderr;
 if(result.status===0 || !output.includes(expect))throw Error('Ownership guard failed: '+args.join(' '));
 console.log('PASS rejected '+args.join(' '));
}
verify(['f_stoke'],'Blender source owns');
verify(['boss_bilge'],'Blender source owns');
verify(['npc_blister'],'Blender source owns');
verify(['--legacy'],'outside game/assets/models');
verify(['--legacy','--out',path.join(root,'game/assets/models/creatures')],'outside game/assets/models');
const list=cp.spawnSync(process.execPath,[path.join(root,'tools/forge/forge.js'),'--list'],{encoding:'utf8'});
// 12 since the 2026-10-16 revamp, + f_knell in v0.9.17 (f_varga is Blender-owned too but never had a forge definition)
if(list.status!==0 || (list.stdout.match(/\[Blender source\]/g)||[]).length!==13)throw Error('Expected 13 Blender owners');
verify(['f_knell'],'Blender source owns');
console.log('PASS lists 13 Blender-owned models');
