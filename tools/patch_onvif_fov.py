import sys
# onvif_simple_server: RelativeMove in TranslationSpaceFov (used by Frigate autotracking).
# Upstream converts the FOV offset to steps with fixed approximations (63 x 37 deg FOV, 360/180 deg spans) and
# treats pan and tilt as independent translations. A dome PTZ is two rotations, so instead we hand the raw
# normalized offset (-1..1, right / up positive) to "ptz fov DX DY", which solves the spherical geometry
# (see src/ptzmath.c) from the current pan and tilt.
p = sys.argv[1]
s = open(p).read()
start = s.index('                    // Convert -100/+100 to degrees values based on FOV')
end = s.index('snprintf(sys_command, sizeof(sys_command), service_ctx.ptz_node.jump_to_rel, dx, dy, 0);', start)
end = s.index('\n', end) + 1
s = s[:start] + (
    '                    /* dome PTZ: two rotations -> exact solve in "ptz fov" (anyka-ak3918ev300l-decloud) */\n'
    '                    snprintf(sys_command, sizeof(sys_command), "/app/bin/ptz fov %f %f", dx / 100.0, dy / 100.0);\n'
) + s[end:]
open(p, 'w').write(s)
print("patch onvif FOV (spherical) OK")
