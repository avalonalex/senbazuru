# Independent strain statistics for a senbazuru study FOLD (material coords in senbazuru:material_coords).
import json, math, sys
f=json.load(open(sys.argv[1]))
X=f['vertices_coords']; U=f['senbazuru:material_coords']; F=f['faces_vertices']
def sub(a,b): return [a[i]-b[i] for i in range(len(a))]
def dot(a,b): return sum(x*y for x,y in zip(a,b))
res=[]
for tri in F:
    a,b,c=tri
    bu,bv=sub(U[b],U[a]); cu,cv=sub(U[c],U[a])
    det=bu*cv-bv*cu
    ab=sub(X[b],X[a]); ac=sub(X[c],X[a])
    du=[(cv*ab[i]-bv*ac[i])/det for i in range(3)]
    dv=[(bu*ac[i]-cu*ab[i])/det for i in range(3)]
    A=dot(du,du);B=dot(du,dv);C=dot(dv,dv)
    sp=math.sqrt((A-C)**2+4*B*B)
    small=math.sqrt(max(0,(A+C-sp)/2))-1; large=math.sqrt(max(0,(A+C+sp)/2))-1
    area=abs(det)/2
    res.append((small,large,area))
tot=sum(r[2] for r in res)
def frac(pred): return sum(r[2] for r in res if pred(r))/tot
n=len(res)
print('triangles',n)
for th in [0.01,0.05,0.10,0.25,0.5]:
    print(f'strain>|{th:.2f}|: {sum(1 for r in res if max(abs(r[0]),abs(r[1]))>th)} tris, {100*frac(lambda r:max(abs(r[0]),abs(r[1]))>th):.1f}% of sheet area')
print('max stretch',max(r[1] for r in res),'max compress',min(r[0] for r in res))
