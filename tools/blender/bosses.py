"""Original boss geometry. All pivots and collision envelopes are imported unchanged."""
import math
from mathutils import Vector
from fighters import loop


def bind_rings(obj,regions,n,blend=.2):
    names=sorted(set(regions))
    groups={name:obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name) for name in names}
    for vertex in obj.data.vertices:
        ring=vertex.index//n; name=regions[ring]
        for group in groups.values():group.remove([vertex.index])
        groups[name].add([vertex.index],1,'REPLACE')
        other=None
        if ring>0 and regions[ring-1]!=name:other=regions[ring-1]
        elif ring<len(regions)-1 and regions[ring+1]!=name:other=regions[ring+1]
        if other:
            groups[name].add([vertex.index],1-blend,'REPLACE');groups[other].add([vertex.index],blend,'REPLACE')


def bilge(s):
    skin='5A4E45'; cream='C6AD8C'; rust='8C3B2B'; dark='302B29'
    pts=[(0,1.26,-1.59),(0,1.26,-1.48),(0,1.26,-1.1),(0,1.28,-.6),(0,1.35,-.38),(0,1.42,-.2),(0,1.42,.3),(0,1.42,.7),(0,1.42,1.12),(0,1.42,1.30)]
    radii=[.035,.30,.495,.495,.55,.615,.615,.615,.44,.08]
    body=s.tube('Cannery hound body',pts,radii,'chest',lambda p: cream if p[1]<1.07 and p[2]>.1 else skin,n=40)
    bind_rings(body,['pelvis']*4+['chest']*6,40)
    s.fit(body,['chest','pelvis'],(0,1.35,0))
    neckpts=[(0,1.50,.9),(0,1.52,.97),(0,1.60,1.30),(0,1.64,1.36),(0,1.70,1.66),(0,1.73,1.78)]
    neck=s.tube('Long hound neck',neckpts,[.26,.258,.25,.22,.218,.18],'neck1',lambda p: cream if p[1]<1.5 else skin,n=32)
    bind_rings(neck,['neck1']*3+['neck2']*3,32)
    s.ellipsoid('Hound head',(0,1.78,1.9),(.298,.298,.298),'head',skin,n=36,m=20,soft=True)
    s.capsule('Cream dog muzzle',(0,1.68,2.05),(0,1.62,2.35),.165,'head',cream,n=28)
    s.ellipsoid('Detail dark open mouth',(0,1.548,2.31),(.147,.06,.187),'head','3C2525',n=28,m=12)
    s.ellipsoid('Lower jaw',(0,1.50,2.27),(.142,.045,.2),'head',cream,n=28,m=12)
    s.ellipsoid('Detail pink tongue',(.043,1.525,2.436),(.047,.019,.066),'head','C97B7A',n=24,m=10)
    s.ellipsoid('Dog nose',(0,1.702,2.449),(.085,.058,.053),'head',dark,n=28,m=14)
    for side in [-1,1]:
        s.eye('Eye '+str(side),(side*.16,1.89,2.109),(.064,.079,.027),'head',iris='815C39')
        s.tube('Detail gentle brow '+str(side),[(side*.08,1.985,2.093),(side*.146,2.001,2.054),(side*.219,1.951,2.016)],[.016,.021,.01],'head','87715B',n=12)
        s.tube('Floppy ear '+str(side),[(side*.2,1.97,1.83),(side*.245,1.89,1.82),(side*.255,1.74,1.81),(side*.235,1.72,1.84)],[(.045,.025),(.047,.025),(.039,.02),(.015,.01)],'head',dark,n=20)
        s.tube('Detail muzzle crease '+str(side),[(side*.12,1.63,2.40),(side*.15,1.60,2.33),(side*.17,1.66,2.23)],.009,'head','6C5443',n=8)
        s.ellipsoid('Detail nose hole '+str(side),(side*.04,1.70,2.495),(.018,.014,.006),'head','181C20',n=16,m=8)
        s.tube('Detail canine tooth '+str(side),[(side*.09,1.587,2.416),(side*.087,1.55,2.426),(side*.08,1.535,2.41)],[.018,.013,.001],'head','E8DFC8',n=16)
    s.tube('Detail drool strand',[(-.12,1.56,2.4),(-.12,1.5,2.41),(-.115,1.46,2.4)],[.007,.005,.009],'head','8BD426',glow=.4,n=10)
    for bone in s.segments:
        if not (bone.startswith('thigh_') or bone.startswith('shin_')):continue
        sh=s.segments[bone]['shapes'][0]
        s.capsule('Hound leg '+bone,sh['a'],sh['b'],sh['radius']*.97,bone,skin,n=24)
        if bone.startswith('shin_'):
            c=s.segments[bone]['shapes'][1]['center']
            s.ellipsoid('Dog paw '+bone,c,(.138,.095,.15),bone,cream,n=24,m=12)
            for dx in [-.05,.05]:
                s.tube('Detail paw crease '+bone+str(dx),[(c[0]+dx,c[1]+.06,c[2]+.07),(c[0]+dx,c[1]+.015,c[2]+.145)],.005,bone,dark,n=6)
    s.capsule('Dog tail',(0,1.38,-1.17),(0,1.1,-1.60),.076,'tail',skin,n=24)
    for i in range(10):
        t=i*math.tau/10; x=.275*math.cos(t);y=1.55+.275*math.sin(t)
        pts=[(x+.049*math.cos(k*math.tau/20),y+.04*math.sin(k*math.tau/20),1.18+.01*math.sin(k*math.tau/20)) for k in range(20)]
        s.tube('Rust collar link '+str(i),pts,.017,'neck1',rust,'metal',n=8,closed=True)
    for i in range(6):
        y=1.26-i*.09;z=1.1-(1.28-y)*.19
        pts=[(.038*math.cos(k*math.tau/16),y+.048*math.sin(k*math.tau/16),z) for k in range(16)]
        s.tube('Hanging chain link '+str(i),pts,.012,'chain',rust,'metal',n=8,closed=True)
    s.ellipsoid('Collar signal housing',(0,1.36,1.245),(.075,.075,.033),'neck1',dark,'metal',n=24,m=12)
    s.ellipsoid('Detail collar red light',(0,1.36,1.274),(.052,.052,.018),'neck1','E03A2B','metal',glow=1,n=24,m=12)
    s.tube('Team foreleg band',[(.43,.79,.574),(.432,.84,.566)],[.162,.162],'thigh_fl','FFFFFF','team',n=24)
    s.tube('Gore canine tooth',[(0,.045,0),(0,0,0),(.01,-.055,0)],[.025,.02,.001],None,'E8DFC8',n=20,role='gore')


