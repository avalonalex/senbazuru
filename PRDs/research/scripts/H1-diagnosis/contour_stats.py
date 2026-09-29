# Contour-graph statistics of the saved book drawings: segment counts, short segments,
# and endpoints of degree 1 (contour ink that stops in the middle of paper).
import json, math, sys
b=json.load(open(sys.argv[1])); ppu=b['pixelsPerSheetUnit']
def key(p,tol=1e-6): return (round(p[0]/tol),round(p[1]/tol))
for v in b['views']:
    segs=v['contours']
    L=[math.dist(a,b_)*ppu for a,b_ in segs]
    deg={}
    for a,b_ in segs:
        for p in (a,b_):
            k=key(p); deg[k]=deg.get(k,0)+1
    dangling=sum(1 for d in deg.values() if d==1)
    # merge collinear chains? report raw
    print(v['id'], 'contour segments',len(segs), 'total px %.0f'%sum(L), '<2px',sum(1 for x in L if x<2), '<0.5px',sum(1 for x in L if x<0.5), 'degree-1 endpoints',dangling, 'crease fragments',v['creaseFragments'],'omitted',len(v['omittedCreases']))
