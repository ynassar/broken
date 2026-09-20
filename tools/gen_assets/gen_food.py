"""
gen_food.py - clickable food pieces -> assets/models/food_*.glb

Each file is ONE piece: origin at bottom centre, real-world size so it sits
on plate.glb (well at y=0.012) or bowl.glb (broth at y~0.06).  Flat shaded,
chunky, saturated.  Run `python3 gen_food.py`.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb import (Material, Geo, merge, box, quad, extrude, lathe, cylinder, cone, sphere,  # noqa: E402
                 ellipsoid, torus, disc, tube, rounded_rect, circle, wavy_polygon, write_glb, shade)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, '..', '..', 'assets', 'models'))
MANIFEST = []


def save(name, geo, note=''):
    os.makedirs(OUT, exist_ok=True)
    # normalise: bottom at y=0, centred in x/z
    lo, hi = geo.bounds()
    geo = geo.translate(-(lo[0] + hi[0]) / 2, -lo[1], -(lo[2] + hi[2]) / 2)
    tris = write_glb(os.path.join(OUT, name + '.glb'), geo, name)
    lo, hi = geo.bounds()
    size = hi - lo
    MANIFEST.append((name, tris, size, note))
    print('  %-24s %4d tris  size %.3f x %.3f x %.3f  %s' % (name, tris, size[0], size[1], size[2], note))
    return tris


def M(name, color, **kw):
    kw.setdefault('roughness', 0.85)
    return Material(name, color, **kw)


BUN = M('bun', '#e3a052')
BUN_DARK = M('bun_dark', '#c5843c')
SESAME = M('sesame', '#fbf1d3')
PATTY = M('patty', '#6b3a22')
PATTY_CHAR = M('patty_char', '#3e2114')
CHEESE = M('cheese', '#f9b32c', roughness=0.6)
LETTUCE = M('lettuce', '#6dc43b')
LETTUCE_DARK = M('lettuce_dark', '#4d9c2a')
TOMATO = M('tomato', '#e8352c', roughness=0.5)
TOMATO_IN = M('tomato_in', '#f06a5a', roughness=0.5)
BACON = M('bacon', '#a8342a')
BACON_FAT = M('bacon_fat', '#f0c8a0')
TORTILLA = M('tortilla', '#efd39a')
TORTILLA_GRILL = M('tortilla_grill', '#c9a56a')
FOIL = M('foil', '#ffffff', texture='foil.png', roughness=0.35, metallic=0.2)
RICE = M('rice', '#fbf8ef')
BEANS = M('beans', '#5a3320')
MEAT = M('meat', '#8d4a2c')
GUAC = M('guac', '#8fc43f')
SALSA = M('salsa', '#d63a2a', roughness=0.5)
CRUST = M('crust', '#e0a24f')
CRUST_DARK = M('crust_dark', '#b97f38')
SAUCE = M('sauce', '#c8321f', roughness=0.5)
PIZZA_CHEESE = M('pizza_cheese', '#f6cf5a', roughness=0.55)
PEPPERONI = M('pepperoni', '#b8322b')
PEPPERONI_EDGE = M('pepperoni_edge', '#8a2119')
BASIL = M('basil', '#3e8a2e')
NOODLE = M('noodle', '#f3d97a')
NOODLE_DARK = M('noodle_dark', '#d9b84f')
CHASHU = M('chashu', '#c98a70')
CHASHU_FAT = M('chashu_fat', '#f4dcc8')
CHASHU_EDGE = M('chashu_edge', '#7a3f2a')
NARUTO = M('naruto', '#fbeef0')
NARUTO_PINK = M('naruto_pink', '#f27ea0')
BROTH = M('broth', '#c8782e', roughness=0.35)
BROTH_OIL = M('broth_oil', '#e9a53a', roughness=0.3)
SCALLION = M('scallion', '#5fb542')
NORI = M('nori', '#1d2b1e')
EGG_WHITE = M('egg_white', '#fbf6ea')
EGG_YOLK = M('egg_yolk', '#f2a530', roughness=0.5)
WING = M('wing', '#d2582a', roughness=0.55)
WING_DARK = M('wing_dark', '#9c3a1c', roughness=0.55)
BONE = M('bone', '#f2e9d6')
TACO = M('taco', '#e9b64b')
TACO_DARK = M('taco_dark', '#c48f32')
SHRED_CHEESE = M('shred_cheese', '#f7a83a')
HOTDOG_BUN = M('hotdog_bun', '#e6b06a')
SAUSAGE = M('sausage', '#b8442f')
CHILI = M('chili', '#7d2f1e')
ONION = M('onion', '#f6f2ea')
FRY = M('fry', '#f2c04d')
FRY_TIP = M('fry_tip', '#d9973a')
BREAD = M('bread', '#e6b872')
BREAD_CRUST = M('bread_crust', '#c58a3f')
HAM = M('ham', '#d97a7a')
PANCAKE = M('pancake', '#e9b45c')
PANCAKE_EDGE = M('pancake_edge', '#c98b3c')
BUTTER = M('butter', '#fbe27a', roughness=0.6)
SYRUP = M('syrup', '#8a4a16', roughness=0.3)
GLASS = M('glass', '#cfe9f5', roughness=0.25, alpha=0.45)
SHAKE = M('shake', '#f5a3c1', roughness=0.5)
CREAM = M('cream', '#fdfaf3')
DOUGHNUT = M('doughnut', '#e1a55c')
GLAZE = M('glaze', '#f27ea0', roughness=0.4)
STRAW = M('straw', '#ef4d4d')
STRAW_WHITE = M('straw_white', '#fdfdfd')
CHERRY = M('cherry', '#c8142a', roughness=0.35)
STEAK = M('steak', '#7c3a22')
STEAK_CHAR = M('steak_char', '#3b1c10')
STEAK_INSIDE = M('steak_inside', '#d8636b')
STEAK_FAT = M('steak_fat', '#f1e4cf')
ROSEMARY = M('rosemary', '#4a7a3a')
OMELET = M('omelet', '#f6c542')
OMELET_BROWN = M('omelet_brown', '#d99a2f')
KETCHUP = M('ketchup', '#d3241c', roughness=0.4)
SALMON = M('salmon', '#f4884f', roughness=0.5)
SALMON_STRIPE = M('salmon_stripe', '#fbd9c2', roughness=0.5)
DUMPLING = M('dumpling', '#f3e3b8')
DUMPLING_BROWN = M('dumpling_brown', '#c99a4e')


# ------------------------------------------------------------------ helpers
def patty(r, h, y0, segs=12):
    """Burger patty: cylinder with alternating charred side faces + char stripes on top."""
    pts = circle(r, segs)
    side = [PATTY_CHAR if i % 3 == 0 else PATTY for i in range(segs)]
    g = extrude(PATTY, pts, h, y0=y0, side_mats=side, mat_top=PATTY, mat_bottom=PATTY)
    for k in (-0.6, 0, 0.6):
        g += box(PATTY_CHAR, (r * 1.5, 0.0015, 0.006), (0, y0 + h + 0.0005, k * r)).rotate_y(25)
    return g.jitter(0.0015, seed=int(y0 * 1000))


def cheese_slice(size, y0, drips=3, rot=20, thick=0.005):
    g = extrude(CHEESE, [(-size / 2, -size / 2), (size / 2, -size / 2), (size / 2, size / 2), (-size / 2, size / 2)],
                thick, y0=y0)
    rng = np.random.default_rng(int(y0 * 1000))
    for k in range(drips):
        a = rng.uniform(0, 2 * math.pi)
        x, z = size / 2 * 0.98 * math.cos(a), size / 2 * 0.98 * math.sin(a)
        d = rng.uniform(0.008, 0.016)
        g += box(CHEESE, (0.012, d, 0.012), (x, y0 + thick / 2 - d / 2 + 0.001, z)).rotate_y(rng.uniform(0, 90))
    return g.rotate_y(rot)


def lettuce_leaf(r, y0, amp=0.008, waves=9, thick=0.006, seed=0):
    pts = wavy_polygon(r, 24, waves, amp, phase=seed)
    g = extrude(LETTUCE, pts, thick, y0=y0, mat_bottom=LETTUCE_DARK, side_mats=[LETTUCE_DARK] * 24)
    return g.jitter(0.002, seed=seed)


def tomato_slice(r, y0, thick=0.008):
    g = cylinder(TOMATO, r, thick, 12, y0=y0, mat_top=TOMATO_IN, mat_bottom=TOMATO_IN)
    g += cylinder(TOMATO, r * 0.55, 0.002, 8, y0=y0 + thick, cap_bottom=False)
    return g


def bun_top(r, y0, seeds=11):
    prof = [(r, y0), (r * 1.02, y0 + 0.014), (r * 0.94, y0 + 0.034), (r * 0.72, y0 + 0.05),
            (r * 0.4, y0 + 0.06), (0, y0 + 0.064)]
    g = lathe(BUN, [(0, y0), (r, y0)], 12) + lathe(BUN, prof, 12)
    rng = np.random.default_rng(7)
    for i in range(seeds):
        a = rng.uniform(0, 2 * math.pi)
        t = rng.uniform(0.15, 0.85)
        # find surface height via profile interpolation
        rr = t * r
        # crude: interpolate y on profile
        ys = [p[1] for p in prof][::-1]
        rs = [p[0] for p in prof][::-1]
        y = np.interp(rr, rs, ys)
        g += box(SESAME, (0.006, 0.003, 0.004), (rr * math.cos(a), y + 0.001, rr * math.sin(a)),
                 faces=('+x', '-x', '+y', '+z', '-z')).rotate_y(rng.uniform(0, 180))
    return g


def bun_bottom(r, y0, h=0.03):
    prof = [(0, y0), (r * 0.9, y0), (r, y0 + h * 0.35), (r, y0 + h * 0.8), (r * 0.94, y0 + h), (0, y0 + h)]
    return lathe(BUN, prof, 12)


# ------------------------------------------------------------------ foods
def food_burger():
    r = 0.07
    y = 0.0
    g = bun_bottom(r, y); y += 0.03
    g += patty(r * 0.97, 0.024, y); y += 0.024
    g += cheese_slice(0.128, y, rot=15); y += 0.005
    g += lettuce_leaf(r * 1.05, y, seed=1); y += 0.006
    g += tomato_slice(r * 0.9, y); y += 0.008
    g += patty(r * 0.97, 0.024, y + 0.001); y += 0.025
    g += cheese_slice(0.128, y, rot=-30); y += 0.005
    # bacon strips
    for k, ang in ((-0.025, 10), (0.02, -15)):
        strip = box(BACON, (0.15, 0.006, 0.02), (0, y + 0.003, k)).rotate_y(ang)
        fat = box(BACON_FAT, (0.15, 0.0065, 0.005), (0, y + 0.003, k)).rotate_y(ang)
        g += strip.jitter(0.002, seed=int(k * 1000)) + fat
    y += 0.007
    g += bun_top(r, y)
    return g


def burrito_body(length, r, mat=TORTILLA):
    prof = [(0, 0), (r * 0.6, 0), (r * 0.9, 0.012), (r, 0.03), (r, length - 0.03), (r * 0.9, length - 0.012),
            (r * 0.6, length), (0, length)]
    return lathe(mat, prof, 12)


def food_burrito():
    L, r = 0.35, 0.042
    g = burrito_body(L, r)
    # grill marks: a few dark thin bands
    for t in (0.35, 0.5, 0.62, 0.78):
        g += torus(TORTILLA_GRILL, r * 0.99, 0.003, 12, 3).translate(0, L * t, 0).scale(1.0, 1.0, 1.0)
    # foil on the first 40%: slightly bigger radius, crinkled
    foil = lathe(FOIL, [(0, 0), (r * 0.7, 0), (r * 1.06, 0.01), (r * 1.06, L * 0.4), (r * 0.98, L * 0.4 + 0.005), (0, L * 0.4 + 0.005)], 12)
    g += foil.jitter(0.003, seed=4)
    # tortilla fold seam
    g += box(TORTILLA_GRILL, (0.012, L * 0.55, 0.004), (0, L * 0.7, r * 0.99)).rotate_y(0)
    # lay it down along X
    return g.rotate_z(-90).translate(0, r * 1.06, 0)


def food_burrito_chunk():
    L, r = 0.08, 0.042
    # tortilla ring (open end at +Y), the cut face shows filling wedges
    prof = [(0, 0), (r * 0.6, 0), (r * 0.9, 0.012), (r, 0.03), (r, L), (r * 0.88, L)]
    g = lathe(TORTILLA, prof, 12)
    g += torus(TORTILLA_GRILL, r * 0.99, 0.003, 12, 3).translate(0, L * 0.5, 0)
    fills = [RICE, BEANS, MEAT, GUAC, SALSA, RICE]
    n = len(fills)
    for i, m in enumerate(fills):
        wedge = lathe(m, [(r * 0.88, L - 0.004), (r * 0.3, L + 0.004), (0, L + 0.004)], 2, angle=360.0 / n)
        g += wedge.rotate_y(360.0 * i / n).jitter(0.002, seed=i)
    return g.rotate_z(-90).translate(0, r, 0)


def food_pizza_slice():
    R = 0.35
    ang = 45.0
    n = 6
    arc = [(R * math.sin(math.radians(-ang / 2 + ang * k / n)), R * math.cos(math.radians(-ang / 2 + ang * k / n))) for k in range(n + 1)]
    wedge = [(0, 0.0)] + arc
    g = extrude(CRUST, wedge, 0.012, mat_bottom=CRUST_DARK)
    # sauce + cheese slightly inset
    inset = [(0.6 * 0 + 0.0, 0.03)] + [(x * 0.92, z * 0.92) for x, z in arc]
    g += extrude(SAUCE, inset, 0.004, y0=0.012)
    cheese = [(0.0, 0.035)] + [(x * 0.9 * (1 + 0.03 * math.sin(k * 5.0)), z * 0.9 * (1 + 0.03 * math.sin(k * 5.0)))
                               for k, (x, z) in enumerate(arc)]
    g += extrude(PIZZA_CHEESE, cheese, 0.006, y0=0.016).jitter(0.0015, seed=2)
    # puffy crust along the arc
    crust_prof = [(x * 1.0, z * 1.0) for x, z in arc] + [(x * 0.9, z * 0.9) for x, z in arc[::-1]]
    g += extrude(CRUST, crust_prof, 0.028, y0=0.005, mat_top=CRUST_DARK).jitter(0.003, seed=3)
    # pepperoni
    rng = np.random.default_rng(11)
    for k in range(5):
        t = rng.uniform(0.35, 0.85)
        a = rng.uniform(-ang / 2 * 0.75, ang / 2 * 0.75)
        x, z = R * t * math.sin(math.radians(a)), R * t * math.cos(math.radians(a))
        g += cylinder(PEPPERONI, 0.024, 0.004, 10, y0=0.022, mat_top=PEPPERONI).translate(x, 0, z)
        g += torus(PEPPERONI_EDGE, 0.021, 0.0025, 10, 3).translate(x, 0.0255, z)
    # basil leaf + cheese drip at the tip
    g += ellipsoid(BASIL, 0.012, 0.002, 0.018, 6, 3, (0.01, 0.024, 0.16)).rotate_y(20)
    g += box(PIZZA_CHEESE, (0.01, 0.02, 0.008), (0.0, 0.01, 0.045))
    return g


def food_noodle_clump():
    g = ellipsoid(NOODLE_DARK, 0.045, 0.02, 0.045, 9, 4, (0, 0.02, 0)).jitter(0.004, seed=1)
    rng = np.random.default_rng(3)
    for k in range(6):
        a0 = rng.uniform(0, 2 * math.pi)
        pts = []
        for s in range(7):
            t = s / 6
            a = a0 + t * rng.uniform(1.5, 3.0)
            rr = 0.02 + 0.026 * math.sin(math.pi * t) * rng.uniform(0.6, 1.0)
            pts.append((rr * math.cos(a), 0.02 + 0.02 * math.cos(math.pi * (t - 0.5)) * rng.uniform(0.7, 1.05), rr * math.sin(a)))
        g += tube(NOODLE, pts, 0.005, 4)
    # chashu slice on top
    ch = extrude(CHASHU, wavy_polygon(0.028, 12, 3, 0.003), 0.007, y0=0.038,
                 side_mats=[CHASHU_EDGE] * 12).translate(0.012, 0, -0.005)
    g += ch
    g += torus(CHASHU_FAT, 0.02, 0.0035, 12, 3).translate(0.012, 0.045, -0.005)
    g += box(CHASHU_FAT, (0.012, 0.0015, 0.05), (0.012, 0.0455, -0.005)).rotate_y(30)
    # narutomaki
    nar = cylinder(NARUTO, 0.014, 0.005, 10, y0=0.036).translate(-0.028, 0, 0.018)
    nar += box(NARUTO_PINK, (0.016, 0.0015, 0.004), (-0.028, 0.0415, 0.018)).rotate_y(0)
    nar += box(NARUTO_PINK, (0.016, 0.0015, 0.004), (-0.028, 0.0415, 0.018)).rotate_y(70)
    g += nar
    # scallion bits
    for k in range(5):
        g += cylinder(SCALLION, 0.004, 0.003, 5, y0=0.03 + rng.uniform(0, 0.01)).translate(rng.uniform(-0.03, 0.03), 0, rng.uniform(-0.03, 0.03))
    return g


def food_broth():
    g = cylinder(BROTH, 0.10, 0.008, 18)
    rng = np.random.default_rng(5)
    for k in range(7):
        r = rng.uniform(0.006, 0.014)
        a, d = rng.uniform(0, 2 * math.pi), rng.uniform(0, 0.08)
        g += cylinder(BROTH_OIL, r, 0.0025, 8, y0=0.008).translate(d * math.cos(a), 0, d * math.sin(a))
    for k in range(6):
        a, d = rng.uniform(0, 2 * math.pi), rng.uniform(0.02, 0.085)
        g += box(SCALLION, (0.008, 0.003, 0.008), (d * math.cos(a), 0.0105, d * math.sin(a))).rotate_y(rng.uniform(0, 90))
    # nori sheet leaning at the edge + half egg
    g += box(NORI, (0.05, 0.001, 0.035), (-0.06, 0.01, -0.05)).rotate_y(-30)
    egg = lathe(EGG_WHITE, [(0, 0), (0.024, 0), (0.024, 0.003), (0.012, 0.003)], 10).translate(0.05, 0.008, 0.04) + \
        lathe(EGG_YOLK, [(0.012, 0.003), (0.009, 0.006), (0, 0.007)], 10).translate(0.05, 0.008, 0.04)
    g += egg
    return g


def food_wing():
    g = ellipsoid(WING, 0.032, 0.02, 0.019, 9, 5, (-0.01, 0.02, 0)).jitter(0.002, seed=1)
    g += ellipsoid(WING, 0.022, 0.016, 0.016, 8, 4, (0.028, 0.017, 0.004)).jitter(0.0015, seed=2)
    g += cylinder(BONE, 0.004, 0.012, 6).rotate_z(90).translate(0.05, 0.016, 0.004)
    g += sphere(BONE, 0.005, 6, 3, (0.052, 0.016, 0.004))
    for k in range(5):
        a = k * 1.3
        g += box(WING_DARK, (0.008, 0.003, 0.006), (-0.01 + 0.022 * math.cos(a), 0.035 + 0.004 * math.sin(a), 0.014 * math.sin(a))).rotate_y(k * 40)
    return g


def food_taco():
    R, w = 0.05, 0.11
    n = 8
    outer = [(R * math.cos(math.pi * k / n), R * math.sin(math.pi * k / n)) for k in range(n + 1)]
    inner = [(0.93 * x, 0.93 * z) for x, z in outer[::-1]]
    shell = extrude(TACO, outer + inner, w, side_mats=None).jitter(0.0015, seed=2)
    # shell is in x-z (arc in x/z); rotate so the arc stands up: x->x, z->-y ... use rotate_x
    g = shell.rotate_x(-90)          # z -> y ; extrusion (y) -> -z
    g = g.rotate_y(90)               # extrusion now along x
    g = g.translate(w / 2, 0, 0)
    g = g.rotate_x(180).translate(0, R, 0)  # open side up
    # filling
    g += box(MEAT, (0.09, 0.025, 0.03), (0, 0.027, 0)).jitter(0.004, seed=3)
    g += extrude(LETTUCE, wavy_polygon(0.02, 20, 6, 0.006), 0.01, y0=0.04, side_mats=[LETTUCE_DARK] * 20).scale(2.3, 1, 0.9).jitter(0.003, seed=5)
    rng = np.random.default_rng(6)
    for k in range(7):
        g += box(SHRED_CHEESE, (0.014, 0.003, 0.003), (rng.uniform(-0.04, 0.04), 0.051, rng.uniform(-0.01, 0.01))).rotate_y(rng.uniform(0, 180))
    for k in range(4):
        g += box(TOMATO, (0.01, 0.008, 0.01), (rng.uniform(-0.035, 0.035), 0.052, rng.uniform(-0.008, 0.008))).rotate_y(rng.uniform(0, 90))
    return g


def food_hotdog():
    L = 0.17
    bun = ellipsoid(HOTDOG_BUN, L / 2, 0.028, 0.036, 12, 6, (0, 0.028, 0))
    # flatten the bottom by scaling the lower half: simply push through the floor and rely on origin normalisation
    g = bun
    saus = lathe(SAUSAGE, [(0, 0), (0.012, 0), (0.018, 0.008), (0.018, L - 0.008), (0.012, L), (0, L)], 10)
    g += saus.rotate_z(-90).translate(-L / 2, 0.045, 0)
    for i in range(4):
        x = -L / 2 + 0.03 + i * 0.036
        g += torus(BACON, 0.019, 0.004, 10, 4).rotate_z(90).rotate_y(20).translate(x, 0.045, 0)
    # chili strip + cheese + onions
    chili = extrude(CHILI, wavy_polygon(0.018, 16, 5, 0.004), 0.012, y0=0.05).scale(4.0, 1, 1).jitter(0.003, seed=1)
    g += chili
    rng = np.random.default_rng(2)
    for k in range(8):
        g += box(SHRED_CHEESE, (0.012, 0.003, 0.003), (rng.uniform(-0.06, 0.06), 0.064, rng.uniform(-0.01, 0.01))).rotate_y(rng.uniform(0, 180))
    for k in range(5):
        g += box(ONION, (0.007, 0.004, 0.007), (rng.uniform(-0.06, 0.06), 0.065, rng.uniform(-0.01, 0.01))).rotate_y(rng.uniform(0, 90))
    return g


def food_fries():
    rng = np.random.default_rng(9)
    g = Geo()
    for k in range(22):
        L = rng.uniform(0.05, 0.085)
        f = box(FRY, (0.008, 0.008, L), mats={'+z': FRY_TIP, '-z': FRY_TIP})
        f = f.rotate_x(rng.uniform(-15, 15) + (80 if k % 4 == 0 else 0)).rotate_y(rng.uniform(0, 360))
        lo, hi = f.bounds()
        f = f.translate(rng.uniform(-0.03, 0.03), -lo[1] + rng.uniform(0, 0.02) * (k % 3), rng.uniform(-0.03, 0.03))
        g += f
    return g


def food_sandwich_section():
    """10 cm section of a stuffed loaf, cut faces at +/-X."""
    L, W = 0.10, 0.11
    Mx = np.array([[0, 1, 0, -L / 2], [0, 0, 1, 0], [1, 0, 0, 0], [0, 0, 0, 1]], dtype=float)  # x->z, z->y, y->x
    # bottom half of loaf: profile in (z, y)
    bottom = [(-W / 2, 0.012), (-W / 2 + 0.008, 0.0), (W / 2 - 0.008, 0.0), (W / 2, 0.012), (W / 2, 0.03), (-W / 2, 0.03)]
    g = extrude(BREAD, bottom, L, side_mats=[BREAD_CRUST, BREAD_CRUST, BREAD_CRUST, BREAD_CRUST, BREAD, BREAD_CRUST]).transform(Mx)
    y = 0.03
    layers = [(HAM, 0.008, 1.06, 0.0), (CHEESE, 0.005, 1.1, 0.004), (HAM, 0.008, 1.03, -0.003), (TOMATO_IN, 0.007, 0.95, 0.0)]
    for mat, h, sc, off in layers:
        g += box(mat, (L + 0.004, h, W * sc), (0, y + h / 2, off)).jitter(0.0015, seed=int(y * 1000))
        y += h
    g += extrude(LETTUCE, wavy_polygon(0.02, 22, 7, 0.006), 0.01, y0=y, side_mats=[LETTUCE_DARK] * 22).scale(2.8, 1, 3.0).jitter(0.003, seed=8)
    y += 0.01
    top = [(-W / 2, y), (W / 2, y), (W / 2, y + 0.012), (W / 2 - 0.012, y + 0.03), (0, y + 0.04), (-W / 2 + 0.012, y + 0.03), (-W / 2, y + 0.012)]
    g += extrude(BREAD, top, L, side_mats=[BREAD, BREAD_CRUST, BREAD_CRUST, BREAD_CRUST, BREAD_CRUST, BREAD_CRUST, BREAD_CRUST]).transform(Mx)
    return g


def food_pancake_stack():
    g = Geo()
    y = 0.0
    for i, r in enumerate((0.07, 0.066, 0.071)):
        pts = wavy_polygon(r, 16, 5, 0.003, phase=i)
        g += extrude(PANCAKE, pts, 0.016, y0=y, side_mats=[PANCAKE_EDGE] * 16).jitter(0.0015, seed=i)
        y += 0.016
    g += extrude(SYRUP, wavy_polygon(0.055, 20, 6, 0.008), 0.004, y0=y).jitter(0.001, seed=9)
    for a in (30, 150, 260):
        x, z = 0.066 * math.cos(math.radians(a)), 0.066 * math.sin(math.radians(a))
        g += box(SYRUP, (0.012, 0.03, 0.006), (x, y - 0.012, z)).rotate_y(-a)
    g += box(BUTTER, (0.022, 0.012, 0.022), (0.005, y + 0.01, -0.005)).rotate_y(15)
    return g


def food_milkshake():
    glass_prof = [(0, 0), (0.03, 0), (0.032, 0.008), (0.027, 0.02), (0.033, 0.06), (0.04, 0.13), (0.042, 0.135),
                  (0.038, 0.135), (0.036, 0.13), (0.03, 0.06), (0.024, 0.025), (0, 0.022)]
    g = lathe(GLASS, glass_prof, 10)
    g += lathe(SHAKE, [(0, 0.024), (0.0235, 0.024), (0.03, 0.06), (0.0355, 0.125), (0, 0.125)], 10)
    # whipped cream swirl (stacked cones) above the rim
    cream = [(0.045, 0.13), (0.05, 0.145), (0.036, 0.15), (0.042, 0.163), (0.028, 0.168), (0.03, 0.18), (0.015, 0.185), (0, 0.195)]
    g += lathe(CREAM, [(0, 0.13)] + cream, 8)
    # doughnut on the rim, tilted
    dn = torus(DOUGHNUT, 0.026, 0.011, 10, 5) + torus(GLAZE, 0.026, 0.0112, 10, 4, (0, 0.002, 0)).scale(1, 0.55, 1).translate(0, 0.006, 0)
    g += dn.rotate_x(-25).translate(0.02, 0.165, 0.03)
    # straw
    straw = cylinder(STRAW, 0.004, 0.16, 6)
    for k in range(3):
        straw += torus(STRAW_WHITE, 0.0041, 0.0015, 6, 3).translate(0, 0.03 + k * 0.05, 0)
    g += straw.rotate_x(-12).rotate_y(200).translate(-0.02, 0.06, -0.01)
    g += sphere(CHERRY, 0.009, 6, 3, (0, 0.2, 0))
    g += cylinder(BASIL, 0.001, 0.02, 4, y0=0.205)
    return g


def point_in_poly(pts, x, z):
    inside = False
    n = len(pts)
    for i in range(n):
        x0, z0 = pts[i]
        x1, z1 = pts[(i + 1) % n]
        if (z0 > z) != (z1 > z):
            xi = x0 + (z - z0) / (z1 - z0) * (x1 - x0)
            if x < xi:
                inside = not inside
    return inside


def food_steak():
    outline = [(x * 1.35, z) for x, z in wavy_polygon(0.065, 22, 3, 0.01)]
    h = 0.03
    g = extrude(STEAK, outline, h, side_mats=[STEAK_INSIDE if 5 <= i <= 9 else STEAK for i in range(22)]).jitter(0.002, seed=4)
    # fat cap along one edge
    g += box(STEAK_FAT, (0.07, h * 0.6, 0.008), (0.03, h / 2, 0.062)).rotate_y(-10)
    # char stripes on top, clipped to the outline
    for k in range(-4, 5):
        d = k * 0.018
        samples = []
        for s in np.linspace(-0.11, 0.11, 60):
            x, z = s * math.cos(math.radians(30)) - d * math.sin(math.radians(30)), s * math.sin(math.radians(30)) + d * math.cos(math.radians(30))
            if point_in_poly(outline, x, z):
                samples.append((x, z))
        if len(samples) < 3:
            continue
        (x0, z0), (x1, z1) = samples[0], samples[-1]
        L = math.hypot(x1 - x0, z1 - z0) * 0.92
        g += box(STEAK_CHAR, (L, 0.0015, 0.005), ((x0 + x1) / 2, h + 0.0007, (z0 + z1) / 2)).rotate_y(-30)
    g += cylinder(ROSEMARY, 0.002, 0.07, 4).rotate_z(90).rotate_y(25).translate(-0.02, h + 0.003, -0.01)
    return g


def food_rice_mound():
    prof = [(0, 0), (0.06, 0), (0.06, 0.012), (0.052, 0.03), (0.036, 0.042), (0.018, 0.05), (0, 0.053)]
    g = lathe(RICE, prof, 12).jitter(0.003, seed=2)
    rng = np.random.default_rng(3)
    for k in range(10):
        a = rng.uniform(0, 2 * math.pi); t = rng.uniform(0.2, 0.9)
        rr = t * 0.055
        y = np.interp(rr, [p[0] for p in prof][::-1], [p[1] for p in prof][::-1])
        g += box(NORI, (0.004, 0.002, 0.002), (rr * math.cos(a), y + 0.002, rr * math.sin(a))).rotate_y(rng.uniform(0, 180))
    g += box(NORI, (0.03, 0.001, 0.045), (0.0, 0.052, 0.0)).rotate_y(20)
    return g


def food_egg_omelet_slice():
    W, D, H = 0.09, 0.05, 0.02
    Mx = np.array([[0, 1, 0, -W / 2], [0, 0, 1, 0], [1, 0, 0, 0], [0, 0, 0, 1]], dtype=float)
    prof = [(-D / 2, 0), (D / 2, 0), (D / 2 - 0.004, H * 0.6), (0.0, H), (-D / 2 + 0.004, H * 0.6)]
    g = extrude(OMELET, prof, W, side_mats=[OMELET_BROWN, OMELET, OMELET, OMELET, OMELET]).transform(Mx).jitter(0.0015, seed=1)
    # cheese layer visible on the cut face
    g += box(CHEESE, (W + 0.003, 0.004, D * 0.6), (0, H * 0.45, 0))
    g += box(OMELET_BROWN, (0.03, 0.001, 0.012), (0.015, H + 0.0005, 0.005)).rotate_y(10)
    g += extrude(KETCHUP, wavy_polygon(0.012, 14, 4, 0.004), 0.004, y0=H - 0.001).scale(2.2, 1, 1).translate(-0.005, 0, -0.004)
    return g


def food_sushi():
    g = extrude(RICE, rounded_rect(0.052, 0.026, 0.008, 2), 0.02).jitter(0.002, seed=1)
    fish = extrude(SALMON, rounded_rect(0.062, 0.03, 0.01, 2), 0.009, y0=0.017).jitter(0.001, seed=2)
    for k in range(-2, 3):
        fish += box(SALMON_STRIPE, (0.006, 0.0015, 0.028), (k * 0.012 + 0.003, 0.0265, 0)).rotate_y(20)
    g += fish.rotate_z(-4)
    return g


def food_dumpling():
    prof = [(0, 0), (0.018, 0), (0.026, 0.008), (0.028, 0.016), (0.022, 0.028), (0.011, 0.036), (0, 0.038)]
    g = lathe(DUMPLING, prof[1:], 10).scale(1.5, 1, 1)
    g += lathe(DUMPLING_BROWN, prof[:2], 10).scale(1.5, 1, 1)
    g = g.jitter(0.0015, seed=3)
    for k in range(6):
        x = -0.025 + k * 0.01
        g += box(DUMPLING, (0.006, 0.01, 0.005), (x, 0.036, 0)).rotate_z(-30 + k * 12).rotate_y(0)
    return g


FOODS = [
    ('food_burger', food_burger, 'dia 0.14, h 0.18'),
    ('food_burrito', food_burrito, 'log 0.35 along X, foil at -X'),
    ('food_burrito_chunk', food_burrito_chunk, 'cut face at +X'),
    ('food_pizza_slice', food_pizza_slice, 'tip at -Z, crust at +Z'),
    ('food_noodle_clump', food_noodle_clump, 'nest ~0.09'),
    ('food_broth', food_broth, 'disc 0.20; place at bowl y=0.055'),
    ('food_wing', food_wing, ''),
    ('food_taco', food_taco, 'along X'),
    ('food_hotdog', food_hotdog, 'along X'),
    ('food_fries', food_fries, 'pile'),
    ('food_sandwich_section', food_sandwich_section, 'cut faces +/-X'),
    ('food_pancake_stack', food_pancake_stack, ''),
    ('food_milkshake', food_milkshake, 'glass dia 0.084'),
    ('food_steak', food_steak, ''),
    ('food_rice_mound', food_rice_mound, ''),
    ('food_egg_omelet_slice', food_egg_omelet_slice, 'along X'),
    ('food_sushi', food_sushi, 'along X'),
    ('food_dumpling', food_dumpling, 'along X'),
]


def main():
    print('gen_food ->', OUT)
    total = 0
    for name, fn, note in FOODS:
        total += save(name, fn(), note)
    print('  total food tris:', total)


if __name__ == '__main__':
    main()
