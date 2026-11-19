"""run23.py - steps 2 and 3 only (materials already built in out/c1_materials.blend)."""
import subprocess, os, sys, bpy
PROJ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WD = os.path.join(PROJ, "tools", "fluyt_merge"); OUT = os.path.join(WD, "out")
env = dict(os.environ, FLUYT_PROJECT=PROJ)
exe = bpy.app.binary_path
c1 = os.path.join(OUT, "c1_materials.blend"); c2 = os.path.join(OUT, "c2_game.blend")
glb = os.path.join(PROJ, "uncharted-oceans", "assets", "ships", "fluyt", "Fluyt.glb")
for step, (script, infile, outfile) in enumerate([("02_build.py", c1, c2), ("03_export.py", c2, c2)], 2):
    e = dict(env, MERGE_OUT=outfile, GLB_OUT=glb)
    r = subprocess.run([exe, "--background", infile, "--python", os.path.join(WD, script)], env=e, capture_output=True, text=True)
    last = [l for l in r.stdout.splitlines() if l.startswith(("OK", "Error", "Traceback"))] or r.stdout.splitlines()[-3:]
    print("step %d %s -> %s" % (step, script, last))
    if r.returncode != 0 or "Traceback" in r.stdout + r.stderr: print(r.stderr[-2500:], r.stdout[-2500:]); sys.exit(1)
print("DONE", glb)
