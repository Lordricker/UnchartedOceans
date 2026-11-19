# The terrain's normal from a step that suits the pixel (it was a fixed 40 m, which turned the steep near-shore slope
# into "rock" and blurred the beach's shape).
import sys
p = sys.argv[1] + '/shaders/world_terrain.gdshader'
s = open(p).read()
o = "	float e = 40.0;\n	float y0 = terrain_y(world_xz);"
assert s.count(o) == 1
s = s.replace(o, "	float e = clamp(foot * 3.0, 1.0, 40.0);\n	float y0 = terrain_y(world_xz);")
open(p, 'w').write(s)
