"""Slurry, the Drain Wyrm (v0.9.17 roster art, docs/ART_REVAMP.md): a sly, slick black moray standing up
out of the cannery drain. Same locked serpent body as before (seven segments, game/content/core/creatures/
f_slurry.json); every coordinate here is fighter rest space (+Z forward, +Y up, +X the creature's left).

Read from the fight camera (high, behind): two rows of glowing slime pores down the black back, the
ruffled lime dorsal fin that runs from the crown down the back and along the tail in sections on
fx_spring_fin_* springs (it ripples as the body undulates), the webbed gill frills flaring behind the jaw,
the caudal paddle at the tail tip and three riveted brass pipe collars with glowing sludge seeping from
their seams. Close up: a long moray head with a toothy, sly grin, a lower jaw on fx_jaw that opens wide,
half-lidded magenta slit-pupil eyes and cocked brows.
Finish: wet lacquer ('shell') hide on the back with an oily green sheen, mottling and a faint reticulated
net, a plated lime belly ('skin'), a darker matte skull so the eyes and teeth carry, brass with painted
verdigris, jelly fins and sludge. Hype feature: the sludge (seams, drips, gullet, pores, fin rims) glows and
pulses (glow mode 'pulse').
Envelope: the skull, jaw and body stay within ~3 cm of their hit volumes; fins, frills and drips within ~8 cm.

The body is one lofted skin along a spline through the old silhouette, split lengthwise into the back
(shell) and the belly stripe (skin) along shared rings, weighted to the segment bones by arc length with
a smooth blend across each pivot. Everything else hangs off that spine (Spine.at / Spine.surf).
"""
import math
from mathutils import Vector
from fighters_v17 import mix, lin, cell_spots, densify

TAU = math.tau

# palette: art.palette of the creature (primary, secondary, accent, sheen, brass, crest) + shades
BLACK = '2A2F2E'; DEEP = '181D1C'; NET = '34433A'
LIME = 'C7E66B'; LIME_D = '9DBF4B'; LIME_SH = 'AFCF58'
CREST = '8BD426'; CREST_DK = '3F6A17'; CREST_HI = 'D2F86A'; RAY = '2C4A12'
BRASS = 'BE9848'; BRASS_HI = 'E2C374'; VERDI = '4FA58A'; VERDI_HI = '86CDB0'
MAGENTA = 'E04FB0'; GUM = 'A3346F'; MOUTH = '3B1428'; TONGUE = 'C2457F'; TOOTH = 'EFE8D8'
SLUDGE = '8FE03A'; SLUDGE_HI = 'D8FF7A'


def _smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def _lr(a, b, t):
    if isinstance(a, (list, tuple)):
        return tuple(a[q] * (1 - t) + b[q] * t for q in range(len(a)))
    return a * (1 - t) + b * t


def _obj(s, name):
    return next(o for o in s.collection.objects if o.name == name)


def _set_colors(obj, cols):
    data = obj.data.color_attributes['Color'].data
    for i, c in enumerate(cols):
        data[i].color = c


def _fighter(v):
    return Vector((v.co.x, v.co.z, -v.co.y))


# --------------------------------------------------------------------------------------------------
# The spine: a Catmull-Rom centreline resampled by arc length, with parallel-transport frames that match
# Studio.tube (u starts at +X; v = t x u). On this body v is UP along the tail and BACK on the reared part,
# so angle 90 deg is always the dorsal midline and 270 deg the belly.
# --------------------------------------------------------------------------------------------------
class Spine:
    def __init__(self, ctrl, radii, ds=.032):
        P = [Vector(p) for p in ctrl]
        ext = [P[0] * 2 - P[1]] + P + [P[-1] * 2 - P[-2]]
        dense = []
        for i in range(len(P) - 1):
            p0, p1, p2, p3 = ext[i], ext[i + 1], ext[i + 2], ext[i + 3]
            for k in range(24):
                t = k / 24
                pos = .5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (3 * p1 - p0 - 3 * p2 + p3) * t ** 3)
                dense.append((pos, _lr(radii[i], radii[i + 1], t)))
        dense.append((P[-1], radii[-1]))
        acc = [0.0]
        for i in range(1, len(dense)):
            acc.append(acc[-1] + (dense[i][0] - dense[i - 1][0]).length)
        self.length = acc[-1]
        n = max(2, round(self.length / ds))
        self.s, self.c, self.r = [], [], []
        q = 0
        for j in range(n + 1):
            sj = self.length * j / n
            while q < len(acc) - 2 and acc[q + 1] < sj:
                q += 1
            t = (sj - acc[q]) / max(1e-9, acc[q + 1] - acc[q])
            self.s.append(sj)
            self.c.append(dense[q][0].lerp(dense[q + 1][0], t))
            self.r.append(_lr(dense[q][1], dense[q + 1][1], t))
        self.t, self.u, self.v = [], [], []
        u = Vector((1, 0, 0))
        for j in range(len(self.c)):
            a = self.c[max(0, j - 1)]; b = self.c[min(len(self.c) - 1, j + 1)]
            t = (b - a).normalized()
            u = (u - t * u.dot(t)).normalized()
            self.t.append(t); self.u.append(u); self.v.append(t.cross(u))

    def at(self, s):
        s = max(0.0, min(self.length, s))
        j = min(len(self.s) - 2, int(s / self.length * (len(self.s) - 1)))
        t = (s - self.s[j]) / (self.s[j + 1] - self.s[j])
        c = self.c[j].lerp(self.c[j + 1], t)
        tt = self.t[j].lerp(self.t[j + 1], t).normalized()
        u = self.u[j].lerp(self.u[j + 1], t)
        u = (u - tt * u.dot(tt)).normalized()
        return c, tt, u, tt.cross(u), _lr(self.r[j], self.r[j + 1], t)

    def surf(self, s, ang, off=0.0):
        c, t, u, v, (rx, ry) = self.at(s)
        return c + u * (math.cos(ang) * (rx + off)) + v * (math.sin(ang) * (ry + off))

    def nearest(self, p):
        p = Vector(p)
        j = min(range(len(self.c)), key=lambda k: (self.c[k] - p).length)
        best, bs = (self.c[j] - p).length, self.s[j]
        for k in range(-20, 21):
            sk = self.s[j] + k * .002
            d = (self.at(sk)[0] - p).length
            if d < best:
                best, bs = d, sk
        return bs


