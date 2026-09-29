"""Order-of-magnitude mechanics of a 15 cm paper crane.

Every input is printed with its source tag so the note can cite this run.
Units are SI unless stated. 'Sheet units' means lengths divided by the side
of the square sheet, which is what study/fold-material uses.
"""
import math

g = 9.81
side = 0.15  # m, a standard 15 cm kami square

papers = {
    # name: (thickness m, grammage kg/m^2, E Pa, nu, source)
    "kami (OrigamiUSA review: 72 um, 63 gsm; E assumed 4 GPa)": (72e-6, 0.063, 4.0e9, 0.23),
    "printer paper (OrigamiUSA: 105 um; 80 gsm assumed; E 4 GPa)": (105e-6, 0.080, 4.0e9, 0.23),
    "Pradier 2016 woodfree (Filipov Table 1: 0.129 mm, E_MD 4 GPa)": (129e-6, 0.080, 4.0e9, 0.23),
}

# L*/t ratios measured (Filipov et al. 2017 Table 1, L* and t columns)
lstar_over_t = {
    "Pradier 2016 paper, pre-folded": 19e-3 / 0.129e-3,
    "Yasuda 2013 paper, pre-folded": 50e-3 / 0.27e-3,
    "Lechenault 2014 Mylar 0.13 mm": 28e-3 / 0.13e-3,
    "Lechenault 2014 Mylar 0.35 mm": 60e-3 / 0.35e-3,
    "Lechenault 2014 Mylar 0.5 mm": 94e-3 / 0.5e-3,
}
print("L*/t from Filipov Table 1:")
for k, v in lstar_over_t.items():
    print(f"  {k}: {v:.0f}")
lo, hi = min(lstar_over_t.values()), max(lstar_over_t.values())

print()
for name, (t, rho_a, E, nu) in papers.items():
    B = E * t**3 / (12 * (1 - nu**2))  # N m, bending stiffness
    Y = E * t  # N/m, 2D stretching stiffness
    fvk = Y * side**2 / B  # dimensionless stretch/bend ratio at sheet scale
    lstar = (lo * t, hi * t)
    kappa = (B / lstar[1], B / lstar[0])  # N (N m per m per rad)
    lg = (B / (rho_a * g)) ** (1 / 3)  # elastogravity length
    q = rho_a * g
    Lw = 0.07
    droop = q * Lw**4 / (8 * B)  # single-layer cantilever tip deflection
    print(name)
    print(f"  B = {B:.3e} N m ; Y = E t = {Y:.3e} N/m")
    print(f"  Y L^2 / B at a 15 cm sheet = {fvk:.3e}")
    print(f"  L* range = {lstar[0]*1e3:.1f}-{lstar[1]*1e3:.1f} mm = {lstar[0]/side:.3f}-{lstar[1]/side:.3f} sheet units")
    print(f"  crease stiffness per length kappa = {kappa[0]:.2e}-{kappa[1]:.2e} N")
    print(f"  elastogravity length (B/(rho g))^(1/3) = {lg*1e3:.0f} mm = {lg/side:.2f} sheet")
    print(f"  single-layer 7 cm cantilever droop under own weight = {droop*1e3:.1f} mm")
    print(f"  minimum fold radius ~1.25 t = {1.25*t*1e6:.0f} um = {1.25*t/side:.2e} sheet")
    print()

# The study's constants (FoldBending.hs:66; WholeCrane uses Bending 1 0.2;
# FoldRelaxation.hs:543 penalty stages; energy w * sum (dl)^2).
print("study constants, sheet units:")
for Bs in (0.2, 5.0):
    print(f"  kappa=1, B={Bs}: L*_study = {Bs:.1f} sheet = {Bs*side*1e3:.0f} mm on a 15 cm sheet")
# A triangular spring lattice with per-edge energy 1/2 k dl^2 has 2D Young's
# modulus 2k/sqrt(3) (equilateral lattice). Study energy w dl^2 => k = 2w.
for w in (1e2, 1e4, 1e6, 1e8):
    Ys = 2 * (2 * w) / math.sqrt(3)
    print(f"  penalty w={w:.0e}: lattice Y ~ {Ys:.2e}; Y/B at B=0.2 -> {Ys/0.2:.2e}; at B=5 -> {Ys/5:.2e}")

print()
print("smooth spherical cap from a flat disc, radial lengths kept (meridians isometric):")
# flat disc radius s0 = 1; cap on sphere radius R; hoop strain at rim = R sin(1/R) - 1
for h_over_s in (0.05, 0.1, 0.2, 0.217, 0.3, 0.4):
    # find R with R(1-cos(1/R)) = h
    lo_r, hi_r = 0.32, 1e6
    for _ in range(200):
        mid = math.sqrt(lo_r * hi_r)
        h = mid * (1 - math.cos(1 / mid))
        if h > h_over_s:
            lo_r = mid
        else:
            hi_r = mid
    R = math.sqrt(lo_r * hi_r)
    strain = R * math.sin(1 / R) - 1
    print(f"  rise/radius {h_over_s:.3f}: rim hoop strain {strain*100:.2f}% (approx -(2/3)(h/s)^2 = {-(2/3)*h_over_s**2*100:.2f}%)")

print()
print("physical length-penalty weight in study units (lattice Y = 4w/sqrt3 = gamma*B):")
gamma_kami = 4.0e9 * 72e-6 * side**2 / (4.0e9 * (72e-6) ** 3 / (12 * (1 - 0.23**2)))
for Bs in (0.07, 0.1, 0.2):
    w = gamma_kami * Bs * math.sqrt(3) / 4
    print(f"  B={Bs}: w_phys = {w:.2e}")
px = 600.0
print()
print("drawing-scale conversions at 600 px per sheet side:")
print(f"  kami thickness 72 um = {72e-6/side*px:.3f} px")
print(f"  minimum fold radius 1.25 t = {1.25*72e-6/side*px:.3f} px")
print(f"  1% strain over a 0.2-sheet panel = {0.01*0.2*px:.2f} px")
print(f"  L* 10.6-15.5 mm = {10.6e-3/side*px:.0f}-{15.5e-3/side*px:.0f} px")
print(f"  pillow target rise 0.045 over half-width (sqrt2-1)/2 = {(math.sqrt(2)-1)/2:.4f}: ratio {0.045/((math.sqrt(2)-1)/2):.3f}")
for s in (2.45e9, 6.83e9):
    print(f"  elastogravity length scales as E^(1/3): E={s/1e9:.2f} GPa -> factor {(s/4e9)**(1/3):.3f}")
