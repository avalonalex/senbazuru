# Length of contour ink that runs within 1 drawing pixel of another, nearly
# parallel contour: two outlines of a hair-thin exposed strip, which prints as
# one heavy stroke (often appearing to stop in the middle of paper).
import json, math, sys
b=json.load(open(sys.argv[1])); ppu=b['pixelsPerSheetUnit']
def seg_dist(p,a,c):
    ax,ay=a; cx,cy=c; px,py=p
    dx,dy=cx-ax,cy-ay; L2=dx*dx+dy*dy
    t=0 if L2==0 else max(0,min(1,((px-ax)*dx+(py-ay)*dy)/L2))
    return math.hypot(px-(ax+t*dx),py-(ay+t*dy))
for v in b['views']:
    S=[((a[0]*ppu,a[1]*ppu),(c[0]*ppu,c[1]*ppu)) for a,c in v['contours']]
    total=sum(math.dist(a,c) for a,c in S); doubled=0
    for i,(a,c) in enumerate(S):
        L=math.dist(a,c)
        if L<1e-9: continue
        d=((c[0]-a[0])/L,(c[1]-a[1])/L)
        hits=0; samples=5
        for k in range(samples):
            t=(k+0.5)/samples; p=(a[0]+t*(c[0]-a[0]),a[1]+t*(c[1]-a[1]))
            for j,(e,f) in enumerate(S):
                if j==i: continue
                M=math.dist(e,f)
                if M<1e-9: continue
                d2=((f[0]-e[0])/M,(f[1]-e[1])/M)
                if abs(d[0]*d2[0]+d[1]*d2[1])<0.97: continue
                dd=seg_dist(p,e,f)
                if 0.02<dd<1.0: hits+=1; break
        doubled+=L*hits/samples
    print(v['id'],'contour ink %.0f px, of which %.0f px (%.1f%%) runs within 1 px of a parallel contour'%(total,doubled,100*doubled/total))
