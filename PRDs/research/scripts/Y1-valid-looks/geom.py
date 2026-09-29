"""Vectorised triangle-pair geometry for the Y1 display-smoothing test.

Written for this experiment (own code, MIT-compatible). Nothing is copied from
any library; ipctk is used only as an independent cross-check in check.py.

Definitions used throughout
---------------------------
* A *crossing* pair is two triangles sharing no vertex where some edge of one
  passes through the interior of the other transversally: its two endpoints lie
  strictly on opposite sides of the other's plane (by more than PLANE_EPS times
  the edge length) and the hit point lies strictly inside the triangle
  (barycentrics > BARY_EPS). Coplanar overlap (stacked zero-thickness layers)
  is deliberately NOT a crossing: faceOrders says which one is on top.
* The *distance* of a pair is the smallest Euclidean distance between the two
  closed triangles (0 when they cross or touch).
"""
import json
import numpy as np
from scipy.spatial import cKDTree

PLANE_EPS = 1e-9
BARY_EPS = 1e-9


# ----------------------------------------------------------------- FOLD input
def load_fold(path):
    d = json.load(open(path))
    V = np.array([list(v) + [0.0] * (3 - len(v)) for v in d["vertices_coords"]], float)
    F = np.array(d["faces_vertices"], int)
    assert F.shape[1] == 3, "triangles only"
    E = np.array(d["edges_vertices"], int)
    A = list(d["edges_assignment"])
    panels = np.array(d.get("senbazuru:source_panels", list(range(len(F)))))
    return dict(V=V, F=F, E=E, A=A, panels=panels, raw=d)


def sharp_edge_set(fold, kinds=("M", "V", "F", "B")):
    return {frozenset(map(int, e)) for e, a in zip(fold["E"], fold["A"]) if a in kinds}


# ----------------------------------------------------------------- normals
def face_normals(V, F):
    n = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    return n / np.maximum(np.linalg.norm(n, axis=1), 1e-300)[:, None]


def corner_normals(V, F, sharp):
    """Per-corner shading normals: average (angle-weighted) of the faces in the
    same smooth fan around the vertex, the fan being cut at sharp edges. If the
    average vanishes or points more than ~84 degrees away from the corner's own
    face normal (faces folded back on each other across a non-sharp edge), the
    corner keeps its face normal, as PaperLighting does for reversed corners."""
    FN = face_normals(V, F)
    nf = len(F)
    # angle at each corner
    ang = np.zeros((nf, 3))
    for k in range(3):
        a, b, c = F[:, k], F[:, (k + 1) % 3], F[:, (k + 2) % 3]
        u = V[b] - V[a]; w = V[c] - V[a]
        cosv = (u * w).sum(1) / np.maximum(np.linalg.norm(u, axis=1) * np.linalg.norm(w, axis=1), 1e-300)
        ang[:, k] = np.arccos(np.clip(cosv, -1, 1))
    # union-find of (face, corner) across non-sharp edges
    parent = {}

    def find(x):
        while parent.setdefault(x, x) != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(x, y):
        parent[find(x)] = find(y)

    edge_uses = {}
    for fi in range(nf):
        for k in range(3):
            a, b = int(F[fi, k]), int(F[fi, (k + 1) % 3])
            edge_uses.setdefault(frozenset((a, b)), []).append((fi, k, (k + 1) % 3, a, b))
    for key, uses in edge_uses.items():
        if key in sharp or len(uses) != 2:
            continue
        (f1, k1a, k1b, a1, b1), (f2, k2a, k2b, a2, b2) = uses
        # corners of the same vertex on the two faces join one fan
        c1 = {a1: k1a, b1: k1b}; c2 = {a2: k2a, b2: k2b}
        for v in key:
            union((f1, c1[v]), (f2, c2[v]))
    acc = {}
    for fi in range(nf):
        for k in range(3):
            r = find((fi, k))
            acc[r] = acc.get(r, 0) + ang[fi, k] * FN[fi]
    CN = np.zeros((nf, 3, 3))
    flat_kept = 0
    for fi in range(nf):
        for k in range(3):
            s = acc[find((fi, k))]
            L = np.linalg.norm(s)
            if L < 1e-12 or (s @ FN[fi]) / L < 0.1:
                CN[fi, k] = FN[fi]; flat_kept += 1
            else:
                CN[fi, k] = s / L
    return CN, flat_kept


# ----------------------------------------------------------------- tessellation
def tess_pattern(n):
    """Barycentric sample points and sub-triangles of a triangle split n x n."""
    pts, idx = [], {}
    for i in range(n + 1):
        for j in range(n + 1 - i):
            idx[(i, j)] = len(pts)
            pts.append((1 - (i + j) / n, i / n, j / n))
    tris = []
    for i in range(n):
        for j in range(n - i):
            tris.append((idx[(i, j)], idx[(i + 1, j)], idx[(i, j + 1)]))
            if i + j < n - 1:
                tris.append((idx[(i + 1, j)], idx[(i + 1, j + 1)], idx[(i, j + 1)]))
    return np.array(pts), np.array(tris)


