import random, statistics as st
N=200000
def rate(f):  # %/s of budget at fill f (time-independent part)
    return 10.0 if f<30 else None
def timeline():
    # returns list of (t,f) at 0.01s steps until 85
    t=0;f=0;out=[];r2=5.0;t30=None
    while f<85:
        if f<30: r=10.0
        else:
            if t30 is None: t30=t
            r=min(9.0,5.0*1.1**(t-t30))
        f+=r*0.01;t+=0.01;out.append((t,f,r))
    return out
TL=timeline()
def t_at(x):
    for t,f,r in TL:
        if f>=x: return t,r
    return TL[-1][0],TL[-1][2]
def f_after(x,delay):
    t,_=t_at(x)
    for tt,f,r in TL:
        if tt>=t+delay: return f
    return 85
def line(early):
    if random.random()<early: return random.uniform(30,50)
    return random.uniform(55,80)
def nm(x,L):
    if x>=L: return 0
    d=L-x
    return 3 if d<=3 else 1.5 if d<=10 else 1
def stages(L,jit):
    s1=L-15+random.uniform(-4,4)*jit; s2=L-8+random.uniform(-2.5,2.5)*jit; s3=L-3+random.uniform(-1.5,1.5)*jit
    s1=max(s1,5);s2=max(s2,s1+0.5);s3=max(s3,s2+0.5)
    return s1,s2,s3
def run(strategy,early=0.1,jit=1.0,bluff=0.15,react=0.25):
    sc=[];fails=0
    for _ in range(N):
        L=line(early)
        s=stages(L,jit)
        if strategy[0]=='fixed': x=strategy[1]
        else:
            k=strategy[1]; trig=s[k-1]
            if k==1 and random.random()<bluff:
                b=random.uniform(15,70); trig=min(trig,b)
            x=f_after(trig,react)
        v=x*nm(x,L); sc.append(v); fails+= v==0
    return st.mean(sc),fails/N
print('time to 30/55/70/80:',[round(t_at(x)[0],1) for x in (30,55,70,80)])
for early in (0.0,0.1):
    print('--- early',early)
    best=max(((run(('fixed',x),early)[0],x) for x in range(20,81,5)))
    for x in (30,45,50,55,60,65): m,f=run(('fixed',x),early); print(f'fixed {x}: EV {m:.1f} fail {f:.0%}')
    for k in (1,2,3):
        for jit in (1.0,0.42):
            m,f=run(('stage',k),early,jit); print(f'stage{k} jit{jit}: EV {m:.1f} fail {f:.0%}')
