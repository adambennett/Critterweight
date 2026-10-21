"""Gusto, the Showboat Tern (v0.9.17 roster art, docs/ART_REVAMP.md "v0.9.17"): a vain, quick,
long-legged white tern with blue-grey wings, an orange beak and legs, black "sunglasses" eye
markings and a turquoise-streaked pompadour. Same locked body as the previous art (fighters.py
gusto): segment bones, pivots and collision shapes are untouched; parts stay registered to the
collision bodies (feathers, crest and tail are soft and stay within ~8 cm); expression and secondary
motion ride extra view bones (fx_*).

Reads from the fight camera (high, behind): layered wings (lesser and greater coverts over separate
flight-feather vanes, black-tipped primaries, blue-grey upper and pale under faces, a turquoise sheen
band = the Hype feature, glow mode 'shimmer'), a styled pompadour of crest feathers on spring bones,
a forked tail fan on spring bones, a grey mantle with scalloped feather rows, scapulars over the wing
roots and the shades' strap round the back of the head. Close up: eyes with confident half-closed
lids inside glossy black "sunglasses", dark feather-tuft brows, an opening lower beak, a cream chest,
scaly orange legs with the taped shins and three-toed webbed feet.
Coordinates are fighter rest space (+Z forward, +Y up, +X the creature's left), metres.
"""
import math
import bmesh
from mathutils import Vector
from mesh_tools import blender
from fighters_v17 import mix, lin, densify

V = Vector
TAU = math.tau

WHITE = 'F2F2EC'; CREAM = 'F4EDDB'; MANTLE = 'B9CBD5'; COVERT = 'A9C1CF'; GREY = '7FA4B8'
SLATE = '587A8E'; INK = '18181E'; ORANGE = 'FF8A3D'; DEEP = 'D9662B'
TURQ = '35C1C9'; PALE = 'E4ECEF'; TAPE = 'EDE6D6'

# the head: an ellipsoid inside the head sphere (centre (0, 1.7, .17), r .14)
HC = V((0, 1.70, .17)); HR = (.135, .135, .14)


# ---- small maths -----------------------------------------------------------------------------------
def smooth(a, b, x):
    if b == a:
        return 1.0 if x >= b else 0.0
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def band(x, a, b, c, d):
    return smooth(a, b, x) * (1 - smooth(c, d, x))


def tone(col, k):
    return (min(1.0, col[0] * k), min(1.0, col[1] * k), min(1.0, col[2] * k), col[3])


def catmull(rows, k):
    """Catmull-Rom through tuples of numbers, k samples per span."""
    out = []
    m = len(rows)
    for i in range(m - 1):
        p0, p1, p2, p3 = rows[max(0, i - 1)], rows[i], rows[i + 1], rows[min(m - 1, i + 2)]
        for j in range(k):
            t = j / k; t2 = t * t; t3 = t2 * t
            out.append(tuple(.5 * (2 * p1[q] + (-p0[q] + p2[q]) * t + (2 * p0[q] - 5 * p1[q] + 4 * p2[q] - p3[q]) * t2
                                   + (-p0[q] + 3 * p1[q] - 3 * p2[q] + p3[q]) * t3) for q in range(len(p1))))
    out.append(tuple(rows[-1]))
    return out


# ---- the collision envelope ------------------------------------------------------------------------
def _shape_dist(p, sh):
    if sh['type'] == 'sphere':
        return (p - V(sh['center'])).length - sh['radius']
    if sh['type'] == 'capsule':
        a, b = V(sh['a']), V(sh['b']); ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
        return (p - a - ab * t).length - sh['radius']
    d = p - V(sh['center']); half = V(sh['size']) / 2
    q = V([abs(d[i]) - half[i] for i in range(3)])
    return V([max(0.0, v) for v in q]).length + min(max(q), 0.0)


def env(s, p, bones=None):
    """Distance of p outside the union of the body's collision shapes (negative inside)."""
    segs = s.segments.values() if bones is None else [s.segments[b] for b in bones]
    return min(_shape_dist(V(p), sh) for seg in segs for sh in seg['shapes'])


def clamp_to(s, p, c, bones, pad):
    """Pull p toward c until it is within `pad` of the named bones' collision shapes."""
    if env(s, p, bones) <= pad:
        return p
    lo, hi = 0.0, 1.0
    for _ in range(22):
        m = (lo + hi) / 2
        if env(s, c + (p - c) * m, bones) > pad:
            hi = m
        else:
            lo = m
    return c + (p - c) * lo


def limit_path(s, pts, widths, limit):
    """Scale a soft appendage's path about its root so it stays within `limit` of the envelope."""
    root = pts[0]

    def worst(k):
        return max(env(s, root + (p - root) * k) + w * .6 for p, w in zip(pts, widths))
    if worst(1.0) <= limit:
        return pts
    lo, hi = .3, 1.0
    for _ in range(18):
        m = (lo + hi) / 2
        if worst(m) > limit:
            hi = m
        else:
            lo = m
    return [root + (p - root) * lo for p in pts]


# ---- mesh helpers ----------------------------------------------------------------------------------
def make(s, name, verts, faces, bone, cols, mat='skin', role='body', smooth_shade=True):
    obj = s.mesh(name, [tuple(v) for v in verts], faces, bone, 'FFFFFF', mat, 0, False, role, smooth_shade)
    attr = obj.data.color_attributes['Color']
    for i, c in enumerate(cols):
        attr.data[i].color = c
    return obj


def loft(s, name, rings, cols, bone, mat='skin', start=None, end=None, role='body'):
    """Quads between rings of n points; each end closed by an n-gon (None) or a fan to (point, rgba)."""
    n = len(rings[0])
    verts = [V(p) for r in rings for p in r]
    vcols = [c for r in cols for c in r]
    faces = []
    for j in range(len(rings) - 1):
        for i in range(n):
            a = j * n + i; b = j * n + (i + 1) % n
            faces.append((a, b, b + n, a + n))
    last = (len(rings) - 1) * n
    if start is None:
        faces.append(tuple(range(n - 1, -1, -1)))
    else:
        k = len(verts); verts.append(V(start[0])); vcols.append(start[1])
        for i in range(n):
            faces.append((k, (i + 1) % n, i))
    if end is None:
        faces.append(tuple(last + i for i in range(n)))
    else:
        k = len(verts); verts.append(V(end[0])); vcols.append(end[1])
        for i in range(n):
            faces.append((k, last + i, last + (i + 1) % n))
    return make(s, name, verts, faces, bone, vcols, mat, role)