def phong_tessellate(V, F, CN, n=4, alpha=0.75):
    """Phong tessellation (Boubekeur & Alexa 2008), own implementation.

    For barycentrics (u, v, w) with corner positions P_i and corner normals n_i:
        p      = u P0 + v P1 + w P2
        pi_i   = p - ((p - P_i) . n_i) n_i        (projection on corner i's tangent plane)
        p*     = (1 - alpha) p + alpha (u pi_0 + v pi_1 + w pi_2)
    Vertices are generated per face, so two faces can disagree along a shared
    edge (a crack). Returns (C, Ft, parent, crack): C are the sub-triangles'
    corner positions (k,3,3) exactly as each face generates them; Ft is the
    topology welded from the alpha = 0 positions, used only to decide which
    sub-triangles share a vertex; crack is the largest disagreement between
    the two faces along any shared source edge.
    """
    B, T = tess_pattern(n)
    P = V[F]                                      # (nf, 3, 3)
    p = np.einsum("sk,fkd->fsd", B, P)            # (nf, ns, 3)
    out = (1 - alpha) * p
    for k in range(3):
        d = ((p - P[:, None, k, :]) * CN[:, None, k, :]).sum(-1, keepdims=True)
        proj = p - d * CN[:, None, k, :]
        out = out + alpha * B[None, :, k, None] * proj
    nf, ns = out.shape[:2]
    Ft_raw = (T[None, :, :] + (np.arange(nf) * ns)[:, None, None]).reshape(-1, 3)
    parent = np.repeat(np.arange(nf), len(T))
    crack = crack_width(F, B, out, n)
    _, inv = weld(p.reshape(-1, 3), 1e-12)
    C = out.reshape(-1, 3)[Ft_raw]
    return C, inv[Ft_raw], parent, crack


def crack_width(F, B, out, n):
    """Largest distance between the two faces' tessellations of a shared edge."""
    # sample index along edge (a -> b) of face corners k -> k+1
    edge_samples = {}
    for s, (b0, b1, b2) in enumerate(B):
        for k in range(3):
            bk = (b0, b1, b2)
            if abs(bk[(k + 2) % 3]) < 1e-12:  # on edge k -> k+1
                t = bk[(k + 1) % 3]
                edge_samples.setdefault(k, []).append((t, s))
    for k in edge_samples:
        edge_samples[k].sort()
    uses = {}
    for fi in range(len(F)):
        for k in range(3):
            a, b = int(F[fi, k]), int(F[fi, (k + 1) % 3])
            pts = out[fi, [s for t, s in edge_samples[k]]]
            if a > b:
                a, b = b, a; pts = pts[::-1]
            uses.setdefault((a, b), []).append(pts)
    worst = 0.0
    for key, u in uses.items():
        if len(u) == 2:
            worst = max(worst, float(np.abs(np.linalg.norm(u[0] - u[1], axis=1)).max()))
    return worst


def weld(X, tol):
    key = np.round(X / tol).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    return X[first], inv.ravel()


def quads_to_tris(P):
    """Polygons (list of index lists) -> triangles, fan from the first corner."""
    out = []
    for poly in P:
        for i in range(1, len(poly) - 1):
            out.append((poly[0], poly[i], poly[i + 1]))
    return np.array(out, int)


# ----------------------------------------------------------------- broad phase
def candidate_pairs(P, F, pad):
    """All triangle pairs (i < j) sharing no vertex whose padded AABBs overlap.
    P: (m,3,3) corner positions; F: (m,3) topological vertex ids."""
    lo = P.min(1) - pad / 2
    hi = P.max(1) + pad / 2
    c = (lo + hi) / 2
    r = np.linalg.norm(hi - lo, axis=1).max() / 2
    tree = cKDTree(c)
    pairs = tree.query_pairs(2 * r, output_type="ndarray")
    if len(pairs) == 0:
        return pairs
    i, j = pairs[:, 0], pairs[:, 1]
    ok = np.all((lo[i] <= hi[j]) & (lo[j] <= hi[i]), axis=1)
    i, j = i[ok], j[ok]
    share = np.zeros(len(i), bool)
    for a in range(3):
        for b in range(3):
            share |= F[i, a] == F[j, b]
    return np.stack([i[~share], j[~share]], 1)


