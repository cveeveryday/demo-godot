# Notes from the macro agent

## Project settings requested (platform agent)
The macro shot is a shallow-DOF rack focus; Godot's default hexagon/medium bokeh with no jitter
gives streaky, "doubled" far blur. Please set:

    rendering/camera/depth_of_field/depth_of_field_bokeh_shape = 2   ; circle
    rendering/camera/depth_of_field/depth_of_field_bokeh_quality = 3 ; high on desktop (med tier: 2, low: 1)
    rendering/camera/depth_of_field/depth_of_field_use_jitter = true  ; TAA resolves it

(or via Quality: RenderingServer.camera_attributes_set_dof_blur_bokeh_shape / _quality(q, true)).
shots/macro/macro.gd applies circle + high + jitter ONLY when run standalone, so it does not
touch global state inside the director.

## For the director
- Shot duration 6.5 s, fully deterministic in t (dust motes are a MultiMesh driven by a shot_t uniform).
- First 2-3 frames after activate() show slightly noisy DOF/dust until TAA converges; a cross-fade in hides it.
- The shot owns its WorldEnvironment (AgX tonemap, glow on, SSAO, light volumetric fog).
