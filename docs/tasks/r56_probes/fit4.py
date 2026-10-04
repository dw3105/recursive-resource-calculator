# usage: fit4.py name=eng.log:key:w.tt[:offset] ...   per-sheet offset by correlation, per-sheet + pooled fits
# offline instr corrected for the tostring/format wrapper (7 instr per call, measured red-1s)
import re,sys,statistics as S
def solve(A,b):
    n=len(A); M=[row[:]+[b[i]] for i,row in enumerate(A)]
    for i in range(n):
        piv=max(range(i,n),key=lambda r:abs(M[r][i])); M[i],M[piv]=M[piv],M[i]
        for r in range(n):
            if r!=i:
                f=M[r][i]/M[i][i]; M[r]=[a-f*c for a,c in zip(M[r],M[i])]
    return [M[i][n]/M[i][i] for i in range(n)]
def lstsq(cols,y,icpt=True):
    X=[list(r)+([1.0] if icpt else []) for r in zip(*cols)]; k=len(X[0])
    A=[[sum(x[i]*x[j] for x in X) for j in range(k)] for i in range(k)]; b=[sum(x[i]*yy for x,yy in zip(X,y)) for i in range(k)]
    c=solve(A,b); return c,[sum(ci*xi for ci,xi in zip(c,x)) for x in X]
def load(spec):
    name,rest=spec.split('=',1); f,key,tt=rest.split(':')[:3]; off=None
    if rest.count(':')==3: off=int(rest.split(':')[3])
    eng={}
    for l in open(f):
        m=re.search(r"RRCT (\S+) (\d+) Duration: ([\d.]+)ms",l)
        if m and m[1]==key: eng[int(m[2])]=float(m[3])
    T={}
    for l in open(tt):
        p=l.split()
        if p[0]=='T':
            n=int(p[10])+int(p[11]); T[int(p[1])]=dict(ph=p[2],mi=(int(p[4])-7*n)/1e6,mb=int(p[7])/1024,kt=n/1e3,cpu=float(p[5]))
    last=max(eng)
    def corr(o):
        ks=[k for k in T if k+o in eng and k+o!=last]
        a=[T[k]['mi'] for k in ks]; b=[eng[k+o] for k in ks]; ma,mb=S.mean(a),S.mean(b)
        return sum((x-ma)*(y-mb) for x,y in zip(a,b))/((sum((x-ma)**2 for x in a)*sum((y-mb)**2 for y in b))**.5)
    if off is None: off=max(range(0,40),key=corr)
    ks=sorted(k for k in T if k+off in eng and k+off!=last)
    return name,off,corr(off),[(name,k,T[k],eng[k+off]) for k in ks],len(T),len(eng)
rows=[];
models=[("Minstr",["mi"]),("Minstr+MB",["mi","mb"]),("Minstr+Ktostr",["mi","kt"]),("Minstr+MB+Ktostr",["mi","mb","kt"])]
def report(name,R):
    y=[r[3] for r in R]; my=S.mean(y); out=[]
    for mn,cols in models:
        c,pr=lstsq([[r[2][k] for r in R] for k in cols],y); res=[a-b for a,b in zip(y,pr)]
        r2=1-sum(e*e for e in res)/sum((a-my)**2 for a in y)
        big=[abs(a-b)/a for a,b in zip(y,pr) if a>50]
        out.append("%s: coef %s r2 %.3f medabs %.1fms | eng>50ms n=%d med rel err %.0f%%"%(mn,[round(v,2) for v in c],r2,S.median([abs(e) for e in res]),len(big),100*S.median(big) if big else 0))
    print("== %s n=%d"%(name,len(R))); print("\n".join(out))
for spec in sys.argv[1:]:
    name,off,c,R,nt,ne=load(spec); print("ALIGN %s offset=%d corr=%.3f offline_ticks=%d engine_ticks=%d paired=%d"%(name,off,c,nt,ne,len(R)))
    report(name,R); rows+=R
if len(sys.argv)>2: report("POOLED",rows)
