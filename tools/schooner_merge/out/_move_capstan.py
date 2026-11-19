
import bpy
from mathutils import Matrix
o = bpy.data.objects['Capstan']
o.data.transform(Matrix.Translation((-2.9, 0, 0)))          # +1.45 -> -1.45
bpy.ops.wm.save_mainfile(); print("capstan moved")
