import sys
p = sys.argv[1] + '/shaders/world_terrain.gdshader'
s = open(p).read()
o = "sand = mix(sand, sand * clamp(sd / max(sav, vec3(0.05)), 0.55, 1.5), near_k);"
assert s.count(o) == 1
s = s.replace(o, "sand = mix(sand, sand * clamp(mix(vec3(1.0), sd / max(sav, vec3(0.05)), 0.6), 0.75, 1.25), near_k);")
open(p, 'w').write(s)
