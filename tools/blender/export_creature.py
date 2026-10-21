"""Export an editable Critterweight .blend through the project's GLB writer.

Blender coordinates are (x,-z,y) relative to fighter space. Only objects marked
cw_role=body/gore ship; imported references, lights and helpers never ship.
"""
import argparse
import json
import hashlib
import pathlib
import subprocess
import sys
import tempfile
import bpy
from mathutils import Vector

ROOT = pathlib.Path(__file__).resolve().parents[2]

def fighter(v):
    return [round(v.x, 7), round(v.z, 7), round(-v.y, 7)]

def extract(objects, bone_ids, skinned):
    positions, normals, colors, joints, weights = [], [], [], [], []
    groups, unique = {}, {}
    for obj in sorted(objects, key=lambda o: o.name):
        unsupported = [m.name for m in obj.modifiers if m.type != "ARMATURE"]
        if unsupported:
            raise ValueError(f"{obj.name}: apply geometry modifiers before export: {unsupported}")
        mesh = obj.data
        if mesh.shape_keys is not None:
            raise ValueError(f"{obj.name}: shape-key export is not implemented; preserve this source and add explicit view support first")
        mesh.calc_loop_triangles()
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        color = mesh.color_attributes.get('Color')
        if color is None:
            raise ValueError(f'{obj.name}: missing Color vertex attribute')
        vertex_weights = []
        for vertex in mesh.vertices:
            entries = [(bone_ids.index(obj.vertex_groups[g.group].name), g.weight)
                       for g in vertex.groups if obj.vertex_groups[g.group].name in bone_ids and g.weight > 0.00001]
            if skinned and (not entries or len(entries) > 4):
                raise ValueError(f'{obj.name}: vertex {vertex.index} has {len(entries)} weights')
            entries.sort(key=lambda entry: (-entry[1], entry[0]))
            total = sum(w for _, w in entries) or 1
            vertex_weights.append(([(j) for j, _ in entries] + [0] * (4-len(entries)),
                                   [w/total for _, w in entries] + [0.] * (4-len(entries))))
        for tri in mesh.loop_triangles:
            material = obj.data.materials[tri.material_index]
            name = material.get('cw_material', material.name)
            indices = groups.setdefault(name, [])
            for loop_index in tri.loops:
                loop = mesh.loops[loop_index]
                vertex = mesh.vertices[loop.vertex_index]
                pos = fighter(obj.matrix_world @ vertex.co)
                normal = fighter((normal_matrix @ mesh.corner_normals[loop_index].vector).normalized())
                rgba = list(color.data[loop_index if color.domain == 'CORNER' else vertex.index].color)
                js, ws = vertex_weights[vertex.index]
                key = tuple(pos + normal + rgba + (js + ws if skinned else []))
                if key not in unique:
                    unique[key] = len(positions)//3
                    positions.extend(pos); normals.extend(normal); colors.extend(rgba)
                    if skinned:
                        joints.extend(js); weights.extend(ws)
                indices.append(unique[key])
    return dict(positions=positions, normals=normals, colors=colors,
                joints=joints if skinned else None, weights=weights if skinned else None,
                groups=[dict(material=k, indices=v) for k, v in groups.items()])

def export(out_path, scratch=None):
    # legacy skins (f_varga_legacy.glb: the v0.9.16 model kept byte for byte) are never written here
    if pathlib.Path(out_path).resolve().name.lower().endswith('_legacy.glb'):
        raise ValueError(f'refusing to export over a legacy skin: {out_path}')
    scene = bpy.context.scene
    manifest=json.loads((ROOT/'tools/blender/model_manifest.json').read_text(encoding='utf-8-sig'))
    entry=next(e for e in manifest if e['id']==scene['cw_id'])
    creature=json.loads((ROOT/entry['creature']).read_text(encoding='utf-8-sig'))
    digest=hashlib.sha256(json.dumps(creature['body'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
    if scene.get('cw_body_sha256') != digest:
        raise ValueError('Body contract differs from the source reference; review registration before exporting')
    bones = json.loads(scene['cw_bones'])
    # v0.9.17 view bones ("fx_*"): expression/secondary-motion joints the game animates; never
    # physics. Segment bones stay first so joint i < len(bones) is always segment i.
    view_bones = json.loads(scene.get('cw_view_bones', '[]'))
    bone_ids = [b['id'] for b in bones] + [v['id'] for v in view_bones]
    rig = next(o for o in scene.objects if o.get('cw_role') == 'rig')
    if set(bone_ids) != set(b.name for b in rig.data.bones):
        raise ValueError('Skeleton names changed')
    for v in view_bones:
        if not v['id'].startswith('fx_') or v['parent'] not in bone_ids[:bone_ids.index(v['id'])]:
            raise ValueError(f"View bone {v['id']} must be named fx_* and follow its parent {v['parent']}")
    for b in bones:
        actual = fighter(rig.matrix_world @ rig.data.bones[b['id']].head_local)
        if max(abs(a-c) for a, c in zip(actual, b['pivot'])) > 0.00001:
            raise ValueError(f"Pivot changed: {b['id']}")
    materials = {}
    for mat in bpy.data.materials:
        if 'cw_material' in mat:
            materials[mat['cw_material']] = dict(roughness=mat.roughness, metallic=mat.metallic)
    body = [o for o in scene.objects if o.type == 'MESH' and o.get('cw_role') == 'body']
    gore = [o for o in scene.objects if o.type == 'MESH' and o.get('cw_role') == 'gore']
    if not body or not gore:
        raise ValueError('Missing body or gore mesh')
    payload = dict(name=scene['cw_id'], generator='Critterweight Blender source / deterministic forge GLB writer', bones=bones, materials=materials,
                   view_bones=view_bones,
                   mesh=extract(body, bone_ids, True), gore=dict(mesh=extract(gore, [], False)),
                   extras=dict(author='Critterweight original art', body_sha256=digest, source='tools/blender/'+scene['cw_id']+'.blend',
                               pipeline='Blender editable meshes; deterministic forge GLB writer'))
    if scene.get('cw_look'):
        payload['extras']['look'] = json.loads(scene['cw_look'])
    for mesh in [payload['mesh'], payload['gore']['mesh']]:
        for group in mesh['groups']:
            if any(mesh['colors'][i*4+3] > .001 for i in group['indices']):
                materials[group['material']]['emissive']=[1,1,1]
    out_path = pathlib.Path(out_path).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    scratch = pathlib.Path(scratch or out_path.parent)
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='cw-export-', dir=scratch) as temp:
        data = pathlib.Path(temp)/'mesh.json'
        data.write_text(json.dumps(payload, separators=(',', ':')), encoding='utf8')
        subprocess.run(['node', str(ROOT/'tools/blender/write_glb.js'), str(data), str(out_path)], check=True)
    return payload

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', required=True)
    parser.add_argument('--scratch')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    export(args.out, args.scratch)
