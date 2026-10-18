"""Generate an authorized, resumable offline voice pack. No retries, no key in output."""
import argparse, json, hashlib, os, wave, io, audioop
from pathlib import Path
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
from breeze_api import request_bytes, request_json, remaining_key_credits
from configure_key import load_key, validate_key
ROOT=Path(__file__).resolve().parents[3]
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def prepare(raw, target):
    with wave.open(io.BytesIO(raw),'rb') as wav:
        channels,width,rate=wav.getnchannels(),wav.getsampwidth(),wav.getframerate()
        pcm=wav.readframes(wav.getnframes())
    if channels==2: pcm=audioop.tomono(pcm,width,.5,.5)
    elif channels!=1: raise ValueError('Unexpected WAV channel count')
    if width!=2: pcm=audioop.lin2lin(pcm,width,2)
    # Remove excess leading/trailing silence, retaining 45 ms handles; short fades prevent clicks.
    window=max(1,rate//100)*2
    active=[i for i in range(0,len(pcm),window) if audioop.rms(pcm[i:i+window],2)>100]
    if not active: raise ValueError('Silent generation: retained raw take for review')
    handle=int(rate*.045)*2
    pcm=pcm[max(0,active[0]-handle):min(len(pcm),active[-1]+window+handle)]
    peak=audioop.max(pcm,2); rms=max(1,audioop.rms(pcm,2))
    gain=min(32767*.708/peak,32767*.1/rms,3.0)
    pcm=audioop.mul(pcm,2,gain)
    fade=min(int(rate*.006),len(pcm)//4)
    pcm=b''.join(audioop.mul(pcm[i*2:i*2+2],2,(i/max(1,fade))) for i in range(fade))+pcm[fade*2:]
    end=len(pcm)-fade*2
    pcm=pcm[:end]+b''.join(audioop.mul(pcm[end+i*2:end+i*2+2],2,1-i/max(1,fade)) for i in range(fade))
    target.parent.mkdir(parents=True,exist_ok=True)
    with wave.open(str(target),'wb') as wav:
        wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(rate); wav.writeframes(pcm)
    return {'seconds':len(pcm)/2/rate,'sample_rate':rate,'peak_dbfs':round(20*__import__('math').log10(max(1,audioop.max(pcm,2))/32768),2),'sha256':digest(target)}
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--generate',action='store_true');ap.add_argument('--max-credits',type=Decimal,default=Decimal('3500'));ap.add_argument('--limit',type=int,default=0)
    args=ap.parse_args()
    plan=json.loads((ROOT/'docs/audio/breeze/plan.json').read_text(encoding='utf-8'))
    rawdir=Path('B:/Critterweight/release-work/v0.9.15-preview2/breeze-raw');rawdir.mkdir(exist_ok=True)
    outdir=ROOT/'game/assets/audio/speech';outdir.mkdir(parents=True,exist_ok=True)
    ledger=ROOT/'docs/audio/breeze/generation-ledger.jsonl'
    records=[json.loads(s) for s in ledger.read_text(encoding='utf-8').splitlines()] if ledger.exists() else []
    complete={r['id']:r for r in records if r['status']=='complete'}
    started={r['id'] for r in records if r['status']=='requested'}
    uncertain=started-set(complete)
    if uncertain: raise RuntimeError('Unresolved prior requests; inspect provider history before any retry: '+str(sorted(uncertain)))
    pending=[]
    for id,item in plan['clips'].items():
        if id in complete:
            r=complete[id]
            if any(r.get(k)!=item.get(k) for k in ['text','voice_id','instructions']) or r.get('model_id')!=plan['model_id'] or digest(outdir/(id+'.wav'))!=r['sha256']: raise RuntimeError('Completed take changed: '+id)
        else:
            if (outdir/(id+'.wav')).exists() or (rawdir/(id+'.wav')).exists(): raise RuntimeError('Unjournaled file exists; inspect before a paid request: '+id)
            pending.append(item)
    estimate=sum(Decimal(str(x['estimated_credits'])) for x in complete.values()) + Decimal(sum(len(x['text']) for x in pending))/10
    print('Plan: {} clips; {} pending; {} credits total, cap {}.'.format(len(plan['clips']),len(pending),estimate,args.max_credits),flush=True)
    if estimate>args.max_credits: raise RuntimeError('Batch exceeds authorization')
    if not args.generate:return
    key=validate_key(os.environ.get('BREEZE_API_KEY','').strip() or load_key() or '')
    counters=request_json('/v1/api-keys/current',key)['api_key']
    safe={k:counters.get(k) for k in ['status','credit_limit','credit_used','credit_reserved','credit_remaining']}
    print('Key budget: '+json.dumps(safe),flush=True)
    (rawdir/'budget-start.json').write_text(json.dumps(safe,indent=2),encoding='utf-8') if not (rawdir/'budget-start.json').exists() else None
    needed=Decimal(sum(len(x['text']) for x in pending))/10
    if remaining_key_credits(key,True)<needed: raise RuntimeError('Key budget does not cover pending clips')
    def log(entry):
        with ledger.open('a',encoding='utf-8') as f:f.write(json.dumps(entry,ensure_ascii=False)+'\n');f.flush();os.fsync(f.fileno())
    def one(item):
        payload={'text':item['text'],'model_id':plan['model_id'],'language_code':'en','instructions':item['instructions'],'voice_settings':{'guidance_scale':2.0}}
        raw=request_bytes('/v1/text-to-speech/'+item['voice_id']+'?output_format=wav',key,payload,accept='audio/wav')
        if raw[:4]!=b'RIFF' or raw[8:12]!=b'WAVE':raise RuntimeError('Not a WAV response')
        rawpath=rawdir/(item['id']+'.wav')
        with rawpath.open('xb') as f:f.write(raw)
        metrics=prepare(raw,outdir/(item['id']+'.wav'))
        return dict(item,status='complete',model_id=plan['model_id'],language_code='en',estimated_credits=len(item['text'])/10,raw_sha256=digest(rawpath),raw_path=str(rawpath),utc=datetime.now(timezone.utc).isoformat(),**metrics)
    if args.limit:pending=pending[:args.limit]
    # Two independent short requests at a time; every submitted request is journaled first.
    with ThreadPoolExecutor(max_workers=2) as pool:
        for offset in range(0,len(pending),2):
            batch=pending[offset:offset+2]
            allowance=remaining_key_credits(key,True)
            if allowance<Decimal(sum(len(x['text']) for x in batch))/10:raise RuntimeError('Provider budget exhausted; no more requests sent')
            for item in batch:log({'id':item['id'],'status':'requested','voice_id':item['voice_id'],'text':item['text'],'estimated_credits':len(item['text'])/10,'utc':datetime.now(timezone.utc).isoformat()})
            jobs=[pool.submit(one,item) for item in batch];errors=[]
            for item,job in zip(batch,jobs):
                try:
                    result=job.result();log(result);complete[item['id']]=result
                    print('Saved {}/{} {} {} ({:.2f}s)'.format(len(complete),len(plan['clips']),item['voice'],item['id'],result['seconds']),flush=True)
                except Exception as e:errors.append(str(e))
            if errors:raise RuntimeError('; '.join(errors)+'; no retries made')
    if all(id in complete for id in plan['clips']):
        catalog={k:plan[k] for k in ['version','voices','cast','fixed_tokens','tokens','lines']}
        catalog['clips']={id:{'path':'res://assets/audio/speech/'+id+'.wav','seconds':complete[id]['seconds'],'sha256':complete[id]['sha256'],'voice':x['voice']} for id,x in plan['clips'].items()}
        (outdir/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        end=request_json('/v1/api-keys/current',key)['api_key'];safe={k:end.get(k) for k in ['status','credit_limit','credit_used','credit_reserved','credit_remaining']}
        (ROOT/'docs/audio/breeze/budget-final.json').write_text(json.dumps(safe,indent=2)+'\n',encoding='utf-8')
        print('Complete. Provider budget: '+json.dumps(safe),flush=True)
if __name__=='__main__':main()
