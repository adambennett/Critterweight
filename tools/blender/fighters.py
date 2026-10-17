"""Original fighter meshes, in the locked fighter rest coordinate system."""
import math
from mathutils import Vector
from mesh_tools import rgba


def loop(s,name,c,rx,rz,bone,color,thickness=.008,ytilt=0,mat='metal',glow=0,n=32):
    pts=[(c[0]+rx*math.cos(i*math.tau/n),c[1]+ytilt*math.cos(i*math.tau/n),c[2]+rz*math.sin(i*math.tau/n)) for i in range(n)]
    return s.tube(name,pts,thickness,bone,color,mat,glow,n=6,closed=True)


def jitters(s):
    s.materials['skin'].roughness=.38
    s.ellipsoid('Jelly body',(0,.42,0),(.353,.351,.354),'body',lambda p: 'BDEFFF' if p[1]>.30 else '8ED5EE',n=40,m=24)
    # Opaque, painted jelly window: all exterior marks ride the body, as in the original.
    def jelly_front(x,y):
        return .354*math.sqrt(max(0,1-(x/.353)**2-((y-.42)/.351)**2))+.003
    verts=[(0,.295,jelly_front(0,.295))]
    for ring in range(1,4):
        for i in range(24):
            t=i*math.tau/24;x=.19*ring/3*math.cos(t);y=.295+.105*ring/3*math.sin(t)
            verts.append((x,y,jelly_front(x,y)))
    faces=[(0,i+1,(i+1)%24+1) for i in range(24)]
    for ring in range(2):
        for i in range(24):
            a=1+ring*24+i;b=1+ring*24+(i+1)%24
            faces.append((a,b,b+24,a+24))
    s.mesh('Detail coil window',verts,faces,'body','69ADC8')
    for j in range(3):
        y=.252+j*.041
        xy=[(-.14,y),(-.10,y-.009),(0,y-.013),(.10,y+.006),(.14,y+.018)]
        pts=[(x,yy,jelly_front(x,yy)+.004) for x,yy in xy]
        s.tube('Detail luminous coil '+str(j),pts,.006,'body','FFF27A','metal',glow=.8,n=8)
    s.ellipsoid('Internal coil',(0,.42,0),(.115,.115,.115),'coil','FFF27A','metal',glow=1,n=20,m=12)
    for side,suffix in [(1,'l'),(-1,'r')]:
        s.capsule('Lavender arm '+suffix,(side*.35,.48,.07),(side*.60,.44,.16),.058,'arm_'+suffix,'B59CE0',n=20)
        s.ellipsoid('Soft mitten '+suffix,(side*.63,.43,.18),(.069,.068,.072),'arm_'+suffix,'B59CE0',n=24,m=12)
        s.ellipsoid('Thumb '+suffix,(side*.61,.46,.219),(.027,.027,.04),'arm_'+suffix,'A28BCC',n=16,m=8)
        s.tube('Antenna stem '+suffix,[(side*.13,.74,-.02),(side*.17,.83,-.03),(side*.20,.90,-.04)],[.025,.023,.022],'antenna_'+suffix,'3C4650','metal',n=16,soft=True)
        s.ellipsoid('Antenna bulb '+suffix,(side*.21,.92,-.04),(.045,.047,.045),'antenna_'+suffix,'F7E04A','metal',glow=.85,n=24,m=12)
        s.eye('Eye '+suffix,(side*.115,.552,.291),(.065,.076,.023),'body',iris='6B6DAE')
        s.tube('Detail anxious brow '+suffix,[(side*.04,.657,.27),(side*.095,.672,.254),(side*.17,.64,.242)],[.009,.012,.007],'body','76619D',n=10)
        s.tube('Detail cheek '+suffix,[(side*.205,.46,.289),(side*.224,.445,.276)],.008,'body','BA9DDC',n=8)
    s.tube('Detail worried mouth',[(-.045,.424,.354),(-.018,.435,.361),(.01,.427,.363),(.042,.436,.352)],.007,'body','334457',n=8)
    s.tube('Battery cap',[(0,.751,0),(0,.787,0),(0,.799,0)],[.081,.081,.069],'body','3C4650','metal',n=28)
    s.tube('Battery terminal',[(0,.797,0),(0,.827,0)],[.035,.035],'body','83929C','metal',n=20)
    loop(s,'Team ring',(0,.216,0),.287,.289,'body','FFFFFF',.011,mat='team',n=40)
    s.tube('Gore battery cap',[(0,-.025,0),(0,.025,0),(0,.04,0)],[.06,.06,.03],None,'3C4650','metal',n=24,role='gore')


