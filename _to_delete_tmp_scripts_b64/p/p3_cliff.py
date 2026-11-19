# Cliffs rise with the distance from the waterline (a rocky foreshore, then the cliff), not with every bump of the ground.
import sys
root = sys.argv[1]
def edit(p, pairs):
    p = root + '/' + p
    s = open(p).read()
    for o, n in pairs:
        assert s.count(o) == 1, (p, o[:80])
        s = s.replace(o, n)
    open(p, 'w').write(s)
edit('shaders/world_terrain.gdshader', [("""		// 0 at the waterline, all of the cliff once the shore is fully land (a few tens of metres in)
		y += rock * cliff_height(cp) * smoothstep(0.15, 1.0, y);""",
"""		// a few metres of rocky foreshore, then the cliff rises over the next 30 m or so
		y += rock * cliff_height(cp) * smoothstep(5.0, 38.0, shore_d(cp));""")])
edit('scripts/world_ground.gd', [("""		y += rock * cliff_height(cp) * smoothstep(0.15, 1.0, y)""",
"""		y += rock * cliff_height(cp) * smoothstep(5.0, 38.0, shore_d(x, z))""")])
