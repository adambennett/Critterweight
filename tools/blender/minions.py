"""Small, original minions with an inclusive 2,000-triangle target (including gore)."""
import math
from mathutils import Vector


def lean_capsule(s,name,a,b,r,bone,color,n=8,mat='skin'):
    a,b=Vector(a),Vector(b);direction=(b-a).normalized()
    pts=[a-direction*r,a-direction*r*.707,a,b,b+direction*r*.707,b+direction*r]
    return s.tube(name,pts,[.0001,r*.707,r,r,r*.707,.0001],bone,color,mat,n=n,soft=True)


def disc(s,name,c,rx,ry,bone,color,n=12,glow=0,mat='skin'):
    verts=[c]+[(c[0]+rx*math.cos(i*math.tau/n),c[1]+ry*math.sin(i*math.tau/n),c[2]) for i in range(n)]
    faces=[(0,i+1,(i+1)%n+1) for i in range(n)]
    return s.mesh(name,verts,faces,bone,color,mat,glow=glow)


def low_box(s,name,c,size,bone,color,mat='skin',role='body'):
    verts=[(c[0]+x*size[0]/2,c[1]+y*size[1]/2,c[2]+z*size[2]/2) for x,y,z in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
    faces=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)]
    return s.mesh(name,verts,faces,bone,color,mat,role=role,smooth=False)


def scrapling(s):
    tin='A7A9A0';rust='8C3B2B';dark='3E4346';yellow='FFD23F'
    s.box('Tin torso',(0,.52,0),(.30,.28,.26),'torso',tin,'metal',.022)
    s.ellipsoid('Scrapling head',(0,.78,.02),(.108,.108,.108),'head',tin,'metal',n=16,m=8)
    for bone in s.segments:
        if bone.startswith(('arm_','thigh_','shin_')):
            sh=s.segments[bone]['shapes'][0]
            lean_capsule(s,'Scrap limb '+bone,sh['a'],sh['b'],sh['radius']*.97,bone,rust,n=8)
            if bone.startswith('shin_'):
                sh=s.segments[bone]['shapes'][1]
                low_box(s,'Scrap boot '+bone,sh['center'],sh['size'],bone,dark)
    s.box('Bin lid shield',(.12,.45,.24),(.335,.335,.039),'arm_l',tin,'metal',.018)
    # Square rounded lid fits the existing shield box, unlike an undersized circular disc.
    s.box('Detail lid handle',(.12,.45,.269),(.085,.026,.022),'arm_l',dark,'metal',.009)
    pipe=s.segments['arm_r']['shapes'][1]
    lean_capsule(s,'Raised pipe',pipe['a'],pipe['b'],.024,'arm_r',dark,n=8,mat='metal')
    s.ellipsoid('Detail goggle lens',(0,.8,.125),(.073,.072,.019),'head',yellow,'eye',glow=.65,n=12,m=8)
    disc(s,'Detail single pupil',(.018,.8,.146),.026,.034,'head','242D32',n=12,mat='eye')
    disc(s,'Detail eye glint',(.009,.818,.147),.008,.009,'head','FFFFFF',n=8,mat='eye')
    pts=[(.081*math.cos(i*math.tau/16),.8+.079*math.sin(i*math.tau/16),.128) for i in range(16)]
    s.tube('Detail goggle rim',pts,.009,'head',dark,'metal',n=6,closed=True)
    s.tube('Detail cheeky smile',[(-.055,.734,.109),(0,.721,.121),(.06,.745,.105)],.005,'head',dark,n=6)
    low_box(s,'Detail crooked tooth',(.026,.723,.125),(.022,.024,.008),'head','EDE6D6')
    low_box(s,'Team chest tape',(0,.54,.133),(.13,.029,.008),'torso','FFFFFF','team')
    s.box('Gore bin lid',(0,0,0),(.30,.30,.035),None,tin,'metal',.017,role='gore')


def blister(s):
    green='8BD426';dark='4F7F1A';light='C7E66B'
    body=s.ellipsoid('Sludge egg',(0,.35,0),(.258,.328,.258),'core',green,n=20,m=14)
    s.fit(body,['core'],(0,.35,0))
    s.ellipsoid('Detail pale belly',(0,.332,.229),(.164,.186,.03),'core',light,n=16,m=10)
    for side,suffix in [(1,'l'),(-1,'r')]:
        lean_capsule(s,'Sludge nub '+suffix,(side*.25,.5,0),(side*.36,.6,-.04),.048,'nub_'+suffix,green,n=10)
        x=side*.085
        s.ellipsoid('Eye '+suffix+' sclera',(x,.462,.237),(.046,.062,.018),'core','F1F4B4','eye',n=12,m=6)
        s.ellipsoid('Eye '+suffix+' pupil',(x-side*.008,.46,.254),(.019,.035,.008),'core','293819','eye',n=8,m=6)
        disc(s,'Detail glint '+suffix,(x-side*.012,.48,.263),.006,.009,'core','FFFFFF',n=6,mat='eye')
        s.tube('Detail worried brow '+suffix,[(side*.04,.548,.222),(side*.076,.556,.213),(side*.132,.529,.197)],.007,'core',dark,n=6)
        pts=[(side*.20,.20,.13),(side*.23,.29,.13),(side*.215,.38,.15),(side*.22,.46,.115)]
        s.tube('Detail sac vein '+suffix,pts,.005,'core',dark,glow=.3,n=6)
    s.tube('Detail little smile',[(-.032,.378,.262),(0,.365,.268),(.043,.389,.259)],.005,'core',dark,n=6)
    s.tube('Team nub collar',[(.278,.527,-.011),(.295,.543,-.017)],[.05,.05],'nub_l','FFFFFF','team',n=10)
    s.ellipsoid('Gore nub',(0,0,0),(.04,.04,.04),None,green,n=10,m=6,role='gore')


