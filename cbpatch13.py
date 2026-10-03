import sys
SRC='/root/crunchbyte-test-v10.py'
DST='/root/crunchbyte-test-v11.py'
if len(sys.argv)>2:SRC,DST=sys.argv[1],sys.argv[2]
s=open(SRC).read()
def sub(old,new):
    global s
    if s.count(old)!=1:
        print('PATCH FAILED, not found once:',old[:60]);sys.exit(1)
    s=s.replace(old,new)
CSS=r'''.md p{margin:0 0 8px;white-space:pre-wrap}.md p:last-child{margin-bottom:0}
.md code{background:#1b2036;padding:1px 5px;border-radius:5px;font-family:ui-monospace,Menlo,monospace;font-size:.92em}
.md pre{background:#10131f;border:1px solid #2c3270;border-radius:10px;padding:10px;overflow-x:auto;margin:6px 0}.md pre code{background:none;padding:0}
.md .mdh{font-weight:700;margin:10px 0 4px}.md ul,.md ol{margin:4px 0 8px 22px;padding:0}
.math{font-family:"Cambria Math","STIX Two Math","Times New Roman",serif}
.mathb{display:block;text-align:center;margin:8px 0;font-size:1.1em;font-family:"Cambria Math","STIX Two Math","Times New Roman",serif}
.frac{display:inline-flex;flex-direction:column;vertical-align:middle;text-align:center;margin:0 3px;font-size:.95em}
.frac .num{border-bottom:1px solid currentColor;padding:0 4px}.frac .den{padding:0 4px}
.sqrt .rad{border-top:1px solid currentColor;padding:0 2px;margin-left:1px}
</style><script>'''
JS=r'''const GR={alpha:'α',beta:'β',gamma:'γ',delta:'δ',epsilon:'ε',theta:'θ',lambda:'λ',mu:'μ',pi:'π',sigma:'σ',phi:'φ',omega:'ω',Delta:'Δ',Sigma:'Σ',Omega:'Ω',times:'×',cdot:'·',div:'÷',pm:'±',leq:'≤',le:'≤',geq:'≥',ge:'≥',neq:'≠',ne:'≠',approx:'≈',infty:'∞',to:'→',rightarrow:'→',leftarrow:'←',sum:'∑',prod:'∏',int:'∫',degree:'°',ldots:'…',dots:'…',cdots:'⋯',in:'∈',subset:'⊂',cup:'∪',cap:'∩',partial:'∂',nabla:'∇',forall:'∀',exists:'∃',angle:'∠',circ:'∘'};
function E(t,c){const e=document.createElement(t);if(c)e.className=c;return e}
function tex(p,s){let k=0,b='';const fl=()=>{if(b){p.append(document.createTextNode(b));b=''}};
const arg=()=>{while(s[k]===' ')k++;if(s[k]==='{'){let d=1;const st=++k;while(k<s.length&&d){if(s[k]==='{')d++;else if(s[k]==='}')d--;k++}return s.slice(st,d?k:k-1)}
if(s[k]==='\\'){const m=/^\\[a-zA-Z]+/.exec(s.slice(k));if(m){k+=m[0].length;return m[0]}}return s[k++]||''};
while(k<s.length){const c=s[k];
if(c==='\\'){const m=/^\\([a-zA-Z]+|[\s\S])/.exec(s.slice(k));const n=m[1];k+=m[0].length;
if(n==='frac'||n==='dfrac'){const a=arg(),d=arg();fl();const f=E('span','frac'),nu=E('span','num'),de=E('span','den');tex(nu,a);tex(de,d);f.append(nu,de);p.append(f);continue}
if(n==='sqrt'){const a=arg();fl();const r=E('span','sqrt');r.append(document.createTextNode('√'));const o=E('span','rad');tex(o,a);r.append(o);p.append(r);continue}
if(n==='text'||n==='mathrm'||n==='mathbf'||n==='textbf'||n==='mathit'){b+=arg();continue}
if(n==='left'||n==='right'){continue}
if(n===','||n===';'||n===':'||n==='\\'||n===' '||n==='quad'){b+=' ';continue}
if(GR[n]!==undefined){b+=GR[n];continue}
if(n==='sin'||n==='cos'||n==='tan'||n==='log'||n==='ln'||n==='lim'){b+=n;continue}
if(n.length===1){b+=n;continue}
continue}
if(c==='^'||c==='_'){k++;const a=arg();fl();const e=E(c==='^'?'sup':'sub');tex(e,a);p.append(e);continue}
if(c==='{'||c==='}'){k++;continue}
b+=c;k++}
fl()}
function inl(p,s){let k=0,b='';const fl=()=>{if(b){p.append(document.createTextNode(b));b=''}};
while(k<s.length){const r=s.slice(k);let m;
if(m=/^`([^`\n]+)`/.exec(r)){fl();const c=E('code');c.textContent=m[1];p.append(c);k+=m[0].length;continue}
if(m=/^\$\$([\s\S]+?)\$\$/.exec(r)||/^\\\[([\s\S]+?)\\\]/.exec(r)){fl();const d=E('span','mathb');tex(d,m[1].trim());p.append(d);k+=m[0].length;continue}
if(m=/^\\\(([\s\S]+?)\\\)/.exec(r)||/^\$([^\s$](?:[^$\n]*[^\s$])?)\$(?![0-9])/.exec(r)){fl();const d=E('span','math');tex(d,m[1]);p.append(d);k+=m[0].length;continue}
if(m=/^\*\*([^*\s][\s\S]*?)\*\*/.exec(r)||/^__([^_\s][\s\S]*?)__/.exec(r)){fl();const e=E('strong');inl(e,m[1]);p.append(e);k+=m[0].length;continue}
if(m=/^\*([^*\s][^*\n]*?)\*/.exec(r)){fl();const e=E('em');inl(e,m[1]);p.append(e);k+=m[0].length;continue}
b+=s[k];k++}
fl()}
function md(el,src){el.replaceChildren();const L=String(src).replace(/\r/g,'').split('\n');let i=0,m;
const LI=/^\s*(?:[-*•]|\d+[.)])\s+/;
while(i<L.length){const ln=L[i];
if(/^```/.test(ln)){const pre=E('pre'),c=E('code');i++;const a=[];while(i<L.length&&!/^```/.test(L[i]))a.push(L[i++]);i++;c.textContent=a.join('\n');pre.append(c);el.append(pre);continue}
if(!ln.trim()){i++;continue}
if(m=/^#{1,4}\s+(.*)/.exec(ln)){const h=E('div','mdh');inl(h,m[1]);el.append(h);i++;continue}
if(LI.test(ln)){const o=/^\s*\d+[.)]/.test(ln);const u=E(o?'ol':'ul');while(i<L.length&&(m=/^\s*(?:[-*•]|\d+[.)])\s+(.*)/.exec(L[i]))){const li=E('li');inl(li,m[1]);u.append(li);i++}el.append(u);continue}
const a=[];while(i<L.length&&L[i].trim()&&!/^```/.test(L[i])&&!/^#{1,4}\s/.test(L[i])&&!LI.test(L[i]))a.push(L[i++]);
const p=E('p');inl(p,a.join('\n'));el.append(p)}}
function showThinking(){'''
sub("</style><script>",CSS)
sub("function showThinking(){",JS)
# assistant messages are rendered with md(); user messages stay plain text
sub("const text=document.createElement('div');text.textContent=m.content;","const text=document.createElement('div');if(m.role==='user')text.textContent=m.content;else{text.className='md';md(text,m.content)}")
sub("box.append(r2,document.createElement('div'));","const bd=document.createElement('div');bd.className='md';box.append(r2,bd);")
sub("box.lastChild.textContent=txt;","md(box.lastChild,txt);")
open(DST,'w').write(s)
print('OK wrote '+DST)
