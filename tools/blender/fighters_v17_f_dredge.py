"""Dredge, "the Dock Crab" (Brine): the v0.9.17 roster art (docs/ART_REVAMP.md "v0.9.17").

A weary, armoured, rust-red dock crab on the locked body (segment bones and pivots come from the
creature JSON; nothing here changes them):
  * carapace: a lacquered ('shell') dome ray-cast from inside the shell's two collision capsules,
    smoothed round their cross-shaped union and clamped to stay 1-4.6 cm outside it. Its lobes become
    crab regions split by dark grooves along the capsules' creases (the "H"): mottled rust, darker
    middle plates, worn light plate edges and a worn margin above a thick rim that rises over the
    mouth; serrated front-lateral teeth and a knobbed back rim. Under it a belly tucked in a little,
    rust under the rim and cream underneath, an orange-rust face with a peach muzzle
  * barnacle clusters of mixed sizes; a bud of glowing cirri pokes out of each crater (vertex alpha:
    the Hype feature, glow mode 'pulse')
  * a huge molar-toothed crusher (right) with a mooring chain draped over the wrist whose loose end
    swings (fx_spring_chain_0..3, each link a child of the previous); a slim sharp-edged cutter
    (left); dark finger tips; open pincer gaps; both claws stay inside their hit volumes
  * stalk eyes (rig_eye: iris/pupil on fx_eye_*, closed lids on fx_lid_*) with heavy weary lids,
    worn brows on fx_brow_*, a small frowning mouth whose mandible plate drops on fx_jaw (hinge deep
    behind the mouth, on the shell: Dredge's mouth is on his body, under the eye stalks)
  * segmented walking legs: broad merus, knobbly knee, propodus, dark dactyl tips, pale joint bands
  * ruffled sea lettuce caught on the back rim, swinging on fx_spring_weed<k>_0..1
Limbs, claws and eye cups use the soft 'skin' sheen: lacquer on small rounded parts mirrors the
arena's ring of spotlights as rows of white dots at gameplay distance.
Every coordinate is fighter rest space (+Z forward, +Y up, +X = Dredge's left), metres.
"""
import math
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from fighters_v17 import mix, lin, cell_spots, _hash

V = Vector
UP = Vector((0.0, 1.0, 0.0))

# palette (sRGB hex). Creature palette: primary 8C3B2B, belly E8D9B8, tips 2E2A28, chain 7A7F85,
# accent (barnacle glow) 2E9BE0.
RUST = '8C3B2B'; RUST_TOP = 'A04A33'; RUST_DARK = '6A281D'; RUST_DEEP = '4C1C15'; RUST_LIGHT = 'B95D3E'
WORN = 'D49C72'; SEAM = '30120D'
CREAM = 'E8D9B8'; CREAM_DK = 'C9AE88'; PEACH = 'E2BE9A'; MEMBRANE = 'D9B49B'
TIP = '2E2A28'; MOUTH = '2A1316'
BARN = 'B9B09C'; BARN_DK = '676253'; BARN_TOP = 'D8D2C2'; GLOW = '1F8FE8'; GLOW_HI = '66D6FF'
WEED = '2F561C'; WEED_MID = '4E8C2A'; WEED_TIP = 'A6D05A'
CHAIN = '7A7F85'; CHAIN_RUST = '8F5532'
IRIS = '7DB8C6'; LID = 'A2482F'; BROW = '5C2319'; STALK = 'DCC3A2'


def sstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def C(h, glow=0.0):
    return lin(h, glow)


def keep(rgb, c):
    return (rgb[0], rgb[1], rgb[2], c[3])


# ---- geometry helpers (fighter space) -----------------------------------------------------------
def etube(s, name, pts, radii, bone, color, mat='skin', glow=0, n=12, up=UP, soft=False, role='body', cap=True):
    """A tube with an explicit frame: radii are (across `up` x path, along `up`) so flat parts (legs,
    blades, ribbons) keep their orientation. Fan caps at both ends."""
    pts = [V(p) for p in pts]
    upv = V(up)
    verts = []
    for j, p in enumerate(pts):
        t = (pts[min(j + 1, len(pts) - 1)] - pts[max(j - 1, 0)]).normalized()
        side = upv.cross(t)
        if side.length < 1e-6:
            side = V((1, 0, 0)).cross(t)
        side.normalize()
        u = t.cross(side).normalized()
        rr = radii[j]
        rs, ru = rr if isinstance(rr, (tuple, list)) else (rr, rr)
        for i in range(n):
            a = math.tau * i / n
            verts.append(tuple(p + side * (math.cos(a) * rs) + u * (math.sin(a) * ru)))
    faces = []
    for j in range(len(pts) - 1):
        for i in range(n):
            a = j * n + i; b = j * n + (i + 1) % n
            faces.append((a, b, b + n, a + n))
    if cap:
        b0 = len(verts); verts.append(tuple(pts[0]))
        b1 = len(verts); verts.append(tuple(pts[-1]))
        last = (len(pts) - 1) * n
        for i in range(n):
            faces.append((b0, (i + 1) % n, i))
            faces.append((b1, last + i, last + (i + 1) % n))
    return s.mesh(name, verts, faces, bone, color, mat, glow, soft, role)


def revolve(s, name, base, axis, profile, bone, color, mat='skin', glow=0, n=12, wobble=None):
    """Rings round `axis` at base + axis*h with radius r for each (h, r): barnacles, glow domes."""
    base = V(base); axis = V(axis).normalized()
    ref = V((1, 0, 0)) if abs(axis.x) < .9 else V((0, 0, 1))
    e1 = (ref - axis * ref.dot(axis)).normalized(); e2 = axis.cross(e1)
    verts = []
    for h, r in profile:
        for i in range(n):
            a = math.tau * i / n
            rr = r * (wobble(a) if wobble else 1.0)
            verts.append(tuple(base + axis * h + e1 * (math.cos(a) * rr) + e2 * (math.sin(a) * rr)))
    faces = []
    for j in range(len(profile) - 1):
        for i in range(n):
            a = j * n + i; b = j * n + (i + 1) % n
            faces.append((a, b, b + n, a + n))
    b0 = len(verts); verts.append(tuple(base + axis * profile[0][0]))
    b1 = len(verts); verts.append(tuple(base + axis * profile[-1][0]))
    last = (len(profile) - 1) * n
    for i in range(n):
        faces.append((b0, (i + 1) % n, i))
        faces.append((b1, last + i, last + (i + 1) % n))
    return s.mesh(name, verts, faces, bone, color, mat, glow, False, 'body')


