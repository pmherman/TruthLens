import math, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 1024
SS = 2  # supersample
N = S * SS

def lerp(a, b, t): return tuple(int(a[i] + (b[i]-a[i])*t) for i in range(3))

def grad(size, c1, c2, angle_deg=135):
    w, h = size
    a = math.radians(angle_deg)
    dx, dy = math.cos(a), math.sin(a)
    g = Image.linear_gradient("L").resize((256, 256))
    # build via numpy-free approach: draw on small then resize
    small = Image.new("RGB", (256, 256))
    px = small.load()
    for y in range(256):
        for x in range(256):
            t = ((x-128)*dx + (y-128)*dy) / 362 + 0.5
            px[x, y] = lerp(c1, c2, max(0, min(1, t)))
    return small.resize(size, Image.BICUBIC)

def radial_glow(size, center, radius, color, strength):
    w, h = size
    m = Image.new("L", (256, 256), 0)
    d = ImageDraw.Draw(m)
    for i in range(128, 0, -1):
        v = int(255 * strength * (1 - i/128) ** 2)
        d.ellipse((128-i, 128-i, 128+i, 128+i), fill=v)
    m = m.resize((int(radius*2), int(radius*2)), Image.BICUBIC)
    layer = Image.new("RGB", size, color)
    mask = Image.new("L", size, 0)
    mask.paste(m, (int(center[0]-radius), int(center[1]-radius)))
    return layer, mask