def path_frames(pts):
    pts = [V(p) for p in pts]
    tans = []
    for j in range(len(pts)):
        a = pts[max(0, j - 1)]; b = pts[min(len(pts) - 1, j + 1)]
        tans.append((b - a).normalized())
    acc = [0.0]
    for j in range(1, len(pts)):
        acc.append(acc[-1] + (pts[j] - pts[j - 1]).length)
    tot = acc[-1] or 1.0
    return pts, tans, [a / tot for a in acc]


def vane(s, name, pts, widths, thick, bone, colf, side=None, up=None, mat='skin', n=6, camber=0.0,
         role='body', limit=None):
    """A feather vane (or any flattened tapered tube) along pts, root first. The width runs along
    `side` (projected off the path) or along up x tangent; up = tangent x side is its top face.
    colf(t along 0..1, x across -1..1 (+ = side), y face (+ top)) -> linear rgba."""
    pts = [V(p) for p in pts]
    if limit is not None:
        pts = limit_path(s, pts, widths, limit)
    pts, tans, ts = path_frames(pts)
    if isinstance(thick, (int, float)):
        thick = [thick] * len(pts)
    if isinstance(camber, (int, float)):
        camber = [camber] * len(pts)
    rings, cols = [], []
    for j, (p, t) in enumerate(zip(pts, tans)):
        if side is not None:
            sd = V(side) - t * V(side).dot(t)
        else:
            u0 = V(up[j]) if isinstance(up, (list, tuple)) and not isinstance(up[0], (int, float)) else V(up)
            sd = u0.cross(t)
        sd.normalize()
        u = t.cross(sd)
        rr, cc = [], []
        for k in range(n):
            a = TAU * k / n; x = math.cos(a); y = math.sin(a)
            rr.append(p + sd * (x * widths[j]) + u * (y * thick[j] + camber[j] * (1 - x * x)))
            cc.append(colf(ts[j], x, y))
        rings.append(rr); cols.append(cc)
    return loft(s, name, rings, cols, bone, mat, role=role)


def tube_rings(pts, radii, n, ref=(0, 1, 0)):
    """Rings round a path; radii (a, b): a along `ref` (projected), b along tangent x ref.
    Returns pts, ts, rings and each ring point's outward direction."""
    pts, tans, ts = path_frames(pts)
    rings, dirs = [], []
    for p, t, r in zip(pts, tans, radii):
        ra, rb = r if isinstance(r, (tuple, list)) else (r, r)
        a = V(ref) - t * V(ref).dot(t); a.normalize(); b = t.cross(a)
        ring, dd = [], []
        for k in range(n):
            ang = TAU * k / n
            d = a * (math.cos(ang) * ra) + b * (math.sin(ang) * rb)
            ring.append(p + d)
            dd.append((a * (math.cos(ang) / max(ra, 1e-6)) + b * (math.sin(ang) / max(rb, 1e-6))).normalized())
        rings.append(ring); dirs.append(dd)
    return pts, ts, rings, dirs


def set_weights(obj, fn):
    """Replace an object's bone weights: fn(fighter point) -> {bone: weight}."""
    obj.vertex_groups.clear()
    groups = {}
    for v in obj.data.vertices:
        p = V((v.co.x, v.co.z, -v.co.y))
        for b, w in fn(p).items():
            if w <= 1e-4:
                continue
            if b not in groups:
                groups[b] = obj.vertex_groups.new(name=b)
            groups[b].add([v.index], w, 'REPLACE')


def orient_out(obj, center):
    """Open sheets (decals): turn every face away from `center` (fighter space)."""
    me = obj.data
    bm = bmesh.new(); bm.from_mesh(me)
    c = V(blender(center))
    flip = [f for f in bm.faces if f.normal.dot(f.calc_center_median() - c) < 0]
    if flip:
        bmesh.ops.reverse_faces(bm, faces=flip)
    bm.to_mesh(me); bm.free(); me.update()


def scallop(u, v):
    """Rows of overlapping feather tips (tips down), u in feather widths round, v in rows up.
    0 at a feather's tip edge, growing toward its base where the row above overlaps it."""
    r = math.floor(v); fv = v - r
    fu = u + (.5 if r % 2 else 0.0); fu = fu - math.floor(fu) - .5
    d = fv - .9 * (2 * fu) ** 2
    if d < 0:
        fu2 = u + (0.0 if r % 2 else .5); fu2 = fu2 - math.floor(fu2) - .5
        d = fv + 1 - .9 * (2 * fu2) ** 2
    return d


# ---- body + neck: one continuous loft (horizontal rings), fitted to the torso/neck capsules ----------
# (y, centre z, half-width x, front depth, back depth)
BODY = [(.800, -.078, .060, .070, .075), (.820, -.080, .115, .125, .135), (.860, -.078, .158, .170, .180),
        (.920, -.070, .188, .205, .205), (1.000, -.052, .203, .222, .216), (1.080, -.030, .210, .236, .222),
        (1.160, -.004, .212, .243, .215), (1.230, .020, .206, .238, .200), (1.290, .042, .190, .214, .178),
        (1.340, .062, .162, .178, .152), (1.390, .084, .128, .132, .120), (1.440, .104, .103, .102, .095),
        (1.500, .121, .091, .088, .086), (1.560, .134, .086, .082, .083), (1.610, .145, .080, .076, .078),
        (1.655, .155, .056, .050, .055)]
DENSE = catmull(BODY, 3)


def body_at(y):
    if y <= DENSE[0][0]:
        return DENSE[0][1:]
    for a, b in zip(DENSE, DENSE[1:]):
        if a[0] <= y <= b[0]:
            t = (y - a[0]) / (b[0] - a[0])
            return tuple(a[q] * (1 - t) + b[q] * t for q in range(1, 5))
    return DENSE[-1][1:]


def body_surface(y, ph):
    """Point and outward normal of the (unfitted) body loft at height y, angle ph (0 = front, + = left)."""
    def at(yy, pp):
        zc, rx, rf, rb = body_at(yy)
        c = math.cos(pp)
        return V((rx * math.sin(pp), yy, zc + (rf if c >= 0 else rb) * c))
    p = at(y, ph)
    du = at(y, ph + .01) - at(y, ph - .01)
    dv = at(y + .005, ph) - at(y - .005, ph)
    n = du.cross(dv).normalized()
    if n.dot(p - V((0, y, body_at(y)[0]))) < 0:
        n = -n
    return p, n


