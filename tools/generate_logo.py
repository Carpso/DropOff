"""Generate DropOff's refined parcel + location-pin launcher artwork.

Premium pass: vertical gradient background, soft pin shadow, gradient amber
pin, shaded parcel faces, orange packing tape and a dark "drop" notch.
Draws at 3x and downsamples with LANCZOS for clean edges.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "app" / "assets" / "brand" / "dropoff_logo.png"
OUT.parent.mkdir(parents=True, exist_ok=True)

S = 3
W = 1024
WS = W * S


def box(values):
    return tuple(int(v * S) for v in values)


def points(values):
    return [(int(x * S), int(y * S)) for x, y in values]


def v_gradient(rgb_top, rgb_bottom):
    strip = Image.new("RGB", (1, WS))
    sp = strip.load()
    for y in range(WS):
        t = y / (WS - 1)
        sp[0, y] = tuple(int(rgb_top[i] + (rgb_bottom[i] - rgb_top[i]) * t) for i in range(3))
    return strip.resize((WS, WS), Image.Resampling.BILINEAR)


# --- background: deep green vertical gradient + soft top glow -----------------
im = v_gradient((0x15, 0x47, 0x3B), (0x09, 0x2A, 0x25))

glow = Image.new("L", (WS, WS), 0)
ImageDraw.Draw(glow).ellipse(box((80, -420, 1160, 660)), fill=26)
im.paste(Image.new("RGB", (WS, WS), (0x2B, 0x7A, 0x5E)), (0, 0), glow)

# --- pin silhouette ------------------------------------------------------------
pin_mask = Image.new("L", (WS, WS), 0)
pm = ImageDraw.Draw(pin_mask)
pm.ellipse(box((210, 110, 814, 714)), fill=255)
pm.polygon(points([(242, 474), (782, 474), (512, 894)]), fill=255)
pm.polygon(points([(285, 606), (739, 606), (512, 894)]), fill=255)

# --- pin shadow (soft) ---------------------------------------------------------
shadow_a = Image.new("L", (WS, WS), 0)
sil = pin_mask.filter(ImageFilter.GaussianBlur(6 * S))
shadow_a.paste(sil, (0, 26 * S))
shadow_a = shadow_a.point(lambda v: int(v * 0.45))
im.paste(Image.new("RGB", (WS, WS), (0x02, 0x14, 0x10)), (0, 0), shadow_a)

# --- amber pin with a vertical gradient ----------------------------------------
im.paste(v_gradient((0xFF, 0xCE, 0x6B), (0xF2, 0x9C, 0x1E)), (0, 0), pin_mask)

# --- parcel cube (white top, ivory left, sage right) ---------------------------
d = ImageDraw.Draw(im)
d.polygon(points([(338, 371), (512, 271), (686, 371), (512, 471)]), fill="#FFFFFF")      # top
d.polygon(points([(338, 371), (512, 471), (512, 682), (338, 582)]), fill="#F5F7EF")      # left
d.polygon(points([(512, 471), (686, 371), (686, 582), (512, 682)]), fill="#D9E2DC")      # right
# packing tape down the top centre + a soft highlight edge
d.polygon(points([(464, 299), (512, 271), (560, 299), (560, 438), (512, 471), (464, 443)]), fill="#F09A22")
d.polygon(points([(464, 299), (512, 271), (516, 273), (516, 470), (512, 471), (464, 443)]), fill="#FFB84D")
# dark green "drop" chevron under the tape
d.polygon(points([(464, 443), (512, 471), (560, 438), (560, 494), (512, 528), (464, 494)]), fill="#123C32")

# --- mint route accent (pickup point) ------------------------------------------
route = Image.new("RGBA", (WS, WS), (0, 0, 0, 0))
rd = ImageDraw.Draw(route)
rd.ellipse(box((812, 174, 876, 238)), fill=(0x4C, 0xE0, 0xA6, 255))
rd.ellipse(box((826, 188, 862, 224)), fill=(0xF2, 0xFF, 0xF8, 235))
im_rgba = im.convert("RGBA")
im_rgba.alpha_composite(route)
im = im_rgba.convert("RGB")

# --- downsample & save ---------------------------------------------------------
im = im.resize((W, W), Image.Resampling.LANCZOS)
im.save(OUT, optimize=True)
print(OUT)