def conduit(s):
    black='1E1E24';yellow='F7E04A';cyan='CFF4FF';copper='B87333'
    pts=[(0,.28,-3.14),(0,.28,-3.08),(0,.28,-2.34),(0,.28,-2.28),(0,.28,-1.54),(0,.28,-1.48),(0,.30,-.74),(0,.31,-.68),(0,.36,-.34),(0,.44,0),(0,.72,.12),(0,1.0,.19),(0,1.07,.2),(0,1.66,.3),(0,1.72,.3),(0,2.31,.26),(0,2.37,.25),(0,2.86,.12),(0,2.95,.17)]
    r=[.18,.197,.197,.228,.228,.247,.247,.256,.258,.258,.256,.25,.237,.23,.217,.21,.197,.197,.15]
    regions=['body7']*3+['body6']*2+['body5']*2+['body4']*5+['body3']*2+['body2']*2+['body1']*3
    obj=s.tube('Continuous insulated serpent',pts,r,'body4',black,n=40)
    bind_rings(obj,regions,40)
    for bone in ['body1','body2','body3','body4','body5','body6','body7']:
        sh=s.segments[bone]['shapes'][0];a,b=Vector(sh['a']),Vector(sh['b']);axis=(b-a).normalized();u=Vector((1,0,0));v=axis.cross(u)
        radius=sh['radius']+.006
        verts=[]
        for t_offset in [-.10,.10]:
            for i in range(48):
                t=i*math.tau/48
                c=a.lerp(b,.5+t_offset+.16*math.cos(t))
                verts.append(tuple(c+u*(radius*math.cos(t))+v*(radius*math.sin(t))))
        faces=[(i,(i+1)%48,(i+1)%48+48,i+48) for i in range(48)]
        s.mesh('Detail diagonal hazard band '+bone,verts,faces,bone,yellow,'skin')
        c=a.lerp(b,.08); seam=[tuple(c+u*(radius*math.cos(i*math.tau/40))+v*(radius*math.sin(i*math.tau/40))) for i in range(40)]
        s.tube('Detail luminous seam '+bone,seam,.007,bone,cyan,'metal',glow=.9,n=6,closed=True)
    s.ellipsoid('Serpent head',(0,3.05,.3),(.257,.257,.257),'head',black,n=36,m=20,soft=True)
    s.capsule('Electrical muzzle',(0,3,.42),(0,2.92,.78),.156,'head',black,n=28)
    s.ellipsoid('Detail lower jaw',(0,2.835,.66),(.146,.05,.244),'head','5B6567',n=28,m=12)
    s.tube('Detail jaw seam',[(-.145,2.94,.69),(-.12,2.862,.82),(0,2.852,.927),(.12,2.87,.82),(.151,2.97,.65)],.009,'head',cyan,'metal',glow=.5,n=10)
    for side in [-1,1]:
        s.eye('Eye '+str(side),(side*.16,3.115,.464),(.068,.066,.027),'head',iris=yellow)
        s.tube('Detail alert brow '+str(side),[(side*.08,3.19,.471),(side*.15,3.20,.429),(side*.22,3.16,.383)],[.015,.02,.008],'head',black,n=12)
        s.tube('Detail electrical fang '+str(side),[(side*.086,2.88,.87),(side*.082,2.82,.88),(side*.06,2.78,.85)],[.024,.018,.001],'head',cyan,n=16)
        s.ellipsoid('Detail nostril '+str(side),(side*.065,2.968,.914),(.015,.01,.006),'head','0E1319',n=16,m=8)
    crest=s.tube('Copper crown crest',[(0,3.27,.39),(0,3.34,.23),(0,3.30,.07),(0,3.25,-.012)],[(.087,.025),(.08,.024),(.055,.019),(.005,.003)],'head',copper,'metal',n=24)
    for side in [-1,1]:
        s.tube('Copper side crest '+str(side),[(side*.13,3.25,.26),(side*.17,3.28,.10),(side*.18,3.23,.035)],[(.04,.02),(.034,.017),(.003,.002)],'head',copper,'metal',n=16)
    for item in list(s.collection.objects):
        if item.name.startswith('Copper '):s.fit(item,['head'],(0,3.05,.3),.042)
    s.capsule('Plug cable',(0,.28,-3.12),(0,.27,-3.48),.155,'plug',black,n=24)
    s.box('Plug housing',(0,.28,-3.61),(.39,.29,.28),'plug',black,'skin',.04)
    s.box('Detail plug seam',(0,.28,-3.71),(.395,.295,.023),'plug',cyan,'metal',.025)
    for data in s.collection.objects['Detail plug seam'].data.color_attributes['Color'].data:data.color[3]=.9
    for side in [-1,1]:
        s.box('Plug terminal '+str(side),(side*.105,.28,-3.79),(.065,.105,.12),'plug',copper,'metal',.009)
    s.tube('Team cable band',[(0,.28,-1.9),(0,.28,-1.96)],[.234,.234],'body6','FFFFFF','team',n=32)
    s.tube('Gore electrical fang',[(0,.045,0),(0,0,0),(.015,-.065,0)],[.029,.021,.001],None,cyan,n=20,role='gore')


