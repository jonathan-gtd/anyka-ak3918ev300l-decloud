import sys
# onvif_simple_server: RelativeMove in TranslationSpaceFov assumes a 63 deg horizontal FOV and that max_step_x
# covers 360 deg. Make both build-time settings (PTZ_HFOV in degrees, PTZ_DEG_PER_STEP for the pan unit) so that
# FOV-relative moves (Frigate autotracking) turn the camera by the right angle.
p = sys.argv[1]
s = open(p).read()
pairs = [
    ('dx = (dx / 100.0) * (63.0 / 2.0);', 'dx = (dx / 100.0) * (PTZ_HFOV / 2.0);'),
    ('dx = dx / (360.0 / service_ctx.ptz_node.max_step_x);', 'dx = dx / PTZ_DEG_PER_STEP;'),
]
for a, b in pairs:
    assert s.count(a) == 1, (a, s.count(a))
    s = s.replace(a, b, 1)
s = '#ifndef PTZ_HFOV\n#define PTZ_HFOV 63.0\n#endif\n#ifndef PTZ_DEG_PER_STEP\n#define PTZ_DEG_PER_STEP (360.0 / service_ctx.ptz_node.max_step_x)\n#endif\n' + s
open(p, 'w').write(s)
print("patch onvif FOV OK")
