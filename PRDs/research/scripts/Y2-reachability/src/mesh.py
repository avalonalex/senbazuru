"""Mesh loading, subdivision and paper measurements for the Y2 reachability test.

Everything here is written for this experiment. A study FOLD file carries the
folded 3D positions in `vertices_coords` and the flat-sheet position of the same
vertex in `senbazuru:material_coords`; the flat sheet is the rest state that
paper must stay isometric to.
"""
import json
import numpy as np

CREASE = ("M", "V", "F", "U")  # lines of the crease pattern: free hinges here


def load_fold(path):
    d = json.load(open(path))
    X = np.array(d["vertices_coords"], float)
    U = np.array(d["senbazuru:material_coords"], float)
    F = np.array(d["faces_vertices"], int)
    E = np.array(d["edges_vertices"], int)
    A = list(d["edges_assignment"])
    return build(X, U, F, E, A, raw=d)


def build(X, U, F, E, A, raw=None):
    # orient every triangle anticlockwise on the flat sheet
    F = F.copy()
    a, b, c = U[F[:, 0]], U[F[:, 1]], U[F[:, 2]]
    det = (b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (b[:, 1] - a[:, 1]) * (c[:, 0] - a[:, 0])
    flip = det < 0
    F[flip] = F[flip][:, [0, 2, 1]]
    area_t = 0.5 * np.abs(det)
    assign = {}
    for (i, j), s in zip(E, A):
        assign[(min(i, j), max(i, j))] = s
    # edge -> (face, position) uses
    uses = {}
    for fi, f in enumerate(F):
        for k in range(3):
            i, j = f[k], f[(k + 1) % 3]
            uses.setdefault((min(i, j), max(i, j)), []).append((fi, i, j, f[(k + 2) % 3]))
    edges, eassign, eweight = [], [], []
    hinges, hkind, hweight = [], [], []
    for key, us in uses.items():
        s = assign.get(key, "J" if len(us) == 2 else "B")
        edges.append(key)
        eassign.append(s)
        eweight.append(sum(area_t[u[0]] for u in us) / 3.0)
        if len(us) == 2:
            (f1, i, j, k), (f2, i2, j2, l) = us
            # triangle 1 is (i, j, k) anticlockwise; triangle 2 then runs j -> i
            assert i2 == j and j2 == i, "inconsistent orientation"
            hinges.append((i, j, k, l))
            hkind.append(s)
            L = np.linalg.norm(U[i] - U[j])
            hweight.append(3.0 * L * L / (area_t[f1] + area_t[f2]))
    edges = np.array(edges, int)
    rest = np.linalg.norm(U[edges[:, 0]] - U[edges[:, 1]], axis=1)
    varea = np.zeros(len(U))
    for k in range(3):
        np.add.at(varea, F[:, k], area_t / 3.0)
    m = dict(X=X, U=U, F=F, area_t=area_t, edges=edges, eassign=np.array(eassign), eweight=np.array(eweight),
             rest=rest, hinges=np.array(hinges, int), hkind=np.array(hkind), hweight=np.array(hweight),
             varea=varea, raw=raw, assign=assign)
    return m


def subdivide(m):
    """1-to-4 midpoint subdivision in material space. The folded target is the
    same piecewise-flat surface (new vertices at 3D edge midpoints). A new edge
    that halves an old edge keeps its assignment; edges inside a triangle are J."""
    X, U, F = m["X"], m["U"], m["F"]
    mid = {}
    Xn, Un = list(X), list(U)
    for (i, j) in m["edges"]:
        mid[(i, j)] = len(Xn)
        Xn.append(0.5 * (X[i] + X[j]))
        Un.append(0.5 * (U[i] + U[j]))
    def M(i, j):
        return mid[(min(i, j), max(i, j))]
    Fn, En, An = [], [], []
    for (i, j), s in zip(m["edges"], m["eassign"]):
        k = M(i, j)
        En += [(i, k), (k, j)]
        An += [s, s]
    for (a, b, c) in F:
        ab, bc, ca = M(a, b), M(b, c), M(c, a)
        Fn += [(a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)]
        En += [(ab, bc), (bc, ca), (ca, ab)]
        An += ["J", "J", "J"]
    return build(np.array(Xn), np.array(Un), np.array(Fn), np.array(En), An)


# ------------------------------------------------------------------ measures
def principal_strains(m, X):
    """Per triangle (smallest, largest) principal stretch minus one, the same
    definition as H1's strain_stats.py and the study's principalStrains."""
    U, F = m["U"], m["F"]
    a, b, c = F[:, 0], F[:, 1], F[:, 2]
    du1, du2 = U[b] - U[a], U[c] - U[a]
    det = du1[:, 0] * du2[:, 1] - du1[:, 1] * du2[:, 0]
    dx1, dx2 = X[b] - X[a], X[c] - X[a]
    Fu = (du2[:, 1, None] * dx1 - du1[:, 1, None] * dx2) / det[:, None]
    Fv = (du1[:, 0, None] * dx2 - du2[:, 0, None] * dx1) / det[:, None]
    A = (Fu * Fu).sum(1); B = (Fu * Fv).sum(1); C = (Fv * Fv).sum(1)
    sp = np.sqrt((A - C) ** 2 + 4 * B * B)
    lo = np.sqrt(np.maximum(0, (A + C - sp) / 2)) - 1
    hi = np.sqrt(np.maximum(0, (A + C + sp) / 2)) - 1
    return lo, hi


def edge_error(m, X):
    e = m["edges"]
    L = np.linalg.norm(X[e[:, 0]] - X[e[:, 1]], axis=1)
    return np.abs(L - m["rest"]) / m["rest"]


def dihedral(m, X):
    """Signed turning angle at every hinge, 0 = flat (radians)."""
    h = m["hinges"]
    i, j, k, l = h[:, 0], h[:, 1], h[:, 2], h[:, 3]
    e = X[j] - X[i]
    n1 = np.cross(e, X[k] - X[i])
    n2 = np.cross(X[i] - X[j], X[l] - X[j])
    en = e / np.linalg.norm(e, axis=1)[:, None]
    s = (np.cross(n1, n2) * en).sum(1)
    c = (n1 * n2).sum(1)
    return np.arctan2(s, c)


def angle_defect(m, X):
    """|sum of 3D corner angles - sum of flat corner angles| per vertex (deg)."""
    F = m["F"]
    def sums(P):
        s = np.zeros(len(P))
        for k in range(3):
            p, q, r = F[:, k], F[:, (k + 1) % 3], F[:, (k + 2) % 3]
            a = P[q] - P[p]; b = P[r] - P[p]
            cosang = (a * b).sum(1) / (np.linalg.norm(a, axis=1) * np.linalg.norm(b, axis=1))
            np.add.at(s, p, np.arccos(np.clip(cosang, -1, 1)))
        return s
    U3 = np.hstack([m["U"], np.zeros((len(m["U"]), 1))])
    return np.degrees(np.abs(sums(X) - sums(U3)))


def crossings(m, X, tol=1e-7):
    """Triangle pairs that pass through each other: the study's test
    (Senbazuru.Origami.Contact.crosses) re-implemented. Each triangle must
    strictly straddle the other's plane and their cuts along the planes'
    intersection line must overlap by more than tol."""
    F = m["F"]
    T = X[F]  # (n,3,3)
    lo, hi = T.min(1), T.max(1)
    n = len(F)
    nrm = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    nrm /= np.linalg.norm(nrm, axis=1)[:, None]
    I, J = np.triu_indices(n, 1)
    ok = np.all(lo[I] <= hi[J] + tol, 1) & np.all(lo[J] <= hi[I] + tol, 1)
    I, J = I[ok], J[ok]
    def sd(P, Q):  # distances of Q's corners to P's plane
        return np.einsum("nj,nkj->nk", nrm[P], T[Q] - T[P][:, :1, :])
    dAB = sd(I, J); dBA = sd(J, I)
    strad = ((dAB < -tol).any(1) & (dAB > tol).any(1) & (dBA < -tol).any(1) & (dBA > tol).any(1))
    I, J, dAB, dBA = I[strad], J[strad], dAB[strad], dBA[strad]
    line = np.cross(nrm[I], nrm[J])
    ln = np.linalg.norm(line, axis=1)
    keep = ln >= 1e-12
    I, J, dAB, dBA, line, ln = I[keep], J[keep], dAB[keep], dBA[keep], line[keep], ln[keep]
    d = line / ln[:, None]
    def interval(P, dist):  # section of triangle P cut by the other's plane
        lo_ = np.full(len(P), np.inf); hi_ = np.full(len(P), -np.inf)
        for k in range(3):
            pk = T[P, k]
            on = dist[:, k] == 0
            t = (pk * d).sum(1)
            lo_ = np.where(on, np.minimum(lo_, t), lo_); hi_ = np.where(on, np.maximum(hi_, t), hi_)
            q = (k + 1) % 3
            dp, dq = dist[:, k], dist[:, q]
            cr = dp * dq < 0
            s = dp / np.where(cr, dp - dq, 1)
            pt = pk + s[:, None] * (T[P, q] - pk)
            t = (pt * d).sum(1)
            lo_ = np.where(cr, np.minimum(lo_, t), lo_); hi_ = np.where(cr, np.maximum(hi_, t), hi_)
        return lo_, hi_
    l1, h1 = interval(J, dAB)  # B's section by A's plane
    l2, h2 = interval(I, dBA)
    ov = np.minimum(h1, h2) - np.maximum(l1, l2) > tol
    return list(zip(I[ov].tolist(), J[ov].tolist()))


# ------------------------------------------------------------------ camera
def upright_basis():
    """The gallery's 'upright' camera (WholeCraneGallery.hs): forward
    (1, sqrt 2, -1), up hint (0, -1, 0), built as Render.Camera.basisFrom does."""
    f = np.array([1.0, np.sqrt(2), -1.0]); f /= np.linalg.norm(f)
    up = np.array([0.0, -1.0, 0.0])
    r = np.cross(f, up); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return r, u, f


def project(X, basis=None):
    r, u, f = basis or upright_basis()
    return np.stack([X @ r, X @ u], 1), X @ f


def raster(m, X, box, ppu, basis=None):
    """Binary mask of the projected paper (union of triangles), pixel centres."""
    P, _ = project(X, basis)
    x0, y0, x1, y1 = box
    W = int(np.ceil((x1 - x0) * ppu)); H = int(np.ceil((y1 - y0) * ppu))
    mask = np.zeros((H, W), bool)
    for (a, b, c) in m["F"]:
        A_, B_, C_ = P[a], P[b], P[c]
        mn = np.minimum(np.minimum(A_, B_), C_); mx = np.maximum(np.maximum(A_, B_), C_)
        i0 = max(int(np.floor((mn[0] - x0) * ppu - 0.5)), 0); i1 = min(int(np.ceil((mx[0] - x0) * ppu - 0.5)), W - 1)
        j0 = max(int(np.floor((y1 - mx[1]) * ppu - 0.5)), 0); j1 = min(int(np.ceil((y1 - mn[1]) * ppu - 0.5)), H - 1)
        if i1 < i0 or j1 < j0:
            continue
        xs = x0 + (np.arange(i0, i1 + 1) + 0.5) / ppu
        ys = y1 - (np.arange(j0, j1 + 1) + 0.5) / ppu
        gx, gy = np.meshgrid(xs, ys)
        def side(p, q):
            return (q[0] - p[0]) * (gy - p[1]) - (q[1] - p[1]) * (gx - p[0])
        s1, s2, s3 = side(A_, B_), side(B_, C_), side(C_, A_)
        inside = ((s1 >= 0) & (s2 >= 0) & (s3 >= 0)) | ((s1 <= 0) & (s2 <= 0) & (s3 <= 0))
        mask[j0:j1 + 1, i0:i1 + 1] |= inside
    return mask


def outline(mask):
    """Boundary pixels of a mask (4-neighbour), including hole boundaries."""
    p = np.pad(mask, 1)
    inner = p[1:-1, 1:-1] & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
    return mask & ~inner


def silhouette_compare(m, Xa, Xb, px=600, ss=4, basis=None):
    """Outline distances between two poses at the upright camera, in pixels at
    `px` per sheet unit, measured on a raster `ss` times finer."""
    from scipy.ndimage import distance_transform_edt
    Pa, _ = project(Xa, basis); Pb, _ = project(Xb, basis)
    allp = np.vstack([Pa, Pb])
    pad = 0.02
    box = (allp[:, 0].min() - pad, allp[:, 1].min() - pad, allp[:, 0].max() + pad, allp[:, 1].max() + pad)
    ppu = px * ss
    ma = raster(m, Xa, box, ppu, basis); mb = raster(m, Xb, box, ppu, basis)
    oa, ob = outline(ma), outline(mb)
    da = distance_transform_edt(~oa) / ss  # distance to a's outline, in px
    db = distance_transform_edt(~ob) / ss
    ab = db[oa]; ba = da[ob]
    xor = (ma ^ mb).sum() / ss ** 2
    return dict(hausdorff_px=float(max(ab.max(), ba.max())), mean_px=float(0.5 * (ab.mean() + ba.mean())),
                p95_px=float(max(np.percentile(ab, 95), np.percentile(ba, 95))),
                xor_px2=float(xor), area_px2=float(ma.sum() / ss ** 2),
                xor_fraction=float((ma ^ mb).sum() / ma.sum()))


def measure(m, X, X0=None, silhouette=True, cross=True):
    lo, hi = principal_strains(m, X)
    A = m["area_t"]
    mag = np.maximum(np.abs(lo), np.abs(hi))
    th = dihedral(m, X)
    J = m["hkind"] == "J"
    ad = angle_defect(m, X)
    out = dict(max_principal_strain=float(mag.max()), max_stretch=float(hi.max()), max_squash=float(lo.min()),
               area_over_1pct=float(A[mag > 0.01].sum() / A.sum()), area_over_01pct=float(A[mag > 0.001].sum() / A.sum()),
               area_over_10pct=float(A[mag > 0.10].sum() / A.sum()),
               p95_strain=float(np.percentile(mag, 95)),
               max_edge_error=float(edge_error(m, X).max()),
               J_over_45=int((np.abs(th[J]) > np.radians(45)).sum()),
               J_over_20=int((np.abs(th[J]) > np.radians(20)).sum()),
               J_max_deg=float(np.degrees(np.abs(th[J]).max())),
               defect_over_5=int((ad > 5).sum()), defect_over_1=int((ad > 1).sum()), defect_max=float(ad.max()))
    if cross:
        out["crossing_pairs"] = len(crossings(m, X))
    if X0 is not None:
        d = np.linalg.norm(X - X0, axis=1)
        P, _ = project(X); P0, _ = project(X0)
        dp = np.linalg.norm(P - P0, axis=1) * 600
        w = m["varea"] / m["varea"].sum()
        out.update(vertex_max_px=float(d.max() * 600), vertex_mean_px=float((w * d).sum() * 600),
                   proj_vertex_max_px=float(dp.max()), proj_vertex_mean_px=float((w * dp).sum()))
        if silhouette:
            out.update({"sil_" + k: v for k, v in silhouette_compare(m, X0, X).items()})
    return out


def write_fold(m, X, path, title):
    d = dict(m["raw"]) if m["raw"] is not None else {}
    d["vertices_coords"] = X.tolist()
    d["file_title"] = title
    json.dump(d, open(path, "w"))
