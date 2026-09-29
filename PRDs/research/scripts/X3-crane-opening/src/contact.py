"""Contact on the torn ("stitched") crane with ipctk.

ipctk decides adjacency from shared vertex indices. On the torn mesh, two
copies of one material vertex are different indices, so ipctk would treat
elements meeting at a stitched fold as strangers and push the copies apart.
Its per-vertex-pair filter is OR-combined over a primitive's vertices, which
cannot express "exclude pairs that share a material vertex". So candidates
are built by ipctk's broad phase and filtered here by MATERIAL adjacency:
exactly the pairs ipctk would skip on the welded (untorn) sheet.
"""
import numpy as np
import ipctk


class Contact:
    def __init__(self, V, T, mat, dhat, kappa):
        self.T = T.astype(np.int32)
        self.E = ipctk.edges(self.T)
        self.mesh = ipctk.CollisionMesh(V, self.E, self.T)
        self.mat = mat
        self.dhat = dhat
        self.kappa = kappa
        self.B = ipctk.BarrierPotential(dhat, kappa)
        self.Emat = mat[self.E]
        self.Tmat = mat[self.T]

    def _filter(self, c):
        mat, Em, Tm = self.mat, self.Emat, self.Tmat
        c.fv_candidates = [x for x in c.fv_candidates
                           if mat[x.vertex_id] not in Tm[x.face_id]]
        c.ee_candidates = [x for x in c.ee_candidates
                           if not (set(Em[x.edge0_id]) & set(Em[x.edge1_id]))]
        c.ev_candidates = [x for x in c.ev_candidates
                           if mat[x.vertex_id] not in Em[x.edge_id]]
        c.vv_candidates = [x for x in c.vv_candidates
                           if mat[x.vertex0_id] != mat[x.vertex1_id]]
        return c

    def candidates(self, V, V1=None, inflate=None):
        c = ipctk.Candidates()
        inflate = self.dhat if inflate is None else inflate
        if V1 is None:
            c.build(self.mesh, V, inflate)
        else:
            c.build(self.mesh, V, V1, inflate)
        return self._filter(c)

    def collisions(self, V):
        col = ipctk.NormalCollisions()
        col.build(self.candidates(V), self.mesh, V, self.dhat)
        return col

    def energy_grad_hess(self, V, need_hess=True):
        col = self.collisions(V)
        e = self.B(col, self.mesh, V)
        g = self.B.gradient(col, self.mesh, V)
        H = self.B.hessian(col, self.mesh, V, ipctk.PSDProjectionMethod.CLAMP) if need_hess else None
        return e, g, H, len(col)

    def energy(self, V):
        col = self.collisions(V)
        return self.B(col, self.mesh, V)

    def min_distance(self, V, radius):
        col = ipctk.NormalCollisions()
        col.build(self.candidates(V, inflate=radius), self.mesh, V, radius)
        if len(col) == 0:
            return np.inf
        return float(np.sqrt(col.compute_minimum_distance(self.mesh, V)))

    def step_size(self, V0, V1):
        c = self.candidates(V0, V1, inflate=0.0)
        return c.compute_collision_free_stepsize(self.mesh, V0, V1, 0.0, ipctk.AdditiveCCD())



def crossing_pairs(V, F):
    """Triangle pairs sharing no vertex where an edge of one crosses the other.

    Welded mesh (shared vertices). Brute-force AABB prefilter, then
    ipctk.is_edge_intersecting_triangle on the 6 edge/triangle tests."""
    F = np.asarray(F)
    P = V[F]                                  # (nf,3,3)
    lo, hi = P.min(1), P.max(1)
    nf = len(F)
    ov = np.all((lo[:, None, :] <= hi[None, :, :] + 1e-12) & (lo[None, :, :] <= hi[:, None, :] + 1e-12), axis=2)
    iu, ju = np.nonzero(np.triu(ov, 1))
    out = []
    Fs = [set(f) for f in F]
    for i, j in zip(iu, ju):
        if Fs[i] & Fs[j]:
            continue
        hit = False
        for (a, b) in ((0, 1), (1, 2), (2, 0)):
            if ipctk.is_edge_intersecting_triangle(P[i, a], P[i, b], P[j, 0], P[j, 1], P[j, 2]) or \
               ipctk.is_edge_intersecting_triangle(P[j, a], P[j, b], P[i, 0], P[i, 1], P[i, 2]):
                hit = True
                break
        if hit:
            out.append((i, j))
    return out
