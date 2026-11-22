"""Renders the photo-style day / night scenery used on the Home sun card.
Usage: python3 tools/gen_scene.py   (needs Pillow + numpy; writes assets/scene/*.jpg)"""
import math, random, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H, S = 2300, 1000, 2          # final size and supersampling factor
SW, SH = W * S, H * S
HORIZON = 0.575                  # fraction of height where meadow starts


def fbm(w, h, octaves=6, base=4, seed=0, persistence=.55):
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        n = base * (2 ** o)
        g = rng.random((max(2, int(n * h / w) + 2), n + 2)).astype(np.float32)
        im = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        out += np.asarray(im, np.float32) / 255 * amp
        tot += amp
        amp *= persistence
    return out / tot


def vgrad(h, stops):
    """stops: [(pos 0..1, (r,g,b))] -> (h,1,3) float array"""
    ys = np.linspace(0, 1, h)
    cols = np.zeros((h, 3), np.float32)
    ps = [p for p, _ in stops]
    for c in range(3):
        cols[:, c] = np.interp(ys, ps, [s[1][c] for s in stops])
    return cols[:, None, :]


def hexc(s):
    s = s.lstrip('#')
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def homography(src, dst):
    A, b = [], []
    for (x, y), (u, v) in zip(src, dst):
        A.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); b.append(u)
        A.append([0, 0, 0, x, y, 1, -v * x, -v * y]); b.append(v)
    return np.linalg.solve(np.array(A, float), np.array(b, float))


def warp(img, quad_dst, size):
    """Map the flat image (w,h) corners TL,TR,BR,BL onto quad_dst in a canvas of `size`."""
    w, h = img.size
    src = [(0, 0), (w, 0), (w, h), (0, h)]
    coeffs = homography(quad_dst, src)      # output -> input
    return img.transform(size, Image.PERSPECTIVE, tuple(coeffs), Image.BICUBIC)


