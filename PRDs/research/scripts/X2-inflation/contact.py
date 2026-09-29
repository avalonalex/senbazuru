import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.image as mpimg
tiles = [
 ("bl-teabag-r24-tf.png", "Blender cloth, compression 0.1\ntea bag V=0.203, stretch 0.25%"),
 ("bl-teabag-r24-full-flat.png", "Blender cloth, compression 1000 (flat shaded)\nV=0.174, mesh-scale herringbone"),
 ("own-teabag-r24-tf-kb1e-4.png", "own solver, tension-field, kb=1e-4\nV=0.200 (published 0.2055-0.217)"),
 ("own-teabag-r24-full-kb1e-3-flat.png", "own solver, full membrane, kb=1e-3\nV=0.092: locked, barely inflates"),
 ("own-teabag-r24-tf-kb1e-2.png", "own solver, tension-field, kb=1e-2\nV=0.101: stiff paper, gentle pressure"),
 ("own-teabag-r24-full-kb1e-5-flat.png", "own solver, full membrane, kb=1e-5\nV=0.141 (0.111 at r12): mesh-dependent kinks"),
 ("crimp-teabag.png", "look test: tension-field + sine crimps\nreads as a quilted fabric cushion"),
 ("crimp-zigzag-teabag.png", "look test: tension-field + zigzag crimps\nsharper, but hard patch edges, lumpy corners"),
 ("own-mylar-r16-tf.png", "Mylar, own tension-field, 3072 tris\nV=1.213 vs exact 1.219; smooth pebble"),
 ("bl-mylar-r16-full-flat.png", "Mylar, Blender compression 1000\nV=0.80 (1.17 at 1200 tris)"),
 ("drawn-puff-low.png", "repo's drawn puff (z=0.25 sin sin)\nV=0.100, edge stretch up to 26%"),
 ("own-puff-r24-low.png", "solved puff, rim clamped, paper-stiff\nV=0.015, rise 3% of side"),
]
fig = plt.figure(figsize=(20, 26))
gs = fig.add_gridspec(5, 4, height_ratios=[1, 1, 1, 0.95, 1.05])
for k, (f, cap) in enumerate(tiles):
    a = fig.add_subplot(gs[k // 4, k % 4])
    a.imshow(mpimg.imread("img/" + f)); a.set_axis_off(); a.set_title(cap, fontsize=12)
a = fig.add_subplot(gs[3, :]); a.imshow(mpimg.imread("img/profiles.png")); a.set_axis_off()
a = fig.add_subplot(gs[4, :]); a.imshow(mpimg.imread("img/compression-maps.png")); a.set_axis_off()
fig.suptitle("X2 inflation: tea bag, Mylar balloon, clamped puff. Two routes (Blender cloth+pressure, own quasi-static shell)", fontsize=15)
plt.tight_layout(rect=(0, 0, 1, 0.985))
plt.savefig("contact-sheet.png", dpi=70)
print("ok")
