"""
glb.py - tiny GLB 2.0 writer + flat-shaded geometry helpers.

Only depends on numpy.  Everything is built as a *triangle soup*: every
primitive returns a `Geo` (a list of (Material, tris[N,3,3], uvs[N,3,2])
chunks).  Vertices are never shared between faces, so every face gets its
own normal at write time -> flat shading for free.

Conventions (match glTF / Godot): right-handed, Y up, metres, CCW front faces.
Colours are given in sRGB (0..1 or '#rrggbb') and converted to linear for the
glTF baseColorFactor (Godot converts them back, so what you write is what you
see).
"""
import json
import math
import os
import struct

import numpy as np

# --------------------------------------------------------------------------
# colours / materials
# --------------------------------------------------------------------------


def srgb_to_linear(c):
    c = float(c)
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def parse_color(c):
    """'#rrggbb', (r,g,b) in 0..1 or 0..255 -> (r,g,b) floats 0..1 (sRGB)."""
    if isinstance(c, str):
        c = c.lstrip('#')
        return tuple(int(c[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    c = tuple(float(x) for x in c)
    if max(c) > 1.0:
        c = tuple(x / 255.0 for x in c)
    return c[:3]


def shade(c, k):
    """Multiply an sRGB colour by k (k<1 darker, k>1 lighter), clamped."""
    r, g, b = parse_color(c)
    return (min(1.0, r * k), min(1.0, g * k), min(1.0, b * k))


class Material:
    _counter = 0

    def __init__(self, name=None, color=(1, 1, 1), texture=None, roughness=0.9,
                 metallic=0.0, double_sided=False, alpha=1.0, emissive=None,
                 unlit=False):
        Material._counter += 1
        self.name = name or 'mat%d' % Material._counter
        self.color = parse_color(color)
        self.texture = texture          # png file name inside assets/textures
        self.roughness = roughness
        self.metallic = metallic
        self.double_sided = double_sided
        self.alpha = alpha
        self.emissive = parse_color(emissive) if emissive is not None else None
        self.unlit = unlit

    def gltf(self, texture_index):
        pbr = {
            'baseColorFactor': [srgb_to_linear(self.color[0]), srgb_to_linear(self.color[1]),
                                srgb_to_linear(self.color[2]), float(self.alpha)],
            'metallicFactor': float(self.metallic),
            'roughnessFactor': float(self.roughness),
        }
        if texture_index is not None:
            pbr['baseColorTexture'] = {'index': texture_index, 'texCoord': 0}
        m = {'name': self.name, 'pbrMetallicRoughness': pbr, 'doubleSided': bool(self.double_sided)}
        if self.alpha < 1.0:
            m['alphaMode'] = 'BLEND'
        if self.emissive is not None:
            m['emissiveFactor'] = [srgb_to_linear(x) for x in self.emissive]
        if self.unlit:
            m['extensions'] = {'KHR_materials_unlit': {}}
        return m


# --------------------------------------------------------------------------
# Geo container
# --------------------------------------------------------------------------


class Geo:
    """Triangle soup grouped by material. Immutable-style: ops return new Geo."""

    def __init__(self, items=None):
        self.items = list(items) if items else []

    # -- building -----------------------------------------------------------
    def add(self, mat, tris, uvs=None):
        tris = np.asarray(tris, dtype=np.float64).reshape(-1, 3, 3)
        if len(tris) == 0:
            return self
        if uvs is None:
            uvs = np.zeros((len(tris), 3, 2))
        uvs = np.asarray(uvs, dtype=np.float64).reshape(-1, 3, 2)
        self.items.append((mat, tris, uvs))
        return self

    def extend(self, *others):
        for o in others:
            self.items.extend(o.items)
        return self

    def __add__(self, other):
        return Geo(self.items + other.items)

    def __iadd__(self, other):
        self.items.extend(other.items)
        return self

    # -- queries ------------------------------------------------------------
    def tri_count(self):
        return sum(len(t) for _, t, _ in self.items)

    def bounds(self):
        if not self.items:
            return np.zeros(3), np.zeros(3)
        allp = np.concatenate([t.reshape(-1, 3) for _, t, _ in self.items])
        return allp.min(axis=0), allp.max(axis=0)

    # -- transforms ---------------------------------------------------------
    def transform(self, M):
        M = np.asarray(M, dtype=np.float64)
        R, T = M[:3, :3], M[:3, 3]
        flip = np.linalg.det(R) < 0
        out = Geo()
        for mat, tris, uvs in self.items:
            p = tris.reshape(-1, 3) @ R.T + T
            t = p.reshape(-1, 3, 3)
            u = uvs
            if flip:
                t = t[:, ::-1, :]
                u = u[:, ::-1, :]
            out.items.append((mat, t, u))
        return out

    def translate(self, x=0.0, y=0.0, z=0.0):
        if not np.isscalar(x):
            x, y, z = x
        M = np.eye(4)
        M[:3, 3] = (x, y, z)
        return self.transform(M)

    def scale(self, sx, sy=None, sz=None):
        if sy is None:
            sy = sz = sx
        M = np.diag([sx, sy, sz, 1.0])
        return self.transform(M)

    def rotate_x(self, deg):
        a = math.radians(deg)
        c, s = math.cos(a), math.sin(a)
        return self.transform([[1, 0, 0, 0], [0, c, -s, 0], [0, s, c, 0], [0, 0, 0, 1]])

    def rotate_y(self, deg):
        a = math.radians(deg)
        c, s = math.cos(a), math.sin(a)
        return self.transform([[c, 0, s, 0], [0, 1, 0, 0], [-s, 0, c, 0], [0, 0, 0, 1]])

    def rotate_z(self, deg):
        a = math.radians(deg)
        c, s = math.cos(a), math.sin(a)
        return self.transform([[c, -s, 0, 0], [s, c, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]])

    def flip(self):
        """Reverse winding (turn a shape inside-out)."""
        return Geo([(m, t[:, ::-1, :], u[:, ::-1, :]) for m, t, u in self.items])

    def with_material(self, mat):
        return Geo([(mat, t, u) for _, t, u in self.items])

    def jitter(self, amount, seed=0):
        """Random per-vertex displacement (hand-made lumpy look). Faces stay
        disconnected so this tears seams; use on chunky blobs only."""
        rng = np.random.default_rng(abs(int(seed)))
        out = Geo()
        for mat, tris, uvs in self.items:
            flat = tris.reshape(-1, 3)
            # jitter must be consistent per unique vertex position
            keys = np.round(flat, 5)
            uniq, inv = np.unique(keys, axis=0, return_inverse=True)
            d = rng.uniform(-amount, amount, size=uniq.shape)
            out.items.append((mat, (flat + d[inv.reshape(-1)]).reshape(-1, 3, 3), uvs))
        return out


def merge(*geos):
    g = Geo()
    for x in geos:
        g.extend(x)
    return g


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------


def _face_uv(p, axis_u, axis_v, su, sv):
    """planar UV: u = p[axis_u]/su, v = -p[axis_v]/sv (so +v axis goes UP the image)."""
    return np.stack([p[..., axis_u] / su, -p[..., axis_v] / sv], axis=-1)


def quad(mat, p0, p1, p2, p3, uvs=None):
    """Quad given CCW (front = towards the viewer when CCW)."""
    p0, p1, p2, p3 = (np.asarray(p, dtype=np.float64) for p in (p0, p1, p2, p3))
    tris = np.array([[p0, p1, p2], [p0, p2, p3]])
    if uvs is None:
        u = np.array([[0, 1], [1, 1], [1, 0], [0, 0]], dtype=np.float64)
    else:
        u = np.asarray(uvs, dtype=np.float64)
    uv = np.array([[u[0], u[1], u[2]], [u[0], u[2], u[3]]])
    return Geo().add(mat, tris, uv)


_BOX_FACES = {
    # name: (normal axis, sign, corner order CCW seen from outside) using unit cube coords
    '+x': (0, 1, [(1, 0, 1), (1, 0, 0), (1, 1, 0), (1, 1, 1)]),
    '-x': (0, -1, [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
    '+y': (1, 1, [(0, 1, 1), (1, 1, 1), (1, 1, 0), (0, 1, 0)]),
    '-y': (1, -1, [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
    '+z': (2, 1, [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
    '-z': (2, -1, [(1, 0, 0), (0, 0, 0), (0, 1, 0), (1, 1, 0)]),
}


def box(mat, size=(1, 1, 1), center=(0, 0, 0), mats=None, uv_scale=None, faces=None, uv_offset=(0.0, 0.0)):
    """Axis-aligned box. `mats` = {'+x': Material, '+y': ...} overrides per face.
    uv_scale = (su, sv) metres per texture tile using absolute coordinates
    (so tiles line up across separate boxes); None = 0..1 per face.
    `faces` = subset of face names to emit."""
    size = np.asarray(size, dtype=np.float64)
    center = np.asarray(center, dtype=np.float64)
    lo = center - size / 2
    g = Geo()
    mats = mats or {}
    for name, (axis, sign, corners) in _BOX_FACES.items():
        if faces is not None and name not in faces:
            continue
        m = mats.get(name, mat)
        if m is None:
            continue
        pts = np.array([lo + size * np.array(c) for c in corners])
        if uv_scale is None:
            uv = None
        else:
            su, sv = uv_scale
            if axis == 1:   # top/bottom: u=x, v=z
                uv = _face_uv(pts, 0, 2, su, sv)
            elif axis == 0:  # +-x faces: u = z (flipped so texture reads left->right from outside)
                uv = np.stack([pts[:, 2] / su * (-sign), -pts[:, 1] / sv], axis=-1)
            else:            # +-z faces: u = x
                uv = np.stack([pts[:, 0] / su * sign, -pts[:, 1] / sv], axis=-1)
            uv = uv + np.asarray(uv_offset)
        g += quad(m, *pts, uvs=uv)
    return g


def _normalize_poly(pts):
    """Return pts as (N,2) array ordered with positive shoelace area in (x,z)."""
    pts = np.asarray(pts, dtype=np.float64)
    x, z = pts[:, 0], pts[:, 1]
    area = 0.5 * np.sum(x * np.roll(z, -1) - np.roll(x, -1) * z)
    if area < 0:
        pts = pts[::-1]
    return pts


def triangulate(pts):
    """Ear-clipping triangulation of a simple polygon (N,2) with positive area.
    Returns list of index triples (in the polygon's order)."""
    pts = np.asarray(pts, dtype=np.float64)
    n = len(pts)
    idx = list(range(n))
    tris = []

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    def inside(p, a, b, c):
        return cross(a, b, p) >= -1e-12 and cross(b, c, p) >= -1e-12 and cross(c, a, p) >= -1e-12

    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        found = False
        for i in range(len(idx)):
            i0, i1, i2 = idx[i - 1], idx[i], idx[(i + 1) % len(idx)]
            a, b, c = pts[i0], pts[i1], pts[i2]
            if cross(a, b, c) <= 1e-12:
                continue
            ok = True
            for j in idx:
                if j in (i0, i1, i2):
                    continue
                if inside(pts[j], a, b, c):
                    ok = False
                    break
            if ok:
                tris.append((i0, i1, i2))
                idx.pop(i)
                found = True
                break
        if not found:  # degenerate; fan the rest
            for i in range(1, len(idx) - 1):
                tris.append((idx[0], idx[i], idx[i + 1]))
            idx = idx[:3]
            break
    if len(idx) == 3:
        tris.append(tuple(idx))
    return tris


def extrude(mat, pts, height, y0=0.0, mat_top=None, mat_bottom=None, cap_top=True,
            cap_bottom=True, uv_scale=1.0, side_mats=None):
    """Extrude polygon pts=[(x,z),...] from y0 to y0+height (+Y). Outward normals.
    side_mats: optional list of materials per edge (edge i = pts[i]->pts[i+1])."""
    pts = _normalize_poly(pts)
    n = len(pts)
    g = Geo()
    y1 = y0 + height
    cap = triangulate(pts)
    P0 = np.array([[p[0], y0, p[1]] for p in pts])
    P1 = np.array([[p[0], y1, p[1]] for p in pts])
    # positive shoelace in (x,z) -> the loop is CW when seen from +Y, so the
    # bottom cap (seen from -Y) is CCW as-is, and the top cap needs reversing.
    if cap_bottom:
        t = np.array([[P0[a], P0[b], P0[c]] for a, b, c in cap])
        uv = np.stack([t[..., 0] / uv_scale, -t[..., 2] / uv_scale], axis=-1)
        g.add(mat_bottom or mat, t, uv)
    if cap_top:
        t = np.array([[P1[a], P1[c], P1[b]] for a, b, c in cap])
        uv = np.stack([t[..., 0] / uv_scale, -t[..., 2] / uv_scale], axis=-1)
        g.add(mat_top or mat, t, uv)
    u = 0.0
    for i in range(n):
        j = (i + 1) % n
        a0, b0, a1, b1 = P0[i], P0[j], P1[i], P1[j]
        seg = float(np.linalg.norm(b0 - a0))
        m = side_mats[i] if side_mats else mat
        uvq = [[u / uv_scale, -y0 / uv_scale], [(u + seg) / uv_scale, -y0 / uv_scale],
               [(u + seg) / uv_scale, -y1 / uv_scale], [u / uv_scale, -y1 / uv_scale]]
        # walking i->j with the loop CW-from-above means the outside is on the
        # right hand side: quad (b0, a0, a1, b1) is CCW from outside.
        g += quad(m, b0, a0, a1, b1, uvs=[uvq[1], uvq[0], uvq[3], uvq[2]])
        u += seg
    return g


def lathe(mat, profile, segments=12, angle=360.0, uv_scale=None, cap_mats=None):
    """Revolve profile=[(r,y),...] around +Y. Walk the profile so the outside of
    the surface is on your RIGHT when r points right and y up (e.g. a sphere
    profile goes bottom -> top around the outside). Zero-radius points make
    degenerate tris which are dropped."""
    prof = np.asarray(profile, dtype=np.float64)
    n = len(prof)
    g = Geo()
    tris = []
    uvs = []
    ang = [math.radians(angle) * k / segments for k in range(segments + 1)]
    ca = np.cos(ang)
    sa = np.sin(ang)
    # v coordinate along the profile by arc length
    d = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(prof, axis=0), axis=1))])
    total = d[-1] if d[-1] > 0 else 1.0
    for i in range(n - 1):
        (r0, y0), (r1, y1) = prof[i], prof[i + 1]
        v0, v1 = d[i] / total, d[i + 1] / total
        for k in range(segments):
            # points: x = r cos, z = -r sin  (angle increasing = CCW seen from +Y)
            a = (r0 * ca[k], y0, -r0 * sa[k])
            b = (r0 * ca[k + 1], y0, -r0 * sa[k + 1])
            c = (r1 * ca[k + 1], y1, -r1 * sa[k + 1])
            e = (r1 * ca[k], y1, -r1 * sa[k])
            u0, u1 = k / segments, (k + 1) / segments
            # outward = (dy, -dr) rule. quad (a,b,c,e) is CCW seen from outside.
            if r0 > 1e-9:
                tris.append([a, b, c]); uvs.append([[u0, v0], [u1, v0], [u1, v1]])
            if r1 > 1e-9:
                tris.append([a, c, e]); uvs.append([[u0, v0], [u1, v1], [u0, v1]])
    g.add(mat, np.array(tris), np.array(uvs))
    return g


def cylinder(mat, r, h, segments=12, r_top=None, y0=0.0, mat_top=None, mat_bottom=None,
             cap_top=True, cap_bottom=True):
    """Cylinder / frustum from y0 to y0+h. Caps are fans (flat)."""
    if r_top is None:
        r_top = r
    g = lathe(mat, [(r, y0), (r_top, y0 + h)], segments)
    if cap_bottom and r > 0:
        g += lathe(mat_bottom or mat, [(0, y0), (r, y0)], segments)
    if cap_top and r_top > 0:
        g += lathe(mat_top or mat, [(r_top, y0 + h), (0, y0 + h)], segments)
    return g


def cone(mat, r, h, segments=12, y0=0.0):
    return cylinder(mat, r, h, segments, r_top=0.0, y0=y0, cap_top=False)


def sphere(mat, r, segments=8, rings=6, center=(0, 0, 0)):
    prof = [(r * math.sin(math.pi * i / rings), -r * math.cos(math.pi * i / rings)) for i in range(rings + 1)]
    return lathe(mat, prof, segments).translate(*center)


def ellipsoid(mat, rx, ry, rz, segments=8, rings=6, center=(0, 0, 0)):
    return sphere(mat, 1.0, segments, rings).scale(rx, ry, rz).translate(*center)


def torus(mat, R, r, segments=12, rings=8, center=(0, 0, 0)):
    prof = [(R + r * math.cos(2 * math.pi * i / rings), r * math.sin(2 * math.pi * i / rings)) for i in range(rings + 1)]
    return lathe(mat, prof, segments).translate(*center)


def disc(mat, r, segments=12, y=0.0, up=True):
    g = lathe(mat, [(r, y), (0, y)], segments)
    return g if up else g.flip()


def tube(mat, path, radius, segments=6, radii=None, cap=True):
    """Sweep a circle along a 3D polyline (list of points) -> tube.
    radii: optional per-point radius list."""
    P = np.asarray(path, dtype=np.float64)
    n = len(P)
    if radii is None:
        radii = [radius] * n
    # tangents
    T = np.zeros_like(P)
    T[1:-1] = P[2:] - P[:-2]
    T[0] = P[1] - P[0]
    T[-1] = P[-1] - P[-2]
    T /= np.linalg.norm(T, axis=1)[:, None] + 1e-12
    # parallel transport frame
    up = np.array([0, 1, 0.0]) if abs(T[0][1]) < 0.9 else np.array([1.0, 0, 0])
    N = np.cross(T[0], up); N /= np.linalg.norm(N)
    rings = []
    for i in range(n):
        if i > 0:
            N = N - T[i] * np.dot(N, T[i])
            N /= np.linalg.norm(N) + 1e-12
        B = np.cross(T[i], N)
        ring = [P[i] + radii[i] * (math.cos(2 * math.pi * k / segments) * N + math.sin(2 * math.pi * k / segments) * B)
                for k in range(segments)]
        rings.append(ring)
    g = Geo()
    tris, uvs = [], []
    for i in range(n - 1):
        for k in range(segments):
            k2 = (k + 1) % segments
            a, b = rings[i][k], rings[i][k2]
            c, d = rings[i + 1][k2], rings[i + 1][k]
            tris.append([a, b, c]); tris.append([a, c, d])
            uvs.append([[0, 0], [1, 0], [1, 1]]); uvs.append([[0, 0], [1, 1], [0, 1]])
    g.add(mat, np.array(tris), np.array(uvs))
    # orientation check: make sure the tube is outward-facing
    t0 = np.array(tris[0])
    nrm = np.cross(t0[1] - t0[0], t0[2] - t0[0])
    if np.dot(nrm, t0.mean(axis=0) - P[0]) < 0:
        g = g.flip()
    if cap:
        for i, sgn in ((0, -1), (n - 1, 1)):
            ring = rings[i]
            ctr = P[i]
            ct = []
            for k in range(segments):
                k2 = (k + 1) % segments
                ct.append([ctr, ring[k], ring[k2]] if sgn > 0 else [ctr, ring[k2], ring[k]])
            cg = Geo().add(mat, np.array(ct))
            c0 = np.array(ct[0])
            nrm = np.cross(c0[1] - c0[0], c0[2] - c0[0])
            if np.dot(nrm, T[i] * sgn) < 0:
                cg = cg.flip()
            g += cg
    return g


def wavy_polygon(r, n, waves, amp, phase=0.0):
    """2D star-ish outline: radius r + amp*sin(waves*theta). Returns [(x,z)]."""
    return [((r + amp * math.sin(waves * 2 * math.pi * i / n + phase)) * math.cos(2 * math.pi * i / n),
             (r + amp * math.sin(waves * 2 * math.pi * i / n + phase)) * math.sin(2 * math.pi * i / n))
            for i in range(n)]


def rounded_rect(w, d, radius, corner_segs=3):
    """2D rounded rectangle outline centred at origin -> [(x,z)]."""
    pts = []
    hw, hd = w / 2 - radius, d / 2 - radius
    for cx, cz, a0 in ((hw, hd, 0), (-hw, hd, 90), (-hw, -hd, 180), (hw, -hd, 270)):
        for k in range(corner_segs + 1):
            a = math.radians(a0 + 90 * k / corner_segs)
            pts.append((cx + radius * math.cos(a), cz + radius * math.sin(a)))
    return pts


def circle(r, n, cx=0.0, cz=0.0):
    return [(cx + r * math.cos(2 * math.pi * i / n), cz + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


# --------------------------------------------------------------------------
# writer
# --------------------------------------------------------------------------


def _pad4(b, fill=b'\x00'):
    return b + fill * ((4 - len(b) % 4) % 4)


def write_glb(path, geo, name=None, texture_uri_prefix='../textures/'):
    """Write geo to a .glb. One node, one mesh, one primitive per material.
    Textures are referenced by relative URI (textures live next door)."""
    name = name or os.path.splitext(os.path.basename(path))[0]
    # group by material (keeping first-seen order)
    groups = {}
    order = []
    for mat, tris, uvs in geo.items:
        if id(mat) not in groups:
            groups[id(mat)] = (mat, [], [])
            order.append(id(mat))
        groups[id(mat)][1].append(tris)
        groups[id(mat)][2].append(uvs)

    bin_parts = []
    buffer_views = []
    accessors = []
    materials = []
    images, textures, samplers = [], [], []
    tex_index = {}
    primitives = []
    offset = 0

    def add_view(data, target):
        nonlocal offset
        data = _pad4(data)
        buffer_views.append({'buffer': 0, 'byteOffset': offset, 'byteLength': len(data), 'target': target})
        bin_parts.append(data)
        offset += len(data)
        return len(buffer_views) - 1

    for key in order:
        mat, tl, ul = groups[key]
        tris = np.concatenate(tl)
        uvs = np.concatenate(ul)
        # drop degenerate triangles
        e1 = tris[:, 1] - tris[:, 0]
        e2 = tris[:, 2] - tris[:, 0]
        nrm = np.cross(e1, e2)
        ln = np.linalg.norm(nrm, axis=1)
        keep = ln > 1e-12
        tris, uvs, nrm, ln = tris[keep], uvs[keep], nrm[keep], ln[keep]
        if len(tris) == 0:
            continue
        nrm = nrm / ln[:, None]
        pos = tris.reshape(-1, 3).astype(np.float32)
        nor = np.repeat(nrm, 3, axis=0).astype(np.float32)
        uv = uvs.reshape(-1, 2).astype(np.float32)
        nv = len(pos)
        if nv > 65535:
            idx = np.arange(nv, dtype=np.uint32); ctype = 5125
        else:
            idx = np.arange(nv, dtype=np.uint16); ctype = 5123

        v = add_view(pos.tobytes(), 34962)
        accessors.append({'bufferView': v, 'componentType': 5126, 'count': nv, 'type': 'VEC3',
                          'min': [float(x) for x in pos.min(axis=0)], 'max': [float(x) for x in pos.max(axis=0)]})
        a_pos = len(accessors) - 1
        v = add_view(nor.tobytes(), 34962)
        accessors.append({'bufferView': v, 'componentType': 5126, 'count': nv, 'type': 'VEC3'})
        a_nor = len(accessors) - 1
        v = add_view(uv.tobytes(), 34962)
        accessors.append({'bufferView': v, 'componentType': 5126, 'count': nv, 'type': 'VEC2'})
        a_uv = len(accessors) - 1
        v = add_view(idx.tobytes(), 34963)
        accessors.append({'bufferView': v, 'componentType': ctype, 'count': nv, 'type': 'SCALAR'})
        a_idx = len(accessors) - 1

        ti = None
        if mat.texture:
            if mat.texture not in tex_index:
                if not samplers:
                    samplers.append({'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497})
                images.append({'uri': texture_uri_prefix + mat.texture,
                               'name': os.path.splitext(mat.texture)[0]})
                textures.append({'sampler': 0, 'source': len(images) - 1, 'name': os.path.splitext(mat.texture)[0]})
                tex_index[mat.texture] = len(textures) - 1
            ti = tex_index[mat.texture]
        materials.append(mat.gltf(ti))
        primitives.append({'attributes': {'POSITION': a_pos, 'NORMAL': a_nor, 'TEXCOORD_0': a_uv},
                           'indices': a_idx, 'material': len(materials) - 1, 'mode': 4})

    binary = b''.join(bin_parts)
    doc = {
        'asset': {'version': '2.0', 'generator': 'man_v_man_v_food gen_assets'},
        'scene': 0,
        'scenes': [{'name': name, 'nodes': [0]}],
        'nodes': [{'name': name, 'mesh': 0}],
        'meshes': [{'name': name, 'primitives': primitives}],
        'materials': materials,
        'accessors': accessors,
        'bufferViews': buffer_views,
        'buffers': [{'byteLength': len(binary)}],
    }
    if images:
        doc['images'] = images
        doc['textures'] = textures
        doc['samplers'] = samplers
    if any(m.unlit for m, _, _ in geo.items):
        doc['extensionsUsed'] = ['KHR_materials_unlit']
    js = _pad4(json.dumps(doc, separators=(',', ':')).encode('utf-8'), b' ')
    total = 12 + 8 + len(js) + 8 + len(binary)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack('<II', len(binary), 0x004E4942))
        f.write(binary)
    return geo.tri_count()
