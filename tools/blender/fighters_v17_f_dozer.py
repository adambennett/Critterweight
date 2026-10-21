"""v0.9.17 art for Dozer, the Shovelsnout (f_dozer; docs/ART_REVAMP.md "v0.9.17").

A friendly, heavy, single-minded digging hog on the locked quadruped body. What reads from the high
3/4 fight camera: shingled ochre armour scutes from the hump to the tail (pauldrons on the shoulders,
a rump shield and a tail guard; dark rolled rims, iron rivets, scuffed edges, dust packed into the
cracks), the brass-bezelled headlamp behind a horn-base plate (his Hype feature: material 'lamp', glow
mode 'lamp') with its strapped-on battery pack on the hump, the horn and the curved steel shovel snout
(worn bright edge, scratches, riveted mount). Rigged face: eyes with lids tucked under hide lid-folds,
brows, a lower jaw under the shovel (tongue and two blunt tusks show when it drops); floppy spring
ears, a corkscrew spring tail and a swinging brass tool tag on the collar. Caked dust on the belly,
mud on the legs and haunches. Team colour: the girth strap round the chest and tape above the front
knees.

Every coordinate is fighter rest space (+Z forward, +Y up, +X the creature's left). Armour is laid on
the collision envelope itself (closest-point projection onto the chest/pelvis/head shapes), so hard
parts stay within ~5 cm of it and the soft ones (ears, tail curl, tag) within ~8 cm. No segment bone,
pivot or body data changes; the fx_* view bones are extra joints the game animates.
"""
import math
from mathutils import Vector
from fighters_v17 import mix, lin, cell_spots, densify, ring_xy, _hash

HIDE = '6E6A66'; HIDE_TOP = '5E5A57'; HIDE_BELLY = '86807A'; MOTTLE = '5A5653'; LID = '625E5A'; LEG_LIGHT = '96908A'
DUST = 'D9C7A3'; MUD = '5E5144'; MUD_DRY = '9A8A74'
# the palette's plate ochre (#C7A160) washes out to beige under the arena light and AgX tonemapping, so
# the scutes are painted a deeper, more saturated ochre that reads as the palette's ochre on screen
OCHRE = 'C08A36'; OCHRE_DEEP = '8C5F22'; OCHRE_PALE = 'DDB66B'; RIM = '3B2A19'; CRACK = '3E2B1A'
STEEL = '9FA6AD'; STEEL_BRIGHT = 'E8EDF0'; STEEL_DARK = '5F666D'; IRON = '45433F'
BRASS = 'C9A227'; LAMP = 'FFE066'; LEATHER = '4E3829'; IVORY = 'DCD4C2'; HOOF = '332E2B'
SNOUT = 'A08F89'; INNER_EAR = 'B9908A'; DARK = '2B2624'; MOUTH = '3B1A1C'; TONGUE = 'C2767A'

PLATE_MAT = 'brass'   # the scutes: 'shell' read as glazed pastry under the arena lights, brass as armour
RIVET = '3C3835'
HEAD_C = Vector((0, .785, .958)); HEAD_R = Vector((.2, .193, .2))


# ---- small maths -----------------------------------------------------------------------------------
def _smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def _vnoise(p, scale, seed):
    q = (p[0] / scale, p[1] / scale, p[2] / scale)
    i0 = [math.floor(v) for v in q]
    f = [q[k] - i0[k] for k in range(3)]
    f = [t * t * (3 - 2 * t) for t in f]
    acc = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[0] if dx else 1 - f[0]) * (f[1] if dy else 1 - f[1]) * (f[2] if dz else 1 - f[2])
                acc += w * _hash(seed, i0[0] + dx, i0[1] + dy, i0[2] + dz)
    return acc


def _fbm(p, scale, seed, octaves=3):
    a, tot, amp = 0.0, 0.0, 1.0
    for o in range(octaves):
        a += amp * _vnoise(p, scale / (2 ** o), seed + 17 * o)
        tot += amp
        amp *= .5
    return a / tot


def _c(col, a=0.0):
    return (col[0], col[1], col[2], a)


def _seg2(p, a, b):
    """Distance from 2D point p to segment ab."""
    ax, ay = b[0] - a[0], b[1] - a[1]
    t = max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / max(1e-9, ax * ax + ay * ay)))
    return math.hypot(p[0] - a[0] - ax * t, p[1] - a[1] - ay * t)


def _head_z(x, y, off=0.0):
    """z of the head's front surface at (x, y) (the Head ellipsoid), pushed out by off."""
    k = 1 - (x / HEAD_R.x) ** 2 - ((y - HEAD_C.y) / HEAD_R.y) ** 2
    return HEAD_C.z + HEAD_R.z * math.sqrt(max(0.0, k)) + off


# ---- the collision envelope ----------------------------------------------------------------------------
def _sd(sh, p):
    if sh['type'] == 'sphere':
        return (p - Vector(sh['center'])).length - sh['radius']
    if sh['type'] == 'capsule':
        a, b = Vector(sh['a']), Vector(sh['b'])
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
        return (p - a - ab * t).length - sh['radius']
    d = p - Vector(sh['center'])
    half = Vector(sh['size']) / 2
    q = Vector([abs(d[i]) - half[i] for i in range(3)])
    return Vector([max(0.0, v) for v in q]).length + min(max(q), 0.0)


def _sdf(shapes, p, k=.03):
    """Smooth union (the crease between two shapes is filled, so plates bridge it)."""
    vals = [_sd(sh, p) for sh in shapes]
    m = min(vals)
    return m - k * math.log(sum(math.exp(-(v - m) / k) for v in vals))


def _grad(shapes, p, h=.0008):
    g = Vector([_sdf(shapes, p + Vector([h if i == k else 0 for i in range(3)])) -
                _sdf(shapes, p - Vector([h if i == k else 0 for i in range(3)])) for k in range(3)])
    return g.normalized()


def _project(shapes, q):
    """Closest point of the envelope surface to q, and the outward normal there."""
    p = Vector(q)
    for _ in range(7):
        p = p - _grad(shapes, p) * _sdf(shapes, p)
    return p, _grad(shapes, p)


def _shapes(s, *bones):
    return [sh for b in bones for sh in s.segments[b]['shapes']]


def _set_cols(obj, cols):
    attr = obj.data.color_attributes['Color']
    for k, col in enumerate(cols):
        attr.data[k].color = col


def _weights(obj, fn):
    """Re-skin an object: fn(fighter_pos) -> {bone: weight} (normalised by the exporter)."""
    for g in list(obj.vertex_groups):
        obj.vertex_groups.remove(g)
    groups = {}
    for v in obj.data.vertices:
        p = Vector((v.co.x, v.co.z, -v.co.y))
        for bone, w in fn(p).items():
            if w <= 1e-4:
                continue
            if bone not in groups:
                groups[bone] = obj.vertex_groups.new(name=bone)
            groups[bone].add([v.index], w, 'REPLACE')