def body_col(ph, y):
    cz = math.cos(ph)
    col = lin(WHITE)
    chest = smooth(.0, .55, cz) * band(y, .93, 1.06, 1.42, 1.56)
    col = mix(col, lin(CREAM), chest)
    back = smooth(.1, .65, -cz) * band(y, .98, 1.09, 1.33, 1.43)
    col = mix(col, lin(MANTLE), back)
    belly = smooth(.95, .82, y)
    col = mix(col, lin('E6E4DC'), belly * .6)
    # scalloped feather rows, sized to the local girth (smaller up the neck)
    h = max(.022, min(.042, .042 * (body_at(y)[1] / .2) ** .6))
    row_y = (math.floor(y / h) + .5) * h
    R = max(.05, body_at(row_y)[1])
    N = max(8, round(TAU * R / (h * 1.55)))
    d = scallop(ph / TAU * N, y / h)
    k = 1 - (.018 + .04 * back) * smooth(.3, 1.15, d) + .012 * (1 - smooth(0, .2, d))
    return tone(col, k)


def body_w(p):
    wn = smooth(1.30, 1.42, p.y); wh = smooth(1.575, 1.645, p.y)
    return {'torso': 1 - wn, 'neck': wn * (1 - wh), 'head': wh}


def body(s):
    n = 56
    rings, cols = [], []
    for (y, zc, rx, rf, rb) in DENSE:
        c = V((0, y, zc))
        ring, cc = [], []
        for i in range(n):
            ph = TAU * i / n
            cz = math.cos(ph)
            p = V((rx * math.sin(ph), y, zc + (rf if cz >= 0 else rb) * cz))
            ring.append(clamp_to(s, p, c, ['torso', 'neck', 'head'], .014 if y < 1.36 else .024))
            cc.append(body_col(ph, y))
        rings.append(ring); cols.append(cc)
    obj = loft(s, 'Body - tern', rings, cols, 'torso', start=((0, .79, -.078), body_col(0, .79)),
               end=((0, 1.672, .157), lin(WHITE)))
    set_weights(obj, body_w)


# ---- head, beak and face ---------------------------------------------------------------------------
def head_pt(az, el, off=0.0):
    """A point on the head ellipsoid at azimuth az (deg, 0 = front, + = left) and elevation el (deg)."""
    a = math.radians(az); e = math.radians(el)
    p = V((HR[0] * math.cos(e) * math.sin(a), HR[1] * math.sin(e), HR[2] * math.cos(e) * math.cos(a)))
    nrm = V((p.x / HR[0] ** 2, p.y / HR[1] ** 2, p.z / HR[2] ** 2)).normalized()
    return HC + p + nrm * off, nrm


def head(s):
    hd = s.ellipsoid('Head', tuple(HC), HR, 'head', WHITE, n=32, m=16, soft=True)

    def paint(p, n, c):
        col = lin(WHITE)
        col = mix(col, lin(CREAM), smooth(.2, .7, n.z) * smooth(-.1, -.6, n.y) * .8)   # chin, throat
        col = mix(col, lin('E3E8EA'), smooth(.1, .8, -n.z) * smooth(-.2, .5, n.y) * .5)  # cool nape
        return col
    s.paint(hd, paint)
    beak(s)
    sunglasses(s)
    for side, sfx in ((1, 'l'), (-1, 'r')):
        eye(s, side, sfx)
        brow(s, side, sfx)
    crest(s)


def beak(s):
    """Upper mandible on the head; lower mandible on fx_jaw (hinge at the gape); a dark mouth inside.
    A slender dagger, inside the beak capsule (0,1.66,.30)-(0,1.63,.52) r .045."""
    z0, z1 = .258, .566
    ym = lambda t: 1.6485 - .02 * t ** 1.3
    N = 16
    rings, cols = [], []
    ts = [0, .06, .13, .21, .3, .4, .5, .6, .69, .77, .84, .9, .95, .985, 1.0]
    for t in ts:
        z = z0 + (z1 - z0) * t
        w = .031 * (1 - t) ** .8 + .0016
        h = .047 * (1 - t) ** .9 + .002
        ring, cc = [], []
        for k in range(N):
            a = TAU * k / N
            ca, sa = math.cos(a), math.sin(a)
            if sa >= 0:
                y = ym(t) + h * sa ** .9
            else:
                y = ym(t) - .006 * (-sa) ** .6 * (1 - t * .7)
            ring.append(V((w * ca, y, z)))
            top = max(0.0, sa)
            col = mix(lin(ORANGE), lin('EE6A22'), smooth(.5, 1.0, t))
            col = mix(col, lin('FFB27A'), smooth(.8, 1.0, top) * (1 - t) * .5)       # culmen highlight
            if sa < -.2:
                col = mix(col, lin('B9573A'), .8)                                    # palate
            cc.append(col)
        rings.append(ring); cols.append(cc)
    loft(s, 'Beak - upper mandible', rings, cols, 'head', 'shell')
    jaw = s.view_bone('fx_jaw', 'head', (0, 1.646, .262))
    rings, cols = [], []
    zl1 = .552
    for t in ts:
        z = .268 + (zl1 - .268) * t
        tt = (z - z0) / (z1 - z0)
        w = .029 * (1 - t) ** .85 + .0015
        d = .028 * (1 - t) ** .95 + .002
        ring, cc = [], []
        for k in range(N):
            a = TAU * k / N
            ca, sa = math.cos(a), math.sin(a)
            if sa >= 0:
                y = ym(tt) - .0016 + .002 * sa
            else:
                y = ym(tt) - .0016 - d * (-sa) ** .8
            ring.append(V((w * ca, y, z)))
            col = mix(lin(ORANGE), lin('EE6A22'), smooth(.5, 1.0, t))
            if sa > .3:
                col = mix(col, lin('B04E55'), .85)                                   # mouth floor
            cc.append(col)
        rings.append(ring); cols.append(cc)
    loft(s, 'Beak - lower mandible', rings, cols, jaw, 'shell')
    s.ellipsoid('Detail tongue', (0, 1.636, .315), (.011, .005, .04), jaw, 'C9606C', 'skin', n=12, m=6)
    s.ellipsoid('Detail mouth interior', (0, 1.641, .325), (.021, .009, .07), 'head', '3A1820', 'skin', n=14, m=7)
    for side in (1, -1):
        s.ellipsoid('Detail nostril %d' % side, (side * .0196, 1.6712, .338), (.0026, .0021, .0115), 'head', '7A3418', 'skin', n=8, m=4)


