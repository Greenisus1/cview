import re,sys
SRC='/root/crunchbyte-test-v7.py'
DST='/root/crunchbyte-test-v8.py'
if len(sys.argv)>2:SRC,DST=sys.argv[1],sys.argv[2]
s=open(SRC).read()
def fail(w):
    print('PATCH FAILED, not found:',w);sys.exit(1)
def sub(old,new):
    global s
    if s.count(old)!=1:fail(old[:60])
    s=s.replace(old,new)
def rsub(pat,new):
    global s
    s,n=re.subn(pat,lambda m:new,s)
    if n!=1:fail(pat[:60])
# 1 remove the password box and its checks
rsub(r'<input id="access"[^>]*>','')
rsub(r"if\(!document\.getElementById\('access'\)\.value\)\{status\.textContent='[^']*';return\}",'')
sub(',test_password:document.getElementById("access").value','')
rsub(r"            supplied=data\.get\('test_password',''\)\n            if not isinstance\(supplied,str\) or not secrets\.compare_digest\(supplied\.encode\(\),TEST_PASSWORD\.encode\(\)\):\n                self\.reply\(403,\{'error':'Incorrect test password\.'\}\);return\n","            if not rate_ok(self):self.reply(429,{'error':'Too many messages. Wait a few minutes and try again.'});return\n")
# 2 no password prompt at start
rsub(r"    TEST_PASSWORD=getpass\.getpass\([^\n]*\n    if len\(TEST_PASSWORD\)<12:[^\n]*\n","")
sub("    print('Enter your test password in the website. Keep both terminals open. Ctrl+C stops this app.')","    print('Open the website. No password needed. Keep both terminals open. Ctrl+C stops this app.')")
# 3 per-IP rate limit (behind the tunnel the visitor IP is in CF-Connecting-IP)
sub("lock=threading.Lock()","""lock=threading.Lock()
import time as _t
_hits={}
_hlock=threading.Lock()
def rate_ok(h):
    ip=(h.headers.get('CF-Connecting-IP') or h.client_address[0])[:64]
    now=_t.time()
    with _hlock:
        if len(_hits)>5000:_hits.clear()
        q=[x for x in _hits.get(ip,[]) if x>now-86400]
        if len([x for x in q if x>now-600])>=8 or len(q)>=60:
            _hits[ip]=q;return False
        q.append(now);_hits[ip]=q;return True""")
# 4 keep replies and inputs small
sub("'num_predict':220","'num_predict':200")
sub("len(m['content'])>8000","len(m['content'])>1500")
sub('maxlength="8000"','maxlength="1500"')
open(DST,'w').write(s)
print('OK wrote '+DST)
