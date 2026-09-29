"""Experiment W: the study's held wing (--crane-spreading, 392 triangles),
relaxed with the study's energy at w = 1e8 / 4.3e6 / 4.3e5, on the original,
flipped and once-refined triangulations, with the study's grip (arc, +20 deg)
and with a twisted grip (locking provocation: +30 deg twist about the span)."""
import json
import sys
import time
import numpy as np

import sheet as S
import wing as W
import relax as R
import meshops as M
import sil

D = sys.argv[1]
OUT = sys.argv[2]
TWIST = np.radians(float(sys.argv[3])) if len(sys.argv) > 3 else np.radians(30)
GRIPS = sys.argv[4].split(",") if len(sys.argv) > 4 else ["arc20", "twist"]
MESHES = sys.argv[5].split(",") if len(sys.argv) > 5 else ["original", "flipped", "refined1"]
WS = [float(x) for x in sys.argv[6].split(",")] if len(sys.argv) > 6 else [1e8, 4.3e6, 4.3e5]
TAG = sys.argv[7] if len(sys.argv) > 7 else "all"

p = W.load_problem(f"{D}/rigid.fold")
f = p["fold"]
turn = np.radians(20)
t_axis = np.array([0.0, -np.cos(W.ROOT + turn), -np.sin(W.ROOT + turn)])


def rodrigues(v, k, a):
    return v * np.cos(a) + np.cross(k, v) * np.sin(a) + np.outer(v @ k, k) * (1 - np.cos(a))


def setup(F, UV, start, wingmask, frac, amap, panels, grip_kind):
    held = (~wingmask) | (frac <= 0.125 + 1e-8) | (frac >= 0.875 - 1e-8)
    grip = wingmask & (frac >= 0.875 - 1e-8)
    X0 = start.copy()
    X0[wingmask] = W.bent_point(start[wingmask, 0], start[wingmask, 1], 20)
    if grip_kind == "twist":
        c = X0[grip].mean(axis=0)
        s = np.clip((frac - 0.125) / 0.75, 0, 1)
        for i in np.flatnonzero(wingmask & (frac > 0.125 + 1e-8)):
            X0[i] = c + rodrigues((X0[i] - c)[None], t_axis, TWIST * s[i])[0]
    H, rest, k, kind = S.build_hinges(F, UV, amap)
    # crease rest angles from the rigid control, by material edge midpoint
    crease = np.isin(kind, ["M", "V", "U"])
    return dict(F=F, UV=UV, X0=X0, held=held, H=H, rest=rest, k=k, kind=kind, crease=crease)


# rest angles of the original creases, keyed by material midpoint of the source segment
H0, rest0, k0, kind0 = S.build_hinges(f["F"], f["UV"], p["amap"])
ang0 = S.hinge_angles(f["X"], H0)


def crease_rest_lookup(UV, H, kind):
    """For split creases, each half inherits the rest angle of the original hinge it lies on."""
    out = np.zeros(len(H))
    orig_mid = (f["UV"][H0[:, 0]] + f["UV"][H0[:, 1]]) / 2
    orig_dir = f["UV"][H0[:, 1]] - f["UV"][H0[:, 0]]
    for h in np.flatnonzero(np.isin(kind, ["M", "V", "U"])):
        a, b = UV[H[h, 0]], UV[H[h, 1]]
        m = (a + b) / 2
        # original crease hinge whose segment contains m
        best, bd = -1, 1e9
        for g in np.flatnonzero(np.isin(kind0, ["M", "V", "U"])):
            pa, pb = f["UV"][H0[g, 0]], f["UV"][H0[g, 1]]
            d = pb - pa
            tpar = (m - pa) @ d / (d @ d)
            if -1e-9 <= tpar <= 1 + 1e-9:
                dist = abs((m - pa)[0] * d[1] - (m - pa)[1] * d[0]) / np.linalg.norm(d)
                if dist < bd:
                    bd, best = dist, g
        assert bd < 1e-9, bd
        # orientation: same direction of a->b as original?
        same = (b - a) @ (f["UV"][H0[best, 1]] - f["UV"][H0[best, 0]]) > 0
        out[h] = ang0[best] if same else ang0[best]  # dihedral sign is orientation independent
    return out