def render(mac=False):
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    # artwork canvas
    inset = int(N * 0.098) if mac else 0
    box = N - 2*inset
    art = grad((box, box), (38, 30, 120), (6, 8, 28), 120).convert("RGBA")
    k = box / 1024  # scale factor for design coords

    def P(v): return v * k

    # background glow behind lens
    glow, gm = radial_glow((box, box), (P(470), P(460)), P(560), (40, 200, 230), 0.55)
    art.paste(glow, (0, 0), gm)

    # lens geometry
    cx, cy, R = P(470), P(450), P(290)
    ring = P(58)

    # handle (drawn first, under ring)
    hl = Image.new("RGBA", (box, box), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    a = math.radians(45)
    x0, y0 = cx + math.cos(a)*(R+ring*0.2), cy + math.sin(a)*(R+ring*0.2)
    x1, y1 = cx + math.cos(a)*(R+P(250)), cy + math.sin(a)*(R+P(250))
    hd.line((x0, y0, x1, y1), fill=(255, 255, 255, 255), width=int(P(92)))
    for (x, y) in ((x0, y0), (x1, y1)):
        hd.ellipse((x-P(46), y-P(46), x+P(46), y+P(46)), fill=(255, 255, 255, 255))
    hmask = hl.split()[3]
    hcol = grad((box, box), (255, 120, 220), (120, 90, 255), 90)
    # shadow
    sh = Image.new("RGBA", (box, box), (0, 0, 0, 0))
    sh.paste((0, 0, 0, 120), (0, 0), hmask.filter(ImageFilter.GaussianBlur(P(18))))
    art.alpha_composite(sh, (int(P(8)), int(P(16))) if False else (0, 0))
    art.paste(hcol, (0, 0), hmask)

    # lens interior (glass)
    inner = R - ring/2
    glass = Image.new("RGBA", (box, box), (0, 0, 0, 0))
    gmask = Image.new("L", (box, box), 0)
    ImageDraw.Draw(gmask).ellipse((cx-inner, cy-inner, cx+inner, cy+inner), fill=255)
    base = grad((box, box), (16, 24, 70), (10, 14, 44), 90).convert("RGBA")
    glass.paste(base, (0, 0), gmask)

    # scene inside lens: soft aurora "photo" on left, pixelated on right
    scene = Image.new("RGB", (box, box))
    sc = grad((box, box), (60, 220, 230), (130, 70, 255), 60)
    gl2, gm2 = radial_glow((box, box), (cx - P(90), cy + P(40)), P(260), (255, 140, 210), 0.9)
    sc.paste(gl2, (0, 0), gm2)
    # pixelate right side
    cell = int(P(34))
    small = sc.resize((box//cell, box//cell), Image.BOX)
    pix = small.resize((box, box), Image.NEAREST)
    # blend mask: smooth left -> pixel right with a stepped dissolve
    mix = Image.new("L", (box, box), 0)
    md = ImageDraw.Draw(mix)
    gx = cx - P(30)
    for gy in range(0, box, cell):
        for gxx in range(0, box, cell):
            t = (gxx - gx) / P(150)
            if t <= 0: continue
            md.rectangle((gxx, gy, gxx+cell-1, gy+cell-1), fill=int(255*min(1, t)))
    sc = Image.composite(pix, sc, mix)
    # darken a touch for contrast
    sc = Image.blend(sc, Image.new("RGB", (box, box), (8, 10, 36)), 0.28)
    glass.paste(sc, (0, 0), gmask)

    # pixel grid lines on pixelated side
    gridl = Image.new("RGBA", (box, box), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gridl)
    for i in range(0, box, cell):
        gd.line((i, 0, i, box), fill=(8, 10, 36, 90), width=max(1, int(P(2))))
        gd.line((0, i, box, i), fill=(8, 10, 36, 90), width=max(1, int(P(2))))
    gridmask = ImageChops.multiply(gmask, mix)
    glass.paste(gridl, (0, 0), ImageChops.multiply(gridmask, gridl.split()[3]))

    # checkmark in the lens (verified / truth)
    ck = Image.new("RGBA", (box, box), (0, 0, 0, 0))
    cd = ImageDraw.Draw(ck)
    pts = [(cx-P(125), cy+P(10)), (cx-P(35), cy+P(105)), (cx+P(135), cy-P(95))]
    w = int(P(46))
    cd.line(pts, fill=(255, 255, 255, 255), width=w, joint="curve")
    for (x, y) in (pts[0], pts[2]):
        cd.ellipse((x-w/2, y-w/2, x+w/2, y+w/2), fill=(255, 255, 255, 255))
    cshadow = Image.new("RGBA", (box, box), (0, 0, 0, 0))
    cshadow.paste((6, 8, 30, 170), (0, 0), ck.split()[3].filter(ImageFilter.GaussianBlur(P(14))))
    glass.alpha_composite(cshadow)
    glass.alpha_composite(ck)

    # glass highlight
    hi = Image.new("RGBA", (box, box), (0, 0, 0, 0))
    hid = ImageDraw.Draw(hi)
    hid.pieslice((cx-inner*0.92, cy-inner*0.92, cx+inner*0.92, cy+inner*0.92), 200, 262, fill=(255, 255, 255, 60))
    hi_m = Image.new("L", (box, box), 0)
    ImageDraw.Draw(hi_m).ellipse((cx-inner*0.92, cy-inner*0.92, cx+inner*0.92, cy+inner*0.92), fill=255)
    ImageDraw.Draw(hi_m).ellipse((cx-inner*0.78, cy-inner*0.78, cx+inner*0.78, cy+inner*0.78), fill=0)
    hi.putalpha(ImageChops.multiply(hi.split()[3], hi_m))
    glass.alpha_composite(hi)

    art.alpha_composite(glass)

    # ring with gradient
    rmask = Image.new("L", (box, box), 0)
    rd = ImageDraw.Draw(rmask)
    rd.ellipse((cx-R-ring/2, cy-R-ring/2, cx+R+ring/2, cy+R+ring/2), fill=255)
    rd.ellipse((cx-R+ring/2, cy-R+ring/2, cx+R-ring/2, cy+R-ring/2), fill=0)
    rcol = grad((box, box), (90, 255, 235), (140, 100, 255), 60)
    # outer glow
    og = Image.new("RGBA", (box, box), (0, 0, 0, 0))
    og.paste((70, 230, 240, 150), (0, 0), rmask.filter(ImageFilter.GaussianBlur(P(26))))
    art.alpha_composite(og)
    art.paste(rcol, (0, 0), rmask)

    # sparkle (AI) top-right
    def sparkle(x, y, r, alpha=255):
        sp = Image.new("RGBA", (box, box), (0, 0, 0, 0))
        d = ImageDraw.Draw(sp)
        pts = []
        for i in range(8):
            ang = math.pi/4 * i - math.pi/2
            rad = r if i % 2 == 0 else r*0.26
            pts.append((x + math.cos(ang)*rad, y + math.sin(ang)*rad))
        d.polygon(pts, fill=(255, 255, 255, alpha))
        gl = sp.filter(ImageFilter.GaussianBlur(P(14)))
        art.alpha_composite(gl)
        art.alpha_composite(sp)
    sparkle(P(790), P(215), P(90))
    sparkle(P(880), P(340), P(42))

    # compose
    if mac:
        mask = Image.new("L", (box, box), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, box-1, box-1), radius=int(box*0.225), fill=255)
        # drop shadow
        shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        sm = Image.new("L", (N, N), 0)
        sm.paste(mask, (inset, inset + int(N*0.012)))
        shadow.paste((0, 0, 0, 110), (0, 0), sm.filter(ImageFilter.GaussianBlur(N*0.012)))
        img.alpha_composite(shadow)
        tile = Image.new("RGBA", (box, box), (0, 0, 0, 0))
        tile.paste(art, (0, 0), mask)
        # subtle top highlight edge
        img.alpha_composite(tile, (inset, inset))
    else:
        img.alpha_composite(art)
        img = img.convert("RGB").convert("RGBA")
    return img.resize((S, S), Image.LANCZOS)

if __name__ == "__main__":
    out = sys.argv[1]
    render(mac=False).convert("RGB").save(f"{out}/ios.png")
    render(mac=True).save(f"{out}/mac.png")
