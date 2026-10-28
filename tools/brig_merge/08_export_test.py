
import bpy, os
out = os.environ["GLB_OUT"]
print("EXPORT visible meshes:", sum(1 for o in bpy.context.view_layer.objects if o.type == 'MESH' and o.visible_get()), "| hidden source objs:", sum(1 for o in bpy.data.collections["Brig_Source"].objects))
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_visible=True, export_apply=True, export_extras=True, export_lights=True, export_cameras=False,
    export_yup=True, export_texcoords=True, export_normals=True, export_colors=True, export_materials='EXPORT', export_image_format='AUTO', export_morph=True, export_morph_normal=False,
    export_skins=False, export_animations=False, export_draco_mesh_compression_enable=False)
print("EXPORT done", os.path.getsize(out))
