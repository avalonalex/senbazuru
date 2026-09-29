# Discrete Gaussian curvature check: at each vertex, compare the sum of incident
# triangle corner angles in the folded 3D mesh with the same sum on the flat sheet.
# Paper bends without stretching, so the two sums must agree (isometry keeps angles).
import json, math, sys
f=json.load(open(sys.argv[1]))
X=f['vertices_coords']; U=f['senbazuru:material_coords']; F=f['faces_vertices']
def ang(p,q,r):
    a=[q[i]-p[i] for i in range(len(p))]; b=[r[i]-p[i] for i in range(len(p))]
    da=math.sqrt(sum(x*x for x in a)); db=math.sqrt(sum(x*x for x in b))
    c=sum(x*y for x,y in zip(a,b))/(da*db); return math.acos(max(-1,min(1,c)))
s3={}; s2={}
for t in F:
    for k in range(3):
        p,q,r=t[k],t[(k+1)%3],t[(k+2)%3]
        s3[p]=s3.get(p,0)+ang(X[p],X[q],X[r]); s2[p]=s2.get(p,0)+ang(U[p]+[0],U[q]+[0],U[r]+[0])
d=[abs(s3[v]-s2[v])*180/math.pi for v in s3]
print(sys.argv[1].split('/')[-1],'vertices',len(d),'max angle-sum change %.1f deg'%max(d),'>5deg',sum(x>5 for x in d),'>20deg',sum(x>20 for x in d))
