"""Varga, the Cage Rules Guest: the v0.9.17 default skin (docs/ART_REVAMP.md "v0.9.17").

A new Blender builder written from scratch on Varga's locked Cage Rules body. The original imported
procedural model is NOT built here: it stays byte for byte in f_varga_legacy.glb (Settings ->
"Legacy Varga skin"); build_creatures.py refuses to export over it.

Identity kept: a bearded, dark-haired human martial artist in red fight shorts with gold trim, black
gloves and bare feet. Upgraded into the cast's chunky, outlined cartoon style:
  * anatomy as shaped volumes: one continuous torso surface (pecs, six-pack, serratus, lats, traps,
    spine, shoulder blades), deltoid caps, biceps/triceps, chunky forearms, quads with knee caps,
    diamond calves; painted two-tone shading (lit muscle crests, dark creases);
  * a rigged face: amber eyes with lids (fx_eye / fx_lid), heavy expressive brows (fx_brow_l/r), a
    bearded jaw that drops on effort and kiai (fx_jaw; mouth interior and teeth behind it), a
    boxer's nose and cauliflower ears;
  * the fight-camera silhouette (high and behind): a dark topknot whose tail swings on springs
    (fx_spring_hair_0..1), the team-tinted headband (team material), broad traps and shoulders,
    hand-wrap ends trailing from the wrists on springs (fx_spring_wrap_l/r + _1 links);
  * costume: red fight shorts with gold side stripes, gold hems and a black, gold-piped waistband
    with a riveted copper buckle; black fingerless gloves over cream hand wraps (padded knuckles,
    bare finger ends and thumbs); bare feet with toes and white ankle tape;
  * the Scrap accent (the v0.9.18 fighting-type direction): copper tattoo bands with rivets on the
    shoulders and forearms that glow with Hype (glow mode 'pulse').
Hard parts stay on the collision bodies (within a few cm); hair, beard and wrap tails are soft.
Coordinates: fighter rest space (+Z forward, +Y up, +X = Varga's LEFT), metres.
"""
import math
from mathutils import Vector
from mesh_tools import rgba
from fighters_v17 import mix, _interp, ring

TAU = math.tau
PI = math.pi

# ---- palette (sRGB hex) -------------------------------------------------------------------------
SKIN = 'D7976A'; SKIN_LIGHT = 'EEB88A'; SKIN_SHADE = 'A8603E'; SKIN_DEEP = '7E4129'
LIP = 'A9574A'; MOUTH = '3B1A1D'; TEETH = 'F3EEE2'
HAIR = '241915'; HAIR_HI = '4A3328'; HAIR_FADE = '5A4234'
RED = 'C42B34'; RED_SHADE = '84182A'; RED_LIGHT = 'E0484A'
GOLD = 'E3B23C'
BAND = '25222B'
GLOVE = '1E1C23'; GLOVE_HI = '3A3742'
WRAP = 'EDE3CB'
TAPE = 'F2EEE2'
COPPER = 'E8772C'; COPPER_HI = 'FFB066'; COPPER_PLATE = 'B8652F'
IRIS = 'C27A2E'
SIDES = ((1, 'l'), (-1, 'r'))


# ---- small maths ----------------------------------------------------------------------------------
def sstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def plateau(x, a, b, soft):
    return sstep(a - soft, a + soft, x) * (1.0 - sstep(b - soft, b + soft, x))


def gauss(u, w):
    return math.exp(-(u / w) ** 2)


def wrapa(a):
    return (a + PI) % TAU - PI


def sup(th, a, df, db, p):
    """Superellipse cross-section (half width a, front depth df, back depth db, exponent p) at
    parameter th (0 = front/+Z, +pi/2 = +X). Returns x, z and the outward unit normal (nx, nz)."""
    s_, c_ = math.sin(th), math.cos(th)
    e = 2.0 / p
    x = a * math.copysign(abs(s_) ** e, s_)
    d = df if c_ >= 0 else db
    z = d * math.copysign(abs(c_) ** e, c_)
    gx = (abs(x) / a) ** (p - 1) / a * (1 if x >= 0 else -1) if a > 1e-6 else 0.0
    gz = (abs(z) / d) ** (p - 1) / d * (1 if z >= 0 else -1) if d > 1e-6 else 0.0
    L = math.hypot(gx, gz) or 1.0
    return x, z, gx / L, gz / L


def normal_of(fn, phi, y, eps=.0015):
    """Outward 3D normal of a parametric surface fn(phi, y) -> point (numerical)."""
    du = Vector(fn(phi + .01, y)) - Vector(fn(phi - .01, y))
    dv = Vector(fn(phi, y + eps)) - Vector(fn(phi, y - eps))
    n = du.cross(dv)
    if n.length < 1e-9:
        return Vector((0, 1 if y > 1.0 else -1, 0))
    n.normalize()
    return n


def lcol(hex_color):
    """Linear RGB (3-tuple) of an sRGB hex colour."""
    return tuple(rgba(hex_color)[:3])


def cmix(a, b, t):
    return mix(a, b, t)


def ip(xs, vs, x):
    """Piecewise-linear interpolation that accepts ascending or descending xs (clamped)."""
    if xs[0] > xs[-1]:
        xs = xs[::-1]; vs = vs[::-1]
    return _interp(xs, vs, x)


# ---- mesh helpers ---------------------------------------------------------------------------------
def grid(s, name, rows, bone, mat='skin', color='FFFFFF', glow=0, soft=False, role='body', caps=(True, True), wrap_rows=False, smooth=True):
    """Quads between consecutive rings (each a closed loop of the same length); optional fan caps,
    or wrap the last ring back to the first (a torus-like band)."""
    m = len(rows); n = len(rows[0])
    verts = [tuple(p) for r in rows for p in r]
    faces = []
    for j in range(m if wrap_rows else m - 1):
        j2 = (j + 1) % m
        for i in range(n):
            i2 = (i + 1) % n
            faces.append((j * n + i, j * n + i2, j2 * n + i2, j2 * n + i))
    if not wrap_rows:
        if caps[0]:
            c = Vector((0, 0, 0))
            for p in rows[0]:
                c += Vector(p)
            verts.append(tuple(c / n)); k = len(verts) - 1
            for i in range(n):
                faces.append((k, (i + 1) % n, i))
        if caps[1]:
            c = Vector((0, 0, 0))
            for p in rows[-1]:
                c += Vector(p)
            verts.append(tuple(c / n)); k = len(verts) - 1
            for i in range(n):
                faces.append((k, (m - 1) * n + i, (m - 1) * n + (i + 1) % n))
    return s.mesh(name, verts, faces, bone, color, mat, glow, soft, role, smooth)


def superellipsoid(s, name, c, r, p, bone, color, mat='skin', n=16, m=10, glow=0, soft=False):
    """A rounded box (|x/rx|^p + |y/ry|^p + |z/rz|^p = 1) with exact poles: padded gloves, plates."""
    e = 2.0 / p

    def f(t):
        return math.copysign(abs(t) ** e, t)
    verts = [(c[0], c[1] - r[1], c[2])]
    for j in range(1, m):
        v = -PI / 2 + PI * j / m
        for i in range(n):
            u = TAU * i / n
            verts.append((c[0] + r[0] * f(math.cos(v) * math.sin(u)), c[1] + r[1] * f(math.sin(v)), c[2] + r[2] * f(math.cos(v) * math.cos(u))))
    verts.append((c[0], c[1] + r[1], c[2])); top = len(verts) - 1
    faces = [(0, 1 + (i + 1) % n, 1 + i) for i in range(n)]
    for j in range(m - 2):
        for i in range(n):
            a = 1 + j * n + i; b = 1 + j * n + (i + 1) % n
            faces.append((a, b, b + n, a + n))
    faces += [(top, 1 + (m - 2) * n + i, 1 + (m - 2) * n + (i + 1) % n) for i in range(n)]
    return s.mesh(name, verts, faces, bone, color, mat, glow, soft)


