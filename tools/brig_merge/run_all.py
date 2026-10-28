"""run_all.py - rebuild the Godot brig from MerchantBrigShipMaster.blend.
Run from the project root, either of:
   "C:\Program Files\Blender Foundation\Blender 4.1\blender.exe" -b --python tools/brig_merge/run_all.py
   or, inside a Blender session:   exec(open(r"<project>/tools/brig_merge/run_all.py").read())
Every step is its own background Blender process (a crash in one cannot hurt your session) and writes
tools/brig_merge/out/sNN_*.blend; the last step exports export/Brig_test.glb. It never touches Master or Brig.glb."""
import os, sys, subprocess, time
try:
    import bpy; BLENDER = bpy.app.binary_path; HERE = os.path.dirname(bpy.data.filepath) if bpy.data.filepath else None
except Exception:
    BLENDER = os.environ.get("BLENDER", r"C:\Program Files\Blender Foundation\Blender 4.1\blender.exe"); HERE = None
PROJECT = os.environ.get("BRIG_PROJECT") or (os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")) if "__file__" in globals() else HERE)
TOOLS = os.path.join(PROJECT, "tools", "brig_merge"); OUTD = os.path.join(TOOLS, "out"); os.makedirs(OUTD, exist_ok=True)
MASTER = os.path.join(PROJECT, "MerchantBrigShipMaster.blend"); GLB = os.path.join(PROJECT, "export", "Brig_test.glb")
STEPS = [("00_materials.py", MASTER, "s00_materials.blend"), ("01_static_groups.py", "s00_materials.blend", "s01_static.blend"), ("02_animated_parts.py", "s01_static.blend", "s02_animated.blend"),
         ("03_organize.py", "s02_animated.blend", "s03_organized.blend"), ("04_decimate.py", "s03_organized.blend", "s04_decimated.blend"), ("05_rig_lods.py", "s04_decimated.blend", "s05_rig_lods.blend"),
         ("06_finalize.py", "s05_rig_lods.blend", "s06_final.blend"), ("07_collision.py", "s06_final.blend", "s07_collision.blend"), ("08_export_test.py", "s07_collision.blend", None)]
for f in os.listdir(TOOLS):
    if f.endswith("_log.txt") or f == "merge_log.txt": os.remove(os.path.join(TOOLS, f))
for script, src, out in STEPS:
    t0 = time.time(); src = src if os.path.isabs(src) else os.path.join(OUTD, src)
    env = dict(os.environ, BRIG_PROJECT=PROJECT, MERGE_OUT=os.path.join(OUTD, out) if out else "", MERGE_SKIP="", GLB_OUT=GLB)
    p = subprocess.run([BLENDER, "-b", src, "--python", os.path.join(TOOLS, script), "--python-exit-code", "3"], env=env, capture_output=True, text=True, timeout=900)
    bad = [l for l in (p.stdout + p.stderr).splitlines() if "Traceback" in l or l.startswith("Error")]
    print(f"{script:22s} rc={p.returncode} {round(time.time()-t0,1):5.1f}s", "FAILED" if (p.returncode or bad) else "ok")
    if p.returncode or bad: print((p.stdout + p.stderr)[-1800:]); raise SystemExit(f"step {script} failed")
print("done ->", GLB)
