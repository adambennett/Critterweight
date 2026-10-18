"""Build the offline speech script from authored game dialogue. Never calls an API."""
import json, re, hashlib
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'docs/audio/breeze'
VOICES = {'devon':'voc_g53htd8kmjsj','kendall':'voc_j66xnnsxfeet','coach_buck':'voc_b36c5rxpfuzb'}
CAST = {'barnaby':'devon','granny':'coach_buck','snappington':'devon','doc':'devon','ludlow':'devon','teddy':'kendall','needles':'kendall','kid':'kendall'}
DIRECTION = {
'barnaby':'A lively ringside sports announcer at a scrappy waterfront cage fight. Clear, brisk, playful; punch the joke, do not scream.',
'granny':'A gruff veteran boxing coach. Warm tough love, crisp practical instructions, dry wit. Natural speech, no shouting.',
'snappington':'A pompous league commissioner. Measured, officious, dry comic authority.',
'doc':'A brisk no-nonsense medic. Calm, clipped, dryly amused.',
'ludlow':'An old dock janitor sharing a secret. Relaxed, warm, a little gravelly.',
'teddy':'A shady but friendly bookie. Casual, quick, conspiratorial and wry.',
'needles':'An excitable supplement salesman. Slightly nervous, bright, comic sales patter, intelligible.',
'kid':'An eager young adult sparring rival hiding admiration. Energetic, cheeky and awkward.'}
items=[]; clips={}
def read(p): return json.loads((ROOT / p).read_text(encoding='utf-8-sig'))
def strings(obj, prefix):
    if isinstance(obj,str): yield prefix,obj
    elif isinstance(obj,list):
        for i,v in enumerate(obj): yield from strings(v,prefix+'_'+str(i))
    elif isinstance(obj,dict):
        for k,v in obj.items(): yield from strings(v,prefix+'_'+k)
def add(id,speaker,text,voice=None):
    if not text: return
    voice=voice or CAST[speaker]
    # Lower-case prose avoids TTS spelling emphatic all-caps words. Subtitles stay authored.
    parts=[]
    for fragment in re.split(r'(\{[a-z0-9_]+\})',text):
        if not fragment: continue
        if fragment.startswith('{') and fragment.endswith('}'):
            parts.append({'token':fragment[1:-1]}); continue
        spoken=fragment.strip().replace('*','').replace('—',', ').replace('–',', ')
        if not re.search(r'[A-Za-z0-9]',spoken): continue
        spoken=re.sub(r'\b[A-Z]{2,}\b',lambda m:m[0].title(),spoken)
        digest=hashlib.sha256((voice+'\n'+speaker+'\n'+spoken).encode()).hexdigest()[:20]
        clips[digest]={'id':digest,'speaker':speaker,'voice':voice,'voice_id':VOICES[voice],'text':spoken,
            'instructions':DIRECTION[speaker]+(' Speak only this phrase; it is part of a longer sentence.' if '{' in text else '')}
        parts.append({'clip':digest})
    items.append({'id':id,'speaker':speaker,'voice':voice,'template':text,'parts':parts})
for name in ['barnaby','barnaby_vintage','granny']:
    for x in read('game/content/core/announcer/'+name+'.json')['items']:
        # Kendall adds occasional comic color without changing written character identity.
        color = x['id'] in ['ann_big_05','ann_combo_05','ann_parry_06','ann_kd_03','ann_kd_08','ann_comeback_02'] or (x.get('trigger')=='idle' and x['id'].endswith(('02','04')))
        add(x['id'],x['speaker'],x['text'],'kendall' if color else None)
for npc in read('game/content/core/hub/npcs.json')['items']:
    for field in ['barks','talk','hit','run','lines']:
        for id,text in strings(npc.get(field,{}),npc['id']+'_'+field): add(id,npc['speaker'],text)
for ex in read('game/content/core/tutorial/exercises.json')['items']:
    def walk(obj,prefix):
        for k,v in obj.items():
            if k in ['intro','hint','success','rush'] and isinstance(v,str): add(prefix+'_'+k,'granny',v)
            elif isinstance(v,dict): walk(v,prefix+'_'+k)
    walk(ex,ex['id'])
