import os,sys,json
SRC='/root/crunchbyte-test-v3.py'
DST='/root/crunchbyte-test-v7.py'
if len(sys.argv)>2:SRC,DST=sys.argv[1],sys.argv[2]
s=open(SRC).read()
def sub(old,new):
    global s
    if s.count(old)!=1:
        print('PATCH FAILED, not found once:',old[:60]);sys.exit(1)
    s=s.replace(old,new)
# 1 model answers without thinking, stays loaded
sub("'stream':False,'options':{'num_predict':384,'num_ctx':2048}","'stream':False,'think':False,'keep_alive':'24h','options':{'num_predict':220,'num_ctx':2048}")
sub("content=result.get('message',{}).get('content','')","content=__import__('re').sub(r'(?s)<think>.*?</think>','',result.get('message',{}).get('content','')).strip()")
# 2 more time for the 8B model (Cloudflare cuts at ~100 s)
sub('urllib.request.urlopen(req,timeout=85)','urllib.request.urlopen(req,timeout=95)')
sub('Temporary test · GitHub login is not connected · Hosted choices send chats to a hosted service','Private test · Answers are made on the Pi')
# 3 Thinking animation
css="""<style>
#think{display:flex;align-items:center;gap:14px;padding:16px 18px;margin:12px 0;border-radius:16px;background:linear-gradient(135deg,#12142b,#1b1f45);border:1px solid #2c3270;max-width:320px;animation:thk-in .35s ease}
#think .orb{position:relative;width:34px;height:34px;flex:none}
#think .orb i{position:absolute;inset:0;border-radius:50%;border:2px solid transparent;border-top-color:#8f9bff;animation:thk-spin 1.1s linear infinite}
#think .orb i:nth-child(2){inset:6px;border-top-color:#5ee0ff;animation-duration:.8s;animation-direction:reverse}
#think .orb b{position:absolute;left:50%;top:50%;width:8px;height:8px;margin:-4px 0 0 -4px;border-radius:50%;background:#c1c8ff;box-shadow:0 0 12px #8f9bff;animation:thk-pulse 1.4s ease-in-out infinite}
#think .txt{font-weight:600;letter-spacing:.04em;background:linear-gradient(90deg,#6b74c9 0%,#fff 50%,#6b74c9 100%);background-size:200% 100%;-webkit-background-clip:text;background-clip:text;color:transparent;animation:thk-shine 1.8s linear infinite}
#think .dots span{display:inline-block;width:5px;height:5px;margin-left:3px;border-radius:50%;background:#8f9bff;animation:thk-bounce 1.2s ease-in-out infinite}
#think .dots span:nth-child(2){animation-delay:.15s}
#think .dots span:nth-child(3){animation-delay:.3s}
@keyframes thk-spin{to{transform:rotate(360deg)}}
@keyframes thk-pulse{0%,100%{transform:scale(.6);opacity:.6}50%{transform:scale(1.2);opacity:1}}
@keyframes thk-shine{to{background-position:-200% 0}}
@keyframes thk-bounce{0%,60%,100%{transform:translateY(0);opacity:.4}30%{transform:translateY(-5px);opacity:1}}
@keyframes thk-in{from{opacity:0;transform:translateY(6px)}to{opacity:1;transform:none}}
</style><script>"""
assert "<script>" in s
s=s.replace("<script>",css,1)
js="""function showThinking(){const d=document.createElement('div');d.id='think';d.innerHTML='<div class="orb"><i></i><i></i><b></b></div><div><span class="txt">Thinking</span><span class="dots"><span></span><span></span><span></span></span></div>';chat.append(d);d.scrollIntoView({block:'end'})}
function render(){"""

sub("function render(){",js)
sub("status.textContent='Thinking... the test may take a minute.';","showThinking();status.textContent='';")
open(DST,'w').write(s)
# only model: qwen3:8b
cfg=os.path.expanduser('~/.crunchbyte-models.json')
if len(sys.argv)<=2:
    if os.path.exists(cfg):os.replace(cfg,cfg+'.old')
    fd=os.open(cfg,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
    with os.fdopen(fd,'w') as f:json.dump({'Good':{'type':'local','model':'qwen3:8b'}},f)
print('OK wrote '+DST)