def paint_idx(obj, fn):
    """fn(index, fighter_pos, fighter_normal, rgba) -> rgba (linear)."""
    attr = obj.data.color_attributes['Color']
    for v in obj.data.vertices:
        p = Vector((v.co.x, v.co.z, -v.co.y)); nrm = Vector((v.normal.x, v.normal.z, -v.normal.y))
        attr.data[v.index].color = fn(v.index, p, nrm, tuple(attr.data[v.index].color))


def blend_groups(obj, a, b, wfn):
    """Split the vertices between bone groups a and b: weight of b = wfn(fighter position)."""
    ga = obj.vertex_groups[a]
    gb = obj.vertex_groups.get(b) or obj.vertex_groups.new(name=b)
    for v in obj.data.vertices:
        w = max(0.0, min(1.0, wfn((v.co.x, v.co.z, -v.co.y))))
        ga.add([v.index], 1.0 - w, 'REPLACE'); gb.add([v.index], w, 'REPLACE')


def strip(s, name, pts, normals, width, bone, color, mat='skin', glow=0, lift=.0016, depth=.003, closed=False, role='body'):
    """A thin closed slab along a path (wrist wraps, cloth tails): the band has some thickness and is
    visible from both sides. pts/normals: path points and the normal of the band's flat face there;
    width: float or per point."""
    m = len(pts)
    widths = width if isinstance(width, (list, tuple)) else [width] * m
    verts = []
    for i in range(m):
        P = Vector(pts[i]); N = Vector(normals[i]).normalized()
        if closed:
            T = Vector(pts[(i + 1) % m]) - Vector(pts[(i - 1) % m])
        else:
            T = Vector(pts[min(i + 1, m - 1)]) - Vector(pts[max(i - 1, 0)])
        T = (T - N * T.dot(N)).normalized()
        B = N.cross(T).normalized()
        w = widths[i] / 2
        for bw, nh in ((1, lift), (-1, lift), (-1, -depth), (1, -depth)):
            verts.append(tuple(P + B * (bw * w) + N * nh))
    faces = []
    for i in range(m if closed else m - 1):
        i2 = (i + 1) % m
        for k in range(4):
            faces.append((i * 4 + k, i * 4 + (k + 1) % 4, i2 * 4 + (k + 1) % 4, i2 * 4 + k))
    if not closed:
        faces.append((3, 2, 1, 0)); faces.append(tuple((m - 1) * 4 + k for k in range(4)))
    return s.mesh(name, verts, faces, bone, color, mat, glow, False, role, False)