def _smooth_bone_weights(obj, per_vertex, first_bone):
    """per_vertex: list of [(bone, w)] (w sums to 1); obj starts fully on first_bone (Studio.mesh)."""
    groups = {g.name: g for g in obj.vertex_groups}
    for i, ws in enumerate(per_vertex):
        if first_bone not in [b for b, _ in ws]:
            groups[first_bone].remove([i])
        for b, w in ws:
            if b not in groups:
                groups[b] = obj.vertex_groups.new(name=b)
            groups[b].add([i], w, 'REPLACE')


def _ring_weights(s, bounds, hb=.08):
    """Segment weights at arc length s: the owning segment, blended smoothly across each pivot."""
    for sb, a, b in bounds:
        if abs(s - sb) < hb:
            w = _smooth(-hb, hb, s - sb)
            return [(x, y) for x, y in [(a, 1 - w), (b, w)] if y > .002]
    owner = bounds[0][1]
    for sb, a, b in bounds:
        if s >= sb:
            owner = b
    return [(owner, 1.0)]


# --------------------------------------------------------------------------------------------------
# generic builders
# --------------------------------------------------------------------------------------------------
def ring_uv(s, name, c, u, v, R, thick, bone, color, mat='brass', glow=0, n=40, sides=6):
    """A closed ring of radius R around centre c in the plane spanned by u, v (thick: tube radius or list)."""
    pts = [tuple(c + (u * math.cos(TAU * i / n) + v * math.sin(TAU * i / n)) * R) for i in range(n)]
    return s.tube(name, pts, thick, bone, color, mat, glow, n=sides, closed=True)


def membrane(s, name, base, outs, heights, bone, rays, width=.0065, m=9, mat='jelly', edge_glow=.3,
             cols=(CREST_DK, CREST, CREST_HI, RAY)):
    """A webbed fin: a thin lens-section blade standing on `base` (points just inside the skin), rising
    heights[j] along outs[j]. Rays (indices in `rays`) are darker spines; the rim glows a little."""
    J = len(base)
    base = [Vector(b) for b in base]
    verts, info = [], []
    for j in range(J):
        o = Vector(outs[j]).normalized()
        tan = (base[min(J - 1, j + 1)] - base[max(0, j - 1)]).normalized()
        sd = tan.cross(o).normalized()
        h = heights[j]
        w = width * (1.0 if h > .02 else max(.4, h / .02))
        for k in range(m):
            a = math.pi * k / (m - 1)
            f = math.sin(a)
            x = math.cos(a) * w * (1 - .55 * f)
            verts.append(tuple(base[j] + sd * x + o * (h * f)))
            info.append((j, f))
    faces = []
    for j in range(J - 1):
        for k in range(m - 1):
            faces.append((j * m + k, j * m + k + 1, (j + 1) * m + k + 1, (j + 1) * m + k))
        faces.append((j * m + m - 1, j * m, (j + 1) * m, (j + 1) * m + m - 1))
    faces.append(tuple(range(m)))
    faces.append(tuple((J - 1) * m + k for k in range(m - 1, -1, -1)))
    obj = s.mesh(name, verts, faces, bone, CREST, mat)
    dk, mid, hi, ray = (lin(c) for c in cols)
    out = []
    for j, f in info:
        col = mix(dk, mid, _smooth(.05, .55, f))
        if j in rays and f < .9:
            col = mix(col, ray, .75)
        glow = 0.0
        if f > .8:
            col = mix(col, hi, _smooth(.8, .97, f))
            glow = edge_glow * _smooth(.8, 1.0, f)
        out.append((col[0], col[1], col[2], glow))
    _set_colors(obj, out)
    return obj


def pore(s, name, c, nrm, along, R, weights, n=10):
    """A glowing slime pore: a low domed blister lying on the skin (rim tucked just under it), elongated
    along the spine. weights: [(bone, w)] copied from the skin underneath so it rides the same blend."""
    c = Vector(c); nrm = Vector(nrm).normalized(); e1 = (Vector(along) - nrm * nrm.dot(Vector(along))).normalized()
    e2 = nrm.cross(e1)
    verts = [tuple(c + nrm * .0045)]
    for rr, hh in ((.55, .0032), (1.0, -.0012)):
        for i in range(n):
            a = TAU * i / n
            verts.append(tuple(c + e1 * (math.cos(a) * R * 1.18 * rr) + e2 * (math.sin(a) * R * .9 * rr) + nrm * hh))
    verts.append(tuple(c - nrm * .006))           # closed underneath (buried), so normals orient reliably
    faces = [(0, 1 + i, 1 + (i + 1) % n) for i in range(n)]
    faces += [(1 + i, 1 + n + i, 1 + n + (i + 1) % n, 1 + (i + 1) % n) for i in range(n)]
    faces += [(2 * n + 1, 1 + n + (i + 1) % n, 1 + n + i) for i in range(n)]
    first = weights[0][0]
    obj = s.mesh(name, verts, faces, first, SLUDGE, 'jelly')
    _smooth_bone_weights(obj, [weights] * len(verts), first)
    hi = lin('D2FA66'); mid = lin('8ED33E'); rim = lin('243A14')
    _set_colors(obj, [(hi[0], hi[1], hi[2], .55)] + [(mid[0], mid[1], mid[2], .38)] * n + [(rim[0], rim[1], rim[2], 0.0)] * (n + 1))
    return obj