meshes = {}
amap = p["amap"]
start, wingmask, frac = p["start"], p["wing"], p["frac"]
meshes["original"] = (f["F"], f["UV"], start, wingmask, frac, amap, f["panels"])
Ff, Pf, nflip, nj = M.flip_joins(f["F"], f["UV"], amap, f["panels"])
meshes["flipped"] = (Ff, f["UV"], start, wingmask, frac, amap, Pf)
F1, UV1, S1, A1, P1, par = M.refine(f["F"], f["UV"], start, amap, f["panels"])
isnew = par[:, 0] >= 0
w1 = np.concatenate([wingmask, wingmask[par[isnew, 0]] | wingmask[par[isnew, 1]]])
fr1 = np.concatenate([frac, (frac[par[isnew, 0]] + frac[par[isnew, 1]]) / 2])
meshes["refined1"] = (F1, UV1, S1, w1, fr1, A1, P1)
info = dict(flipped=nflip, joins=nj, twist_deg=float(np.degrees(TWIST)))
print("flips", nflip, "of", nj)

results = {"info": info, "runs": []}
store = {}
for grip_kind in GRIPS:
    for mname, (F, UV, st, wm, fr, am, P) in [(k, v) for k, v in meshes.items() if k in MESHES]:
        prob = setup(F, UV, st, wm, fr, am, P, grip_kind)
        rest = prob["rest"].copy()
        if mname == "original" or mname == "flipped":
            rest[prob["crease"]] = S.hinge_angles(f["X"], prob["H"])[prob["crease"]]
        else:
            rest[prob["crease"]] = crease_rest_lookup(UV, prob["H"], prob["kind"])[prob["crease"]]
        Pr = R.Problem(UV, F, prob["H"], rest, prob["k"], prob["held"])
        for w in WS:
            times = []
            nrep = 3 if (grip_kind == "arc20" and mname == "original" and w in (1e8, 4.3e6)) else 1
            for rep in range(nrep):
                X, reps, t = R.relax(Pr, prob["X0"], w, max_iter=400 if grip_kind == "arc20" else 1500)
                times.append(t)
            st_ = S.stats(X, UV, F, prob["H"], prob["kind"], rest)
            key = f"{grip_kind}/{mname}/{w:.1e}"
            store[key] = (X, F)
            run = dict(grip=grip_kind, mesh=mname, w=w, triangles=int(len(F)), vertices=int(len(UV)),
                       held=int(prob["held"].sum()), stats=st_, stages=reps, seconds=times)
            results["runs"].append(run)
            print(key, {k: round(v, 4) if isinstance(v, float) else v for k, v in st_.items()},
                  "grad", f"{reps[-1]['grad_inf']:.1e}", "it", [r['iterations'] for r in reps],
                  "t", [round(x, 2) for x in times], flush=True)
            np.savez_compressed(f"{OUT}/wing-parts/{key.replace('/', '__')}.npz", X=X, F=F)
            json.dump(run, open(f"{OUT}/wing-parts/{key.replace('/', '__')}.json", "w"), default=float)

# silhouettes against the study setting (original mesh, w=1e8) of the same grip
for run in results["runs"]:
    if f"{run['grip']}/original/1.0e+08" not in store:
        continue
    ref = store[f"{run['grip']}/original/1.0e+08"]
    X, F = store[f"{run['grip']}/{run['mesh']}/{run['w']:.1e}"]
    run["silhouette_vs_original_1e8"] = sil.compare_all(ref[0], ref[1], X, F)
    print(run["grip"], run["mesh"], f"{run['w']:.1e}", "haus px", round(run["silhouette_vs_original_1e8"]["max_hausdorff_px"], 2),
          "xor", run["silhouette_vs_original_1e8"]["max_xor_px"])

json.dump(results, open(f"{OUT}/wing-{TAG}.json", "w"), indent=1, default=float)
np.savez_compressed(f"{OUT}/wing-{TAG}.npz", **{k.replace("/", "__"): v[0] for k, v in store.items()},
                    **{("F__" + k.replace("/", "__")): v[1] for k, v in store.items()})
