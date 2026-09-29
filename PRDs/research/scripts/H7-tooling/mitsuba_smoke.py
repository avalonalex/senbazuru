import time, sys, mitsuba as mi
mi.set_variant("scalar_rgb")
scene = mi.load_dict({
    "type": "scene",
    "integrator": {"type": "path", "max_depth": 4},
    "sensor": {"type": "perspective", "fov": 35,
               "to_world": mi.ScalarTransform4f().look_at(origin=[1.9, -2.2, 1.6], target=[0.5, 0.5, 0.0], up=[0, 0, 1]),
               "film": {"type": "hdrfilm", "width": 400, "height": 300},
               "sampler": {"type": "independent", "sample_count": 32}},
    "paper": {"type": "obj", "filename": sys.argv[1], "face_normals": False,
              "bsdf": {"type": "twosided", "bsdf": {"type": "diffuse", "reflectance": {"type": "rgb", "value": [0.9, 0.88, 0.8]}}}},
    "light": {"type": "constant", "radiance": {"type": "rgb", "value": 0.8}},
})
t0 = time.perf_counter(); img = mi.render(scene); t1 = time.perf_counter()
mi.util.write_bitmap(sys.argv[2], img)
print("mitsuba", mi.__version__, "variant scalar_rgb", "seconds", round(t1 - t0, 2))