def ring_axis(s, name, c, axis, R, thick, bone, color, mat='skin', n=24, sides=6, glow=0):
    """A closed ring of radius R round an arbitrary axis (collars, joint bands)."""
    axis = V(axis).normalized()
    ref = V((1, 0, 0)) if abs(axis.x) < .9 else V((0, 0, 1))
    e1 = (ref - axis * ref.dot(axis)).normalized(); e2 = axis.cross(e1)
    pts = [tuple(V(c) + e1 * (R * math.cos(math.tau * i / n)) + e2 * (R * math.sin(math.tau * i / n))) for i in range(n)]
    return s.tube(name, pts, thick, bone, color, mat, glow, n=sides, closed=True)


def chain_link(s, name, c, along, across, L, W, wire, bone, m=10):
    """One oval chain link (outer size L x W) in the plane of `along` and `across`."""
    along = V(along).normalized(); across = V(across)
    across = (across - along * along.dot(across)).normalized()
    a, b = L / 2 - wire, W / 2 - wire
    pts = [tuple(V(c) + along * (a * math.cos(math.tau * k / m)) + across * (b * math.sin(math.tau * k / m))) for k in range(m)]
    obj = s.tube(name, pts, wire, bone, CHAIN, 'metal', n=6, closed=True)
    s.paint(obj, chain_paint)
    return obj


# ---- paint ----------------------------------------------------------------------------------------
def chain_paint(p, n, c):
    rgb = mix(C('5A5E64'), C(CHAIN), sstep(-.5, .6, n.y))
    sp = cell_spots(p, .03, .55, .5, 91)
    if sp > .15:
        rgb = mix(rgb, C(CHAIN_RUST), .35 + .4 * sp)
    return keep(rgb, c)


def limb_paint(top, seed, base=RUST, under=CREAM):
    """Rust on the top/outer side, cream underneath, dark-red mottles and worn light flecks."""
    top = V(top).normalized()

    def fn(p, n, c):
        t = n.dot(top)
        rgb = mix(C(under), C(base), sstep(-.62, .05, t))
        sp = cell_spots(p, .07, .62, .55, seed)
        if sp > .05 and t > -.3:
            rgb = mix(rgb, C(RUST_DEEP), .4 + .35 * min(1.0, sp * 2))
        pit = cell_spots(p, .03, .45, .4, seed + 7)
        if pit > .3 and t > .2:
            rgb = mix(rgb, C(RUST_DARK), .35)
        return keep(rgb, c)
    return fn


def tipped(fn, origin, axis, s0, s1, tip=TIP):
    """Darken toward the end of a finger/leg: 0 at s0 along `axis` from `origin`, full at s1."""
    origin = V(origin); axis = V(axis).normalized()

    def g(p, n, c):
        rgb = fn(p, n, c)
        return keep(mix(rgb, C(tip), sstep(s0, s1, (p - origin).dot(axis))), c)
    return g


# ---- the carapace ---------------------------------------------------------------------------------
C0 = V((0.0, .57, 0.0))     # inside both shell capsules: the union is star-shaped from here
NT = 112                     # columns round the shell
KD = 22                      # dome rings (rim -> crown)
KB = 10                      # belly rings (rim -> underside)


def _sd_shape(p, sh):
    if sh['type'] == 'capsule':
        a = V(sh['a']); ab = V(sh['b']) - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
        return (p - a - ab * t).length - sh['radius']
    return (p - V(sh['center'])).length - sh['radius']


def _exit(c, d, sh):
    lo, hi = 0.0, 1.6
    for _ in range(30):
        mid = (lo + hi) * .5
        if _sd_shape(c + d * mid, sh) < 0:
            lo = mid
        else:
            hi = mid
    return lo


def _dir(th, ph):
    """th: 0 = forward (+Z), +90 deg = Dredge's left (+X); ph: elevation."""
    return V((math.cos(ph) * math.sin(th), math.sin(ph), math.cos(ph) * math.cos(th)))


def _wrap(th):
    return (th + math.pi) % math.tau - math.pi


def phi_rim(th):
    """The rim's elevation: raised over the mouth at the front, level round the sides and back."""
    a = abs(_wrap(th)); lim = math.radians(78)
    base = math.radians(-3)
    if a >= lim:
        return base
    return base + math.radians(19) * math.cos(a / lim * math.pi / 2) ** 2


def _gauss_ring(vals, sig):
    n = len(vals); R = int(math.ceil(sig * 3))
    ws = [math.exp(-(j * j) / (2 * sig * sig)) for j in range(-R, R + 1)]
    tot = sum(ws)
    return [sum(ws[j + R] * vals[(i + j) % n] for j in range(-R, R + 1)) / tot for i in range(n)]


def _gauss_cols(grid, sig):
    K = len(grid); n = len(grid[0]); R = int(math.ceil(sig * 3))
    out = [[0.0] * n for _ in range(K)]
    for k in range(K):
        for i in range(n):
            acc = tot = 0.0
            for j in range(-R, R + 1):
                kk = min(K - 1, max(0, k + j)); w = math.exp(-(j * j) / (2 * sig * sig))
                acc += w * grid[kk][i]; tot += w
            out[k][i] = acc / tot
    return out