for id,text in read('game/content/core/tutorial/jabs.json')['jabs'].items(): add('jab_'+id,'granny',text)
tm=(ROOT/'game/src/tutorial/tutorial_mode.gd').read_text(encoding='utf-8')
for i,text in enumerate(re.findall(r'_say\("hint", "([^"\n]+)"\)',tm)): add('tutorial_extra_'+str(i),'granny',text)
tape=(ROOT/'game/src/hub/ui/hub_tape_overlay.gd').read_text(encoding='utf-8').split('const LINES := [')[1].split(']')[0]
for i,text in enumerate(re.findall(r'"([^"\n]+)"',tape)): add('tape_'+str(i),'barnaby',text)
for x in read('game/content/core/hub/secrets.json')['items']: add(x['id']+'_hint','ludlow',x.get('hint',''))
add('granny_tooth','granny',"So that's where my tooth went. Keep it. It suits you.")
add('parts_progress','ludlow',"So far I've got {part_list}...")
add('recap_title','barnaby',"And they TAKE THE BELT! I'm crying! I'm ALWAYS crying!")
add('recap_win','barnaby',"Past Act 1, a boss down, and then {boss} in Act {act}! What a night!")
add('recap_loss','barnaby',"{boss} ends it in Act {act}! A heartbreaker! A STATISTIC!")
add('recap_walk','barnaby',"{fighter} walks out for {variant}, {difficulty} difficulty!")
add('recap_walk_dose','barnaby',"{fighter} walks out for {variant}, {difficulty} difficulty, DOSE {dose}!")
add('recap_kos','barnaby',"{kos} KNOCKOUTS on the night! I counted every one!")
# A small reusable actor vocabulary avoids hundreds of charged full-sentence variants.
words=['Rookie']+['Player '+str(i) for i in range(1,9)]+['Stoke','Dredge','Gusto','Dozer','Slurry','Jitters','Kid Lamprey','Scrapling','Blister','Bilge','Conduit','Commissioner Snappington','Pelter','The Dragon','your fighter','the boss']
# Owner-selected player-name Easter eggs; The Dragon already exists above.
custom_names=['Adam','Bennett','Jeremy','Austin','Kenny','Sam','McKenna','Kenna','Princess Jeremy','Princess Worm','The Werm','Jerm the Worm','Charizard','Volk','Blastoise','Pikachu']
words += custom_names
name_direction={'McKenna':' Pronounce McKenna muh-KEN-uh.', 'Kenna':' Pronounce Kenna KEN-uh.', 'Jerm the Worm':' Jerm rhymes with germ.', 'The Werm':' Pronounce Werm exactly like worm.', 'Charizard':' Pronounce Charizard CHAR-ih-zard.', 'Volk':' Pronounce Volk vohlk.', 'Blastoise':' Pronounce Blastoise BLAS-toys.', 'Pikachu':' Pronounce Pikachu PEE-kah-choo.'}
name_aliases={'princess werm':'princess worm','jerm the werm':'jerm the worm','the worm':'the werm'}
words += ['zero','one','two','three','four','five','six','seven','eight','nine','ten','eleven','twelve','thirteen','fourteen','fifteen','sixteen','seventeen','eighteen','nineteen','twenty','thirty','forty','fifty','sixty','seventy','eighty','ninety','hundred','many']
fixed={'light':'light attack','heavy':'heavy attack','guard':'guard','dodge':'dodge','grab':'grab','ability1':'your first ability','ability2':'your second ability','juice':'your ultimate','taunt':'taunt','pause':'pause','target':'change target','move':'the movement controls','l_names':'your three hit combination','heavy_name':'your heavy attack','charged_name':'your charged attack','ability1_name':'your first ability','juice_name':'your ultimate','part_list':'some of the parts'}
tokens={}
for voice in VOICES:
    tokens[voice]={}
    # Only coach needs control-binding and technique wording.
    vocabulary=words+(list(fixed.values()) if voice=='coach_buck' else ['your ultimate','some of the parts'])
    if voice=='devon': vocabulary += ['Fight Camp','Off the Street','Punching Bag','Amateur','Journeyman','Contender','Champion','Legend','standard']
    for word in dict.fromkeys(vocabulary):
        digest=hashlib.sha256((voice+'\ntoken\n'+word).encode()).hexdigest()[:20]
        clips[digest]={'id':digest,'speaker':'token','voice':voice,'voice_id':VOICES[voice],'text':word,
          'instructions':'Say this short name or phrase clearly as part of a sentence, with natural neutral inflection. No introduction.'+name_direction.get(word,'')}
        tokens[voice][word.lower()]=digest
    for alias,canonical in name_aliases.items(): tokens[voice][alias]=tokens[voice][canonical]
# Preserve first-lesson joke + instruction and the parts-progress suffix without generating duplicates.
base=list(items)
intro=next(x for x in base if x['id']=='tut_footwork_intro')
for jab in [x for x in base if x['id'].startswith('jab_')]:
    items.append(dict(id='combined_'+jab['id'],speaker='granny',voice='coach_buck',template=jab['template']+' '+intro['template'],parts=jab['parts']+intro['parts']))
partintro=next(x for x in base if x['id']=='npc_ludlow_lines_parts_intro')
progress=next(x for x in base if x['id']=='parts_progress')
items.append(dict(id='combined_parts',speaker='ludlow',voice='devon',template=partintro['template']+'  '+progress['template'],parts=partintro['parts']+progress['parts']))
plan={'version':1,'model_id':'breeze-tts-2','authorized_credits':3500,'voices':VOICES,'cast':CAST,'fixed_tokens':fixed,'tokens':tokens,'lines':items,'clips':clips}
plan['estimated_characters']=sum(len(x['text']) for x in clips.values())
plan['estimated_credits']=plan['estimated_characters']/10
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'lines':len(items),'clips':len(clips),'characters':plan['estimated_characters'],'credits':plan['estimated_credits'],'speakers':sorted(set(x['speaker'] for x in items))}))
print('Dynamic tokens:',sorted(set(p['token'] for x in items for p in x['parts'] if 'token' in p)))
if plan['estimated_credits']>3500: raise SystemExit('Plan exceeds authorized cap; do not generate.')
