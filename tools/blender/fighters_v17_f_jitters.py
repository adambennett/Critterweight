"""Jitters, the Battery Jelly (v0.9.17 roster art, docs/ART_REVAMP.md "v0.9.17").

A small, nervous jellyfish wired like a battery. The locked body is one 0.36 m sphere (plus the
non-colliding inner coil, two stubby arms and two antenna segments), so the jelly BELL is that sphere:
a pale cyan dome carrying the face, lightning-bolt markings that radiate from the battery cap and a
battery charge badge on the back (the fight camera's view), a frilled, scalloped rim below the equator
and, under the rim, the glowing conical coil spring (the battery's negative contact: his Hype feature,
glow mode 'pulse') whose upper windings show through the jelly above the rim. Signature: eight short
trailing tentacles hanging from under the rim, each a three-link spring chain
(fx_spring_tentacle_<k>_0..2) the game swings as he hops. The antennae are light-bulb electrodes on
springy stalks, the arms soft rubber mittens with team-tint cuffs, the cap carries the brass terminal,
+ and - marks and a hazard stripe (and pops off as the gore piece). Rigged face: rig eyes turned to sit
on the ball, with lids and lash lines, worried brows on fx_brow_l/r, a wobbly mouth whose lower lip
rides fx_jaw, blush and a bead of nervous sweat.

Fighter rest space throughout (+Z forward, +Y up, +X = the creature's LEFT), metres. Segment bones and
pivots are untouched; hard parts stay within 5 cm of the collision sphere they belong to, the soft
tentacle fringe within ~8 cm, and the cap and bulbs inside their weapon hit volumes.
"""
import math
import bmesh
from mathutils import Vector, Matrix
from mathutils.geometry import tessellate_polygon
from fighters_v17 import mix, lin, densify, _hash

C = Vector((0.0, .42, 0.0))   # bell centre = the body pivot / collision sphere centre
RB = .358                     # outer bell (the collision sphere is 0.36)
RS = .338                     # the subumbrella: a concentric shell under the rim
RIM_EL = -24.0                # elevation (deg) where the frilled rim meets the bell
SPRING_D = .346               # distance of the coil spring's wire centre from C
EL_BOT, EL_PITCH = -63.0, 14.4    # the conical spring: bottom winding elevation, degrees per turn
SPRING_AZ0 = 160.0            # azimuth where the spring's bottom winding starts
TURNS = 2.5                   # turns below the rim (more continue, painted, inside the bell)


def smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def sph(az, el, r=RB):
    """A point at azimuth `az` (deg, from +Z toward +X) and elevation `el` (deg) around the bell centre."""
    a, e = math.radians(az), math.radians(el)
    return Vector((r * math.cos(e) * math.sin(a), C.y + r * math.sin(e), r * math.cos(e) * math.cos(a)))


def az_el(p):
    d = Vector(p) - C
    L = max(d.length, 1e-9)
    return math.degrees(math.atan2(d.x, d.z)), math.degrees(math.asin(max(-1.0, min(1.0, d.y / L))))


def on_bell(x, y, off=0.0, r=RB):
    """The front of the bell above (x, y), pushed `off` out along its normal."""
    z = math.sqrt(max(0.0, r * r - x * x - (y - C.y) ** 2))
    p = Vector((x, y, z))
    return p + (p - C).normalized() * off


def xform(obj, fn):
    """Move an object's vertices through fn(fighter point) -> fighter point."""
    for v in obj.data.vertices:
        q = fn(Vector((v.co.x, v.co.z, -v.co.y)))
        v.co = Vector((q.x, -q.z, q.y))
    obj.data.update()


def face_out(obj, centre):
    """Open surfaces (decals): every face looks away from `centre` (fighter space)."""
    me = obj.data
    cb = Vector((centre[0], -centre[2], centre[1]))
    bad = sum(1 for poly in me.polygons if poly.normal.dot(poly.center - cb) < 0)
    if bad * 2 > len(me.polygons):
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        me.update()


def recolor(obj, fn):
    """fn(vertex index, fighter point) -> (r, g, b, a) linear."""
    attr = obj.data.color_attributes['Color']
    for v in obj.data.vertices:
        attr.data[v.index].color = fn(v.index, Vector((v.co.x, v.co.z, -v.co.y)))


def frame_at(d):
    """Tangent frame on the bell at unit direction d: (east = increasing azimuth, down the meridian)."""
    east = Vector((0, 1, 0)).cross(d)
    if east.length < 1e-6:
        east = Vector((1, 0, 0))
    east.normalize()
    down = east.cross(d).normalized()
    return east, down


