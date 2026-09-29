"""Compare senbazuru's faceOrders with the simulated (tucked) stacking.

usage: compare.py SIM.json FOLDED.fold
Prints how many of the file's faceOrders agree with the simulation's heights,
and lists the disagreeing pairs (by face label).
"""
import json
import sys


def signed_area(P):
    a = 0.0
    for i in range(len(P)):
        x1, y1 = P[i][:2]
        x2, y2 = P[(i + 1) % len(P)][:2]
        a += x1 * y2 - x2 * y1
    return a / 2


def load(sim_path, fold_path):
    sim = json.load(open(sim_path))
    fo = json.load(open(fold_path))
    key = {tuple(sorted(f["face"])): k for k, f in enumerate(sim["faces"])}
    # the folded file's vertex indices must match the pattern's (no cutting)
    assert len(fo["vertices_coords"]) == len(sim["V"]), "vertex count changed"
    fmap = []
    for f in fo["faces_vertices"]:
        fmap.append(key[tuple(sorted(f))])
    return sim, fo, fmap


def compare(sim, fo, fmap):
    X = fo["vertices_coords"]
    agree, dis = 0, []
    for (f, g, s) in fo["faceOrders"]:
        # FOLD reads s against g's normal (the winding of g's folded polygon)
        P = [X[v] for v in fo["faces_vertices"][g]]
        nz = 1 if signed_area(P) > 0 else -1
        if len(P[0]) == 3:
            zs = {round(p[2], 9) for p in X}
            assert len(zs) == 1, "not flat"
        zf = sim["faces"][fmap[f]]["z"]
        zg = sim["faces"][fmap[g]]["z"]
        sim_above = (zf > zg) if nz > 0 else (zf < zg)
        file_above = s > 0
        if sim_above == file_above:
            agree += 1
        else:
            dis.append((fmap[f], fmap[g]))
    return agree, dis


def label(sim, k):
    f = sim["faces"][k]
    return f"{f['q']}:{'/'.join(f['hist']) or 'base'}#{k}"


if __name__ == "__main__":
    sim, fo, fmap = load(sys.argv[1], sys.argv[2])
    agree, dis = compare(sim, fo, fmap)
    n = len(fo["faceOrders"])
    print(f"{agree}/{n} faceOrders agree with the simulated tucked stacking; {len(dis)} disagree")
    if len(sys.argv) > 3:
        for a, b in dis[:40]:
            print("  ", label(sim, a), "vs", label(sim, b))
