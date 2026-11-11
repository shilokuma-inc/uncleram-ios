import sys
from PIL import Image, ImageOps, ImageEnhance, ImageDraw, ImageFilter
dl, out = sys.argv[1], sys.argv[2]
NAVY = (30, 35, 64)

# 1. paper background (portrait, 2x of 390x844)
p = Image.open(f"{dl}/paper.jpg").convert("RGB")
w, h = p.size
cw = int(h * 390 / 844)
p = p.crop((w - cw - 60, 0, w - 60, h)).resize((780, 1688), Image.LANCZOS)
p = ImageEnhance.Brightness(p).enhance(1.04)
p.save(f"{out}/paper-bg.jpg", quality=72, optimize=True, progressive=True)

# 2. border strips -> navy line art on transparent
b = Image.open(f"{dl}/borders.jpg").convert("L")
def strip(box, name):
    s = b.crop(box)
    s = ImageOps.autocontrast(s, cutoff=2)
    alpha = s.point(lambda v: 255 if v < 110 else (0 if v > 170 else int((170 - v) * 255 / 60)))
    img = Image.new("RGBA", s.size, NAVY + (0,))
    img.putalpha(alpha)
    img.save(f"{out}/{name}", optimize=True)
strip((78, 713, 1140, 781), "border-a.png")   # No 133
strip((36, 1128, 1176, 1177), "border-b.png")  # No 136

# 3. halftone (navy dots on transparent)
def halftone(src, box, width, name, cell=7, gamma=1.0, contrast=1.4):
    g = Image.open(src).convert("L")
    if box: g = g.crop(box)
    g = g.resize((width, int(g.height * width / g.width)), Image.LANCZOS)
    g = ImageEnhance.Contrast(g).enhance(contrast)
    sm = g.resize((max(1, g.width // cell), max(1, g.height // cell)), Image.BOX)
    scale = 3
    img = Image.new("RGBA", (g.width * scale, g.height * scale), NAVY + (0,))
    d = ImageDraw.Draw(img)
    for y in range(sm.height):
        for x in range(sm.width):
            dark = (1 - sm.getpixel((x, y)) / 255) ** gamma
            r = dark * cell * scale * 0.72
            if r < 0.6: continue
            cx, cy = (x + 0.5) * cell * scale, (y + 0.5) * cell * scale
            d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=NAVY + (255,))
    img = img.resize((g.width, g.height), Image.LANCZOS)
    img.save(f"{out}/{name}", optimize=True)
halftone(f"{dl}/factory.jpg", (70, 420, 1850, 960), 900, "factory-halftone.png", cell=3, gamma=1.25, contrast=1.35)
halftone(f"{dl}/servers.jpg", (0, 600, 2000, 2500), 900, "servers-halftone.png", cell=6, contrast=1.6)