def lens_bounds(az):
    """Elevation range (deg) of the sunglasses marking at azimuth az: two wayfarer lenses round the
    eyes, a bridge over the beak and temple bars narrowing into a strap round the back of the head."""
    a = abs(az)
    lo = hi = None
    if a < 13:
        lo, hi = 17.0, 25.0
    elif a > 46:
        # the temple bar narrows into a strap that runs round the back of the head (sports shades)
        f = (a - 46) / (180 - 46)
        mid = 23.5 - 5 * smooth(0, 1, f); hw = 2.7 + 1.9 * (1 - smooth(46, 118, a))
        lo, hi = mid - hw, mid + hw
    cx, cy, ax, ay, pw = 30.0, 12.5, 21.5, 17.5, 3.2
    dx = (a - cx) / ax
    if abs(dx) < 1:
        e = (1 - abs(dx) ** pw) ** (1 / pw)
        top = cy + ay * e * 1.0 + 2.5 * dx
        bot = cy - ay * e * (.92 + .1 * dx)
        lo = bot if lo is None else min(lo, bot)
        hi = top if hi is None else max(hi, top)
    return lo, hi


def sunglasses(s):
    """Glossy black 'shades': a feather marking (decal) conformed to the head, crisp edges."""
    azs = []
    a = -180.0
    while a <= 180.0001:
        azs.append(a)
        a += 2.0 if abs(a) < 56 else 5.0
    if azs[-1] < 179.999:
        azs.append(180.0)                  # close the strap behind the head
    M = 5
    verts, cols, faces = [], [], []
    for a in azs:
        lo, hi = lens_bounds(a)
        for k in range(M):
            el = lo + (hi - lo) * k / (M - 1)
            p, _ = head_pt(a, el, .0028)
            verts.append(p)
            lens = 1 - smooth(46, 54, abs(a)) if abs(a) > 9 else 0.0
            cols.append(mix(lin(INK), lin('263040'), smooth(.6, 1.0, k / (M - 1)) * lens * .7))
    for i in range(len(azs) - 1):
        for k in range(M - 1):
            q = i * M + k
            faces.append((q, q + 1, q + M + 1, q + M))
    obj = make(s, 'Detail sunglasses marking', verts, faces, 'head', cols, 'eye')
    orient_out(obj, HC)


EYE = (.028, .025, .013)


def lid(s, name, c, scale, bone, side, color, tilt=7.0, depth=1.5):
    """A closed upper lid on fx_lid_<side> (CreatureFxRig squashes it toward its bone at the top of
    the eye): a squircle in front view, so the open (squashed) lid has a straight edge, tipped so the
    inner corner sits lower - the confident, half-lidded look."""
    x, y, z = c; w, h, d = scale
    cz = z + d * .55
    rx, ry, rz = w * 1.13, h * 1.1, d * depth
    a = math.radians(tilt) * side
    ca, sa = math.cos(a), math.sin(a)
    n, m = 22, 12
    sg = lambda v, e: math.copysign(abs(v) ** e, v)

    def at(px, py, pz):
        return V((x + px * ca - py * sa, y + px * sa + py * ca, cz + pz))
    verts = [at(0, -ry, 0)]
    for j in range(1, m):
        ph = -math.pi / 2 + math.pi * j / m
        for i in range(n):
            th = TAU * i / n
            verts.append(at(rx * sg(math.cos(ph), .5) * math.cos(th), ry * sg(math.sin(ph), .5),
                            rz * sg(math.cos(ph), .5) * math.sin(th)))
    verts.append(at(0, ry, 0))
    top = len(verts) - 1
    faces = [(0, 1 + i, 1 + (i + 1) % n) for i in range(n)]
    for j in range(m - 2):
        for i in range(n):
            q = 1 + j * n + i; r = 1 + j * n + (i + 1) % n
            faces.append((q, q + n, r + n, r))
    faces += [(top, 1 + (m - 2) * n + (i + 1) % n, 1 + (m - 2) * n + i) for i in range(n)]
    make(s, name, verts, faces, bone, [lin(color)] * len(verts), 'eye')


def eye(s, side, sfx):
    """Smaller eyes peeking out of the shades; the lids are the shades' colour, so a half-closed lid
    reads as the shades' heavy top rim (a confident, half-lidded look)."""
    ep, _ = head_pt(side * 30.0, 12.0, -.004)
    eb, lb = s.rig_eye('Eye ' + sfx, tuple(ep), EYE, 'head', sfx, iris='2BB3BD', lid_color=None, pupil='0E0E12')
    lid(s, 'Detail lid Eye ' + sfx, ep, EYE, lb, side, '1C1C23')
    x, y, z = ep
    w, h, d = EYE
    # a second, low catchlight that stays clear of the half-closed lid
    s.ellipsoid('Detail glint low ' + sfx, (x + .3 * w, y - .3 * h, z + d * 1.8), (.0032, .0026, .0018), eb, 'FFFFFF', 'eye', n=8, m=4)


def brow(s, side, sfx):
    """Brows: dark feather tufts above each lens (a long swept stroke and a flick at its outer end),
    on fx_brow_<side>; a white gap keeps them apart from the shades."""
    c, _ = head_pt(side * 31.0, 37.0, .004)
    bb = s.view_bone('fx_brow_' + sfx, 'head', tuple(c))
    for k, (a0, e0, da, de, w, L) in enumerate([(13.0, 34.0, 32.0, 5.5, .0088, 5), (31.0, 37.2, 21.0, 7.5, .0062, 5)]):
        pts, ups = [], []
        for q in range(L):
            f = q / (L - 1)
            p, nrm = head_pt(side * (a0 + da * f), e0 + de * f * f, .0035 + .002 * math.sin(f * math.pi))
            pts.append(p); ups.append(nrm)
        ws = [w * .55, w, w * .95, w * .6, .0012]
        vane(s, 'Detail brow %s%d' % (sfx, k), pts, ws, .0016, bb,
             lambda t, x, y: mix(lin('1E1E24'), lin('3A3A44'), smooth(.55, 1.0, t) * .5), up=ups, n=6, camber=.0012)


