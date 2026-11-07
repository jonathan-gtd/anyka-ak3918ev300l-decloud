/* ptzmath.c - aim a ceiling-mounted dome PTZ at a point of the current image.
 *
 * The dome has two rotations: pan around the vertical axis and tilt around a horizontal axis. Tilt is counted in
 * half-steps from the "+" end stop (t = 0) and the horizon is at t = TILT_H (the dome axis at TILT_H - 1024 on this unit). Near the dome axis a pan
 * move rotates the image instead of shifting it, so image offsets cannot be mapped linearly to pan/tilt: we rebuild
 * the 3D direction of the target and convert it back to pan/tilt angles.
 *
 * Usage: ptzmath P T DX DY PAN_CENTER PAN_MAX TILT_H TILT_MAX HFOV VFOV DEG_PER_STEP
 *   P, T     current pan / tilt (half-steps)       DX, DY  target in the raw image, -1..1 (right / up positive)
 *   output:  "P2 T2"  new pan / tilt (half-steps, clamped to 0..PAN_MAX / 0..TILT_MAX)
 */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define RAD(d) ((d) * M_PI / 180.0)
#define DEG(r) ((r) * 180.0 / M_PI)

static double clampd(double v, double lo, double hi) { return v < lo ? lo : v > hi ? hi : v; }

int main(int argc, char **argv)
{
    if (argc != 12) {
        fprintf(stderr, "usage: %s P T DX DY PAN_CENTER PAN_MAX TILT_H TILT_MAX HFOV VFOV DEG_PER_STEP\n", argv[0]);
        return 1;
    }
    double P = atof(argv[1]), T = atof(argv[2]), dx = atof(argv[3]), dy = atof(argv[4]);
    double pc = atof(argv[5]), pmax = atof(argv[6]), th = atof(argv[7]), tmax = atof(argv[8]);
    double hfov = atof(argv[9]), vfov = atof(argv[10]), dps = atof(argv[11]);
    dx = clampd(dx, -1, 1); dy = clampd(dy, -1, 1);

    /* camera pose: azimuth th0 (pan, 0 = centre, + = right), depression a0 below the horizon (90 = straight down) */
    double th0 = RAD((P - pc) * dps);
    double a0  = RAD((th - T) * dps);

    /* model frame: the dome axis (t = 0) is -y, pan turns around y. forward f, image right r = pan "+" direction,
     * image up u = r x f, i.e. towards the dome axis: that is the raw sensor image (tilt "+" = image up, pan "+" =
     * image right, checked on the real camera). A 180-degree rotated image is handled by the caller (negate DX DY). */
    double f[3] = { cos(a0) * sin(th0), -sin(a0), cos(a0) * cos(th0) };
    double r[3] = { cos(th0), 0.0, -sin(th0) };
    double u[3] = { r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0] };

    /* ray through the target pixel (pinhole model) */
    double X = dx * tan(RAD(hfov / 2)), Y = dy * tan(RAD(vfov / 2));
    double d[3];
    for (int i = 0; i < 3; i++) d[i] = f[i] + X * r[i] + Y * u[i];

    double hz = sqrt(d[0] * d[0] + d[2] * d[2]);
    double th1 = hz > 1e-6 ? atan2(d[0], d[2]) : th0;   /* straight down: keep the azimuth */
    double a1  = atan2(-d[1], hz);                         /* depression below the horizon */

    /* keep the azimuth change the short way round */
    double dth = th1 - th0;
    while (dth >  M_PI) dth -= 2 * M_PI;
    while (dth < -M_PI) dth += 2 * M_PI;

    double P2 = clampd(P + DEG(dth) / dps, 0, pmax);
    double T2 = clampd(th - DEG(a1) / dps, 0, tmax);
    printf("%.0f %.0f\n", P2, T2);
    return 0;
}