def _xform(obj, fn):
    """Move an object's vertices: fn(fighter_pos) -> fighter_pos."""
    for v in obj.data.vertices:
        q = fn(Vector((v.co.x, v.co.z, -v.co.y)))
        v.co = Vector((q.x, -q.z, q.y))
    obj.data.update()


def _rot_x(c, ang):
    """Rotation about the fighter x axis through c (positive tips +y toward +z)."""
    cs, sn = math.cos(ang), math.sin(ang)

    def f(p):
        d = p - c
        return c + Vector((d.x, d.y * cs - d.z * sn, d.y * sn + d.z * cs))
    return f


def _blob(s, name, c, r, bone, color, mat='skin', n=16, m=8, xf=None, glow=0):
    """An ellipsoid (Studio topology) whose vertices pass through xf(local offset) first."""
    verts = [(0, -r[1], 0)]
    for j in range(1, m):
        lat = -math.pi / 2 + math.pi * j / m
        for i in range(n):
            a = math.tau * i / n
            verts.append((r[0] * math.cos(lat) * math.cos(a), r[1] * math.sin(lat), r[2] * math.cos(lat) * math.sin(a)))
    verts.append((0, r[1], 0))
    top = len(verts) - 1
    faces = [(0, 1 + i, 1 + (i + 1) % n) for i in range(n)]
    for j in range(m - 2):
        for i in range(n):
            a = 1 + j * n + i
            b = 1 + j * n + (i + 1) % n
            faces.append((a, a + n, b + n, b))
    for i in range(n):
        faces.append((top, 1 + (m - 2) * n + (i + 1) % n, 1 + (m - 2) * n + i))
    out = []
    for v in verts:
        q = Vector(v)
        if xf:
            q = xf(q)
        out.append(tuple(Vector(c) + q))
    return s.mesh(name, out, faces, bone, color, mat, glow)


# ---- armour plates -------------------------------------------------------------------------------------
def _patch(s, name, shapes, bone, nu, nv, geo, prof, col, mat=None, pad=.015):
    """A closed armour slab laid on the envelope. geo(u, v) -> (guide point, w, c): w runs 0..1 toward
    the free (rimmed) edge, c -1..1 across. prof(w, c) -> (underside, top) offsets along the normal.
    col(w, c, top, p, n) -> linear rgba. Returns the object and a sampler for rims and rivets."""
    grid = []
    for j in range(nv):
        row = []
        for i in range(nu):
            q, w, c = geo(i / (nu - 1), j / (nv - 1))
            p, n = _project(shapes, q)
            row.append((p, n, w, c))
        grid.append(row)
    verts, cols = [], []
    for top in (0, 1):
        for j in range(nv):
            for i in range(nu):
                p, n, w, c = grid[j][i]
                lo, hi = prof(w, c)
                q = p + n * (pad + (hi if top else lo))
                verts.append(tuple(q))
                cols.append(col(w, c, top, q, n))

    def ix(top, i, j):
        return top * nu * nv + j * nu + i
    faces = []
    for j in range(nv - 1):
        for i in range(nu - 1):
            faces.append((ix(1, i, j), ix(1, i + 1, j), ix(1, i + 1, j + 1), ix(1, i, j + 1)))
            faces.append((ix(0, i, j), ix(0, i, j + 1), ix(0, i + 1, j + 1), ix(0, i + 1, j)))
    for i in range(nu - 1):
        faces.append((ix(0, i, 0), ix(0, i + 1, 0), ix(1, i + 1, 0), ix(1, i, 0)))
        faces.append((ix(0, i, nv - 1), ix(1, i, nv - 1), ix(1, i + 1, nv - 1), ix(0, i + 1, nv - 1)))
    for j in range(nv - 1):
        faces.append((ix(0, 0, j), ix(1, 0, j), ix(1, 0, j + 1), ix(0, 0, j + 1)))
        faces.append((ix(0, nu - 1, j), ix(0, nu - 1, j + 1), ix(1, nu - 1, j + 1), ix(1, nu - 1, j)))
    obj = s.mesh(name, verts, faces, bone, OCHRE, mat or PLATE_MAT)
    _set_cols(obj, cols)

    def top_at(u, v, lift=0.0):
        q, w, c = geo(u, v)
        p, n = _project(shapes, q)
        lo, hi = prof(w, c)
        return p + n * (pad + hi + lift), n
    return obj, grid, top_at


def _ribbon(s, name, pts, nrms, bone, color, mat='cloth', hw=.016, th=.005):
    """A flat strap lying on a surface: a box-section ribbon through pts, its broad face along nrms."""
    pts = [Vector(p) for p in pts]
    verts = []
    for i, p in enumerate(pts):
        tg = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        n = Vector(nrms[i]).normalized()
        b = n.cross(tg).normalized()
        n = tg.cross(b).normalized()
        for sb, sn in ((1, 1), (-1, 1), (-1, -1), (1, -1)):
            verts.append(tuple(p + b * (sb * hw) + n * (sn * th)))
    faces = []
    for i in range(len(pts) - 1):
        for k in range(4):
            a, c = i * 4 + k, i * 4 + (k + 1) % 4
            faces.append((a, c, c + 4, a + 4))
    faces.append((3, 2, 1, 0))
    last = (len(pts) - 1) * 4
    faces.append((last, last + 1, last + 2, last + 3))
    return s.mesh(name, verts, faces, bone, color, mat)


def _rim(s, name, grid, prof, bone, pad=.015, radius=.0105, sink=.004):
    """The dark rolled lip along a plate's free edge (the last grid row)."""
    pts = []
    for p, n, w, c in grid[-1]:
        lo, hi = prof(w, c)
        pts.append(tuple(p + n * (pad + hi - sink)))
    return s.tube(name, pts, radius, bone, RIM, 'metal', n=6)


def _rivets(s, name, top_at, us, v, bone, r=.0088):
    for k, u in enumerate(us):
        p, n = top_at(u, v, .0015)
        _blob(s, 'Detail rivet %s %d' % (name, k), p, (r, r * .8, r), bone, RIVET, 'metal', n=6, m=3,
              xf=_align_y(n))


def _align_y(n):
    """xf for _blob: turn the blob's local +y onto n."""
    n = Vector(n).normalized()
    up = Vector((0, 1, 0))
    axis = up.cross(n)
    if axis.length < 1e-6:
        return None
    ang = math.acos(max(-1.0, min(1.0, up.dot(n))))
    from mathutils import Matrix
    m = Matrix.Rotation(ang, 3, axis.normalized())
    return lambda q: m @ q


