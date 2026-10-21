"""Knell, the Hollow Diver (v0.9.17 roster art, docs/ART_REVAMP.md "v0.9.17").

An empty deep-sea diving suit worn by a violet ghost. A riveted copper bonnet with three brass-framed
ports: the big front port shows the ghost's rigged face (fx_eye/fx_lid/fx_brow/fx_jaw), the barred
side ports leak its light. A bolted corselet with brass brails and wing nuts, a patched teal canvas
suit with stitched seams, brass cuffs over heavy gauntlets, a lead-weighted belt with an anchor
buckle, lead-soled boots with brass toe caps. The chest lantern is the Ghost Light.
Secondary motion (springs): the air hose from the helmet's gooseneck curling down the back
(fx_spring_hose_0..3), three violet wisps leaking from the collar, the exhaust valve and the crown
valve (fx_spring_wisp_*_0..1) and a small anchor charm on the belt (fx_spring_anchor_0..1).
Hype feature: the ghost light (face, lantern, wisps, ports, the leaks at collar and cuffs), shimmering.

Every coordinate is fighter rest space (+Z forward, +Y up, +X the creature's LEFT, metres); every hard
part sits on the locked collision body of game/content/core/creatures/f_knell.json (the build prints
a registration report: how far each part reaches beyond the collision envelope, and triangle counts).
"""
import math
import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from fighters_v17 import mix, lin, cell_spots, densify, _hash
from mesh_tools import blender

TAU = math.tau

# palette (sRGB hex)
CANVAS = '2E4B53'; CANVAS_HI = '46717A'; CANVAS_LO = '1B3037'; SALT = 'A7BAB0'; WORN = '5E8A8C'; WELT = '233C43'; STITCH = 'D2C8A6'
COPPER = 'B66A3D'; COPPER_HI = 'E6A36C'; COPPER_LO = '6E3519'; VERDI_DK = '3D7F6B'
BRASS = 'D2A64A'; BRASS_HI = 'F2D27E'; BRASS_DK = '8C6624'
LEAD = '59606B'; LEAD_HI = '8A93A0'; LEAD_DK = '3A3F47'
LEATHER = '6E4831'; LEATHER_DK = '3F281B'; LEATHER_HI = '94654A'
GHOST = '9673F5'; GHOST_HI = 'BBA2FF'; GHOST_DK = '5A35C2'; GHOST_DEEP = '2B1458'
TAN = 'C2A46A'; BRICK = 'A5503C'; HOSE = 'B39563'; HOSE_DK = '6A5639'


# ---- small geometry toolkit (fighter space) --------------------------------------------------------
def _mat(s, key):
    """A Studio material by class name, making the outline-free detail_ copy on demand."""
    if key not in s.materials:
        base = key[len('detail_'):] if key.startswith('detail_') else key
        m = s.materials[base].copy()
        m.name = 'CW ' + key
        m['cw_material'] = key
        s.materials[key] = m
    return s.materials[key]


def _vcol(obj, fn):
    """Recolour by vertex: fn(index, fighter position, current linear rgba) -> linear rgba."""
    attr = obj.data.color_attributes['Color']
    for v in obj.data.vertices:
        p = Vector((v.co.x, v.co.z, -v.co.y))
        attr.data[v.index].color = fn(v.index, p, tuple(attr.data[v.index].color))


def _flat(col, glow=0.0):
    return lambda i, p, c: (col[0], col[1], col[2], glow)


def _find(s, name):
    return next(o for o in s.collection.objects if o.name == name)