def dredge(s):
    rust='8C3B2B'; light='AB5337'; cream='E8D9B8'; dark='372F2D'
    heights=[.27,.32,.44,.58,.71,.82,.88,.90]
    radii=[(.36,.25),(.60,.46),(.71,.55),(.735,.59),(.68,.53),(.54,.42),(.36,.27),(.10,.09)]
    # Extra rings support a smooth girth and the existing cosmetic ring-fit sampler.
    dense_h=[];dense_r=[]
    for i in range(len(heights)-1):
        dense_h.extend([heights[i],(heights[i]+heights[i+1])/2])
        dense_r.extend([radii[i],tuple((a+b)/2 for a,b in zip(radii[i],radii[i+1]))])
    dense_h.append(heights[-1]);dense_r.append(radii[-1])
    shell=s.tube('Carapace - low broad shell',[(0,y,0) for y in dense_h],dense_r,'shell',lambda p: cream if p[1]<.47 else rust,n=48,fan_caps=True)
    s.fit(shell,['shell'],(0,.58,0))
    rim=loop(s,'Shell rim',(0,.51,0),.727,.576,'shell',light,.02,mat='skin',n=48)
    s.fit(rim,['shell'],(0,.58,0),.025)
    for side,suffix in [(1,'l'),(-1,'r')]:
        s.capsule('Eye stalk '+suffix,(side*.1,.84,.4),(side*.12,1.06,.42),.048,'head',cream,n=16)
        s.eye('Eye '+suffix,(side*.121,1.066,.446),(.045,.047,.018),'head',iris='9DB8BD')
        s.ellipsoid('Detail weary lid '+suffix,(side*.121,1.084,.467),(.047,.027,.024),'head',rust,n=20,m=8)
        bone='uclaw_'+suffix; sh=s.segments[bone]['shapes'][0]
        s.capsule('Claw arm '+suffix,sh['a'],sh['b'],sh['radius']*.97,bone,rust,n=20)
        bone='claw_'+suffix
        if side==1:
            p=[(.70,.72,.61),(.64,.72,.75),(.54,.71,.90),(.46,.70,.99)]
            r=[.087,.092,.086,.062]
        else:
            p=[(-.74,.74,.63),(-.68,.72,.77),(-.58,.68,.94),(-.5,.66,1.04)]
            r=[.151,.158,.143,.115]
        # Palm ends before the two tapered jaws, leaving a real, readable pincer gap.
        a=Vector(p[0]); mid=Vector(p[1]); end=Vector(p[-1]); radius=r[1]
        s.tube('Claw palm '+suffix,[a,mid],[r[0],radius],bone,light,n=28,soft=True)
        for up in [-1,1]:
            start=mid+Vector((0,up*radius*.48,0))
            knuckle=mid.lerp(end,.60)+Vector((0,up*radius*.67,.018))
            tip=end+Vector((0,up*radius*.16,radius*.63))
            s.tube('Pincer '+suffix+str(up),[start,knuckle,tip],[radius*.53,radius*.40,.006],bone,light if up>0 else rust,n=20)
            s.tube('Dark pincer tip '+suffix+str(up),[knuckle.lerp(tip,.55),tip],[radius*.23,.006],bone,dark,n=16)
    for bone in s.segments:
        if 'leg_' not in bone: continue
        sh=s.segments[bone]['shapes'][0]
        a,b=Vector(sh['a']),Vector(sh['b']);r=sh['radius']
        s.capsule('Walking leg '+bone,a,b,r*.96,bone,light if bone.startswith('uleg') else rust,n=14)
        if bone.startswith('lleg'):
            s.tube('Dark crab foot '+bone,[b+Vector((0,.04,0)),b+Vector((.01 if b.x>0 else -.01,-.06,0))],[r*.98,.015],bone,dark,n=12)
    for i,(x,z,size) in enumerate([(-.39,-.10,.063),(-.24,-.28,.049),(.31,-.13,.055),(.43,.09,.047)]):
        y=s.surface_top('shell',x,z,.58,1.10)-.003
        s.tube('Barnacle shell '+str(i),[(x,y-.027,z),(x,y+.031,z)],[size,size*.76],'shell','B9B3A6','skin',n=16)
        s.ellipsoid('Detail barnacle glow '+str(i),(x,y+.032,z),(size*.55,.009,size*.55),'shell','2E9BE0','metal',glow=.9,n=16,m=8)
    # Mooring chain follows the crusher, preserving its signature asymmetry.
    axis=Vector((.20,-.06,.32)).normalized();u=Vector((0,1,0));u=(u-axis*u.dot(axis)).normalized();v=axis.cross(u)
    for i in range(8):
        angle=i*math.tau/8; radial=u*math.cos(angle)+v*math.sin(angle);tangent=-u*math.sin(angle)+v*math.cos(angle)
        c=Vector((-.66,.71,.80))+radial*.165
        pts=[tuple(c+tangent*(.047*math.cos(k*math.tau/16))+axis*(.028*math.sin(k*math.tau/16))) for k in range(16)]
        s.tube('Crusher chain link '+str(i),pts,.009,'claw_r','7A7F85','metal',n=6,closed=True)
    s.tube('Team claw cuff',[(.445,.635,.405),(.49,.65,.44)],[.073,.074],'uclaw_l','FFFFFF','team',n=20)
    s.tube('Gore cutter tip',[(0,0,0),(0,.035,0),(.015,.075,0)],[.025,.02,.001],None,dark,n=16,role='gore')


