"""Write FOLD files for chosen projected states and X1-style Blender configs.

usage: mkrender.py SPEC.json
SPEC: {"groups": [{"name": "spread0", "model": "spread-0",
                    "states": [["sketch", null, null], ["p1", RUN, TARGET_STRAIN], ...]}]}
Each group shares one camera box (frame_with = every state in the group), at the
gallery's upright camera, so sketch and projections are directly comparable.
TARGET_STRAIN picks the first row of the run's sweep whose max strain is <= it.
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np, mesh

here = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
G = os.path.abspath(os.path.join(here, "../../gallery/whole-crane")) + "/"
spec = json.load(open(sys.argv[1]))
os.makedirs(os.path.join(here, "fold"), exist_ok=True)
os.makedirs(os.path.join(here, "configs"), exist_ok=True)
os.makedirs(os.path.join(here, "renders"), exist_ok=True)
names = []
for g in spec["groups"]:
    m = mesh.load_fold(G + g["model"] + ".fold")
    paths = []
    for label, run, target in g["states"]:
        path = os.path.join(here, "fold", f"{g['name']}-{label}.fold")
        if run is None:
            X = m["X"]; title = "sketch"
        else:
            d = json.load(open(os.path.join(here, "out", run, "sweep.json")))
            assert d["levels"] == 0
            row = [r for r in d["rows"][1:] if r["max_principal_strain"] <= target][0]
            X = np.load(os.path.join(here, "out", run, f"X_lam{row['lam']:.0e}.npy"))
            title = f"{run} lam {row['lam']:.0e} strain {row['max_principal_strain']:.2e}"
        mesh.write_fold(m, X, path, title)
        paths.append((label, path))
    for label, path in paths:
        n = f"{g['name']}-{label}"
        cfg = dict(axes="crane", forward=[1, 2 ** 0.5, -1], up=[0, -1, 0], frame_with=[p for _, p in paths], fold=path,
                   treatment=spec.get("treatment", "paper"), thickness=0.0006666666666666668, gap=0.0007333333333333334,
                   samples=spec.get("samples", 64), exposure=-1.0, res=spec.get("res", [900, 750]),
                   out=os.path.join(here, "renders", n + ".png"), timing_out=os.path.join(here, "logs", "render-" + n + ".json"))
        json.dump(cfg, open(os.path.join(here, "configs", n + ".json"), "w"), indent=1)
        names.append(n)
print("\n".join(names))
