# Check: an equilateral triangular spring lattice (spring k, unit bond length)
# has 2D Young's modulus 2k/sqrt(3) and Poisson ratio 1/3, independent of spacing.
import math
k = 1.0
dirs = [(math.cos(a), math.sin(a)) for a in (0, math.pi/3, 2*math.pi/3)]
cell = math.sqrt(3)/2  # area per vertex; 3 bonds per vertex
def energy_density(exx, eyy):
    return sum(0.5*k*(n[0]*n[0]*exx + n[1]*n[1]*eyy)**2 for n in dirs) / cell
exx = 1e-4
best = min((energy_density(exx, e), e) for e in [i*1e-8 - 1e-4 for i in range(20001)])
W, eyy = best
Y = 2*W/exx**2
print(f"Poisson {-eyy/exx:.4f}  Y {Y:.5f}  2k/sqrt3 {2*k/math.sqrt(3):.5f}")