# ----------------------------------------------------------------- narrow phase
def _pt_tri(p, a, b, c):
    """Squared distance point -> triangle, vectorised (Ericson, Real-Time
    Collision Detection, 5.1.5, re-derived)."""
    ab = b - a; ac = c - a; ap = p - a
    d1 = (ab * ap).sum(-1); d2 = (ac * ap).sum(-1)
    bp = p - b
    d3 = (ab * bp).sum(-1); d4 = (ac * bp).sum(-1)
    cp = p - c
    d5 = (ab * cp).sum(-1); d6 = (ac * cp).sum(-1)
    va = d3 * d6 - d5 * d4
    vb = d5 * d2 - d1 * d6
    vc = d1 * d4 - d3 * d2
    denom = va + vb + vc
    with np.errstate(divide="ignore", invalid="ignore"):
        v = vb / denom; w = vc / denom
        q = a + ab * v[..., None] + ac * w[..., None]              # interior
        # edges
        v_ab = d1 / (d1 - d3); q_ab = a + ab * v_ab[..., None]
        w_ac = d2 / (d2 - d6); q_ac = a + ac * w_ac[..., None]
        w_bc = (d4 - d3) / ((d4 - d3) + (d5 - d6)); q_bc = b + (c - b) * w_bc[..., None]
    cond = [
        (d1 <= 0) & (d2 <= 0),                                   # A
        (d3 >= 0) & (d4 <= d3),                                  # B
        (d6 >= 0) & (d5 <= d6),                                  # C
        (vc <= 0) & (d1 >= 0) & (d3 <= 0),                       # AB
        (vb <= 0) & (d2 >= 0) & (d6 <= 0),                       # AC
        (va <= 0) & ((d4 - d3) >= 0) & ((d5 - d6) >= 0),         # BC
    ]
    res = q
    # apply in priority order: A, B, C, AB, AC, BC, else interior
    res = np.where(cond[5][..., None], q_bc, res)
    res = np.where(cond[4][..., None], q_ac, res)
    res = np.where(cond[3][..., None], q_ab, res)
    res = np.where(cond[2][..., None], c, res)
    res = np.where(cond[1][..., None], b, res)
    res = np.where(cond[0][..., None], a, res)
    dd = ((p - res) ** 2).sum(-1)
    return np.where(np.isfinite(dd), dd, np.inf)


def _seg_seg(p1, q1, p2, q2):
    """Squared distance segment-segment, vectorised (Ericson 5.1.9, re-derived)."""
    d1 = q1 - p1; d2 = q2 - p2; r = p1 - p2
    a = (d1 * d1).sum(-1); e = (d2 * d2).sum(-1); f = (d2 * r).sum(-1)
    c = (d1 * r).sum(-1); b = (d1 * d2).sum(-1)
    denom = a * e - b * b
    with np.errstate(divide="ignore", invalid="ignore"):
        s = np.where(denom > 1e-30 * np.maximum(a * e, 1e-300), np.clip((b * f - c * e) / denom, 0, 1), 0.0)
        t = (b * s + f) / e
        s = np.where(t < 0, np.clip(-c / a, 0, 1), np.where(t > 1, np.clip((b - c) / a, 0, 1), s))
        t = np.clip(t, 0, 1)
    c1 = p1 + d1 * s[..., None]; c2 = p2 + d2 * t[..., None]
    return ((c1 - c2) ** 2).sum(-1)


def _edge_pierces(p, q, a, b, c):
    """Edge pq passes transversally through the interior of triangle abc."""
    n = np.cross(b - a, c - a)
    nl = np.linalg.norm(n, axis=-1)
    el = np.linalg.norm(q - p, axis=-1)
    sp = ((p - a) * n).sum(-1) / np.maximum(nl, 1e-300)
    sq = ((q - a) * n).sum(-1) / np.maximum(nl, 1e-300)
    tol = PLANE_EPS * np.maximum(el, 1e-300)
    straddle = ((sp > tol) & (sq < -tol)) | ((sp < -tol) & (sq > tol))
    with np.errstate(divide="ignore", invalid="ignore"):
        tt = sp / (sp - sq)
        x = p + (q - p) * tt[..., None]
        # barycentrics of x
        v0 = b - a; v1 = c - a; v2 = x - a
        d00 = (v0 * v0).sum(-1); d01 = (v0 * v1).sum(-1); d11 = (v1 * v1).sum(-1)
        d20 = (v2 * v0).sum(-1); d21 = (v2 * v1).sum(-1)
        den = d00 * d11 - d01 * d01
        v = (d11 * d20 - d01 * d21) / den
        w = (d00 * d21 - d01 * d20) / den
        u = 1 - v - w
    inside = (u > BARY_EPS) & (v > BARY_EPS) & (w > BARY_EPS)
    hit = straddle & inside & (nl > 0)
    depth = np.where(hit, np.minimum(np.abs(sp), np.abs(sq)), 0.0)
    return hit, depth


