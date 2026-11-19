import sys
p = sys.argv[1] + '/shaders/world_ground.gdshaderinc'
s = open(p).read()
a = s.index("// What kind of coast a stretch of shore is")
b = s.index("}\n", s.index("vec3 coast_kind(vec2 cp)")) + 2
block = s[a:b]
s = s[:a] + s[b:]
i = s.index("// ---- The near-shore profile ----")
s = s[:i] + block + "\n" + s[i:]
open(p, 'w').write(s)