def module_tex(night, rng, mw=720, mh=430):
    """One photovoltaic module seen flat: aluminium frame, glass, cells, busbars."""
    base_top = np.array(hexc('#1c3f9e' if not night else '#1a2f6e'), np.float32)
    base_bot = np.array(hexc('#0a1c5c' if not night else '#0a1540'), np.float32)
    img = np.zeros((mh, mw, 3), np.float32)
    fr = int(mw * .028)
    # frame
    fy = np.linspace(0, 1, mh)[:, None, None]
    frame_col = np.array(hexc('#d9e0ea' if not night else '#8c97ad'), np.float32)
    img[:] = frame_col * (.93 + .07 * (1 - fy))
    # inner glass
    gx0, gx1, gy0, gy1 = fr, mw - fr, fr, mh - fr
    cols, rows = 12, 6
    cw, ch = (gx1 - gx0) / cols, (gy1 - gy0) / rows
    glass = np.zeros((gy1 - gy0, gx1 - gx0, 3), np.float32)
    for r in range(rows):
        for c in range(cols):
            x0, x1 = int(c * cw), int((c + 1) * cw)
            y0, y1 = int(r * ch), int((r + 1) * ch)
            t = (r + 1) / (rows + 1)
            colr = base_top * (1 - t) + base_bot * t
            colr = colr * (.88 + .24 * rng.random())          # per-cell tone variation (poly look)
            colr = colr + np.array([0, 0, 10 * rng.random()])
            glass[y0:y1, x0:x1] = colr
            # cell gap (backsheet)
            glass[y0:y1, x0:x0 + 3] = np.array(hexc('#c9d3e6' if not night else '#52607f'), np.float32) * .75
            glass[y0:y0 + 3, x0:x1] = np.array(hexc('#c9d3e6' if not night else '#52607f'), np.float32) * .75
            # chamfered corners (mono-Si look): darken diagonal
            k = int(cw * .09)
            for d in range(k):
                glass[y0 + d, x0:x0 + max(0, k - d)] = glass[y0 + d, x0 + 4]  # cheap corner cut
            # busbars (3) and fine fingers
            for bb in (.2, .5, .8):
                yy = y0 + int(ch * bb)
                glass[yy:yy + 2, x0 + 3:x1] = np.array([205, 214, 232], np.float32) * (.75 if not night else .45)
            glass[y0 + 2:y1, x0 + 4:x1:5] *= 1.10
    img[gy0:gy1, gx0:gx1] = glass
    # inner frame shadow line
    img[gy0 - 2:gy0, gx0:gx1] *= .55
    img[gy0:gy1, gx0 - 2:gx0] *= .55
    # glass reflection of the sky: diagonal bright sweep + top-left sheen
    yy, xx = np.mgrid[0:mh, 0:mw].astype(np.float32)
    sweep = np.exp(-(((xx / mw) * .9 + (yy / mh) * .5 - .55) ** 2) / .008)
    sheen = np.clip(1 - (xx / mw * .8 + yy / mh * 1.1), 0, 1) ** 2
    refl_col = np.array([200, 225, 255] if not night else [120, 150, 215], np.float32)
    k = (sweep * (.22 if not night else .10) + sheen * (.20 if not night else .08))[..., None]
    img[gy0:gy1, gx0:gx1] = img[gy0:gy1, gx0:gx1] * (1 - k[gy0:gy1, gx0:gx1]) + refl_col * k[gy0:gy1, gx0:gx1]
    # frame bevel lines
    img[:2] *= 1.05; img[-3:] *= .75; img[:, :2] *= 1.05; img[:, -3:] *= .78
    img += rng.normal(0, 2.2, img.shape)
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def render(mode, seed=7):
    night = mode == 'night'
    dusk = mode == 'dusk'
    rng = np.random.default_rng(seed)
    random.seed(seed)
    P = dict(
        sky=[(0, hexc('#1f6fe6')), (.35, hexc('#559ff2')), (.62, hexc('#a6d2f8')), (1, hexc('#e6f3fd'))],
        m1=hexc('#a9c3e0'), m2=hexc('#86a7cf'), m3=hexc('#6f9a74'),
        g_far=hexc('#9fd070'), g_mid=hexc('#6fb844'), g_near=hexc('#4f9a33'),
        blade=[hexc('#3e7d28'), hexc('#5aa238'), hexc('#8cc85a'), hexc('#2f6a22')],
        haze=(225, 238, 252), light=1.0)
    if dusk:
        P.update(
            sky=[(0, hexc('#2c3f8c')), (.40, hexc('#7d6fb0')), (.68, hexc('#f19a62')), (1, hexc('#ffd9a8'))],
            m1=hexc('#b5a0c4'), m2=hexc('#8c7fae'), m3=hexc('#6d7f78'),
            g_far=hexc('#a8b866'), g_mid=hexc('#7fa443'), g_near=hexc('#5a8530'),
            blade=[hexc('#476f26'), hexc('#6f9a36'), hexc('#a9bf5c'), hexc('#3b5f20')],
            haze=(255, 196, 140), light=.8)
    if night:
        P.update(
            sky=[(0, hexc('#030918')), (.55, hexc('#0b1c44')), (1, hexc('#1a3566'))],
            m1=hexc('#18295a'), m2=hexc('#12214b'), m3=hexc('#0d1a3a'),
            g_far=hexc('#1d3a34'), g_mid=hexc('#162e26'), g_near=hexc('#0d1d17'),
            blade=[hexc('#0b1712'), hexc('#1b3a2c'), hexc('#25493b'), hexc('#09120e')],
            haze=(40, 62, 110), light=.35)
    hz = int(SH * HORIZON)

    # ---- sky
    sky = vgrad(hz + 80, [(p, c) for p, c in P['sky']]).repeat(SW, axis=1)
    canvas = np.zeros((SH, SW, 3), np.float32)
    canvas[:hz + 80] = sky
    canvas[hz + 80:] = sky[-1]
    if not night:
        cl = fbm(SW // 4, SH // 4, 6, 3, seed + 1)
        cl = np.asarray(Image.fromarray((cl * 255).astype(np.uint8)).resize((SW, SH), Image.BICUBIC), np.float32) / 255
        yy = np.linspace(0, 1, SH)[:, None]
        mask = np.clip((cl - .56) * 5.0, 0, 1) * np.clip(1 - np.abs(yy - .26) / .26, 0, 1) * .55
        canvas = canvas * (1 - mask[..., None]) + np.array([255, 255, 255]) * mask[..., None]

    def ridge(base, amp, seed_, rough, x0=0):
        n = fbm(SW // 8, 8, 6, 4, seed_, rough)[4]
        xs = np.linspace(0, 1, SW)
        h1 = np.interp(xs, np.linspace(0, 1, len(n)), n)
        return base - (h1 - .5) * amp * 2

    def draw_layer(y_line, color, texture_seed, haze, shade):
        mask = Image.new('L', (SW, SH), 0)
        d = ImageDraw.Draw(mask)
        d.polygon([(0, SH)] + [(x, float(y_line[x])) for x in range(0, SW, 3)] + [(SW, SH)], fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(1.4))
        m = np.asarray(mask, np.float32)[..., None] / 255
        tex = fbm(SW // 3, SH // 3, 6, 6, texture_seed)
        tex = np.asarray(Image.fromarray((tex * 255).astype(np.uint8)).resize((SW, SH), Image.BICUBIC), np.float32) / 255
        col = np.array(color, np.float32)[None, None, :] * (1 + (tex[..., None] - .5) * shade)
        # lit slope: brighter towards the top edge of each ridge
        yy = np.arange(SH)[:, None].astype(np.float32)
        top = y_line[None, :SW].astype(np.float32)
        edge = np.clip(1 - (yy - top) / (SH * .09), 0, 1)[..., None]
        col = col * (1 + .06 * edge * P['light'])
        col = col * (1 - haze) + np.array(P['haze'], np.float32) * haze
        return canvas * (1 - m) + col * m

    canvas = draw_layer(ridge(hz - SH * .17, SH * .13, 11, .62), P['m1'], 21, .22, .12) if True else canvas
    canvas = draw_layer(ridge(hz - SH * .09, SH * .09, 12, .58), P['m2'], 22, .22, .18)
    canvas = draw_layer(ridge(hz - SH * .03, SH * .05, 13, .55), P['m3'], 23, .10, .30)

    # ---- distant tree line on the far hills
    img = Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img, 'RGBA')
    tl = ridge(hz - SH * .03, SH * .05, 13, .55)
    for i in range(420):
        x = random.randint(0, SW - 1)
        y = tl[x] + random.randint(0, int(SH * .02))
        r = random.randint(int(SH * .004), int(SH * .011))
        g = random.choice(['#3f8a40', '#4e9c48', '#2f7338'] if not night else ['#0c1b18', '#102421', '#0a1714'])
        d.ellipse([x - r, y - r * 1.3, x + r, y + r * .5], fill=g)

    # ---- meadow with depth
    arr = np.asarray(img, np.float32)
    ys = np.arange(hz - int(SH * .03), SH)
    t = ((ys - ys[0]) / (SH - ys[0]))[:, None, None]
    far, mid, near = (np.array(P[k], np.float32) for k in ('g_far', 'g_mid', 'g_near'))
    ground = np.where(t < .35, far * (1 - t / .35) + mid * (t / .35), mid * (1 - (t - .35) / .65) + near * ((t - .35) / .65))
    gt = fbm(SW // 2, len(ys) // 2 + 2, 6, 10, seed + 5)
    gt = np.asarray(Image.fromarray((gt * 255).astype(np.uint8)).resize((SW, len(ys)), Image.BICUBIC), np.float32) / 255
    ground = ground * (.78 + .5 * gt[..., None])
    # gentle undulation of the meadow's top edge
    edge = (np.sin(np.linspace(0, 7, SW)) * SH * .006 + np.sin(np.linspace(0, 19, SW)) * SH * .002).astype(np.int32)
    gm = np.zeros((SH, SW, 1), np.float32)
    for x0 in range(0, SW, 1):
        pass
    top_line = ys[0] + edge
    yy = np.arange(SH)[:, None]
    mk = (yy >= top_line[None, :]).astype(np.float32)
    mk = np.asarray(Image.fromarray((mk * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), np.float32)[..., None] / 255
    full_ground = np.zeros((SH, SW, 3), np.float32)
    full_ground[ys[0]:] = ground
    arr = arr * (1 - mk) + full_ground * mk
    # atmospheric haze on the far meadow
    hzmask = np.clip(1 - (yy - hz) / (SH * .14), 0, 1)[..., None] * mk * (.35 if not night else .25)
    arr = arr * (1 - hzmask) + np.array(P['haze'], np.float32) * hzmask
    # mowing bands
    band = (np.sin(np.arange(SH)[:, None] / SH * 38) * .5 + .5)[..., None]
    arr = arr * (1 + (band - .5) * .06 * mk)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))

    # ---- big foreground trees and bushes (soft blobs w/ light side)
    d = ImageDraw.Draw(img, 'RGBA')

    def tree(cx, base, s):
        d.rectangle([cx - s * .03, base - s * .30, cx + s * .03, base], fill='#6b4a2c' if not night else '#10161c')
        for _ in range(70):
            a = random.random() * math.tau
            rr = random.random() ** .6 * s * .27
            px, py = cx + math.cos(a) * rr * 1.05, base - s * .52 + math.sin(a) * rr * .95
            r = s * (.05 + random.random() * .06)
            lit = (px - cx) / (s * .3)
            if not night:
                g = (int(50 + 38 * (1 - lit) / 2 + random.random() * 16), int(110 + 50 * (1 - lit) / 2 + random.random() * 24), int(52 + random.random() * 20))
            else:
                g = (8, int(22 + random.random() * 14), 22)
            d.ellipse([px - r, py - r, px + r, py + r], fill=g + (235,))
    tree(int(SW * .985), int(SH * .66), SH * .52)
    tree(int(SW * .395), int(SH * .62), SH * .36)
    tree(int(SW * .345), int(SH * .60), SH * .24)

    # ---- grass blades, denser and larger towards the camera
    gb = Image.new('RGBA', (SW, SH), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gb)
    top_y = hz + int(SH * .02)
    for i in range(52000):
        y = top_y + (SH - top_y) * random.random() ** 1.7
        x = random.random() * SW
        k = (y - top_y) / (SH - top_y)
        ln = (3 + 26 * k ** 1.2) * S * random.uniform(.6, 1.3)
        lean = random.uniform(-.45, .45)
        col = random.choice(P['blade'])
        gd.line([(x, y), (x + lean * ln, y - ln)], fill=col + (int(110 + 100 * k),), width=max(1, int(S * (1 + 2.2 * k))))
    gb = gb.filter(ImageFilter.GaussianBlur(.5 * S * .5))
    img = Image.alpha_composite(img.convert('RGBA'), gb).convert('RGB')
    # wild flowers
    d = ImageDraw.Draw(img, 'RGBA')
    if not night:
        for i in range(380):
            y = top_y + (SH - top_y) * random.random() ** 1.3
            x = random.random() * SW
            k = (y - top_y) / (SH - top_y)
            r = (1.2 + 3.2 * k) * S
            d.ellipse([x - r, y - r, x + r, y + r], fill=random.choice([(255, 255, 255, 230), (255, 214, 77, 230), (255, 143, 177, 220)]))

    # ---- solar array geometry (card space, scaled by S)
    q = lambda x, y: (x * S, y * S)
    FL, FR, BR, BL = q(1160, 668), q(1850, 668), q(1935, 468), q(1325, 468)
    rows, cols = 2, 6
    mw, mh = 720, 430
    gapx, gapy = 16, 18
    flat = Image.new('RGB', (cols * (mw + gapx) + gapx, rows * (mh + gapy) + gapy), (24, 30, 44))
    for r in range(rows):
        for c in range(cols):
            flat.paste(module_tex(night, np.random.default_rng(seed * 100 + r * 10 + c), mw, mh), (gapx + c * (mw + gapx), gapy + r * (mh + gapy)))

    # shadows first (on the grass)
    sh = Image.new('L', (SW, SH), 0)
    sd = ImageDraw.Draw(sh)
    ox, oy = (230 * S, 55 * S) if not night else (150 * S, 40 * S)
    sd.polygon([FL, FR, (FR[0] + ox * .6, FR[1] + oy + 90 * S), (FL[0] + ox * .6, FL[1] + oy + 90 * S)], fill=int(120 if not night else 70))
    sh = sh.filter(ImageFilter.GaussianBlur(14 * S))
    a = np.asarray(img, np.float32)
    a *= (1 - np.asarray(sh, np.float32)[..., None] / 255 * .75)
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))

    # steel structure: back legs, then front legs + cross bracing
    d = ImageDraw.Draw(img, 'RGBA')
    steel = '#8d97a6' if not night else '#4c576b'
    steel_d = '#566074' if not night else '#2b3446'
    ground_back = 618 * S
    for fx in (.08, .36, .64, .92):
        bx = BL[0] + (BR[0] - BL[0]) * fx
        d.rectangle([bx - 5 * S, BL[1], bx + 5 * S, ground_back], fill=steel_d)
    # rails
    d.line([BL, BR], fill=steel_d, width=6 * S)
    gl = 770 * S
    legx = [FL[0] + (FR[0] - FL[0]) * f for f in (.07, .36, .64, .93)]
    for x in legx:
        d.rectangle([x - 6 * S, FL[1], x + 6 * S, gl], fill=steel)
        d.rectangle([x - 6 * S, FL[1], x - 2 * S, gl], fill=(255, 255, 255, 70))
        d.ellipse([x - 16 * S, gl - 5 * S, x + 16 * S, gl + 9 * S], fill=(120, 120, 118, 255) if not night else (40, 44, 48, 255))
    for a_, b_ in zip(legx[:-1], legx[1:]):
        d.line([(a_, FL[1] + 22 * S), (b_, gl - 24 * S)], fill=steel_d, width=3 * S)
        d.line([(b_, FL[1] + 22 * S), (a_, gl - 24 * S)], fill=steel_d, width=3 * S)
    d.line([(legx[0], FL[1] + 55 * S), (legx[-1], FL[1] + 55 * S)], fill=steel_d, width=4 * S)

    # panel plane
    layer = warp(flat, [BL, BR, FR, FL], (SW, SH)).convert('RGBA')
    # layer has black outside the quad: build mask from the quad
    m = Image.new('L', (SW, SH), 0)
    ImageDraw.Draw(m).polygon([BL, BR, FR, FL], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(.8))
    img = Image.composite(layer.convert('RGB'), img, m)

    # global specular streak across the glass (follows the sun's light)
    st = Image.new('L', (SW, SH), 0)
    sdr = ImageDraw.Draw(st)
    sdr.polygon([(BL[0] + (BR[0] - BL[0]) * .50, BL[1]), (BL[0] + (BR[0] - BL[0]) * .62, BL[1]), (FL[0] + (FR[0] - FL[0]) * .50, FL[1]), (FL[0] + (FR[0] - FL[0]) * .36, FL[1])], fill=255 if not night else 90)
    st = st.filter(ImageFilter.GaussianBlur(28 * S))
    st = Image.composite(st, Image.new('L', (SW, SH), 0), m)
    a = np.asarray(img, np.float32)
    k = np.asarray(st, np.float32)[..., None] / 255 * (.22 if not night else .10)
    a = a * (1 - k) + np.array([235, 245, 255], np.float32) * k
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))

    # ---- battery / inverter cabinet with 3 faces
    d = ImageDraw.Draw(img, 'RGBA')
    cx0, cx1, cy0, cy1 = 1925 * S, 2045 * S, 585 * S, 775 * S
    dx, dy = 26 * S, 22 * S
    d.ellipse([cx0 - 10 * S, cy1 - 8 * S, cx1 + 70 * S, cy1 + 26 * S], fill=(15, 40, 12, 110) if not night else (0, 0, 0, 120))
    side = '#c4cedb' if not night else '#56627a'
    top = '#f4f7fb' if not night else '#8b97ad'
    front = ['#ffffff', '#e8edf4'] if not night else ['#a6b3c9', '#7b87a0']
    d.polygon([(cx1, cy0), (cx1 + dx, cy0 - dy), (cx1 + dx, cy1 - dy), (cx1, cy1)], fill=side)
    d.polygon([(cx0, cy0), (cx0 + dx, cy0 - dy), (cx1 + dx, cy0 - dy), (cx1, cy0)], fill=top)
    for i in range(cy1 - cy0):
        tcol = i / (cy1 - cy0)
        c1, c2 = hexc(front[0]), hexc(front[1])
        d.line([(cx0, cy0 + i), (cx1, cy0 + i)], fill=tuple(int(c1[k] * (1 - tcol) + c2[k] * tcol) for k in range(3)))
    d.rectangle([cx0, cy0, cx1, cy1], outline=(150, 160, 178, 255), width=2 * S)
    # vents
    for i in range(6):
        y = cy1 - 70 * S + i * 9 * S
        d.line([(cx0 + 20 * S, y), (cx1 - 20 * S, y)], fill=(120, 130, 148, 200), width=2 * S)
    # display and LEDs
    d.rounded_rectangle([cx0 + 20 * S, cy0 + 24 * S, cx1 - 20 * S, cy0 + 74 * S], radius=6 * S, fill=(18, 28, 48, 255))
    for i in range(4):
        d.rectangle([cx0 + 30 * S, cy0 + (32 + i * 9) * S, cx1 - 30 * S - (i == 3) * 24 * S, cy0 + (36 + i * 9) * S], fill=(52, 211, 153, 255))
    bx, by = (cx0 + cx1) / 2, cy0 + 112 * S
    bolt = [(bx + 6 * S, by - 26 * S), (bx - 16 * S, by + 4 * S), (bx - 2 * S, by + 4 * S), (bx - 7 * S, by + 26 * S), (bx + 17 * S, by - 8 * S), (bx + 2 * S, by - 8 * S)]
    d.polygon(bolt, fill=(47, 123, 255, 255))
    if night:
        glow = Image.new('RGBA', (SW, SH), (0, 0, 0, 0))
        ImageDraw.Draw(glow).ellipse([cx0 - 40 * S, cy0 - 20 * S, cx1 + 60 * S, cy1], fill=(52, 211, 153, 40))
        glow = glow.filter(ImageFilter.GaussianBlur(26 * S))
        img = Image.alpha_composite(img.convert('RGBA'), glow).convert('RGB')
        d = ImageDraw.Draw(img, 'RGBA')

    # cable from array to cabinet
    pts = [(legx[-1], gl - 20 * S), (legx[-1] + 40 * S, gl + 12 * S), (cx0 - 50 * S, cy1 + 8 * S), (cx0, cy1 - 24 * S)]
    d.line(pts, fill=(40, 46, 58, 255), width=4 * S, joint='curve')

    # ---- finishing: light grading, vignette, grain
    a = np.asarray(img, np.float32)
    yy, xx = np.mgrid[0:SH, 0:SW].astype(np.float32)
    vig = 1 - .22 * (((xx / SW - .6) ** 2) * 1.6 + ((yy / SH - .5) ** 2) * 1.2)
    a = a * vig[..., None]
    if dusk:
        a *= np.array([1.07, .93, .80], np.float32)
    if not night and not dusk:   # warm sunlight tint on the right, cool shade on the left
        a *= (1 + (xx / SW - .5)[..., None] * np.array([.05, .03, -.04]))
    a += np.random.default_rng(seed).normal(0, 2.0, a.shape)
    out = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))   # full 4600 x 2000 output
    return out.filter(ImageFilter.UnsharpMask(1.6, 70, 2))


if __name__ == '__main__':
    import os
    out = os.path.join(os.path.dirname(__file__), '..', 'assets', 'scene')
    os.makedirs(out, exist_ok=True)
    for mode in ('day', 'dusk', 'night'):
        im = render(mode)
        im.save(os.path.join(out, mode + '.jpg'), quality=88, optimize=True, subsampling=0)
        print('wrote', mode, im.size)
