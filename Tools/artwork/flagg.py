import sys
from PIL import Image, ImageOps, ImageEnhance, ImageDraw
dl, out = sys.argv[1], sys.argv[2]
NAVY=(30,35,64)
f=1.1525
p = Image.open(f"{dl}/flagg-poster-ref.jpg").convert("L")
def ht(box, width, name, cell=4, gamma=1.0, contrast=1.3, fade_bottom=0):
    g = p.crop(tuple(int(v*f) for v in box))
    g = g.resize((width, int(g.height*width/g.width)), Image.LANCZOS)
    g = ImageOps.autocontrast(g, cutoff=1)
    g = ImageEnhance.Contrast(g).enhance(contrast)
    sm = g.resize((g.width//cell, g.height//cell), Image.BOX)
    s=3
    img = Image.new("RGBA",(sm.width*cell*s, sm.height*cell*s),NAVY+(0,))
    d = ImageDraw.Draw(img)
    for y in range(sm.height):
        fade = 1.0
        if fade_bottom and y > sm.height - fade_bottom:
            fade = max(0.0,(sm.height - y)/fade_bottom)
        for x in range(sm.width):
            dark=((1-sm.getpixel((x,y))/255)**gamma)*fade
            r=dark*cell*s*0.74
            if r<0.7: continue
            cx,cy=(x+.5)*cell*s,(y+.5)*cell*s
            d.ellipse((cx-r,cy-r,cx+r,cy+r),fill=NAVY+(255,))
    img=img.resize((sm.width*cell, sm.height*cell),Image.LANCZOS)
    img.save(f"{out}/{name}",optimize=True)
ht((500,795,925,1280), 640, "hand-halftone.png", cell=4, fade_bottom=18)
ht((540,150,1070,500), 520, "hat-halftone.png", cell=4, contrast=1.5)