def revolve(s, name, profile, n, bone, color, mat='skin', glow=0.0):
    """A closed surface of revolution about the bell axis: profile = [(y, r)] bottom -> top, the first
    and last entries are the poles (their r is ignored)."""
    rings = profile[1:-1]
    verts = [(0.0, profile[0][0], 0.0)]
    for y, r in rings:
        for i in range(n):
            a = math.tau * i / n
            verts.append((r * math.sin(a), y, r * math.cos(a)))
    verts.append((0.0, profile[-1][0], 0.0))
    top = len(verts) - 1
    faces = [(0, 1 + (i + 1) % n, 1 + i) for i in range(n)]
    for j in range(len(rings) - 1):
        for i in range(n):
            a = 1 + j * n + i
            b = 1 + j * n + (i + 1) % n
            faces.append((a, b, b + n, a + n))
    last = 1 + (len(rings) - 1) * n
    faces += [(top, last + i, last + (i + 1) % n) for i in range(n)]
    return s.mesh(name, verts, faces, bone, color, mat, glow)


def _subdivide(pts, tris, levels):
    for _ in range(levels):
        mid = {}

        def m(a, b):
            key = (min(a, b), max(a, b))
            if key not in mid:
                pts.append(((pts[a][0] + pts[b][0]) / 2, (pts[a][1] + pts[b][1]) / 2))
                mid[key] = len(pts) - 1
            return mid[key]
        out = []
        for a, b, c in tris:
            ab, bc, ca = m(a, b), m(b, c), m(c, a)
            out += [(a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)]
        tris = out
    return pts, tris


def offset_poly(poly, d):
    """Mitred outward offset of a simple 2D polygon (clamped at sharp tips)."""
    area = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))
    sgn = 1.0 if area > 0 else -1.0
    out = []
    for i in range(len(poly)):
        p0, p1, p2 = Vector(poly[i - 1]), Vector(poly[i]), Vector(poly[(i + 1) % len(poly)])
        e1, e2 = (p1 - p0).normalized(), (p2 - p1).normalized()
        n1 = Vector((e1.y, -e1.x)) * sgn
        n2 = Vector((e2.y, -e2.x)) * sgn
        mdir = (n1 + n2)
        mdir = mdir.normalized() if mdir.length > 1e-6 else n1
        k = d / max(.3, mdir.dot(n1))
        out.append(tuple(p1 + mdir * k))
    return out


def bell_decal(s, name, poly, az, el, color, glow=0.0, mat='jelly', off=.0018, levels=2, mirror=False, r=RB, bone='body'):
    """A flat 2D polygon (u along increasing azimuth, v down the meridian, metres; (0, 0) at the anchor)
    wrapped onto the bell: crisp painted markings without dense bell topology. Names start 'Detail '."""
    pts = [((-u if mirror else u), v) for u, v in poly]
    tris = tessellate_polygon([[Vector((u, v, 0.0)) for u, v in pts]])
    pts, tris = _subdivide(list(pts), [tuple(t) for t in tris], levels)
    d0 = (sph(az, el, 1.0) - C).normalized()
    east, down = frame_at(d0)
    verts = []
    for u, v in pts:
        d = (d0 + east * (u / r) + down * (v / r)).normalized()
        verts.append(tuple(C + d * (r + off)))
    obj = s.mesh(name, verts, [tuple(t) for t in tris], bone, color, mat, glow)
    face_out(obj, C)
    return obj


