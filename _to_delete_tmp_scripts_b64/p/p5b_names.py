import sys, re
p = sys.argv[1] + '/shaders/world_ground.gdshaderinc'
s = open(p).read()
s = s.replace("float surf_break_x(float swell_a, float slope_under) {\n\tfloat hb = clamp(0.35 + swell_a * 0.55, 0.35, 1.6);",
              "float surf_break_x(float p_amp, float p_slope) {\n\tfloat hb = clamp(0.35 + p_amp * 0.55, 0.35, 1.6);")
s = s.replace("return clamp(hb / max(slope_under, 0.01), 4.0, 45.0);", "return clamp(hb / max(p_slope, 0.01), 4.0, 45.0);")
s = s.replace("float swash_x(float swell_a, float rock, float slope_above) {\n\tfloat r = clamp(0.2 + swell_a * 0.35, 0.2, 0.8) * mix(1.0, 0.5, rock);\n\treturn r / max(slope_above, 0.02);",
              "float swash_x(float p_amp, float p_rock, float p_slope) {\n\tfloat r = clamp(0.2 + p_amp * 0.35, 0.2, 0.8) * mix(1.0, 0.5, p_rock);\n\treturn r / max(p_slope, 0.02);")
s = s.replace("float surf_u(vec2 cp, float t, float period, int f) {", "float surf_u(vec2 cp, float t, float p_period, int f) {")
s = s.replace("return fract(t / period + float(f) * 0.5 + wob * 0.9);", "return fract(t / p_period + float(f) * 0.5 + wob * 0.9);")
s = s.replace("float surf_lace(float dens, float pat) {\n\tfloat thr = 1.0 - dens;\n\treturn smoothstep(thr - 0.07, thr + 0.07, pat) * smoothstep(0.02, 0.12, dens);",
              "float surf_lace(float p_dens, float p_pat) {\n\tfloat thr = 1.0 - p_dens;\n\treturn smoothstep(thr - 0.07, thr + 0.07, p_pat) * smoothstep(0.02, 0.12, p_dens);")
for bad in ["swell_a", "slope_under", "slope_above", "float period", "float dens", "float pat"]:
    assert bad not in s[s.index("// ---- Surf and swash"):], bad
open(p, 'w').write(s)
