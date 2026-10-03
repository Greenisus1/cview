import sys
SRC='/root/crunchbyte-test-v8.py'
DST='/root/crunchbyte-test-v9.py'
if len(sys.argv)>2:SRC,DST=sys.argv[1],sys.argv[2]
s=open(SRC).read()
def sub(old,new):
    global s
    if s.count(old)!=1:
        print('PATCH FAILED, not found once:',old[:60]);sys.exit(1)
    s=s.replace(old,new)
OAUTH='''
GH_FILE=Path.home()/'.crunchbyte-github.json'
GH_AUTH='https://github.com/login/oauth/authorize'
GH_TOKEN='https://github.com/login/oauth/access_token'
GH_API='https://api.github.com'
GH_SITE='https://crunchbytes.dpdns.org'
OWNER_LOGIN='greenisus1'
_owner_sessions={}
_oauth_states={}
def gh_config():
    try:
        if GH_FILE.is_symlink() or GH_FILE.stat().st_mode&0o077:return None
        c=json.loads(GH_FILE.read_text())
        if c.get('client_id') and c.get('client_secret') and isinstance(c.get('owner_id'),int):return c
    except Exception:pass
    return None
def _cookie(h,name):
    from http.cookies import SimpleCookie
    try:
        c=SimpleCookie();c.load(h.headers.get('Cookie',''));m=c.get(name);return m.value if m else ''
    except Exception:return ''
def is_owner(h):
    tok=_cookie(h,'cb_owner')
    with _hlock:
        exp=_owner_sessions.get(tok) if tok else None
        if exp and exp>_t.time():return True
        _owner_sessions.pop(tok,None)
    return False
def _redir(h,url,cookies=()):
    h.send_response(303);h.send_header('Location',url)
    for c in cookies:h.send_header('Set-Cookie',c)
    h.send_header('Content-Length','0');h.send_header('Cache-Control','no-store');h.end_headers()
def _post_json(url,data,headers):
    req=urllib.request.Request(url,urllib.parse.urlencode(data).encode(),headers)
    with urllib.request.urlopen(req,timeout=15) as r:return json.loads(r.read(100000))
def _get_json(url,headers):
    req=urllib.request.Request(url,None,headers)
    with urllib.request.urlopen(req,timeout=15) as r:return json.loads(r.read(100000))
def oauth_route(h):
    parts=urllib.parse.urlsplit(h.path);path=parts.path
    if path=='/me':h.reply(200,{'owner':is_owner(h)});return
    cfg=gh_config()
    if not cfg:h.reply(503,{'error':'Owner sign-in is not set up.'});return
    flags='; Path=/; HttpOnly; Secure; SameSite=Lax'
    if path=='/auth/github':
        st=secrets.token_urlsafe(24)
        with _hlock:
            for k in [k for k,v in _oauth_states.items() if v<_t.time()]:_oauth_states.pop(k,None)
            _oauth_states[st]=_t.time()+600
        q=urllib.parse.urlencode({'client_id':cfg['client_id'],'redirect_uri':GH_SITE+'/auth/github/callback','state':st,'allow_signup':'false'})
        _redir(h,GH_AUTH+'?'+q,['cb_state='+st+flags+'; Max-Age=600']);return
    if path=='/auth/github/callback':
        qs=urllib.parse.parse_qs(parts.query);st=(qs.get('state') or [''])[0];code=(qs.get('code') or [''])[0]
        with _hlock:valid=_oauth_states.pop(st,0)>_t.time()
        clear='cb_state=; Path=/; Max-Age=0'
        if not valid or not code or not secrets.compare_digest(_cookie(h,'cb_state').encode(),st.encode()):
            _redir(h,'/',[clear]);return
        try:
            tok=_post_json(GH_TOKEN,{'client_id':cfg['client_id'],'client_secret':cfg['client_secret'],'code':code,'redirect_uri':GH_SITE+'/auth/github/callback'},{'Accept':'application/json','User-Agent':'Crunchbyte'}).get('access_token')
            u=_get_json(GH_API+'/user',{'Authorization':'Bearer '+str(tok),'Accept':'application/json','User-Agent':'Crunchbyte'})
            ok=bool(tok) and u.get('id')==cfg['owner_id'] and str(u.get('login','')).lower()==OWNER_LOGIN
        except Exception:ok=False
        if not ok:_redir(h,'/',[clear]);return
        sid=secrets.token_urlsafe(32)
        with _hlock:_owner_sessions[sid]=_t.time()+43200
        _redir(h,'/',[clear,'cb_owner='+sid+flags+'; Max-Age=43200']);return
    h.reply(404,{'error':'Not found.'})
def setup_github():
    print('Owner sign-in setup. Secret is hidden and saved only on this Pi.')
    cid=input('Client ID (Enter for the saved Crunchbyte one): ').strip() or 'Ov23lixyC1BoCANXfdvd'
    sec=getpass.getpass('Client secret (hidden): ').strip()
    if not sec or any(c.isspace() for c in sec):raise RuntimeError('Invalid secret.')
    u=_get_json(GH_API+'/users/Greenisus1',{'Accept':'application/json','User-Agent':'Crunchbyte'})
    if str(u.get('login','')).lower()!=OWNER_LOGIN or not isinstance(u.get('id'),int):raise RuntimeError('Owner lookup failed.')
    fd=os.open(str(GH_FILE),os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600);os.fchmod(fd,0o600)
    with os.fdopen(fd,'w') as f:json.dump({'client_id':cid,'client_secret':sec,'owner_id':u['id']},f)
    print('Saved. Now start the site as usual.')
def rate_ok('''
sub("def rate_ok(",OAUTH)
sub("vip=coupon_ok(coupon)","vip=coupon_ok(coupon) or is_owner(h)")
sub("    def do_GET(self):\n        if self.path=='/':","    def do_GET(self):\n        if self.path=='/me' or self.path.startswith('/auth/github'):oauth_route(self);return\n        if self.path=='/':")
sub('<input id="coupon"','<a id="gh" href="/auth/github" style="display:block;margin:0 0 8px;color:#c1c8ff;font-size:14px">Owner sign-in with GitHub</a><input id="coupon"')
sub("const cp=document.getElementById('coupon');","fetch('/me').then(r=>r.json()).then(d=>{if(d.owner){const g=document.getElementById('gh');g.textContent='Signed in as owner - unlimited';g.removeAttribute('href')}}).catch(()=>{});const cp=document.getElementById('coupon');")
sub("    if '--setup-fast' in sys.argv:","    if '--setup-github' in sys.argv:\n        try:setup_github()\n        except Exception as e:print(str(e));sys.exit(1)\n        sys.exit(0)\n    if '--setup-fast' in sys.argv:")
open(DST,'w').write(s)
print('OK wrote '+DST)