def oriented_eye(s, side, c, facing, scale, iris, lid_color, pupil='1F2A33'):
    """rig_eye (mesh_tools.Studio.rig_eye) turned to sit on the ball: built facing +Z around c, then
    rotated so it looks along `facing`, sunk into the bell with a dark rim instead of a socket.
    Iris/pupil/glints ride fx_eye_<side>; the upper lid (modelled closed, squashed open by the game)
    rides fx_lid_<side>, whose head is the top of the turned eye."""
    c = Vector(c)
    w, h, d = scale
    zA = Vector(facing).normalized()
    xA = Vector((0, 1, 0)).cross(zA).normalized()
    yA = zA.cross(xA).normalized()
    R = Matrix((xA, yA, zA)).transposed()
    eye_bone = s.view_bone('fx_eye_' + side, 'body', tuple(c))
    # the lid's bone sits on the top of the white: squashed open (lid_rest) it covers the top of the
    # white like an upper lid instead of floating above the socket
    lid_bone = s.view_bone('fx_lid_' + side, 'body', tuple(c + R @ Vector((0, h * 1.05, 0))))
    name = 'Eye ' + side
    # the eye is sunk into the ball: a dark rim traces the line where the white meets the jelly
    f = zA
    rim = []
    for i in range(30):
        t = math.tau * i / 30
        q = c + R @ Vector((w * .955 * math.cos(t), h * .955 * math.sin(t), 0))
        b = (q - C).dot(f)
        z = -b + math.sqrt(max(0.0, b * b - ((q - C).length_squared - (RB + .0012) ** 2)))
        rim.append(q + f * z)
    s.tube(name + ' rim', rim, .0042, 'body', '2C2436', 'skin', n=6, closed=True)
    # a shallow iris/pupil stack keeps the squashed lid (a thin shelf of the closed lid) close to the eye
    parts = [
        s.ellipsoid(name + ' sclera', tuple(c + Vector((0, 0, d * .35))), (w, h, d), 'body', 'FFF8E6', 'eye', n=24, m=12),
        s.ellipsoid(name + ' iris', tuple(c + Vector((0, h * .02, d * 1.18))), (w * .52, h * .57, d * .34), eye_bone, iris, 'eye', n=20, m=8),
        s.ellipsoid(name + ' pupil', tuple(c + Vector((0, h * .03, d * 1.42))), (w * .29, h * .34, d * .14), eye_bone, pupil, 'eye', n=16, m=8),
        s.ellipsoid(name + ' glint', tuple(c + Vector((-w * .17, h * .22, d * 1.52))), (w * .13, h * .12, d * .09), eye_bone, 'FFFFFF', 'eye', n=10, m=5),
        s.ellipsoid(name + ' glint small', tuple(c + Vector((w * .14, -h * .16, d * 1.49))), (w * .06, h * .055, d * .07), eye_bone, 'FFFFFF', 'eye', n=8, m=4),
        s.ellipsoid('Detail lid ' + name, tuple(c + Vector((0, -h * .02, d * .45))), (w * 1.1, h * 1.05, d * 1.24), lid_bone, lid_color, 'skin', n=22, m=30),
    ]
    # lash line on the lid's equator (its front-most rows): shut, it is the closed-eye line across the
    # middle; squashed open, those rows form the lid's protruding front edge, so the upper lid shows a
    # dark lash edge from the front and from the high fight camera alike
    lc, dark = lin(lid_color), lin('2C2436')

    def lid_col(p, n, col):
        y = p.y - (c.y - h * .02)
        t = 1 - smooth(.05 * h, .13 * h, abs(y))
        return tuple(list(mix(lc, dark, t * min(1.0, max(0.0, n.z) * 2.5))[:3]) + [0.0])
    s.paint(parts[-1], lid_col)
    for o in parts:
        xform(o, lambda p: c + R @ (p - c))
    return eye_bone, lid_bone


