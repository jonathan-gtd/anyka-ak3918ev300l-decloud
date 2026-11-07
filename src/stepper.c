/* stepper.c - drive a 4-phase unipolar stepper (28BYJ-48 style) through 4 sysfs GPIOs.
 * Usage: stepper P1,P2,P3,P4 STEPS [DELAY_US [half|full [RAMP]]]
 *   RAMP: half-steps of acceleration and deceleration (constant acceleration from half speed), 0 = none (default)
 *   STEPS in half-steps, > 0 one way, < 0 the other way. DELAY_US per half-step (the speed is the same in both modes).
 *   half: 8-state half-step sequence (finest, but the one-coil states have ~70% of the torque)
 *   full: two-coil full steps only (default, ~1.4x the torque of one coil, 2 half-steps per step)
 * The coil phase is remembered between runs (/tmp/stepper.P1.phase): starting from a wrong phase makes the rotor
 * jump or go backwards on the first step and loses position at every move. The current phase is energized briefly
 * before moving and after the last step (rotor locked in place), then the coils are released (no heating).
 * Example: stepper 24,25,26,27 400 1500
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sched.h>
#include <signal.h>
#include <time.h>
#include <math.h>

#define SETTLE_US 40000
static volatile sig_atomic_t g_stop = 0;
static void on_sig(int s) { (void)s; g_stop = 1; }   /* SIGTERM/SIGINT: stop cleanly, release coils, report steps done */

static int wr(const char *path, const char *val)
{
    int fd = open(path, O_WRONLY);
    if (fd < 0) return -1;
    int r = write(fd, val, strlen(val));
    close(fd);
    return r < 0 ? -1 : 0;
}

static const unsigned char seq[8] = { 0x1, 0x3, 0x2, 0x6, 0x4, 0xC, 0x8, 0x9 };   /* odd index = two coils */
static int fd[4];
static unsigned char cur = 0;

static int coils(unsigned char want)
{
    for (int i = 0; i < 4; i++) {             /* only write the coils that change */
        unsigned char b = 1u << i;
        if ((want ^ cur) & b)
            if (write(fd[i], (want & b) ? "1" : "0", 1) < 0) return -1;
    }
    cur = want;
    return 0;
}

static long long now_us(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (long long)t.tv_sec * 1000000LL + t.tv_nsec / 1000;
}

/* The kernel only wakes sleepers on its 10 ms tick, so usleep() caps us at ~100 steps/s.
 * We busy-wait on the monotonic clock instead, at normal priority so video keeps running. */
static void wait_until(long long next)
{
    for (;;) {
        long long now = now_us();
        if (now >= next) break;
        if (next - now > 12000) usleep(next - now - 11000);   /* long waits: let the tick sleep */
        else sched_yield();
    }
}

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr, "usage: %s P1,P2,P3,P4 STEPS [DELAY_US [half|full [RAMP]]]\n", argv[0]);
        return 1;
    }
    int pin[4];
    if (sscanf(argv[1], "%d,%d,%d,%d", &pin[0], &pin[1], &pin[2], &pin[3]) != 4) {
        fprintf(stderr, "need 4 comma-separated GPIO numbers\n");
        return 1;
    }
    long steps = atol(argv[2]);
    int delay = argc > 3 ? atoi(argv[3]) : 1200;
    if (delay < 300) delay = 300;
    int full = !(argc > 4 && strcmp(argv[4], "half") == 0);
    long ramp = argc > 5 ? atol(argv[5]) : 0;
    if (ramp < 0) ramp = 0;

    char p[64], n[16], phf[64];
    for (int i = 0; i < 4; i++) {
        snprintf(p, sizeof(p), "/sys/class/gpio/gpio%d", pin[i]);
        if (access(p, F_OK) != 0) {
            snprintf(n, sizeof(n), "%d", pin[i]);
            wr("/sys/class/gpio/export", n);
        }
        snprintf(p, sizeof(p), "/sys/class/gpio/gpio%d/direction", pin[i]);
        if (wr(p, "low") != 0) { fprintf(stderr, "gpio%d: cannot set output\n", pin[i]); return 1; }
        snprintf(p, sizeof(p), "/sys/class/gpio/gpio%d/value", pin[i]);
        fd[i] = open(p, O_WRONLY);
        if (fd[i] < 0) { fprintf(stderr, "gpio%d: cannot open value\n", pin[i]); return 1; }
    }

    /* phase where the rotor was left by the previous run */
    int idx = 1;
    snprintf(phf, sizeof(phf), "/tmp/stepper.%d.phase", pin[0]);
    FILE *f = fopen(phf, "r");
    if (f) { if (fscanf(f, "%d", &idx) != 1) idx = 1; fclose(f); idx &= 7; }

    signal(SIGTERM, on_sig);
    signal(SIGINT, on_sig);

    int dir = steps >= 0 ? 1 : -1;
    long total = steps >= 0 ? steps : -steps;
    long done = 0;

    if (total > 0) {
        if (coils(seq[idx]) < 0) return 1;     /* lock the rotor on its current phase */
        usleep(SETTLE_US);
    }
    long long next = now_us();
    while (done < total && !g_stop) {
        int inc = 1;
        if (full && (idx & 1) && total - done >= 2) inc = 2;   /* two-coil -> next two-coil state */
        else if (full && (idx & 1)) break;                     /* one half-step left: stay on a two-coil state */
        idx = (idx + dir * inc + 8) & 7;
        if (coils(seq[idx]) < 0) return 1;
        done += inc;
        /* optional ramp, constant acceleration: v^2 grows linearly with distance from v0 = vmax/2 to vmax over
         * ramp half-steps (and back down at the end). ramp = 0: constant speed (start/stop at full speed). */
        long left = total - done, edge = done - inc < left ? done - inc : left;
        long d = delay;
        if (ramp > 0 && edge < ramp)
            d = (long)(delay / sqrt(0.25 + 0.75 * (double)edge / ramp));
        next += d * inc;
        wait_until(next);
    }
    if (total > 0) usleep(SETTLE_US);          /* let the rotor settle on the last phase */
    for (int i = 0; i < 4; i++) { if (write(fd[i], "0", 1) < 0) return 1; close(fd[i]); }   /* release coils */
    f = fopen(phf, "w");
    if (f) { fprintf(f, "%d\n", idx); fclose(f); }
    printf("stepper %s: %ld half-steps done\n", argv[1], dir * done);
    return 0;
}