def _plate_col(seed, cracks, under=RIM):
    """Ochre scute paint: broad tonal drift, worn pale edges, grime before the rim, cracks packed with
    pale dust, settled dust on the upward faces."""
    def col(w, c, top, p, n):
        if not top:
            return _c(lin(under))
        f = _fbm(p, .11, seed)
        cc = mix(lin(OCHRE), lin(OCHRE_DEEP), max(0.0, f - .5) * 1.7)
        cc = mix(cc, lin(OCHRE_PALE), max(0.0, .45 - f) * 1.3)
        edge = max(_smooth(.78, .97, abs(c)), _smooth(.14, 0.0, w))
        scuff = _fbm(p, .03, seed + 3)
        cc = mix(cc, lin(OCHRE_PALE), edge * (.35 + .6 * scuff))
        cc = mix(cc, lin(OCHRE_DEEP), _smooth(.58, .84, w) * .45)
        for poly in cracks:
            d = min(_seg2((c, w), poly[i], poly[i + 1]) for i in range(len(poly) - 1))
            if d < .13:
                cc = mix(cc, lin(DUST), (1 - d / .13) * .55)
            if d < .065:
                cc = mix(cc, lin(CRACK), (1 - d / .065) * .85)
        dust = _smooth(.56, .78, _fbm(p, .055, seed + 7)) * max(0.0, n.y) * .45
        cc = mix(cc, lin(DUST), dust)
        return _c(cc)
    return col


def _band_geo(zf, zr, half_th, yaxis, k=.7, chev=.035, R=.47):
    zc, zh = (zf + zr) / 2, (zf - zr) / 2

    def geo(u, v):
        sa, ta = 2 * u - 1, 2 * v - 1
        s2 = sa * math.sqrt(1 - k * ta * ta / 2)
        t2 = ta * math.sqrt(1 - k * sa * sa / 2)
        z = zc - t2 * zh - chev * (1 - abs(s2)) ** 2 * (1 + t2) / 2
        a = s2 * half_th
        q = Vector((0, yaxis(z), z)) + Vector((math.sin(a), math.cos(a), 0)) * R
        return q, (1 + t2) / 2, s2
    return geo


def _band_prof(half_th, lift=.012, keel=.007, shoulder=0.0, thick=.011):
    def prof(w, c):
        lo = lift * w * w + shoulder * _smooth(.7, .97, abs(c))
        th = .006 + thick * _smooth(0.0, .32, w)
        kl = keel * max(0.0, 1 - abs(c) * half_th / .38) ** 2 * _smooth(.1, .45, w)
        return lo, lo + th + kl
    return prof


def _side_geo(side, zf, zr, th_top, th_bot, yaxis, k=.95, R=.47):
    """A shoulder plate (pauldron) on the flank: u runs along the body, v down the side to the rim."""
    zc, zh = (zf + zr) / 2, (zf - zr) / 2
    tc, th = (th_top + th_bot) / 2, (th_bot - th_top) / 2

    def geo(u, v):
        sa, ta = 2 * u - 1, 2 * v - 1
        s2 = sa * math.sqrt(1 - k * ta * ta / 2)
        t2 = ta * math.sqrt(1 - k * sa * sa / 2)
        z = zc - s2 * zh * (1 + .12 * t2)
        a = side * (tc + t2 * th)
        q = Vector((0, yaxis(z), z)) + Vector((math.sin(a), math.cos(a), 0)) * R
        return q, (1 + t2) / 2, s2
    return geo


def _dome_geo(centre, b0, b1, half_phi, k=.7, R=.45):
    """A plate on a capsule's rear dome: phi across the back, beta from the top toward the rear."""
    centre = Vector(centre)

    def geo(u, v):
        sa, ta = 2 * u - 1, 2 * v - 1
        s2 = sa * math.sqrt(1 - k * ta * ta / 2)
        t2 = ta * math.sqrt(1 - k * sa * sa / 2)
        beta = b0 + (t2 + 1) / 2 * (b1 - b0)
        phi = s2 * half_phi
        d = Vector((math.sin(phi) * math.cos(beta), math.cos(phi) * math.cos(beta), -math.sin(beta)))
        return centre + d * R, (1 + t2) / 2, s2
    return geo


def _cap_geo(centre, a0, a1, b_rear, b_front, k=.6, R=.3):
    """The forehead plate on the head sphere: a from the crown (a0) toward the brow (a1), its half
    width narrowing from b_rear to b_front; the rim is the front (brow) edge."""
    centre = Vector(centre)

    def geo(u, v):
        sa, ta = 2 * u - 1, 2 * v - 1
        s2 = sa * math.sqrt(1 - k * ta * ta / 2)
        t2 = ta * math.sqrt(1 - k * sa * sa / 2)
        f = (t2 + 1) / 2
        a = a0 + f * (a1 - a0)
        b = s2 * (b_rear + f * (b_front - b_rear))
        d = Vector((math.sin(b), math.cos(b) * math.cos(a), math.cos(b) * math.sin(a)))
        return centre + d * R, f, s2
    return geo


# ---- soft parts ----------------------------------------------------------------------------------------
def _leaf(s, name, base, tip, wdir, bone, out_col, in_col, width=.09, thick=.013, cup=.014, droop=.025, nu=7, nv=9, out_dir=(0, 1, 0)):
    """A floppy ear: a pointed leaf from base to tip, cupped toward its inner face (the edges and the
    tip curl that way); the outer face (toward out_dir) is hide, the inner face lighter."""
    base, tip = Vector(base), Vector(tip)
    ax = (tip - base)
    ln = ax.length
    ax.normalize()
    wv = Vector(wdir)
    wv = (wv - ax * wv.dot(ax)).normalized()
    nr = ax.cross(wv)
    if nr.dot(Vector(out_dir)) < 0:
        nr = -nr
    verts, cols = [], []
    for top in (0, 1):
        for j in range(nv):
            v = j / (nv - 1)
            hw = max(.004, width * .5 * (1 - v) ** .8 * (.82 + .3 * math.sin(math.pi * min(1.0, v * 1.4))))
            for i in range(nu):
                u = 2 * i / (nu - 1) - 1
                th = thick * (1 - .55 * v) * (1 - .5 * u * u)
                q = base + ax * (v * ln) + wv * (u * hw) + nr * (-cup * u * u - droop * v * v + (th * .5 if top else -th * .5))
                verts.append(tuple(q))
                edge = max(abs(u), v)
                if top:
                    cols.append(_c(mix(lin(out_col), lin(MOTTLE), _smooth(.55, 1.0, edge) * .5)))
                else:
                    cols.append(_c(mix(lin(in_col), lin(out_col), _smooth(.5, .95, abs(u)) * .8)))

    def ix(top, i, j):
        return top * nu * nv + j * nu + i
    faces = []
    for j in range(nv - 1):
        for i in range(nu - 1):
            faces.append((ix(1, i, j), ix(1, i + 1, j), ix(1, i + 1, j + 1), ix(1, i, j + 1)))
            faces.append((ix(0, i, j), ix(0, i, j + 1), ix(0, i + 1, j + 1), ix(0, i + 1, j)))
    for i in range(nu - 1):
        faces.append((ix(0, i, 0), ix(0, i + 1, 0), ix(1, i + 1, 0), ix(1, i, 0)))
        faces.append((ix(0, i, nv - 1), ix(1, i, nv - 1), ix(1, i + 1, nv - 1), ix(0, i + 1, nv - 1)))
    for j in range(nv - 1):
        faces.append((ix(0, 0, j), ix(1, 0, j), ix(1, 0, j + 1), ix(0, 0, j + 1)))
        faces.append((ix(0, nu - 1, j), ix(0, nu - 1, j + 1), ix(1, nu - 1, j + 1), ix(1, nu - 1, j)))
    obj = s.mesh(name, verts, faces, bone, out_col, 'skin')
    _set_cols(obj, cols)
    return obj