def slurry(s):
    black='2A2F2E'; belly='C7E66B'; brass='B08A3E'
    # A continuous skin replaces the overlapping sausages. Weights blend only at existing pivots.
    pts=[(0,.13,-1.52),(0,.15,-1.43),(0,.16,-1.18),(0,.17,-1.14),(0,.17,-.8),(0,.18,-.76),(0,.20,-.42),(0,.24,-.35),(0,.32,-.04),(0,.48,.075),(0,.67,.13),(0,.72,.14),(0,1.04,.16),(0,1.08,.16),(0,1.36,.115),(0,1.44,.13)]
    radii=[.025,.075,.105,.11,.134,.139,.157,.162,.168,.168,.157,.155,.139,.137,.127,.10]
    body=s.tube('Continuous eel skin',pts,radii,'body3',black,n=32)
    centers=[(Vector(p),r) for p,r in zip(pts,radii)]
    groups={name:body.vertex_groups.get(name) or body.vertex_groups.new(name=name) for name in s.segments if name!='head'}
    regions=['body6','body6','body6','body5','body5','body4','body4','body3','body3','body3','body3','body2','body2','body1','body1','body1']
    for v in body.data.vertices:
        ring=v.index//32; bone=regions[ring]
        for group in groups.values(): group.remove([v.index])
        groups[bone].add([v.index],1,'REPLACE')
        # The two neighbouring rings straddling each pivot blend softly.
        if ring>0 and regions[ring-1]!=bone:
            groups[bone].add([v.index],.8,'REPLACE');groups[regions[ring-1]].add([v.index],.2,'REPLACE')
        if ring<len(pts)-1 and regions[ring+1]!=bone:
            groups[bone].add([v.index],.8,'REPLACE');groups[regions[ring+1]].add([v.index],.2,'REPLACE')
        p=Vector((v.co.x,v.co.z,-v.co.y)); center=centers[ring][0]
        front=(p.z-center.z)/radii[ring] if ring>8 else -(p.y-center.y)/radii[ring]
        if front>.35:body.data.color_attributes['Color'].data[v.index].color=rgba(belly)
    s.tube('Moray crown fin',[(0,1.68,.20),(0,1.748,.17),(0,1.735,.10),(0,1.66,.055)],[(.025,.012),(.022,.012),(.015,.008),(.003,.002)],'head','8BD426',glow=.3,n=12)
    s.ellipsoid('Eel head',(0,1.56,.2),(.157,.158,.16),'head',black,n=32,m=16,soft=True)
    s.capsule('Moray muzzle',(0,1.54,.28),(0,1.48,.48),.098,'head',black,n=24)
    s.ellipsoid('Detail lower jaw',(0,1.445,.411),(.093,.05,.16),'head',belly,n=28,m=12)
    s.tube('Detail moray grin',[(-.09,1.49,.46),(-.073,1.467,.535),(0,1.46,.575),(.07,1.476,.534),(.096,1.53,.44)],.009,'head','17231B',n=8)
    for side in [-1,1]:
        s.eye('Eye '+str(side),(side*.105,1.602,.284),(.048,.044,.02),'head',iris='E04FB0')
        s.tube('Detail sly brow '+str(side),[(side*.06,1.648,.294),(side*.105,1.642,.28),(side*.15,1.623,.248)],[.013,.018,.008],'head',black,n=12)
        s.tube('Detail fang '+str(side),[(side*.057,1.485,.548),(side*.056,1.449,.55),(side*.051,1.425,.54)],[.012,.008,.001],'head','EDE6D6',n=12)
        s.ellipsoid('Detail nostril '+str(side),(side*.04,1.515,.566),(.01,.007,.004),'head','151C18',n=12,m=6)
    for i,(bone,y,z,r) in enumerate([('body1',1.23,.135,.137),('body2',.90,.15,.156),('body3',.53,.09,.177)]):
        s.tube('Brass collar '+str(i),[(0,y-.023,z),(0,y+.023,z)],[r,r],bone,brass,'metal',n=32)
        loop(s,'Detail collar edge '+str(i),(0,y+.024,z),r,r,bone,'D5B96E',.005,n=32)
    # Short webbed frill stays close to the non-striking back of the neck.
    for i,(bone,y,z) in enumerate([('body1',1.24,-.015),('body2',.89,-.02),('body3',.53,-.08)]):
        verts=[(-.012,y-.12,z),(.012,y-.12,z),(-.008,y+.12,z),(.008,y+.12,z),(0,y+.06,z-.025),(0,y-.07,z-.025)]
        faces=[(0,2,4,5),(1,5,4,3),(0,1,3,2),(0,5,1),(2,3,4)]
        s.mesh('Webbed frill '+str(i),verts,faces,bone,'8BD426',glow=.25)
    s.tube('Team tail band',[(0,.17,-.85),(0,.17,-.89)],[.142,.142],'body5','FFFFFF','team',n=28)
    s.ellipsoid('Detail sludge drop',(.04,1.422,.535),(.015,.028,.012),'head','8BD426',glow=.8,n=16,m=8)
    s.tube('Gore fang',[(0,.03,0),(0,0,0),(.01,-.04,0)],[.015,.012,.001],None,'EDE6D6',n=16,role='gore')


