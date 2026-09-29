# Sliver statistics for the book drawings' visible pieces: a piece whose
# mean width (2*area/perimeter) is under 1 drawing pixel but is long enough
# to be seen (perimeter over 10 px) reads as a stray stroke once outlined.
import json, math, sys
b=json.load(open(sys.argv[1])); ppu=b['pixelsPerSheetUnit']
def area(r): return 0.5*sum(r[i][0]*r[(i+1)%len(r)][1]-r[(i+1)%len(r)][0]*r[i][1] for i in range(len(r)))
def perim(r): return sum(math.dist(r[i],r[(i+1)%len(r)]) for i in range(len(r)))
for v in b['views']:
    pieces=[]
    for tone in v['tones']:
        for r in tone['rings']:
            A=abs(area(r))*ppu*ppu; P=perim(r)*ppu
            pieces.append((A,P,tone['colour']))
    n=len(pieces)
    slivers=[p for p in pieces if p[1]>10 and 2*p[0]/p[1]<1.0]
    tiny=[p for p in pieces if p[0]<1.0]
    print(v['id'],'visible pieces',n,'tones',[ (t['colour'],len(t['rings'])) for t in v['tones']],'slivers(width<1px,perim>10px)',len(slivers),'longest sliver perim %.1f px'%max([s[1] for s in slivers] or [0]),'pieces<1px^2',len(tiny))