def build(s):
    jelly = 'BDEFFF'; lav = 'B59CE0'; volt = 'FFF27A'; bulb = 'F7E04A'; cap = '3C4650'; ink = '1F2A33'
    # the jelly reads pale cyan once the game's jelly shading lifts it: the albedo sits a step deeper
    J = lin('98E4FA'); J_top = lin('C4F4FF'); J_lo = lin('6CCDEE'); J_back = lin('82D6F2'); J_rim = lin('ABA6EC'); J_face = lin('B2EDFF')
    SUB = lin('4BB0D4'); WARM = lin('E6F79A'); V = lin(volt)

    # ---------------------------------------------------------------------------------------------
    # The bell: one closed surface of revolution. Outer dome (r .358) from the rim up to the cap; under
    # the rim a concentric subumbrella (r .338) the coil spring wraps. Rings are denser where the coil
    # shows through the jelly (painted) and coarser on the plain dome.
    # ---------------------------------------------------------------------------------------------
    els_sub = [-86 + 4 * i for i in range(16)]                      # -86 .. -26 on the inner shell
    els_coil = [RIM_EL + 1.6 * i for i in range(13)]                # -24 .. -4.8 (painted windings)
    els_dome = [-2.0 + 3.0 * i for i in range(26)]                  # -2 .. 73
    prof = [(C.y - RS, 0.0)]
    prof += [(C.y + RS * math.sin(math.radians(e)), RS * math.cos(math.radians(e))) for e in els_sub]
    prof += [(C.y + RB * math.sin(math.radians(e)), RB * math.cos(math.radians(e))) for e in els_coil + els_dome]
    prof += [(C.y + RB, 0.0)]
    bell = revolve(s, 'Jelly bell', prof, 56, 'body', jelly, 'jelly')

    def winding(az, el):
        """How strongly the spring's upper windings show through the jelly at (az, el): (core, halo)."""
        t_cont = (el - EL_BOT) / EL_PITCH
        frac = ((az - SPRING_AZ0) % 360.0) / 360.0
        k = round(t_cont - frac)
        best = (0.0, 0.0)
        for kk in (k - 1, k, k + 1):
            T = frac + kk
            if T < TURNS - .05:
                continue
            d = abs(el - (EL_BOT + EL_PITCH * T)) * math.pi / 180 * RB
            fade = smooth(TURNS - .05, TURNS + .2, T) * (1 - smooth(TURNS + .55, TURNS + 1.25, T))
            core = (1 - smooth(.006, .013, d)) * fade
            halo = math.exp(-(d / .03) ** 2) * fade
            if core + halo > best[0] + best[1]:
                best = (core, halo)
        return best

    def bell_col(p, n, c):
        az, el = az_el(p)
        dist = (p - C).length
        if dist < (RS + RB) / 2 and el < RIM_EL - 1:
            # the subumbrella under the rim, lit warm by the coil
            g = smooth(-80, -30, el)
            col = mix(SUB, WARM, .25 + .3 * g)
            return (col[0], col[1], col[2], .14 + .14 * g)
        col = mix(J_lo, J, smooth(-22, 14, el))
        col = mix(col, J_top, smooth(30, 72, el) * .7)
        col = mix(col, J_back, max(0.0, -n.z) * .45 * smooth(-30, 30, el))
        # the face is a touch lighter so eyes and mouth sit on a clean field
        fa = (1 - smooth(30, 55, abs(az))) * smooth(-14, 4, el) * (1 - smooth(45, 62, el))
        col = mix(col, J_face, fa * .7)
        col = mix(col, J_rim, (1 - smooth(RIM_EL, RIM_EL + 16, el)) * .55)
        a = 0.0
        if el > RIM_EL - .5:
            core, halo = winding(az, el)
            col = mix(col, lin('FFE65A'), min(1.0, .8 * core + .35 * halo))
            a = .55 * core + .14 * halo
        return (col[0], col[1], col[2], a)
    s.paint(bell, bell_col)

    # ---- frilled rim: sixteen scallops, the bell margin, lavender at the edge ----
    N, S = 16, 6
    M = N * S
    y0 = C.y + RB * math.sin(math.radians(RIM_EL))
    r0 = RB * math.cos(math.radians(RIM_EL))
    verts, faces = [], []
    for i in range(M):
        phi = 360.0 * i / M
        lobe = (1 - abs(math.sin(math.radians(phi) * N / 2))) ** .55
        re = .333 + .022 * lobe
        ye = y0 - .013 - .009 * lobe + .003 * math.sin(math.radians(phi) * 3 + 1.0)
        rm, ym = (r0 + re) / 2, (y0 + ye) / 2 - .001
        sec = [(r0 - .004, y0 + .011), (rm, ym + .0075), (re - .002, ye + .0042), (re + .0025, ye - .0005),
               (re - .003, ye - .0052), (rm - .003, ym - .0072), (r0 - .009, y0 - .012)]
        a = math.radians(phi)
        for rr, yy in sec:
            verts.append((rr * math.sin(a), yy, rr * math.cos(a)))
    P = 7
    for i in range(M):
        for j in range(P):
            a = i * P + j
            b = i * P + (j + 1) % P
            c = ((i + 1) % M) * P + (j + 1) % P
            d = ((i + 1) % M) * P + j
            faces.append((a, b, c, d))
    frill = s.mesh('Frill rim', verts, faces, 'body', jelly, 'jelly')

    def frill_col(p, n, c):
        rr = math.hypot(p.x, p.z)
        t = smooth(r0 - .004, r0 + .02, rr)
        col = mix(lin('A9B8F0'), lin('A68AE2'), t)
        col = mix(col, lin('7F63C4'), max(0.0, -n.y) * .45)
        return (col[0], col[1], col[2], 0.0)
    s.paint(frill, frill_col)

    # ---- the coil: a glowing conical spring under the rim (the battery's negative contact) ----
    pts = []
    steps = int(TURNS * 40)
    for i in range(steps + 1):
        T = TURNS * i / steps
        pts.append(sph(SPRING_AZ0 + 360.0 * T, EL_BOT + EL_PITCH * T, SPRING_D))
    pts.reverse()                                   # top winding first, down to the bottom one
    end_az = SPRING_AZ0
    for rr, yy in [(.118, .095), (.07, .087)]:
        a = math.radians(end_az)
        pts.append(Vector((rr * math.sin(a), yy, rr * math.cos(a))))
    spring = s.tube('Coil spring', pts, .0125, 'body', volt, 'metal', glow=.95, n=8)

    def spring_col(i, p):
        # saturated gold: the emission lifts it to yellow without washing out to cream
        az, el = az_el(p)
        t = smooth(EL_BOT, RIM_EL, el)
        col = mix(lin('F0A60C'), lin('FFD52E'), .35 + .65 * t)
        return (col[0], col[1], col[2], .85 + .15 * t)
    recolor(spring, spring_col)
    s.tube('Contact plate', [(0, .073, 0), (0, .081, 0), (0, .086, 0)], [.05, .05, .044], 'body', '8A96A0', 'metal', n=24)
    s.box('Detail contact minus', (0, .0718, 0), (.032, .003, .008), 'body', ink, 'metal', .0012)
    s.ellipsoid('Inner coil core', (0, .42, 0), (.1, .1, .1), 'coil', volt, 'metal', glow=.9, n=12, m=6)

    # ---- eight trailing tentacles from under the rim: three-link spring chains ----
    # A fringe that flares out from under the rim and droops, wavy, with a glowing bead at the tip: they
    # end ABOVE the bell's lowest point (the coil hangs below them), so they read as floating tentacles,
    # not legs, and they stay within ~8 cm of the collision sphere. Long and short ones alternate; the
    # four at the back are all long (the fight camera sees the back).
    for k in range(8):
        az = 22.5 + 45.0 * k
        back = abs(az - 180.0) < 70
        long_one = (k % 2 == 0) or back
        if long_one:
            prof_t = [(.31, .262), (.33, .236), (.343, .207), (.341, .178), (.333, .152), (.317, .132), (.303, .12)]
        else:
            prof_t = [(.31, .262), (.331, .239), (.342, .214), (.343, .19), (.338, .17), (.331, .157), (.327, .149)]
        rads_t = [.0158, .0146, .0128, .0106, .0083, .006, .0041]
        a = math.radians(az)
        out = Vector((math.sin(a), 0, math.cos(a)))
        east = Vector((math.cos(a), 0, -math.sin(a)))
        ph = _hash(k, 3) * math.tau
        tp = []
        for i, (rr, yy) in enumerate(prof_t):
            wave = .019 * math.sin(ph + i * 1.3) * min(1.0, i / 2.0)
            tp.append(out * rr + Vector((0, yy, 0)) + east * wave)
        dp, dr = densify([tuple(q) for q in tp], rads_t, 2)
        acc = [0.0]
        for i in range(1, len(dp)):
            acc.append(acc[-1] + (Vector(dp[i]) - Vector(dp[i - 1])).length)
        L = acc[-1]
        ts = [x / L for x in acc]

        def at(t):
            for i in range(1, len(ts)):
                if ts[i] >= t:
                    f = (t - ts[i - 1]) / max(1e-9, ts[i] - ts[i - 1])
                    return Vector(dp[i - 1]).lerp(Vector(dp[i]), f)
            return Vector(dp[-1])
        names = ['fx_spring_tentacle_%d_%d' % (k, j) for j in range(3)]
        s.view_bone(names[0], 'body', tuple(at(0.0)))
        s.view_bone(names[1], names[0], tuple(at(1 / 3)))
        s.view_bone(names[2], names[1], tuple(at(2 / 3)))
        nn = 9
        obj = s.tube('Tentacle %d' % k, dp, dr, names[0], lav, 'jelly', n=nn)
        g = [obj.vertex_groups[names[0]], obj.vertex_groups.new(name=names[1]), obj.vertex_groups.new(name=names[2])]
        for v in obj.data.vertices:
            t = ts[min(v.index // nn, len(ts) - 1)]
            w1 = smooth(1 / 3 - .07, 1 / 3 + .07, t)
            w2 = smooth(2 / 3 - .07, 2 / 3 + .07, t)
            ws = [1 - w1, w1 - w2, w2]
            for j in range(3):
                if ws[j] > 1e-4:
                    g[j].add([v.index], ws[j], 'REPLACE')
                else:
                    g[j].remove([v.index])

        def tcol(i, p, ts=ts, nn=nn):
            t = ts[min(i // nn, len(ts) - 1)]
            col = mix(lin('9E84D6'), lin('CDB9F2'), smooth(0, .65, t))
            tip = smooth(.78, .97, t)
            col = mix(col, V, tip * .8)
            return (col[0], col[1], col[2], .5 * tip)
        recolor(obj, tcol)
        # a glowing bead on the tip (a live wire end)
        tipd = (Vector(dp[-1]) - Vector(dp[-2])).normalized()
        s.ellipsoid('Detail tentacle bead %d' % k, tuple(Vector(dp[-1]) + tipd * .003), (.0078, .0082, .0078), names[2], volt, 'jelly', glow=.85, n=10, m=6)

    # ---------------------------------------------------------------------------------------------
    # Face: big nervous eyes turned to sit on the ball, worried brows, a wobbly mouth, blush, a bead
    # of sweat.
    # ---------------------------------------------------------------------------------------------
    for side, sx in [('l', 1), ('r', -1)]:
        ex, ey = sx * .118, .549
        surf = on_bell(ex, ey)
        nrm = (surf - C).normalized()
        # (almost) along the ball's normal: the jelly then falls away evenly above and below the eye, so
        # the squashed upper lid sits close to the surface
        facing = (nrm * .9 + Vector((0, 0, 1)) * .1).normalized()
        # shallow (d) and sunk a full d into the bell: the whites bulge ~6 mm and the squashed lid (a plate
        # as deep as the closed lid) stays slim even seen from the high fight camera
        w, h, d = .078, .09, .018
        oriented_eye(s, side, surf - facing * d * 1.0, facing, (w, h, d), '6E6FC4', '8CD3EF')
        bpts = [on_bell(sx * x, y, .0075) for x, y in [(.046, .677), (.084, .682), (.123, .673), (.16, .652), (.184, .63)]]
        brow = s.view_bone('fx_brow_' + side, 'body', tuple(on_bell(sx * .11, .676, .004)))
        s.tube('Detail worried brow ' + side, bpts, [.0095, .012, .012, .0095, .006], brow, '6A5398', n=10)
        bell_decal(s, 'Detail cheek ' + side, [(.032 * math.cos(t * math.tau / 16), .019 * math.sin(t * math.tau / 16)) for t in range(16)],
                   sx * 36.0, 8.0, 'D9A9EC', mat='jelly', levels=1)
    # a bead of nervous sweat on his left temple: a teardrop lying on the bell, point up
    d0 = (sph(51.0, 17.0, 1.0) - C).normalized()
    east, down = frame_at(d0)
    base = C + d0 * RB
    prof = [(0.0, .0025), (.007, .0115), (.017, .0158), (.027, .016), (.037, .013), (.049, .0078), (.061, .0028), (.068, .0007)]
    dpts = [base + d0 * (rr * .55) - down * hh + east * (hh * .12) for hh, rr in prof]
    s.tube('Detail sweat drop', dpts, [rr for hh, rr in prof], 'body', '8FD8FA', 'glass', n=14)
    s.ellipsoid('Detail sweat glint', tuple(base + d0 * .023 - down * .032 + east * .0055), (.0035, .006, .0035), 'body', 'FFFFFF', 'glass', n=8, m=4)

    # mouth: dark interior and a squiggly upper lip on the body, a jelly lower lip on fx_jaw
    s.ellipsoid('Detail mouth interior', (0, .4255, .354), (.045, .0195, .009), 'body', '3C2148', 'skin', n=20, m=8)
    lip = [on_bell(x, .4425 + .0042 * math.sin(x / .0125 * math.pi), .0085) for x in [-.052 + .0104 * i for i in range(11)]]
    s.tube('Detail upper lip', lip, [.0035, .0045, .0048, .0048, .0048, .0048, .0048, .0048, .0048, .0045, .0035], 'body', '2B2F4A', n=8)
    jaw = s.view_bone('fx_jaw', 'body', (0, .428, .12))
    s.ellipsoid('Detail lower lip', (0, .4125, .357), (.05, .0215, .012), jaw, 'A9E4F6', 'jelly', n=22, m=10)
    s.tube('Detail lower lip line', [on_bell(x, .4335 - .0015 * math.cos(x / .05 * math.pi), .0105) for x in [-.04, -.02, 0, .02, .04]],
           [.0022, .003, .003, .003, .0022], jaw, '7C6AB0', n=6)

    # ---------------------------------------------------------------------------------------------
    # Battery cap: steel cap, hazard stripe, brass terminal, + and - on top. (The cap weapon is a 0.1 m
    # sphere at (0, .78, 0): the whole cap stays inside it.)
    # ---------------------------------------------------------------------------------------------
    s.tube('Battery cap', [(0, .742, 0), (0, .792, 0), (0, .801, 0), (0, .806, 0)], [.087, .087, .084, .074], 'body', cap, 'metal', n=40)
    s.tube('Detail warning band', [(0, .770, 0), (0, .789, 0)], [.0885, .0885], 'body', 'F2CC2E', 'metal', n=40)
    verts, faces = [], []
    for k in range(12):
        base = len(verts)
        for j in range(4):
            for yy, sl in ((.7695, 0.0), (.7895, 11.0)):
                a = math.radians(30.0 * k + 13.0 * j / 3 + sl)
                verts.append((.0893 * math.sin(a), yy, .0893 * math.cos(a)))
        for j in range(3):
            q = base + 2 * j
            faces.append((q, q + 2, q + 3, q + 1))
    stripes = s.mesh('Detail hazard stripes', verts, faces, 'body', '1D2127', 'metal')
    face_out(stripes, (0, .78, 0))
    s.tube('Battery terminal', [(0, .803, 0), (0, .819, 0), (0, .827, 0)], [.029, .029, .022], 'body', 'D7B24C', 'brass', n=24)
    ring_pts = [(.033 * math.sin(i * math.tau / 24), .8075, .033 * math.cos(i * math.tau / 24)) for i in range(24)]
    s.tube('Detail terminal ring', ring_pts, .0035, 'body', 'A88A3A', 'brass', n=6, closed=True)
    s.box('Detail plus bar', (0, .8072, -.056), (.026, .004, .0075), 'body', 'F2F4F5', 'metal', .0015)
    s.box('Detail plus stem', (0, .8072, -.056), (.0075, .004, .026), 'body', 'F2F4F5', 'metal', .0015)
    s.box('Detail minus bar', (0, .8072, .056), (.026, .004, .0075), 'body', 'F2F4F5', 'metal', .0015)

    # lightning bolts radiating from the cap down the dome (none over the face)
    bolt = [(x * 1.25, y * 1.12) for x, y in [(-.021, 0.0), (.023, 0.0), (.007, .096), (.034, .096), (-.004, .262), (.004, .138), (-.025, .138)]]
    for i, az in enumerate([66.0, -66.0, 124.0, -124.0, 180.0]):
        mir = az < 0
        bell_decal(s, 'Detail bolt edge %d' % i, offset_poly(bolt, .0065), az, 70.0, '5A3E9E', mirror=mir, off=.0016)
        bell_decal(s, 'Detail bolt %d' % i, bolt, az, 70.0, 'FFE24A', glow=.35, mirror=mir, off=.0027)

    # a battery charge badge on his back, under the centre bolt (the fight camera sees his back): three
    # of four bars lit, never quite full
    def rrect(wd, ht, r, v0=0.0, seg=4):
        pts = []
        for cu, cv, a0 in [(wd / 2 - r, v0 + r, -90), (wd / 2 - r, v0 + ht - r, 0), (-wd / 2 + r, v0 + ht - r, 90), (-wd / 2 + r, v0 + r, 180)]:
            for j in range(seg + 1):
                a = math.radians(a0 + 90.0 * j / seg)
                pts.append((cu + r * math.cos(a), cv + r * math.sin(a)))
        return pts
    BADGE_EL = 22.0
    bell_decal(s, 'Detail charge badge', rrect(.096, .17, .022), 180.0, BADGE_EL, '4E3592', off=.0016)
    bell_decal(s, 'Detail charge nub', rrect(.038, .02, .007, -.016), 180.0, BADGE_EL, '4E3592', off=.0016)
    for k in range(4):
        vb = .154 - k * .0352
        lit = k < 3
        bell_decal(s, 'Detail charge bar %d' % k, rrect(.066, .027, .006, vb - .027), 180.0, BADGE_EL,
                   'FFE24A' if lit else '6A5BB0', glow=.55 if lit else 0.0, off=.0027, levels=1)

    # ---------------------------------------------------------------------------------------------
    # Antennae: light-bulb electrodes on springy steel stalks (the bulbs stay inside the 0.07 m antenna
    # hit volume), and soft rubber mitten arms with team-tint cuffs.
    # ---------------------------------------------------------------------------------------------
    for side, sx in [('l', 1), ('r', -1)]:
        bone = 'antenna_' + side
        a0, b0 = Vector((sx * .14, .76, -.02)), Vector((sx * .2, .9, -.04))
        ax = (b0 - a0).normalized()
        bc = Vector((sx * .21, .925, -.04))
        stem = [a0 - ax * .035, a0, a0.lerp(b0, .5), bc - ax * .066]
        s.tube('Antenna stalk ' + side, stem, [.0175, .016, .0145, .014], bone, cap, 'metal', n=12, soft=True)
        u = ax.cross(Vector((0, 0, 1))).normalized()
        v = ax.cross(u).normalized()
        coil = []
        for i in range(49):
            t = i / 48
            ang = t * 3.25 * math.tau
            coil.append(a0 + ax * (.004 + .06 * t) + (u * math.cos(ang) + v * math.sin(ang)) * .0225)
        s.tube('Detail antenna spring ' + side, coil, .0042, bone, 'C9923C', 'brass', n=6)
        s.tube('Antenna socket ' + side, [bc - ax * .066, bc - ax * .05, bc - ax * .036], [.022, .028, .03], bone, 'C8A24A', 'brass', n=18)
        for j, (t, rr) in enumerate([(.06, .0258), (.046, .0302)]):
            rp = [bc - ax * t + (u * math.cos(i * math.tau / 18) + v * math.sin(i * math.tau / 18)) * rr for i in range(18)]
            s.tube('Detail socket thread %s%d' % (side, j), rp, .0026, bone, '9C7A30', 'brass', n=5, closed=True)
        br = (.055, .058, .055)
        bulbo = s.ellipsoid('Antenna bulb ' + side, tuple(bc), br, bone, bulb, 'glass', glow=.85, n=24, m=12)
        s.paint(bulbo, lambda p, n, c: (lambda col: (col[0], col[1], col[2], .7 + .25 * max(0.0, n.y)))(
            mix(lin('FFC42A'), lin('FFEC85'), max(0.0, n.y) * .6)))
        for face_z, tag in [(1, 'front'), (-1, 'back')]:
            fil = []
            for x, y in [(-.022, -.008), (-.011, .011), (0, -.008), (.011, .011), (.022, -.008)]:
                z = br[2] * math.sqrt(max(0.0, 1 - (x / br[0]) ** 2 - (y / br[1]) ** 2)) + .0006
                fil.append(bc + Vector((sx * x, y, face_z * z)))
            s.tube('Detail filament %s %s' % (side, tag), fil, .0028, bone, 'FF8A2A', 'glass', glow=.9, n=6)
        gd = Vector((sx * -.32, .55, .77)).normalized()
        s.ellipsoid('Detail bulb glint ' + side, tuple(bc + Vector((gd.x * br[0], gd.y * br[1], gd.z * br[2]))), (.009, .012, .006), bone, 'FFFFFF', 'glass', n=10, m=5)

        arm = 'arm_' + side
        apts = [(sx * .29, .487, .045), (sx * .35, .48, .07), (sx * .47, .461, .113), (sx * .552, .447, .143)]
        dp, dr = densify(apts, [.062, .059, .055, .051], 3)
        armo = s.tube('Rubber arm ' + side, dp, dr, arm, lav, n=20, soft=True)
        s.paint(armo, lambda p, n, c: (lambda col: (col[0], col[1], col[2], 0.0))(
            mix(mix(lin('C2ACEE'), lin('9479C9'), max(0.0, -n.y) * .8), lin('D0BEF4'), max(0.0, n.y) * .35)))
        s.tube('Team cuff ' + side, [(sx * .546, .448, .141), (sx * .586, .4425, .156)], [.0575, .0585], arm, 'FFFFFF', 'team', n=20)
        mit = s.ellipsoid('Mitten ' + side, (sx * .633, .432, .181), (.069, .066, .069), arm, 'A68BD9', n=24, m=12)
        s.paint(mit, lambda p, n, c: (lambda col: (col[0], col[1], col[2], 0.0))(
            mix(mix(lin('B39AE6'), lin('8467BE'), max(0.0, -n.y) * .7), lin('CBB8F2'), max(0.0, n.y) * .4)))
        s.capsule('Mitten thumb ' + side, (sx * .603, .458, .217), (sx * .61, .49, .236), .0205, arm, 'AE95E2', n=12, soft=False)

    # detachable gore piece: the battery cap pops off like a champagne cork
    s.tube('Gore battery cap', [(0, -.024, 0), (0, .014, 0), (0, .02, 0), (0, .024, 0)], [.062, .062, .059, .052], None, cap, 'metal', n=28, role='gore')
    s.tube('Gore cap stripe', [(0, -.006, 0), (0, .008, 0)], [.0635, .0635], None, 'F2CC2E', 'metal', n=28, role='gore')
    s.tube('Gore cap terminal', [(0, .022, 0), (0, .034, 0), (0, .04, 0)], [.021, .021, .016], None, 'D7B24C', 'brass', n=16, role='gore')

    s.set_look({'glow_mode': 'pulse', 'fx': {'pupil_reach': .0075, 'jaw_deg': 7, 'brow_drop': .011, 'lid_rest': .07,
                                             'spring_gain': 1.4, 'spring_stiffness': .8}})
    s.bake_ao(rays=14, distance=.085, strength=.36)