def decal(s, name, pts, normals, width, bone, color, mat='skin', glow=0, lift=.0014, closed=False):
    """A flat single-sided band lying just above a surface (two vertices per path point): crisp
    painted-on detail (tattoo line, stripe, tape) at 2 triangles per step. Faces are turned to look
    along the surface normal after the mesh is built."""
    import bmesh
    m = len(pts)
    widths = width if isinstance(width, (list, tuple)) else [width] * m
    verts = []
    for i in range(m):
        P = Vector(pts[i]); N = Vector(normals[i]).normalized()
        if closed:
            T = Vector(pts[(i + 1) % m]) - Vector(pts[(i - 1) % m])
        else:
            T = Vector(pts[min(i + 1, m - 1)]) - Vector(pts[max(i - 1, 0)])
        T = (T - N * T.dot(N)).normalized()
        B = N.cross(T).normalized()
        w = widths[i] / 2
        verts.append(tuple(P + B * w + N * lift)); verts.append(tuple(P - B * w + N * lift))
    faces = [(i * 2, i * 2 + 1, ((i + 1) % m) * 2 + 1, ((i + 1) % m) * 2) for i in range(m if closed else m - 1)]
    obj = s.mesh(name, verts, faces, bone, color, mat, glow, False, 'body', False)
    bm = bmesh.new(); bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    flip = []
    for f in bm.faces:
        want = Vector((0, 0, 0))
        for v in f.verts:
            nn = Vector(normals[v.index // 2])
            want += Vector((nn.x, -nn.z, nn.y))      # fighter -> Blender axes
        if f.normal.dot(want) < 0:
            flip.append(f)
    if flip:
        bmesh.ops.reverse_faces(bm, faces=flip)
    bm.to_mesh(obj.data); bm.free(); obj.data.update()
    return obj


def surface_path(fn, path, step=.006, closed=False):
    """Densify a (phi, y) polyline on a parametric surface: points and normals."""
    ctrl = list(path) + ([path[0]] if closed else [])
    pts, nrm = [], []
    for k in range(len(ctrl) - 1):
        (p0, y0), (p1, y1) = ctrl[k], ctrl[k + 1]
        L = (Vector(fn(p1, y1)) - Vector(fn(p0, y0))).length
        q = max(1, int(L / step))
        for j in range(q):
            t = j / q
            ph, y = p0 + (p1 - p0) * t, y0 + (y1 - y0) * t
            pts.append(fn(ph, y)); nrm.append(normal_of(fn, ph, y))
    if not closed:
        ph, y = ctrl[-1]
        pts.append(fn(ph, y)); nrm.append(normal_of(fn, ph, y))
    return pts, nrm


def surface_lap(fn_d, phi, y, dp=.05, dy=.006):
    """Concavity of a displacement field (positive in creases): drives the painted shading."""
    c = fn_d(phi, y)
    return (fn_d(phi + dp, y) + fn_d(phi - dp, y) - 2 * c) / 2 + (fn_d(phi, y + dy) + fn_d(phi, y - dy) - 2 * c) / 2


# ---- the torso: one continuous surface (pelvis -> chest -> traps) ---------------------------------
T_Y = [.94, .99, 1.04, 1.09, 1.14, 1.19, 1.24, 1.29, 1.34, 1.39, 1.43, 1.47, 1.50, 1.525, 1.55, 1.57, 1.588, 1.602]
T_A = [.165, .158, .152, .152, .158, .168, .179, .19, .2, .209, .214, .216, .212, .198, .17, .128, .085, .045]
T_DF = [.112, .108, .106, .108, .112, .116, .12, .123, .125, .125, .121, .114, .104, .09, .074, .06, .049, .032]
T_DB = [.122, .11, .103, .101, .103, .107, .111, .115, .118, .12, .121, .12, .116, .106, .091, .075, .06, .036]
T_P = [2.2, 2.1, 2.0, 2.0, 2.05, 2.15, 2.25, 2.35, 2.45, 2.5, 2.5, 2.45, 2.35, 2.25, 2.1, 2.0, 2.0, 2.0]
T_CZ = [0, 0, 0, .002, .004, .006, .008, .01, .01, .01, .008, .005, 0, -.004, -.008, -.01, -.01, -.008]


def torso_d(phi, y):
    """Muscle relief of the torso (metres along the outward normal)."""
    phi = wrapa(phi)
    ap = abs(phi)
    d = 0.0
    # pecs: full plates whose lower edge sweeps up toward the armpits, split at the sternum
    lo = 1.334 + .055 * sstep(.25, 1.05, ap)
    pec = sstep(lo - .003, lo + .013, y) * (1 - sstep(1.45, 1.515, y)) * sstep(.035, .13, ap) * (1 - sstep(.8, 1.15, ap))
    d += .022 * pec * (1.0 - .35 * sstep(lo + .02, 1.5, y))
    # six-pack: three rows either side of the linea alba
    if ap < .55 and 1.1 < y < 1.33:
        col = plateau(ap, .04, .34, .022)
        ab = 0.0
        for r0, r1 in ((1.262, 1.318), (1.199, 1.252), (1.137, 1.19)):
            ab = max(ab, plateau(y, r0, r1, .007))
        d += .011 * ab * col
    # obliques and the belt line above the waistband
    d += .007 * gauss(ap - 1.2, .3) * plateau(y, 1.1, 1.2, .03)
    # serratus fingers
    for k, yy in enumerate((1.305, 1.268, 1.231)):
        d += .005 * gauss(ap - (1.22 + .04 * k), .09) * gauss(y - yy, .011)
    # lats: the V from behind
    d += .02 * gauss(ap - 2.0, .42) * plateau(y, 1.25, 1.45, .045)
    # spine groove between the erectors, shoulder blades, traps
    d -= .008 * gauss(ap - PI, .09) * plateau(y, 1.12, 1.53, .03)
    d += .009 * gauss(ap - (PI - .28), .12) * plateau(y, 1.1, 1.3, .04)
    d += .011 * gauss(ap - 2.5, .28) * plateau(y, 1.36, 1.47, .025)
    d += .013 * sstep(1.4, 2.3, ap) * plateau(y, 1.475, 1.585, .02)
    # navel
    d -= .006 * gauss(ap, .05) * gauss(y - 1.107, .007)
    return d


def torso_point(phi, y, lift=0.0):
    a = _interp(T_Y, T_A, y); df = _interp(T_Y, T_DF, y); db = _interp(T_Y, T_DB, y)
    p = _interp(T_Y, T_P, y); cz = _interp(T_Y, T_CZ, y)
    x, z, nx, nz = sup(phi, a, df, db, p)
    d = torso_d(phi, y) + lift
    return (x + nx * d, y, cz + z + nz * d)


# ---- the head: skull and face (the mouth area recessed behind the jaw piece) ----------------------
H_Y = [1.582, 1.59, 1.6, 1.612, 1.628, 1.645, 1.662, 1.68, 1.70, 1.72, 1.74, 1.76, 1.778, 1.794, 1.806, 1.815, 1.821, 1.826]
H_A = [.04, .066, .08, .088, .095, .1, .104, .106, .107, .107, .104, .097, .087, .075, .061, .045, .03, .008]
H_DF = [.05, .07, .078, .084, .09, .097, .102, .106, .108, .108, .105, .098, .088, .075, .061, .045, .03, .008]
H_DB = [.03, .042, .052, .062, .074, .087, .098, .106, .111, .112, .109, .101, .088, .074, .057, .041, .028, .008]
H_P = [2.5, 2.7, 2.85, 2.85, 2.7, 2.5, 2.3, 2.2, 2.2, 2.15, 2.1, 2.05, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0]
H_CZ = [.019, .02, .02, .018, .014, .01, .006, .004, .002, 0, -.002, -.004, -.006, -.007, -.008, -.008, -.008, -.008]
EYE_Y = 1.706; EYE_X = .046
JAW_HINGE = (0, 1.676, -.016)


def head_d(phi, y):
    phi = wrapa(phi)
    ap = abs(phi)
    d = .006 * gauss(ap - .36, .4) * gauss(y - 1.73, .009)            # brow ridge
    d -= .006 * gauss(ap - .39, .15) * gauss(y - EYE_Y, .013)         # eye sockets
    d += .006 * gauss(ap - .86, .22) * gauss(y - 1.688, .013)         # cheekbones
    d += .004 * gauss(ap - 1.25, .2) * gauss(y - 1.635, .02)          # masseters
    d -= .003 * gauss(ap - 1.25, .2) * gauss(y - 1.745, .012)         # temples
    return d


def mouth_recess(phi, y):
    return .026 * (1 - sstep(.42, .62, abs(wrapa(phi)))) * (1 - sstep(1.636, 1.651, y))


def head_point(phi, y, lift=0.0, recess=True):
    a = _interp(H_Y, H_A, y); df = _interp(H_Y, H_DF, y); db = _interp(H_Y, H_DB, y)
    p = _interp(H_Y, H_P, y); cz = _interp(H_Y, H_CZ, y)
    x, z, nx, nz = sup(phi, a, df, db, p)
    d = head_d(phi, y) + lift - (mouth_recess(phi, y) if recess else 0.0)
    return (x + nx * d, y, cz + z + nz * d)


def head_skin(phi, y):
    return head_point(phi, y, recess=False)


def neck_point(phi, y):
    a = _interp([1.48, 1.56, 1.62, 1.665], [.078, .074, .07, .066], y)
    df = _interp([1.48, 1.56, 1.62, 1.665], [.07, .068, .068, .06], y)
    db = _interp([1.48, 1.56, 1.62, 1.665], [.074, .072, .07, .064], y)
    x, z, nx, nz = sup(phi, a, df, db, 2.2)
    # the sternocleidomastoid cords, from behind the ear down to the collar bone
    yy = (y - 1.48) / .18
    cord = .006 * gauss(abs(wrapa(phi)) - (.55 + .7 * yy), .2) * plateau(y, 1.5, 1.64, .02)
    cz = -.006 + .01 * sstep(1.55, 1.66, y)
    return (x + nx * cord, y, cz + z + nz * cord)


# The hair and the beard are edge-following surfaces: their rows run along the hairline / beard line,
# so those edges are clean curves (tucked under the skin), never ring-aligned stair steps.
HL_P = [0, .5, .8, 1.15, 1.45, 1.75, 2.1, 2.5, PI + .01]
HL_Y = [1.768, 1.765, 1.756, 1.729, 1.717, 1.713, 1.686, 1.656, 1.649]
HAIR_TOP = 1.826
HAIR_V = [0, .025, .07, .13, .21, .31, .42, .54, .66, .78, .89, .96, 1.0]


def hairline(phi):
    return _interp(HL_P, HL_Y, abs(wrapa(phi)))


def hair_thick(phi, y):
    ap = abs(wrapa(phi))
    return .0042 + .0095 * sstep(1.752, 1.79, y) + .004 * sstep(1.9, 2.8, ap) * sstep(1.735, 1.8, y)


def hair_t(phi, y):
    """Hair thickness over the skin at (phi, y); negative (under the skin) below the hairline."""
    yh = hairline(phi)
    m = sstep(yh - .003, yh + .01, y)
    return m * hair_thick(phi, y) - (1 - m) * .006


def hair_uv(phi, v):
    yh = hairline(phi)
    y = yh + (HAIR_TOP - yh) * v
    e = sstep(0.0, .07, v)
    t = e * hair_thick(phi, y) - (1 - e) * .005
    return tuple(Vector(head_skin(phi, y)) + normal_of(head_skin, phi, y) * t)


def beard_ref(phi, y):
    """The skin the beard grows on: the face (no recess) and, below the chin, the jaw underside
    running back into the neck."""
    if y >= 1.6:
        return head_skin(phi, y)
    t = max(0.0, min(1.0, (y - 1.562) / .038))
    return tuple(Vector(neck_point(phi, 1.562)).lerp(Vector(head_skin(phi, 1.6)), t))


BEARD_PM = 2.05
BT_P = [0, .3, .5, .8, 1.1, 1.3, 1.46, 1.6, 1.8, 2.06]
BT_Y = [1.633, 1.637, 1.646, 1.664, 1.684, 1.711, 1.721, 1.69, 1.655, 1.635]
BB_P = [0, .5, 1.0, 1.5, 2.06]
BB_Y = [1.563, 1.569, 1.582, 1.598, 1.616]
BEARD_V = [0, .05, .12, .24, .38, .52, .66, .79, .9, .96, 1.0]


def beard_uv(u, v, inner=False):
    phi = u * BEARD_PM
    ap = abs(phi)
    yt = _interp(BT_P, BT_Y, ap); yb = _interp(BB_P, BB_Y, ap)
    y = yb + (yt - yb) * v
    e = sstep(0, .1, v) * sstep(1, .93, v) * sstep(1, .8, abs(u))
    thick = _interp([0, .35, .7, 1.0, 1.4, 1.75, 2.06], [.0115, .0108, .0082, .006, .0045, .004, .0035], ap) + .0015 * gauss(ap, .4) * (1 - sstep(.0, .5, v))
    t = -.009 if inner else e * thick - (1 - e) * .005
    return tuple(Vector(beard_ref(phi, y)) + normal_of(beard_ref, phi, y) * t)


def shell_patch(s, name, outer, inner, bone, mat='skin', color='FFFFFF'):
    """A closed thin shell from two (v rows x u columns) grids: the visible outer sheet and a hidden
    inner sheet, stitched along all four borders."""
    nv = len(outer); nu = len(outer[0])
    verts = [tuple(p) for row in outer for p in row] + [tuple(p) for row in inner for p in row]
    off = nv * nu
    faces = []
    for j in range(nv - 1):
        for i in range(nu - 1):
            a, b, c, d = j * nu + i, j * nu + i + 1, (j + 1) * nu + i + 1, (j + 1) * nu + i
            faces.append((a, b, c, d))
            faces.append((off + d, off + c, off + b, off + a))
    for j in range(nv - 1):
        for i in (0, nu - 1):
            a, d = j * nu + i, (j + 1) * nu + i
            faces.append((a, d, off + d, off + a))
    for i in range(nu - 1):
        for j in (0, nv - 1):
            a, b = j * nu + i, j * nu + i + 1
            faces.append((a, b, off + b, off + a))
    return s.mesh(name, verts, faces, bone, color, mat)


# ---- limbs: vertical surfaces round a segment axis (phi = 0 front, +pi/2 = the OUTER side) ---------
class Limb:
    def __init__(self, cx, side, ys, rs, bumps, cz=None):
        pairs = sorted(zip(ys, rs))
        self.cx, self.side, self.bumps = cx, side, bumps
        self.ys = [p[0] for p in pairs]; self.rs = [p[1] for p in pairs]
        self.cz = cz or (lambda y: 0.0)

    def r(self, phi, y):
        return _interp(self.ys, self.rs, y) + self.bumps(wrapa(phi), y)

    def point(self, phi, y, lift=0.0):
        r = self.r(phi, y) + lift
        return (self.cx + self.side * math.sin(phi) * r, y, self.cz(y) + math.cos(phi) * r)

    def rings(self, ys, n):
        return [[self.point(TAU * i / n, y) for i in range(n)] for y in ys]


def limb_mesh(s, name, limb, ys, n, bone, soft=True, mat='skin'):
    return grid(s, name, limb.rings(ys, n), bone, mat, soft=soft)


def upper_arm_bumps(phi, y):
    phi = wrapa(phi)
    ap = abs(phi)
    d = 0.0
    # deltoid: a cap over the shoulder whose V reaches lowest on the outer side
    low = 1.452 - .06 * gauss(phi - PI / 2, .5)
    d += .0155 * plateau(y, low, 1.56, .01)
    # biceps (front) and the triceps horseshoe (back), split by a groove on the outer side
    d += .016 * gauss(phi, .65) * plateau(y, 1.275, 1.405, .028)
    d += .014 * gauss(ap - PI, .75) * plateau(y, 1.285, 1.44, .03)
    d -= .004 * gauss(phi - PI / 2, .22) * plateau(y, 1.27, 1.39, .02)
    # flatter toward the body
    d -= .006 * gauss(phi + PI / 2, .55) * plateau(y, 1.3, 1.5, .04)
    return d


def forearm_bumps(phi, y):
    phi = wrapa(phi)
    ap = abs(phi)
    d = .013 * gauss(phi - .9, .6) * plateau(y, 1.07, 1.19, .03)     # brachioradialis / extensors
    d += .007 * gauss(phi + 1.0, .6) * plateau(y, 1.05, 1.17, .03)   # flexors
    d += .006 * gauss(ap - PI, .4) * gauss(y - 1.214, .016)           # elbow point
    return d


def thigh_bumps(phi, y):
    phi = wrapa(phi)
    ap = abs(phi)
    d = .01 * gauss(phi, .8) * plateau(y, .45, .66, .04)               # quads
    d += .012 * gauss(phi + .75, .38) * gauss(y - .458, .03)          # vastus medialis teardrop
    d += .008 * gauss(phi - 1.2, .5) * plateau(y, .5, .66, .04)       # vastus lateralis
    d += .006 * gauss(ap - PI, .9) * plateau(y, .5, .67, .05)         # hamstrings
    d += .009 * gauss(phi, .33) * gauss(y - .396, .017)               # knee cap
    d -= .004 * gauss(phi, .5) * gauss(y - .418, .006)                # crease above it
    return d


def shin_bumps(phi, y):
    phi = wrapa(phi)
    pb = wrapa(phi - PI)          # 0 at the back, + toward the outer side
    d = .021 * gauss(pb - .45, .42) * plateau(y, .215, .335, .04)     # outer calf head
    d += .024 * gauss(pb + .45, .42) * plateau(y, .19, .32, .045)     # inner calf head (lower, fuller)
    d -= .005 * gauss(pb, .3) * plateau(y, -.03, .12, .03)            # achilles
    d += .004 * gauss(phi + .15, .25) * plateau(y, .02, .34, .05)     # tibia ridge
    d += .006 * gauss(abs(phi) - PI / 2, .3) * gauss(y - (-.073), .014)          # ankle bones
    return d


def skin_painter(dfield, base=SKIN, strength=1.0):
    """Two-tone painted anatomy: lit crests on the muscles, darker creases, a cooler underside."""
    b = lcol(base); hi = lcol(SKIN_LIGHT); sh = lcol(SKIN_SHADE); deep = lcol(SKIN_DEEP)

    def fn(phi, y, n):
        d = dfield(phi, y)
        lap = surface_lap(dfield, phi, y)
        crest = max(0.0, min(1.0, d / .016)) * max(0.0, -lap) / .002
        crease = max(0.0, min(1.0, lap / .0018))
        c = cmix(b, hi, min(.55, .25 * max(0.0, d / .012) + .45 * min(1.0, crest)) * strength)
        c = cmix(c, sh, min(.7, crease * .7) * strength)
        c = cmix(c, sh, max(0.0, -n.y - .25) * .45)
        if crease > .9:
            c = cmix(c, deep, (crease - .9) * 1.2)
        return c
    return fn


# ==================================================================================================
def _ys(top, bottom, step):
    n = max(2, int(round((top - bottom) / step)))
    return [top - (top - bottom) * k / n for k in range(n + 1)]


def _paint_grid(obj, params, painter, fallback=SKIN):
    fb = lcol(fallback)
    paint_idx(obj, lambda i, p, n, c: (*(painter(*params[i], n) if i < len(params) else fb), c[3]))


def _torso(s):
    n = 32
    ys = _ys(1.602, .995, .02)[::-1]
    torso = grid(s, 'Body - torso', [[torso_point(TAU * i / n, y) for i in range(n)] for y in ys], 'chest')
    blend_groups(torso, 'chest', 'pelvis', lambda p: 1 - sstep(1.04, 1.16, p[1]))
    _paint_grid(torso, [(TAU * i / n, y) for y in ys for i in range(n)], skin_painter(torso_d))
    ys_n = _ys(1.665, 1.48, .02)[::-1]
    neck = grid(s, 'Neck', [[neck_point(TAU * i / 24, y) for i in range(24)] for y in ys_n], 'head')
    blend_groups(neck, 'head', 'chest', lambda p: 1 - sstep(1.515, 1.6, p[1]))
    s.paint(neck, lambda p, n, c: (*cmix(lcol(SKIN), lcol(SKIN_SHADE), max(0.0, -n.y) * .5 + .15 * (1 - sstep(1.5, 1.6, p.y))), c[3]))


def _head(s):
    view = s.view_bone
    n = 36
    ys = sorted(set([round(y, 4) for y in _ys(1.70, 1.582, .009) + _ys(1.826, 1.70, .021)]))
    head = grid(s, 'Head', [[head_point(TAU * i / n, y) for i in range(n)] for y in ys], 'head')
    params = [(TAU * i / n, y) for y in ys for i in range(n)]
    hp = skin_painter(head_d, strength=.7)

    def head_paint(ph, y, nn):
        col = hp(ph, y, nn)
        rec = mouth_recess(ph, y)
        if rec > .006:
            col = cmix(col, lcol(MOUTH), min(1.0, rec / .015))
        # a warm flush high on the cheeks
        return cmix(col, lcol('C97E5A'), .3 * gauss(abs(wrapa(ph)) - .85, .3) * gauss(y - 1.676, .012))
    _paint_grid(head, params, head_paint)

    # nose: a broad boxer's nose with a slight crook
    s.tube('Detail nose bridge', [(0, 1.728, .1), (.002, 1.705, .111), (.003, 1.685, .12)], [.009, .0108, .0122], 'head', SKIN, n=12)
    s.ellipsoid('Detail nose tip', (.002, 1.6745, .1235), (.0142, .0126, .013), 'head', 'D28A62', n=14, m=7)
    for side in (1, -1):
        s.ellipsoid('Detail nose wing %d' % side, (side * .0132 + .001, 1.668, .1145), (.0098, .0082, .0092), 'head', 'CF875F', n=10, m=5)
        s.ellipsoid('Detail nostril %d' % side, (side * .0072 + .001, 1.6632, .1205), (.0046, .0025, .0038), 'head', '4A2620', n=8, m=4)
    # ears (cauliflowered)
    for side in (1, -1):
        s.ellipsoid('Ear %d' % side, (side * .112, 1.69, -.009), (.012, .029, .021), 'head', 'D08F64', n=12, m=7)
        s.ellipsoid('Ear lump %d' % side, (side * .117, 1.703, -.006), (.008, .012, .011), 'head', 'D9996C', n=8, m=5)
        s.ellipsoid('Detail ear hollow %d' % side, (side * .1215, 1.686, -.006), (.0035, .015, .01), 'head', '8E5034', n=8, m=5)

    # eyes (rigged lids and pupils), heavy brows on their own bones
    for side, suffix in SIDES:
        s.rig_eye('Eye ' + suffix, (side * EYE_X, EYE_Y, .0895), (.019, .0128, .0085), 'head', suffix, iris=IRIS, lid_color='C3845A')
        brow = view('fx_brow_' + suffix, 'head', (side * .047, 1.729, .1))
        s.tube('Detail brow ' + suffix, [(side * .012, 1.7205, .1075), (side * .029, 1.7275, .1098), (side * .052, 1.732, .1068), (side * .074, 1.729, .0945)],
               [.0078, .0104, .0096, .0056], brow, HAIR, 'cloth', n=8)

    # mouth: interior, upper teeth and mustache stay on the head
    s.ellipsoid('Mouth interior', (0, 1.628, .084), (.03, .021, .021), 'head', MOUTH, n=14, m=7)
    s.tube('Detail upper teeth', [(-.018, 1.6395, .0965), (0, 1.6415, .101), (.018, 1.6395, .0965)], [.0045, .0049, .0045], 'head', TEETH, 'shell', n=6)
    s.tube('Detail mustache', [(-.043, 1.625, .092), (-.035, 1.637, .104), (-.018, 1.6465, .1135), (0, 1.6485, .1165), (.018, 1.6465, .1135), (.035, 1.637, .104), (.043, 1.625, .092)],
           [.006, .0085, .0098, .0098, .0098, .0085, .006], 'head', HAIR, 'cloth', n=8)

    # the jaw (fx_jaw): beard over jaw and chin, lower lip and teeth; drops on effort and kiai
    jaw = view('fx_jaw', 'head', JAW_HINGE)
    nbu = 21
    us = [-1 + 2 * i / (nbu - 1) for i in range(nbu)]
    outer = [[beard_uv(u, v) for u in us] for v in BEARD_V]
    inner = [[beard_uv(u, v, True) for u in us] for v in BEARD_V]
    beard = shell_patch(s, 'Beard', outer, inner, jaw, 'cloth', HAIR)
    hair_c = lcol(HAIR); hair_hi = lcol(HAIR_HI)
    b_par = [(u * BEARD_PM, v) for v in BEARD_V for u in us]
    paint_idx(beard, lambda i, p, nn, c: (*(cmix(hair_c, hair_hi, .3 * (.5 + .5 * math.sin(b_par[i][0] * 40 + p.y * 120)) * max(0.0, nn.z + .2)) if i < len(b_par) else hair_c), c[3]))
    s.ellipsoid('Detail lower lip', (0, 1.638, .1005), (.0172, .0048, .0082), jaw, LIP, n=12, m=6)
    s.tube('Detail lower teeth', [(-.015, 1.6335, .093), (0, 1.635, .0965), (.015, 1.6335, .093)], [.0036, .0038, .0036], jaw, TEETH, 'shell', n=6)

    # hair: a swept cap over a faded undercut (rows follow the hairline)
    nr = 36
    hair = grid(s, 'Hair', [[hair_uv(TAU * i / nr, v) for i in range(nr)] for v in HAIR_V], 'head', 'cloth')
    fade = lcol(HAIR_FADE)
    h_par = [(TAU * i / nr, v) for v in HAIR_V for i in range(nr)]

    def hair_paint(i, p, nn, c):
        if i >= len(h_par):
            return (*hair_c, c[3])
        ph, v = h_par[i]
        ap = abs(wrapa(ph))
        # the fade: short, lighter hair low on the sides and back; the long top combed back
        side_fade = sstep(.7, 1.3, ap) * (1 - sstep(.18, .42, v))
        col = cmix(hair_c, fade, .75 * side_fade)
        st = .5 + .5 * math.sin(p.x * 210 + 2.0 * math.sin(p.z * 40))
        return (*cmix(col, hair_hi, .45 * sstep(.35, .6, v) * st * st), c[3])
    paint_idx(hair, hair_paint)
    # combed strands: lighter streaks running up from the hairline and the nape to the crown, where
    # the topknot is tied (decals: no extra silhouette, crisp at close range)
    for k, (ph, v0) in enumerate([(-.8, .07), (-.48, .05), (-.16, .04), (.16, .04), (.48, .05), (.8, .07),
                                  (PI - .76, .3), (PI - .38, .28), (PI, .27), (PI + .38, .28), (PI + .76, .3)]):
        vs = [v0 + (.86 - v0) * j / 9 for j in range(10)]
        pts = [hair_uv(ph + .05 * math.sin(j * .7 + k), v) for j, v in enumerate(vs)]
        nrm = [normal_of(head_skin, ph, HAIR_TOP - (HAIR_TOP - hairline(ph)) * (1 - v)) for v in vs]
        decal(s, 'Detail hair strand %d' % k, pts, nrm, [.0062 - .0034 * j / 9 for j in range(10)], 'head', HAIR_HI, 'cloth', lift=.0012)

    # the team headband: round the head, low at the back, knotted, two short tails
    def band_y(ph):
        return 1.772 - .036 * sstep(.4, 2.6, abs(wrapa(ph)))
    nhb = 40
    hb_rows = []
    for dy, t_extra in ((.012, -.002), (.012, .0078), (-.012, .0078), (-.012, -.002)):
        row = []
        for i in range(nhb):
            ph = TAU * i / nhb
            y = band_y(ph) + dy
            base = Vector(head_skin(ph, y)); nn = normal_of(head_skin, ph, y)
            row.append(tuple(base + nn * (max(0.0, hair_t(ph, y)) + t_extra)))
        hb_rows.append(row)
    grid(s, 'Headband', hb_rows, 'head', 'team', 'FFFFFF', wrap_rows=True)
    s.ellipsoid('Headband knot', (0, 1.736, -.121), (.017, .0135, .011), 'head', 'FFFFFF', 'team', n=12, m=6)
    for side in (1, -1):
        pts = [(side * .006, 1.733, -.125), (side * .016, 1.712, -.132), (side * .024, 1.69, -.134), (side * .03, 1.672, -.131)]
        s.tube('Headband tail %d' % side, pts, [(.0085, .0035), (.009, .0032), (.0085, .003), (.006, .0025)], 'head', 'FFFFFF', 'team', n=8)

    # topknot: a bun with a gold tie on the crown; it bobs on the first spring link (pivot at its root)
    # and its tail swings on both links
    h0 = view('fx_spring_hair_0', 'head', (0, 1.81, -.056))
    h1 = view('fx_spring_hair_1', h0, (0, 1.85, -.104))
    s.ellipsoid('Topknot bun', (0, 1.84, -.057), (.032, .031, .034), h0, HAIR, 'cloth', n=14, m=7)
    ring(s, 'Detail topknot tie', (0, 1.821, -.057), .0272, .029, h0, GOLD, .005, 'shell', n=16)
    # the tail: one tapered tuft with two short wisps, swinging on the two links
    tails = [('Topknot tail', [(0, 1.855, -.07), (0, 1.857, -.095), (0, 1.845, -.12), (0, 1.824, -.139), (0, 1.802, -.148)], [.019, .0165, .0135, .0085, .002], 8)]
    for k, dx in enumerate((-.009, .009)):
        tails.append(('Topknot wisp %d' % k, [(dx * .4, 1.857, -.076), (dx, 1.859, -.1), (dx * 1.5, 1.847, -.124), (dx * 1.9, 1.831, -.138)], [.0115, .0102, .0072, .0015], 6))
    for name, pts, radii, nn in tails:
        tail = s.tube(name, pts, radii, h0, HAIR, 'cloth', n=nn)
        blend_groups(tail, h0, h1, lambda p: sstep(-.095, -.118, p[2]))
        s.paint(tail, lambda p, n, c: (*cmix(hair_c, hair_hi, .4 * max(0.0, n.y) * (.5 + .5 * math.sin(p.x * 400))), c[3]))


def _arm(s, side, suffix):
    view = s.view_bone
    ax = .2438 * side
    ua_bone = suffix + 'UpperArm'
    fa_bone = suffix + 'Forearm'
    ua = Limb(ax, side, [1.58, 1.576, 1.567, 1.552, 1.527, 1.497, 1.46, 1.425, 1.39, 1.35, 1.31, 1.27, 1.24, 1.215, 1.2],
              [.008, .031, .051, .063, .07, .072, .069, .063, .06, .06, .059, .056, .052, .048, .02], upper_arm_bumps)
    n = 18
    ys = [1.58, 1.577, 1.571] + _ys(1.562, 1.2, .02)
    obj = limb_mesh(s, 'Upper arm ' + suffix, ua, ys, n, ua_bone)
    _paint_grid(obj, [(TAU * i / n, y) for y in ys for i in range(n)], skin_painter(upper_arm_bumps))

    fa = Limb(ax, side, [1.238, 1.232, 1.22, 1.195, 1.165, 1.13, 1.095, 1.06, 1.025, .995, .97, .95, .942],
              [.012, .035, .05, .059, .065, .066, .062, .056, .05, .046, .043, .042, .02], forearm_bumps)
    ys = [1.238, 1.235, 1.229] + _ys(1.22, .942, .02)
    obj = limb_mesh(s, 'Forearm ' + suffix, fa, ys, n, fa_bone)
    _paint_grid(obj, [(TAU * i / n, y) for y in ys for i in range(n)], skin_painter(forearm_bumps))

    # Scrap tattoos (copper, glowing with Hype): a cog on each shoulder (hub on the deltoid cap, three
    # spokes, a toothed rim under the deltoid), two bars over the trapezius toward the neck, and two
    # forearm bands joined by lightning zigzags front and back. Rivet dots at the joints.
    def ua_fn(ph, y):
        return ua.point(ph, y)

    def fa_fn(ph, y):
        return fa.point(ph, y)
    glow = .8
    pts, nrm = surface_path(ua_fn, [(TAU * k / 20, 1.45) for k in range(20)], step=.012, closed=True)
    decal(s, 'Detail tattoo shoulder band ' + suffix, pts, nrm, .014, ua_bone, COPPER, glow=glow, closed=True)
    for k in range(5):
        ph = -.35 + k * (PI * .95) / 4
        pts, nrm = surface_path(ua_fn, [(ph, 1.455), (ph, 1.481)], step=.013)
        decal(s, 'Detail tattoo tooth %s%d' % (suffix, k), pts, nrm, .012, ua_bone, COPPER, glow=glow)
    hub = [(PI / 2 + .34 * math.cos(TAU * k / 12), 1.546 + .011 * math.sin(TAU * k / 12)) for k in range(12)]
    pts, nrm = surface_path(ua_fn, hub, step=.01, closed=True)
    decal(s, 'Detail tattoo hub ' + suffix, pts, nrm, .009, ua_bone, COPPER, glow=glow, closed=True)
    s.ellipsoid('Detail tattoo hub rivet ' + suffix, ua.point(PI / 2, 1.546, .001), (.0065, .0065, .0065), ua_bone, COPPER_HI, glow=.9, n=8, m=4)
    for k, ph in enumerate((PI / 2 - .62, PI / 2, PI / 2 + .62)):
        q0 = (PI / 2 + (ph - PI / 2) * .5, 1.535 if k != 1 else 1.533)
        pts, nrm = surface_path(ua_fn, [q0, (ph, 1.49)], step=.01)
        decal(s, 'Detail tattoo spoke %s%d' % (suffix, k), pts, nrm, .011, ua_bone, COPPER, glow=glow)
        s.ellipsoid('Detail tattoo rivet %s%d' % (suffix, k), ua.point(ph, 1.487, .001), (.006, .006, .006), ua_bone, COPPER_HI, glow=.9, n=8, m=4)
    # bars over the trapezius (chest), from the shoulder toward the neck
    for k, ph in enumerate((1.55, 1.95)):
        phs = ph * side
        pts, nrm = surface_path(torso_point, [(phs, 1.528), (phs * .97, 1.586)], step=.01)
        decal(s, 'Detail tattoo trap bar %s%d' % (suffix, k), pts, nrm, .012, 'chest', COPPER, glow=glow)
        s.ellipsoid('Detail tattoo trap rivet %s%d' % (suffix, k), torso_point(phs * .97, 1.59, .001), (.0055, .0055, .0055), 'chest', COPPER_HI, glow=.9, n=8, m=4)
    for k, y in enumerate((1.16, .99)):
        pts, nrm = surface_path(fa_fn, [(TAU * j / 20, y) for j in range(20)], step=.012, closed=True)
        decal(s, 'Detail tattoo forearm band %s%d' % (suffix, k), pts, nrm, .013, fa_bone, COPPER, glow=glow, closed=True)
    for k, base in enumerate((0.0, PI)):
        sgn = 1 if k == 0 else -1
        zig = [(base + sgn * p, y) for p, y in ((.25, 1.15), (.92, 1.113), (.35, 1.075), (1.02, 1.038), (.45, 1.0))]
        pts, nrm = surface_path(fa_fn, zig, step=.01)
        decal(s, 'Detail tattoo zigzag %s%d' % (suffix, k), pts, nrm, .011, fa_bone, COPPER, glow=glow)

    # ---- hand: a black fingerless MMA glove over cream hand wraps --------------------------------------
    hx = ax

    def P(dx, y, z):           # dx > 0: toward the back of the hand (the outer side)
        return (hx + side * dx, y, z)
    for k, (y0, tilt) in enumerate(((.975, .006), (.99, -.007))):
        pts, nrm = [], []
        for j in range(16):
            a = TAU * j / 16
            r = fa.r(a, y0) + .002
            pts.append((hx + side * math.sin(a) * r, y0 + tilt * math.sin(a), math.cos(a) * r))
            nrm.append((side * math.sin(a), 0, math.cos(a)))
        strip(s, 'Wrist wrap %s%d' % (suffix, k), pts, nrm, .016, fa_bone, WRAP if k == 0 else 'E2D6BB', 'cloth', lift=.002, depth=.004, closed=True)
    s.tube('Glove cuff ' + suffix, [(hx, .974, 0), (hx, .963, 0), (hx, .932, .001), (hx, .922, .002)], [.046, .054, .055, .051], fa_bone, GLOVE, 'shell', n=16)
    ring(s, 'Detail glove strap trim ' + suffix, (hx, .9615, 0), .0545, .0545, fa_bone, GOLD, .003, 'shell', n=16)
    s.box('Detail glove patch ' + suffix, P(.054, .946, 0), (.007, .018, .032), fa_bone, RED, 'cloth', .003)
    # padded back of the hand, knuckle roll (the striking face, with knuckle ridges), palm
    superellipsoid(s, 'Glove back ' + suffix, P(.013, .889, 0), (.032, .047, .053), 2.8, fa_bone, GLOVE, 'shell', n=16, m=9)
    superellipsoid(s, 'Glove knuckles ' + suffix, P(.008, .843, 0), (.037, .025, .056), 2.6, fa_bone, GLOVE, 'shell', n=16, m=8)
    superellipsoid(s, 'Glove palm ' + suffix, P(-.016, .892, 0), (.017, .041, .046), 2.4, fa_bone, '2E2B33', 'cloth', n=12, m=7)
    for k in range(4):
        s.ellipsoid('Detail knuckle %s%d' % (suffix, k), P(.01, .8195, -.039 + .026 * k), (.022, .0085, .0115), fa_bone, GLOVE_HI, 'shell', n=8, m=4)
    # bare curled fingers out of the glove's finger loops, and the thumb across them
    for k in range(4):
        z = -.036 + .024 * k
        fl = .03 - .004 * abs(k - 1.5)
        pts = [P(-.002, .827, z), P(-.014, .8275, z), P(-.018, .828, z), P(-.002 - fl, .83, z), P(-.008 - fl, .846, z * .97), P(-.007 - fl, .861, z * .95), P(-.006 - fl, .867, z * .95)]
        s.tube('Finger %s%d' % (suffix, k), pts, [.0118, .0118, .0116, .0112, .0104, .0097, .003], fa_bone,
               lambda v, hx=hx: GLOVE if abs(v[0] - hx) < .016 else SKIN, n=8)
    s.tube('Thumb ' + suffix, [P(-.02, .918, .03), P(-.024, .89, .052), P(-.014, .862, .058), P(-.004, .852, .055), P(.0, .849, .052)],
           [.0145, .0138, .0125, .0112, .004], fa_bone, SKIN, n=8)

    # trailing wrap ends: two loose cloth tails from the back of the wrist, angled back toward the
    # elbow (in a guard they hang; in a punch they stream behind the fist)
    root = Vector((hx + side * .014, .982, -.04))
    w0 = view('fx_spring_wrap_' + suffix, fa_bone, tuple(root))
    d0 = Vector((side * .28, .55, -.79)).normalized()
    w1 = view('fx_spring_wrap_%s_1' % suffix, w0, tuple(root + d0 * .045))
    for k, (L, dd, ph0) in enumerate(((.09, Vector((side * .28, .55, -.79)), 0.0), (.07, Vector((side * .5, .42, -.76)), 1.3))):
        dd = dd.normalized()
        sv = Vector((side, 0, 0))
        nv = (sv - dd * sv.dot(dd)).normalized()      # the flat face looks out to the side
        bv = dd.cross(nv).normalized()
        pts, nrm = [], []
        for j in range(8):
            t = j / 7
            q = root + Vector((0, .004 * k, -.004 * k)) + dd * (L * t) + bv * (.007 * math.sin(t * 4.5 + ph0)) + Vector((0, -.012 * t * t, 0))
            pts.append(tuple(q)); nrm.append(tuple(nv))
        tail = strip(s, 'Wrap tail %s%d' % (suffix, k), pts, nrm, [.021 - .006 * (j / 7) for j in range(8)], w0, WRAP, 'cloth', lift=.0018, depth=.0018)
        blend_groups(tail, w0, w1, lambda p, root=root, dd=dd: sstep(.035, .055, (Vector(p) - root).dot(dd)))


def _leg(s, side, suffix):
    lx = .106 * side
    th_bone = suffix + 'Thigh'
    sh_bone = suffix + 'Shin'
    n = 18
    th = Limb(lx, side, [.72, .68, .63, .58, .53, .48, .44, .41, .385, .365, .35, .342],
              [.1, .101, .1, .099, .094, .086, .078, .072, .069, .066, .055, .02], thigh_bumps,
              cz=lambda y: .004 * gauss(y - .55, .1))
    ys = _ys(.665, .35, .021) + [.346, .342]
    obj = limb_mesh(s, 'Thigh ' + suffix, th, ys, n, th_bone)
    _paint_grid(obj, [(TAU * i / n, y) for y in ys for i in range(n)], skin_painter(thigh_bumps))

    sh = Limb(lx, side, [.405, .395, .38, .355, .32, .29, .26, .23, .2, .17, .14, .11, .08, .05, .02, -.01, -.04, -.07, -.09, -.105, -.112],
              [.02, .045, .06, .066, .068, .068, .067, .065, .062, .058, .054, .05, .047, .045, .043, .043, .043, .044, .046, .04, .015], shin_bumps)
    ys = [.405, .4, .393] + _ys(.38, -.105, .025) + [-.112]
    obj = limb_mesh(s, 'Shin ' + suffix, sh, ys, n, sh_bone)
    _paint_grid(obj, [(TAU * i / n, y) for y in ys for i in range(n)], skin_painter(shin_bumps))

    # bare foot: heel to ball, arch on the inner side, five toes with nails
    FZ = [-.07, -.062, -.05, -.03, -.005, .02, .045, .07, .09, .105, .115, .12]

    def foot_pt(ph, z):
        w = _interp(FZ, [.012, .03, .038, .041, .043, .046, .05, .053, .054, .051, .044, .02], z)
        top = _interp(FZ, [-.15, -.132, -.12, -.108, -.103, -.112, -.128, -.143, -.151, -.156, -.159, -.162], z)
        bot = -.1745
        xo = _interp([-.07, .0, .06, .12], [0, -.002, -.006, -.004], z) * side
        cy = (top + bot) / 2; hh = (top - bot) / 2
        sx = math.sin(ph); cy_ = math.cos(ph)
        x = math.copysign(abs(sx) ** (2 / 2.4), sx) * w
        y = math.copysign(abs(cy_) ** (2 / 2.6), cy_) * hh
        inner = max(0.0, -sx * side)
        if y < 0:
            y = y * (1 - .55 * inner * plateau(z, -.02, .06, .025))
        return (lx + x + xo, cy + y, z)
    zs = [-.07 + k * .0125 for k in range(16)] + [.12]
    foot = grid(s, 'Foot ' + suffix, [[foot_pt(TAU * i / 14, z) for i in range(14)] for z in zs], sh_bone)
    s.paint(foot, lambda p, n, c: (*cmix(cmix(lcol(SKIN), lcol(SKIN_LIGHT), .35 * max(0.0, n.y)), lcol('C07A55'), .6 * max(0.0, -n.y - .4)), c[3]))
    toes = [(-.028, .0145, .108, .162), (-.0085, .0112, .112, .153), (.009, .0105, .109, .146), (.025, .0098, .103, .136), (.039, .009, .095, .124)]
    for k, (dx, r, z0, z1) in enumerate(toes):
        x0 = lx + dx * side          # dx < 0: toward the body (the big toe is on the inner side)
        y0 = -.1745 + r + .001
        tip = (x0 + side * .002 * k, y0 - .002, z1)
        s.tube('Toe %s%d' % (suffix, k), [(x0, y0, z0), (x0 + side * .001 * k, y0 - .001, (z0 + z1) / 2), tip, (tip[0], tip[1] - .001, z1 + r * .75)],
               [r, r * .97, r * .88, r * .3], sh_bone, SKIN, n=6)
        s.ellipsoid('Detail toenail %s%d' % (suffix, k), (tip[0], tip[1] + r * .5, z1 - r * .1), (r * .6, r * .22, r * .55), sh_bone, 'EBC2A4', 'shell', n=6, m=3)

    # athletic tape round the ankle and over the instep
    for k, (y0, tilt) in enumerate(((-.03, .008), (-.05, -.009), (-.07, .008))):
        pts, nrm = [], []
        for j in range(20):
            a = TAU * j / 20
            r = sh.r(a, y0) + .0015
            pts.append((lx + side * math.sin(a) * r, y0 + tilt * math.cos(a), math.cos(a) * r))
            nrm.append((side * math.sin(a), 0, math.cos(a)))
        decal(s, 'Detail ankle tape %s%d' % (suffix, k), pts, nrm, .017, sh_bone, TAPE if k != 1 else 'E6DFCD', 'cloth', lift=.0015, closed=True)
    pts, nrm = [], []
    for j in range(20):
        a = TAU * j / 20
        q = Vector(foot_pt(a, .015))
        dv = q - Vector((lx, -.14, .015)); dv.z = 0
        pts.append(tuple(q)); nrm.append(tuple(dv.normalized()))
    decal(s, 'Detail instep tape ' + suffix, pts, nrm, .018, sh_bone, TAPE, 'cloth', lift=.0018, closed=True)

    # shorts leg (thigh bone, blended into the seat at the hip)
    LY = [.905, .87, .83, .79, .75, .71, .675, .645, .632]

    def short_leg_pt(ph, y):
        rx = ip(LY, [.085, .1, .106, .107, .107, .107, .108, .11, .111], y)
        rz = ip(LY, [.098, .114, .12, .119, .117, .116, .116, .117, .118], y)
        fold = -.004 * gauss(wrapa(ph + PI / 2), .5) * plateau(y, .66, .82, .04)
        return (lx + side * .006 + side * math.sin(ph) * (rx + fold), y, math.cos(ph) * (rz + fold) + .004)
    nl = 24
    ys = _ys(.905, .632, .021)
    legs = grid(s, 'Shorts leg ' + suffix, [[short_leg_pt(TAU * i / nl, y) for i in range(nl)] for y in ys], th_bone, 'cloth', soft=True, caps=(True, False))
    hem_in = [(lx + side * .006 + side * math.sin(TAU * i / nl) * .1, .634, math.cos(TAU * i / nl) * .106 + .004) for i in range(nl)]
    grid(s, 'Shorts hem lining ' + suffix, [[short_leg_pt(TAU * i / nl, .632) for i in range(nl)], hem_in], th_bone, 'cloth', RED_SHADE, caps=(False, False))
    s.paint(legs, lambda p, n, c: (*cmix(cmix(lcol(RED), lcol(RED_LIGHT), .3 * max(0.0, n.z) * max(0.0, n.y + .3)), lcol(RED_SHADE), .55 * max(0.0, -n.x * side) + .3 * max(0.0, -n.y)), c[3]))
    hem = [short_leg_pt(TAU * i / 28, .634) for i in range(28)]
    s.tube('Shorts hem trim ' + suffix, [(p[0] + side * .0015 * math.sin(TAU * i / 28), p[1], p[2] + .0015 * math.cos(TAU * i / 28)) for i, p in enumerate(hem)], .0062, th_bone, GOLD, 'shell', n=5, closed=True)
    pts, nrm = surface_path(short_leg_pt, [(PI / 2, .9), (PI / 2, .64)], step=.015)
    decal(s, 'Detail shorts stripe leg ' + suffix, pts, nrm, .03, th_bone, GOLD, 'shell')
    pts, nrm = surface_path(short_leg_pt, [(PI / 2 + .19, .875), (PI / 2 + .19, .64)], step=.015)
    decal(s, 'Detail shorts pin stripe leg ' + suffix, pts, nrm, .006, th_bone, BAND, 'cloth')


P_Y = [1.098, 1.09, 1.06, 1.02, .98, .94, .9, .86, .835, .818, .808]
P_A = [.162, .168, .174, .186, .196, .2, .2, .196, .19, .178, .165]
P_DF = [.119, .124, .127, .13, .133, .134, .133, .126, .1, .065, .035]
P_DB = [.119, .124, .128, .138, .148, .153, .152, .142, .11, .072, .04]


def seat_pt(ph, y, lift=0.0):
    a = ip(P_Y, P_A, y); df = ip(P_Y, P_DF, y); db = ip(P_Y, P_DB, y)
    x, z, nx, nz = sup(ph, a, df, db, 2.4)
    # the seam between the glutes and down the fly
    w = wrapa(ph)
    d = lift - .004 * gauss(abs(w) - PI, .06) * plateau(y, .82, .98, .03) - .003 * gauss(w, .05) * plateau(y, .83, .99, .03)
    return (x + nx * d, y, z + nz * d)


def _shorts_seat(s):
    n = 32
    ys = _ys(1.098, .81, .02) + [.808]
    seat = grid(s, 'Shorts seat', [[seat_pt(TAU * i / n, y) for i in range(n)] for y in ys], 'pelvis', 'cloth')
    s.paint(seat, lambda p, nn, c: (*cmix(cmix(lcol(RED), lcol(RED_LIGHT), .3 * max(0.0, nn.z) * max(0.0, nn.y + .3)), lcol(RED_SHADE), .35 * max(0.0, -nn.z) + .35 * max(0.0, -nn.y)), c[3]))
    # waistband with gold piping and a riveted copper buckle plate
    nw = 48
    wb_rows = [[seat_pt(TAU * i / nw, y, lift) for i in range(nw)] for y, lift in ((1.026, -.003), (1.031, .006), (1.094, .006), (1.1, -.003))]
    grid(s, 'Waistband', wb_rows, 'pelvis', 'cloth', BAND, wrap_rows=True)
    for k, y in enumerate((1.0315, 1.0935)):
        s.tube('Detail waist piping %d' % k, [seat_pt(TAU * i / 32, y, .0075) for i in range(32)], .0032, 'pelvis', GOLD, 'shell', n=4, closed=True)
    for side in (1, -1):
        pts, nrm = surface_path(seat_pt, [(side * PI / 2, 1.026), (side * PI / 2, .82)], step=.015)
        decal(s, 'Detail shorts stripe seat %d' % side, pts, nrm, .03, 'pelvis', GOLD, 'shell')
    s.box('Buckle plate', (.052, 1.063, .136), (.05, .046, .012), 'pelvis', COPPER_PLATE, 'brass', .006)
    for k, (dx, dy) in enumerate(((-.018, .015), (.018, .015), (-.018, -.015), (.018, -.015))):
        s.ellipsoid('Detail buckle rivet %d' % k, (.052 + dx, 1.063 + dy, .1425), (.0042, .0042, .0028), 'pelvis', 'E9C27A', 'brass', n=6, m=3)


def build(s):
    _torso(s)
    _head(s)
    for side, suffix in SIDES:
        _arm(s, side, suffix)
        _leg(s, side, suffix)
    _shorts_seat(s)
    # the detachable gag piece: a knocked-out tooth
    s.tube('Gore - spare tooth', [(0, 0, 0), (0, .012, 0), (.001, .024, 0), (.002, .034, 0)], [.0085, .0105, .0095, .0015], None, TEETH, n=12, role='gore')
    s.set_look({'glow_mode': 'pulse', 'fx': {'pupil_reach': .006, 'jaw_deg': 15, 'brow_drop': .007, 'lid_rest': .38,
                                             'spring_gain': 1.25, 'spring_stiffness': .9}})
    s.bake_ao(rays=14, distance=.085, strength=.36)
