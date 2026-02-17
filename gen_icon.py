#!/usr/bin/env python3
"""Generate YTApp icon - a rounded rect with a play button, YouTube-inspired."""
from PIL import Image, ImageDraw
import math

def gen_icon(size):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Rounded rectangle background - dark charcoal with slight gradient feel
    margin = int(size * 0.05)
    radius = int(size * 0.22)
    
    # Background: dark gradient-like (draw two layers)
    # Base: dark charcoal
    draw.rounded_rectangle(
        [margin, margin, size - margin, size - margin],
        radius=radius,
        fill=(30, 30, 30, 255)
    )
    
    # Subtle inner glow/lighter area at top
    inner_m = int(size * 0.08)
    draw.rounded_rectangle(
        [inner_m, inner_m, size - inner_m, int(size * 0.55)],
        radius=int(radius * 0.8),
        fill=(45, 45, 45, 255)
    )
    
    # Re-draw bottom half to blend
    draw.rounded_rectangle(
        [margin, margin, size - margin, size - margin],
        radius=radius,
        outline=None,
        fill=None
    )
    
    # Actually let's do a clean approach: solid dark bg with a red rounded-rect "screen" and play button
    img2 = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img2)
    
    # Outer rounded rect - dark
    m = int(size * 0.045)
    r = int(size * 0.22)
    d.rounded_rectangle([m, m, size-m, size-m], radius=r, fill=(24, 24, 24, 255))
    
    # Inner "screen" area - YouTube red, slightly rounded
    sm = int(size * 0.15)
    sr = int(size * 0.12)
    d.rounded_rectangle([sm, sm, size-sm, size-sm], radius=sr, fill=(255, 0, 0, 255))
    
    # Play triangle - white, centered in the red area
    cx = size / 2
    cy = size / 2
    tri_size = size * 0.22
    # Play triangle points (equilateral-ish, pointing right)
    # Offset slightly right since play buttons look better that way
    offset = tri_size * 0.1
    pts = [
        (cx - tri_size * 0.45 + offset, cy - tri_size * 0.55),
        (cx - tri_size * 0.45 + offset, cy + tri_size * 0.55),
        (cx + tri_size * 0.55 + offset, cy),
    ]
    d.polygon(pts, fill=(255, 255, 255, 255))
    
    return img2


sizes = {
    16: "icon_16x16.png",
    32: "icon_16x16@2x.png",
    32: "icon_32x32.png",
    64: "icon_32x32@2x.png",
    128: "icon_128x128.png",
    256: "icon_128x128@2x.png",
    256: "icon_256x256.png",
    512: "icon_256x256@2x.png",
    512: "icon_512x512.png",
    1024: "icon_512x512@2x.png",
}

# Generate unique sizes and save all variants
base = "YTApp/YTApp/Assets.xcassets/AppIcon.appiconset"
all_files = []

for sz, name in [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]:
    icon = gen_icon(sz)
    path = f"{base}/{name}"
    icon.save(path)
    all_files.append((name, sz))
    print(f"  {name} ({sz}x{sz})")

print("Done!")