def _grooves():
    """The carapace grooves seen from above (x, z). They follow the creases where the shell's two
    capsules meet, so the envelope's lobes become crab regions: the gastric U at the front (the
    cervical groove), the cardiac U at the back, and two branchial grooves along the sides of the
    middle column (the crab "H"); a short frontal groove runs between the eye stalks."""
    xs = [i * .031 - .31 for i in range(21)]
    gastric = [(x, .175 + .165 * (abs(x) / .31) ** 2) for x in xs]
    cardiac = [(x * .3 / .31, -(.165 + .175 * (abs(x) / .31) ** 2)) for x in xs]
    zs = [-.34 + .0425 * i for i in range(17)]
    left = [(.305 + .012 * (1 - (z / .34) ** 2), z) for z in zs]
    right = [(-x, z) for x, z in left]
    front = [(0.0, .42 + .04 * i) for i in range(5)]
    return [gastric, cardiac, left, right, front]


GROOVES = _grooves()


def middle_column(x, z):
    """1 on the middle plates (gastric, mesogastric, cardiac) between the branchial grooves."""
    return 1 - sstep(.27, .33, abs(x))


def groove_dist(x, z):
    best = 9.0
    for line in GROOVES:
        for (ax, az), (bx, bz) in zip(line, line[1:]):
            dx, dz = bx - ax, bz - az
            t = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz)))
            ex, ez = ax + dx * t - x, az + dz * t - z
            best = min(best, ex * ex + ez * ez)
    return math.sqrt(best)


def dome_paint(p, n, c):
    rgb = C(RUST)
    rgb = mix(rgb, C(RUST_TOP), .5 * sstep(.76, .9, p.y))              # sun-faded crown
    mid = middle_column(p.x, p.z) * sstep(.62, .74, p.y)
    rgb = mix(rgb, C('6E261B'), .5 * mid)                              # the middle plates are darker
    big = cell_spots(p, .14, .72, .62, 41)
    if big > .03:
        rgb = mix(rgb, C(RUST_DEEP), .45 + .35 * min(1.0, big * 2.0))  # dark-red mottling
    med = cell_spots(p, .075, .6, .5, 43)
    if med > .1:
        rgb = mix(rgb, C(RUST_DARK), .5)
    sm = cell_spots(p, .035, .45, .45, 17)
    if sm > .3:
        rgb = mix(rgb, C(RUST_DEEP), .3)                               # pitting
    g = groove_dist(p.x, p.z)
    top = sstep(.62, .70, p.y)
    rgb = mix(rgb, C(WORN), .32 * top * sstep(.02, .045, g) * (1 - sstep(.055, .1, g)))    # worn plate edges
    rgb = mix(rgb, C(SEAM), .75 * top * (1 - sstep(.015, .045, g)))
    # the carapace margin just above the rim: worn lighter, then a dark wet line under the crown
    q = p - C0
    th = math.atan2(q.x, q.z)
    above = math.degrees(math.atan2(q.y, math.hypot(q.x, q.z)) - phi_rim(th))
    rgb = mix(rgb, C('C26A45'), .75 * (1 - sstep(3.0, 7.5, above)))
    rgb = mix(rgb, C(RUST_DARK), .45 * sstep(6.0, 9.0, above) * (1 - sstep(10.0, 16.0, above)))
    return keep(rgb, c)


def belly_paint(p, n, c):
    # under the rim: wet rust fading to orange down the sides; facing down: the cream belly
    rgb = mix(C(RUST_DARK), C('B9603E'), sstep(.3, -.1, n.y))
    rgb = mix(rgb, C('D59A72'), sstep(-.15, -.4, n.y))
    rgb = mix(rgb, C(CREAM), sstep(-.35, -.7, n.y))
    # the face: orange-rust under the front rim with a small peach muzzle round the mouth
    face = sstep(.3, .7, n.z) * sstep(.48, .58, p.y)
    rgb = mix(rgb, C('B65A39'), .7 * face)
    muzzle = (1 - sstep(.055, .1, math.hypot(p.x / 1.35, p.y - .645))) * sstep(.3, .6, n.z)
    rgb = mix(rgb, C(PEACH), muzzle)
    return keep(rgb, c)


def rim_paint(p, n, c):
    rgb = mix(C(RUST_DARK), C(RUST_LIGHT), sstep(-.4, .5, n.y))
    rgb = mix(rgb, C(WORN), .5 * sstep(.55, .95, n.y))
    sp = cell_spots(p, .05, .5, .45, 77)
    if sp > .2:
        rgb = mix(rgb, C(RUST_DEEP), .4)
    return keep(rgb, c)