def lamprey(s):
    cloth='3F4A5C';skin='6E8B8E';red='C23A2B';cream='F2EFE4';dark='222933'
    s.tube('Hoodie torso',[(0,.63,0),(0,.70,0),(0,.83,0),(0,.97,.01),(0,1.02,0),(0,1.06,0)],[(.12,.12),(.15,.14),(.168,.168),(.17,.17),(.245,.085),(.14,.05)],'chest',cloth,'cloth',n=12,soft=True)
    lean_capsule(s,'Trousers pelvis',(0,.6,-.01),(0,.27,0),.136,'pelvis',dark,n=8,mat='cloth')
    s.tube('Hood collar',[(0,1.025,.04),(0,1.09,.04),(0,1.14,.04)],[.14,.10,.08],'head',cloth,'cloth',n=8,soft=True)
    s.ellipsoid('Hood',(0,1.25,.022),(.177,.178,.17),'head',cloth,'cloth',n=14,m=7,soft=True)
    rim=[]
    for i in range(14):
        angle=i*math.tau/14;x=.129*math.cos(angle);dy=.135*math.sin(angle)
        z=.022+.17*math.sqrt(max(0,1-(x/.177)**2-(dy/.178)**2))+.008
        rim.append((x,1.25+dy,z))
    s.tube('Hood opening rim',rim,.009,'head','59687B','cloth',n=4,closed=True)
    # Face patch follows the head sphere, so the teeth remain at the registered mouth.
    verts=[(0,1.25,.205)]
    for i in range(16):
        angle=i*math.tau/16;x=.12*math.cos(angle);y=.125*math.sin(angle)
        verts.append((x,1.25+y,.04+math.sqrt(max(0,.16**2-x*x-y*y))+.004))
    s.mesh('Detail lamprey face',verts,[(0,i+1,(i+1)%16+1) for i in range(16)],'head',skin)
    disc(s,'Detail sucker mouth',(0,1.226,.209),.082,.082,'head','4A292C',n=16)
    pts=[(.088*math.cos(i*math.tau/16),1.226+.088*math.sin(i*math.tau/16),.202) for i in range(16)]
    s.tube('Detail sucker lip',pts,.01,'head',red,n=4,closed=True)
    for i in range(8):
        angle=i*math.tau/8
        c=Vector((.073*math.cos(angle),1.226+.073*math.sin(angle),.218))
        tangent=Vector((-math.sin(angle),math.cos(angle),0))*.012
        tip=Vector((.048*math.cos(angle),1.226+.048*math.sin(angle),.226))
        vertices=[tuple(c+tangent),tuple(c-tangent),tuple(c+Vector((0,0,-.012))),tuple(tip)]
        s.mesh('Detail tooth '+str(i),vertices,[(0,1,3),(1,2,3),(2,0,3),(0,2,1)],'head',cream,'eye',glow=.2)
    for side,suffix in [(1,'l'),(-1,'r')]:
        disc(s,'Detail fish eye '+suffix,(side*.056,1.332,.165),.024,.018,'head',cream,n=10,mat='eye')
        disc(s,'Detail fish pupil '+suffix,(side*.054,1.331,.167),.012,.014,'head',dark,n=8,mat='eye')
        for prefix in ['uarm_','farm_','thigh_','shin_']:
            bone=prefix+suffix;sh=s.segments[bone]['shapes'][0]
            lean_capsule(s,'Clothed limb '+bone,sh['a'],sh['b'],sh['radius']*.97,bone,cloth if 'arm' in prefix else dark,n=8,mat='cloth')
            if prefix=='farm_':
                c=s.segments[bone]['shapes'][1]['center']
                s.ellipsoid('Small fist '+suffix,c,(.081,.082,.083),bone,skin,n=8,m=6)
            if prefix=='shin_':
                sh=s.segments[bone]['shapes'][1]
                x,y,z=sh['center'];w,h,d=sh['size'];r=.018
                outline=[(-w/2+r,-d/2),(w/2-r,-d/2),(w/2,-d/2+r),(w/2,d/2-r),(w/2-r,d/2),(-w/2+r,d/2),(-w/2,d/2-r),(-w/2,-d/2+r)]
                verts=[(x+dx,y+dy,z+dz) for dy in [-h/2,h/2] for dx,dz in outline]
                faces=[tuple(range(7,-1,-1)),tuple(range(8,16))]+[(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
                s.mesh('Rounded sneaker '+suffix,verts,faces,bone,cream,'cloth',smooth=False)
        s.tube('Detail hoodie drawstring '+suffix,[(side*.055,1.06,.08),(side*.058,.97,.16),(side*.06,.92,.17)],.004,'chest',red,'cloth',n=4)
    for bone in ['tail1','tail2']:
        sh=s.segments[bone]['shapes'][0]
        lean_capsule(s,'Lamprey tail '+bone,sh['a'],sh['b'],sh['radius']*.97,bone,skin,n=8)
    low_box(s,'Detail hoodie pocket',(0,.79,.171),(.19,.08,.012),'chest',dark,'cloth')
    low_box(s,'Team hoodie label',(0,.735,.155),(.08,.025,.008),'chest','FFFFFF','team')
    s.mesh('Gore tooth',[(-.008,0,0),(.008,0,0),(0,0,-.009),(0,.026,.004)],[(0,1,3),(1,2,3),(2,0,3),(0,2,1)],None,cream,'eye',role='gore')
