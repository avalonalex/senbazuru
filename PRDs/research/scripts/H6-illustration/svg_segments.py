# Count straight vs curved path segments in an SVG, honouring implicit
# command repetition (m/l/c/q/s/a/h/v), for describing third-party drawings.
import re, sys, collections
ARGS = {'m': 2, 'l': 2, 'h': 1, 'v': 1, 'c': 6, 's': 4, 'q': 4, 't': 2, 'a': 7, 'z': 0}
s = open(sys.argv[1]).read()
counts = collections.Counter(); npaths = 0
for d in re.findall(r'\sd="([^"]*)"', s):
    npaths += 1
    toks = re.findall(r'[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?', d)
    cmd = None; nums = []
    def flush(cmd, nums):
        if cmd is None: return
        k = ARGS[cmd.lower()]
        if k == 0: counts['close'] += 1; return
        n = len(nums)//k
        if cmd.lower() == 'm':
            counts['move'] += 1; counts['line'] += max(0, n-1)   # extra pairs are lines
        elif cmd.lower() in 'lhv': counts['line'] += n
        elif cmd.lower() in 'csqta': counts['curve'] += n
    for t in toks:
        if re.match(r'[A-Za-z]', t):
            flush(cmd, nums); cmd, nums = t, []
        else: nums.append(t)
    flush(cmd, nums)
print(sys.argv[1], "paths with d:", npaths, dict(counts))