# --------------------------------------------------------------------------------------------------------
def build(s):
    body_shapes = _shapes(s, 'chest', 'pelvis')

    def yaxis(z):
        return .76 + .06 * _smooth(-.35, -.1, z)

    # ---- hide paint ---------------------------------------------------------------------------------
    def hide(p, n, c, seed=5, belly=True):
        # coarse matte slate hide: darker along the top, paler underneath, only subtle DARK mottling
        # (pale blotches on a rounded body read as glossy reflections)
        col = mix(lin(HIDE), lin(HIDE_TOP), max(0.0, n.y) * .5)
        if belly:
            col = mix(col, lin(HIDE_BELLY), max(0.0, -n.y) * .45)
        m = _fbm(p, .09, seed)
        col = mix(col, lin(MOTTLE), _smooth(.55, .75, m) * .4)
        # coarse bristly grain: a per-vertex flicker of darker hide
        g = _hash(seed, int(p.x * 997), int(p.y * 991), int(p.z * 983))
        col = mix(col, lin(MOTTLE), max(0.0, g - .45) * .45)
        return col

    def body_paint(p, n, c):
        col = hide(p, n, c)
        # dry dust caked as a crust on the underside only (a pale band along the flank reads as a chrome
        # reflection on this rounded body), dark mud splashes kicked up onto the lower flanks/haunches
        under = _smooth(-.35, -.8, n.y) * _smooth(.6, .5, p.y)
        crust = _smooth(.4, .62, _fbm(p, .04, 9))
        col = mix(col, mix(lin(DUST), lin(MUD_DRY), .45), under * (.3 + .45 * crust))
        sp = cell_spots(p, .045, .55, .5, 21) * _smooth(.7, .55, p.y)
        sp = max(sp, cell_spots(p, .038, .62, .62, 23) * _smooth(-.45, -.7, p.z) * _smooth(.8, .64, p.y))
        if sp > .22:
            col = mix(col, lin(MUD), .72)
        return _c(col, c[3])

    # ---- body: one continuous barrel fitted to the chest + pelvis capsules ----------------------------
    pts = [(0, .76, -.935), (0, .76, -.90), (0, .76, -.82), (0, .76, -.70), (0, .76, -.55), (0, .77, -.40), (0, .79, -.25),
           (0, .81, -.10), (0, .82, .10), (0, .82, .30), (0, .82, .48), (0, .82, .62), (0, .82, .72), (0, .82, .79), (0, .82, .83)]
    rad = [.03, .17, .27, .33, .345, .36, .38, .40, .40, .40, .40, .37, .30, .20, .04]
    dp, dr = densify(pts, rad, 2)
    body = s.tube('Hog body - armoured barrel', dp, dr, 'chest', HIDE, n=44)
    s.fit(body, ['chest', 'pelvis'], (0, .8, -.05))
    pelvis = body.vertex_groups.new(name='pelvis')
    chest = body.vertex_groups['chest']
    for v in body.data.vertices:
        z = -v.co.y
        w = max(0, min(1, (z + .4) / .24))
        chest.add([v.index], w, 'REPLACE')
        pelvis.add([v.index], 1 - w, 'REPLACE')
    s.paint(body, body_paint)

    def neck_paint(p, n, c):
        col = hide(p, n, c, seed=8)
        col = mix(col, lin(DUST), _smooth(-.2, -.8, n.y) * _smooth(.66, .58, p.y) * .4)
        return _c(col, c[3])
    # the neck as a densified capsule: rings along its whole length (paint resolution, and the scarf
    # cosmetic's ring fit needs neck vertices to wrap, not just the two end rings of a plain capsule)
    na, nb, nr = Vector((0, .80, .64)), Vector((0, .785, .83)), .198
    nd = (nb - na).normalized()
    npts = [na + nd * nr * math.sin(t) for t in (-math.pi / 2 + .01, -math.pi / 3, -math.pi / 6)]
    nrad = [nr * math.cos(t) for t in (-math.pi / 2 + .01, -math.pi / 3, -math.pi / 6)]
    for k in range(6):
        npts.append(na.lerp(nb, k / 5))
        nrad.append(nr)
    npts += [nb + nd * nr * math.sin(t) for t in (math.pi / 6, math.pi / 3, math.pi / 2 - .01)]
    nrad += [nr * math.cos(t) for t in (math.pi / 6, math.pi / 3, math.pi / 2 - .01)]
    neck = s.tube('Neck', [tuple(p) for p in npts], nrad, 'neck', HIDE, n=26, soft=True)
    s.paint(neck, neck_paint)

    # ---- armour: shingled ochre scutes from the hump to the rump ------------------------------------
    bands = [  # name, bone, z front, z rear, half angle, shoulder lift, seed, cracks (c, w polylines)
        ('Scute nape', 'chest', .62, .36, math.radians(56), 0.0, 31, [[(-.3, 1), (-.22, .7), (-.3, .45)]]),
        ('Scute withers', 'chest', .41, .14, math.radians(74), .018, 32, [[(.42, 1), (.5, .72), (.44, .4)], [(-.62, 1), (-.7, .78)]]),
        ('Scute saddle', 'chest', .19, -.08, math.radians(74), .018, 33, [[(.1, 1), (.02, .66), (.1, .38)]]),
        ('Scute loin', 'chest', -.03, -.29, math.radians(70), 0.0, 34, [[(-.45, 1), (-.36, .7)], [(.66, 1), (.6, .74), (.68, .5)]]),
        ('Scute hip', 'pelvis', -.24, -.48, math.radians(68), 0.0, 35, [[(.25, 1), (.33, .64)]]),
        ('Scute croup', 'pelvis', -.43, -.65, math.radians(66), 0.0, 36, [[(-.15, 1), (-.24, .7), (-.16, .42)]]),
    ]
    for name, bone, zf, zr, half, sh_lift, seed, cracks in bands:
        prof = _band_prof(half, shoulder=sh_lift)
        obj, grid, top_at = _patch(s, name, body_shapes, bone, 20, 7, _band_geo(zf, zr, half, yaxis), prof,
                                   _plate_col(seed, cracks))
        _rim(s, name + ' rim', grid, prof, bone)
        _rivets(s, name, top_at, [.16, .38, .62, .84], .8, bone)
    # rump shield over the pelvis's rear dome
    prof = _band_prof(math.radians(64), lift=.01)
    obj, grid, top_at = _patch(s, 'Scute rump', body_shapes, 'pelvis', 22, 8, _dome_geo((0, .76, -.6), math.radians(4), math.radians(73), math.radians(64)),
                               prof, _plate_col(37, [[(.3, 1), (.22, .7), (.3, .4)], [(-.55, 1), (-.48, .7)], [(.05, .55), (-.05, .3)]]))
    _rim(s, 'Scute rump rim', grid, prof, 'pelvis')
    _rivets(s, 'rump', top_at, [.16, .33, .5, .67, .84], .84, 'pelvis')
    # a smaller tasset under the rump shield's lip, down to just above the tail: from behind the
    # shingles carry on down the rump instead of stopping at a bare grey ball
    prof = _band_prof(math.radians(26), lift=.008)
    obj, grid, top_at = _patch(s, 'Scute tasset', body_shapes, 'pelvis', 14, 7,
                               _cap_geo((0, .76, -.6), math.radians(-66), math.radians(-93), math.radians(25), math.radians(11), k=.8, R=.45),
                               prof, _plate_col(38, [[(-.2, 1), (-.12, .6)]]))
    _rim(s, 'Scute tasset rim', grid, prof, 'pelvis')
    _rivets(s, 'tasset', top_at, [.3, .7], .55, 'pelvis')
    # pauldrons: the shoulder plates under the withers bands (the shoulder barge leads with them)
    for side, sfx in [(1, 'l'), (-1, 'r')]:
        prof = _band_prof(1.0, lift=.016, keel=0.0, thick=.012)
        obj, grid, top_at = _patch(s, 'Pauldron ' + sfx, body_shapes, 'chest', 16, 8,
                                   _side_geo(side, .55, .13, math.radians(60), math.radians(117), yaxis), prof,
                                   _plate_col(40 + side, [[(.2, 1), (.28, .72), (.2, .5)], [(-.5, 1), (-.42, .8)]]))
        _rim(s, 'Pauldron rim ' + sfx, grid, prof, 'chest', radius=.012)
        _rivets(s, 'pauldron ' + sfx, top_at, [.16, .38, .62, .84], .78, 'chest')

    # ---- team colour: the girth strap round the chest, tucked under the band ends --------------------
    gz = .055
    girth = []
    for i in range(31):
        th = math.radians(71 + 218 * i / 30)
        q = Vector((0, .82, gz)) + Vector((math.sin(th), math.cos(th), 0)) * .47
        p, n = _project(body_shapes, q)
        girth.append(tuple(p + n * .019))
    s.tube('Team girth strap', girth, [(.0055, .032)] * len(girth), 'chest', 'FFFFFF', 'team', n=6)
    bp, bn = _project(body_shapes, Vector((0, .82, gz)) + Vector((math.sin(math.radians(112)), math.cos(math.radians(112)), 0)) * .47)
    s.box('Girth buckle', tuple(bp + bn * .026), (.014, .06, .078), 'chest', BRASS, 'brass', .006)
    s.box('Detail buckle tongue', tuple(bp + bn * .034), (.006, .048, .012), 'chest', IRON, 'metal', .002)

    # ---- the lamp's battery pack on the hump, and its cable --------------------------------------------
    dome = Vector((0, .82, .45))
    up = Vector((0, math.cos(math.radians(40)), math.sin(math.radians(40))))
    back = Vector((0, up.z, -up.y))
    bsurf = dome + up * .38
    bc = bsurf + up * .03
    pack = s.box('Lamp battery pack', tuple(bc), (.15, .044, .11), 'chest', IRON, 'metal', .012)
    _xform(pack, _rot_x(bc, math.radians(40)))
    for k, dx in enumerate((-.055, .055)):
        cap = s.box('Battery corner cap %d' % k, tuple(bc + Vector((dx, 0, 0))), (.03, .05, .116), 'chest', BRASS, 'brass', .008)
        _xform(cap, _rot_x(bc, math.radians(40)))
    for side in (-1, 1):
        # the pack's straps run down the hump's front to the collar
        strap, snrm = [], []
        for k in range(8):
            t = k / 7
            q = Vector((side * (.07 + .2 * t), 1.16 - .3 * t, .72 + .05 * t)) + Vector((side * .1, .08, .05))
            p, n = _project(_shapes(s, 'chest', 'neck'), q)
            strap.append(tuple(p + n * .018))
            snrm.append(tuple(n))
        _ribbon(s, 'Pack strap %d' % side, strap, snrm, 'chest', LEATHER)
    gauge = s.box('Detail battery gauge', tuple(bc + up * .022 + back * .012), (.07, .006, .03), 'chest', 'FFC94A', 'lamp', .0025)
    _xform(gauge, _rot_x(bc + up * .022 + back * .012, math.radians(40)))
    for c0 in gauge.data.color_attributes['Color'].data:
        c0.color[3] = .85
    cable = s.tube('Lamp cable', [tuple(bc - back * .05 + up * .005), (0, 1.075, .745), (0, 1.035, .79), (0, 1.008, .835), (0, .998, .87), (0, .992, .896)],
                   .009, 'chest', DARK, 'skin', n=8)
    _weights(cable, lambda p: {'chest': _smooth(.81, .77, p.z), 'neck': max(0.0, 1 - _smooth(.81, .77, p.z) - _smooth(.84, .88, p.z)),
                               'head': _smooth(.84, .88, p.z)})

    # ---- collar with the swinging brass tool tag --------------------------------------------------------
    neck_shapes = _shapes(s, 'neck', 'chest')
    collar = []
    nrm = Vector((0, .22, .975)).normalized()
    upv = Vector((0, 1, 0)) - nrm * nrm.y
    upv.normalize()
    cc = Vector((0, .785, .762))
    for i in range(30):
        a = math.tau * i / 30
        q = cc + (Vector((1, 0, 0)) * math.cos(a) + upv * math.sin(a)) * .3
        p, n = _project(neck_shapes, q)
        collar.append(tuple(p + n * .016))
    s.tube('Collar strap', collar, [(.006, .024)] * len(collar), 'neck', LEATHER, 'cloth', n=6, closed=True)
    low = min(collar, key=lambda p: p[1])
    tag_bone = s.view_bone('fx_spring_tag_0', 'neck', (0, low[1] - .006, low[2]))
    ring_pts = [(0, low[1] - .006 + .013 * math.sin(a), low[2] + .013 * math.cos(a)) for a in [math.tau * i / 12 for i in range(12)]]
    s.tube('Detail tag ring', ring_pts, .0035, tag_bone, BRASS, 'brass', n=6, closed=True)
    tag = s.box('Tool tag', (0, low[1] - .047, low[2] + .004), (.046, .052, .007), tag_bone, BRASS, 'brass', .003)

    def tag_paint(p, n, c):
        e = max(abs(p.x) / .023, abs(p.y - (low[1] - .047)) / .026)
        col = mix(lin(BRASS), lin('7C5E1A'), _smooth(.72, .86, e) * (1 - _smooth(.9, 1.0, e)))
        if abs(p.x) < .011 and abs(p.y - (low[1] - .047)) < .013:
            col = mix(lin(BRASS), lin('7C5E1A'), .7)     # the stamped pick mark
        return _c(col)
    s.paint(tag, tag_paint)

    # ---- head ----------------------------------------------------------------------------------------
    def head_paint(p, n, c):
        col = hide(p, n, c, seed=12, belly=False)
        col = mix(col, lin('8A7F7A'), _smooth(1.04, 1.13, p.z) * _smooth(.92, .80, p.y) * .45)   # paler muzzle
        col = mix(col, lin('9A807A'), _smooth(.07, 0.0, abs(abs(p.x) - .14) + abs(p.y - .80) * .8) * .35)  # cheeks
        return _c(col, c[3])
    head = s.ellipsoid('Head', tuple(HEAD_C), tuple(HEAD_R), 'head', HIDE, n=30, m=15, soft=True)
    s.paint(head, head_paint)
    jowls = s.ellipsoid('Jowls', (0, .712, 1.0), (.188, .098, .135), 'head', HIDE, n=24, m=10)
    s.paint(jowls, head_paint)
    # the snout disc above the shovel
    nose = s.tube('Snout disc', [(0, .776, 1.095), (0, .776, 1.148), (0, .777, 1.177), (0, .778, 1.19), (0, .779, 1.196), (0, .779, 1.198)],
                  [(.07, .052), (.088, .064), (.09, .066), (.084, .061), (.06, .044), (.002, .002)], 'head', SNOUT, n=28)
    s.paint(nose, lambda p, n, c: _c(mix(lin(SNOUT), lin('B5A39C'), _smooth(.3, .9, n.z) * .5), c[3]))
    for side, sfx in [(1, 'l'), (-1, 'r')]:
        s.ellipsoid('Nostril ' + sfx, (side * .032, .779, 1.193), (.016, .023, .008), 'head', DARK, n=12, m=6)
    # eyes, lids, brows
    for side, sfx in [(1, 'l'), (-1, 'r')]:
        ex, ey, ew, eh, ed = side * .1, .868, .05, .056, .022
        ez = _head_z(ex, ey, -.016)
        s.rig_eye('Eye ' + sfx, (ex, ey, ez), (ew, eh, ed), 'head', sfx, iris='7A4E2A', lid_color=LID)
        # the upper-lid fold: a ridge of hide over the top of the eye. rig_eye's lid, squashed open to a
        # band at the top of the eye, keeps its full closed depth; on this round head that band would
        # jut out like a visor. It tucks in behind the fold instead, and a blink still sweeps down past it.
        fold, frad, top = [], [], []
        for k in range(9):
            u = -1 + 2 * k / 8
            dx = u * 1.16 * ew
            t = max(0.0, 1 - u * u)
            lid_front = ez + .55 * ed + 1.5 * ed * math.sqrt(max(0.0, 1 - (dx / (1.1 * ew)) ** 2))
            rz, ry = .012 + .04 * t, .006 + .011 * t
            cy, cz = ey + 1.02 * eh + .004 * t, lid_front + .003 - rz
            fold.append((ex + dx, cy, cz))
            frad.append((rz, ry))
            top.append((ex + dx, cy + ry * .9 + .013 + .005 * t + .005 * max(0.0, -u * side), cz + rz * .42 + .004))
        lf = s.tube('Lid fold ' + sfx, fold, frad, 'head', HIDE, n=12)
        s.paint(lf, lambda p, n, c: _c(mix(lin(LID), lin(MOTTLE), max(0.0, -n.y) * .7), c[3]))
        brow = s.view_bone('fx_brow_' + sfx, 'head', top[4])
        s.tube('Detail brow ' + sfx, top[1:8], [.007, .011, .014, .015, .014, .011, .007], brow, '26211F', n=10)
        # friendly smile creases at the mouth corners, either side of the shovel mount
        sm = [(side * .062, .712), (side * .105, .7), (side * .146, .716), (side * .168, .742)]
        s.tube('Detail smile ' + sfx, [(px, py, _head_z(px, py, .006) if abs(px) < .15 else _head_z(px, py, .004)) for px, py in sm],
               [.006, .007, .006, .004], 'head', '3A2E2B', n=8)

    # ---- the horn-base plate, the horn and the headlamp (on the crown, just behind the plate, so the
    #      whole lens shows) --------------------------------------------------------------------------
    head_shapes = [s.segments['head']['shapes'][0]]
    prof = lambda w, c: (0.0, .011 + .004 * (1 - abs(c)) - .004 * w)
    obj, grid, top_at = _patch(s, 'Forehead plate', head_shapes, 'head', 16, 8,
                               _cap_geo(HEAD_C, math.radians(7), math.radians(41), math.radians(30), math.radians(11)), prof,
                               _plate_col(51, [[(.45, .1), (.52, .4)]]), pad=.008)
    _rim(s, 'Forehead plate rim', grid, prof, 'head', pad=.008, radius=.0085)
    _rivets(s, 'forehead', top_at, [.12, .88], .2, 'head', r=.0075)
    horn = s.tube('Horn', [(0, .895, 1.015), (0, .95, 1.075), (0, 1.005, 1.13), (0, 1.045, 1.17), (0, 1.07, 1.197), (0, 1.081, 1.211)],
                  [.05, .047, .039, .028, .015, .003], 'head', IVORY, 'shell', n=22)

    def horn_paint(p, n, c):
        t = (p - Vector((0, .895, 1.015))).dot(Vector((0, .684, .73)))
        col = mix(lin('A89E8A'), lin(IVORY), _smooth(.02, .1, t))
        if math.sin(t * 160) > .55 and t < .2:
            col = mix(col, lin('9C907C'), .45)      # growth rings
        col = mix(col, lin('F4EFE4'), _smooth(.2, .26, t) * .6)
        return _c(col)
    s.paint(horn, horn_paint)
    s.tube('Headlamp housing', [(0, .992, .858), (0, .992, .864), (0, .992, .925), (0, .992, .931)], [.026, .038, .04, .04], 'head', '3F3D3A', 'metal', n=22)
    s.box('Headlamp bracket', (0, .96, .895), (.055, .03, .05), 'head', '3F3D3A', 'metal', .008)
    ring_xy(s, 'Detail lamp bezel', (0, .992, .933), .041, .041, 'head', BRASS, .008, 'brass', n=26)
    s.ellipsoid('Detail lamp lens', (0, .992, .934), (.036, .036, .017), 'head', LAMP, 'lamp', glow=1.0, n=18, m=7)
    s.ellipsoid('Detail lamp bulb', (0, .992, .946), (.011, .011, .007), 'head', 'FFF6D8', 'lamp', glow=1.0, n=10, m=5)

    # ---- the shovel snout: a dished steel blade on a riveted mount ---------------------------------------
    nu, nv = 25, 12

    def blade_pt(u, v, top):
        sa, ta = 2 * u - 1, 2 * v - 1
        s2 = sa * math.sqrt(1 - .35 * max(0.0, ta) ** 2 / 2)
        w = (ta + 1) / 2 * math.sqrt(1 - .45 * max(0.0, abs(sa) - .4) ** 2)
        x = s2 * (.192 + .024 * w)
        z = 1.03 + .236 * w - .012 * s2 * s2 * w
        y = .604 + .052 * abs(s2) ** 2.6 + .088 * (1 - w) ** 2.2
        th = .017 - .008 * _smooth(.8, 1.0, w)
        return Vector((x, y + (0 if top else -th), z)), w, s2
    bverts, bcols = [], []
    for top in (0, 1):
        for j in range(nv):
            for i in range(nu):
                p, w, c = blade_pt(i / (nu - 1), j / (nv - 1), top)
                bverts.append(tuple(p))
                if not top:
                    col = mix(lin(STEEL_DARK), lin(STEEL), _smooth(.85, 1.0, w) * .6)
                else:
                    col = mix(lin('8C939A'), lin('6F767D'), _smooth(.45, .75, _fbm(p, .05, 61)) * .6)
                    col = mix(col, lin('5E5249'), _smooth(.32, 0.0, w) * .6)               # grime at the mount
                    col = mix(col, lin('B9C0C6'), _smooth(.6, .82, w) * .35)               # polished by digging
                    col = mix(col, lin(STEEL_BRIGHT), _smooth(.86, .98, w) * .95)          # the worn bright edge
                    col = mix(col, lin(STEEL_BRIGHT), _smooth(.84, .98, abs(c)) * .55)
                bcols.append(_c(col))

    def bix(top, i, j):
        return top * nu * nv + j * nu + i
    bfaces = []
    for j in range(nv - 1):
        for i in range(nu - 1):
            bfaces.append((bix(1, i, j), bix(1, i + 1, j), bix(1, i + 1, j + 1), bix(1, i, j + 1)))
            bfaces.append((bix(0, i, j), bix(0, i, j + 1), bix(0, i + 1, j + 1), bix(0, i + 1, j)))
    for i in range(nu - 1):
        bfaces.append((bix(0, i, 0), bix(0, i + 1, 0), bix(1, i + 1, 0), bix(1, i, 0)))
        bfaces.append((bix(0, i, nv - 1), bix(1, i, nv - 1), bix(1, i + 1, nv - 1), bix(0, i + 1, nv - 1)))
    for j in range(nv - 1):
        bfaces.append((bix(0, 0, j), bix(1, 0, j), bix(1, 0, j + 1), bix(0, 0, j + 1)))
        bfaces.append((bix(0, nu - 1, j), bix(0, nu - 1, j + 1), bix(1, nu - 1, j + 1), bix(1, nu - 1, j)))
    blade = s.mesh('Shovel snout blade', bverts, bfaces, 'head', STEEL, 'metal')
    _set_cols(blade, bcols)

    def blade_y(x, z):
        w = max(0.0, min(1.0, (z - 1.03) / .236))
        s2 = max(-1.0, min(1.0, x / (.192 + .024 * w)))
        return .604 + .052 * abs(s2) ** 2.6 + .088 * (1 - w) ** 2.2
    # scratches scraped into the blade by digging: thin bright scars, mostly along the scoop direction
    for k in range(13):
        x0 = (_hash(70, k, 1) * 2 - 1) * .15
        z0 = 1.085 + _hash(70, k, 2) * .12
        ln = .03 + .06 * _hash(70, k, 3)
        ang = (_hash(70, k, 4) - .5) * .55
        wob = (_hash(70, k, 5) - .5) * .012
        sp = []
        for t in (0.0, .5, 1.0):
            x = x0 + math.sin(ang) * ln * t + wob * math.sin(t * math.pi)
            z = min(1.245, z0 + math.cos(ang) * ln * t)
            sp.append((x, blade_y(x, z) + .0016, z))
        s.tube('Detail scratch %d' % k, sp, [(.0022, .0007)] * 3, 'head', STEEL_BRIGHT, 'metal', n=4)
    # the mount: a steel band round the lower face, bolted to the blade's heel
    mount = []
    for i in range(15):
        a = math.radians(-62 + 124 * i / 14)
        r = .176
        mount.append((r * math.sin(a), .695 - .01 * math.cos(a), .958 + r * math.cos(a) + .012))
    s.tube('Shovel mount band', mount, [(.007, .021)] * len(mount), 'head', '7A8188', 'metal', n=6)
    for k, a in enumerate([-48, -24, 0, 24, 48]):
        ar = math.radians(a)
        p = Vector((.19 * math.sin(ar), .695 - .01 * math.cos(ar), .958 + .19 * math.cos(ar) + .008))
        _blob(s, 'Detail rivet mount %d' % k, tuple(p), (.0085, .0085, .0085), 'head', BRASS, 'brass', n=6, m=4)
    for side in (-1, 1):
        s.box('Shovel heel bracket %d' % side, (side * .158, .688, 1.07), (.03, .04, .06), 'head', STEEL_DARK, 'metal', .008)
        _blob(s, 'Detail rivet heel %d' % side, (side * .158, .712, 1.078), (.009, .007, .009), 'head', BRASS, 'brass', n=6, m=4)

    # ---- the lower jaw tucked under the shovel (opens on effort, pain, taunts) --------------------------
    s.ellipsoid('Mouth interior', (0, .612, 1.07), (.112, .018, .07), 'head', MOUTH, n=14, m=6)   # stays under the blade's top
    jaw = s.view_bone('fx_jaw', 'head', (0, .635, .985))
    chin = s.ellipsoid('Lower jaw', (0, .592, 1.068), (.13, .031, .09), jaw, HIDE, n=18, m=8)
    s.paint(chin, lambda p, n, c: _c(mix(lin(HIDE_BELLY), lin(DUST), max(0.0, -n.y) * .35), c[3]))
    s.ellipsoid('Detail tongue', (0, .614, 1.075), (.072, .01, .058), jaw, TONGUE, n=12, m=5)
    for k, x in enumerate((-.078, .078)):
        # two small blunt lower tusks, seen when the jaw drops (friendly, not fangs)
        zt = 1.068 + .085 * math.sqrt(max(0.0, 1 - (x / .13) ** 2)) - .012
        s.tube('Detail jaw tusk %d' % k, [(x, .606, zt), (x * 1.04, .622, zt + .003), (x * 1.06, .631, zt + .002)], [.009, .007, .003], jaw, 'E6DDCB', 'shell', n=8)

    # ---- ears on springs ---------------------------------------------------------------------------------
    for side, sfx in [(1, 'l'), (-1, 'r')]:
        # pig ears: broad flaps standing out and up from the crown, cupped forward (pink side to the
        # front, hide to the back and top), the tips flopping forward
        base = Vector((side * .112, .928, .866))
        tip = Vector((side * .168, .998, .942))
        inner = Vector((side * .3, .05, .95)).normalized()
        ax = (tip - base).normalized()
        bone = s.view_bone('fx_spring_ear_' + sfx, 'head', tuple(base))
        _leaf(s, 'Ear ' + sfx, base, tip, ax.cross(inner), bone, HIDE, INNER_EAR, out_dir=-inner,
              width=.125, thick=.015, cup=.02, droop=.028)

    # ---- legs: stout hide limbs, muddy below the knees, cloven hooves ----------------------------------
    def leg_paint(knee_y, seed):
        def f(p, n, c):
            col = hide(p, n, c, seed=seed)
            # the upper legs live in the body's shadow: a shade lighter so they don't go black
            col = mix(col, lin(LEG_LIGHT), _smooth(knee_y + .02, knee_y + .2, p.y) * .6)
            for ky in (knee_y, knee_y + .045, knee_y - .04):          # wrinkles round the knee
                col = mix(col, lin(MOTTLE), _smooth(.008, 0.0, abs(p.y - ky + .01 * math.sin(p.x * 60 + p.z * 40))) * .75)
            for k in range(3):                                         # faint hide stripes above it
                col = mix(col, lin(HIDE_TOP), _smooth(.012, 0.0, abs(p.y - (knee_y + .1 + .05 * k))) * .4)
            # mud caked on the lower legs with a ragged edge, dried splashes above it
            line = .21 + .05 * _fbm(p, .035, seed + 1)
            mud = _smooth(line + .01, line - .01, p.y)
            col = mix(col, mix(lin(MUD), lin(MUD_DRY), _smooth(.35, .65, _fbm(p, .02, seed + 2)) * .6), mud * .92)
            sp = cell_spots(p, .028, .55, .5, seed + 3) * _smooth(.4, .22, p.y)
            if sp > .2:
                col = mix(col, lin(MUD_DRY), .75)
            return _c(col, c[3])
        return f
    for fb in ('f', 'b'):
        for side, sfx in [(1, 'l'), (-1, 'r')]:
            tb, sb = 'thigh_' + fb + sfx, 'shin_' + fb + sfx
            tsh = s.segments[tb]['shapes'][0]
            ssh, foot = s.segments[sb]['shapes']
            a, b = Vector(tsh['a']), Vector(tsh['b'])
            top = a + Vector((0, .1, 0))
            tp, tr = densify([tuple(top), tuple(a), tuple(a.lerp(b, .55)), tuple(b)], [.098, .1, .094, .085], 2)
            th = s.tube('Leg ' + tb, tp + [tuple(b + (b - a).normalized() * .05)], tr + [.03], tb, HIDE, n=18, soft=True)
            s.paint(th, leg_paint(b.y - .005, 70 + len(fb) + side))
            if fb == 'f':
                # team tape above the front knees: the team colour from the front and back as well
                s.tube('Team leg tape ' + sfx, [tuple(a.lerp(b, .66)), tuple(a.lerp(b, .82))], [.0965, .0955], tb, 'FFFFFF', 'team', n=18)
            sa_, sb_ = Vector(ssh['a']), Vector(ssh['b'])
            fc = Vector(foot['center'])
            past = Vector((fc.x, .1, fc.z - .01))
            sp_, sr_ = densify([tuple(sa_ + (sa_ - sb_).normalized() * .03), tuple(sa_), tuple(sb_), tuple(past)], [.05, .07, .06, .052], 3)
            sh_ = s.tube('Leg ' + sb, sp_ + [tuple(past + Vector((0, -.025, .004)))], sr_ + [.02], sb, HIDE, n=18, soft=True)
            s.paint(sh_, leg_paint(sa_.y + .01, 80 + side + len(fb)))
            # two hoof toes with a cleft, glossy keratin with growth lines and a highlight
            for k, dx in enumerate((-.026, .026)):
                tc = Vector((fc.x + dx, .043, fc.z + .022))

                def toe_xf(q, dx=dx):
                    q = Vector((q.x * (1 - .25 * max(0.0, q.z) / .062), q.y, q.z))
                    q.y -= .3 * max(0.0, q.z)          # the toe slopes down to its tip
                    q.y = max(q.y, -.043)              # flat sole on the ground
                    q.x += dx * .25 * max(0.0, q.z) / .062
                    return q
                toe = _blob(s, 'Hoof toe %s %d' % (sb, k), tuple(tc), (.031, .046, .062), sb, HOOF, 'shell', n=12, m=7, xf=toe_xf)

                def hoof_paint(p, n, c, tc=tc):
                    col = lin(HOOF)
                    if math.sin((p.y - tc.y) * 230) > .6:
                        col = mix(col, lin('4A433E'), .6)
                    col = mix(col, lin('77706A'), _smooth(.55, .95, n.z * .7 + n.y * .5) * .7)   # highlight
                    col = mix(col, lin(MUD), _smooth(.012, .0, p.y) * .6)
                    return _c(col)
                s.paint(toe, hoof_paint)
                s.tube('Dewclaw %s %d' % (sb, k), [(fc.x + dx * 1.2, .11, fc.z - .05), (fc.x + dx * 1.35, .085, fc.z - .07), (fc.x + dx * 1.4, .072, fc.z - .074)],
                       [.013, .009, .002], sb, HOOF, 'shell', n=8)

    # ---- the curly tail: a corkscrew off the rump (a ring from behind, a spring from the side) on a
    #      three-link spring chain -------------------------------------------------------------------
    A = Vector((0, .3, -1)).normalized()
    e1 = Vector((1, 0, 0))
    e2 = A.cross(e1)
    S = Vector((0, .705, -.915))
    path = [Vector((0, .735, -.85)), Vector((0, .719, -.885)), S]
    ts = [0.0, 0.0, 0.0]
    for k in range(1, 21):
        t = k / 20
        r = .03 * _smooth(0.0, .22, t) * (1 - .25 * t)
        ph = math.tau * 1.35 * t
        path.append(S + A * (.075 * t) + (e1 * math.cos(ph) + e2 * math.sin(ph)) * r)
        ts.append(t)
    t0 = s.view_bone('fx_spring_tail_0', 'tail', tuple(S))
    t1 = s.view_bone('fx_spring_tail_1', t0, tuple(path[3 + 8]))
    t2 = s.view_bone('fx_spring_tail_2', t1, tuple(path[3 + 15]))
    radii = [.024, .021, .019] + [.018 - .007 * k / 20 for k in range(1, 21)]
    tail = s.tube('Curly tail', [tuple(p) for p in path], radii, 'tail', HIDE, n=10)

    def tail_w(p):
        best = min(range(len(path)), key=lambda k: (path[k] - p).length)
        if best <= 2:
            return {'tail': 1.0}
        t = ts[best]
        if t < .45:
            return {t0: 1 - _smooth(.33, .45, t), t1: _smooth(.33, .45, t)}
        if t < .8:
            return {t1: 1 - _smooth(.68, .8, t), t2: _smooth(.68, .8, t)}
        return {t2: 1.0}
    _weights(tail, tail_w)
    s.paint(tail, lambda p, n, c: _c(mix(lin('5A5552'), lin(HIDE), max(0.0, n.y) * .4), c[3]))
    tip = path[-1]
    for k in range(3):
        d = (A + Vector((.5 * (k - 1), -.4, 0))).normalized()
        s.tube('Tail tuft %d' % k, [tuple(tip), tuple(tip + d * .028)], [.006, .001], t2, '3A3533', 'skin', n=6)

    # ---- the detachable gore piece: the horn tip -----------------------------------------------------------
    s.tube('Gore horn tip', [(0, -.03, 0), (0, .015, .015), (0, .06, .04)], [.023, .017, .001], None, IVORY, 'shell', n=16, role='gore')
    s.set_look({'glow_mode': 'lamp', 'fx': {'pupil_reach': .012, 'jaw_deg': 18, 'brow_drop': .01, 'lid_rest': .14,
                                            'spring_gain': 1.35, 'spring_stiffness': .85}})
    s.bake_ao(rays=14, distance=.085, strength=.36)