def snappington(s):
    moss='4F6B3A';gold='C9A227';olive='8A8C5A';dark='454735'
    shell=s.ellipsoid('Commissioner shell',(0,.85,0),(1.145,.548,.995),'shell',lambda p:'B3A26B' if p[1]<.63 else moss,n=64,m=32)
    s.fit(shell,['shell'],(0,.85,0))
    rim=loop(s,'Gold shell rim',(0,.67,0),1.13,.97,'shell',gold,.025,n=64)
    s.fit(rim,['shell'],(0,.85,0),.028)
    # Broad architectural scutes: a crown oval and six clean radial seams.
    for lat in [.35,.76]:
        rx=1.145*math.cos(lat);rz=.995*math.cos(lat);y=.85+.548*math.sin(lat)
        seam=loop(s,'Detail shell crown seam '+str(lat),(0,y,0),rx,rz,'shell',gold,.009,glow=.35,n=64)
        s.fit(seam,['shell'],(0,.85,0),.024)
    for j in range(8):
        angle=j*math.tau/8;pts=[]
        for i in range(16):
            lat=.05+.71*i/15
            pts.append((1.145*math.cos(lat)*math.cos(angle),.85+.548*math.sin(lat),.995*math.cos(lat)*math.sin(angle)))
        seam=s.tube('Detail radial shell seam '+str(j),pts,.009,'shell',gold,'metal',glow=.4,n=6)
        s.fit(seam,['shell'],(0,.85,0),.024)
    s.capsule('Turtle neck',(0,.97,1.07),(0,1.1,1.45),.166,'neck',olive,n=28)
    s.ellipsoid('Commissioner head',(0,1.2,1.68),(.237,.237,.237),'head',olive,n=36,m=20,soft=True)
    s.capsule('Snapping beak',(0,1.12,1.85),(0,1.05,2.05),.097,'head','B2A46F',n=24)
    s.tube('Beak hook',[(0,1.075,2.11),(0,1.027,2.14),(0,.986,2.12)],[.057,.035,.002],'head','B2A46F',n=20)
    s.ellipsoid('Detail turtle jaw',(0,1.008,1.987),(.087,.027,.133),'head',olive,n=24,m=12)
    s.tube('Detail stern mouth',[(-.088,1.064,1.982),(-.063,1.035,2.069),(0,1.031,2.104),(.063,1.044,2.069),(.088,1.073,1.98)],.006,'head',dark,n=8)
    for side in [-1,1]:
        s.eye('Eye '+str(side),(side*.127,1.291,1.862),(.06,.053,.024),'head',iris='A18943')
        s.ellipsoid('Detail skeptical eyelid '+str(side),(side*.127,1.311,1.865),(.062,.034,.025),'head',olive,n=24,m=12)
        s.tube('Detail stern brow '+str(side),[(side*.06,1.346,1.88),(side*.12,1.371,1.853),(side*.19,1.328,1.801)],[.015,.023,.008],'head',dark,n=12)
        pts=[]
        for i in range(32):
            angle=i*math.tau/32;x=side*.127+.073*math.cos(angle);y=1.293+.06*math.sin(angle)
            pts.append((x,y,1.68+math.sqrt(max(.001,.278**2-x*x-(y-1.2)**2))))
        s.tube('Reading glasses '+str(side),pts,.006,'head',gold,'metal',n=8,closed=True)
        s.tube('Detail cheek crease '+str(side),[(side*.11,1.23,1.886),(side*.16,1.217,1.83),(side*.18,1.232,1.782)],.005,'head','666D45',n=8)
    s.tube('Glasses bridge',[(-.054,1.294,1.908),(0,1.315,1.922),(.054,1.294,1.908)],.006,'head',gold,'metal',n=8)
    for bone in s.segments:
        if 'leg_' in bone or bone.startswith('uclaw_'):
            sh=s.segments[bone]['shapes'][0]
            s.capsule('Turtle limb '+bone,sh['a'],sh['b'],sh['radius']*.97,bone,olive,n=20)
            if bone.startswith('lleg_'):
                c=s.segments[bone]['shapes'][1]['center'];r=s.segments[bone]['shapes'][1]['radius']
                s.ellipsoid('Turtle foot '+bone,c,(r,.075,r),bone,dark,n=20,m=10)
    for side,suffix in [(1,'l'),(-1,'r')]:
        bone='claw_'+suffix;sh=s.segments[bone]['shapes'][0]
        a,b=Vector(sh['a']),Vector(sh['b']);r=sh['radius']
        s.capsule('Turtle claw '+suffix,a,b,r*.96,bone,olive,n=24)
        for i in [-1,0,1]:
            c=b+Vector((i*.065,-.025,.055))
            s.tube('Turtle nail '+suffix+str(i),[c,c+Vector((0,-.02,.11)),c+Vector((0,-.04,.15))],[.037,.025,.001],bone,dark,n=14)
    # A short held gavel sits on the front of the right claw's existing sphere.
    # Its head is readable in combat without extending the weapon's physical reach.
    handle=s.tube('Held gavel handle',[(-.85,.69,1.64),(-.85,.86,1.665),(-.85,.91,1.66)],[.027,.027,.026],'claw_r','704928','skin',n=16)
    s.fit(handle,['claw_r'],(-.85,.85,1.5),.028)
    head=s.tube('Held gavel head',[(-1.025,.925,1.665),(-1.01,.925,1.665),(-.69,.925,1.665),(-.675,.925,1.665)],[.055,.079,.079,.055],'claw_r','986039','skin',n=24)
    s.fit(head,['claw_r'],(-.85,.85,1.5),.028)
    for x in [-.98,-.72]:
        band=s.tube('Gavel brass band '+str(x),[(x-.012,.925,1.665),(x+.012,.925,1.665)],[.082,.082],'claw_r',gold,'metal',n=24)
        s.fit(band,['claw_r'],(-.85,.85,1.5),.030)
    s.capsule('Turtle tail',(0,.68,-.97),(0,.5,-1.3),.096,'tail',olive,n=20)
    s.tube('Team claw cuff',[(.78,.83,.65),(.83,.85,.685)],[.134,.134],'uclaw_l','FFFFFF','team',n=24)
    for side in [-1,1]:
        pts=[(side*.06+.047*math.cos(i*math.tau/24),.038*math.sin(i*math.tau/24),0) for i in range(24)]
        s.tube('Gore glasses '+str(side),pts,.006,None,gold,'metal',n=6,closed=True,role='gore')
    s.tube('Gore glasses bridge',[(-.013,0,0),(0,.01,0),(.013,0,0)],.006,None,gold,'metal',n=6,role='gore')
