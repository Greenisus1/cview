import re,sys
SRC='/root/crunchbyte-test-v9.py'
DST='/root/crunchbyte-test-v10.py'
if len(sys.argv)>2:SRC,DST=sys.argv[1],sys.argv[2]
s=open(SRC).read()
def fail(w):
    print('PATCH FAILED, not found once:',w[:60]);sys.exit(1)
def sub(old,new):
    global s
    if s.count(old)!=1:fail(old)
    s=s.replace(old,new)
# 1 server: stream the answer as newline-separated JSON with a keepalive every 10 s
a=s.find("        try:\n            if choice['type']=='hosted':")
b=s.find("        finally:lock.release()")
if a<0 or b<a or s.count("        finally:lock.release()")!=1:fail('chat block')
NEW='''        try:
            self.send_response(200)
            self.send_header('Content-Type','application/x-ndjson');self.send_header('Cache-Control','no-store, no-transform')
            self.send_header('X-Accel-Buffering','no');self.send_header('X-Content-Type-Options','nosniff');self.send_header('Connection','close')
            self.end_headers()
            wl=threading.Lock();done=threading.Event()
            def emit(o):
                with wl:
                    self.wfile.write((json.dumps(o)+'\\n').encode());self.wfile.flush()
            def beat():
                while not done.wait(10):
                    try:emit({'k':1})
                    except Exception:return
            threading.Thread(target=beat,daemon=True).start()
            try:
                emit({'k':1})
                payload=json.dumps({'model':choice['model'],'messages':messages,'stream':True,'think':False,'keep_alive':'24h','options':{'num_predict':200,'num_ctx':2048,'num_thread':4}}).encode()
                req=urllib.request.Request(BASE+'/api/chat',payload,{'Content-Type':'application/json'})
                start=_t.time();got=False;skip=False
                with urllib.request.urlopen(req,timeout=120) as r:
                    for line in r:
                        if _t.time()-start>420:break
                        try:o=json.loads(line)
                        except ValueError:continue
                        t=o.get('message',{}).get('content','') or ''
                        t=__import__('re').sub(r'(?s)<think>.*?</think>','',t)
                        if '<think>' in t:t=t.split('<think>')[0];skip=True
                        elif skip:
                            if '</think>' in t:t=t.split('</think>')[-1];skip=False
                            else:t=''
                        if t:
                            if not got:t=t.lstrip()
                            if t:got=True;emit({'t':t})
                        if o.get('done'):break
                if not got:emit({'e':'No answer came back. Try again.'})
            except (BrokenPipeError,ConnectionResetError):pass
            except Exception:
                try:emit({'e':'The AI is busy or slow right now. Try again in a minute.'})
                except Exception:pass
            finally:done.set()
        except Exception:pass
'''
s=s[:a]+NEW+s[b:]
# 2 browser: read the stream, show words as they arrive, friendly errors for non-JSON replies
old="const data=await res.json();if(!res.ok)throw new Error(data.error||'Request failed.');messages.push({role:'assistant',content:data.content});render();status.textContent=''"
JS="""if(!res.ok){let m='Something went wrong. Try again in a minute.';try{m=(await res.json()).error||m}catch(e){}throw new Error(m)}
const rd=res.body.getReader(),dec=new TextDecoder();let buf='',txt='',box=null,bad='';
for(;;){const x=await rd.read();if(x.done)break;buf+=dec.decode(x.value,{stream:true});let i;while((i=buf.indexOf('\\n'))>=0){const line=buf.slice(0,i);buf=buf.slice(i+1);if(!line.trim())continue;let o;try{o=JSON.parse(line)}catch(e){continue}
if(o.e)bad=o.e;if(o.t){txt+=o.t;if(!box){const th=document.getElementById('think');if(th)th.remove();box=document.createElement('div');box.className='message assistant';const r2=document.createElement('div');r2.className='role';r2.textContent='Crunchbyte AI';box.append(r2,document.createElement('div'));chat.append(box)}box.lastChild.textContent=txt;box.scrollIntoView({block:'end'})}}}
if(!txt)throw new Error(bad||'No answer came back. Try again.');
messages.push({role:'assistant',content:txt});render();status.textContent=bad?'The answer was cut short.':''"""
sub(old,JS)
sub("}catch(err){status.textContent=err.message}","}catch(err){const th=document.getElementById('think');if(th)th.remove();status.textContent=(err&&err.message&&err.message.indexOf('<')<0&&err.message.indexOf('JSON')<0)?err.message:'The connection dropped. Try again in a minute.'}")
open(DST,'w').write(s)
print('OK wrote '+DST)