def gusto(s):
    white='F2F2EC'; blue='7FA4B8'; black='2B2B2B'; orange='FF8A3D'
    s.capsule('Tern torso',(0,1,-.05),(0,1.22,.05),.215,'torso',white,n=28,soft=False)
    s.capsule('Long neck',(0,1.32,.1),(0,1.56,.14),.068,'neck',white,n=20)
    s.ellipsoid('Tern head',(0,1.7,.17),(.138,.139,.14),'head',white,n=28,m=14,soft=True)
    # Long, narrow beak covers the existing beak capsule; two clean planes suggest a smirk.
    s.tube('Upper tern beak',[(0,1.664,.292),(0,1.651,.40),(0,1.633,.52),(0,1.63,.561)],[(.058,.043),(.048,.034),(.033,.026),(.002,.002)],'head',orange,n=20)
    s.tube('Detail beak seam',[(-.049,1.641,.32),(-.038,1.625,.45),(0,1.617,.552),(.037,1.625,.45),(.049,1.642,.32)],.004,'head','77442A',n=6)
    for side in [-1,1]:
        s.ellipsoid('Detail sunglasses marking '+str(side),(side*.073,1.735,.272),(.063,.037,.021),'head',black,n=24,m=10)
        s.ellipsoid('Detail confident eye '+str(side),(side*.073,1.735,.292),(.036,.024,.008),'head','F5F4D9','eye',n=20,m=8)
        s.ellipsoid('Detail pupil '+str(side),(side*.069,1.735,.299),(.013,.017,.005),'head',black,'eye',n=16,m=8)
        s.ellipsoid('Detail glint '+str(side),(side*.065,1.741,.304),(.004,.004,.002),'head','FFFFFF','eye',n=8,m=4)
    # Swept, compact quiff: the turquoise streak is a separate close-fitting surface.
    s.tube('Pompadour',[(0,1.79,.13),(0,1.82,.12),(0,1.85,.18),(0,1.84,.24)],[(.09,.065),(.075,.055),(.06,.042),(.015,.012)],'head',white,n=24)
    s.tube('Detail quiff streak',[(.025,1.806,.19),(.022,1.829,.20),(.015,1.851,.245)],[.019,.019,.004],'head','35C1C9',glow=.6,n=12)
    for side,suffix in [(1,'l'),(-1,'r')]:
        for prefix in ['uwing_','lwing_']:
            bone=prefix+suffix; sh=s.segments[bone]['shapes'][0]
            s.capsule('Wing leading edge '+bone,sh['a'],sh['b'],sh['radius']*.96,bone,blue,n=20)
        # Feather vanes hug the thin wing capsule instead of widening the collision silhouette.
        for i,x in enumerate([.31,.44,.57,.72,.85,.98,1.10]):
            y=1.24+(x-.24)*.167 if x<.62 else 1.30-(x-.62)*.19
            z=-.02-(x-.24)*.1
            bone=('uwing_' if x<.62 else 'lwing_')+suffix
            s.tube('Flight feather '+suffix+str(i),[(side*x,y,z+.017),(side*(x+.012),y-.053,z-.012),(side*(x+.035),y-.097,z-.024)],[(.048,.014),(.041,.01),(.004,.002)],bone,(lambda p, yy=y: black if p[1]<yy-.075 else blue),n=12)
        for prefix in ['thigh_','shin_']:
            bone=prefix+suffix;sh=s.segments[bone]['shapes'][0]
            s.capsule('Long bird leg '+bone,sh['a'],sh['b'],sh['radius']*.96,bone,orange,n=18)
        x=.14*side
        s.ellipsoid('Webbed foot '+suffix,(x,.032,.025),(.06,.027,.09),'shin_'+suffix,orange,n=20,m=8)
        for toe in [-1,0,1]:
            s.capsule('Bird toe '+suffix+str(toe),(x+toe*.025,.029,.075),(x+toe*.053,.026,.216 if toe==0 else .19),.017,'shin_'+suffix,orange,n=10,soft=False)
        for j in range(3):
            y=.27+j*.035
            s.tube('Detail shin wrap '+suffix+str(j),[(x,y-.01,-.023),(x,y+.012,-.03)],[.048,.047],'shin_'+suffix,'EDE6D6','cloth',n=20)
        s.tube('Team wing tape '+suffix,[(side*.47,1.278,-.058),(side*.505,1.284,-.064)],[.062,.062],'uwing_'+suffix,'FFFFFF','team',n=20)
    s.capsule('Tail root',(0,.98,-.22),(0,.90,-.48),.048,'tail',white,n=18)
    for i,x in enumerate([-.035,0,.035]):
        s.tube('Tail feather '+str(i),[(x,.96,-.28),(x,.92,-.42),(x*1.4,.89,-.54)],[(.025,.012),(.025,.013),(.003,.002)],'tail',white,n=12)
    for i in range(3):
        s.tube('Gore feather '+str(i),[(i*.012,0,0),(i*.012,.05,.01),(i*.014,.12,.02)],[(.009,.004),(.014,.004),(.001,.001)],None,white,n=10,role='gore')