def crest(s):
    """The pompadour: a back row of five feather locks rising from the crown and arching forward
    (the middle one tallest, one dyed turquoise) over three short front locks rising from the forehead
    into the curl (the streak carries on down one of them), on a small white base; every lock on its
    own spring bone (the number ending its name is how loosely it swings: the tall middle ones most)."""
    s.ellipsoid('Pompadour base', (0, 1.85, .205), (.054, .05, .074), 'head', 'E9ECEC', n=14, m=7)

    def lock_col(dyed):
        def colf(t, x, y):
            if y < -.2:
                return mix(lin('C9D2D8'), lin('E2E7EA'), t)
            col = mix(lin('EEEFEA'), lin('FFFFFF'), smooth(.2, .9, t))
            col = tone(col, 1 - .06 * (1 - abs(x)) * smooth(.5, .95, y))          # the shaft
            g = 0.0
            if dyed > .9:
                g = smooth(.05, .22, t) * (1 - smooth(.9, .99, t))
            elif dyed > 0:
                g = (1 - smooth(-.45, -.05, x)) * smooth(.1, .25, t) * (1 - smooth(.82, .95, t))
            return mix(col, lin(TURQ, .8), g)
        return colf

    def locks(centre, xs, names, root_z, w_c, lift, dyed_at, label, widths, thick, camber, sv=(1, 0, 0)):
        for i, xi in enumerate(xs):
            f = abs(xi) / max(abs(v) for v in xs)
            hf = 1 - lift * f * f
            zf = .9 + .1 * hf
            rz = root_z + .012 * f
            ry = HC.y + HR[1] * math.sqrt(max(0.0, 1 - (xi / HR[0]) ** 2 - ((rz - HC.z) / HR[2]) ** 2)) - .009
            root = V((xi, ry, rz))
            pts = [root]
            for k, (yy, zz) in enumerate(centre[1:]):
                t = (k + 1) / (len(centre) - 1)
                pts.append(V((xi * (1 + .2 * t), root.y + (yy - centre[0][0]) * hf, root.z + (zz - centre[0][1]) * zf)))
            bone = s.view_bone('fx_spring_crest_' + names[i], 'head', tuple(root))
            w0 = w_c - .002 * f
            vane(s, 'Feather crest %s%d' % (label, i), pts, [w0 * q for q in widths], thick, bone,
                 lock_col(dyed_at.get(i, 0.0)), side=sv, n=8, camber=camber, limit=.082)
    locks([(1.822, .148), (1.868, .160), (1.900, .196), (1.911, .238), (1.902, .270), (1.886, .292)],
          [-.046, -.023, 0.0, .023, .046], ['r2_0', 'r1_1', 'c_2', 'l1_1', 'l2_0'],
          .148, .025, .32, {1: 1.0, 2: .55}, 'b',
          [.7, 1.0, 1.04, .95, .62, .1], [.007, .0085, .008, .007, .0048, .0015],
          [.002, .006, .007, .006, .004, .0005])
    # the front face: three locks rising from the forehead into the curl (their outer face forward)
    locks([(1.806, .236), (1.832, .258), (1.856, .274), (1.874, .281), (1.884, .279)],
          [-.03, 0.0, .03], ['fr_0', 'fc_1', 'fl_0'], .236, .021, .25, {0: 1.0}, 'f',
          [.75, 1.0, 1.0, .85, .35], [.0065, .0075, .007, .0055, .002],
          [.002, .005, .005, .003, .0008], sv=(-1, 0, 0))


# ---- wings -----------------------------------------------------------------------------------------
T0 = V((0, -.8, -.6)).normalized()        # flight feathers trail back and down from the leading edge
UP = V((0, .6, -.8))                        # the wing's upper face (seen from above and behind)


def wing_axis(x):
    if x <= .62:
        t = (x - .24) / .36
        return V((x, 1.24 + .06 * t, -.02 - .06 * t))
    t = (x - .64) / .46
    return V((x, 1.30 - .09 * t, -.08 - .02 * t))


def wing_r(x):
    pts = [(.19, .050), (.24, .056), (.45, .056), (.60, .052), (.66, .048), (.85, .043), (.98, .036), (1.08, .026), (1.14, .010)]
    for (xa, ra), (xb, rb) in zip(pts, pts[1:]):
        if xa <= x <= xb:
            t = (x - xa) / (xb - xa)
            return ra * (1 - t) + rb * t
    return pts[-1][1]


def trail(x):
    return (T0 + V((1, 0, 0)) * (.05 + .22 * smooth(.55, 1.0, x))).normalized()


def mirror(p, side):
    return V((p[0] * side, p[1], p[2]))


