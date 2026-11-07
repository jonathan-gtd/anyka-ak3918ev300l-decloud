/* ptzmath.c - aim a dome PTZ at a point of the current image.
 *
 * The dome has two rotations: pan around the vertical axis and tilt around a horizontal axis. Near the dome axis a
 * pan move rotates the image instead of shifting it, so image offsets cannot be mapped linearly to pan/tilt: we
 * rebuild the 3D direction of the target and convert it back to pan/tilt angles.
 *
 * Usage: ptzmath P T DX DY PAN_CENTER PAN_MAX TILT_H TILT_MAX HFOV VFOV DEG_PER_STEP PAN_LEFT TILT_DOWN
 *   P, T       current pan / tilt (half-steps)
 *   DX, DY     target in the image, -1..1 (right / up positive), image upright
 *   TILT_H     tilt position where the camera looks at the horizon
 *   PAN_LEFT   1 if pan "+" turns the view to the left, 0 if to the right
 *   TILT_DOWN  1 if tilt "+" turns the view down, 0 if up
 *   output:    "P2 T2"  new pan / tilt (half-steps, clamped to 0..PAN_MAX / 0..TILT_MAX)
 */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define RAD(d) ((d) * M_PI / 180.0)
#define DEG(r) ((r) * 180.0 / M_PI)

static double clampd(double v, double lo, double hi) { return v < lo ? lo : v > hi ? hi : v; }

int main(int argc, char **argv)
{
    if (argc != 14) {
        fprintf(stderr, "usage: %s P T DX DY PAN_CENTER PAN_MAX TILT_H TILT_MAX HFOV VFOV DEG_PER_STEP PAN_LEFT TILT_DOWN\n",
                argv[0]);
        return 1;
    }
    double P = atof(argv[1]), T = atof(argv[2]), dx = atof(argv[3]), dy = atof(argv[4]);
    double pc = atof(argv[5]), pmax = atof(argv[6]), th = atof(argv[7]), tmax = atof(argv[8]);
    double hfov = atof(argv[9]), vfov = atof(argv[10]), dps = atof(argv[11]);
    double ps = atoi(argv[12]) ? 1.0 : -1.0;   /* + : pan "+" = view left (= azimuth increasing below) */
    double ts = atoi(argv[13]) ? 1.0 : -1.0;   /* + : tilt "+" = view down (= depression increasing) */
    dx = clampd(dx, -1, 1); dy = clampd(dy, -1, 1);

    /* camera pose: azimuth th0 (increasing = turning left), depression a0 below the horizon (90 = straight down) */
    double th0 = RAD(ps * (P - pc) * dps);
    double a0  = RAD(ts * (T - th) * dps);

    /* right-handed world, y up. forward f; image right R and image up U (an upright camera looking along +z has
     * +x on its left, hence R = -dF/dth) */
    double f[3] = { cos(a0) * sin(th0), -sin(a0), cos(a0) * cos(th0) };
    double R[3] = { -cos(th0), 0.0, sin(th0) };
    double U[3] = { R[1] * f[2] - R[2] * f[1], R[2] * f[0] - R[0] * f[2], R[0] * f[1] - R[1] * f[0] };

    /* ray through the target pixel. f-theta (equidistant) lens model: the angle from the optical axis grows linearly
     * with the distance to the image centre, which fits this wide-angle lens with strong barrel distortion far
     * better than a pinhole. HFOV / VFOV are the full angles across the image (same angular scale per pixel). */
    double ax = dx * RAD(hfov / 2), ay = dy * RAD(vfov / 2);
    double rr = sqrt(ax * ax + ay * ay), k = rr > 1e-9 ? tan(rr) / rr : 1.0;
    double X = ax * k, Y = ay * k;
    double d[3];
    for (int i = 0; i < 3; i++) d[i] = f[i] + X * R[i] + Y * U[i];

    double hz = sqrt(d[0] * d[0] + d[2] * d[2]);
    double th1 = hz > 1e-6 ? atan2(d[0], d[2]) : th0;   /* straight down: keep the azimuth */
    double a1  = atan2(-d[1], hz);                         /* depression below the horizon */

    /* keep the azimuth change the short way round */
    double dth = th1 - th0;
    while (dth >  M_PI) dth -= 2 * M_PI;
    while (dth < -M_PI) dth += 2 * M_PI;

    double P2 = clampd(P + ps * DEG(dth) / dps, 0, pmax);
    double T2 = clampd(th + ts * DEG(a1) / dps, 0, tmax);
    printf("%.0f %.0f\n", P2, T2);
    return 0;
}
