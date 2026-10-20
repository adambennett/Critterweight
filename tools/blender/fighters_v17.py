"""v0.9.17 roster art (docs/ART_REVAMP.md "v0.9.17"): the playable fighters rebuilt on the same locked
bodies with richer forms, patterned hides, signature silhouette details readable from the fight camera,
rigged faces (fx_eye / fx_lid / fx_brow / fx_jaw view bones) and spring-driven secondary parts
(fx_spring_*). Every coordinate is fighter rest space; parts stay registered to the existing collision
bodies (cosmetic appendages such as gills, fins and tentacles stay soft and close). No gameplay data,
bones, pivots or weights of segment bones change; the view bones are extra joints the game animates.
"""
import math
from mathutils import Vector
from mesh_tools import rgba


def _hash(*v):
    h = 2166136261
    for x in v:
        h = ((h ^ (int(x) & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
    return h / 4294967295.0


def cell_spots(p, cell=.08, radius=.36, density=.7, seed=1):
    """Deterministic cellular spots in fighter space: 0 outside, up to 1 at a spot's centre."""
    best = 0.0
    ci = [math.floor(p[k] / cell) for k in range(3)]
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                c = (ci[0] + dx, ci[1] + dy, ci[2] + dz)
                if _hash(seed, c[0], c[1], c[2], 7) > density:
                    continue
                f = Vector([(c[k] + .2 + .6 * _hash(seed, c[0], c[1], c[2], k)) * cell for k in range(3)])
                r = cell * radius * (.7 + .6 * _hash(seed, c[0], c[1], c[2], 11))
                d = (Vector(p) - f).length
                if d < r:
                    best = max(best, 1 - d / r)
    return best


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(len(a)))


def lin(hex_color, glow=0.0):
    return tuple(rgba(hex_color, glow))


def ring(s, name, c, rx, rz, bone, color, thickness=.008, mat='metal', glow=0, n=32, ytilt=0):
    pts = [(c[0] + rx * math.cos(i * math.tau / n), c[1] + ytilt * math.cos(i * math.tau / n), c[2] + rz * math.sin(i * math.tau / n)) for i in range(n)]
    return s.tube(name, pts, thickness, bone, color, mat, glow, n=6, closed=True)


def ring_xy(s, name, c, rx, ry, bone, color, thickness=.008, mat='metal', glow=0, n=32):
    """A ring facing forward (+Z): a bezel around a door, a gauge or a porthole."""
    pts = [(c[0] + rx * math.cos(i * math.tau / n), c[1] + ry * math.sin(i * math.tau / n), c[2]) for i in range(n)]
    return s.tube(name, pts, thickness, bone, color, mat, glow, n=6, closed=True)


def densify(points, radii, k=3):
    """k-1 extra rings between each pair of path points (linear in position and radius), so painted
    patterns (spots, stripes, belly gradients) have enough vertices to show."""
    pts, rads = [], []
    for i in range(len(points) - 1):
        a, b = Vector(points[i]), Vector(points[i + 1])
        ra, rb = radii[i], radii[i + 1]
        for j in range(k):
            t = j / k
            pts.append(tuple(a.lerp(b, t)))
            if isinstance(ra, (list, tuple)):
                rads.append(tuple(ra[q] * (1 - t) + rb[q] * t for q in range(2)))
            else:
                rads.append(ra * (1 - t) + rb * t)
    pts.append(tuple(points[-1])); rads.append(radii[-1])
    return pts, rads


def _interp(ys, vals, y):
    if y <= ys[0]:
        return vals[0]
    for i in range(len(ys) - 1):
        if ys[i] <= y <= ys[i + 1]:
            t = (y - ys[i]) / (ys[i + 1] - ys[i])
            return vals[i] * (1 - t) + vals[i + 1] * t
    return vals[-1]


# --------------------------------------------------------------------------------------------------
# Stoke, the Boiler Newt: a fire salamander with a furnace for a chest. Signature: the glowing dorsal
# crest and ember gills (seen from above and behind), the riveted boiler and its two back stacks.
# --------------------------------------------------------------------------------------------------
def stoke(s):
    orange = 'D9532B'; deep = 'A63A1E'; belly = 'F29A5C'; cream = 'EDE6D6'; dark = '393943'; soot = '5E2418'; brass = 'C9A227'
    ys = [.47, .51, .59, .64, .70, .75, .81, .90, 1.0, 1.10, 1.16, 1.215, 1.26, 1.29]
    zc = [0, 0, 0, 0, 0, .01, .02, .035, .04, .02, -.01, -.01, 0, .02]
    rad = [(.06, .06), (.21, .12), (.30, .175), (.315, .188), (.29, .18), (.225, .17), (.25, .215), (.295, .28), (.308, .305), (.30, .27), (.405, .17), (.37, .12), (.27, .09), (.11, .045)]
    hide_back = lin(deep); hide = lin(orange); hide_belly = lin(belly); blotch = lin(soot)

    def newt_hide(p, n, c):
        # belly light, back deep, fire-salamander blotches on the back and shoulders
        t_front = max(0.0, n.z) * .9 + max(0.0, -n.y) * .2
        col = mix(hide, hide_belly, t_front * 1.1 - .15)
        col = mix(col, hide_back, max(0.0, -n.z) * .75 + max(0.0, n.y) * .2)
        sp = cell_spots(p, .075, .55, .7, 3) * max(0.0, -n.z * 1.1 + .45)
        if sp > .22:
            col = mix(col, blotch, .8)
        elif sp > .12:
            col = mix(col, blotch, .35)
        return (col[0], col[1], col[2], c[3])

    dense_pts, dense_rad = densify([(0, y, z) for y, z in zip(ys, zc)], rad, 3)
    torso = s.tube('Body - continuous newt silhouette', dense_pts, dense_rad, 'chest', orange, n=48)
    pelvis = torso.vertex_groups.new(name='pelvis')
    chest = torso.vertex_groups['chest']
    for v in torso.data.vertices:
        w = max(0, min(1, (v.co.z - .70) / .10))
        chest.add([v.index], w, 'REPLACE'); pelvis.add([v.index], 1 - w, 'REPLACE')
    s.fit(torso, ['chest', 'pelvis'], (0, .74, 0))
    s.paint(torso, newt_hide)

    # ---- the boiler: iron plate, brass rim, rivets, glowing ember window, gauge ----
    s.ellipsoid('Boiler iron plate', (0, .985, .264), (.221, .224, .083), 'chest', dark, 'metal', n=32, m=14)
    ring_xy(s, 'Boiler brass rim', (0, .985, .318), .205, .205, 'chest', brass, .013, 'brass', n=44)
    for i in range(10):
        a = math.tau * i / 10 + .3
        s.ellipsoid('Plate rivet %d' % i, (math.cos(a) * .19, .985 + math.sin(a) * .19, .318), (.013, .013, .009), 'chest', 'B49C7D', 'brass', n=10, m=5)
    s.box('Furnace door rim', (0, .995, .331), (.257, .199, .026), 'chest', '877061', 'brass', .025)
    s.box('Furnace glass', (0, .995, .347), (.214, .157, .014), 'chest', 'FF7A1A', 'ember', .017)
    glass = next(o for o in s.collection.objects if o.name == 'Furnace glass')
    for c in glass.data.color_attributes['Color'].data:
        c.color[3] = 1
    for i, y in enumerate([.953, 1.006, 1.059]):
        s.box('Furnace grille %d' % i, (0, y, .362), (.218, .011, .014), 'chest', dark, 'metal', .004)
    s.ellipsoid('Latch', (.143, .99, .349), (.025, .032, .018), 'chest', '9C8774', 'brass', n=16, m=8)
    s.tube('Furnace gauge', [(-.15, 1.12, .27), (-.15, 1.12, .3)], [.034, .034], 'chest', brass, 'brass', n=20)
    s.ellipsoid('Detail gauge face', (-.15, 1.12, .301), (.027, .027, .004), 'chest', 'EDE6D6', 'glass', n=16, m=6)
    s.tube('Detail gauge needle', [(-.15, 1.12, .305), (-.135, 1.135, .305)], .003, 'chest', 'B0251C', 'metal', n=6)

    # ---- two back stacks fed by pipes over the shoulders (read from the fight camera) ----
    for side in (-1, 1):
        x = .12 * side
        s.tube('Exhaust pipe %d' % side, [(side * .2, 1.05, .2), (side * .27, 1.17, .05), (side * .19, 1.2, -.1), (x, 1.18, -.15)],
               [.024, .024, .024, .028], 'chest', dark, 'metal', n=14)
        s.tube('Back stack %d' % side, [(x, 1.12, -.165), (x, 1.24, -.175), (x, 1.31, -.18)], [.038, .036, .044], 'chest', dark, 'metal', n=20)
        ring(s, 'Detail stack band %d' % side, (x, 1.2, -.172), .039, .039, 'chest', brass, .006, 'brass', n=20)
        s.ellipsoid('Stack ember %d' % side, (x, 1.305, -.18), (.03, .006, .03), 'chest', 'FF7A1A', 'ember', glow=.55, n=16, m=6)

    # ---- dorsal crest: rounded spines down the back and onto the tail, ember tips ----
    back_z = [zc[i] - rad[i][1] for i in range(len(ys))]
    spine_dark = lin(dark); ember = lin('FF7A1A', .6)
    for i, y in enumerate([1.21, 1.14, 1.07, 1.0, .93, .86, .79, .72, .66]):
        z = _interp(ys, back_z, y) + .016
        if y > 1.13:
            z = max(z, -.16)
        h = .13 - .008 * abs(i - 2.5)
        base = Vector((0, y, z)); tip = base + Vector((0, .55, -1)).normalized() * h
        # a thin sail-like spine: narrow across (x), deep along the back, a sharp ember tip
        s.tube('Dorsal crest %d' % i, [base - Vector((0, .02, -.006)), base.lerp(tip, .45), tip], [(.02, .045), (.014, .03), (.002, .004)],
               'chest' if y > .74 else 'pelvis', dark, 'skin', n=12)
        crest = next(o for o in s.collection.objects if o.name == 'Dorsal crest %d' % i)
        for idx, cdat in enumerate(crest.data.color_attributes['Color'].data):
            vco = crest.data.vertices[idx].co
            p = Vector((vco.x, vco.z, -vco.y))
            t = (p - base).length / h
            cdat.color = ember if t > .58 else (lin('5E2418') if t > .3 else spine_dark)
    tail_pts = [(0, .59, -.15), (0, .55, -.22), (0, .49, -.34), (0, .44, -.42), (0, .43, -.463)]
    tail = s.tube('Newt tail', tail_pts, [.074, .065, .058, .049, .002], 'tail', orange, n=28, soft=True)
    s.paint(tail, lambda p, n, c: (lambda col: (col[0], col[1], col[2], c[3]))(
        mix(lin(orange), lin(deep), max(0.0, n.y) * .8) if (math.floor((p.z + .5) / .05) % 2) else mix(lin(soot), lin(deep), .3)))
    for i, z in enumerate([-.25, -.32, -.39]):
        y = .54 - (z + .22) * -.62
        base = Vector((0, .55 + (z + .22) * .5 + .045, z)); tip = base + Vector((0, .5, -1)).normalized() * .05
        s.tube('Tail crest %d' % i, [base, tip], [(.016, .024), (.003, .004)], 'tail', 'FF7A1A', 'skin', glow=.45, n=10)

    # ---- head: newt face, rigged eyes and brows, an opening jaw, ember gills ----
    s.ellipsoid('Head', (0, 1.36, .07), (.167, .17, .168), 'head', orange, n=30, m=14, soft=True)
    head = next(o for o in s.collection.objects if o.name == 'Head')
    s.paint(head, newt_hide)
    s.capsule('Neck', (0, 1.235, .03), (0, 1.31, .05), .093, 'head', orange, n=16)
    s.ellipsoid('Muzzle', (0, 1.313, .177), (.144, .075, .079), 'head', 'ED7842', n=28, m=12)
    s.ellipsoid('Mouth interior', (0, 1.288, .166), (.118, .03, .066), 'head', '3A1418', n=20, m=8)
    jaw = s.view_bone('fx_jaw', 'head', (0, 1.30, .07))
    s.ellipsoid('Lower jaw', (0, 1.272, .172), (.131, .042, .073), jaw, 'E9AF75', n=24, m=10)
    for x in [-.075, -.025, .025, .075]:
        s.tube('Detail lower tooth %d' % int(x * 1000), [(x, 1.29, .225 - abs(x) * .3), (x, 1.302, .228 - abs(x) * .3)], [.007, .001], jaw, cream, 'shell', n=8)
    s.tube('Smirk', [(-.126, 1.315, .217), (-.10, 1.297, .24), (-.05, 1.29, .255), (.02, 1.291, .259), (.08, 1.302, .244), (.125, 1.331, .216)], .007, 'head', '532826', n=8)
    for x in [-.057, .063]:
        s.tube('Small newt tooth %d' % int(x * 1000), [(x, 1.297, .251), (x, 1.281, .256), (x + .002, 1.266, .253)], [.011, .008, .001], 'head', cream, 'shell', n=12)
    for side, suffix in [(-1, 'r'), (1, 'l')]:
        x = side * .085
        s.rig_eye('Eye ' + suffix, (x, 1.407, .198), (.041, .046, .018), 'head', suffix, iris='FFD23F', lid_color='C24A26')
        brow = s.view_bone('fx_brow_' + suffix, 'head', (side * .08, 1.455, .21))
        s.tube('Determined brow ' + suffix, [(side * .037, 1.447, .218), (side * .074, 1.462, .209), (side * .12, 1.449, .185)], [.012, .016, .008], brow, soot, n=10)
        s.ellipsoid('Nostril ' + suffix, (side * .05, 1.333, .251), (.01, .007, .004), 'head', soot, n=12, m=6)
        # three ember gills behind each cheek, each on its own spring bone
        for g in range(3):
            base = Vector((side * .148, 1.315 + .05 * g, -.005 - .012 * g))
            out = Vector((side * 1.0, .25 + .3 * g, -.55)).normalized()
            L = .095 - .012 * g
            bone = s.view_bone('fx_spring_gill_%s_%d' % (suffix, g), 'head', tuple(base))
            mid = base + out * L * .55 + Vector((0, .012, 0)); tip = base + out * L

            def gill_col(p, base=base, L=L):
                t = (Vector(p) - base).length / L
                return 'FF7A1A' if t > .7 else ('D9532B' if t > .35 else 'B8401F')
            s.tube('Gill %s %d' % (suffix, g), [base, mid, tip], [.02, .014, .004], bone, gill_col, 'skin', n=12)
            gill = next(o for o in s.collection.objects if o.name == 'Gill %s %d' % (suffix, g))
            for idx, cdat in enumerate(gill.data.color_attributes['Color'].data):
                vco = gill.data.vertices[idx].co
                p = Vector((vco.x, vco.z, -vco.y))
                if (p - base).length / L > .7:
                    cdat.color = lin('FF8A3D', .45)
            for f in range(4):
                q = base + out * L * (.3 + .18 * f)
                up = Vector((0, 1, 0)) if f % 2 == 0 else Vector((0, -.6, .4))
                s.ellipsoid('Detail gill frond %s %d %d' % (suffix, g, f), tuple(q + up * .011), (.019, .007, .013), bone, 'FF9A6A', 'skin', glow=.3, n=10, m=5)
    s.tube('Stovepipe crest', [(0, 1.49, .066), (0, 1.515, .065), (0, 1.551, .062), (0, 1.566, .061)], [.044, .035, .036, .046], 'head', dark, 'metal', n=22)
    ring(s, 'Detail stovepipe band', (0, 1.528, .064), .037, .037, 'head', brass, .005, 'brass', n=20)
    s.ellipsoid('Stovepipe ember', (0, 1.565, .061), (.034, .004, .034), 'head', 'FF7A1A', 'ember', glow=.6, n=20, m=6)

    # ---- arms and wrapped fists ----
    for side, suffix in [(1, 'l'), (-1, 'r')]:
        x = .38 * side
        ua = s.capsule('Upper arm ' + suffix, (x, 1.13, 0), (x, .84, 0), .081, 'uarm_' + suffix, orange, n=20)
        fa = s.capsule('Forearm ' + suffix, (x, .8, 0), (x, .58, .02), .073, 'farm_' + suffix, orange, n=20)
        s.paint(ua, newt_hide); s.paint(fa, newt_hide)
        s.ellipsoid('Wrapped fist ' + suffix, (x, .5, .03), (.116, .12, .119), 'farm_' + suffix, cream, 'cloth', n=28, m=14)
        for i, y in enumerate([.57, .60, .63]):
            s.tube('Wrist wrap %s%d' % (suffix, i), [(x, y - .012, .021), (x, y + .012, .021)], [.079 + .002 * i, .078 + .002 * i], 'farm_' + suffix, cream if i != 1 else 'D8CCB3', 'cloth', n=20)
        for y in [.47, .51]:
            s.tube('Fist wrap seam %s%d' % (suffix, int(y * 100)), [(x - .08, y, .112), (x - .04, y - .008, .143), (x + .03, y - .008, .146), (x + .075, y, .122)], .003, 'farm_' + suffix, 'B6A68C', 'cloth', n=6)
        for k in range(4):
            kx = x + (k - 1.5) * .045 * side
            s.ellipsoid('Detail knuckle %s%d' % (suffix, k), (kx, .545, .118), (.022, .016, .014), 'farm_' + suffix, 'F5EFE2', 'cloth', n=10, m=5)
        s.tube('Team tape ' + suffix, [(x, .994, 0), (x, 1.028, 0)], [.083, .084], 'uarm_' + suffix, 'FFFFFF', 'team', n=24)
        leg = .15 * side
        th = s.capsule('Thigh ' + suffix, (leg, .57, 0), (leg, .35, .055), .092, 'thigh_' + suffix, orange, n=20)
        sh = s.capsule('Shin ' + suffix, (leg, .31, .058), (leg, .11, .01), .073, 'shin_' + suffix, orange, n=20)
        s.paint(th, newt_hide); s.paint(sh, newt_hide)
        s.ellipsoid('Newt foot ' + suffix, (leg, .05, .054), (.075, .049, .13), 'shin_' + suffix, 'ED7842', n=22, m=10)
        for t, dx in enumerate([-.045, -.015, .015, .045]):
            s.capsule('Toe %s%d' % (suffix, t), (leg + dx, .04, .13), (leg + dx * 1.3, .03, .185 - abs(dx) * .4), .019, 'shin_' + suffix, 'ED7842', n=10, soft=False)
            s.ellipsoid('Detail toe pad %s%d' % (suffix, t), (leg + dx * 1.3, .03, .19 - abs(dx) * .4), (.016, .01, .014), 'shin_' + suffix, 'F2A15A', n=8, m=4)
    s.tube('Gore - spare tooth', [(0, 0, 0), (0, .025, 0), (.004, .05, 0)], [.014, .012, .001], None, cream, n=16, role='gore')
    s.set_look({'glow_mode': 'flicker', 'fx': {'pupil_reach': .011, 'jaw_deg': 20, 'brow_drop': .01, 'lid_rest': .16, 'spring_gain': 1.3}})
    s.bake_ao(rays=14, distance=.085, strength=.36)


BUILDERS = {'f_stoke': stoke}
# The other fighters live in their own modules (fighters_v17_<id>.py, each defining build(s)), so
# they can be authored side by side; a missing module keeps that fighter's previous art.
import importlib
for _id in ['f_dredge', 'f_gusto', 'f_dozer', 'f_slurry', 'f_jitters', 'f_varga', 'f_knell']:
    try:
        BUILDERS[_id] = importlib.import_module('fighters_v17_' + _id).build
    except ModuleNotFoundError:
        pass