def drip(s, name, top, length, bone, bulb=.011, neck=.0045, glow=.85, down=(0, -1, 0), n=10):
    """A hanging teardrop of glowing sludge: thin neck at `top`, bulb at the bottom."""
    top = Vector(top); d = Vector(down).normalized()
    ts = [0, .18, .42, .62, .78, .9, .97, 1.0]
    rs = [neck * 1.3, neck, neck * 1.05, bulb * .8, bulb, bulb * .92, bulb * .55, .0008]
    obj = s.tube(name, [tuple(top + d * (length * t)) for t in ts], rs, bone, SLUDGE, 'jelly', glow, n=n)
    hi = lin(SLUDGE_HI); lo = lin(SLUDGE)
    cols = []
    for v in obj.data.vertices:
        t = (_fighter(v) - top).dot(d) / length
        c = mix(lo, hi, _smooth(.45, .95, t))
        cols.append((c[0], c[1], c[2], glow * (.75 + .25 * t)))
    _set_colors(obj, cols)
    return obj


# --------------------------------------------------------------------------------------------------
# the moray head: a loft along +Z of two-half (super)elliptical sections
# --------------------------------------------------------------------------------------------------
def _sec_xy(rx, ym, rt, rb, a, pt=2.0, pb=2.0):
    ca, sa = math.cos(a), math.sin(a)
    if sa >= 0:
        e = 2.0 / pt
        return rx * math.copysign(abs(ca) ** e, ca), ym + rt * abs(sa) ** e
    e = 2.0 / pb
    return rx * math.copysign(abs(ca) ** e, ca), ym - rb * abs(sa) ** e


class Loft:
    """Sections (z, y_mid, rx, y_top, y_bottom); pt/pb: superellipse powers of the top/bottom halves."""
    def __init__(self, secs, pt=2.0, pb=2.0):
        self.secs = secs; self.pt = pt; self.pb = pb

    def params(self, z):
        secs = self.secs
        if z <= secs[0][0]:
            return secs[0][1:]
        for i in range(len(secs) - 1):
            if secs[i][0] <= z <= secs[i + 1][0]:
                t = (z - secs[i][0]) / (secs[i + 1][0] - secs[i][0])
                return tuple(secs[i][k] * (1 - t) + secs[i + 1][k] * t for k in range(1, 5))
        return secs[-1][1:]

    def half_width(self, z, y):
        ym, rx, yt, yb = self.params(z)
        if y >= ym:
            if y >= yt:
                return -1
            sa = ((y - ym) / max(1e-6, yt - ym)) ** (self.pt / 2.0)
            return rx * (max(0.0, 1 - sa * sa) ** .5) ** (2.0 / self.pt)
        if y <= yb:
            return -1
        sa = ((ym - y) / max(1e-6, ym - yb)) ** (self.pb / 2.0)
        return rx * (max(0.0, 1 - sa * sa) ** .5) ** (2.0 / self.pb)

    def front_z(self, x, y, z0=.0, z1=.62):
        """The most forward z where (x, y) is on/inside the loft (scanning back from the tip)."""
        z = z1
        while z > z0:
            if self.half_width(z, y) >= abs(x):
                return z
            z -= .002
        return z0

    def mesh(self, s, name, bone, color, mat='shell', n=40, soft=False, tip=None, tail=None):
        verts = []
        for (z, ym, rx, yt, yb) in self.secs:
            for i in range(n):
                x, y = _sec_xy(rx, ym, yt - ym, ym - yb, TAU * i / n, self.pt, self.pb)
                verts.append((x, y, z))
        faces = []
        S = len(self.secs)
        for j in range(S - 1):
            for i in range(n):
                a = j * n + i; b = j * n + (i + 1) % n
                faces.append((a, b, b + n, a + n))
        if tail is not None:
            k = len(verts); verts.append(tail)
            for i in range(n):
                faces.append((k, (i + 1) % n, i))
        if tip is not None:
            k = len(verts); verts.append(tip)
            for i in range(n):
                faces.append((k, (S - 1) * n + i, (S - 1) * n + (i + 1) % n))
        return s.mesh(name, verts, faces, bone, color, mat, soft=soft)


def lip_y(z):
    """The gape line (where the jaws meet), back corner to snout tip: it climbs toward the back all the way,
    so the long moray mouth reads as a grin from below (close-ups) as well as from above."""
    zs = [.15, .19, .24, .30, .36, .42, .48, .53, .565, .59]
    ys = [1.519, 1.506, 1.497, 1.489, 1.483, 1.478, 1.474, 1.471, 1.469, 1.468]
    if z <= zs[0]:
        return ys[0]
    for i in range(len(zs) - 1):
        if zs[i] <= z <= zs[i + 1]:
            t = (z - zs[i]) / (zs[i + 1] - zs[i])
            return ys[i] * (1 - t) + ys[i + 1] * t
    return ys[-1]