class Carapace:
    def __init__(self, s):
        shapes = s.segments['shell']['shapes']

        def renv(d):
            return max(_exit(C0, d, sh) for sh in shapes)
        ths = [math.tau * i / NT for i in range(NT)]
        prs = [phi_rim(t) for t in ths]
        # ---- dome: rim (k = 0) to crown ----
        dph = [[prs[i] + (math.pi / 2 - prs[i]) * (k / KD) for i in range(NT)] for k in range(KD)]
        R0 = [[renv(_dir(ths[i], dph[k][i])) for i in range(NT)] for k in range(KD)]
        Rs = _gauss_cols([_gauss_ring(row, 3.0) for row in R0], 1.0)
        dome = []
        for k in range(KD):
            hi = .032 + .014 * sstep(0, 4, k) - .016 * sstep(8, KD - 1, k)
            # shoulders pushed out a little: a flatter crown and steeper flanks read as armour
            lo = .012 + .018 * math.sin(math.pi * min(1.0, k / (KD * .8))) ** .8
            for i in range(NT):
                d = _dir(ths[i], dph[k][i])
                r = min(max(Rs[k][i], R0[k][i] + lo), R0[k][i] + hi)
                p = C0 + d * r
                g = groove_dist(p.x, p.z)
                p = p - d * (.01 * (1 - sstep(0.0, .075, g)) * sstep(.62, .70, p.y))
                dome.append(p)
        dome.append(C0 + UP * (renv(UP) + .012))
        dfaces = []
        for k in range(KD - 1):
            for i in range(NT):
                a = k * NT + i; b = k * NT + (i + 1) % NT
                dfaces.append((a, b, b + NT, a + NT))
        top = KD * NT
        for i in range(NT):
            dfaces.append(((KD - 1) * NT + i, (KD - 1) * NT + (i + 1) % NT, top))
        # ---- belly and face: rim down to the underside, tucked in under the rim (not the face) ----
        # rings packed toward the rim: the contact shadow under the overhang ramps over several rings
        bph = [[prs[i] - (prs[i] + math.pi / 2) * (k / KB) ** 1.6 for i in range(NT)] for k in range(KB)]
        B0 = [[renv(_dir(ths[i], bph[k][i])) for i in range(NT)] for k in range(KB)]
        Bs = _gauss_cols([_gauss_ring(row, 3.0) for row in B0], 1.0)
        belly = []
        for k in range(KB):
            for i in range(NT):
                if k == 0:
                    belly.append(dome[i].copy())
                    continue
                th = ths[i]; ph = bph[k][i]; d = _dir(th, ph)
                delta = prs[i] - ph
                pad = .012 - .02 * sstep(0, math.radians(24), delta) + .006 * sstep(math.radians(30), math.radians(85), delta)
                face = (1 - sstep(math.radians(26), math.radians(46), abs(_wrap(th)))) * (1 - sstep(math.radians(30), math.radians(55), delta))
                pad = pad * (1 - face) + .005 * face
                r = min(max(Bs[k][i] + pad, B0[k][i] + pad - .004), B0[k][i] + pad + .03)
                belly.append(C0 + d * r)
        belly.append(C0 - UP * (renv(-UP) - .004))
        bfaces = []
        for k in range(KB - 1):
            for i in range(NT):
                a = k * NT + i; b = k * NT + (i + 1) % NT
                bfaces.append((a, a + NT, b + NT, b))
        bot = KB * NT
        for i in range(NT):
            bfaces.append(((KB - 1) * NT + (i + 1) % NT, (KB - 1) * NT + i, bot))
        self.dome, self.belly, self.ths, self.prs = dome, belly, ths, prs
        self.dome_obj = s.mesh('Carapace - lacquered dome', [tuple(p) for p in dome], dfaces, 'shell', RUST, 'shell')
        s.paint(self.dome_obj, dome_paint)
        self.belly_obj = s.mesh('Carapace - belly and face', [tuple(p) for p in belly], bfaces, 'shell', CREAM, 'skin')
        s.paint(self.belly_obj, belly_paint)
        nd = len(dome)
        self.bvh = BVHTree.FromPolygons([tuple(p) for p in dome + belly], dfaces + [tuple(x + nd for x in f) for f in bfaces])

    def rim_at(self, th):
        f = (th % math.tau) / math.tau * NT
        i0 = int(math.floor(f)) % NT; i1 = (i0 + 1) % NT; t = f - math.floor(f)
        return self.dome[i0].lerp(self.dome[i1], t)

    def out_at(self, th):
        """Horizontal outward normal of the rim seen from above."""
        tan = self.rim_at(th + .01) - self.rim_at(th - .01)
        tan.y = 0
        out = tan.normalized().cross(UP).normalized()
        p = self.rim_at(th)
        if out.dot(V((p.x, 0, p.z))) < 0:
            out = -out
        return out

    def down(self, x, z):
        """The shell surface straight below (x, z) seen from above: (point, outward normal) or None."""
        hit = self.bvh.ray_cast(V((x, 1.8, z)), V((0, -1, 0)), 3.0)
        if hit[0] is None:
            return None
        nrm = hit[1] if hit[1].y > 0 else -hit[1]
        return hit[0], nrm

    def radial(self, th, ph):
        d = _dir(th, ph)
        hit = self.bvh.ray_cast(C0, d, 3.0)
        if hit[0] is None:
            return None
        nrm = hit[1] if hit[1].dot(d) > 0 else -hit[1]
        return hit[0], nrm


# ---- barnacles (Hype feature) ---------------------------------------------------------------------
CLUSTERS = [  # top-view centre (x, z) and barnacles (dx, dz, base radius): tight, crusty clumps
    (-.50, -.08, [(0, 0, .036), (.05, .034, .026), (-.044, .044, .022), (.026, -.058, .03), (-.058, -.024, .018)]),
    (.50, -.20, [(0, 0, .034), (.048, .026, .022), (-.034, .046, .018), (-.016, -.05, .016)]),
    (.08, -.43, [(0, 0, .028), (-.044, .018, .02), (.04, .03, .016)]),
    (.47, .13, [(0, 0, .028), (.04, -.038, .018), (-.034, .036, .015)]),
    (-.16, .39, [(0, 0, .022), (-.034, .03, .015)]),
]


def barnacle(s, name, base, nrm, R, bone):
    """An acorn barnacle: chalky wall plates round a crater; a bud of glowing cirri pokes out of it
    (vertex alpha: the Hype feature)."""
    base = V(base)
    ax = (V(nrm).normalized() * .72 + UP * .28).normalized()
    H = R * .78
    seed = _hash(int(base.x * 1000), int(base.z * 1000), int(R * 1000)) * 6
    prof = [(-.006, R * 1.02), (H * .35, R * .9), (H * .75, R * .74), (H, R * .64), (H, R * .58), (H * .85, R * .54), (H * .7, R * .52)]
    wall = revolve(s, 'Barnacle ' + name, base, ax, prof, bone, BARN, 'skin', n=10, wobble=lambda a: 1 + .09 * math.cos(6 * a + seed))

    def wall_paint(p, n, c):
        t = (p - base).dot(ax) / H
        rgb = mix(C(BARN_DK), C(BARN), sstep(.05, .55, t))
        rgb = mix(rgb, C(BARN_TOP), sstep(.85, 1.0, t))
        return keep(rgb, c)
    s.paint(wall, wall_paint)
    glow = revolve(s, 'Detail barnacle glow ' + name, base, ax, [(H * .68, R * .5), (H * .98, R * .56), (H * 1.18, R * .44), (H * 1.3, R * .2), (H * 1.33, R * .02)],
                   bone, GLOW, 'jelly', glow=1.0, n=8)

    def glow_paint(p, n, c):
        t = (p - base).dot(ax) / H
        rgb = mix(C(GLOW), C(GLOW_HI), sstep(1.05, 1.3, t))
        return (rgb[0], rgb[1], rgb[2], 1.0)
    s.paint(glow, glow_paint)


