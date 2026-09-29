# Order-of-magnitude regime for inflating paper (all SI).
import math
E = 3.0e9        # Pa, Kent paper 2.45-3.27 GPa (Isobe & Okumura 2016); kami assumed similar (UNVERIFIED)
t = 1.0e-4       # m, 0.1 mm (repo note a-crease-is-a-hinge.md)
nu = 0.3         # Poisson ratio, assumed
B = E * t**3 / (12 * (1 - nu**2))
print(f"bending stiffness B = {B:.3e} N m")
for L in (0.02, 0.03, 0.04):
    print(f"L = {L*100:.0f} cm: bending scale E t^3/L^3 = {E*t**3/L**3:8.1f} Pa ; stretching scale E t/L = {E*t/L:.2e} Pa")
cmH2O = 98.0665
for name, v in (("PEmax women mean", 142), ("PEmax men mean", 195)):
    print(f"{name}: {v} cmH2O = {v*cmH2O/1000:.1f} kPa")
R = 0.02
for p in (100.0, 1000.0, 10000.0):
    T = p * R / 2                      # membrane tension of a pocket of radius R (sphere-like)
    strain = T / (E * t)
    lam = math.sqrt(2 * math.pi) * (B / T) ** 0.25 * math.sqrt(0.02)   # Cerda-Mahadevan eq. 5, L = 2 cm
    print(f"p = {p:7.0f} Pa: tension {T:6.2f} N/m, membrane strain {strain:.1e}, wrinkle wavelength ~ {lam*100:.1f} cm")
