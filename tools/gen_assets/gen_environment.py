"""
gen_environment.py - buildings, storefront, road tiles, street props and
restaurant furniture -> assets/models/*.glb

Every asset has its origin at ground level, centred on its footprint
(props: bottom centre).  1 unit = 1 m, Y up, fronts face +Z.
Run `python3 gen_environment.py`; tri counts are printed per file.
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
    tris = write_glb(os.path.join(OUT, name + '.glb'), geo, name)
    lo, hi = geo.bounds()
    size = hi - lo
    MANIFEST.append((name, tris, size, lo, note))
    print('  %-22s %5d tris  size %.2f x %.2f x %.2f  min y %.2f  %s' % (name, tris, size[0], size[1], size[2], lo[1], note))
    return tris


# ------------------------------------------------------------------ materials
def M(name, color, **kw):
    return Material(name, color, **kw)


STUCCO = M('stucco', '#ffffff', texture='stucco.png')
BRICK = M('brick', '#ffffff', texture='brick.png')
WIN_A = M('windows_a', '#ffffff', texture='windows_a.png')
WIN_B = M('windows_b', '#ffffff', texture='windows_b.png')
WIN_GLASS = M('windows_glass', '#ffffff', texture='windows_glass.png')
WIN_DECO = M('windows_deco', '#ffffff', texture='windows_deco.png')
CONCRETE = M('concrete', '#ffffff', texture='concrete.png')
ASPHALT = M('asphalt', '#ffffff', texture='asphalt.png')
ROAD_STRAIGHT = M('road_straight', '#ffffff', texture='road_straight.png')
ROAD_CROSS = M('road_cross', '#ffffff', texture='road_cross.png')
AWNING = M('awning', '#ffffff', texture='awning_stripes.png', double_sided=True)
WOOD = M('wood', '#ffffff', texture='wood.png')
CHECKER = M('checker', '#ffffff', texture='checker_floor.png')
METAL = M('metal', '#ffffff', texture='metal.png')
SIGN = M('sign_blank', '#ffffff', texture='sign_blank.png')

ROOF = M('roof', '#8f8a80')
ROOF_DARK = M('roof_dark', '#6d6862')
PARAPET = M('parapet', '#d8cdb5')
TRIM_WHITE = M('trim_white', '#f4efe4')
DOOR_DARK = M('door_dark', '#3b2f2a')
GLASS = M('glass', '#79c1e0', roughness=0.3, alpha=0.55)
GLASS_DARK = M('glass_dark', '#2f5b7f', roughness=0.4)
AC_GREY = M('ac_grey', '#b8bcbf')
AC_DARK = M('ac_dark', '#5a5f63')
CURB = M('curb', '#9c978c')
POLE_GREY = M('pole', '#5c6166')
POLE_GREEN = M('pole_green', '#2f4a3a')
LAMP = M('lamp', '#fff1c2', emissive='#ffe9a8')
TRUNK = M('trunk', '#8b6a48')
TRUNK_DARK = M('trunk_dark', '#6e5236')
FROND = M('frond', '#4d9f3c', double_sided=True)
FROND_DARK = M('frond_dark', '#377a2c', double_sided=True)
COCONUT = M('coconut', '#8a6a3a')
BENCH_IRON = M('bench_iron', '#3d4a3f')
BIN_GREEN = M('bin_green', '#2f7a4b')
BIN_DARK = M('bin_dark', '#1f4f31')
HYDRANT_RED = M('hydrant_red', '#e0392b')
HYDRANT_DARK = M('hydrant_dark', '#a8241a')
CAR_PAINT = M('car_paint', '#2e7fd9', roughness=0.5)
CAR_DARK = M('car_dark', '#1a2430')
TYRE = M('tyre', '#222222')
HUB = M('hub', '#c9ccd1')
CHROME = M('chrome', '#d7dade', roughness=0.4)
TAIL = M('tail_light', '#ff3b2a', emissive='#ff2200')
HEAD = M('head_light', '#fff6d5', emissive='#fff2c0')
TRUCK_PAINT = M('truck_paint', '#f28c28', roughness=0.6)
TRUCK_TEAL = M('truck_teal', '#2bb3a3')
TRUCK_WHITE = M('truck_white', '#f6f1e6')
BUS_BLUE = M('bus_blue', '#2258b8')
CROSS_RED = M('cross_red', '#e11d2b')
SIGN_WHITE = M('sign_white', '#f8f6f0')
STEEL = M('steel', '#7f8791')
TABLE_TOP = M('table_top', '#ffffff', texture='wood.png')
TABLE_LEG = M('table_leg', '#3a3a40')
CHAIR_SEAT = M('chair_seat', '#d94f3d')
CHAIR_FRAME = M('chair_frame', '#3a3a40')
PLATE = M('plate', '#f8f7f2', roughness=0.5)
PLATE_RIM = M('plate_rim', '#e9e6dc', roughness=0.5)
BOWL = M('bowl', '#f4f1ea', roughness=0.5)
BOWL_STRIPE = M('bowl_stripe', '#3c6fb2', roughness=0.5)
TRAY_RED = M('tray', '#c9412f', roughness=0.7)


# ------------------------------------------------------------------ building bits
def ac_unit(x, y, z, w=1.4, h=0.9, d=1.0):
    g = box(AC_GREY, (w, h, d), (x, y + h / 2, z))
    g += box(AC_DARK, (w * 0.7, 0.04, d * 0.7), (x, y + h + 0.02, z))
    g += cylinder(AC_DARK, min(w, d) * 0.28, 0.06, 10, y0=y + h + 0.04).translate(x, 0, z)
    return g


def parapet(w, d, y, t=0.3, h=0.7, mat=PARAPET):
    g = Geo()
    g += box(mat, (w, h, t), (0, y + h / 2, d / 2 - t / 2))
    g += box(mat, (w, h, t), (0, y + h / 2, -d / 2 + t / 2))
    g += box(mat, (t, h, d - 2 * t), (w / 2 - t / 2, y + h / 2, 0))
    g += box(mat, (t, h, d - 2 * t), (-w / 2 + t / 2, y + h / 2, 0))
    g += box(mat, (w + 0.1, 0.08, t + 0.1), (0, y + h + 0.04, d / 2 - t / 2))
    g += box(mat, (w + 0.1, 0.08, t + 0.1), (0, y + h + 0.04, -d / 2 + t / 2))
    g += box(mat, (t + 0.1, 0.08, d), (w / 2 - t / 2, y + h + 0.04, 0))
    g += box(mat, (t + 0.1, 0.08, d), (-w / 2 + t / 2, y + h + 0.04, 0))
    return g


def door(x, y, z, w=1.2, h=2.4, frame=TRIM_WHITE, leaf=DOOR_DARK, depth=0.12, glass=False):
    """Door on a +Z facing wall at plane z. Recess built by protruding frame."""
    g = box(frame, (w + 0.3, h + 0.15, depth), (x, y + h / 2 + 0.075, z + depth / 2 - 0.02))
    g += box(leaf, (w, h, 0.06), (x, y + h / 2, z + depth - 0.02 + 0.03))
    if glass:
        g += box(GLASS_DARK, (w * 0.7, h * 0.6, 0.02), (x, y + h * 0.55, z + depth - 0.02 + 0.07))
    g += box(CHROME, (0.05, 0.3, 0.05), (x + w * 0.35, y + h * 0.45, z + depth + 0.04))
    return g


def shop_window(x, y, z, w, h, frame=TRIM_WHITE, glass=GLASS_DARK):
    g = box(frame, (w + 0.2, h + 0.2, 0.08), (x, y + h / 2, z + 0.04))
    g += box(glass, (w, h, 0.04), (x, y + h / 2, z + 0.06))
    g += box(frame, (0.08, h, 0.03), (x, y + h / 2, z + 0.09))
    return g


def wall_block(size, center, tex, uv_scale, uv_offset=(0, 0), top=ROOF):
    """Box with a window/wall texture on 4 sides, plain roof."""
    return box(tex, size, center, mats={'+y': top, '-y': None}, uv_scale=uv_scale, uv_offset=uv_offset)


def building_a():
    """Stucco mid-rise: 12x12, ground floor + 4 window floors, penthouse."""
    w, d = 12.0, 12.0
    gh, fh, floors = 3.6, 3.2, 4
    top = gh + fh * floors
    g = box(STUCCO, (w, gh, d), (0, gh / 2, 0), mats={'+y': None, '-y': None}, uv_scale=(4, 4))
    g += wall_block((w, fh * floors, d), (0, gh + fh * floors / 2, 0), WIN_A, (6.0, 6.4), (0, gh / 6.4))
    # ground floor: door + shop windows on the +Z face
    g += door(0, 0, d / 2, w=1.6, h=2.6, glass=True)
    for x in (-3.8, 3.8):
        g += shop_window(x, 0.7, d / 2, 3.6, 2.0)
    # cornice between ground and upper floors
    g += box(PARAPET, (w + 0.4, 0.25, d + 0.4), (0, gh + 0.12, 0))
    # balconies on front
    for x in (-3.0, 3.0):
        for f in (1, 3):
            y = gh + fh * f
            g += box(PARAPET, (3.2, 0.15, 1.2), (x, y + 0.07, d / 2 + 0.6))
            g += box(TRIM_WHITE, (3.2, 0.9, 0.06), (x, y + 0.6, d / 2 + 1.17))
            g += box(TRIM_WHITE, (0.06, 0.9, 1.2), (x - 1.57, y + 0.6, d / 2 + 0.6))
            g += box(TRIM_WHITE, (0.06, 0.9, 1.2), (x + 1.57, y + 0.6, d / 2 + 0.6))
    g += parapet(w, d, top)
    # penthouse
    g += box(STUCCO, (7, 2.8, 5), (-1.0, top + 1.4, -2.0), mats={'+y': ROOF_DARK, '-y': None}, uv_scale=(4, 4))
    g += door(2.4, top, -2.0 + 2.5, w=0.9, h=2.1)
    g += ac_unit(3.5, top, 3.0)
    g += ac_unit(-4.0, top, 3.5, 1.0, 0.8, 1.0)
    return g


def building_b():
    """Brick walk-up: 12x12, 3 tall window floors over a shop base, fire escape, water tank."""
    w, d = 12.0, 12.0
    gh, fh, floors = 4.0, 3.2, 3
    top = gh + fh * floors
    g = box(BRICK, (w, gh, d), (0, gh / 2, 0), mats={'+y': None, '-y': None}, uv_scale=(3, 3))
    g += wall_block((w, fh * floors, d), (0, gh + fh * floors / 2, 0), WIN_B, (6.0, 6.4), (0, gh / 6.4))
    g += box(TRIM_WHITE, (w + 0.3, 0.3, d + 0.3), (0, gh + 0.15, 0))
    # stoop + door
    g += door(-3.5, 0.45, d / 2, w=1.2, h=2.4, frame=DOOR_DARK, leaf=M('door_green', '#2c5d3b'))
    for i in range(3):
        g += box(CONCRETE, (2.2, 0.15, 0.4), (-3.5, 0.075 + i * 0.15, d / 2 + 1.0 - i * 0.35), uv_scale=(1, 1))
    g += shop_window(2.5, 0.8, d / 2, 5.0, 2.2, frame=M('shop_green', '#2c5d3b'))
    g += box(M('shop_green2', '#2c5d3b'), (7.0, 0.6, 0.15), (2.5, 3.5, d / 2 + 0.08))
    # fire escape on the front: platforms + railings + ladders
    for f in range(floors):
        y = gh + fh * f + 0.9
        g += box(BENCH_IRON, (3.0, 0.08, 1.0), (3.0, y, d / 2 + 0.5))
        for zz in (d / 2 + 0.98,):
            g += box(BENCH_IRON, (3.0, 0.9, 0.04), (3.0, y + 0.5, zz))
        for xx in (1.52, 4.48):
            g += box(BENCH_IRON, (0.04, 0.9, 1.0), (xx, y + 0.5, d / 2 + 0.5))
        # ladder to next floor
        if f < floors - 1:
            g += box(BENCH_IRON, (0.6, fh, 0.05), (2.0, y + fh / 2, d / 2 + 0.8)).rotate_x(0)
    # cornice
    g += box(TRIM_WHITE, (w + 0.8, 0.5, d + 0.8), (0, top + 0.25, 0))
    g += parapet(w, d, top + 0.5, h=0.5, mat=BRICK)
    # water tank on legs
    tank_x, tank_z = -3.0, -3.0
    for dx in (-1.0, 1.0):
        for dz in (-1.0, 1.0):
            g += box(BENCH_IRON, (0.15, 1.6, 0.15), (tank_x + dx, top + 0.5 + 0.8, tank_z + dz))
    g += cylinder(WOOD, 1.5, 2.4, 12, y0=top + 2.1).translate(tank_x, 0, tank_z)
    g += cone(ROOF_DARK, 1.65, 0.8, 12, y0=top + 4.5).translate(tank_x, 0, tank_z)
    g += ac_unit(3.5, top + 0.5, 2.0)
    return g


def building_c():
    """Glass office: 12x12, 6 floors of curtain wall, lobby base, roof plant room."""
    w, d = 12.0, 12.0
    gh, fh, floors = 4.4, 3.2, 6
    top = gh + fh * floors
    g = box(M('lobby_stone', '#4a5258'), (w, gh, d), (0, gh / 2, 0), mats={'+y': None, '-y': None})
    g += wall_block((w, fh * floors, d), (0, gh + fh * floors / 2, 0), WIN_GLASS, (3.0, 3.2), (0, gh / 3.2))
    # lobby glass + revolving-door canopy
    g += shop_window(0, 0.3, d / 2, 9.0, 3.4, frame=AC_DARK, glass=GLASS_DARK)
    g += box(AC_DARK, (5.0, 0.25, 2.0), (0, 3.9, d / 2 + 1.0))
    g += door(0, 0.3, d / 2 + 0.1, w=2.0, h=2.8, frame=AC_DARK, leaf=GLASS_DARK)
    g += box(AC_DARK, (w + 0.3, 0.4, d + 0.3), (0, gh + 0.2, 0))
    g += parapet(w, d, top, t=0.25, h=0.5, mat=AC_DARK)
    # plant room + louvres + antenna
    g += box(AC_GREY, (5.0, 2.6, 4.0), (2.5, top + 1.3, -2.5))
    for i in range(5):
        g += box(AC_DARK, (4.4, 0.12, 0.1), (2.5, top + 0.5 + i * 0.4, -0.45))
    g += cylinder(AC_DARK, 0.06, 4.0, 6, y0=top + 2.6).translate(4.0, 0, -4.0)
    g += sphere(HYDRANT_RED, 0.15, 6, 4, (4.0, top + 6.7, -4.0))
    g += ac_unit(-3.5, top, 2.5, 1.8, 1.0, 1.4)
    g += ac_unit(-3.5, top, -2.5, 1.8, 1.0, 1.4)
    return g


def building_d():
    """Art deco: 12x12 base (3 floors) + 8x8 setback (2 floors) + tower, fins and gold trims."""
    w, d = 12.0, 12.0
    gh, fh = 4.0, 3.2
    g = box(M('deco_base', '#d99d7f'), (w, gh, d), (0, gh / 2, 0), mats={'+y': None, '-y': None})
    y1 = gh + fh * 3
    g += wall_block((w, fh * 3, d), (0, gh + fh * 1.5, 0), WIN_DECO, (6.0, 6.4), (0, gh / 6.4))
    g += box(M('gold', '#d9a441', roughness=0.5), (w + 0.3, 0.35, d + 0.3), (0, gh + 0.17, 0))
    g += parapet(w, d, y1, t=0.35, h=0.9, mat=M('deco_parapet', '#e9b89a'))
    # setback tower
    w2 = 8.0
    y2 = y1 + fh * 2
    g += wall_block((w2, fh * 2, w2), (0, y1 + fh, 0), WIN_DECO, (6.0, 6.4), (0, y1 / 6.4))
    g += parapet(w2, w2, y2, t=0.3, h=0.7, mat=M('deco_parapet2', '#e9b89a'))
    # crown: stepped blocks + spire
    g += box(M('deco_crown', '#e9b89a'), (4.0, 2.0, 4.0), (0, y2 + 1.0, 0))
    g += box(M('deco_crown2', '#d9a441', roughness=0.5), (2.6, 1.2, 2.6), (0, y2 + 2.6, 0))
    g += cone(M('spire', '#c9ccd1', roughness=0.4), 0.5, 3.0, 8, y0=y2 + 3.2)
    # vertical fins on the front and back faces
    for x in (-4.5, -1.5, 1.5, 4.5):
        g += box(M('fin', '#f6dcc7'), (0.4, fh * 3 + 0.6, 0.35), (x, gh + fh * 1.5, d / 2 + 0.17))
        g += box(M('fin2', '#f6dcc7'), (0.4, fh * 3 + 0.6, 0.35), (x, gh + fh * 1.5, -d / 2 - 0.17))
    # grand entrance
    g += box(M('deco_portal', '#d9a441', roughness=0.5), (4.0, 3.6, 0.3), (0, 1.8, d / 2 + 0.12))
    g += door(0, 0, d / 2 + 0.27, w=1.8, h=2.8, frame=M('deco_doorframe', '#3b3a45'), leaf=M('deco_door', '#7a4a2a'), glass=True)
    for x in (-4.0, 4.0):
        g += shop_window(x, 0.8, d / 2, 2.6, 2.2, frame=M('deco_frame', '#3b3a45'))
    g += ac_unit(-2.5, y1 + 0.0, 4.2, 1.2, 0.8, 1.0)
    g += ac_unit(2.5, y1 + 0.0, -4.2, 1.2, 0.8, 1.0)
    return g


def storefront():
    """Single-storey restaurant unit 10 w x 8 d x 4.5 h. Front (+Z) has big windows,
    a centred recessed door, striped awning and a blank sign board 6 x 1.2 m
    (front face at z = 4.11, centre y = 3.75)."""
    w, d, h = 10.0, 8.0, 4.5
    zf = d / 2
    g = Geo()
    # body (sides, back, roof) - front face left open and built from pieces
    g += box(STUCCO, (w, h, d), (0, h / 2, 0), mats={'+y': ROOF, '-y': None, '+z': None}, uv_scale=(4, 4))
    # front face pieces: piers, bulkhead, lintel band
    pier = 0.5
    for x in (-w / 2 + pier / 2, w / 2 - pier / 2):
        g += box(STUCCO, (pier, h, 0.3), (x, h / 2, zf - 0.15), uv_scale=(4, 4))
    g += box(STUCCO, (w, 0.6, 0.3), (0, 0.3, zf - 0.15), uv_scale=(4, 4))          # bulkhead
    g += box(STUCCO, (w, 1.5, 0.3), (0, 3.75, zf - 0.15), uv_scale=(4, 4))         # lintel / sign band
    # door recess (2.4 wide, 1.0 deep) with checker floor
    rw, rd = 2.4, 1.0
    g += box(STUCCO, (0.3, 2.4, rd), (-rw / 2 - 0.15, 0.6 + 1.2, zf - rd / 2), uv_scale=(4, 4))
    g += box(STUCCO, (0.3, 2.4, rd), (rw / 2 + 0.15, 0.6 + 1.2, zf - rd / 2), uv_scale=(4, 4))
    g += box(CHECKER, (rw + 0.6, 0.6, rd), (0, 0.3, zf - rd / 2), mats={'+z': STUCCO}, uv_scale=(1.0, 1.0))
    # actually the bulkhead spans the recess; cut it by re-adding recess floor slightly proud
    g += box(CHECKER, (rw, 0.02, rd + 0.02), (0, 0.61, zf - rd / 2 + 0.01), uv_scale=(1.0, 1.0))
    g += box(STUCCO, (rw + 0.6, 0.02, rd), (0, 3.0, zf - rd / 2), uv_scale=(4, 4))  # recess ceiling
    g += box(GLASS_DARK, (rw, 2.4, 0.06), (0, 0.6 + 1.2, zf - rd + 0.05))          # door glass
    g += box(M('door_frame', '#2f2f35'), (rw + 0.1, 0.1, 0.1), (0, 2.95, zf - rd + 0.05))
    g += box(M('door_frame2', '#2f2f35'), (0.08, 2.4, 0.1), (0, 1.8, zf - rd + 0.06))
    g += box(CHROME, (0.05, 0.4, 0.05), (0.4, 1.7, zf - rd + 0.12))
    g += box(CHROME, (0.05, 0.4, 0.05), (-0.4, 1.7, zf - rd + 0.12))
    # windows either side of the recess (0.6..3.0 m), inset 0.1
    for x0, x1 in ((-w / 2 + pier, -rw / 2 - 0.3), (rw / 2 + 0.3, w / 2 - pier)):
        cx, ww = (x0 + x1) / 2, x1 - x0
        g += box(GLASS_DARK, (ww, 2.4, 0.08), (cx, 1.8, zf - 0.12))
        g += box(TRIM_WHITE, (ww + 0.05, 0.12, 0.22), (cx, 3.0, zf - 0.1))
        g += box(TRIM_WHITE, (ww + 0.05, 0.12, 0.22), (cx, 0.6, zf - 0.1))
        g += box(TRIM_WHITE, (0.1, 2.4, 0.16), (cx, 1.8, zf - 0.1))
    # sign board 6 x 1.2 (blank), centre (0, 3.75, 4.06), front face z = 4.11
    g += box(M('sign_frame', '#d63b2f'), (6.2, 1.4, 0.1), (0, 3.75, zf + 0.03))
    g += box(SIGN, (6.0, 1.2, 0.02), (0, 3.75, zf + 0.10), uv_scale=None)
    # awning: attached at y=3.0, slopes out 1.3 m to y=2.55, valance 0.25 (profile in z,y)
    prof = [(zf, 3.0), (zf + 1.3, 2.55), (zf + 1.3, 2.30), (zf + 1.25, 2.30), (zf + 1.25, 2.50), (zf + 0.02, 2.95)]
    aw = extrude(AWNING, prof, w - 2 * pier - 0.1, uv_scale=1.2)          # in X-Z plane, extruded along Y
    # map: local x -> world z, local z -> world y, local y -> world x
    Mx = np.array([[0, 1, 0, -(w / 2 - pier - 0.05)], [0, 0, 1, 0], [1, 0, 0, 0], [0, 0, 0, 1]], dtype=float)
    g += aw.transform(Mx)
    for x in (-3.8, 0, 3.8):
        g += box(STEEL, (0.05, 0.05, 1.25), (x, 2.58, zf + 0.62)).rotate_x(0)
    # roof parapet + ac
    g += parapet(w, d, h, t=0.25, h=0.4)
    g += ac_unit(3.0, h, -2.0, 1.2, 0.8, 1.0)
    g += box(STEEL, (0.3, 1.2, 0.3), (-3.5, h + 0.6, -2.5))   # vent
    return g


# ------------------------------------------------------------------ ground tiles
def road_tile(mat):
    # top face with 0..1 uv (texture designed per tile), sides asphalt
    top = quad(mat, (-5, 0, 5), (5, 0, 5), (5, 0, -5), (-5, 0, -5), uvs=[[0, 1], [1, 1], [1, 0], [0, 0]])
    sides = box(ASPHALT, (10, 0.05, 10), (0, -0.025, 0), mats={'+y': None, '-y': None}, uv_scale=(2, 2))
    return top + sides


def sidewalk():
    g = box(CONCRETE, (10, 0.15, 10), (0, 0.075, 0), mats={'+x': CURB, '-x': CURB, '+z': CURB, '-z': CURB, '-y': None},
            uv_scale=(2.5, 2.5))
    return g


def curb_corner():
    """10x10 sidewalk block whose +X/+Z corner is rounded (r = 4 m) for intersections."""
    pts = [(-5, -5), (5, -5)]
    for k in range(7):
        a = math.radians(k * 90 / 6)
        pts.append((1 + 4 * math.cos(a), 1 + 4 * math.sin(a)))
    pts.append((-5, 5))
    g = extrude(CURB, pts, 0.15, mat_top=CONCRETE, cap_bottom=False, uv_scale=2.5)
    return g


# ------------------------------------------------------------------ props
def street_lamp():
    g = cylinder(POLE_GREEN, 0.22, 0.5, 8)
    g += cylinder(POLE_GREEN, 0.08, 6.0, 8, r_top=0.06, y0=0.5)
    path = [(0, 6.4, 0), (0.3, 6.75, 0), (0.8, 6.95, 0), (1.5, 7.0, 0)]
    g += tube(POLE_GREEN, path, 0.05, 6)
    g += box(POLE_GREEN, (0.9, 0.18, 0.35), (1.5, 6.95, 0))
    g += box(LAMP, (0.8, 0.06, 0.28), (1.5, 6.84, 0))
    g += cylinder(POLE_GREEN, 0.12, 0.08, 8, y0=6.5)
    return g


def palm_tree():
    rng = np.random.default_rng(5)
    # curved trunk
    path, radii = [], []
    n = 9
    for i in range(n):
        t = i / (n - 1)
        path.append((0.9 * t * t, 0.05 + 6.95 * t, 0.3 * math.sin(t * 2.5)))
        radii.append(0.30 - 0.14 * t)
    g = tube(TRUNK, path, 0.3, 7, radii, cap=True)
    # trunk rings (dark bands)
    for i in range(1, n - 1, 2):
        p = path[i]
        g += torus(TRUNK_DARK, radii[i] * 0.98, 0.05, 7, 3).translate(*p)
    top = np.array(path[-1])
    # fronds: bent serrated strips, double sided
    for k in range(10):
        a = 2 * math.pi * k / 10 + rng.uniform(-0.2, 0.2)
        droop = rng.uniform(0.6, 1.4)
        length = rng.uniform(2.6, 3.4)
        dirv = np.array([math.cos(a), 0, math.sin(a)])
        side = np.array([-math.sin(a), 0, math.cos(a)])
        tris, uvs = [], []
        segs = 6
        prev = None
        for s in range(segs + 1):
            t = s / segs
            lift = 1.2 * t - droop * t * t          # rises then droops
            centre = top + dirv * (length * t) + np.array([0, lift, 0]) + np.array([0, 0.3, 0])
            width = 0.55 * math.sin(math.pi * min(1, 0.15 + t * 0.9)) + 0.05
            serr = 0.12 if s % 2 else -0.05
            l = centre + side * (width + serr)
            r = centre - side * (width - serr)
            if prev is not None:
                pl, pr, pc = prev
                tris += [[pl, pc, l], [pc, centre, l], [pc, pr, centre], [pr, r, centre]]
                uvs += [[[0, 0], [0.5, 0], [0, 1]]] * 4
            prev = (l, r, centre)
        mat = FROND if k % 2 else FROND_DARK
        g += Geo().add(mat, np.array(tris), np.array(uvs))
    # coconuts
    for k in range(4):
        a = 2 * math.pi * k / 4
        g += sphere(COCONUT, 0.16, 6, 4, top + np.array([0.28 * math.cos(a), 0.05, 0.28 * math.sin(a)]))
    return g


def bench():
    g = Geo()
    for x in (-0.8, 0.8):
        g += box(BENCH_IRON, (0.08, 0.45, 0.5), (x, 0.225, 0))
        g += box(BENCH_IRON, (0.08, 0.5, 0.08), (x, 0.7, -0.22))
        g += box(BENCH_IRON, (0.12, 0.06, 0.6), (x, 0.03, 0))
    for i in range(4):
        g += box(WOOD, (1.8, 0.05, 0.1), (0, 0.45, -0.2 + i * 0.13), uv_scale=(1.8, 0.4))
    for i in range(3):
        g += box(WOOD, (1.8, 0.1, 0.05), (0, 0.6 + i * 0.14, -0.24), uv_scale=(1.8, 0.4))
    return g


def trash_can():
    g = cylinder(BIN_GREEN, 0.32, 0.95, 12, r_top=0.34)
    for i in range(3):
        g += torus(BIN_DARK, 0.335 + i * 0.005, 0.02, 12, 4).translate(0, 0.2 + i * 0.3, 0)
    g += cylinder(BIN_DARK, 0.37, 0.12, 12, r_top=0.30, y0=0.95)
    g += cylinder(BIN_DARK, 0.18, 0.05, 12, r_top=0.14, y0=1.07)
    return g


def hydrant():
    prof = [(0, 0), (0.22, 0), (0.22, 0.08), (0.14, 0.1), (0.14, 0.55), (0.17, 0.58), (0.17, 0.66), (0.14, 0.68),
            (0.12, 0.82), (0.0, 0.9)]
    g = lathe(HYDRANT_RED, prof, 10)
    g += cylinder(HYDRANT_DARK, 0.06, 0.12, 8).rotate_z(-90).translate(0.14, 0.42, 0)
    g += cylinder(HYDRANT_DARK, 0.06, 0.12, 8).rotate_z(90).translate(-0.14, 0.42, 0)
    g += cylinder(HYDRANT_DARK, 0.08, 0.1, 8).rotate_x(90).translate(0, 0.38, 0.14)
    g += cylinder(HYDRANT_DARK, 0.05, 0.06, 6, y0=0.88)
    g += torus(HYDRANT_DARK, 0.15, 0.02, 10, 4).translate(0, 0.62, 0)
    return g


def car_sedan():
    """Parked sedan ~4.5 m long along Z (front = -Z), 1.8 m wide, 1.45 m tall."""
    L, W = 4.5, 1.8
    # lower body side profile (z, y)
    body = [(-L / 2, 0.35), (-L / 2 + 0.1, 0.25), (L / 2 - 0.1, 0.25), (L / 2, 0.35), (L / 2, 0.75), (L / 2 - 0.4, 0.8),
            (-L / 2 + 0.9, 0.85), (-L / 2, 0.75)]
    Mz = np.array([[0, 1, 0, -W / 2], [0, 0, 1, 0], [1, 0, 0, 0], [0, 0, 0, 1]], dtype=float)   # x->z, z->y, y->x
    g = extrude(CAR_PAINT, body, W).transform(Mz)
    # cabin (glass) + roof
    cab = [(-L / 2 + 1.0, 0.8), (L / 2 - 0.5, 0.8), (L / 2 - 1.2, 1.4), (-L / 2 + 1.7, 1.42)]
    g += extrude(CAR_DARK, cab, W - 0.2).transform(Mz).translate(0.1, 0, 0)
    g += box(CAR_PAINT, (W - 0.24, 0.06, 1.35), (0, 1.43, -L / 2 + 1.7 + 0.6))
    # pillars
    for z in (-L / 2 + 1.0, L / 2 - 0.5):
        pass
    # wheels (axis along X)
    for z in (-L / 2 + 0.85, L / 2 - 0.85):
        for x in (-W / 2 + 0.1, W / 2 - 0.1):
            wheel = cylinder(TYRE, 0.33, 0.22, 10).rotate_z(90).translate(x + 0.11, 0.33, z)
            hub = cylinder(HUB, 0.18, 0.24, 8).rotate_z(90).translate(x + 0.10, 0.33, z)
            g += wheel + hub
    # bumpers, lights, plate
    g += box(CHROME, (W + 0.02, 0.15, 0.12), (0, 0.4, -L / 2 - 0.05))
    g += box(CHROME, (W + 0.02, 0.15, 0.12), (0, 0.4, L / 2 + 0.05))
    for x in (-0.6, 0.6):
        g += box(HEAD, (0.4, 0.18, 0.06), (x, 0.62, -L / 2 - 0.02))
        g += box(TAIL, (0.4, 0.18, 0.06), (x, 0.62, L / 2 + 0.02))
    g += box(CAR_DARK, (1.0, 0.04, 0.04), (0, 0.85, -L / 2 + 0.3))  # hood gap line
    return g


def food_truck():
    """Food truck 6 m long along Z (cab at -Z), serving hatch on the +X side."""
    L, W, H = 6.0, 2.4, 2.9
    g = box(TRUCK_PAINT, (W, 2.0, 4.2), (0, 1.6, 0.9), mats={'-y': None})               # box body
    g += box(TRUCK_WHITE, (W + 0.02, 0.5, 4.22), (0, 1.0, 0.9))                             # stripe band
    g += box(TRUCK_TEAL, (W - 0.2, 0.2, 4.0), (0, 2.7, 0.9))                                 # roof rim
    g += box(TRUCK_PAINT, (W - 0.1, 1.2, 1.7), (0, 1.15, -2.1), mats={'-y': None})           # cab
    g += box(CAR_DARK, (W - 0.3, 0.6, 1.3), (0, 1.95, -1.95))                                # cab windows
    g += box(TRUCK_PAINT, (W - 0.1, 0.3, 1.7), (0, 2.4, -2.1))                               # cab roof
    g += box(CAR_DARK, (W - 0.4, 0.5, 0.05), (0, 1.9, -2.96))                                # windscreen
    # serving hatch on +X: opening + counter + tilted awning flap
    g += box(CAR_DARK, (0.05, 1.1, 2.4), (W / 2 + 0.01, 1.85, 1.0))
    g += box(TRUCK_WHITE, (0.5, 0.08, 2.6), (W / 2 + 0.2, 1.3, 1.0))
    flap = box(TRUCK_TEAL, (1.3, 0.06, 2.6), (0.65, 0, 0)).rotate_z(-35).translate(W / 2, 2.45, 1.0)
    g += flap
    # menu board + roof vent + wheels
    g += box(SIGN, (0.04, 0.8, 1.2), (W / 2 + 0.03, 1.5, -1.0))
    g += box(AC_GREY, (0.8, 0.4, 0.8), (0, 3.0, 1.8))
    g += cylinder(AC_DARK, 0.2, 0.3, 8, y0=2.8).translate(-0.6, 0, 0.0)
    for z in (-1.7, 1.9):
        for x in (-W / 2 + 0.15, W / 2 - 0.15):
            g += cylinder(TYRE, 0.42, 0.3, 10).rotate_z(90).translate(x + 0.15, 0.42, z)
            g += cylinder(HUB, 0.2, 0.32, 8).rotate_z(90).translate(x + 0.14, 0.42, z)
    g += box(CHROME, (W, 0.2, 0.15), (0, 0.5, -L / 2 + 0.05))
    g += box(CHROME, (W, 0.2, 0.15), (0, 0.5, L / 2 - 0.05))
    for x in (-0.8, 0.8):
        g += box(HEAD, (0.4, 0.25, 0.06), (x, 0.9, -L / 2 - 0.01))
        g += box(TAIL, (0.3, 0.3, 0.06), (x, 1.0, L / 2 + 0.01))
    return g


def bus_stop():
    """Shelter 4 x 1.6 m, open side facing +Z, sign pole on the right."""
    g = Geo()
    for x in (-1.9, 1.9):
        g += box(STEEL, (0.1, 2.6, 0.1), (x, 1.3, -0.7))
        g += box(STEEL, (0.1, 2.6, 0.1), (x, 1.3, 0.7))
    g += box(BUS_BLUE, (4.2, 0.12, 1.7), (0, 2.66, 0))
    g += box(GLASS, (3.8, 2.2, 0.04), (0, 1.3, -0.72))
    g += box(GLASS, (0.04, 2.2, 1.3), (-1.92, 1.3, 0))
    g += box(SIGN, (2.0, 1.0, 0.05), (0, 1.6, -0.76))
    g += box(BENCH_IRON, (3.0, 0.06, 0.4), (0, 0.45, -0.3))
    for x in (-1.3, 1.3):
        g += box(BENCH_IRON, (0.06, 0.45, 0.35), (x, 0.225, -0.3))
    g += cylinder(STEEL, 0.04, 3.0, 6).translate(2.4, 0, 0.6)
    g += box(BUS_BLUE, (0.5, 0.5, 0.05), (2.4, 3.0, 0.6))
    g += box(SIGN_WHITE, (0.4, 0.4, 0.02), (2.4, 3.0, 0.63))
    return g


def hospital_sign():
    g = cylinder(STEEL, 0.07, 4.0, 8)
    g += box(SIGN_WHITE, (1.6, 1.6, 0.1), (0, 4.6, 0))
    g += box(CROSS_RED, (1.0, 0.32, 0.14), (0, 4.6, 0))
    g += box(CROSS_RED, (0.32, 1.0, 0.14), (0, 4.6, 0))
    g += box(STEEL, (1.7, 0.08, 0.14), (0, 3.76, 0))
    g += box(STEEL, (1.7, 0.08, 0.14), (0, 5.44, 0))
    return g


def billboard():
    """Board 8 x 4 m, bottom at 6 m, blank face towards +Z (face plane z = 0.13)."""
    g = Geo()
    for x in (-2.5, 2.5):
        g += cylinder(STEEL, 0.15, 6.4, 8).translate(x, 0, -0.2)
    g += box(STEEL, (8.4, 4.4, 0.2), (0, 8.0, 0))
    g += box(SIGN, (8.0, 4.0, 0.06), (0, 8.0, 0.1))
    g += box(STEEL, (8.4, 0.12, 0.6), (0, 5.8, 0.2))         # catwalk
    for x in (-3.0, 0, 3.0):
        g += box(STEEL, (0.06, 0.06, 0.7), (x, 10.25, 0.35)).rotate_x(0)
        g += box(LAMP, (0.5, 0.15, 0.25), (x, 10.15, 0.7))
    g += box(STEEL, (5.2, 0.15, 0.15), (0, 6.3, -0.2))
    return g


# ------------------------------------------------------------------ interior
def table():
    g = box(TABLE_TOP, (1.2, 0.05, 0.8), (0, 0.725, 0), uv_scale=(1.2, 0.8))
    g += box(TABLE_LEG, (1.1, 0.08, 0.7), (0, 0.66, 0))
    for x in (-0.52, 0.52):
        for z in (-0.32, 0.32):
            g += box(TABLE_LEG, (0.06, 0.66, 0.06), (x, 0.33, z))
    return g


def chair():
    g = box(CHAIR_SEAT, (0.44, 0.06, 0.44), (0, 0.45, 0))
    for x in (-0.19, 0.19):
        for z in (-0.19, 0.19):
            g += box(CHAIR_FRAME, (0.04, 0.42, 0.04), (x, 0.21, z))
    for x in (-0.19, 0.19):
        g += box(CHAIR_FRAME, (0.04, 0.45, 0.04), (x, 0.7, -0.2))
    g += box(CHAIR_SEAT, (0.44, 0.22, 0.05), (0, 0.8, -0.2))
    g += box(CHAIR_FRAME, (0.42, 0.04, 0.04), (0, 0.62, -0.2))
    return g


def plate():
    """30 cm plate. Food sits at y = 0.012 (well surface)."""
    prof = [(0, 0), (0.10, 0), (0.15, 0.022), (0.15, 0.03), (0.115, 0.018), (0.105, 0.012), (0, 0.012)]
    g = lathe(PLATE, prof[:4], 16) + lathe(PLATE_RIM, prof[3:], 16)
    return g


def bowl():
    """24 cm ramen bowl, 8 cm tall. Inner floor at y = 0.02; broth surface ~ y = 0.06."""
    prof = [(0, 0), (0.06, 0), (0.07, 0.005), (0.10, 0.03), (0.12, 0.075), (0.12, 0.08),
            (0.108, 0.08), (0.10, 0.06), (0.075, 0.025), (0.0, 0.02)]
    g = lathe(BOWL, prof, 16)
    g += torus(BOWL_STRIPE, 0.121, 0.006, 16, 4).translate(0, 0.068, 0)
    g += torus(BOWL_STRIPE, 0.121, 0.006, 16, 4).translate(0, 0.075, 0)
    return g


def tray():
    g = box(TRAY_RED, (0.45, 0.02, 0.35), (0, 0.01, 0))
    g += box(TRAY_RED, (0.45, 0.04, 0.02), (0, 0.02, 0.165))
    g += box(TRAY_RED, (0.45, 0.04, 0.02), (0, 0.02, -0.165))
    g += box(TRAY_RED, (0.02, 0.04, 0.35), (0.215, 0.02, 0))
    g += box(TRAY_RED, (0.02, 0.04, 0.35), (-0.215, 0.02, 0))
    return g


ASSETS = [
    ('building_a', building_a, 'stucco mid-rise, 12x12, 16.4 m'),
    ('building_b', building_b, 'brick walk-up, 12x12'),
    ('building_c', building_c, 'glass office, 12x12'),
    ('building_d', building_d, 'art deco stepped tower, 12x12'),
    ('storefront', storefront, 'front +Z; sign 6x1.2 centre (0,3.75,4.11)'),
    ('road_straight', lambda: road_tile(ROAD_STRAIGHT), '10x10, road runs along Z'),
    ('road_cross', lambda: road_tile(ROAD_CROSS), '10x10 intersection'),
    ('sidewalk', sidewalk, '10x10, 0.15 high'),
    ('curb_corner', curb_corner, '10x10, +X+Z corner rounded r=4'),
    ('street_lamp', street_lamp, 'arm points +X, lamp at y 6.85'),
    ('palm_tree', palm_tree, '~8 m tall'),
    ('bench', bench, 'faces +Z'),
    ('trash_can', trash_can, ''),
    ('hydrant', hydrant, ''),
    ('car_sedan', car_sedan, 'front = -Z'),
    ('food_truck', food_truck, 'cab = -Z, hatch on +X'),
    ('bus_stop', bus_stop, 'open side +Z'),
    ('hospital_sign', hospital_sign, 'board faces +/-Z'),
    ('billboard', billboard, 'blank face +Z at z=0.13, centre y=8'),
    ('table', table, '1.2x0.8, top y=0.75'),
    ('chair', chair, 'seat y=0.48, back at -Z'),
    ('plate', plate, 'dia 0.30, food y=0.012'),
    ('bowl', bowl, 'dia 0.24, h 0.08'),
    ('tray', tray, '0.45x0.35'),
]


def main():
    print('gen_environment ->', OUT)
    total = 0
    for name, fn, note in ASSETS:
        total += save(name, fn(), note)
    print('  total environment tris:', total)


if __name__ == '__main__':
    main()