def wing(s, side, sfx):
    ub, lb = 'uwing_' + sfx, 'lwing_' + sfx

    def bone_at(x):
        return ub if x < .61 else lb
    # the arm (leading edge): a flattened, airfoil-like tube across the elbow, blue-grey, paler under
    xs = [.19 + (1.14 - .19) * i / 27 for i in range(28)]
    pts = [mirror(wing_axis(x), side) for x in xs]
    radii = [(wing_r(x) * .78, wing_r(x)) for x in xs]
    _, _, rings, dirs = tube_rings(pts, radii, 14, ref=(0, 1, 0))
    cols = []
    for ring, dd, x in zip(rings, dirs, xs):
        cc = []
        for d in dd:
            top = d.dot(UP)
            col = mix(lin('BCCDD8'), lin(COVERT), smooth(-.65, .15, top))
            col = mix(col, lin('9DB8C7'), smooth(.35, .95, top) * .5)
            col = mix(col, lin(SLATE), smooth(1.0, 1.13, x) * smooth(-.2, .5, top))
            cc.append(col)
        cols.append(cc)
    arm = loft(s, 'Wing arm ' + sfx, rings, cols, ub)

    # marginal coverts: small flat feathers lying over the leading edge, tips swept back over the top
    def marg_col(t, x, y):
        if y < -.05:
            return lin('B4C6D1')
        c = mix(lin('B9CCD7'), lin(COVERT), t * .7)
        return mix(c, lin('DCE6EB'), smooth(.78, .95, t))
    for i in range(18):
        x = .255 + .045 * i
        if .372 < x < .452 or x > 1.04:
            continue          # the team tape sits on the arm there
        r = wing_r(x); ry = r * .78
        c0 = wing_axis(x)
        mp, ups = [], []
        for q in range(4):
            f = q / 3
            th = math.radians(-14 + 82 * f)
            nrm = V((0, math.sin(th) / ry, math.cos(th) / r)).normalized()
            pnt = c0 + V((.014 * f, ry * math.sin(th), r * math.cos(th))) + nrm * (.003 + .0025 * math.sin(f * math.pi))
            mp.append(mirror(pnt, side)); ups.append(mirror(nrm, side))
        vane(s, 'Feather marginal %s%02d' % (sfx, i), mp, [.011, .021, .018, .005], [.0022, .002, .0017, .001],
             bone_at(x), marg_col, up=ups, n=6, camber=.0012)

    def arm_w(p):
        x = abs(p.x)
        wl = smooth(.575, .665, x)
        wt = .45 * (1 - smooth(.19, .27, x))
        return {'torso': wt, ub: (1 - wl) * (1 - wt), lb: wl * (1 - wt)}
    set_weights(arm, arm_w)
    rt = wing_r(.41)
    s.tube('Team wing tape ' + sfx, [mirror(wing_axis(.395), side), mirror(wing_axis(.432), side)],
           [(rt + .0065, rt * .78 + .0065)] * 2, ub, 'FFFFFF', 'team', n=20)

    def flight_col(kind):
        def f(t, x, y):
            if y < -.05:
                c = mix(lin(PALE), lin('CDD6DB'), t * .6)
                if kind == 'p':
                    c = mix(c, lin('4C5158'), smooth(.55, .75, t))
                return c
            if kind == 'p':
                c = mix(lin(SLATE), lin(INK), smooth(.5, .68, t))
                c = mix(c, lin('32424E'), smooth(.0, .25, t) * (1 - smooth(.2, .5, t)) * .4)
                return c
            c = mix(lin(GREY), lin('6F96AA'), t * .4)
            sheen = band(t, .5, .6, .74, .84)                       # the exposed band below the coverts
            c = mix(c, lin(TURQ, .82), sheen * .95)
            c = mix(c, lin('EEF3F5'), smooth(.86, .96, t))           # white trailing edge
            return c
        return f

    # secondaries and tertials along the arm (uwing and lwing)
    for i in range(16):
        x = .27 + .0452 * i
        r = wing_r(x)
        T = trail(x)
        root = wing_axis(x) + T * (r * .3) - UP * (r * .1)
        L = .118 - .006 * smooth(.6, .95, x)
        p = [root, root + T * (L * .28) + UP * .003, root + T * (L * .58) + UP * .004, root + T * (L * .84) + UP * .001, root + T * L - UP * .004]
        p = [mirror(q, side) for q in p]
        w = .0245
        vane(s, 'Feather wing %s s%02d' % (sfx, i), p, [.008, w, w * 1.02, w * .85, w * .2], [.005, .0045, .004, .0035, .0018],
             bone_at(x), flight_col('s'), side=(-1, 0, 0), n=6, camber=.0035, limit=.08)
    # primaries fanning from the hand: dark, black tips
    fan = [.12, .27, .43, .6, .77, .93]
    for i, f in enumerate(fan):
        x = .955 + .032 * i
        r = wing_r(x)
        D = (trail(1.0) * (1 - f) + V((1, -.10, -.22)).normalized() * f).normalized()
        root = wing_axis(x) + D * (r * .2) - UP * (r * .1)
        L = .135 + .01 * f
        p = [root, root + D * (L * .28) + UP * .003, root + D * (L * .58) + UP * .003, root + D * (L * .84), root + D * L - UP * .005]
        p = [mirror(q, side) for q in p]
        w = .026 - .003 * f
        vane(s, 'Feather wing %s p%d' % (sfx, i), p, [.007, w, w, w * .8, w * .18], [.0048, .0042, .0038, .0032, .0016],
             lb, flight_col('p'), side=(-1, 0, 0), n=6, camber=.003, limit=.08)

    # greater coverts over the flight feathers' bases, lesser coverts on the arm
    def covert_col(c0, c1):
        def f(t, x, y):
            if y < -.05:
                return lin(PALE)
            c = mix(lin(c0), lin(c1), smooth(.72, .92, t))
            return c
        return f
    for i in range(17):
        x = .292 + .0452 * i
        if x > 1.0:
            break
        r = wing_r(x)
        T = trail(x)
        root = wing_axis(x) + T * (r * .15) + UP * (r * .55)
        L = .068 - .008 * smooth(.6, .95, x)
        fr = [0, .3, .55, .75, .88, .96, 1.0]
        p = [root + T * (L * u) + UP * (.002 * math.sin(u * math.pi) - .008 * u ** 3) for u in fr]
        p = [mirror(q, side) for q in p]
        vane(s, 'Feather covert %s g%02d' % (sfx, i), p, [.008, .019, .021, .02, .016, .01, .003], [.0042, .0038, .0035, .0032, .0028, .0022, .0012],
             bone_at(x), covert_col(COVERT, 'D7E3E9'), side=(-1, 0, 0), n=6, camber=.003, limit=.08)
    for i in range(15):
        x = .275 + .049 * i
        if .375 < x < .455 or x > .99:
            continue          # the team tape sits on the arm there
        r = wing_r(x)
        T = trail(x)
        root = wing_axis(x) + UP * (r * .86) - T * (r * .1)
        L = .056
        fr = [0, .35, .65, .85, 1.0]
        p = [root + T * (L * u) + UP * (.0015 * math.sin(u * math.pi) - .005 * u * u) for u in fr]
        p = [mirror(q, side) for q in p]
        vane(s, 'Detail feather covert %s l%02d' % (sfx, i), p, [.009, .022, .022, .016, .004], [.0022, .002, .0018, .0015, .001],
             bone_at(x), covert_col('A2BCCB', 'CFDDE5'), side=(-1, 0, 0), n=6, camber=.0012, limit=.08)
    # primary coverts over the hand
    for i in range(3):
        x = .975 + .045 * i
        r = wing_r(x)
        D = (trail(1.0) * (1 - .25 * i) + V((1, -.1, -.22)).normalized() * (.25 * i)).normalized()
        root = wing_axis(x) + UP * (r * .6) + D * (r * .1)
        L = .064
        p = [root, root + D * (L * .4) + UP * .002, root + D * (L * .78) - UP * .001, root + D * L - UP * .007]
        p = [mirror(q, side) for q in p]
        vane(s, 'Feather covert %s pc%d' % (sfx, i), p, [.008, .022, .019, .005], [.004, .0036, .003, .0015],
             lb, covert_col(GREY, 'C3D4DD'), side=(-1, 0, 0), n=6, camber=.0025, limit=.08)


def scapulars(s, side, sfx):
    """Shoulder tufts: two staggered rows of rounded mantle feathers over each wing root, lying down
    the back (seen from behind); the grey mantle shows between the shoulders."""
    rows = [(1.312, [1.86, 2.13, 2.40], .105, .006), (1.356, [1.74, 2.0, 2.27], .118, .011)]
    k = 0
    for y0, phs, L, off in rows:
        for ph0 in phs:
            pts, ups = [], []
            for q in range(6):
                f = q / 5
                p, nrm = body_surface(y0 - L * f, ph0 + .09 * f)
                p = V((p.x * side, p.y, p.z)); nrm = V((nrm.x * side, nrm.y, nrm.z))
                pts.append(p + nrm * (off + .004 * math.sin(f * math.pi))); ups.append(nrm)

            def colf(t, x, y):
                if y < -.05:
                    return lin('B2C2CC')
                c = mix(lin('B4C7D3'), lin(COVERT), t * .6)
                c = tone(c, 1 - .05 * (1 - abs(x)) * smooth(.5, .95, y))
                return mix(c, lin('DDE7EC'), smooth(.8, .96, t))
            vane(s, 'Feather scapular %s%d' % (sfx, k), pts, [.012, .029, .032, .031, .025, .008], [.005, .0045, .0042, .004, .0034, .0015],
                 'torso', colf, up=ups, n=8, camber=.0035)
            k += 1