# --------------------------------------------------------------------------------------------------
def build(s):
    seg = s.segments
    # ---- the spine through the old silhouette (tail tip on the floor -> reared neck into the head) ----
    ctrl = [(0, .13, -1.545), (0, .135, -1.50), (0, .145, -1.42), (0, .155, -1.25), (0, .165, -1.05), (0, .17, -.85),
            (0, .18, -.62), (0, .20, -.42), (0, .235, -.25), (0, .30, -.08), (0, .42, .045), (0, .57, .10),
            (0, .72, .142), (0, .90, .155), (0, 1.07, .158), (0, 1.24, .136), (0, 1.38, .116), (0, 1.455, .128)]
    rad = [(.012, .014), (.046, .052), (.074, .082), (.094, .104), (.112, .121), (.126, .134), (.141, .148),
           (.152, .157), (.162, .165), (.168, .169), (.171, .171), (.168, .168), (.158, .158), (.150, .150),
           (.140, .140), (.131, .131), (.121, .121), (.090, .090)]
    sp = Spine(ctrl, rad, ds=.032)
    s_p = {b: sp.nearest(seg[b]['pivot']) for b in ['body6', 'body5', 'body4', 'body2', 'body1', 'head']}
    s_root = sp.nearest(seg['body3']['pivot'])
    bounds = [(s_p['body6'], 'body6', 'body5'), (s_p['body5'], 'body5', 'body4'), (s_p['body4'], 'body4', 'body3'),
              (s_p['body2'], 'body3', 'body2'), (s_p['body1'], 'body2', 'body1'), (s_p['head'], 'body1', 'head')]
    # collars sit mid-segment on the three reared segments (pipe fittings, the scale cue); team band on body5
    s_col = {'body1': sp.nearest((0, 1.235, .14)), 'body2': sp.nearest((0, .895, .155)), 'body3': sp.nearest((0, .515, .085))}
    s_band = s_p['body5'] - .066

    # glowing slime pores in two rows down the back (the marking the fight camera sees)
    pores = []
    sv, k = .26, 0
    while sv < s_p['head'] - .02:
        c, t, u, v, (rx, ry) = sp.at(sv)
        r = .5 * (rx + ry)
        if all(abs(sv - sc) > .062 for sc in s_col.values()) and abs(sv - s_band) > .055:
            big = k % 2 == 0
            for side in (1, -1):
                pores.append((sv + side * .006 * (1 if big else -1), math.radians(90 + side * (42 + 3 * (k % 3))),
                              (.016 + .085 * r) * (1.0 if big else .72), r))
            k += 1
        sv += .05 + .32 * r

    black = lin(BLACK); deep = lin(DEEP); net_c = lin(NET); lime = lin(LIME); lime_d = lin(LIME_D); lime_sh = lin(LIME_SH)
    halo = lin('3A5A2A'); sheen = lin('22402A'); mottle = lin('121615')

    def hide_col(p, dors, sv=None, ang=None):
        """dors: 1 on the spine .. 0 at the belly stripe edge; sv/ang: spine coordinates (body only)."""
        col = mix(black, deep, _smooth(.6, 1.0, dors) * .9)
        col = mix(col, sheen, .45 * _smooth(.15, .45, dors) * (1 - _smooth(.5, .8, dors)))   # green oil sheen on the flanks
        blot = cell_spots(p, .12, .5, .55, 31)
        if blot > .05:
            col = mix(col, mottle, min(.55, blot * 1.4))
        netv = cell_spots(p, .07, .64, .96, 5)
        if netv < .08 and dors > .15:
            col = mix(col, net_c, .6 * (1 - netv / .08))
        if sv is not None:
            for ps, pa, pr, rr in pores:          # a faint green seep round each pore
                ds_ = sv - ps
                if abs(ds_) > pr * 1.6:
                    continue
                da = (ang - pa + math.pi) % TAU - math.pi
                d = math.sqrt(ds_ * ds_ + (rr * da) ** 2) / (pr * 1.6)
                if d < 1.0:
                    col = mix(col, halo, .55 * (1 - _smooth(.5, 1.0, d)))
        if dors < .3:
            sp2 = cell_spots(p, .042, .46, .6, 13)
            if sp2 > .22:
                col = mix(col, lime_sh, .75 * _smooth(.3, .0, dors))
        return (col[0], col[1], col[2], 0.0)

    # ---- the hide: one skin, split along shared rings into the lacquered back and the plated belly ----
    n = 48
    BEL = (30, 42)                 # ring indices of the belly stripe (270 deg +- 45)
    J = len(sp.c)
    pos = []
    for j in range(J):
        c, u, v = sp.c[j], sp.u[j], sp.v[j]; rx, ry = sp.r[j]
        groove = .0045 if j % 2 == 0 else 0.0
        for i in range(n):
            a = TAU * i / n
            bw = math.sin(math.pi * (i - BEL[0]) / (BEL[1] - BEL[0])) if BEL[0] <= i <= BEL[1] else 0.0
            f = 1 - groove * bw / max(rx, .05)
            pos.append(c + u * (math.cos(a) * rx * f) + v * (math.sin(a) * ry * f))
    tip = sp.c[0] - sp.t[0] * .01
    top = sp.c[-1] + sp.t[-1] * .005

    def part(name, idx, mat):
        remap = {}
        verts, info = [], []
        for j in range(J):
            for i in idx:
                remap[(j, i)] = len(verts); verts.append(tuple(pos[j * n + i])); info.append((j, i))
        it = len(verts); verts.append(tuple(tip)); info.append((0, -1))
        ie = len(verts); verts.append(tuple(top)); info.append((J - 1, -1))
        faces = []
        for j in range(J - 1):
            for q in range(len(idx) - 1):
                a, b = idx[q], idx[q + 1]
                faces.append((remap[(j, a)], remap[(j, b)], remap[(j + 1, b)], remap[(j + 1, a)]))
        for q in range(len(idx) - 1):
            a, b = idx[q], idx[q + 1]
            faces.append((it, remap[(0, b)], remap[(0, a)]))
            faces.append((ie, remap[(J - 1, a)], remap[(J - 1, b)]))
        obj = s.mesh(name, verts, faces, 'body3', BLACK, mat)
        _smooth_bone_weights(obj, [_ring_weights(sp.s[j], bounds) for j, _ in info], 'body3')
        return obj, info

    back, back_info = part('Body - wyrm back', list(range(BEL[1], n)) + list(range(0, BEL[0] + 1)), 'shell')
    belly, belly_info = part('Body - wyrm belly', list(range(BEL[0], BEL[1] + 1)), 'skin')
    cols = []
    for k, (j, i) in enumerate(back_info):
        if i < 0:
            cols.append((deep[0], deep[1], deep[2], 0.0)); continue
        a = TAU * i / n
        dang = abs(((math.degrees(a) - 90 + 180) % 360) - 180)          # 0 on the spine .. 135 at the stripe
        cols.append(hide_col(_fighter(back.data.vertices[k]), 1 - dang / 135.0, sp.s[j], a))
    _set_colors(back, cols)
    cols = []
    for k, (j, i) in enumerate(belly_info):
        if i < 0:
            cols.append((lime_d[0], lime_d[1], lime_d[2], 0.0)); continue
        bw = math.sin(math.pi * (i - BEL[0]) / (BEL[1] - BEL[0]))
        col = mix(lime_sh, lime, _smooth(.0, .55, bw))
        if j % 2 == 0:
            col = mix(col, lime_d, .6 * bw)
        cols.append((col[0], col[1], col[2], 0.0))
    _set_colors(belly, cols)
    for q, (ps, pa, pr, rr) in enumerate(pores):
        c_, t_, u_, v_, _r = sp.at(ps)
        pore(s, 'Detail pore %d' % q, sp.surf(ps, pa, .0005), u_ * math.cos(pa) + v_ * math.sin(pa), t_, pr, _ring_weights(ps, bounds))

    # ---- three brass pipe collars: band, flanged lips, rivets, hex nuts, verdigris, a sludge seam ----
    brass = lin(BRASS); brass_hi = lin(BRASS_HI); verdi = lin(VERDI); verdi_hi = lin(VERDI_HI)

    def tarnish(p, n_, cc, c0, t0, half, lip=0.0):
        """Brass with green verdigris: patches everywhere, gathering toward the lower edge and the lips."""
        ax = (p - c0).dot(t0) / half                  # -1 at the bottom edge .. +1 at the top
        low = _smooth(.1, -1.15, ax)
        col = mix(brass, brass_hi, max(0.0, n_.y) * .45)
        pat = cell_spots(p, .026, .55, .7, 21)
        v = pat * (.8 + 1.1 * low) + low * .3 + lip * .12 - .3
        if v > 0:
            col = mix(col, verdi, min(.85, v * 1.7))
        if v > .38:
            col = mix(col, verdi_hi, .5)
        return (col[0], col[1], col[2], cc[3])

    for k, bone in enumerate(['body1', 'body2', 'body3']):
        sm = s_col[bone]
        c, t, u, v, (rx, ry) = sp.at(sm)
        r = max(rx, ry)
        R = r + .017; half = .029
        dp, dr = densify([tuple(c - t * half), tuple(c + t * half)], [R, R], 4)
        band = s.tube('Collar band %d' % k, dp, dr, bone, BRASS, 'brass', n=40)
        s.paint(band, lambda p, n_, cc, c=c, t=t: tarnish(p, n_, cc, c, t, half))
        for e, sg in (('top', 1), ('bottom', -1)):
            lipo = ring_uv(s, 'Collar lip %d %s' % (k, e), c + t * (sg * half), u, v, R + .004, .0078, bone, BRASS_HI, 'brass', n=36, sides=5)
            s.paint(lipo, lambda p, n_, cc, c=c, t=t: tarnish(p, n_, cc, c, t, half, 1.0))
        for q in range(8):
            a = TAU * q / 8 + .2 + k * .3
            rp = c + (u * math.cos(a) + v * math.sin(a)) * (R + .001)
            s.ellipsoid('Detail rivet %d %d' % (k, q), tuple(rp), (.0074, .0074, .0074), bone, BRASS_HI, 'brass', n=6, m=4)
        for sd in (1, -1):
            o = u * sd
            s.tube('Detail hex nut %d %d' % (k, sd), [tuple(c + o * (R - .004)), tuple(c + o * (R + .011))], [.0135, .0135], bone, BRASS, 'brass', n=6)
            s.tube('Detail bolt %d %d' % (k, sd), [tuple(c + o * (R + .01)), tuple(c + o * (R + .019))], [.0062, .0055], bone, BRASS_HI, 'brass', n=8)
        # sludge squeezing out from under the lower lip, and streaks running down the skin
        seam_s = sm - half - .011
        cs, ts, us, vs, (rxs, rys) = sp.at(seam_s)
        thick = [.0072 + .0034 * (.5 + .5 * math.sin(5 * TAU * i / 36 + k * 1.7)) for i in range(36)]
        ring_uv(s, 'Detail sludge seam %d' % k, cs, us, vs, max(rxs, rys) + .004, thick, bone, SLUDGE, 'jelly', glow=.8, n=36, sides=6)
        for q, (ang, L) in enumerate([(math.radians(232 + 9 * k), .085), (math.radians(306 - 7 * k), .062), (math.radians(118 + 11 * k), .074)]):
            pts, rs = [], []
            for m_ in range(9):
                pts.append(tuple(sp.surf(seam_s - .004 - L * m_ / 8, ang, -.0015)))
                rs.append([.0068, .0058, .0052, .005, .0052, .0068, .0082, .006, .0012][m_])
            st = s.tube('Detail drip streak %d %d' % (k, q), pts, rs, bone, SLUDGE, 'jelly', .75, n=6)
            cc = mix(lin(SLUDGE), lin(SLUDGE_HI), .35)
            _set_colors(st, [(cc[0], cc[1], cc[2], .72)] * len(st.data.vertices))

        # one drop hangs free off the front of the lower lip, on its own spring
        ang = math.radians([335, 205, 325][k])
        radial = u * math.cos(ang) + v * math.sin(ang)
        top_ = c - t * (half + .004) + radial * (R + .008)
        db = s.view_bone('fx_spring_drip_c%d_0' % k, bone, tuple(top_))
        drip(s, 'Detail drip collar %d' % k, top_, .05 - .008 * k, db, bulb=.0098, neck=.0045, n=8)

    # ---- team band: white tint ring on the tail, seen from the camera behind ----
    c, t, u, v, (rx, ry) = sp.at(s_band)
    s.tube('Team tail band', [tuple(c - t * .027), tuple(c + t * .027)], [(rx + .009, ry + .009)] * 2, 'body5', 'FFFFFF', 'team', n=48)

    # ---- the dorsal fin: ruffled sections between collars and joints, each on its own spring ----
    def dorsal(label, s0, s1, hmax, parent, lean=.4, embed=.012, step=.0125, ruffle=.24):
        cnt = max(5, int(round((s1 - s0) / step)) + 1)
        base, outs, hs = [], [], []
        for q in range(cnt):
            sv = s0 + (s1 - s0) * q / (cnt - 1)
            c_, t_, u_, v_, (rx_, ry_) = sp.at(sv)
            base.append(c_ + v_ * (ry_ - embed))
            outs.append((v_ + u_ * (ruffle * math.sin(TAU * (sv - s0) / .15)) - t_ * lean).normalized())
            env = math.sin(math.pi * (.07 + .86 * q / (cnt - 1))) ** .3      # flat-topped: the run reads as one fin
            hs.append(hmax * env * (1.0 if q % 4 == 2 else .87))
        bone = s.view_bone('fx_spring_fin_%s_0' % label, parent, tuple(base[cnt // 2]))
        return membrane(s, 'Fin dorsal %s' % label, base, outs, hs, bone, {q for q in range(cnt) if q % 4 == 2}, m=7,
                        width=.0075, edge_glow=.45)

    m45 = (s_p['body5'] + s_p['body4']) / 2
    b3a = s_p['body4'] + (s_root - s_p['body4']) * .5
    for label, s0, s1, hmax, parent in [
            ('tail', .19, s_p['body6'] - .025, .07, 'body6'),
            ('b5', s_p['body6'] + .025, s_band - .05, .076, 'body5'),
            ('b4a', s_p['body5'] + .025, m45 - .01, .078, 'body4'),
            ('b4b', m45 + .01, s_p['body4'] - .025, .078, 'body4'),
            ('b3a', s_p['body4'] + .025, b3a - .01, .076, 'body3'),
            ('b3b', b3a + .01, s_root + .085, .074, 'body3'),
            ('b3c', s_root + .1, s_col['body3'] - .046, .068, 'body3'),
            ('b3u', s_col['body3'] + .046, s_p['body2'] - .025, .064, 'body3'),
            ('b2l', s_p['body2'] + .025, s_col['body2'] - .046, .064, 'body2'),
            ('b2u', s_col['body2'] + .046, s_p['body1'] - .025, .064, 'body2'),
            ('b1l', s_p['body1'] + .025, s_col['body1'] - .046, .062, 'body1'),
            ('b1u', s_col['body1'] + .046, s_p['head'] - .015, .066, 'body1')]:
        # long runs are split so no section rocks far about its spring pivot (<= ~14 cm each)
        pieces = max(1, math.ceil((s1 - s0) / .145))
        span = (s1 - s0 - .018 * (pieces - 1)) / pieces
        for q in range(pieces):
            a0 = s0 + q * (span + .018)
            if span > .05:
                dorsal(label + ('%d' % q if pieces > 1 else ''), a0, a0 + span, hmax, parent)

    # ---- caudal paddle wrapping the tail tip (fin on a spring) ----
    base, outs, hs = [], [], []
    cnt = 15
    for q in range(cnt):
        f = q / (cnt - 1)                                  # 0: up on the back .. .5: behind the tip .. 1: under it
        sv = .16 * (1 - 2 * f) if f < .5 else .08 * (2 * f - 1)
        c_, t_, u_, v_, (rx_, ry_) = sp.at(max(.004, sv))
        th = math.radians(90 + 180 * f)
        sgn = 1 if f < .5 else -1
        base.append(c_ + v_ * (sgn * max(0.0, ry_ - .01) * min(1.0, abs(.5 - f) * 6)))
        outs.append((v_ * math.sin(th) + t_ * math.cos(th) - t_ * .45).normalized())
        prof = [.026, .042, .055, .064, .071, .077, .081, .083, .078, .07, .06, .05, .038, .026, .014][q]
        hs.append(prof * (1.0 if q % 2 == 1 else .82))
    cb = s.view_bone('fx_spring_caudal_0', 'body6', tuple(sp.at(.07)[0]))
    membrane(s, 'Fin caudal paddle', base, outs, hs, cb, {q for q in range(cnt) if q % 2 == 1}, width=.0078, edge_glow=.45)

    _head(s, hide_col)
    s.tube('Gore fang', [(0, .03, 0), (0, 0, 0), (.01, -.04, 0)], [.015, .012, .001], None, TOOTH, n=16, role='gore')
    # lid_rest is low: the fixed lid folds carry the sly half-lidded look; the rigged lid stays tucked under them
    s.set_look({'glow_mode': 'pulse', 'fx': {'pupil_reach': .011, 'jaw_deg': 30, 'brow_drop': .01, 'lid_rest': .22,
                                             'spring_gain': .9, 'spring_stiffness': 1.15}})
    s.bake_ao(rays=14, distance=.085, strength=.36)


def _head(s, hide_col):
    """The moray head: a long skull to the gape (head bone), the lower jaw on fx_jaw, the toothy grin, tube
    nostrils, rigged half-lidded eyes, cocked brows, the crown fin and gill frills (springs)."""
    lime = lin(LIME); lime_d = lin(LIME_D); mouth = lin(MOUTH)
    # the skull stays inside the head's hit sphere at the back (no nape hanging behind it)
    zs = [.05, .075, .11, .15, .19, .23, .275, .32, .37, .42, .465, .505, .54, .566, .585]
    ymid = [1.553, 1.553, 1.551, 1.547, 1.541, 1.535, 1.528, 1.522, 1.515, 1.509, 1.504, 1.500, 1.498, 1.497, 1.497]
    rxs = [.058, .093, .113, .121, .123, .121, .116, .108, .099, .089, .079, .068, .055, .040, .022]
    ytop = [1.616, 1.658, 1.693, 1.712, 1.716, 1.708, 1.687, 1.656, 1.626, 1.600, 1.580, 1.563, 1.548, 1.532, 1.515]
    ybot = []
    for z in zs:
        throat = 1.452 if z < .11 else 1.452 + (lip_y(z) - .009 - 1.452) * _smooth(.11, .22, z)
        ybot.append(min(throat, lip_y(z) - .009) if z >= .11 else throat)
    head_loft = Loft([(zs[i], ymid[i], rxs[i], ytop[i], ybot[i]) for i in range(len(zs))], pt=2.0, pb=3.0)
    head = head_loft.mesh(s, 'Head - moray skull', 'head', BLACK, 'skin', n=44, soft=True, tip=(0, 1.497, .596), tail=(0, 1.553, .036))

    def head_col(p, n_, c):
        dors = max(0.0, min(1.0, .5 + .5 * n_.y))
        col = hide_col(p, dors)
        if n_.y < -.25 and p.z < .2:
            col = mix(col, lime, _smooth(-.25, -.6, n_.y))
        if p.z >= .15 and p.y < lip_y(p.z) + .001 and n_.y < .2:
            col = mouth
        return (col[0], col[1], col[2], 0.0)
    s.paint(head, head_col)

    jzs = [.12, .16, .21, .27, .33, .39, .45, .50, .54, .57, .592]
    jbot = [1.433, 1.416, 1.404, 1.397, 1.394, 1.396, 1.402, 1.41, 1.42, 1.432, 1.447]
    jaw_secs = []
    for z, bot in zip(jzs, jbot):
        lp = lip_y(z)
        hw = head_loft.half_width(z, lp + .002)
        hw = hw if hw > 0 else .03
        jaw_secs.append((z, lp - .013, min(hw, .104) if z > .14 else .084, lp + .005, bot))
    jaw_loft = Loft(jaw_secs, pt=3.2, pb=2.0)
    jaw = s.view_bone('fx_jaw', 'head', (0, 1.484, .15))
    lower = jaw_loft.mesh(s, 'Lower jaw', jaw, BLACK, 'skin', n=34, tip=(0, 1.464, .606), tail=(0, 1.462, .112))

    def jaw_col(p, n_, c):
        col = hide_col(p, .45)
        if n_.y < -.3:
            col = mix(col, lime, _smooth(-.3, -.62, n_.y))
            if int((p.z - .1) / .034) % 2 == 0:
                col = mix(col, lime_d, .35 * _smooth(-.5, -.8, n_.y))
        if p.y > lip_y(p.z) - .004 and n_.y > .25:
            col = mouth
        return (col[0], col[1], col[2], 0.0)
    s.paint(lower, jaw_col)

    # mouth: dark interior, glowing gullet, forked tongue on the jaw floor
    s.ellipsoid('Detail mouth interior', (0, 1.462, .33), (.07, .028, .215), 'head', MOUTH, 'skin', n=18, m=9)
    s.ellipsoid('Detail gullet sludge', (0, 1.47, .235), (.052, .02, .075), 'head', SLUDGE, 'jelly', glow=.9, n=14, m=7)
    s.tube('Detail tongue', [(0, lip_y(z), z) for z in (.2, .27, .34, .41, .46)], [.012, .013, .012, .009, .006], jaw, TONGUE, 'skin', n=8)
    for sd in (-1, 1):
        s.tube('Detail tongue fork %d' % sd, [(0, lip_y(.46), .46), (sd * .009, lip_y(.5) + .002, .495), (sd * .016, lip_y(.52) + .004, .52)], [.006, .004, .001], jaw, TONGUE, 'skin', n=6)

    # gum line + teeth: the permanent toothy moray grin, corners curling up (the left one higher: smug)
    for sd, side in ((1, 'l'), (-1, 'r')):
        pts = []
        for z in [.594, .576, .55, .52, .48, .43, .38, .33, .28, .23, .19, .165]:
            hw = head_loft.half_width(z, lip_y(z) + .002)
            pts.append((sd * (max(hw, .004) + .0015) if z < .59 else 0.0, lip_y(z), z))
        curl = .03 if sd > 0 else .017
        y0 = lip_y(.15)
        cx = head_loft.half_width(.14, y0 + curl * .6) - .002
        pts += [(sd * (cx + .002), y0 + curl * .3, .15), (sd * cx, y0 + curl * .75, .137), (sd * (cx - .006), y0 + curl, .127)]
        s.tube('Detail gum line %s' % side, pts, [.0064] * (len(pts) - 2) + [.0052, .0035], 'head', GUM, 'skin', n=8)
        for q, z in enumerate([.215, .262, .31, .358, .405, .45]):
            hw = head_loft.half_width(z, lip_y(z) + .002)
            x = sd * (hw + .0035); y = lip_y(z) + .003
            L = .021 if q < 5 else .025
            s.tube('Detail tooth up %s %d' % (side, q), [(x, y, z), (x + sd * .002, y - L * .55, z - .002), (x + sd * .001, y - L, z - .006)], [.0062, .0046, .0006], 'head', TOOTH, 'shell', n=6)
        # the big front fangs hang outside the lower lip
        z = .505; hw = head_loft.half_width(z, lip_y(z) + .002)
        fx_, fy = sd * (hw + .004), lip_y(z) + .005
        s.tube('Detail fang %s' % side, [(fx_, fy, z), (fx_ + sd * .003, fy - .023, z - .002), (fx_ + sd * .0015, fy - .043, z - .01)], [.009, .0066, .0008], 'head', TOOTH, 'shell', n=8)
        drip(s, 'Detail drip fang %s' % side, (fx_ + sd * .0015, fy - .041, z - .01), .018, 'head', bulb=.0048, neck=.0022, n=6)
        # lower teeth stand outside the upper lip, between the upper ones
        for q, z in enumerate([.238, .286, .334, .382, .43, .53]):
            hw = head_loft.half_width(z, lip_y(z) + .011)
            x = sd * (max(hw, .01) + .004); y = lip_y(z) - .004
            L = .019 if q < 5 else .026
            r0 = .0056 if q < 5 else .007
            s.tube('Detail tooth low %s %d' % (side, q), [(x, y, z), (x + sd * .0015, y + L * .55, z + .001), (x + sd * .0005, y + L, z + .004)], [r0, r0 * .76, .0006], jaw, TOOTH, 'shell', n=6)

    # sludge hanging from the chin (one on a spring, so it swings)
    db = s.view_bone('fx_spring_drip_jaw_0', jaw, (.022, 1.402, .48))
    drip(s, 'Detail drip chin', (.022, 1.402, .48), .058, db, bulb=.0115, neck=.005)
    drip(s, 'Detail drip chin small', (-.03, 1.398, .43), .03, jaw, bulb=.007, neck=.0035, n=8)

    # tube nostrils at the snout tip (a moray tell)
    for sd in (-1, 1):
        z0 = .55; y0 = head_loft.params(z0)[2] - .006
        s.tube('Detail nostril tube %d' % sd, [(sd * .022, y0, z0), (sd * .026, y0 + .012, z0 + .016), (sd * .029, y0 + .02, z0 + .028)], [.0085, .0078, .0072], 'head', BLACK, 'shell', n=8)
        s.ellipsoid('Detail nostril hole %d' % sd, (sd * .029, y0 + .021, z0 + .029), (.0052, .0052, .004), 'head', '1E0E16', 'skin', n=8, m=4)

    # ---- eyes: magenta, slit pupils, slanted heavy lid folds over rigged lids (rig_eye), cocked brows ----
    eye_w, eye_h, eye_d = .043, .041, .02
    for sd, side in ((1, 'l'), (-1, 'r')):
        ex, ey = sd * .072, 1.622
        ez = head_loft.front_z(ex, ey) - .007
        s.rig_eye('Eye ' + side, (ex, ey, ez), (eye_w, eye_h, eye_d), 'head', side, iris=MAGENTA, lid_color='343B39')
        pupil = _obj(s, 'Eye %s pupil' % side)
        cx = ex - eye_w * .06
        for vv in pupil.data.vertices:
            vv.co.x = cx + (vv.co.x - cx) * .42
        # the sly shape: a fixed fold of skin over the top of the eye, a touch lower toward the nose; the
        # rigged lid blinks under it (it sits a little behind the fold) and covers the rest of the eye
        s.ellipsoid('Detail lid fold ' + side, (ex, ey + eye_h * .74, ez + eye_d * .8), (eye_w * 1.14, eye_h * .46, eye_d * 1.62), 'head', BLACK, 'shell', n=14, m=6)
        al = math.radians(7) * sd
        be = math.radians(20) * sd               # the eyes turn a little outward, as on a moray's narrow head
        for o in s.collection.objects:
            if not (o.name.startswith('Eye %s ' % side) or o.name in ('Detail lid Eye ' + side, 'Detail lid fold ' + side)):
                continue
            for vv in o.data.vertices:
                fx_, fy, fz = vv.co.x - ex, vv.co.z - ey, -vv.co.y - ez
                if o.name.startswith('Detail lid fold'):
                    fx_, fy = fx_ * math.cos(al) - fy * math.sin(al), fx_ * math.sin(al) + fy * math.cos(al)
                fx_, fz = fx_ * math.cos(be) + fz * math.sin(be), -fx_ * math.sin(be) + fz * math.cos(be)
                vv.co.x, vv.co.z, vv.co.y = ex + fx_, ey + fy, -(ez + fz)
            o.data.update()
        # brows ride over the top of the eye bulge: the left one low and level (smug), the right one cocked
        if sd > 0:
            bxy = [(-.034, eye_h * 1.12), (.0, eye_h * 1.3), (.036, eye_h * 1.26)]
        else:
            bxy = [(-.034, eye_h * 1.22), (.0, eye_h * 1.62), (.036, eye_h * 1.42)]
        bp = []
        for dx, dy in bxy:
            x = ex + sd * dx
            z = ez + eye_d * 1.35 - abs(dx) * .3 - sd * dx * math.sin(be) * .9
            bp.append((x + sd * .004, ey + dy, max(z, head_loft.front_z(x, ey + dy) + .003)))
        brow = s.view_bone('fx_brow_' + side, 'head', bp[1])
        s.tube('Detail sly brow ' + side, bp, [.009, .0135, .0065], brow, '93CF3C', 'skin', n=8)

    # ---- crown fin over the skull and down the nape (three springs) ----
    def back_z(y):
        z = .05
        while z < .25 and head_loft.half_width(z, y) < .004:
            z += .002
        return z
    path = [(head_loft.params(z)[2], z) for z in [.27 - .2 * q / 13 for q in range(14)]]
    path += [(y, back_z(y)) for y in [1.652 - .14 * q / 7 for q in range(1, 8)]]
    for part_name, lo, hi, hmax in (('crown', 0, 8, .068), ('crest', 7, 15, .078), ('nape', 14, len(path), .058)):
        base, outs, hs = [], [], []
        cnt = hi - lo
        for q in range(lo, hi):
            y, z = path[q]
            y0, z0 = path[max(0, q - 1)]; y1, z1 = path[min(len(path) - 1, q + 1)]
            tan = Vector((0, y1 - y0, z1 - z0)).normalized()
            nrm = Vector((0, -tan.z, tan.y))
            if nrm.dot(Vector((0, y - 1.55, z - .15))) < 0:
                nrm = -nrm
            base.append(Vector((0, y, z)) - nrm * .009)
            outs.append((nrm + tan * .5 + Vector((.3 * math.sin(TAU * q / 8.0), 0, 0))).normalized())
            f = (q - lo) / (cnt - 1)
            hs.append(hmax * math.sin(math.pi * (.07 + .86 * f)) ** .55 * (1.0 if q % 4 == 2 else .84))
        b = s.view_bone('fx_spring_%s_0' % part_name, 'head', tuple(base[cnt // 2]))
        membrane(s, 'Fin %s' % part_name, base, outs, hs, b, {q - lo for q in range(lo, hi) if q % 4 == 2}, width=.0075, m=7, edge_glow=.45)

    # ---- webbed gill frills flaring from behind the jaw (springs) ----
    for sd, side in ((1, 'l'), (-1, 'r')):
        base, outs, hs = [], [], []
        fz = .1
        for q in range(13):
            f = q / 12
            y = 1.462 + .14 * f
            x = head_loft.half_width(fz, y)
            x = (x if x > 0 else .1) - .008
            base.append(Vector((sd * x, y, fz - .01 * f)))
            ang = math.radians(-50 + 110 * f)
            outs.append(Vector((sd * math.cos(ang) * .75, math.sin(ang) * .7, -.75)).normalized())
            env = math.sin(math.pi * (.07 + .86 * f)) ** .5
            hs.append(.068 * env * (1.0 if q % 3 == 1 else .76))
        fb = s.view_bone('fx_spring_frill_%s_0' % side, 'head', (sd * .112, 1.53, fz))
        membrane(s, 'Fin frill %s' % side, base, outs, hs, fb, {q for q in range(13) if q % 3 == 1}, width=.0065, m=7, edge_glow=.4,
                 cols=('6E2452', CREST, CREST_HI, '8A2C66'))      # gill frills: blood-dark roots and rays
