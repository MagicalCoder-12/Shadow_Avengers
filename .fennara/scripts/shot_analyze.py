import sys
try:
    from PIL import Image
except ImportError:
    print("PIL_MISSING")
    sys.exit(1)

path = sys.argv[1]
img = Image.open(path).convert('RGB')
w, h = img.size
print(f"size: {w}x{h}")

# 4 columns x 6 rows grid of average colors
cols, rows = 4, 6
for r in range(rows):
    line = []
    for c in range(cols):
        box = (c * w // cols, r * h // rows, (c + 1) * w // cols, (r + 1) * h // rows)
        region = img.crop(box).resize((1, 1), Image.BILINEAR)
        px = region.getpixel((0, 0))
        line.append(f"({px[0]:3d},{px[1]:3d},{px[2]:3d})")
    print(" | ".join(line))

# Top-left 220x120 px area (PROF button zone) brightness & colorfulness
tl = img.crop((0, 0, 220, 120))
stat = tl.resize((1, 1), Image.BILINEAR).getpixel((0, 0))
ext = tl.convert('L').getextrema()
print(f"top-left zone avg: ({stat[0]},{stat[1]},{stat[2]}) luma-extrema: {ext}")

# Whole-image brightness extrema (splash=uniform, menu=varied)
g = img.convert('L')
small = g.resize((64, 64))
pxs = list(small.getdata())
print(f"global luma min/max/avg: {min(pxs)}/{max(pxs)}/{sum(pxs)//len(pxs)}")