def _cull_buried(obj, hidden):
    """Delete faces whose corners are all hidden inside another surface (never seen, pure budget)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    dead = [f for f in bm.faces if all(hidden(Vector((v.co.x, v.co.z, -v.co.y))) for v in f.verts)]
    bmesh.ops.delete(bm, geom=dead, context='FACES_ONLY')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def _hammer(obj, amp, seed):
    """Hammered metal: each vertex normal is tipped a little at random, so the arena's several lights
    break into irregular glints on a big smooth dome instead of a row of clean round dots. Shading
    only: no extra geometry, the silhouette is unchanged."""
    me = obj.data
    custom = []
    for v in me.vertices:
        n = Vector(v.normal)
        r = Vector((_hash(seed, v.index, 1) - .5, _hash(seed, v.index, 2) - .5, _hash(seed, v.index, 3) - .5)) * 2
        r = r - n * r.dot(n)
        custom.append(tuple((n + r * amp).normalized()))
    me.normals_split_custom_set_from_vertices(custom)


def _basis(w, up=(0, 1, 0)):
    w = Vector(w).normalized()
    up = Vector(up)
    if abs(w.dot(up.normalized())) > .95:
        up = Vector((0, 0, 1)) if abs(w.z) < .95 else Vector((1, 0, 0))
    u = up.cross(w).normalized()
    v = w.cross(u).normalized()
    return u, v, w


def oellipsoid(s, name, c, axes, r, bone, color, mat='skin', glow=0, n=20, m=10, soft=False, role='body'):
    """An ellipsoid in its own frame: axes = (u, v, w) (w = the pole axis), radii r along them."""
    u, v, w = [Vector(a).normalized() for a in axes]
    c = Vector(c)
    verts = [tuple(c - w * r[2])]
    for j in range(1, m):
        lat = -math.pi / 2 + math.pi * j / m
        for i in range(n):
            a = TAU * i / n
            verts.append(tuple(c + u * (r[0] * math.cos(lat) * math.cos(a)) + v * (r[1] * math.cos(lat) * math.sin(a)) + w * (r[2] * math.sin(lat))))
    verts.append(tuple(c + w * r[2]))
    top = len(verts) - 1
    faces = [(0, 1 + i, 1 + (i + 1) % n) for i in range(n)]
    for j in range(m - 2):
        for i in range(n):
            a = 1 + j * n + i
            b = 1 + j * n + (i + 1) % n
            faces.append((a, a + n, b + n, b))
    faces += [(top, 1 + (m - 2) * n + (i + 1) % n, 1 + (m - 2) * n + i) for i in range(n)]
    return s.mesh(name, verts, faces, bone, color, mat, glow, soft, role)


def facing(s, name, c, w, r, bone, color, mat='skin', glow=0, n=20, m=10, up=(0, 1, 0), soft=False):
    """An ellipsoid facing w (radii: across, up, along w): plates, patches, discs, rivets."""
    return oellipsoid(s, name, c, _basis(w, up), r, bone, color, mat, glow, n, m, soft)


def loft(s, name, rings, bone, color, mat='skin', glow=0, wrap=False, soft=False, role='body', smooth=True):
    """Quads between consecutive closed rings of n points. wrap: the last ring joins the first (a closed
    profile: bezels, rolled rims, belts); otherwise both ends get fan caps."""
    n = len(rings[0])
    R = len(rings)
    verts = [tuple(p) for rg in rings for p in rg]
    faces = []
    for j in range(R if wrap else R - 1):
        j2 = (j + 1) % R
        for i in range(n):
            faces.append((j * n + i, j * n + (i + 1) % n, j2 * n + (i + 1) % n, j2 * n + i))
    if not wrap:
        c0 = len(verts)
        verts.append(tuple(sum((Vector(p) for p in rings[0]), Vector()) / n))
        c1 = len(verts)
        verts.append(tuple(sum((Vector(p) for p in rings[-1]), Vector()) / n))
        for i in range(n):
            faces.append((c0, (i + 1) % n, i))
            faces.append((c1, (R - 1) * n + i, (R - 1) * n + (i + 1) % n))
    return s.mesh(name, verts, faces, bone, color, mat, glow, soft, role, smooth)


def turned(s, name, c, w, profile, bone, color, mat='brass', n=24, glow=0, closed=True, up=(0, 1, 0)):
    """A solid of revolution about axis w through c: profile = [(radius, offset along w), ...].
    closed: the profile is a loop (bezels, rims); else it runs end to end and both ends are capped."""
    u, v, ww = _basis(w, up)
    c = Vector(c)
    rings = [[c + ww * d + u * (r * math.cos(TAU * i / n)) + v * (r * math.sin(TAU * i / n)) for i in range(n)] for r, d in profile]
    return loft(s, name, rings, bone, color, mat, glow, wrap=closed)


def hoop(s, name, c, w, r, bone, color, thickness=.008, mat='brass', glow=0, n=32, sides=6, up=(0, 1, 0), rv=None):
    """A closed ring (torus) around axis w: bands, bails, chain links."""
    u, v, w = _basis(w, up)
    c = Vector(c)
    rv = r if rv is None else rv
    pts = [c + u * (r * math.cos(TAU * i / n)) + v * (rv * math.sin(TAU * i / n)) for i in range(n)]
    return s.tube(name, pts, thickness, bone, color, mat, glow, n=sides, closed=True)


def catmull(ctrl, per=4):
    """A smooth Catmull-Rom path through the control points (per samples per span)."""
    P = [Vector(p) for p in ctrl]
    out = []
    for i in range(len(P) - 1):
        p0, p1, p2, p3 = P[max(i - 1, 0)], P[i], P[i + 1], P[min(i + 2, len(P) - 1)]
        for k in range(per):
            t = k / per
            t2 = t * t
            t3 = t2 * t
            out.append(.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(P[-1].copy())
    return out


def arclen(pts):
    L = [0.0]
    for i in range(1, len(pts)):
        L.append(L[-1] + (Vector(pts[i]) - Vector(pts[i - 1])).length)
    return L


def resample(pts, L, step):
    """Evenly spaced points along a polyline (L = its arc lengths): rings land at a regular pitch."""
    total = L[-1]
    n = max(2, int(round(total / step)))
    out, svals = [], []
    j = 0
    for k in range(n + 1):
        sv = total * k / n
        while j < len(L) - 2 and L[j + 1] < sv:
            j += 1
        seg = L[j + 1] - L[j]
        t = 0.0 if seg <= 0 else max(0.0, min(1.0, (sv - L[j]) / seg))
        out.append(Vector(pts[j]).lerp(Vector(pts[j + 1]), t))
        svals.append(sv)
    return out, svals


def chain_skin(obj, n, ring_s, links, link_s):
    """Skin a tube (ring-major, n vertices per ring, no cap vertices) along a spring chain: each link owns
    the middle of its stretch and blends into the next one across the joint between them."""
    groups = {}
    for b in links:
        groups[b] = obj.vertex_groups[b] if b in obj.vertex_groups else obj.vertex_groups.new(name=b)
    end = ring_s[-1]
    centres = [(link_s[k] + (link_s[k + 1] if k + 1 < len(links) else end)) / 2 for k in range(len(links))]
    for r, sv in enumerate(ring_s):
        w = [0.0] * len(links)
        if sv <= centres[0]:
            w[0] = 1.0
        elif sv >= centres[-1]:
            w[-1] = 1.0
        else:
            for k in range(len(links) - 1):
                if centres[k] <= sv <= centres[k + 1]:
                    t = (sv - centres[k]) / (centres[k + 1] - centres[k])
                    w[k] = 1 - t
                    w[k + 1] = t
                    break
        idx = list(range(r * n, (r + 1) * n))
        for k, b in enumerate(links):
            if w[k] > 1e-4:
                groups[b].add(idx, w[k], 'REPLACE')
            elif k == 0:
                groups[b].remove(idx)


class Surface:
    """Ray casts against finished meshes (fighter space) to seat belts, seams and patches on them."""

    def __init__(self, objs):
        verts, polys = [], []
        for o in objs:
            base = len(verts)
            verts.extend([o.matrix_world @ v.co for v in o.data.vertices])
            polys.extend([[base + i for i in p.vertices] for p in o.data.polygons])
        self.tree = BVHTree.FromPolygons(verts, polys)

    def hit(self, origin, direction):
        loc, nrm, _i, _d = self.tree.ray_cast(Vector(blender(origin)), Vector(blender(direction)).normalized())
        if loc is None:
            return None, None
        return Vector((loc.x, loc.z, -loc.y)), Vector((nrm.x, nrm.z, -nrm.y)).normalized()

    def radial(self, y, a, cx=0.0, cz=0.0):
        """Where the ray from (cx, y, cz) at heading a (0 = forward, +pi/2 = the creature's left) exits."""
        return self.hit((cx, y, cz), (math.sin(a), 0, math.cos(a)))


def _sdf(sh, p):
    if sh['type'] == 'sphere':
        return (p - Vector(sh['center'])).length - sh['radius']
    if sh['type'] == 'capsule':
        a, b = Vector(sh['a']), Vector(sh['b'])
        ab = b - a
        t = max(0, min(1, (p - a).dot(ab) / ab.length_squared))
        return (p - a - ab * t).length - sh['radius']
    d = p - Vector(sh['center'])
    half = Vector(sh['size']) / 2
    q = Vector([abs(d[i]) - half[i] for i in range(3)])
    return Vector([max(0, x) for x in q]).length + min(max(q), 0)


def envelope(s, p):
    return min(_sdf(sh, p) for seg in s.segments.values() for sh in seg['shapes'])


SOFT_PARTS = ('Air hose', 'Detail wisp', 'Anchor', 'Detail anchor', 'Detail hose', 'Hose end', 'Lantern', 'Detail lantern')


def registration_report(s):
    rows = []
    tris = 0
    by_group = {}
    for o in s.collection.objects:
        if o.type != 'MESH' or o.get('cw_role') != 'body':
            continue
        t = sum(len(p.vertices) - 2 for p in o.data.polygons)
        tris += t
        key = ' '.join(w for w in o.name.split() if not any(ch.isdigit() for ch in w) and w not in ('l', 'r'))
        by_group[key] = by_group.get(key, 0) + t
        d = max(envelope(s, Vector((v.co.x, v.co.z, -v.co.y))) for v in o.data.vertices)
        rows.append((d, o.name))
    rows.sort(reverse=True)
    print('KNELL REGISTRATION: farthest reach beyond the collision envelope (hard <= .05, soft <= .08)')
    for d, nm in rows[:24]:
        limit = .08 if nm.startswith(SOFT_PARTS) else .05
        print('KNELL %s %.3f  %s' % ('!!' if d > limit + .005 else '  ', d, nm))
    print('KNELL approx body triangles', tris)
    for k, t in sorted(by_group.items(), key=lambda kv: -kv[1])[:28]:
        print('KNELL tris %6d  %s' % (t, k))


# ---- Knell ------------------------------------------------------------------------------------------
def build(s):
    canvas, canvas_hi, canvas_lo, salt, worn = lin(CANVAS), lin(CANVAS_HI), lin(CANVAS_LO), lin(SALT), lin(WORN)
    copper, copper_hi, copper_lo, verdi_dk = lin(COPPER), lin(COPPER_HI), lin(COPPER_LO), lin(VERDI_DK)
    brass, brass_hi, brass_dk = lin(BRASS), lin(BRASS_HI), lin(BRASS_DK)
    lead, lead_hi, lead_dk = lin(LEAD), lin(LEAD_HI), lin(LEAD_DK)
    leather, leather_dk, leather_hi = lin(LEATHER), lin(LEATHER_DK), lin(LEATHER_HI)
    stitch = lin(STITCH)
    # rubbed, lighter canvas round the patched knees and elbows
    wear_spots = [Vector((.12, .45, .1)), Vector((-.12, .45, .1)), Vector((.3, 1.05, -.088)), Vector((-.3, 1.05, -.088))]

    def canvas_paint(p, n, c):
        # sun-faded shoulders, darker undersides, worn panels, dried salt creeping up from the boots
        col = mix(canvas, canvas_hi, max(0.0, n.y) * .5 + max(0.0, n.z) * .1)
        col = mix(col, canvas_lo, max(0.0, -n.y) * .55)
        col = mix(col, canvas_hi, cell_spots(p, .12, .75, .6, 21) * .3)
        for wsp in wear_spots:
            d = (p - wsp).length
            if d < .085:
                col = mix(col, worn, (1 - d / .085) * .7)
        low = max(0.0, min(1.0, (.85 - p.y) / .6))
        sp = cell_spots(p, .07, .65, .55, 33) * (.3 + low * 1.1)
        if sp > .3:
            col = mix(col, salt, .42)
        elif sp > .17:
            col = mix(col, salt, .18)
        return (col[0], col[1], col[2], c[3])

    def copper_paint(p, n, c, patina_below=1.445):
        # polished copper above, darker below, hammered speckle, dull tarnish patches; verdigris only in
        # a thin band at the seams low down (bright spots read as polka dots from the fight camera)
        col = mix(copper, copper_hi, max(0.0, n.y) * .55 + max(0.0, n.z) * .1)
        col = mix(col, copper_lo, max(0.0, -n.y) * .6)
        h = _hash(math.floor(p.x * 150), math.floor(p.y * 150), math.floor(p.z * 150), 5)
        col = mix(col, copper_hi if h > .5 else copper_lo, abs(h - .5) * .3)
        col = mix(col, copper_lo, cell_spots(p, .09, .8, .55, 13) * .3)
        low = max(0.0, min(1.0, (patina_below - p.y) / .05))
        if low > 0 and cell_spots(p, .03, .7, .6, 9) * low > .25:
            col = mix(col, verdi_dk, .6)
        return (col[0], col[1], col[2], c[3])

    def brass_paint(p, n, c):
        col = mix(brass, brass_hi, max(0.0, n.y) * .5)
        col = mix(col, brass_dk, max(0.0, -n.y) * .55)
        if cell_spots(p, .045, .5, .3, 17) > .35:
            col = mix(col, verdi_dk, .45)
        return (col[0], col[1], col[2], c[3])

    def lead_paint(p, n, c):
        col = mix(lead, lead_hi, max(0.0, n.y) * .6)
        col = mix(col, lead_dk, max(0.0, -n.y) * .6)
        col = mix(col, lead_dk, cell_spots(p, .03, .5, .5, 41) * .5)
        return (col[0], col[1], col[2], c[3])

    def leather_paint(p, n, c):
        col = mix(leather, leather_hi, max(0.0, n.y) * .45 + cell_spots(p, .05, .6, .5, 51) * .3)
        col = mix(col, leather_dk, max(0.0, -n.y) * .55)
        return (col[0], col[1], col[2], c[3])

    # ======================= the canvas suit (chest + pelvis) =======================
    ys = [.66, .70, .75, .81, .87, .93, .99, 1.05, 1.12, 1.19, 1.26, 1.32, 1.37]
    rad = [(.06, .05), (.15, .10), (.235, .15), (.275, .172), (.29, .18), (.28, .17), (.29, .20), (.325, .235), (.35, .255), (.36, .26),
           (.35, .25), (.31, .22), (.22, .15)]
    pts, rads = densify([(0, y, 0) for y in ys], rad, 2)
    suit = s.tube('Suit - canvas body', pts, rads, 'chest', CANVAS, 'cloth', n=44)
    pel = suit.vertex_groups.new(name='pelvis')
    chg = suit.vertex_groups['chest']
    for v in suit.data.vertices:
        w = max(0, min(1, (v.co.z - .88) / .12))
        chg.add([v.index], w, 'REPLACE')
        pel.add([v.index], 1 - w, 'REPLACE')
    s.fit(suit, ['chest', 'pelvis'], (0, 1.02, 0), padding=.016)
    s.paint(suit, canvas_paint)

    def bunched(p, n, c):
        # the baggy canvas bunches above the weight belt: soft creases that rise toward the sides
        side = math.sin(math.atan2(p.x, p.z)) ** 2
        col = c
        for y0 in (.968, 1.018, 1.072):
            yy = y0 + .04 * side
            d = (p.y - yy) / .017
            col = mix(col, canvas_lo, .3 * math.exp(-d * d))
            d2 = (p.y - yy - .02) / .015
            col = mix(col, canvas_hi, .14 * math.exp(-d2 * d2))
        return (col[0], col[1], col[2], c[3])
    s.paint(suit, bunched)
    body_surf = Surface([suit])

    # ======================= corselet: the bolted copper yoke on the shoulders =======================
    def cors(a, t):
        sa, ca = math.sin(a), math.cos(a)
        s2 = sa * sa
        nx, nz = .18 * sa, .014 + .17 * ca
        rx, rz = .372 * sa, .25 * ca
        x = nx + (rx - nx) * t
        z = nz + (rz - nz) * t
        y = 1.41 + (1.245 + .09 * s2 - 1.41) * t ** (1.0 + 2.0 * s2 * s2) + .01 * math.sin(math.pi * t) * s2 ** 3
        return Vector((x, y, z))

    def cors_frame(a, t):
        p = cors(a, t)
        dt = cors(a, min(1, t + .01)) - cors(a, max(0, t - .01))
        da = cors(a + .01, t) - cors(a - .01, t)
        nrm = da.cross(dt).normalized()
        if nrm.dot(Vector((math.sin(a), 1.2, math.cos(a)))) < 0:
            nrm = -nrm
        return p, nrm, da.normalized()

    NC = 52
    heads = [TAU * i / NC for i in range(NC)]

    def radial_out(a, d):
        return Vector((math.sin(a) * d, 0, math.cos(a) * d))

    rings = [[cors(a, t) for a in heads] for t in [0, .12, .26, .4, .54, .66, .77, .86, .93, .975, 1.0]]
    rings.append([cors(a, 1.0) + Vector((0, -.012, 0)) + radial_out(a, .004) for a in heads])     # rolled lip
    rings.append([cors(a, .985) + Vector((0, -.026, 0)) + radial_out(a, -.006) for a in heads])
    for t in [.8, .4, 0]:                                                                        # underside
        rings.append([cors(a, t) + Vector((0, -.028, 0)) + radial_out(a, -.006) for a in heads])
    corselet = loft(s, 'Corselet - copper yoke', rings, 'chest', COPPER, 'brass', wrap=True)
    s.paint(corselet, lambda p, n, c: copper_paint(p, n, c, 1.285))
    _hammer(corselet, .15, 31)

    # brass brails (the clamping strips round the rim) with 12 wing nuts
    br = []
    for t, lift in [(.83, -.002), (.836, .007), (.928, .007), (.934, -.002)]:
        br.append([cors_frame(a, t)[0] + cors_frame(a, t)[1] * lift for a in heads])
    brails = loft(s, 'Corselet brails', br, 'chest', BRASS, 'brass', wrap=True)
    s.paint(brails, brass_paint)
    for k in range(12):
        a = math.radians(15 + 30 * k)
        p, nrm, tan = cors_frame(a, .882)
        p = p + nrm * .007
        bi = nrm.cross(tan).normalized()
        s.tube('Detail wing nut hub %d' % k, [p - nrm * .002, p + nrm * .0065], [.0092, .0082], 'chest', BRASS_DK, 'brass', n=6)
        for side in (-1, 1):
            oellipsoid(s, 'Detail wing nut %d %d' % (k, side), p + nrm * .0075 + tan * (side * .0102), (tan, nrm, bi), (.0102, .0058, .0024),
                       'chest', BRASS_HI, 'brass', n=6, m=3)

    # ======================= helmet: copper bonnet, three brass ports, gooseneck =======================
    HC = Vector((0, 1.555, .02))
    HR = (.228, .222, .226)

    def bonnet(phi, a):
        return Vector((HR[0] * math.sin(phi) * math.sin(a), HC.y + HR[1] * math.cos(phi), HC.z + HR[2] * math.sin(phi) * math.cos(a)))

    def in_bonnet(p, k=1.0):
        return sum(((p[i] - HC[i]) / HR[i]) ** 2 for i in range(3)) < k

    def bonnet_hit(o, d):
        """Where a ray from inside the bonnet ellipsoid leaves it (point, outward normal)."""
        o = Vector(o) - HC
        d = Vector(d).normalized()
        A = sum((d[i] / HR[i]) ** 2 for i in range(3))
        B = 2 * sum(o[i] * d[i] / HR[i] ** 2 for i in range(3))
        C = sum((o[i] / HR[i]) ** 2 for i in range(3)) - 1
        t = (-B + math.sqrt(B * B - 4 * A * C)) / (2 * A)
        p = HC + o + d * t
        nrm = Vector([(p[i] - HC[i]) / HR[i] ** 2 for i in range(3)]).normalized()
        return p, nrm

    phi_end = math.acos((1.385 - HC.y) / HR[1])
    NB = 44
    b_rings = [[bonnet(phi_end * k / 22, TAU * i / NB) for i in range(NB)] for k in range(1, 23)]
    helmet = loft(s, 'Helmet bonnet', b_rings, 'head', COPPER, 'brass')
    s.paint(helmet, copper_paint)
    _hammer(helmet, .18, 7)
    # the neck flange where the bonnet locks onto the corselet, riveted all round
    fl_y = 1.416
    sphi = math.sqrt(1 - ((fl_y - HC.y) / HR[1]) ** 2)
    fx, fz = HR[0] * sphi * 1.03, HR[2] * sphi * 1.03
    flange = s.tube('Helmet neck flange', [(fx * math.sin(TAU * i / 40), fl_y, HC.z + fz * math.cos(TAU * i / 40)) for i in range(40)],
                    .017, 'head', BRASS, 'brass', n=6, closed=True)
    s.paint(flange, brass_paint)
    for k in range(12):
        a = TAU * (k + .5) / 12
        p = Vector((fx * math.sin(a), fl_y + .004, HC.z + fz * math.cos(a))) + radial_out(a, .0165)
        facing(s, 'Detail flange rivet %d' % k, p, radial_out(a, 1) + Vector((0, .35, 0)), (.0075, .0075, .005), 'head', BRASS_HI, 'brass', n=6, m=3)
    # ghost light leaking from the collar seam (stays on the corselet: shows more when the helmet tips)
    s.tube('Detail collar leak', [(fx * 1.07 * math.sin(TAU * i / 36), 1.403, HC.z + fz * 1.07 * math.cos(TAU * i / 36)) for i in range(36)],
           .0075, 'chest', GHOST, 'ghost', glow=.75, n=4, closed=True)

    # -- front port: heavy brass boss, dark glass, the ghost's face --
    PC = Vector((0, 1.565, 0))
    front = turned(s, 'Front port frame', PC, (0, 0, 1), [(.150, .178), (.153, .238), (.150, .256), (.141, .2645), (.129, .263), (.1215, .256), (.1215, .205), (.134, .182)],
                   'head', BRASS, 'brass', n=40)
    s.paint(front, brass_paint)
    for k in range(6):
        a = TAU * k / 6 + TAU / 12
        p = PC + Vector((math.cos(a) * .1405, math.sin(a) * .1405, .262))
        s.tube('Detail port bolt %d' % k, [p - Vector((0, 0, .001)), p + Vector((0, 0, .0042))], .0085, 'head', BRASS_HI, 'brass', n=6)
    # hinge on the creature's left, wing-nut latch on its right
    s.box('Detail port hinge', (.156, 1.565, .236), (.03, .05, .03), 'head', BRASS_DK, 'brass', .006)
    s.tube('Detail port hinge pin', [(.168, 1.533, .244), (.168, 1.597, .244)], .006, 'head', BRASS_HI, 'brass', n=6)
    s.tube('Detail port latch stud', [(-.149, 1.565, .244), (-.162, 1.565, .256)], .0055, 'head', BRASS_DK, 'brass', n=6)
    for side in (-1, 1):
        oellipsoid(s, 'Detail port latch wing %d' % side, (-.164, 1.565 + side * .0105, .258), ((0, 0, 1), (0, 1, 0), (1, 0, 0)), (.007, .0105, .0026),
                   'head', BRASS_HI, 'brass', n=6, m=3)
    glass = facing(s, 'Detail port glass', (0, 1.565, .224), (0, 0, 1), (.1235, .1235, .008), 'head', '150B27', 'glass', n=28, m=6)
    _cull_buried(glass, lambda p: p.z < .2235)

    # the ghost's face, pressed to the glass
    FC = Vector((0, 1.563, .219))
    FR = (.103, .101, .04)

    def face_z(x, y):
        return FC.z + FR[2] * math.sqrt(max(0.0, 1 - (x / FR[0]) ** 2 - ((y - FC.y) / FR[1]) ** 2))

    def behind_face(p, margin=.0012):
        return (p.x / FR[0]) ** 2 + ((p.y - FC.y) / FR[1]) ** 2 < .98 and p.z < face_z(p.x, p.y) - margin

    g_hi, g_mid, g_dk = lin(GHOST_HI), lin(GHOST), lin(GHOST_DK)
    blush = lin('F09BE0')

    def ghost_col(p):
        d = min(1.0, math.sqrt((p.x / FR[0]) ** 2 + ((p.y - FC.y) / FR[1]) ** 2))
        col = mix(g_hi, g_mid, d * 1.5)
        col = mix(col, g_dk, (d - .6) * 2.4)
        for sx in (-1, 1):
            dc = math.sqrt((p.x - sx * .063) ** 2 + (p.y - 1.531) ** 2)
            if dc < .021:
                col = mix(col, blush, (1 - dc / .021) * .6)
        return col, .74 - .34 * d

    def ghost_paint(i, p, c):
        col, g = ghost_col(p)
        return (col[0], col[1], col[2], g)

    face = s.ellipsoid('Ghost face', tuple(FC), FR, 'head', GHOST, 'ghost', n=26, m=14)
    _vcol(face, ghost_paint)
    _cull_buried(face, lambda p: p.z < .2265)

    def face_patch(name, cx, cy, rx, ry, lift, thick, bone, col, mat, n=16, k=3):
        """A thin shell lying on the ghost's face (mouth, chin): its top lifted off the face by `lift`."""
        tops, bots = [], []
        for j in range(k, 0, -1):
            f = j / k
            ring_t, ring_b = [], []
            for i in range(n):
                a = TAU * i / n
                x = cx + rx * f * math.cos(a)
                y = cy + ry * f * math.sin(a)
                ring_t.append(Vector((x, y, face_z(x, y) + lift)))
                ring_b.append(Vector((x, y, face_z(x, y) + lift - thick)))
            tops.append(ring_t)
            bots.append(ring_b)
        return loft(s, name, list(reversed(tops)) + bots, bone, col, mat)

    # rigged ghost eyes (pale, glowing), brows, a small ghostly mouth that opens on fx_jaw
    for side, suffix in [(1, 'l'), (-1, 'r')]:
        x = side * .041
        ze = face_z(x, 1.578) - .0015
        nm = 'Eye ' + suffix
        s.rig_eye(nm, (x, 1.578, ze), (.027, .033, .009), 'head', suffix, iris='86F0DC', lid_color=GHOST, pupil='1F0B3A')
        # a wider, shallow socket: a deep-violet ring round each eye, clear of the eye white
        socket = _find(s, nm + ' socket')
        c0 = Vector((x, 1.578, ze))
        for v in socket.data.vertices:
            p = Vector((v.co.x, v.co.z, -v.co.y)) - c0
            v.co = Vector(blender(c0 + Vector((p.x * 1.18, p.y * 1.15, p.z * 1.05))))
        socket.data.update()
        _vcol(socket, _flat(lin(GHOST_DEEP)))
        sclera = _find(s, nm + ' sclera')
        _vcol(sclera, _flat(lin('EDF2FF'), .25))
        _vcol(_find(s, nm + ' iris'), _flat(lin('86F0DC'), .6))
        _vcol(_find(s, nm + ' pupil'), _flat(lin('1F0B3A')))
        lid = _find(s, 'Detail lid ' + nm)
        lid.data.materials[0] = _mat(s, 'detail_ghost')
        _vcol(lid, ghost_paint)
        # budget: the halves of the eye buried in the face (and inside the eyeball) are never seen
        sc = Vector((x, 1.578, ze + .35 * .009))

        def in_sclera(p, sc=sc):
            return ((p.x - sc.x) / .027) ** 2 + ((p.y - sc.y) / .033) ** 2 + ((p.z - sc.z) / .009) ** 2 < .97
        for part in ['socket', 'sclera', 'iris', 'pupil']:
            o = _find(s, nm + ' ' + part)
            _cull_buried(o, (lambda p: behind_face(p)) if part in ('socket', 'sclera') else (lambda p: behind_face(p) or in_sclera(p)))
        _cull_buried(lid, lambda p: behind_face(p, .0005))
        brow = s.view_bone('fx_brow_' + suffix, 'head', (side * .044, 1.622, face_z(side * .044, 1.622)))
        bp = [(side * .02, 1.616), (side * .044, 1.625), (side * .068, 1.617)]
        s.tube('Detail ghost brow ' + suffix, [(bx, by, face_z(bx, by) + .002) for bx, by in bp], [.004, .0055, .0028], brow, GHOST_DK, 'ghost', n=6)
    face_patch('Detail mouth', 0, 1.509, .021, .0135, .0024, .004, 'head', '1A0A2E', 'skin')
    jaw = s.view_bone('fx_jaw', 'head', (0, 1.513, .195))
    chin = face_patch('Detail ghost chin', 0, 1.4975, .03, .0115, .0034, .004, jaw, GHOST, 'ghost')
    _vcol(chin, ghost_paint)
    # glints on the glass (in front of the face, upper left as you look at it)
    for k, (r0, a0, a1) in enumerate([(.1, 112, 152), (.086, 124, 142)]):
        arc = [PC + Vector((r0 * math.cos(math.radians(a)), r0 * math.sin(math.radians(a)), .2605)) for a in [a0 + (a1 - a0) * i / 6 for i in range(7)]]
        s.tube('Detail port glint %d' % k, arc, [.0012, .003, .004, .0042, .004, .003, .0012], 'head', 'FFFFFF', 'glass', glow=.3, n=4)

    # -- side ports: barred, their glass lit faintly from inside --
    for side, suffix in [(1, 'l'), (-1, 'r')]:
        a = side * math.radians(72)
        S, w = bonnet_hit((0, 1.585, .02), (math.sin(a), 0, math.cos(a)))
        sp = turned(s, 'Side port frame ' + suffix, S, w, [(.079, -.028), (.081, .006), (.078, .016), (.07, .021), (.061, .019), (.0575, .012), (.0575, -.02), (.068, -.03)],
                    'head', BRASS, 'brass', n=28)
        s.paint(sp, brass_paint)
        sg = facing(s, 'Detail side port glass ' + suffix, S + w * .002, w, (.059, .059, .006), 'head', GHOST_DEEP, 'ghost', glow=.32, n=16, m=4)
        _vcol(sg, lambda i, p, c, S=S: (lambda t: (lambda col: (col[0], col[1], col[2], .62 - .4 * t))(mix(lin('6A45C8'), lin(GHOST_DEEP), t)))(
            min(1.0, (p - S).length / .06)))
        u, v, _ = _basis(w)
        for b in (-1, 0, 1):
            half = math.sqrt(.0575 ** 2 - (b * .028) ** 2) - .002
            s.tube('Detail side port bar %s%d' % (suffix, b + 1), [S + w * .011 + u * (b * .028) - v * half, S + w * .011 + u * (b * .028) + v * half],
                   .0048, 'head', BRASS_HI, 'brass', n=5)

    # -- the gooseneck air inlet, exhaust valve and crown valve --
    goose = [(0, 1.636, -.17), (0, 1.643, -.198), (0, 1.629, -.222), (0, 1.598, -.232), (0, 1.56, -.231), (0, 1.528, -.227)]
    s.tube('Helmet gooseneck', catmull(goose, 2), .0185, 'head', BRASS, 'brass', n=10)
    facing(s, 'Detail gooseneck flange', (0, 1.634, -.191), (0, .3, -1), (.036, .036, .007), 'head', BRASS_DK, 'brass', n=14, m=4)
    s.tube('Helmet hose coupling', [(0, 1.538, -.227), (0, 1.522, -.227), (0, 1.504, -.227)], [.0245, .026, .0245], 'head', BRASS_DK, 'brass', n=6)
    ev, evn = bonnet_hit((0, 1.50, .02), (-math.sin(math.radians(118)), .12, math.cos(math.radians(118))))
    s.tube('Helmet exhaust valve', [ev - evn * .01, ev + evn * .02, ev + evn * .026], [.021, .021, .016], 'head', BRASS, 'brass', n=10)
    s.tube('Detail exhaust valve cap', [ev + evn * .026, ev + evn * .034], [.012, .006], 'head', BRASS_HI, 'brass', n=8)
    cv, cvn = bonnet_hit((0, 1.56, .02), (0, .93, -.36))
    s.tube('Helmet crown valve', [cv - cvn * .008, cv + cvn * .016], [.017, .015], 'head', BRASS, 'brass', n=10)
    hoop(s, 'Detail crown valve ring', cv + cvn * .016, cvn, .013, 'head', BRASS_HI, .0035, 'brass', n=12, sides=5)

    # ======================= chest lantern: the Ghost Light, hung from the front brail =======================
    LZ = .272
    s.tube('Lantern hook', [(0, 1.282, .247), (0, 1.27, .262), (0, 1.256, .266), (0, 1.249, .261)], .0042, 'chest', BRASS_DK, 'brass', n=5)
    hoop(s, 'Detail lantern chain 0', (0, 1.239, .266), (1, 0, 0), .0065, 'chest', '6B6F78', .0022, 'metal', n=8, sides=4, rv=.009)
    hoop(s, 'Detail lantern chain 1', (0, 1.225, .268), (0, 0, 1), .0065, 'chest', '6B6F78', .0022, 'metal', n=8, sides=4, rv=.009)
    s.tube('Lantern bail', [(-.025, 1.188, LZ), (-.022, 1.204, LZ), (-.012, 1.214, LZ), (0, 1.217, LZ), (.012, 1.214, LZ), (.022, 1.204, LZ), (.025, 1.188, LZ)],
           .0028, 'chest', BRASS, 'brass', n=4)
    lc = Vector((0, 0, LZ))
    top = turned(s, 'Lantern cap', lc, (0, 1, 0), [(.004, 1.214), (.008, 1.206), (.016, 1.199), (.031, 1.183), (.034, 1.178), (.03, 1.175), (.004, 1.174)],
                 'chest', BRASS, 'brass', n=14, closed=False, up=(0, 0, 1))
    s.paint(top, brass_paint)
    globe = turned(s, 'Lantern globe', lc, (0, 1, 0), [(.012, 1.177), (.022, 1.172), (.028, 1.157), (.0295, 1.14), (.027, 1.12), (.02, 1.106), (.01, 1.102)],
                   'chest', GHOST, 'ghost', n=14, closed=False, up=(0, 0, 1))
    flame_hi, flame_lo = lin('CDB8FF'), lin('7A4DEB')

    def globe_col(i, p, c):
        # white-violet at the heart of the light, deeper toward the top and bottom of the glass
        t = min(1.0, abs(p.y - 1.142) / .036) ** 1.4
        col = mix(flame_hi, flame_lo, t)
        return (col[0], col[1], col[2], 1.0 - .3 * t)
    _vcol(globe, globe_col)
    for k in range(4):
        a = TAU * k / 4 + TAU / 8
        bx, bz = math.cos(a) * .0305, math.sin(a) * .0305
        s.tube('Detail lantern cage %d' % k, [(bx * .8, 1.178, LZ + bz * .8), (bx, 1.168, LZ + bz), (bx * 1.03, 1.14, LZ + bz * 1.03), (bx, 1.112, LZ + bz), (bx * .8, 1.103, LZ + bz * .8)],
               .0023, 'chest', BRASS_HI, 'brass', n=4)
    base = turned(s, 'Lantern base', lc, (0, 1, 0), [(.012, 1.106), (.03, 1.104), (.0325, 1.098), (.027, 1.089), (.012, 1.083), (.004, 1.082)],
                  'chest', BRASS, 'brass', n=14, closed=False, up=(0, 0, 1))
    s.paint(base, brass_paint)

    # ======================= weighted belt (on the hips), lead blocks, anchor buckle =======================
    NBLT = 48
    belt_heads = [TAU * i / NBLT for i in range(NBLT)]
    Y_TOP, Y_BOT = .935, .857
    ysamp = [Y_BOT + (Y_TOP - Y_BOT) * k / 6 for k in range(7)]
    rin = {y: [(body_surf.radial(y, a)[0] - Vector((0, y, 0))).length for a in belt_heads] for y in ysamp}
    rmax = [max(rin[y][i] for y in ysamp) + .012 for i in range(NBLT)]

    def r_in(i, y):
        ks = min(range(len(ysamp)), key=lambda k: abs(ysamp[k] - y))
        return rin[ysamp[ks]][i]

    def rb(i, y):
        return max(r_in(i, y) + .012, rmax[i] - .016)

    def bp(a, y, r):
        return Vector((math.sin(a) * r, y, math.cos(a) * r))

    prof = [(Y_TOP + .003, 'in'), (Y_TOP, 'out'), (Y_TOP - .006, 'out'), (Y_TOP - .012, 'out'), (Y_BOT + .012, 'out'), (Y_BOT + .006, 'out'), (Y_BOT, 'out'),
            (Y_BOT - .002, 'in')]
    belt_rings = [[bp(a, y, (r_in(i, y) - .003) if kind == 'in' else rb(i, y)) for i, a in enumerate(belt_heads)] for y, kind in prof]
    belt = loft(s, 'Weight belt', belt_rings, 'pelvis', LEATHER, 'cloth', wrap=True)
    s.paint(belt, leather_paint)
    _vcol(belt, lambda i, p, c: (stitch[0], stitch[1], stitch[2], c[3]) if (i // NBLT in (2, 5) and (i % NBLT) % 2 == 0) else c)

    def belt_r(a, y0, y1):
        i = int(round(a / TAU * NBLT)) % NBLT
        return max(rb(i, y) for y in ysamp if y0 - .01 <= y <= y1 + .01)

    for k, deg in enumerate([40, -40, 140, -140]):
        a = math.radians(deg)
        rr = belt_r(a, Y_BOT, Y_TOP) + .009
        c = bp(a, .868, rr)
        blk = s.box('Lead weight %d' % k, tuple(c), (.07, .076, .018), 'pelvis', LEAD, 'metal', .008)
        ca_, sa_ = math.cos(a), math.sin(a)
        for v in blk.data.vertices:
            p = Vector((v.co.x, v.co.z, -v.co.y)) - c
            v.co = Vector(blender(c + Vector((p.x * ca_ + p.z * sa_, p.y, -p.x * sa_ + p.z * ca_))))
        blk.data.update()
        s.paint(blk, lead_paint)
    # anchor buckle at the front
    bc = bp(0, .896, belt_r(0, Y_BOT, Y_TOP) + .006)
    buckle = s.box('Belt buckle', tuple(bc), (.086, .066, .012), 'pelvis', BRASS, 'brass', .01)
    s.paint(buckle, brass_paint)
    az = bc.z + .0075
    yb = bc.y
    s.tube('Detail buckle anchor shank', [(0, yb + .02, az), (0, yb - .016, az)], .0028, 'pelvis', BRASS_DK, 'brass', n=5)
    s.tube('Detail buckle anchor stock', [(-.013, yb + .013, az), (.013, yb + .013, az)], .0024, 'pelvis', BRASS_DK, 'brass', n=5)
    hoop(s, 'Detail buckle anchor ring', (0, yb + .0235, az), (0, 0, 1), .0045, 'pelvis', BRASS_DK, .0018, 'brass', n=8, sides=4)
    s.tube('Detail buckle anchor arms', [(-.02, yb - .007, az), (-.016, yb - .015, az), (-.008, yb - .0205, az), (0, yb - .0215, az), (.008, yb - .0205, az), (.016, yb - .015, az),
                                         (.02, yb - .007, az)], .0028, 'pelvis', BRASS_DK, 'brass', n=5)

    # anchor charm hanging off the back of the belt on a short chain (springs)
    aa = math.pi
    hook = bp(aa, Y_BOT - .002, belt_r(aa, Y_BOT, Y_BOT + .02) + .002)
    radial = Vector((math.sin(aa), 0, math.cos(aa)))
    tang = Vector((math.cos(aa), 0, -math.sin(aa)))
    anc0 = s.view_bone('fx_spring_anchor_0', 'pelvis', tuple(hook))
    hoop(s, 'Detail anchor chain 0', hook + Vector((0, -.008, 0)), tang, .006, anc0, '6B6F78', .0022, 'metal', n=8, sides=4, rv=.0095)
    hoop(s, 'Detail anchor chain 1', hook + Vector((0, -.022, 0)), radial, .006, anc0, '6B6F78', .0022, 'metal', n=8, sides=4, rv=.0095)
    ar = hook + Vector((0, -.038, 0))
    anc1 = s.view_bone('fx_spring_anchor_1', anc0, tuple(ar))
    hoop(s, 'Anchor ring', ar, radial, .0085, anc1, BRASS, .0028, 'brass', n=10, sides=5)
    s.tube('Anchor shank', [ar + Vector((0, -.008, 0)), ar + Vector((0, -.088, 0))], [.0048, .0042], anc1, BRASS, 'brass', n=6)
    s.tube('Anchor stock', [ar + Vector((0, -.018, 0)) - tang * .024, ar + Vector((0, -.018, 0)) + tang * .024], .0038, anc1, BRASS_DK, 'brass', n=6)
    ac = ar + Vector((0, -.066, 0))
    arc = [ac + tang * (math.cos(math.radians(d)) * .03) + Vector((0, math.sin(math.radians(d)) * .03, 0)) for d in range(200, 341, 20)]
    s.tube('Anchor arms', arc, .0048, anc1, BRASS, 'brass', n=6)
    for side in (-1, 1):
        tip = ac + tang * (side * math.cos(math.radians(20)) * .03) + Vector((0, -math.sin(math.radians(20)) * .03, 0))
        oellipsoid(s, 'Detail anchor fluke %d' % side, tip + Vector((0, .006, 0)) + tang * (side * .003), (tang * side, Vector((0, 1, 0)), radial), (.009, .012, .0026),
                   anc1, BRASS_HI, 'brass', n=6, m=3)

    # ======================= arms: canvas sleeves, patched elbows, brass cuffs, gauntlets =======================
    for side, suffix in [(1, 'l'), (-1, 'r')]:
        x = .3 * side
        ua = s.capsule('Sleeve ' + suffix, (x, 1.3, 0), (x, 1.07, -.004), .087, 'uarm_' + suffix, CANVAS, 'cloth', n=20)
        fa = s.capsule('Forearm sleeve ' + suffix, (x, 1.045, -.004), (x, .905, .006), .08, 'farm_' + suffix, CANVAS, 'cloth', n=20)
        s.paint(ua, canvas_paint)
        s.paint(fa, canvas_paint)
        s.tube('Team armband ' + suffix, [(x, 1.15, -.001), (x, 1.19, -.002)], [.0925, .0925], 'uarm_' + suffix, 'FFFFFF', 'team', n=20)
        # elbow patch sewn over the back of the joint, split between upper arm and forearm
        ep = _limb_patch(s, 'Detail elbow patch ' + suffix, Surface([ua, fa]), (x, -.004), math.pi - side * .35, 1.05, .048, .052, .006, .088,
                         'farm_' + suffix, LEATHER_HI if side > 0 else TAN, stitch)
        _split_weights(ep, 'uarm_' + suffix, 'farm_' + suffix, 1.035, .035, .25)
        # brass cuff over the sleeve end, the violet leak at the wrist, the gauntlet
        cuff = s.tube('Brass cuff ' + suffix, [(x, .936, .005), (x, .929, .005), (x, .914, .006), (x, .907, .006)], [.083, .087, .087, .083], 'farm_' + suffix, BRASS, 'brass', n=20)
        s.paint(cuff, brass_paint)
        for k in range(4):
            a = TAU * k / 4 + TAU / 8
            facing(s, 'Detail cuff rivet %s%d' % (suffix, k), (x + math.sin(a) * .088, .9215, .006 + math.cos(a) * .088), (math.sin(a), 0, math.cos(a)),
                   (.0062, .0062, .004), 'farm_' + suffix, BRASS_HI, 'brass', n=6, m=3)
        hoop(s, 'Detail wrist leak ' + suffix, (x, .9015, .007), (0, 1, 0), .079, 'farm_' + suffix, GHOST, .0062, 'ghost', glow=.7, n=20, sides=4, up=(0, 0, 1))
        gc = s.tube('Gauntlet cuff ' + suffix, [(x, .9, .007), (x, .885, .008), (x, .862, .01)], [.08, .083, .087], 'farm_' + suffix, LEATHER, 'cloth', n=20)
        s.paint(gc, leather_paint)
        mitt = s.ellipsoid('Gauntlet ' + suffix, (x, .795, .014), (.095, .1, .097), 'farm_' + suffix, LEATHER, 'cloth', n=24, m=12)
        s.paint(mitt, leather_paint)
        th = s.capsule('Gauntlet thumb ' + suffix, (x - side * .062, .835, .045), (x - side * .07, .787, .084), .029, 'farm_' + suffix, LEATHER, 'cloth', n=10, soft=False)
        s.paint(th, leather_paint)
        # brass knuckle plate across the striking face
        kp = []
        for i in range(9):
            u = -.062 + .124 * i / 8
            yy = .827
            zz = .014 + .097 * math.sqrt(max(0.0, 1 - (u / .095) ** 2 - ((yy - .795) / .1) ** 2)) + .004
            kp.append((x + u, yy + .004 * (1 - (u / .062) ** 2), zz))
        kpo = s.tube('Knuckle plate ' + suffix, kp, [.008, .0115, .013, .0135, .0135, .0135, .013, .0115, .008], 'farm_' + suffix, BRASS, 'brass', n=8)
        s.paint(kpo, brass_paint)
        for k in range(4):
            u = -.045 + .03 * k
            zz = .014 + .097 * math.sqrt(max(0.0, 1 - (u / .095) ** 2 - ((.829 - .795) / .1) ** 2)) + .016
            facing(s, 'Detail knuckle rivet %s%d' % (suffix, k), (x + u, .829, zz), (u * 4, .25, 1), (.0055, .0055, .0035), 'farm_' + suffix, BRASS_HI, 'brass', n=6, m=3)
        # stitched seam down the back of the sleeve
        _seam(s, 'sleeve seam ' + suffix, [(x + side * .02, y, -math.sqrt(max(0.0, .0905 ** 2 - .02 ** 2))) for y in _steps(1.27, 1.1, .014)], 'uarm_' + suffix)

    # ======================= legs: canvas trousers, patched knees, lead-soled boots =======================
    for side, suffix in [(1, 'l'), (-1, 'r')]:
        x = .12 * side
        th = s.capsule('Trouser ' + suffix, (x, .79, 0), (x, .47, .006), .102, 'thigh_' + suffix, CANVAS, 'cloth', n=20)
        sh = s.capsule('Shin ' + suffix, (x, .452, .006), (x, .3, .002), .088, 'shin_' + suffix, CANVAS, 'cloth', n=16)
        s.paint(th, canvas_paint)
        s.paint(sh, canvas_paint)
        # patched knee (left: a broad tan patch, right: a round brick-red one)
        kp_r = (.056, .06) if side > 0 else (.05, .05)
        kpatch = _limb_patch(s, 'Detail knee patch ' + suffix, Surface([th, sh]), (x, .004), side * .15, .45, kp_r[0], kp_r[1], .006, .1,
                             'shin_' + suffix, TAN if side > 0 else BRICK, stitch)
        _split_weights(kpatch, 'thigh_' + suffix, 'shin_' + suffix, .43, .04, .2)
        _seam(s, 'trouser seam ' + suffix, [(x + side * .1025, y, .002) for y in _steps(.76, .5, .014)], 'thigh_' + suffix)
        # the boot: leather shaft with a folded cuff, a heavy foot, brass toe cap, lead sole and heel
        bs = s.tube('Boot shaft ' + suffix, [(x, .318, .003), (x, .311, .003), (x, .298, .004), (x, .29, .004), (x, .2, .006), (x, .13, .012)],
                    [.09, .1, .1, .094, .093, .092], 'shin_' + suffix, LEATHER, 'cloth', n=20)
        s.paint(bs, leather_paint)
        _vcol(bs, lambda i, p, c: (leather_hi[0], leather_hi[1], leather_hi[2], c[3]) if i // 20 in (1, 2) else c)
        foot_path = [(x, .066, -.088), (x, .072, -.06), (x, .08, -.01), (x, .074, .05), (x, .064, .11), (x, .058, .16), (x, .056, .19), (x, .055, .203)]
        foot_r = [(.05, .03), (.08, .056), (.09, .07), (.091, .063), (.089, .052), (.08, .044), (.055, .034), (.02, .015)]
        foot = s.tube('Boot foot ' + suffix, foot_path, foot_r, 'shin_' + suffix, LEATHER, 'cloth', n=20)
        s.paint(foot, leather_paint)
        toe = s.ellipsoid('Brass toe cap ' + suffix, (x, .06, .158), (.087, .049, .058), 'shin_' + suffix, BRASS, 'brass', n=20, m=10)
        s.paint(toe, brass_paint)
        for k in range(3):
            a = math.radians(-45 + 45 * k)
            facing(s, 'Detail toe rivet %s%d' % (suffix, k), (x + math.sin(a) * .08, .074, .158 - math.cos(a) * .036), (math.sin(a), .5, -.3),
                   (.005, .005, .0035), 'shin_' + suffix, BRASS_HI, 'brass', n=6, m=3)
        sole = s.box('Lead sole ' + suffix, (x, .017, .056), (.19, .03, .318), 'shin_' + suffix, LEAD, 'metal', .012)
        s.paint(sole, lead_paint)
        heel = s.box('Lead heel ' + suffix, (x, .04, -.062), (.15, .03, .075), 'shin_' + suffix, LEAD_DK, 'metal', .008)
        s.paint(heel, lead_paint)
        for k, (zz, yc, rx, ry) in enumerate([(.03, .077, .0905, .066), (.088, .0675, .0898, .0565)]):
            # straps over the instep, following the foot's cross-section, buckled on the outside
            strap = [(x + math.cos(math.pi * i / 12) * (rx + .005), yc + math.sin(math.pi * i / 12) * (ry + .005), zz) for i in range(13)]
            s.tube('Boot strap %s%d' % (suffix, k), strap, .0072, 'shin_' + suffix, LEATHER_DK, 'cloth', n=5)
            facing(s, 'Detail boot buckle %s%d' % (suffix, k), (x + side * (rx + .011), yc + .01, zz), (side, 0, 0), (.011, .013, .004), 'shin_' + suffix, BRASS, 'brass', n=6, m=3)

    # ======================= stitched seams on the suit =======================
    for name, a, y0, y1, bone in [('front', 0.0, 1.23, .945, 'chest'), ('back', math.pi, 1.235, .945, 'chest'), ('side l', math.pi / 2, 1.27, .945, 'chest'),
                                  ('side r', -math.pi / 2, 1.27, .945, 'chest'), ('hip l', math.pi / 2, .85, .72, 'pelvis'), ('hip r', -math.pi / 2, .85, .72, 'pelvis')]:
        pts_ = []
        for y in _steps(y0, y1, .014):
            p, nrm = body_surf.radial(y, a)
            if p is not None:
                pts_.append(p + nrm * .0022)
        _seam(s, 'suit seam ' + name, pts_, bone)

    # ======================= the air hose: gooseneck -> over the corselet -> down the back -> a loose curl =======================
    ctrl = [(0, 1.504, -.227), (-.003, 1.462, -.214), (-.01, 1.42, -.207), (-.02, 1.372, -.218), (-.034, 1.322, -.238), (-.05, 1.278, -.258), (-.066, 1.235, -.276),
            (-.084, 1.19, -.277), (-.1, 1.162, -.274)]
    cc = Vector((-.102, 1.134, -.272))
    for d in range(100, 350, 30):
        rr = .032 - .004 * (d - 100) / 240
        ctrl.append((cc.x + math.cos(math.radians(d)) * rr, cc.y + math.sin(math.radians(d)) * rr, cc.z - .01 * (d - 100) / 240))
    dense = catmull(ctrl, 8)
    dl = arclen(dense)
    hose_pts, hs = resample(dense, dl, .0105)
    key_s = [dl[8 * i] for i in (0, 3, 6, 8)]
    link_ring = [min(range(len(hs)), key=lambda r, ks=ks: abs(hs[r] - ks)) for ks in key_s]
    hose_r = [.0205 if r % 3 == 0 else .0188 for r in range(len(hose_pts))]     # corrugated rubber
    links = []
    parent = 'head'
    for k, ri in enumerate(link_ring):
        links.append(s.view_bone('fx_spring_hose_%d' % k, parent, tuple(hose_pts[ri])))
        parent = links[-1]
    hose = s.tube('Air hose', hose_pts, hose_r, links[0], HOSE, 'cloth', n=8)
    chain_skin(hose, 8, hs, links, [hs[ri] for ri in link_ring])
    hose_c, hose_d = lin(HOSE), lin(HOSE_DK)
    _vcol(hose, lambda i, p, c: (hose_d[0], hose_d[1], hose_d[2], 0.0) if (i // 8) % 3 == 0 else (hose_c[0], hose_c[1], hose_c[2], 0.0))
    end = hose_pts[-1]
    tdir = (hose_pts[-1] - hose_pts[-2]).normalized()
    s.tube('Hose end coupling', [end - tdir * .012, end + tdir * .006], [.0235, .0235], links[-1], BRASS, 'brass', n=8)
    facing(s, 'Detail hose end glow', end + tdir * .0065, tdir, (.016, .016, .003), links[-1], GHOST_HI, 'ghost', glow=.8, n=10, m=3)

    # ======================= ghost wisps leaking from the collar, the exhaust valve and the crown =======================
    w_hi, w_mid, w_dk = lin('B08CFF'), lin('8A5CF5'), lin('5530D6')
    wisps = [('l', [(.112, 1.42, -.125), (.135, 1.452, -.172), (.15, 1.51, -.2), (.143, 1.575, -.21), (.12, 1.625, -.198), (.098, 1.645, -.17), (.094, 1.628, -.15)], .022),
             ('r', [tuple(ev + evn * .03), tuple(ev + evn * .05 + Vector((0, .03, -.015))), (-.232, 1.585, -.125), (-.222, 1.64, -.105), (-.195, 1.675, -.085),
                    (-.172, 1.678, -.068), (-.168, 1.66, -.06)], .02),
             ('v', [tuple(cv + cvn * .018), tuple(cv + cvn * .042 + Vector((0, 0, -.012))), (.01, 1.785, -.115), (-.008, 1.79, -.14), (-.024, 1.778, -.157),
                    (-.029, 1.761, -.158)], .019)]
    for suffix, ctrl_w, r0 in wisps:
        wp = catmull(ctrl_w, 4)
        ws = arclen(wp)
        L = ws[-1]
        b0 = s.view_bone('fx_spring_wisp_%s_0' % suffix, 'head', tuple(wp[0]))
        mid = len(wp) // 2
        b1 = s.view_bone('fx_spring_wisp_%s_1' % suffix, b0, tuple(wp[mid]))
        radii = [r0 * (1 - sv / L) ** .55 * (1 + .3 * math.sin(sv / L * math.pi * 5)) + .0025 for sv in ws]
        wo = s.tube('Detail wisp ' + suffix, wp, radii, b0, GHOST, 'ghost', n=8)
        chain_skin(wo, 8, ws, [b0, b1], [0.0, ws[mid]])

        def wisp_col(i, p, c, ws=ws, L=L):
            t = ws[i // 8] / L
            col = mix(w_hi, w_mid, t * 2.0)
            col = mix(col, w_dk, (t - .5) * 2.0)
            return (col[0], col[1], col[2], 1.0 - .35 * t)
        _vcol(wo, wisp_col)

    # ======================= gore: the exhaust valve cap pops off =======================
    s.tube('Gore - exhaust valve cap', [(0, 0, 0), (0, .006, 0), (0, .05, 0), (0, .058, 0), (0, .075, 0), (0, .09, 0)], [.03, .048, .048, .04, .02, .004], None, BRASS, 'brass', n=16, role='gore')

    registration_report(s)
    s.set_look({'glow_mode': 'shimmer', 'fx': {'pupil_reach': .007, 'jaw_deg': 22, 'brow_drop': .006, 'lid_rest': .17, 'spring_gain': .95, 'spring_stiffness': .85}})
    s.bake_ao(rays=14, distance=.085, strength=.36)


def _steps(a, b, step):
    n = max(1, int(round(abs(b - a) / step)))
    return [a + (b - a) * i / n for i in range(n + 1)]


def _seam(s, name, pts, bone):
    """A stitched seam: a thin welt with pale stitches painted on every other ring."""
    if len(pts) < 2:
        return None
    obj = s.tube('Detail ' + name, pts, .0032, bone, WELT, 'cloth', n=4)
    st, we = lin(STITCH), lin(WELT)
    _vcol(obj, lambda i, p, c: (st[0], st[1], st[2], 0.0) if (i // 4) % 2 == 0 else (we[0], we[1], we[2], 0.0))
    return obj


def _limb_patch(s, name, surf, axis_xz, heading, y0, rx, ry, h, R, bone, color, stitch, n=16):
    """A sewn-on canvas/leather patch conformed to a limb: each ring is cast onto the limb's visible
    surface from outside and lifted off it (a low cushion); running stitches on the row just inside
    the rim. heading: where round the limb it sits (0 = forward, +pi/2 = the creature's left)."""
    ax, az = axis_xz
    rings = []
    for f, lift in [(.42, h), (.8, h * .85), (.91, h * .5), (1.0, -.0015)]:
        ring = []
        for i in range(n):
            a = TAU * i / n
            th = heading + rx * f * math.cos(a) / R
            d = Vector((math.sin(th), 0, math.cos(th)))
            o = Vector((ax, y0 + ry * f * math.sin(a), az))
            p, nrm = surf.hit(o + d * .3, -d)
            ring.append(p + nrm * lift)
        rings.append(ring)
    obj = loft(s, name, rings, bone, color, 'cloth')
    attr = obj.data.color_attributes['Color']
    for i in range(0, n, 2):
        attr.data[2 * n + i].color = (stitch[0], stitch[1], stitch[2], 0.0)
    return obj


def _split_weights(obj, upper, lower, y_lo, span, base):
    """Share a part that sits over a joint between the bone above and the one below it."""
    ug = obj.vertex_groups.get(upper) or obj.vertex_groups.new(name=upper)
    lg = obj.vertex_groups[lower]
    for v in obj.data.vertices:
        w_up = max(0.0, min(1.0, (v.co.z - y_lo) / span))
        ug.add([v.index], base + .5 * w_up, 'REPLACE')
        lg.add([v.index], 1 - base - .5 * w_up, 'REPLACE')