def dozer(s):
    skin='6E6A66'; plate='C7A160'; steel='9FA6AD'; dark='393938'
    points=[(0,.76,-.91),(0,.76,-.84),(0,.76,-.62),(0,.76,-.35),(0,.80,-.17),(0,.82,.0),(0,.82,.25),(0,.82,.45),(0,.82,.68),(0,.82,.80)]
    radii=[(.03,.03),(.20,.20),(.317,.317),(.32,.32),(.363,.36),(.376,.376),(.376,.376),(.376,.376),(.27,.27),(.06,.06)]
    obj=s.tube('Hog continuous body',points,radii,'chest',skin,n=36)
    s.fit(obj,['chest','pelvis'],(0,.8,-.05))
    pelvis=obj.vertex_groups.new(name='pelvis'); chest=obj.vertex_groups['chest']
    for v in obj.data.vertices:
        z=-v.co.y; w=max(0,min(1,(z+.4)/.24))
        chest.add([v.index],w,'REPLACE');pelvis.add([v.index],1-w,'REPLACE')
    s.capsule('Strong neck',(0,.80,.64),(0,.78,.82),.195,'neck',skin,n=24)
    s.ellipsoid('Hog head',(0,.78,.96),(.196,.196,.196),'head',skin,n=28,m=14,soft=True)
    # A curved shovel face follows the fixed snout box, with a sloping upper edge.
    profile=[(.603,.979),(.603,1.24),(.613,1.265),(.649,1.265),(.697,1.244),(.723,1.22),(.723,1.005),(.70,.979)]
    verts=[(x,y,z) for x in [-.228,.228] for y,z in profile]
    faces=[tuple(range(7,-1,-1)),tuple(range(8,16))]+[(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
    blade=s.mesh('Shovel snout',verts,faces,'head',steel,'metal',smooth=False)
    import bpy
    bevel=blade.modifiers.new('Shovel edge radius','BEVEL');bevel.width=.012;bevel.segments=2
    bpy.context.view_layer.objects.active=blade;bpy.ops.object.modifier_apply(modifier=bevel.name)
    s.box('Detail shovel lip',(0,.603,1.235),(.45,.027,.06),'head','C7CED2','metal',.01)
    s.ellipsoid('Pig nose',(0,.767,1.126),(.135,.066,.049),'head','89817A',n=28,m=12)
    for side in [-1,1]:
        s.eye('Eye '+str(side),(side*.118,.862,1.084),(.047,.052,.022),'head',iris='70523A')
        s.tube('Detail friendly brow '+str(side),[(side*.068,.915,1.087),(side*.112,.925,1.066),(side*.158,.905,1.033)],[.01,.013,.008],'head',dark,n=10)
        s.ellipsoid('Detail nostril '+str(side),(side*.055,.78,1.169),(.019,.022,.007),'head',dark,n=16,m=8)
        s.tube('Pig ear '+str(side),[(side*.15,.89,.89),(side*.171,.913,.884),(side*.18,.919,.9)],[(.035,.025),(.023,.014),(.003,.003)],'head',skin,n=16)
        s.ellipsoid('Detail inner ear '+str(side),(side*.171,.913,.9),(.019,.024,.007),'head','BA9A79',n=12,m=8)
    s.tube('Detail cheerful mouth',[(-.133,.707,1.151),(-.09,.695,1.17),(0,.69,1.178),(.09,.699,1.17),(.133,.72,1.151)],.005,'head',dark,n=8)
    s.tube('Shovel horn',[(0,.90,1.02),(0,.975,1.099),(0,1.05,1.18),(0,1.082,1.205)],[.048,.047,.04,.001],'head','D8D3C8',n=24)
    s.ellipsoid('Headlamp casing',(0,.969,.915),(.061,.041,.042),'head',dark,'metal',n=24,m=10)
    s.ellipsoid('Detail headlamp lens',(0,.976,.947),(.047,.03,.016),'head','FFE066','metal',glow=1,n=24,m=10)
    # Three ochre shoulder scutes, each sampled directly on the body's capsule radius.
    for i,z in enumerate([-.09,.14,.37]):
        verts=[]
        for dz in [-.09,.09]:
            for j in range(13):
                angle=-1.05+2.1*j/12
                verts.append((.39*math.sin(angle),.82+.39*math.cos(angle),z+dz))
        faces=[(j,j+1,j+14,j+13) for j in range(12)]
        obj=s.mesh('Shoulder armour '+str(i),verts,faces,'chest',plate,'skin')
        # Thickness makes the edge editable and preserves a clean rim without bulky volumes.
        bpy_mod=obj.modifiers.new('Plate thickness','SOLIDIFY');bpy_mod.thickness=.012
        import bpy
        bpy.context.view_layer.objects.active=obj
        bpy.ops.object.modifier_apply(modifier=bpy_mod.name)
    for bone in s.segments:
        if not (bone.startswith('thigh_') or bone.startswith('shin_')):continue
        sh=s.segments[bone]['shapes'][0]
        s.capsule('Hog leg '+bone,sh['a'],sh['b'],sh['radius']*.97,bone,skin,n=18)
        if bone.startswith('shin_'):
            foot=s.segments[bone]['shapes'][1]['center']
            s.ellipsoid('Cloven hoof '+bone,foot,(.074,.059,.082),bone,dark,n=20,m=10)
            x,y,z=foot
            s.tube('Detail hoof cleft '+bone,[(x,y+.042,z+.035),(x,y+.016,z+.081)],.004,bone,'B4AAA0',n=6)
    s.capsule('Short pig tail',(0,.76,-.72),(0,.62,-.96),.047,'tail',skin,n=20)
    s.tube('Team foreleg tape',[(.307,.40,.452),(.309,.435,.44)],[.093,.093],'thigh_fl','FFFFFF','team',n=24)
    s.tube('Gore horn tip',[(0,-.03,0),(0,.015,.015),(0,.06,.04)],[.023,.017,.001],None,'D8D3C8',n=16,role='gore')
