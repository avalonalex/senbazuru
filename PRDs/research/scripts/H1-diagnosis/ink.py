# Ink length relative to the drawing's bounding-box diagonal, for stroked paths only.
import re, math, sys
def run(fn):
    s=open(fn).read()
    total=0; n=0; xs=[]; ys=[]
    for m in re.finditer(r'<(path|polyline)\b([^>]*)>', s):
        attrs=m.group(2)
        dm=re.search(r'\bd="([^"]*)"',attrs) or re.search(r'points="([^"]*)"',attrs)
        if not dm: continue
        nums=[float(x) for x in re.findall(r'-?\d+\.?\d*(?:e-?\d+)?',dm.group(1))]
        pts=list(zip(nums[0::2],nums[1::2]))
        for x,y in pts: xs.append(x); ys.append(y)
        stroked='stroke=' in attrs and 'stroke="none"' not in attrs
        filled = re.search(r'fill="(?!none)',attrs)
        if stroked and not filled:
            n+=1
            total+=sum(math.dist(pts[i],pts[i+1]) for i in range(len(pts)-1))
    diag=math.hypot(max(xs)-min(xs),max(ys)-min(ys))
    print(fn.split('/')[-1],'stroked paths',n,'ink/diagonal %.1f'%(total/diag))
for fn in sys.argv[1:]: run(fn)
