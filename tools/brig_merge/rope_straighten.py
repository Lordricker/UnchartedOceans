
# rope_straighten.py - exec'd by 04_decimate.py (2026-10-26)
# Pulls long, tube-shaped rope pieces (stays, shrouds, backstays) onto the straight line between their two ends.
# Ends stay where they are (attached to the masts / blocks / rails); only the middle moves, never along the rope.
# Left alone: pieces shorter than STRAIGHT_MIN_LEN, pieces that are not a simple tube (ratlines tied to shrouds, loops),
# pieces already straight, and pieces bowed more than STRAIGHT_MAX_BOW of their length (hanging / deliberately curved ropes).
import numpy as np
STRAIGHT_MIN_LEN = 2.5     # m
STRAIGHT_MAX_BOW = 0.08    # bow / chord length above this = a deliberately curved rope, leave it
STRAIGHT_MIN_BOW = 0.003   # below this it is already straight
STRAIGHT_MAX_R = 0.07      # m: a ring wider than this is not a rope tube
STRAIGHT_RING_GAP = 0.03   # m: vertices closer than this along the rope belong to the same ring

def rope_straighten(bm):
    bm.verts.ensure_lookup_table()
    n = len(bm.verts); P = np.array([tuple(v.co) for v in bm.verts], dtype=np.float64); new = P.copy()
    seen = np.zeros(n, dtype=bool)
    st = dict(long_pieces=0, straightened=0, skipped_not_tube=0, skipped_straight=0, skipped_curved=0, ratios=[], worst_before=0.0)
    for v0 in bm.verts:
        if seen[v0.index] or not v0.link_edges: continue
        stack = [v0]; seen[v0.index] = True; comp = []
        while stack:
            a = stack.pop(); comp.append(a.index)
            for e in a.link_edges:
                b = e.other_vert(a)
                if not seen[b.index]: seen[b.index] = True; stack.append(b)
        if len(comp) < 8: continue
        idx = np.array(comp); Q = P[idx]; c = Q.mean(axis=0)
        ax = np.linalg.svd(Q - c, full_matrices=False)[2][0]
        t = (Q - c) @ ax; L = t.max() - t.min()
        if L < STRAIGHT_MIN_LEN: continue
        st["long_pieces"] += 1
        order = np.argsort(t); cuts = np.where(np.diff(t[order]) > STRAIGHT_RING_GAP)[0] + 1
        groups = np.split(order, cuts)
        if len(groups) < 3: st["skipped_not_tube"] += 1; continue
        C = np.array([Q[g].mean(axis=0) for g in groups]); ok = True
        for g, ck in zip(groups, C):
            d = Q[g] - ck; d = d - np.outer(d @ ax, ax)
            if np.linalg.norm(d, axis=1).max() > STRAIGHT_MAX_R: ok = False; break
        if not ok: st["skipped_not_tube"] += 1; continue
        A = C[0]; Bv = C[-1]; chord = Bv - A; Lc = float(np.linalg.norm(chord))
        if Lc < 1e-6: st["skipped_not_tube"] += 1; continue
        u = chord / Lc; s = (C - A) @ u; D = A + np.outer(s, u); dev = np.linalg.norm(C - D, axis=1).max(); ratio = dev / Lc
        if ratio < STRAIGHT_MIN_BOW: st["skipped_straight"] += 1; continue
        if ratio > STRAIGHT_MAX_BOW: st["skipped_curved"] += 1; continue
        for g, dk in zip(groups, D - C): new[idx[g]] += dk
        st["straightened"] += 1; st["ratios"].append(round(float(ratio), 4)); st["worst_before"] = max(st["worst_before"], float(dev))
    for i, v in enumerate(bm.verts):
        if not np.array_equal(new[i], P[i]): v.co = tuple(new[i])
    return st
