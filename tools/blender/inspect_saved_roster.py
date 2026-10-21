"""Render the saved editable roster in Blender for authoring-source inspection.

Does not regenerate geometry, export assets, or save changes to the .blend files.
Workbench shows vertex colours and form; Godot captures cover the runtime shader.
Run under the shared heavy-job lock with Blender's caches redirected to B:.
"""
import argparse
import hashlib
import json
import pathlib
import sys

import bpy
from mathutils import Vector

ROOT = pathlib.Path(__file__).resolve().parents[2]
IDS = ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters", "f_varga", "f_knell"]


def inspect(fighter_id, out):
    source = ROOT / "tools" / "blender" / (fighter_id + ".blend")
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    scene = bpy.context.scene
    body = [obj for obj in scene.objects if obj.type == "MESH" and obj.get("cw_role") == "body"]
    if not body or scene.get("cw_id") != fighter_id:
        raise ValueError("Wrong or empty source: " + fighter_id)
    for obj in scene.objects:
        if obj.type == "MESH":
            obj.hide_render = obj not in body
    corners = [obj.matrix_world @ Vector(corner) for obj in body for corner in obj.bound_box]
    lo = Vector([min(v[i] for v in corners) for i in range(3)])
    hi = Vector([max(v[i] for v in corners) for i in range(3)])
    centre = (lo + hi) * .5
    extent = hi - lo
    scale = max(extent.z, extent.x * 1.25, extent.y * 1.25) * 1.23
    camera_data = bpy.data.cameras.new("Inspection camera")
    camera = bpy.data.objects.new("Inspection camera", camera_data)
    scene.collection.objects.link(camera)
    camera.location = centre + Vector((.28, -1, .20)).normalized() * scale * 3
    camera.rotation_euler = (centre - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = scale
    scene.camera = camera
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "VERTEX"
    shading.show_shadows = True
    shading.show_cavity = True
    shading.cavity_type = "BOTH"
    shading.background_type = "WORLD"
    scene.world.color = (.035, .045, .065)
    scene.render.resolution_x = 640
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    target = out / (fighter_id + "-blender.png")
    scene.render.filepath = str(target)
    bpy.ops.render.render(write_still=True)
    after = hashlib.sha256(source.read_bytes()).hexdigest()
    if before != after:
        raise ValueError("Source changed during inspection: " + fighter_id)
    return dict(fighter=fighter_id, source_sha256=before, source_unchanged=True,
                body_objects=len(body), view_bones=len(json.loads(scene.get("cw_view_bones", "[]"))),
                image=target.name, image_sha256=hashlib.sha256(target.read_bytes()).hexdigest())


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    output = pathlib.Path(args.out).resolve()
    output.mkdir(parents=True, exist_ok=True)
    reports = [inspect(fighter_id, output) for fighter_id in IDS]
    (output / "blender-inspection.json").write_text(json.dumps(reports, indent=2) + "\n", encoding="utf-8")