def pair_metrics(P, pairs, chunk=400_000, depth_out=None):
    """(crossing bool, distance) for each pair of triangles. P: (m,3,3).
    If depth_out is an array, it receives each pair's penetration depth: the
    largest, over piercing edges, of the shorter part of the edge that pokes
    through the other triangle's plane (0 when the pair does not cross)."""
    cross = np.zeros(len(pairs), bool)
    dist = np.zeros(len(pairs))
    for s in range(0, len(pairs), chunk):
        pr = pairs[s:s + chunk]
        A = P[pr[:, 0]]; Bt = P[pr[:, 1]]
        cr = np.zeros(len(pr), bool)
        dep = np.zeros(len(pr))
        for k in range(3):
            for h, dd in (_edge_pierces(A[:, k], A[:, (k + 1) % 3], Bt[:, 0], Bt[:, 1], Bt[:, 2]),
                          _edge_pierces(Bt[:, k], Bt[:, (k + 1) % 3], A[:, 0], A[:, 1], A[:, 2])):
                cr |= h
                dep = np.maximum(dep, dd)
        if depth_out is not None:
            depth_out[s:s + chunk] = dep
        d2 = np.full(len(pr), np.inf)
        for k in range(3):
            d2 = np.minimum(d2, _pt_tri(A[:, k], Bt[:, 0], Bt[:, 1], Bt[:, 2]))
            d2 = np.minimum(d2, _pt_tri(Bt[:, k], A[:, 0], A[:, 1], A[:, 2]))
            for m in range(3):
                d2 = np.minimum(d2, _seg_seg(A[:, k], A[:, (k + 1) % 3], Bt[:, m], Bt[:, (m + 1) % 3]))
        d = np.sqrt(d2)
        d[cr] = 0.0
        cross[s:s + chunk] = cr
        dist[s:s + chunk] = d
    return cross, dist


def _orient2(a, b, c):
    return (b[..., 0] - a[..., 0]) * (c[..., 1] - a[..., 1]) - (b[..., 1] - a[..., 1]) * (c[..., 0] - a[..., 0])


def coplanar_overlap(P, pairs, eps=1e-9, chunk=400_000):
    """Pairs of coplanar triangles (within eps) whose interiors overlap: an edge
    pair crossing properly, or a vertex or centroid strictly inside the other.
    This is the zero-thickness 'stacked layers' relation: faceOrders must order
    every such pair."""
    out = np.zeros(len(pairs), bool)
    for s in range(0, len(pairs), chunk):
        pr = pairs[s:s + chunk]
        A = P[pr[:, 0]]; B = P[pr[:, 1]]
        n = np.cross(A[:, 1] - A[:, 0], A[:, 2] - A[:, 0])
        nl = np.linalg.norm(n, axis=1)
        nu = n / np.maximum(nl, 1e-300)[:, None]
        m = np.cross(B[:, 1] - B[:, 0], B[:, 2] - B[:, 0])
        mu = m / np.maximum(np.linalg.norm(m, axis=1), 1e-300)[:, None]
        cop = (np.abs(((B - A[:, :1]) * nu[:, None]).sum(-1)).max(1) < eps) & \
              (np.abs(((A - B[:, :1]) * mu[:, None]).sum(-1)).max(1) < eps)
        ax = np.argmax(np.abs(nu), axis=1)
        keep = [(np.array([1, 2]), 0), (np.array([0, 2]), 1), (np.array([0, 1]), 2)]
        A2 = np.zeros(A.shape[:2] + (2,)); B2 = np.zeros_like(A2)
        for idx, k in keep:
            sel = ax == k
            A2[sel] = A[sel][:, :, idx]; B2[sel] = B[sel][:, :, idx]
        scale = np.maximum(np.abs(A2).max((1, 2)), 1.0)
        e2 = 1e-12 * scale

        def inside(p, T):
            o = [_orient2(T[:, k], T[:, (k + 1) % 3], p) for k in range(3)]
            return ((o[0] > e2) & (o[1] > e2) & (o[2] > e2)) | ((o[0] < -e2) & (o[1] < -e2) & (o[2] < -e2))
        ov = np.zeros(len(pr), bool)
        for k in range(3):
            for j in range(3):
                a, b = A2[:, k], A2[:, (k + 1) % 3]
                c, d = B2[:, j], B2[:, (j + 1) % 3]
                o1, o2 = _orient2(a, b, c), _orient2(a, b, d)
                o3, o4 = _orient2(c, d, a), _orient2(c, d, b)
                ov |= (((o1 > e2) & (o2 < -e2)) | ((o1 < -e2) & (o2 > e2))) & \
                      (((o3 > e2) & (o4 < -e2)) | ((o3 < -e2) & (o4 > e2)))
            ov |= inside(A2[:, k], B2) | inside(B2[:, k], A2)
        ov |= inside(A2.mean(1), B2) | inside(B2.mean(1), A2)
        out[s:s + chunk] = cop & ov
    return out
