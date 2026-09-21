"""
gen_textures.py - procedural, hand-painted-looking, tileable textures.

All textures are 512x512 (or smaller) PNGs written to assets/textures/.
Everything is built from periodic value noise + simple rect painting so each
texture tiles seamlessly.  Colours are chosen saturated / warm to suit the
flat-shaded low-poly look.
"""
import math
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, '..', '..', 'assets', 'textures'))
S = 512


# ------------------------------------------------------------------ utils
def col(c):
    c = c.lstrip('#')
    return np.array([int(c[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64)


def canvas(color, size=S):
    return np.ones((size, size, 3)) * col(color)


def value_noise(size, cells, seed, octaves=3, persistence=0.5):
    """Periodic (tileable) value noise in [0,1]."""
    rng = np.random.default_rng(seed)
    out = np.zeros((size, size))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        grid = rng.random((c, c))
        # bilinear upsample with wrap
        ys = np.linspace(0, c, size, endpoint=False)
        xs = np.linspace(0, c, size, endpoint=False)
        y0 = np.floor(ys).astype(int) % c
        x0 = np.floor(xs).astype(int) % c
        fy = (ys - np.floor(ys))[:, None]
        fx = (xs - np.floor(xs))[None, :]
        fy = fy * fy * (3 - 2 * fy)
        fx = fx * fx * (3 - 2 * fx)
        y1 = (y0 + 1) % c
        x1 = (x0 + 1) % c
        a = grid[np.ix_(y0, x0)]
        b = grid[np.ix_(y0, x1)]
        cc = grid[np.ix_(y1, x0)]
        d = grid[np.ix_(y1, x1)]
        v = (a * (1 - fx) + b * fx) * (1 - fy) + (cc * (1 - fx) + d * fx) * fy
        out += v * amp
        total += amp
        amp *= persistence
    return out / total


def painterly(img, seed, blotch=0.10, grain=0.04, cells=4):
    """Low-frequency colour blotches + fine grain -> hand-painted feel."""
    n = value_noise(img.shape[0], cells, seed, 3)
    img = img * (1 + (n - 0.5) * 2 * blotch)[..., None]
    rng = np.random.default_rng(seed + 99)
    g = rng.normal(0, grain, img.shape[:2])
    img = img * (1 + g)[..., None]
    # slight hue wobble: shift red/blue in opposite directions
    n2 = value_noise(img.shape[0], cells * 2, seed + 7, 2)
    img[..., 0] *= 1 + (n2 - 0.5) * blotch * 0.6
    img[..., 2] *= 1 - (n2 - 0.5) * blotch * 0.6
    return img


def rect(img, x0, y0, x1, y1, color, jitter=0, seed=0):
    """Fill rect (wrapping) with edge jitter for a hand-drawn edge."""
    h, w = img.shape[:2]
    c = col(color) if isinstance(color, str) else np.asarray(color, dtype=np.float64)
    rng = np.random.default_rng(seed)
    for y in range(int(y0), int(y1)):
        jx0 = x0 + (rng.integers(-jitter, jitter + 1) if jitter else 0)
        jx1 = x1 + (rng.integers(-jitter, jitter + 1) if jitter else 0)
        xs = np.arange(int(jx0), int(jx1)) % w
        img[y % h, xs] = c
    return img


def hline(img, y, x0, x1, color, thick=2):
    return rect(img, x0, y, x1, y + thick, color)


def vline(img, x, y0, y1, color, thick=2):
    return rect(img, x, y0, x + thick, y1, color)


def save(name, img):
    os.makedirs(OUT, exist_ok=True)
    arr = np.clip(img, 0, 255).astype(np.uint8)
    Image.fromarray(arr).save(os.path.join(OUT, name))
    print('  texture', name, arr.shape[1], 'x', arr.shape[0])


# ------------------------------------------------------------------ walls
def wall_stucco(seed=1, base='#ead9b6'):
    img = canvas(base)
    img = painterly(img, seed, blotch=0.07, grain=0.035, cells=3)
    # a few hairline cracks / stains
    rng = np.random.default_rng(seed + 3)
    for _ in range(6):
        x, y = rng.integers(0, S, 2)
        for k in range(rng.integers(20, 60)):
            img[(y + k) % S, (x + int(3 * math.sin(k * 0.3))) % S] *= 0.93
    return img


def wall_brick(seed=2, brick='#b4503a', mortar='#d9cbb5', rows=16, cols=8):
    img = canvas(mortar)
    img = painterly(img, seed, blotch=0.05, grain=0.05, cells=8)
    bh, bw = S // rows, S // cols
    rng = np.random.default_rng(seed)
    base = col(brick)
    for r in range(rows):
        off = (bw // 2) if r % 2 else 0
        for c in range(cols):
            x0 = c * bw + off
            y0 = r * bh
            k = rng.uniform(0.8, 1.15)
            tint = base * k + rng.uniform(-12, 12, 3)
            rect(img, x0 + 2, y0 + 2, x0 + bw - 2, y0 + bh - 2, tint, jitter=1, seed=r * 31 + c)
            # darker bottom edge on each brick for chunkiness
            rect(img, x0 + 2, y0 + bh - 5, x0 + bw - 2, y0 + bh - 2, tint * 0.8)
    img = painterly(img, seed + 5, blotch=0.06, grain=0.03, cells=3)
    return img


def draw_window(img, x0, y0, x1, y1, style, seed=0, frame='#f4efe4', glass='#3f6a93', sill=True):
    """One window into the wall image (pixel rect). style: 0 plain, 1 blinds, 2 lit, 3 dark."""
    rng = np.random.default_rng(seed)
    fw = 5
    rect(img, x0 - fw, y0 - fw, x1 + fw, y1 + fw, frame, jitter=1, seed=seed)
    g = col(glass)
    if style == 2:
        g = col('#f3c96b')
    elif style == 3:
        g = col('#2b3d54')
    rect(img, x0, y0, x1, y1, g)
    h, w = y1 - y0, x1 - x0
    # reflection: lighter diagonal band
    for y in range(y0, y1):
        t = (y - y0) / max(h, 1)
        xa = int(x0 + w * (0.55 - t * 0.5))
        xb = int(xa + w * 0.22)
        xs = np.arange(max(x0, xa), min(x1, xb))
        img[y % S, xs % S] = g * 1.35 + 25
    # sky gradient (darker at bottom)
    for y in range(y0, y1):
        t = (y - y0) / max(h, 1)
        img[y % S, np.arange(x0, x1) % S] *= (1.08 - t * 0.25)
    if style == 1:  # blinds
        for y in range(y0 + 4, y1 - 2, 8):
            hline(img, y, x0, x1, '#e8e2d0', 3)
    # mullion cross
    vline(img, (x0 + x1) // 2 - 2, y0, y1, frame, 4)
    hline(img, (y0 + y1) // 2 - 1, x0, x1, frame, 3)
    if sill:
        rect(img, x0 - fw - 4, y1 + fw, x1 + fw + 4, y1 + fw + 7, '#d9d2c2', jitter=1, seed=seed)
        rect(img, x0 - fw - 4, y1 + fw + 7, x1 + fw + 4, y1 + fw + 10, '#9d9585')
    return img


def windows_a():
    """Cream stucco with 2x2 windows per tile (tile = 6 m wide x 6.4 m tall)."""
    img = wall_stucco(11, '#efdcb4')
    styles = [0, 1, 0, 2]
    k = 0
    for r in range(2):
        for c in range(2):
            cx, cy = c * 256 + 128, r * 256 + 128
            draw_window(img, cx - 62, cy - 78, cx + 62, cy + 62, styles[k], seed=k, frame='#fbf7ee', glass='#3e6f9e')
            k += 1
    # floor line band
    for r in range(2):
        hline(img, r * 256 + 236, 0, S, '#dcc8a0', 6)
    return img


def windows_b():
    """Red brick with 2x2 tall windows, white lintels (tile = 6 m x 6.4 m)."""
    img = wall_brick(12, '#a94a36', '#cdbfa8')
    styles = [3, 0, 1, 0]
    k = 0
    for r in range(2):
        for c in range(2):
            cx, cy = c * 256 + 128, r * 256 + 124
            # lintel
            rect(img, cx - 78, cy - 104, cx + 78, cy - 90, '#e5ded0', jitter=1, seed=k)
            draw_window(img, cx - 56, cy - 84, cx + 56, cy + 76, styles[k], seed=k + 10, frame='#f0ebe0', glass='#2f5b7f')
            k += 1
    return img


def windows_glass():
    """Curtain wall: 2x2 blue-teal panes per tile (tile = 3 m x 3.2 m)."""
    img = canvas('#1e2a33')
    for r in range(2):
        for c in range(2):
            x0, y0 = c * 256 + 8, r * 256 + 8
            x1, y1 = x0 + 240, y0 + 240
            g = col('#4aa0c8') if (r + c) % 2 == 0 else col('#3d8fb8')
            rect(img, x0, y0, x1, y1, g)
            for y in range(y0, y1):
                t = (y - y0) / 240
                img[y, x0:x1] *= (1.15 - t * 0.35)
                xa = int(x0 + 240 * (0.7 - t * 0.6))
                xb = xa + 50
                xs = np.arange(max(x0, xa), min(x1, xb))
                img[y, xs] = img[y, xs] * 1.25 + 30
            # spandrel strip (opaque band) at bottom of each pane
            rect(img, x0, y1 - 48, x1, y1, '#22343f')
            hline(img, y1 - 48, x0, x1, '#8fb4c4', 2)
    img = painterly(img, 13, blotch=0.04, grain=0.02, cells=4)
    return img


def windows_deco():
    """Art deco: salmon plaster, tall narrow windows with fins, gold trim (tile 6 x 6.4 m)."""
    img = wall_stucco(14, '#e9b89a')
    # vertical fins
    for x in (40, 236, 296, 492):
        vline(img, x, 0, S, '#f6dcc7', 10)
        vline(img, x + 10, 0, S, '#b7846a', 4)
    for r in range(2):
        for c in range(2):
            cx, cy = c * 256 + 128 + 10, r * 256 + 128
            draw_window(img, cx - 30, cy - 92, cx + 30, cy + 80, [0, 3, 1, 0][r * 2 + c], seed=r * 2 + c + 20,
                        frame='#3b3a45', glass='#4c7d9c', sill=False)
            draw_window(img, cx - 90, cy - 92, cx - 46, cy + 80, 0, seed=r * 2 + c + 30, frame='#3b3a45', glass='#4c7d9c', sill=False)
            draw_window(img, cx + 46, cy - 92, cx + 90, cy + 80, 0, seed=r * 2 + c + 40, frame='#3b3a45', glass='#4c7d9c', sill=False)
            # gold chevron band above window
            rect(img, cx - 96, cy - 118, cx + 96, cy - 104, '#d9a441', jitter=1, seed=r + c)
            for k in range(-90, 96, 24):
                rect(img, cx + k, cy - 116, cx + k + 8, cy - 106, '#8a5f1d')
    return img


def stucco():
    return wall_stucco(21, '#e8d7b3')


def brick():
    return wall_brick(22)


def asphalt(seed=31, base='#3d3d42'):
    img = canvas(base)
    img = painterly(img, seed, blotch=0.10, grain=0.08, cells=6)
    rng = np.random.default_rng(seed)
    # aggregate speckles
    ys, xs = rng.integers(0, S, (2, 2500))
    img[ys, xs] *= rng.uniform(0.7, 1.5, 2500)[:, None]
    # a couple of patches / cracks
    for _ in range(5):
        x, y = rng.integers(0, S, 2)
        for k in range(rng.integers(40, 120)):
            img[(y + k) % S, (x + int(6 * math.sin(k * 0.15))) % S] *= 0.75
    return img


def road_straight():
    """10 m tile, road runs along the V axis (Z in the model). Yellow dashed
    centre line + white edge lines."""
    img = asphalt(32)
    # dashes: 3 m dash / 2 m gap -> 2 per tile
    for y0 in (26, 282):
        rect(img, 248, y0, 264, y0 + 154, '#e0b52e', jitter=1, seed=y0)
    # edge lines 0.5 m in from the edge
    rect(img, 22, 0, 30, S, '#dcdcd4', jitter=1, seed=1)
    rect(img, 482, 0, 490, S, '#dcdcd4', jitter=1, seed=2)
    img = painterly(img, 33, blotch=0.05, grain=0.03, cells=4)
    return img


def road_cross():
    """10 m intersection tile: zebra crosswalk on all four sides."""
    img = asphalt(34)
    stripe = '#e6e6df'
    # bands 1.4 m..2.6 m from each edge (px 72..134)
    for k in range(146, 372, 42):
        rect(img, k, 72, k + 22, 134, stripe, jitter=1, seed=k)          # top band, stripes run along V
        rect(img, k, S - 134, k + 22, S - 72, stripe, jitter=1, seed=k + 1)
        rect(img, 72, k, 134, k + 22, stripe, jitter=1, seed=k + 2)      # left band
        rect(img, S - 134, k, S - 72, k + 22, stripe, jitter=1, seed=k + 3)
    # stop lines (one lane each side)
    rect(img, 140, 140, 250, 148, stripe)
    rect(img, 262, S - 148, 372, S - 140, stripe)
    rect(img, 140, 262, 148, 372, stripe)
    rect(img, S - 148, 140, S - 140, 250, stripe)
    img = painterly(img, 35, blotch=0.05, grain=0.03, cells=4)
    return img


def concrete():
    """Sidewalk slab: light warm grey with a seam along each tile edge (tile = 2.5 m)."""
    img = canvas('#bdb7aa')
    img = painterly(img, 41, blotch=0.07, grain=0.05, cells=4)
    rng = np.random.default_rng(41)
    ys, xs = rng.integers(0, S, (2, 1500))
    img[ys, xs] *= rng.uniform(0.85, 1.2, 1500)[:, None]
    # seam lines at the tile border (wraps)
    rect(img, 0, 0, S, 6, '#8e887c', jitter=1, seed=3)
    rect(img, 0, 0, 6, S, '#8e887c', jitter=1, seed=4)
    rect(img, 0, 6, S, 9, '#d3cdc0')
    rect(img, 6, 0, 9, S, '#d3cdc0')
    return img


def awning_stripes():
    img = canvas('#f4efe2')
    for k in range(0, S, 128):
        rect(img, k, 0, k + 64, S, '#d63b2f', jitter=2, seed=k)
    img = painterly(img, 51, blotch=0.05, grain=0.04, cells=3)
    return img


def wood():
    img = canvas('#b9803f')
    img = painterly(img, 61, blotch=0.10, grain=0.04, cells=2)
    # grain streaks
    n = value_noise(S, 1, 62, 4)
    stripes = (np.sin((np.arange(S)[None, :] * 0.0 + np.arange(S)[:, None]) * 0.25 + n * 9) * 0.5 + 0.5)
    img *= (0.88 + 0.16 * stripes)[..., None]
    # plank seams: 4 planks per tile
    for k in range(0, S, 128):
        rect(img, 0, k, S, k + 4, '#6d4520', jitter=1, seed=k)
        rect(img, 0, k + 4, S, k + 6, '#d8a468')
    return img


def checker_floor():
    img = canvas('#f2ede0')
    for r in range(4):
        for c in range(4):
            if (r + c) % 2:
                rect(img, c * 128, r * 128, c * 128 + 128, r * 128 + 128, '#2e2b30', jitter=1, seed=r * 4 + c)
    img = painterly(img, 71, blotch=0.06, grain=0.03, cells=3)
    return img


def grass():
    img = canvas('#6fae3c')
    img = painterly(img, 81, blotch=0.14, grain=0.06, cells=5)
    rng = np.random.default_rng(81)
    for _ in range(900):
        x, y = rng.integers(0, S, 2)
        h = rng.integers(3, 9)
        c = col('#8fd04d') if rng.random() < 0.6 else col('#4e8a2a')
        for k in range(h):
            img[(y - k) % S, x] = c
    return img


def foil():
    img = canvas('#c9ccd2')
    n = value_noise(S, 12, 91, 3)
    img *= (0.7 + 0.6 * n)[..., None]
    # crease highlights
    rng = np.random.default_rng(92)
    for _ in range(60):
        x, y = rng.integers(0, S, 2)
        dx, dy = rng.uniform(-1, 1, 2)
        for k in range(rng.integers(20, 80)):
            img[int(y + dy * k) % S, int(x + dx * k) % S] = col('#f2f4f8')
    img = painterly(img, 93, blotch=0.05, grain=0.05, cells=6)
    return img


def sign_blank():
    """White board with a subtle painted edge, used for signs/billboards (256px)."""
    img = canvas('#f7f3ea', 256)
    img = painterly(img, 101, blotch=0.03, grain=0.03, cells=2)
    return img


def metal():
    img = canvas('#9aa0a6')
    img = painterly(img, 111, blotch=0.08, grain=0.05, cells=5)
    for k in range(0, S, 64):
        rect(img, 0, k, S, k + 3, '#6e747a')
    return img


TEXTURES = {
    'windows_a.png': windows_a,
    'windows_b.png': windows_b,
    'windows_glass.png': windows_glass,
    'windows_deco.png': windows_deco,
    'brick.png': brick,
    'stucco.png': stucco,
    'asphalt.png': asphalt,
    'road_straight.png': road_straight,
    'road_cross.png': road_cross,
    'concrete.png': concrete,
    'awning_stripes.png': awning_stripes,
    'wood.png': wood,
    'checker_floor.png': checker_floor,
    'grass.png': grass,
    'foil.png': foil,
    'sign_blank.png': sign_blank,
    'metal.png': metal,
}


def main():
    print('gen_textures ->', OUT)
    for name, fn in TEXTURES.items():
        save(name, fn())


if __name__ == '__main__':
    main()
