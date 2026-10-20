"""Build the first original Blender source, preserving the imported forge skeleton."""
import argparse
import math
import pathlib
import sys
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from mesh_tools import Studio, ROOT
from export_creature import export
from fighters import jitters, dredge, slurry, gusto, dozer
from bosses import bilge, conduit, snappington
from minions import scrapling, blister, lamprey
import fighters_v17


def stoke(s):
    orange='D9532B'; light='ED7842'; cream='EDE6D6'; dark='393943'; soot='703025'
    # A tapered boiler torso stays within the immutable sphere/shoulder capsule.
    torso=s.tube('Body - continuous newt silhouette',[(0,.47,0),(0,.51,0),(0,.59,0),(0,.64,0),(0,.70,0),(0,.75,.01),(0,.81,.02),(0,.90,.035),(0,1.0,.04),(0,1.10,.02),(0,1.16,-.01),(0,1.215,-.01),(0,1.26,0),(0,1.29,.02)],
           [(.06,.06),(.21,.12),(.30,.175),(.315,.188),(.29,.18),(.225,.17),(.25,.215),(.295,.28),(.308,.305),(.30,.27),(.405,.17),(.37,.12),(.27,.09),(.11,.045)],'chest',orange,n=28)
    pelvis=torso.vertex_groups.new(name='pelvis')
    chest=torso.vertex_groups['chest']
    for v in torso.data.vertices:
        w=max(0,min(1,(v.co.z-.70)/.10))
        chest.add([v.index],w,'REPLACE'); pelvis.add([v.index],1-w,'REPLACE')
    s.fit(torso,['chest','pelvis'],(0,.74,0))
    # Furnace is a fitted skin plate, not an inflated second stomach.
    s.ellipsoid('Boiler iron plate',(0,.985,.264),(.221,.224,.083),'chest',dark,'metal',n=24,m=12)
    s.box('Furnace door rim',(0,.995,.331),(.257,.199,.026),'chest','877061','metal',.025)
    s.box('Furnace glass',(0,.995,.347),(.214,.157,.014),'chest','FF7A1A','metal',.017)
    glass=next(o for o in s.collection.objects if o.name=='Furnace glass')
    for c in glass.data.color_attributes['Color'].data: c.color[3]=1
    for y in [.953,1.006,1.059]:
        s.box('Furnace grille '+str(y),(0,y,.362),(.218,.011,.014),'chest',dark,'metal',.004)
    s.ellipsoid('Latch',(.143,.99,.349),(.025,.032,.018),'chest','9C8774','metal',n=16,m=8)
    for x in [-.14,.14]:
        s.ellipsoid('Plate rivet',(x,1.135,.296),(.013,.013,.009),'chest','B49C7D','metal',n=12,m=6)
    # Broad cheeks and an asymmetrical smirk fit the original 17 cm head sphere.
    s.ellipsoid('Head',(0,1.36,.07),(.167,.17,.168),'head',orange,n=24,m=10,soft=True)
    s.capsule('Neck',(0,1.235,.03),(0,1.31,.05),.093,'head',orange,n=12)
    s.ellipsoid('Muzzle',(0,1.313,.177),(.144,.075,.079),'head',light,n=24,m=12)
    s.ellipsoid('Lower jaw',(0,1.281,.172),(.131,.04,.073),'head','E9AF75',n=20,m=10)
    s.tube('Smirk',[(-.126,1.315,.217),(-.10,1.295,.24),(-.05,1.286,.255),(.02,1.287,.259),(.08,1.3,.244),(.125,1.331,.216)],.007,'head','532826',n=8)
    for x in [-.057,.063]:
        s.tube('Small newt tooth',[(x,1.297,.251),(x,1.281,.256),(x+.002,1.266,.253)],[.011,.008,.001],'head',cream,n=12)
    for side in [-1,1]:
        x=side*.085
        s.eye('Eye '+str(side),(x,1.407,.198),(.041,.046,.018),'head',iris='FFD23F')
        s.tube('Determined brow '+str(side),[(side*.037,1.447,.218),(side*.074,1.462,.209),(side*.12,1.449,.185)],[.012,.016,.008],'head',soot,n=10)
        s.ellipsoid('Nostril '+str(side),(side*.05,1.333,.251),(.01,.007,.004),'head',soot,n=12,m=6)
    s.tube('Stovepipe crest',[(0,1.49,.066),(0,1.515,.065),(0,1.551,.062),(0,1.561,.061)],[.042,.034,.035,.042],'head',dark,'metal',n=20)
    s.ellipsoid('Stovepipe mouth',(0,1.562,.061),(.033,.003,.033),'head','171E27','metal',n=20,m=6)
    for side,suffix in [(1,'l'),(-1,'r')]:
        x=.38*side
        s.capsule('Upper arm '+suffix,(x,1.13,0),(x,.84,0),.081,'uarm_'+suffix,orange)
        s.capsule('Forearm '+suffix,(x,.8,0),(x,.58,.02),.073,'farm_'+suffix,orange)
        s.ellipsoid('Wrapped fist '+suffix,(x,.5,.03),(.116,.12,.119),'farm_'+suffix,cream,'cloth',n=24,m=12)
        for i,y in enumerate([.57,.60,.63]):
            s.tube('Wrist wrap '+suffix+str(i),[(x,y-.012,.021),(x,y+.012,.021)],[.079,.078],'farm_'+suffix,cream,'cloth',n=20)
        for y in [.47,.51]:
            s.tube('Fist wrap seam '+suffix+str(y),[(x-.08,y,.112),(x-.04,y-.008,.143),(x+.03,y-.008,.146),(x+.075,y,.122)],.003,'farm_'+suffix,'B6A68C','cloth',n=6)
        s.tube('Team tape '+suffix,[(x,.994,0),(x,1.028,0)],[.083,.084],'uarm_'+suffix,'FFFFFF','team',n=24)
        leg=.15*side
        s.capsule('Thigh '+suffix,(leg,.57,0),(leg,.35,.055),.092,'thigh_'+suffix,orange)
        s.capsule('Shin '+suffix,(leg,.31,.058),(leg,.11,.01),.073,'shin_'+suffix,orange)
        s.ellipsoid('Newt foot '+suffix,(leg,.05,.054),(.075,.049,.13),'shin_'+suffix,light,n=20,m=10)
        for dx in [-.027,.027]:
            s.tube('Toe cleft '+suffix+str(dx),[(leg+dx,.084,.137),(leg+dx,.069,.177)],.0025,'shin_'+suffix,soot,n=6)
    s.tube('Short newt tail',[(0,.59,-.15),(0,.55,-.22),(0,.49,-.34),(0,.44,-.42),(0,.43,-.463)],[.074,.065,.058,.049,.002],'tail',orange,n=24,soft=True)
    s.tube('Gore - spare tooth',[(0,0,0),(0,.025,0),(.004,.05,0)],[.014,.012,.001],None,cream,n=16,role='gore')


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('id',choices=['f_stoke','f_jitters','f_dredge','f_slurry','f_gusto','f_dozer','f_varga','f_knell','boss_bilge','boss_conduit','boss_snappington','npc_scrapling','npc_blister','npc_kid_lamprey'])
    parser.add_argument('--reference-root',required=True)
    parser.add_argument('--out-source')
    parser.add_argument('--out-glb', help='export here instead of the shipped model path (scratch builds)')
    parser.add_argument('--v16', action='store_true', help='build the v0.9.10-v0.9.16 art (comparison only)')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    s=Studio(args.id,pathlib.Path(args.reference_root)/'creatures'/f'{args.id}.glb')
    builders={'f_stoke':stoke,'f_jitters':jitters,'f_dredge':dredge,'f_slurry':slurry,'f_gusto':gusto,'f_dozer':dozer,'boss_bilge':bilge,'boss_conduit':conduit,'boss_snappington':snappington,'npc_scrapling':scrapling,'npc_blister':blister,'npc_kid_lamprey':lamprey}
    if not args.v16:
        builders.update(fighters_v17.BUILDERS)   # v0.9.17 roster art (docs/ART_REVAMP.md)
    builders[args.id](s)
    s.save(args.out_source or ROOT/'tools/blender'/f'{args.id}.blend')
    out=pathlib.Path(args.out_glb) if args.out_glb else ROOT/'game/assets/models'/s.entry['out']
    if out.name.endswith('_legacy.glb'):
        raise SystemExit('refusing to export over a legacy skin: '+str(out))
    export(out,ROOT.parent/'tmp')