def claw_frame(sh, outward):
    """Claw frame from its capsule: u along the claw, v up (the pincer opens along v), w outward."""
    A = V(sh['a']); B = V(sh['b'])
    u = (B - A).normalized()
    v = (UP - u * u.dot(UP)).normalized()
    w = u.cross(v)
    if w.x * outward < 0:
        w = -w
    return A, u, v, w


def _lerp_path(path, radii, s_):
    """Linear interpolation of a finger path [(s, a, b)] and its radii [(rw, rv)] at s_."""
    for j in range(len(path) - 1):
        if path[j][0] <= s_ <= path[j + 1][0]:
            t = (s_ - path[j][0]) / (path[j + 1][0] - path[j][0])
            a = path[j][1] * (1 - t) + path[j + 1][1] * t
            b = path[j][2] * (1 - t) + path[j + 1][2] * t
            rv = radii[j][1] * (1 - t) + radii[j + 1][1] * t
            return a, b, rv
    return path[-1][1], path[-1][2], radii[-1][1]


# ---------------------------------------------------------------------------------------------------
def build(s):
    car = Carapace(s)

    # ---- the worn rim: a thick lip round the shell, serrated front-lateral teeth, knobbed back ----
    rim_pts = []
    for i in range(0, NT, 2):
        th = car.ths[i]
        rim_pts.append(tuple(car.dome[i] + car.out_at(th) * .004 - UP * .002))
    rim = s.tube('Shell rim - worn edge', rim_pts, .021, 'shell', RUST_LIGHT, 'shell', n=8, closed=True)
    s.paint(rim, rim_paint)
    for side, sfx in ((1, 'l'), (-1, 'r')):
        for j, deg in enumerate([24, 36, 48, 60, 72]):
            th = math.radians(deg) * side
            p = car.rim_at(th); out = car.out_at(th)
            L = .036 if j in (1, 2, 3) else .028
            tooth = etube(s, 'Rim tooth %s%d' % (sfx, j), [p + out * .003, p + out * (L * .55) + UP * .005, p + out * L + UP * .01],
                          [(.026, .014), (.016, .01), (.002, .002)], 'shell', RUST_LIGHT, 'shell', n=8)
            s.paint(tooth, lambda q, n, c, p=p, L=L: keep(mix(C(RUST_LIGHT), C(WORN), sstep(.2, .9, (q - p).length / L)), c))
        for j, deg in enumerate([98, 116, 134, 152, 170]):
            th = math.radians(deg) * side
            p = car.rim_at(th); out = car.out_at(th)
            knob = s.ellipsoid('Rim knob %s%d' % (sfx, j), tuple(p + out * .013 + UP * .005), (.019, .014, .019), 'shell', RUST_LIGHT, 'skin', n=8, m=5)
            s.paint(knob, rim_paint)
        # frontal lobes between the eye stalks
        th = math.radians(6) * side
        p = car.rim_at(th); out = car.out_at(th)
        etube(s, 'Rim tooth front %s' % sfx, [p + out * .002, p + out * .014 - UP * .003, p + out * .024 - UP * .007],
              [(.016, .01), (.011, .008), (.002, .002)], 'shell', WORN, 'shell', n=8)

    # ---- grooves: dark seams sunk into the dome (the crab "H" and the frontal groove) ----
    for gi, line in enumerate(GROOVES):
        pts = []
        for (ax_, az), (bx, bz) in zip(line, line[1:]):
            segs = max(1, int(math.hypot(bx - ax_, bz - az) / .02))
            for q in range(segs):
                t = q / segs
                pts.append((ax_ + (bx - ax_) * t, az + (bz - az) * t))
        pts.append(line[-1])
        runs, run = [], []
        for x, z in pts:
            hit = car.down(x, z)
            if hit is None or hit[1].y < .45:
                if len(run) >= 3:
                    runs.append(run)
                run = []
                continue
            run.append(hit[0] + hit[1] * .0015)
        if len(run) >= 3:
            runs.append(run)
        for ri, run in enumerate(runs):
            etube(s, 'Detail seam %d %d' % (gi, ri), run, [(.0095, .005)] * len(run), 'shell', SEAM, 'skin', n=6)

    # ---- face: a small frowning mouth under the rim, a mandible plate that drops on fx_jaw ----
    s.ellipsoid('Detail face mound', (0, .648, .566), (.11, .062, .045), 'shell', PEACH, 'skin', n=20, m=10)
    s.ellipsoid('Detail mouth', (0, .655, .592), (.06, .022, .022), 'shell', MOUTH, 'skin', n=16, m=8)
    etube(s, 'Detail upper lip', [(-.07, .641, .594), (-.046, .66, .608), (0, .671, .613), (.046, .66, .608), (.07, .641, .594)],
          [.008, .011, .012, .011, .008], 'shell', RUST_LIGHT, 'shell', n=8)
    jaw = s.view_bone('fx_jaw', 'shell', (0, .632, .50))
    plate = s.ellipsoid('Detail jaw plate', (0, .632, .600), (.058, .02, .02), jaw, CREAM, 'shell', n=16, m=8)
    s.paint(plate, lambda p, n, c: keep(mix(C(CREAM), C(CREAM_DK), sstep(.0, -.7, n.y)), c))
    for side in (-1, 1):
        mand = etube(s, 'Detail mandible %d' % side, [(side * .05, .648, .603), (side * .046, .627, .615), (side * .032, .608, .617)],
                     [.010, .007, .002], jaw, CREAM, 'shell', n=8)
        s.paint(mand, lambda p, n, c: keep(mix(C(CREAM), C(TIP), sstep(.63, .608, p.y)), c))
        # little antennules between the stalks
        etube(s, 'Detail antenna %d' % side, [(side * .028, .795, .506), (side * .043, .824, .531), (side * .058, .839, .542)],
              [.006, .004, .0015], 'shell', RUST_LIGHT, 'shell', n=6)

    # ---- eye stalks, rigged eyes with heavy weary lids, worn brows ----
    for side, sfx in ((1, 'l'), (-1, 'r')):
        a = V((side * .10, .84, .40)); b = V((side * .12, 1.06, .42)); ax = (b - a).normalized()
        hit = car.bvh.ray_cast(b, -ax, 1.0)
        base = hit[0] if hit[0] is not None else a
        ring_axis(s, 'Stalk collar ' + sfx, base + ax * .004, ax, .043, .013, 'shell', RUST_LIGHT, 'shell', n=16, sides=6)
        stalk = etube(s, 'Stalk ' + sfx, [base - ax * .03, base + ax * .02, a.lerp(b, .55), b - ax * .035], [.033, .032, .028, .03],
                      'head', STALK, 'skin', n=14, soft=True)
        s.paint(stalk, lambda p, n, c: keep(mix(C(STALK), C('C9A27E'), sstep(.3, -.6, n.y)), c))
        ring_axis(s, 'Detail stalk band ' + sfx, a.lerp(b, .5), ax, .029, .006, 'head', 'B48A68', 'skin', n=12, sides=4)
        cup = s.ellipsoid('Stalk cup ' + sfx, (side * .12, 1.056, .404), (.048, .047, .039), 'head', RUST, 'skin', n=18, m=10)
        s.paint(cup, limb_paint(UP, 31 + side))
        s.rig_eye('Eye ' + sfx, (side * .121, 1.06, .428), (.04, .043, .024), 'head', sfx, iris=IRIS, lid_color=LID)
        brow = s.view_bone('fx_brow_' + sfx, 'head', (side * .121, 1.109, .447))
        etube(s, 'Detail weary brow ' + sfx, [(side * .086, 1.117, .452), (side * .12, 1.112, .457), (side * .155, 1.097, .446)],
              [(.009, .006), (.011, .007), (.006, .004)], brow, BROW, 'shell', n=8)

    # ---- barnacle clusters (glowing openings) on the carapace ----
    for ci, (cx, cz, items) in enumerate(CLUSTERS):
        for bi, (dx, dz, R) in enumerate(items):
            x, z = cx + dx, cz + dz
            if groove_dist(x, z) < R + .008:
                print('dredge: barnacle %d%d skipped (on a groove)' % (ci, bi))
                continue
            hit = car.down(x, z)
            if hit is None:
                continue
            barnacle(s, '%d%d' % (ci, bi), hit[0] - hit[1] * .004, hit[1], R, 'shell')

    # ---- seaweed caught on the rim: lying over the shell, the loose ends swing (springs) ----
    for k, (deg, sc) in enumerate([(150, 1.0), (-160, .9), (-112, .85), (122, .8)]):
        th = math.radians(deg)
        out = car.out_at(th); tan = UP.cross(out).normalized()
        lie = []
        for off in (.16, .09, .035):
            hit = car.radial(th + .025 * off / .16, phi_rim(th) + off)
            if hit is not None:
                lie.append(hit[0] + hit[1] * .005)
        root = car.rim_at(th) + out * .03 - UP * .006
        lie.append(root)
        lr = [(.018 + .012 * j / max(1, len(lie) - 1), .0035) for j in range(len(lie))]
        weed = etube(s, 'Frond weed %d lying' % k, lie, lr, 'shell', WEED, 'skin', n=6, up=out)
        # the loose sheet: broad, ruffled sea lettuce in two swinging pieces
        b0 = s.view_bone('fx_spring_weed%d_0' % k, 'shell', tuple(root))
        L0 = .08 * sc
        p1 = root - UP * L0 + out * .006
        wav = [(0, 0), (.009, .007), (-.002, -.005), (.008, .006), (.006, 0)]
        pa = [root + UP * .004 - UP * (L0 * j / 4) + out * wav[j][0] + tan * wav[j][1] for j in range(5)]
        pa[-1] = p1
        wa = etube(s, 'Frond weed %d a' % k, pa, [(w, .0035) for w in (.03, .036, .029, .034, .028)], b0, WEED_MID, 'jelly', n=6, up=out)
        b1 = s.view_bone('fx_spring_weed%d_1' % k, b0, tuple(p1))
        L1 = .06 * sc
        wav = [(0, 0), (.004, -.008), (.008, .004), (.003, -.005), (.006, .006)]
        pb = [p1 + UP * .004 - UP * (L1 * j / 4) + out * (wav[j][0] - .014 * j / 4) + tan * wav[j][1] for j in range(5)]   # curls in under the shell
        wb = etube(s, 'Frond weed %d b' % k, pb, [(w, .003) for w in (.028, .031, .024, .016, .003)], b1, WEED_TIP, 'jelly', n=6, up=out)
        s.ellipsoid('Frond bladder %d' % k, tuple(root - UP * (L0 * .3) + out * .02 - tan * .016), (.01, .013, .01), b0, WEED, 'skin', n=8, m=5)
        top_y, bot_y = root.y + .02, p1.y - L1

        def weed_paint(p, n, c, top_y=top_y, bot_y=bot_y):
            t = (top_y - p.y) / max(.01, top_y - bot_y)
            rgb = mix(C(WEED), C(WEED_MID), sstep(.0, .45, t))
            return keep(mix(rgb, C(WEED_TIP), sstep(.55, 1.0, t)), c)
        for o in (weed, wa, wb):
            s.paint(o, weed_paint)

    # ---- claw arms (merus + carpus), joint bands, team cuffs ----
    for side, sfx in ((1, 'l'), (-1, 'r')):
        bone = 'uclaw_' + sfx
        sh = s.segments[bone]['shapes'][0]; a = V(sh['a']); b = V(sh['b']); r = sh['radius']
        ax = (b - a).normalized()
        arm = etube(s, 'Claw arm ' + sfx, [a - ax * .04, a + ax * .03, a.lerp(b, .45), a.lerp(b, .8), b - ax * .01],
                    [(r * .74, r * .8), (r * .84, r * .9), (r * .88, r * .94), (r * .84, r * .9), (r * .72, r * .78)], bone, RUST, 'skin', n=18, soft=True)
        s.paint(arm, limb_paint(UP, 51 + side))
        ring_axis(s, 'Detail arm joint ' + sfx, a + ax * .035, ax, r * .87, .008, bone, MEMBRANE, 'skin', n=16, sides=4)
        cc = a.lerp(b, .58)
        etube(s, 'Team cuff ' + sfx, [cc - ax * .024, cc + ax * .024], [(r * .87 + .009, r * .93 + .009)] * 2, bone, 'FFFFFF', 'team', n=20)
        knob = s.ellipsoid('Claw carpus ' + sfx, tuple(b - ax * .015), (r * .9, r * .86, r * .9), bone, RUST, 'skin', n=16, m=8)
        s.paint(knob, limb_paint(UP, 57 + side))
        for j, t in enumerate([.3, .55]):
            q = a.lerp(b, t) + UP * (r * .9)
            sp = etube(s, 'Spine arm %s%d' % (sfx, j), [q - UP * .01, q + UP * .012 + ax * .008, q + UP * .026 + ax * .016], [.012, .007, .0015], bone, RUST_DARK, 'skin', n=6)
            s.paint(sp, lambda p, n, c, q=q: keep(mix(C(RUST_DARK), C(TIP), sstep(.0, .022, p.y - q.y)), c))

    # ---- the crusher (right): swollen palm, molar teeth, dark tips, a mooring chain ----
    A, u, v, w = claw_frame(s.segments['claw_r']['shapes'][0], -1)

    def P(s_, a_=0.0, b_=0.0):
        return A + u * s_ + v * a_ + w * b_
    palm_s = [-.035, .02, .08, .15, .22, .28, .315]
    palm_r = [(.068, .072), (.088, .096), (.106, .124), (.116, .14), (.114, .138), (.098, .122), (.066, .085)]
    palm = etube(s, 'Crusher palm', [P(x) for x in palm_s], palm_r, 'claw_r', RUST, 'skin', n=24, up=v, soft=True)
    s.paint(palm, limb_paint(v, 71))
    dac = [(.24, .066, 0), (.32, .072, 0), (.40, .068, 0), (.47, .052, .004), (.53, .026, .008), (.562, .002, .012)]
    dac_r = [(.058, .05), (.056, .048), (.05, .043), (.04, .034), (.024, .02), (.005, .005)]
    pol = [(.24, -.07, 0), (.32, -.076, 0), (.40, -.071, 0), (.47, -.054, -.004), (.528, -.026, -.008), (.556, .004, -.012)]
    pol_r = [(.064, .055), (.062, .052), (.055, .046), (.043, .036), (.026, .021), (.005, .005)]
    for nm, path, rad, seed in (('Crusher dactyl', dac, dac_r, 73), ('Crusher pollex', pol, pol_r, 75)):
        f = etube(s, nm, [P(*q) for q in path], rad, 'claw_r', RUST, 'skin', n=16, up=v)
        s.paint(f, tipped(limb_paint(v, seed), A, u, .43, .52))
    for j, (ts, R) in enumerate([(.315, .019), (.385, .017), (.45, .014)]):
        a_, b_, rv = _lerp_path(dac, dac_r, ts)
        s.ellipsoid('Detail crusher tooth d%d' % j, tuple(P(ts, a_ - rv * .78, b_)), (R, R * .9, R), 'claw_r', 'EADFC6', 'shell', n=8, m=5)
    for j, (ts, R) in enumerate([(.28, .022), (.35, .02), (.42, .017), (.485, .012)]):
        a_, b_, rv = _lerp_path(pol, pol_r, ts)
        s.ellipsoid('Detail crusher tooth p%d' % j, tuple(P(ts, a_ + rv * .78, b_)), (R, R * .9, R), 'claw_r', 'EADFC6', 'shell', n=8, m=5)
    for j, (ts, deg, R) in enumerate([(.17, 100, .019), (.2, 80, .014), (.14, 114, .012)]):
        ang = math.radians(deg)
        nrm = (v * math.sin(ang) + w * math.cos(ang)).normalized()
        q = P(ts, math.sin(ang) * .138, math.cos(ang) * .114)
        barnacle(s, 'c%d' % j, q - nrm * .004, nrm, R, 'claw_r')
    # the mooring chain: draped from the inner side over the wrist to the outer side ...
    Rw, Rv = .118, .128

    def drape(al):
        return P(.05 + .035 * (1 - al / math.radians(160)), math.sin(al) * Rv, math.cos(al) * Rw)
    samples = [drape(math.radians(160) * (1 - q / 200)) for q in range(201)]
    lengths = [0.0]
    for q in range(1, len(samples)):
        lengths.append(lengths[-1] + (samples[q] - samples[q - 1]).length)
    pitch, L, W, wire = .041, .056, .034, .0092
    n_links = int(lengths[-1] / pitch)
    for j in range(n_links):
        target = pitch * (j + .5)
        q = next(i for i in range(len(lengths)) if lengths[i] >= target)
        cen = samples[q]
        tan = (samples[min(q + 1, 200)] - samples[max(q - 1, 0)]).normalized()
        radial = (cen - A - u * (cen - A).dot(u)).normalized()
        chain_link(s, 'Detail chain link w%d' % j, cen, tan, radial if j % 2 == 0 else u, L, W, wire, 'claw_r')
    # ... and its loose end hanging off the outer side: one spring bone per link
    end = drape(0.0) + w * .008
    parent = 'claw_r'
    for k in range(4):
        head = end - UP * (k * pitch)
        bone = s.view_bone('fx_spring_chain_%d' % k, parent, tuple(head))
        if k < 3:
            chain_link(s, 'Detail chain link t%d' % k, head - UP * (L / 2 - wire), UP, w if k % 2 == 0 else u, L, W, wire, bone)
        else:
            chain_link(s, 'Detail chain ring', head - UP * (.025 - wire), UP, u, .05, .05, wire * 1.1, bone, m=14)
        parent = bone

    # ---- the cutter (left): slim palm, blade fingers with a sharp light edge, dark tips ----
    A2, u2, v2, w2 = claw_frame(s.segments['claw_l']['shapes'][0], 1)

    def Q(s_, a_=0.0, b_=0.0):
        return A2 + u2 * s_ + v2 * a_ + w2 * b_
    cpalm_s = [-.035, .02, .07, .13, .19, .23, .26]
    cpalm_r = [(.05, .054), (.06, .066), (.068, .077), (.07, .081), (.064, .075), (.054, .064), (.034, .044)]
    cpalm = etube(s, 'Cutter palm', [Q(x) for x in cpalm_s], cpalm_r, 'claw_l', RUST, 'skin', n=20, up=v2, soft=True)
    s.paint(cpalm, limb_paint(v2, 81))
    cdac = [(.20, .04, 0), (.27, .045, 0), (.34, .04, .002), (.41, .026, .004), (.462, .008, .006), (.492, -.003, .008)]
    cdac_r = [(.017, .024), (.016, .023), (.014, .019), (.011, .014), (.006, .008), (.0015, .002)]
    cpol = [(.20, -.044, 0), (.27, -.05, 0), (.34, -.045, -.002), (.41, -.029, -.004), (.458, -.009, -.006), (.486, .004, -.008)]
    cpol_r = [(.019, .026), (.018, .025), (.015, .021), (.012, .016), (.007, .009), (.0015, .002)]
    for nm, path, rad, seed, sgn in (('Cutter dactyl', cdac, cdac_r, 83, -1), ('Cutter pollex', cpol, cpol_r, 85, 1)):
        f = etube(s, nm, [Q(*q) for q in path], rad, 'claw_l', RUST, 'skin', n=14, up=v2)
        s.paint(f, tipped(limb_paint(v2, seed), A2, u2, .39, .47))
        edge = [Q(q[0], q[1] + sgn * r_[1] * .82, q[2]) for q, r_ in zip(path[1:-1], rad[1:-1])]
        s.tube('Detail cutter edge %d' % sgn, edge, [.0045, .004, .0032, .002], 'claw_l', 'EFE5CE', 'shell', n=6)

    # ---- walking legs: broad merus, knobbly knee, propodus, dark dactyl, pale joint bands ----
    for sfx in ('fl', 'bl', 'fr', 'br'):
        ub, lb = 'uleg_' + sfx, 'lleg_' + sfx
        ush = s.segments[ub]['shapes'][0]; lsh = s.segments[lb]['shapes'][0]; fsh = s.segments[lb]['shapes'][1]
        a = V(ush['a']); b = V(ush['b']); r = ush['radius']
        side = 1 if a.x > 0 else -1
        ax = (b - a).normalized()
        merus = etube(s, 'Leg merus ' + sfx, [a - ax * .05, a + ax * .04, a.lerp(b, .5), b - ax * .05],
                      [(r * .74, r * .58), (r * .9, r * .68), (r * .96, r * .74), (r * .8, r * .64)], ub, RUST, 'skin', n=14, soft=True)
        s.paint(merus, limb_paint(UP, 101 + len(sfx) * side))
        ring_axis(s, 'Detail coxa band ' + sfx, a + ax * .045, ax, r * .78, .007, ub, MEMBRANE, 'skin', n=14, sides=4)
        knee = s.ellipsoid('Leg knee ' + sfx, tuple(b), (r * .8, r * .8, r * .8), ub, RUST, 'skin', n=14, m=8)
        s.paint(knee, limb_paint(UP, 107 + side))
        a2 = V(lsh['a']); b2 = V(lsh['b']); r2 = lsh['radius']; foot = V(fsh['center'])
        ax2 = (b2 - a2).normalized()
        jn = a2.lerp(b2, .6)
        tip = V((foot.x + side * .012, .014, foot.z))
        pro = etube(s, 'Leg propodus ' + sfx, [a2 - ax2 * .02, a2 + ax2 * .06, a2.lerp(b2, .35), jn],
                    [(r2 * .82, r2 * .72), (r2 * .92, r2 * .8), (r2 * .88, r2 * .76), (r2 * .74, r2 * .64)], lb, RUST, 'skin', n=12, soft=True)
        s.paint(pro, limb_paint(V((side, .6, 0)), 111 + side))
        ring_axis(s, 'Detail knee band ' + sfx, a2 + ax2 * .03, ax2, r2 * .86, .007, lb, MEMBRANE, 'skin', n=14, sides=4)
        ring_axis(s, 'Detail dactyl band ' + sfx, jn, ax2, r2 * .74, .007, lb, MEMBRANE, 'skin', n=14, sides=4)
        dac_l = etube(s, 'Leg dactyl ' + sfx, [jn - ax2 * .01, jn.lerp(tip, .45), jn.lerp(tip, .8), tip],
                      [(r2 * .7, r2 * .6), (r2 * .58, r2 * .5), (r2 * .36, r2 * .32), (.003, .003)], lb, RUST, 'skin', n=10)
        s.paint(dac_l, tipped(limb_paint(V((side, .6, 0)), 117 + side), jn, ax2, .02, .16))

    # ---- detachable gore piece: the cutter's dark tip (same kind as before) ----
    gore = s.tube('Gore cutter tip', [(0, 0, 0), (0, .035, 0), (.015, .075, 0)], [.025, .02, .001], None, TIP, n=16, role='gore')
    s.paint(gore, lambda p, n, c: keep(mix(C(RUST), C(TIP), sstep(.0, .03, p.y)), c))

    s.set_look({'glow_mode': 'pulse', 'fx': {'pupil_reach': .008, 'jaw_deg': 18, 'brow_drop': .008, 'lid_rest': .32,
                                             'spring_gain': 1.4, 'spring_stiffness': .75}})
    s.bake_ao(rays=14, distance=.085, strength=.36)
