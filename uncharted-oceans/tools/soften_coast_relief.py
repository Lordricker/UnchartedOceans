#!/usr/bin/env python3
"""Soften the macro terrain's coasts: no mountain may rise straight out of the sea.

Reads assets/world/world_height16.png.pre-soften-2026-11-11 (the original heightmap, R = high byte, G = low byte)
and writes assets/world/world_height16.png. On land, the height above the coast is capped at SLOPE x (distance
inland from the nearest water pixel), then lightly smoothed. Interior mountains of big landmasses keep their height;
small islands and coasts lose their wall of cliffs. Run again with another slope to retune: the source is always the
backup, so it never compounds.

  python tools/soften_coast_relief.py [slope=0.25] [sigma_px=1.0]
Needs: pillow, numpy, scipy.
"""
import json, sys
import numpy as np
from PIL import Image
from scipy import ndimage

SLOPE = float(sys.argv[1]) if len(sys.argv) > 1 else 0.25     # metres of height per metre inland (0.25 = about 14 degrees)
SIGMA = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0      # smoothing, in chart pixels
COAST = 0.2431                                                # heightmap value at the shoreline (world_terrain.gdshader coast_level)
RELIEF_M = 1100.0                                             # world_terrain.gdshader relief_m: height of value 1.0 above the coast
A = "assets/world/"
chart = json.load(open(A + "world_chart.json"))
mpp = float(chart["width_m"]) / float(chart["px_width"])

src = np.array(Image.open(A + "world_height16.png.pre-soften-2026-11-11").convert("RGB")).astype(np.int64)
v = (src[:, :, 0] * 256 + src[:, :, 1]) / 65535.0
land = np.array(Image.open(A + "world_land.png").convert("L")) >= 128

h_m = (v - COAST) / (1.0 - COAST) * RELIEF_M                  # metres above the coast
dist_m = ndimage.distance_transform_edt(land) * mpp           # inland distance to the nearest water pixel
cap = SLOPE * dist_m
h2 = np.where(land & (h_m > 0.0), np.minimum(h_m, cap), h_m)
if SIGMA > 0.0:
    sm = ndimage.gaussian_filter(np.where(land, np.maximum(h2, 0.0), 0.0), SIGMA)
    wgt = ndimage.gaussian_filter(land.astype(float), SIGMA)
    sm = sm / np.maximum(wgt, 1e-6)
    h2 = np.where(land & (h_m > 0.0), np.minimum(sm, h_m), h2)   # smoothing never raises land above the original
v2 = np.where(land & (h_m > 0.0), COAST + h2 / RELIEF_M * (1.0 - COAST), v)
q = np.clip(np.round(v2 * 65535.0), 0, 65535).astype(np.int64)
out = np.zeros(src.shape, dtype=np.uint8)
out[:, :, 0] = q >> 8
out[:, :, 1] = q & 255
out[:, :, 2] = src[:, :, 2]
Image.fromarray(out, "RGB").save(A + "world_height16.png")
ch = (h_m > h2 + 1.0) & land
print("slope %.2f sigma %.1f px, mpp %.1f" % (SLOPE, SIGMA, mpp))
print("land px changed: %d of %d; max height before %.0f m, after %.0f m" % (ch.sum(), land.sum(), h_m[land].max(), h2[land].max()))