# ---- tail ------------------------------------------------------------------------------------------
def tail(s):
    pts = [V((0, 1.005, -.16)), V((0, .985, -.25)), V((0, .958, -.34)), V((0, .936, -.405)), V((0, .925, -.44))]
    radii = [(.064, .088), (.054, .078), (.042, .062), (.028, .04), (.012, .014)]
    _, _, rings, dirs = tube_rings(pts, radii, 18, ref=(0, 1, 0))
    cols = [[mix(lin(WHITE), lin('DCE3E7'), smooth(.2, .9, d.y) * .7) for d in dd] for dd in dirs]
    rump = loft(s, 'Tail rump', rings, cols, 'tail')
    set_weights(rump, lambda p: {'torso': .5 * smooth(-.27, -.17, p.z), 'tail': 1 - .5 * smooth(-.27, -.17, p.z)})
    # spring links (the last number in the bone name): the long outer streamers swing the most
    fan = [('0', 0, .150), ('l_1', 1, .160), ('r_1', -1, .160), ('lm_1', 2, .175), ('rm_1', -2, .175), ('ls_2', 3, .205), ('rs_2', -3, .205)]
    for name, k, L in fan:
        ang = math.radians(11.0 * k)
        tilt = math.radians(14.0 + 1.5 * abs(k))
        D = V((math.sin(ang) * math.cos(tilt), -math.sin(tilt), -math.cos(ang) * math.cos(tilt)))
        root = V((.011 * k, .943 - .002 * abs(k), -.392 + .004 * abs(k)))
        bone = s.view_bone('fx_spring_tail_' + name, 'tail', tuple(root))
        streamer = abs(k) == 3
        p = [root, root + D * (L * .3) + V((0, .004, 0)), root + D * (L * .62) + V((0, .004, 0)), root + D * (L * .86), root + D * L - V((0, .006, 0))]
        w = .016 if streamer else .021

        def colf(t, x, y, streamer=streamer, k=k):
            if y < -.05:
                return mix(lin('E9EEF0'), lin('C9D1D6'), t * .5)
            c = mix(lin('D5DDE2'), lin(WHITE), smooth(.0, .45, t))
            if streamer:
                outer = x * (-1 if k > 0 else 1)          # side=(-1,0,0): +x points to the creature's right
                c = mix(c, lin('9FB3BF'), smooth(.2, .9, outer) * .7)
                c = mix(c, lin(INK), smooth(.72, .9, t))
            else:
                c = mix(c, lin('B9C9D2'), smooth(.8, 1.0, t) * .6)
            return c
        widths = [.006, w, w * 1.02, w * .8, .002] if not streamer else [.006, w, w * .9, w * .6, .0015]
        vane(s, 'Feather tail ' + name, p, widths, [.0045, .004, .0038, .003, .0015], bone, colf,
             side=(-1, 0, 0), n=6, camber=.003, limit=.08)


