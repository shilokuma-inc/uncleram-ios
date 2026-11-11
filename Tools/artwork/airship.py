import sys
from PIL import Image, ImageOps, ImageEnhance, ImageDraw, ImageFilter
dl, out = sys.argv[1], sys.argv[2]
NAVY=(30,35,64)
def halftone(g, width, name, cell=4, gamma=1.0, contrast=1.3):
    g = g.resize((width, int(g.height*width/g.width)), Image.LANCZOS)
    g = ImageEnhance.Contrast(g).enhance(contrast)
    sm = g.resize((g.width//cell, g.height//cell), Image.BOX); s=3
    img = Image.new("RGBA",(sm.width*cell*s, sm.height*cell*s),NAVY+(0,)); d=ImageDraw.Draw(img)
    for y in range(sm.height):
        for x in range(sm.width):
            dark=(1-sm.getpixel((x,y))/255)**gamma; r=dark*cell*s*0.74
            if r<0.7: continue
            cx,cy=(x+.5)*cell*s,(y+.5)*cell*s; d.ellipse((cx-r,cy-r,cx+r,cy+r),fill=NAVY+(255,))
    img.resize((sm.width*cell, sm.height*cell),Image.LANCZOS).save(f"{out}/{name}",optimize=True)
# Bain: crop caption/edges, blur hull lettering
b = Image.open(f"{dl}/airship-bain.jpg").convert("L")
mask = Image.new("L", b.size, 0); ImageDraw.Draw(mask).polygon([(470,420),(650,320),(690,400),(510,500)], fill=255)
blur = b.filter(ImageFilter.GaussianBlur(14))
b = Image.composite(blur, b, mask.filter(ImageFilter.GaussianBlur(6)))
b = b.crop((60, 95, 1150, 850))
b = ImageOps.autocontrast(b, cutoff=1)
b = b.point(lambda v: min(255, int(v*1.05)))
halftone(b, 900, "airship-halftone.png", cell=4, gamma=2.0, contrast=1.0)
# Stieglitz: small silhouette only
s = Image.open(f"{dl}/airship-stieglitz.jpg").convert("L").crop((400, 115, 585, 295))
s = ImageOps.autocontrast(s, cutoff=1).point(lambda v: 255 if v > 95 else int(v*0.6))
halftone(s, 240, "airship-small.png", cell=3, gamma=1.0, contrast=1.0)
