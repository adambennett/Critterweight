"""Original editable mesh tools. All input coordinates are fighter rest space.
No remeshing, voxel grids, generated textures, external geometry or actions.
"""
import json
import hashlib
import math
import pathlib
import bpy
import bmesh
from mathutils import Vector

ROOT = pathlib.Path(__file__).resolve().parents[2]
TAU = math.tau


def blender(v):
    return (v[0], -v[2], v[1])


def rgba(hex_color, glow=0):
    values = [int(hex_color.lstrip('#')[i:i+2],16)/255 for i in (0,2,4)]
    return [v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in values] + [glow]


class Studio:
    def __init__(self, creature_id, reference):
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.object.delete(use_global=False)
        self.id = creature_id
        manifest = json.loads((ROOT/'tools/blender/model_manifest.json').read_text(encoding='utf-8-sig'))
        self.entry = next(e for e in manifest if e['id']==creature_id)
        self.creature = json.loads((ROOT/self.entry['creature']).read_text(encoding='utf-8-sig'))
        self.segments = {s['id']:s for s in self.creature['body']['segments']}
        bpy.ops.import_scene.gltf(filepath=str(reference))
        reference_objects = list(bpy.context.scene.objects)
        old_rig = next(o for o in reference_objects if o.type=='ARMATURE')
        for seg in self.segments.values():
            bone = old_rig.data.bones[seg['id']]
            p = old_rig.matrix_world @ bone.head_local
            actual = Vector((p.x,p.z,-p.y))
            if (actual-Vector(seg['pivot'])).length > 1e-5:
                raise ValueError('Imported reference pivot mismatch: '+seg['id'])
        refs = bpy.data.collections.new('REFERENCE - original forge mesh (not exported)')
        bpy.context.scene.collection.children.link(refs)
        for obj in reference_objects:
            for collection in list(obj.users_collection): collection.objects.unlink(obj)
            refs.objects.link(obj)
        refs.hide_render = True
        refs.hide_viewport = True
        self.collection = bpy.data.collections.new('EDITABLE - '+creature_id)
        bpy.context.scene.collection.children.link(self.collection)
        self.armature = bpy.data.armatures.new(creature_id+'_skeleton')
        self.rig = bpy.data.objects.new('Rig - exact body pivots', self.armature)
        self.collection.objects.link(self.rig)
        self.rig['cw_role']='rig'
        bpy.context.view_layer.objects.active=self.rig
        self.rig.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT')
        for seg in self.segments.values():
            bone=self.armature.edit_bones.new(seg['id'])
            bone.head=blender(seg['pivot'])
            bone.tail=bone.head+Vector((0,0,.06))
        bpy.ops.object.mode_set(mode='OBJECT')
        self.rig.show_in_front=True
        self.rig.select_set(False)
        self.materials={}
        # v0.9.17 adds material classes the creature shader shades differently (CreatureView.MATERIAL_KINDS)
        for name,rough,metal in [('skin',.86,0),('cloth',.95,0),('metal',.68,.35),('eye',.6,0),('team',.9,0),
                                 ('shell',.32,0),('brass',.38,.8),('ember',.5,0),('jelly',.18,0),('ghost',.4,0),('glass',.12,0),('lamp',.2,0)]:
            mat=bpy.data.materials.new('CW '+name)
            mat['cw_material']=name
            mat.diffuse_color=(.8,.8,.8,1)
            mat.roughness=rough; mat.metallic=metal
            mat.use_nodes=True
            tree=mat.node_tree
            bsdf=tree.nodes.get('Principled BSDF')
            attr=tree.nodes.new('ShaderNodeVertexColor'); attr.layer_name='Color'
            tree.links.new(attr.outputs['Color'],bsdf.inputs['Base Color'])
            bsdf.inputs['Roughness'].default_value=rough
            bsdf.inputs['Metallic'].default_value=metal
            self.materials[name]=mat
        scene=bpy.context.scene
        scene['cw_id']=creature_id
        scene['cw_body_sha256']=hashlib.sha256(json.dumps(self.creature['body'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
        scene['cw_bones']=json.dumps([dict(id=s['id'],pivot=s['pivot']) for s in self.segments.values()])
        scene['cw_source_note']='Original Critterweight mesh. Reference GLB imported and bone heads verified. Fighter (x,y,z) maps to Blender (x,-z,y).'
        scene.unit_settings.system='METRIC'
        scene.render.engine='BLENDER_EEVEE'
        bpy.context.preferences.filepaths.temporary_directory=str(ROOT.parent/'tmp')

    def view_bone(self,bone_id,parent,head):
        """A view-only joint (v0.9.17): eyes, lids, jaws, crests, chains. The game animates it on
        top of its parent; it never touches the body contract (segment bones and pivots)."""
        if not bone_id.startswith('fx_'):
            raise ValueError('view bones are named fx_*: '+bone_id)
        known=[b['id'] for b in json.loads(bpy.context.scene.get('cw_view_bones','[]'))]
        if parent not in self.segments and parent not in known:
            raise ValueError('unknown parent for '+bone_id+': '+parent)
        bpy.context.view_layer.objects.active=self.rig
        self.rig.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT')
        bone=self.armature.edit_bones.new(bone_id)
        bone.head=blender(head)
        bone.tail=bone.head+Vector((0,0,.03))
        bone.parent=self.armature.edit_bones[parent]
        bpy.ops.object.mode_set(mode='OBJECT')
        self.rig.select_set(False)
        views=json.loads(bpy.context.scene.get('cw_view_bones','[]'))
        views.append(dict(id=bone_id,parent=parent,head=[round(float(x),6) for x in head]))
        bpy.context.scene['cw_view_bones']=json.dumps(views)
        return bone_id

    def mesh(self,name,verts,faces,bone,color,mat='skin',glow=0,soft=False,role='body',smooth=True):
        mesh=bpy.data.meshes.new(name)
        mesh.from_pydata([blender(v) for v in verts],[],faces)
        mesh.update()
        bm=bmesh.new(); bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
        bm.to_mesh(mesh); bm.free()
        for poly in mesh.polygons: poly.use_smooth=smooth
        obj=bpy.data.objects.new(name,mesh)
        self.collection.objects.link(obj)
        obj['cw_role']=role
        detail = name.startswith(('Detail ', 'Eye ', 'Nostril ', 'Smirk', 'Determined brow', 'Small newt tooth', 'Wrist wrap', 'Fist wrap seam', 'Toe cleft', 'Furnace ', 'Plate rivet', 'Latch', 'Stovepipe mouth'))
        if detail:
            key='detail_'+mat
            if key not in self.materials:
                detail_mat=self.materials[mat].copy()
                detail_mat.name='CW '+key
                detail_mat['cw_material']=key
                self.materials[key]=detail_mat
            mat=key
        mesh.materials.append(self.materials[mat])
        attr=mesh.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='POINT')
        for i, data in enumerate(attr.data):
            paint=color(verts[i]) if callable(color) else color
            data.color=rgba(paint,glow)
        if bone:
            group=obj.vertex_groups.new(name=bone)
            group.add(list(range(len(verts))),1,'REPLACE')
            if soft and 'parent' in self.segments[bone]:
                parent=obj.vertex_groups.new(name=self.segments[bone]['parent'])
                pivot=Vector(self.segments[bone]['pivot'])
                for i,v in enumerate(verts):
                    # Only the narrow overlap band near the actual pivot deforms.
                    d=(Vector(v)-pivot).length
                    w=.35*max(0,1-d/.11)
                    if w>0.001:
                        parent.add([i],w,'REPLACE'); group.add([i],1-w,'REPLACE')
            modifier=obj.modifiers.new('Body segment skin','ARMATURE')
            modifier.object=self.rig
        if role=='gore':
            obj.hide_render=True
            obj.hide_set(True)
        return obj

    def ellipsoid(self,name,c,r,bone,color,mat='skin',glow=0,n=20,m=10,soft=False,role='body'):
        verts=[(c[0],c[1]-r[1],c[2])]
        for j in range(1,m):
            lat=-math.pi/2+math.pi*j/m
            for i in range(n):
                a=TAU*i/n
                verts.append((c[0]+r[0]*math.cos(lat)*math.cos(a),c[1]+r[1]*math.sin(lat),c[2]+r[2]*math.cos(lat)*math.sin(a)))
        verts.append((c[0],c[1]+r[1],c[2])); top=len(verts)-1
        faces=[]
        for i in range(n): faces.append((0,1+i,1+(i+1)%n))
        for j in range(m-2):
            for i in range(n):
                a=1+j*n+i; b=1+j*n+(i+1)%n
                faces.append((a,a+n,b+n,b))
        for i in range(n): faces.append((top,1+(m-2)*n+(i+1)%n,1+(m-2)*n+i))
        return self.mesh(name,verts,faces,bone,color,mat,glow,soft,role)

    def tube(self,name,points,radii,bone,color,mat='skin',glow=0,n=16,soft=False,role='body',closed=False,fan_caps=False):
        points=[Vector(p) for p in points]
        if isinstance(radii,(int,float)): radii=[radii]*len(points)
        verts=[]
        previous_u=None
        for j,p in enumerate(points):
            tangent=(points[(j+1)%len(points)]-points[j-1]).normalized() if closed else (points[min(j+1,len(points)-1)]-points[max(0,j-1)]).normalized()
            # Parallel transport prevents a sudden ring twist when a path turns.
            u=previous_u.copy() if previous_u is not None else Vector((1,0,0))
            if abs(u.dot(tangent))>.98: u=Vector((0,0,1))
            if abs(u.dot(tangent))>.98: u=Vector((0,1,0))
            u=(u-tangent*u.dot(tangent)).normalized(); v=tangent.cross(u)
            previous_u=u
            radius=radii[j]
            rx,ry=radius if isinstance(radius,(list,tuple)) else (radius,radius)
            for i in range(n):
                verts.append(tuple(p+u*(math.cos(TAU*i/n)*rx)+v*(math.sin(TAU*i/n)*ry)))
        faces=[]
        for j in range(len(points) if closed else len(points)-1):
            for i in range(n):
                a=j*n+i; b=j*n+(i+1)%n; c=((j+1)%len(points))*n+(i+1)%n; d=((j+1)%len(points))*n+i
                faces.append((a,b,c,d))
        if not closed:
            if fan_caps:
                # Explicit cap centres also let cosmetic fitting sample the actual flat surface.
                bottom=len(verts);verts.append(tuple(points[0]))
                top=len(verts);verts.append(tuple(points[-1]))
                for i in range(n):
                    faces.append((bottom,(i+1)%n,i))
                    faces.append((top,(len(points)-1)*n+i,(len(points)-1)*n+(i+1)%n))
            else:
                faces.append(tuple(range(n-1,-1,-1)))
                faces.append(tuple((len(points)-1)*n+i for i in range(n)))
        return self.mesh(name,verts,faces,bone,color,mat,glow,soft,role)

    def capsule(self,name,a,b,r,bone,color,mat='skin',n=16,soft=True):
        a,b=Vector(a),Vector(b); direction=(b-a).normalized()
        points=[]; radii=[]
        for t in [-math.pi/2,-math.pi/3,-math.pi/6,0]:
            points.append(a+direction*r*math.sin(t)); radii.append(max(.0001,r*math.cos(t)))
        for t in [0,math.pi/6,math.pi/3,math.pi/2]:
            points.append(b+direction*r*math.sin(t)); radii.append(max(.0001,r*math.cos(t)))
        return self.tube(name,points,radii,bone,color,mat,n=n,soft=soft)

    def box(self,name,c,size,bone,color,mat='skin',bevel=.02,role='body'):
        # Bevel geometry is applied into the editable source; no export-time modifier ambiguity.
        bpy.ops.mesh.primitive_cube_add(size=1,location=blender(c))
        obj=bpy.context.object; obj.name=name
        obj.dimensions=(size[0],size[2],size[1])
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        modifier=obj.modifiers.new('Soft manufactured edges','BEVEL'); modifier.width=bevel; modifier.segments=2
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        verts=[(v.co.x+c[0],v.co.z+c[1],-v.co.y+c[2]) for v in obj.data.vertices]
        faces=[tuple(p.vertices) for p in obj.data.polygons]
        bpy.data.objects.remove(obj,do_unlink=True)
        return self.mesh(name,verts,faces,bone,color,mat,role=role,smooth=False)

    def eye(self,name,c,scale,bone,iris='FFD23F',mood='bold'):
        x,y,z=c; w,h,d=scale
        self.ellipsoid(name+' socket',(x,y,z),(w*1.06,h*1.06,d*.9),bone,'342B31',n=16,m=8)
        self.ellipsoid(name+' sclera',(x,y,z+d*.35),(w,h,d),bone,'FFF3D4','eye',n=20,m=10)
        self.ellipsoid(name+' iris',(x-w*.10,y-h*.03,z+d*1.25),(w*.68,h*.76,d*.44),bone,iris,'eye',n=16,m=8)
        self.ellipsoid(name+' pupil',(x-w*.11,y-h*.02,z+d*1.61),(w*.49,h*.60,d*.23),bone,'212331','eye',n=14,m=8)
        self.ellipsoid(name+' glint',(x-w*.22,y+h*.22,z+d*1.79),(w*.12,h*.12,d*.15),bone,'FFFFFF','eye',n=8,m=4)

    # ---- v0.9.17 toolkit: rigged faces, patterns, contact shading, look metadata ----------------
    def rig_eye(self,name,c,scale,bone,side,iris='FFD23F',lid_color=None,pupil='212331',lid_depth=1.5):
        """An eye whose iris/pupil/glint ride fx_eye_<side> (they slide toward what the fighter looks at)
        and an upper lid on fx_lid_<side>: modelled CLOSED below its bone at the top of the eye; the game
        squashes it to a rim when open, stretches it to blink, squint or shut (CreatureFxRig)."""
        x,y,z=c; w,h,d=scale
        eye_bone=self.view_bone('fx_eye_'+side,bone,(x,y,z))
        lid_bone=self.view_bone('fx_lid_'+side,bone,(x,y+h*1.12,z))
        self.ellipsoid(name+' socket',(x,y,z),(w*1.08,h*1.08,d*.9),bone,'342B31',n=18,m=9)
        self.ellipsoid(name+' sclera',(x,y,z+d*.35),(w,h,d),bone,'FFF6DE','eye',n=22,m=11)
        self.ellipsoid(name+' iris',(x-w*.05,y-h*.03,z+d*1.25),(w*.64,h*.72,d*.44),eye_bone,iris,'eye',n=18,m=8)
        self.ellipsoid(name+' pupil',(x-w*.06,y-h*.02,z+d*1.61),(w*.42,h*.52,d*.23),eye_bone,pupil,'eye',n=14,m=8)
        self.ellipsoid(name+' glint',(x-w*.24,y+h*.25,z+d*1.82),(w*.13,h*.13,d*.15),eye_bone,'FFFFFF','eye',n=8,m=4)
        if lid_color:
            # closed lid: an ellipsoid shell slightly larger than the eye, in front of the iris
            self.ellipsoid('Detail lid '+name,(x,y,z+d*.55),(w*1.1,h*1.1,d*lid_depth),lid_bone,lid_color,'skin',n=20,m=10)
        return eye_bone,lid_bone

    def paint(self,obj,fn):
        """Recolour an object's vertices: fn(fighter_pos, fighter_normal, (r,g,b,a) linear) -> (r,g,b,a)."""
        attr=obj.data.color_attributes['Color']
        for v in obj.data.vertices:
            p=Vector((v.co.x,v.co.z,-v.co.y)); n=Vector((v.normal.x,v.normal.z,-v.normal.y))
            c=tuple(attr.data[v.index].color)
            attr.data[v.index].color=fn(p,n,c)

    def bake_ao(self,rays=16,distance=.14,strength=.5,skip_prefix=('Detail ','Eye ','Detail lid')):
        """Contact shading baked into the vertex colours: each vertex casts a fixed hemisphere of rays
        against every body mesh (rest pose); occluded vertices darken. Deterministic; no textures."""
        from mathutils.bvhtree import BVHTree
        bodies=[o for o in self.collection.objects if o.type=='MESH' and o.get('cw_role')=='body']
        # small parts (crests, gills, fronds, details) never cast contact shading: they would streak
        occluders=[o for o in bodies if not o.name.startswith(skip_prefix+('Dorsal crest','Tail crest','Gill','Toe','Spine','Fin','Feather','Tentacle','Frond'))]
        verts=[];polys=[]
        for o in occluders:
            base=len(verts)
            mw=o.matrix_world
            verts.extend([mw@v.co for v in o.data.vertices])
            polys.extend([[base+i for i in p.vertices] for p in o.data.polygons])
        tree=BVHTree.FromPolygons(verts,polys,all_triangles=False)
        golden=math.pi*(3-math.sqrt(5))
        dirs=[]
        for i in range(rays):
            zz=1-(i+.5)/rays; r=math.sqrt(max(0,1-zz*zz)); a=golden*i
            dirs.append(Vector((r*math.cos(a),r*math.sin(a),zz)))
        for o in bodies:
            if o.name.startswith(skip_prefix):
                continue
            attr=o.data.color_attributes['Color']; mw=o.matrix_world; nm=mw.to_3x3().inverted().transposed()
            for v in o.data.vertices:
                n=(nm@v.normal).normalized(); p=mw@v.co+n*.003
                t=n.orthogonal().normalized(); b=n.cross(t)
                occ=0.;tot=0.
                for dv in dirs:
                    d=(t*dv.x+b*dv.y+n*dv.z).normalized(); wgt=dv.z
                    hit=tree.ray_cast(p,d,distance)
                    if hit[0] is not None:
                        occ+=wgt*(1-hit[3]/distance)
                    tot+=wgt
                ao=1-strength*min(1,occ/max(tot,1e-6)*1.6)
                c=attr.data[v.index].color
                attr.data[v.index].color=(c[0]*ao,c[1]*ao,c[2]*ao,c[3])

    def set_look(self,look):
        """View-only presentation data exported into the GLB root extras (CreatureView reads 'look')."""
        bpy.context.scene['cw_look']=json.dumps(look,sort_keys=True)

    def fit(self,obj,bones,center,padding=.012):
        """Fit only authored torso surfaces to the locked collision envelope.
        Cosmetic features are deliberately separate and never projected.
        """
        shapes=[sh for bone in bones for sh in self.segments[bone]['shapes']]
        def distance(point):
            values=[]
            for sh in shapes:
                if sh['type']=='sphere':
                    values.append((point-Vector(sh['center'])).length-sh['radius'])
                elif sh['type']=='capsule':
                    a,b=Vector(sh['a']),Vector(sh['b']);ab=b-a
                    t=max(0,min(1,(point-a).dot(ab)/ab.length_squared))
                    values.append((point-a-ab*t).length-sh['radius'])
                else:
                    d=point-Vector(sh['center']);half=Vector(sh['size'])/2
                    q=Vector([abs(d[i])-half[i] for i in range(3)])
                    values.append(Vector([max(0,v) for v in q]).length+min(max(q),0))
            return min(values)
        center=Vector(center)
        for vertex in obj.data.vertices:
            point=Vector((vertex.co.x,vertex.co.z,-vertex.co.y))
            if distance(point)<=padding:continue
            lo,hi=0.,1.
            for _ in range(24):
                t=(lo+hi)/2
                if distance(center+(point-center)*t)>padding:hi=t
                else:lo=t
            vertex.co=blender(center+(point-center)*lo)
        obj.data.update()
        obj['cw_fit_bones']=','.join(bones)

    def surface_top(self,bone,x,z,low,high):
        """Vertical contact on a convex body union; low must begin inside it."""
        def inside(y):
            point=Vector((x,y,z))
            for sh in self.segments[bone]['shapes']:
                if sh['type']=='capsule':
                    a,b=Vector(sh['a']),Vector(sh['b']);ab=b-a
                    t=max(0,min(1,(point-a).dot(ab)/ab.length_squared))
                    if (point-a-ab*t).length<=sh['radius']:return True
                elif sh['type']=='sphere' and (point-Vector(sh['center'])).length<=sh['radius']:return True
            return False
        if not inside(low):raise ValueError('Surface ray starts outside '+bone)
        for _ in range(32):
            mid=(low+high)/2
            if inside(mid):low=mid
            else:high=mid
        return low

    def save(self,path):
        # Select the visible artwork for immediate editing on open.
        bpy.ops.object.select_all(action='DESELECT')
        body=[o for o in self.collection.objects if o.get('cw_role')=='body']
        for o in body: o.select_set(True)
        if body: bpy.context.view_layer.objects.active=body[0]
        bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
