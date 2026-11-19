
import bpy, math, mathutils
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'; sc.display.shading.color_type = 'MATERIAL'
sc.render.resolution_x = 900; sc.render.resolution_y = 450
w = bpy.data.objects['Wheel']; hub = w.matrix_world.translation.copy()
for n in ('Sea_Preview', 'Deck', 'Hull'):
    o = bpy.data.objects.get(n)
    if n == 'Sea_Preview' and o: o.hide_render = True
cam = bpy.data.objects.new('C', bpy.data.cameras.new('C')); sc.collection.objects.link(cam); sc.camera = cam
cam.data.lens = 60
def shot(name, pos, target):
    cam.location = pos
    d = mathutils.Vector(target) - mathutils.Vector(pos)
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = r"%s\\%s.png" % (OUT, name)
    bpy.ops.render.render(write_still=True)
OUT = r"C:\\Users\\Victus\\Documents\\GitHub\\UnchartedOceans\\tools\\schooner_merge\\out"
shot("wheel_back", (hub.x + 0.0, hub.y + 2.6, hub.z + 0.35), hub)
shot("wheel_front3q", (hub.x + 1.6, hub.y - 1.6, hub.z + 0.6), hub)
shot("wheel_side", (hub.x + 2.6, hub.y, hub.z), hub)
