# Paulsen's Mylar balloon, deflated disc radius a = 1, constants from Wikipedia
# (A = generatrix length / inflated radius, B = half-thickness / inflated radius).
import math
A = 1.3110287771; B = 0.5990701173  # Wikipedia names; k1, k2 in the note
a = 1.0
r = a / A                      # inflated rim radius
tau = 2 * B * r                # thickness on the axis
V = 2 / 3 * math.pi * a * r**2 # volume
S = math.pi**2 * r**2          # inflated surface area
S0 = 2 * math.pi * a**2        # area of the two flat discs
Vsphere = 4/3*math.pi*(math.sqrt(S0/(4*math.pi)))**3
print(f"rim radius r/a = {r:.4f}  (rim pulls in by {100*(1-r):.2f}%)")
print(f"thickness tau/a = {tau:.4f}, tau/(2r) = {tau/(2*r):.4f}")
print(f"volume V/a^3 = {V:.4f}; alt 4/3 tau a^2 = {4/3*tau*a*a:.4f}")
print(f"inflated area / flat area = {S/S0:.4f}  (lost to crimps {100*(1-S/S0):.2f}%)")
print(f"sphere of same area: V = {Vsphere:.4f}; mylar/sphere = {V/Vsphere:.4f}")
# polygon correction for a 6*rings-gon rim
for rings in (8, 12):
    m = 6*rings
    poly = m/2*math.sin(2*math.pi/m)/math.pi
    print(f"{m}-gon rim: area factor {poly:.5f}; volume if scaled by (area)^(3/2): {V*poly**1.5:.4f}")
# square pillow reference numbers (Wikipedia, paper bag problem)
print("Robin simple formula h=w=1:", 1/math.pi - 0.142*(1-10**(-1)))