# ---- legs and feet ---------------------------------------------------------------------------------
def leg(s, side, sfx):
    th, sh = 'thigh_' + sfx, 'shin_' + sfx
    X = lambda x: x * side
    # feathered "trousers" with a scalloped hem
    path = [V((X(.114), .955, .004)), V((X(.12), .885, -.004)), V((X(.123), .82, -.016)), V((X(.125), .772, -.026)), V((X(.126), .742, -.032))]
    radii = [.066, .074, .07, .062, .052]
    _, _, rings, dirs = tube_rings(path, radii, 16, ref=(0, 0, 1))
    hem = rings[-1]
    for i in range(16):
        hem[i] = hem[i] - V((0, .013 if i % 2 == 0 else 0, 0))
    cols = []
    for ring, dd in zip(rings, dirs):
        cc = []
        for p, d in zip(ring, dd):
            ph = math.atan2(d.x * side, d.z)
            dsc = scallop(ph / TAU * 12, p.y / .034)
            c = tone(lin(WHITE), 1 - .05 * smooth(.3, 1.1, dsc))
            c = mix(c, lin('DDE2E4'), smooth(.80, .73, p.y) * .5)
            cc.append(c)
        cols.append(cc)
    tr = loft(s, 'Thigh feathers ' + sfx, rings, cols, th, end=(path[-1] - V((0, .004, 0)), lin('DDE2E4')))
    set_weights(tr, lambda p: {'torso': .4 * smooth(.88, .96, p.y), th: 1 - .4 * smooth(.88, .96, p.y)})
    # bare legs: orange, scaly
    upper = [V((X(.126), .77, -.028)), V((X(.128), .66, -.048)), V((X(.13), .535, -.075))]
    _, _, rings, dirs = tube_rings(upper, [.041, .038, .036], 14, ref=(0, 0, 1))
    loft(s, 'Leg upper ' + sfx, rings, [[lin(ORANGE) for _ in r] for r in rings], th)
    s.ellipsoid('Leg joint ' + sfx, (X(.13), .52, -.079), (.044, .046, .044), sh, 'F7843A', n=14, m=7, soft=True)
    shin_path = [V((X(.13), .525, -.079)), V((X(.133), .42, -.053)), V((X(.136), .31, -.025)), V((X(.139), .20, .0)), V((X(.141), .11, .018)), V((X(.141), .058, .025))]

    def on_shin(y):
        for a, b in zip(shin_path, shin_path[1:]):
            if b.y <= y <= a.y:
                return a.lerp(b, (a.y - y) / (a.y - b.y))
        return shin_path[0] if y > shin_path[0].y else shin_path[-1]
    # scutes: two rings per scale row (a dark crease, then the lit upper edge of the next scale)
    ys, crease = [], []
    y = .525
    while y > .07:
        ys += [y, y - .0055]; crease += [True, False]
        y -= .029
    ys += [.058, .042]; crease += [False, False]
    sp = [on_shin(v) for v in ys]
    sr = [.038 + (.031 - .038) * (.525 - v) / (.525 - .058) for v in ys]
    _, _, rings, dirs = tube_rings(sp, sr, 14, ref=(0, 0, 1))
    cols = []
    for ring, dd, cr in zip(rings, dirs, crease):
        cc = []
        for d in dd:
            front = d.z
            c = mix(lin(ORANGE), lin('F79A55'), smooth(.2, .9, front) * .5)
            c = mix(c, lin(DEEP), smooth(.1, .9, -front) * .35)
            k = smooth(-.35, .25, front)
            c = tone(c, 1 - .2 * k if cr else 1 + .04 * k)
            cc.append(c)
        cols.append(cc)
    loft(s, 'Leg shin ' + sfx, rings, cols, sh)
    # the shin tape (Gusto's scale cue), hand-wrapped
    for j, y in enumerate([.268, .302, .336]):
        lo_, hi_ = on_shin(y - .012), on_shin(y + .012)
        s.tube('Detail shin wrap %s%d' % (sfx, j), [lo_, hi_], [.0392, .039], sh, TAPE if j != 1 else 'DCD3C0', 'cloth', n=20)
    # foot: heel pad, three webbed front toes with claws, a small hind toe
    s.ellipsoid('Foot heel ' + sfx, (X(.14), .034, .028), (.034, .026, .042), sh, 'F7843A', n=12, m=6)
    toes = [
        [V((X(.14), .031, .04)), V((X(.14), .029, .10)), V((X(.14), .022, .165)), V((X(.14), .013, .212))],
        [V((X(.132), .031, .036)), V((X(.113), .028, .088)), V((X(.096), .021, .138)), V((X(.084), .013, .172))],
        [V((X(.148), .031, .036)), V((X(.167), .028, .088)), V((X(.184), .021, .138)), V((X(.196), .013, .172))],
    ]
    for k, tp in enumerate(toes):
        dense, rr = densify(tp, [.0165, .0145, .0115, .0068], 2)

        def toe_col(t, x, y):
            c = mix(lin(ORANGE), lin(DEEP), (1 - y) * .15)
            band_ = (t * 5.0) % 1.0
            return tone(c, 1 - .14 * smooth(.75, .95, band_))
        vane(s, 'Toe %s%d' % (sfx, k), dense, rr, rr, sh, toe_col, side=(1, 0, 0), n=7)
        tip = tp[-1]; dirn = (tp[-1] - tp[-2]).normalized()
        s.tube('Detail claw %s%d' % (sfx, k), [tip - dirn * .004, tip + dirn * .008 - V((0, .002, 0)), tip + dirn * .017 - V((0, .007, 0))],
               [.0058, .0045, .0006], sh, '3B302C', 'shell', n=8)
    hind = [V((X(.14), .03, .02)), V((X(.14), .024, -.02)), V((X(.14), .016, -.042))]
    vane(s, 'Toe %s hind' % sfx, hind, [.012, .010, .005], [.012, .010, .005], sh, lambda t, x, y: lin(ORANGE), side=(1, 0, 0), n=8)
    s.tube('Detail claw %s hind' % sfx, [hind[-1], hind[-1] + V((0, -.004, -.011))], [.005, .0006], sh, '3B302C', 'shell', n=8)
    # webs between the front toes: thin membranes with a concave front edge
    for k, (a_i, b_i) in enumerate([(1, 0), (0, 2)]):
        A = [V(q) for q in densify(toes[a_i], [0] * 4, 3)[0]]; B = [V(q) for q in densify(toes[b_i], [0] * 4, 3)[0]]
        rows_, M = 5, 5
        top, bot = [], []
        for r in range(rows_):
            for m in range(M):
                v = m / (M - 1)
                reach = (r / (rows_ - 1)) * (.78 - .3 * math.sin(math.pi * v))
                ia = reach * (len(A) - 1); ib = reach * (len(B) - 1)
                pa = A[int(ia)].lerp(A[min(len(A) - 1, int(ia) + 1)], ia - int(ia))
                pb = B[int(ib)].lerp(B[min(len(B) - 1, int(ib) + 1)], ib - int(ib))
                p = pa.lerp(pb, v) - V((0, .004 + .002 * math.sin(math.pi * v), 0))
                top.append(p + V((0, .0018, 0))); bot.append(p - V((0, .0018, 0)))
        verts = top + bot
        faces = []
        nb = rows_ * M
        for r in range(rows_ - 1):
            for m in range(M - 1):
                q = r * M + m
                faces.append((q, q + 1, q + M + 1, q + M))
                faces.append((nb + q, nb + q + M, nb + q + M + 1, nb + q + 1))
        edge = [r * M for r in range(rows_)] + [(rows_ - 1) * M + m for m in range(1, M)] + [r * M + M - 1 for r in range(rows_ - 2, -1, -1)] + [m for m in range(M - 2, 0, -1)]
        for e0, e1 in zip(edge, edge[1:] + edge[:1]):
            faces.append((e0, e1, nb + e1, nb + e0))
        make(s, 'Detail web %s%d' % (sfx, k), verts, faces, sh, [lin('F49A5C')] * len(verts), 'skin')


# ---- the KO piece: a plucked trio of tail feathers (the creature's gore_piece rides the tail) -------
def gore(s):
    for k in range(3):
        a = (k - 1) * .38
        D = V((math.sin(a) * .55, math.cos(a), .12)).normalized()
        L = .11 - .015 * abs(k - 1)
        pts = [D * (L * q) + V(((k - 1) * .006, 0, 0)) for q in (0, .3, .65, 1.0)]

        def colf(t, x, y, k=k):
            c = mix(lin('D5DDE2'), lin(WHITE), smooth(.0, .45, t))
            if k != 1:
                c = mix(c, lin(INK), smooth(.72, .9, t))          # the streamers' black tips
            return c
        vane(s, 'Gore feather %d' % k, pts, [.005, .016, .013, .002], [.004, .0035, .003, .0012], None, colf,
             side=(1, 0, 0), n=6, camber=.002, role='gore')


# ---- diagnostics -----------------------------------------------------------------------------------
def report(s):
    rows = []
    tris = 0
    for o in s.collection.objects:
        if o.type != 'MESH' or o.get('cw_role') not in ('body', 'gore'):
            continue
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
        if o.get('cw_role') != 'body':
            continue
        worst = max(env(s, V((v.co.x, v.co.z, -v.co.y))) for v in o.data.vertices)
        rows.append((worst, o.name))
    rows.sort(reverse=True)
    print('GUSTO triangles (body+gore) %d' % tris)
    soft = ('Feather', 'Detail feather', 'Pompadour')
    for w, n in [r for r in rows if r[1].startswith(soft)][:8]:
        print('ENVELOPE soft %-34s %5.1f cm' % (n, w * 100))
    for w, n in [r for r in rows if not r[1].startswith(soft)][:16]:
        print('ENVELOPE hard %-34s %5.1f cm' % (n, w * 100))


def build(s):
    body(s)
    head(s)
    for side, sfx in ((1, 'l'), (-1, 'r')):
        wing(s, side, sfx)
        scapulars(s, side, sfx)
        leg(s, side, sfx)
    tail(s)
    gore(s)
    report(s)
    s.set_look({'glow_mode': 'shimmer', 'fx': {'pupil_reach': .007, 'jaw_deg': 16, 'brow_drop': .008, 'lid_rest': .45,
                                                'spring_gain': .7, 'spring_stiffness': 1.1}})
    s.bake_ao(rays=14, distance=.085, strength=.36)
