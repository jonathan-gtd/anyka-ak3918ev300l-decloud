/* stepper.c - drive a 4-phase unipolar stepper (28BYJ-48 style) through 4 sysfs GPIOs, half-step sequence.
 * Usage: stepper P1,P2,P3,P4 STEPS [DELAY_US]
 *   STEPS > 0 one way, < 0 the other way. Coils are released at the end (no heating, no holding torque).
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

#define RAMP 120   /* half-steps of acceleration / deceleration */
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

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr, "usage: %s P1,P2,P3,P4 STEPS [DELAY_US]\n", argv[0]);
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

    int fd[4];
    char p[64], n[16];
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

    signal(SIGTERM, on_sig);
    signal(SIGINT, on_sig);

    /* The kernel only wakes sleepers on its 10 ms tick, so usleep() caps us at ~100 steps/s.
     * We busy-wait on the monotonic clock instead, at normal priority so video keeps running. */
    static const unsigned char seq[8] = { 0x1, 0x3, 0x2, 0x6, 0x4, 0xC, 0x8, 0x9 };   /* half-step */
    int dir = steps >= 0 ? 1 : -1;
    long total = steps >= 0 ? steps : -steps;
    int idx = 0;
    unsigned char cur = 0;
    long done = 0;
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    long long next = (long long)t.tv_sec * 1000000LL + t.tv_nsec / 1000;
    for (long s = 0; s < total && !g_stop; s++) {
        idx = (idx + dir + 8) & 7;
        unsigned char want = seq[idx];
        for (int i = 0; i < 4; i++) {             /* only write the coils that change */
            unsigned char b = 1u << i;
            if ((want ^ cur) & b)
                if (write(fd[i], (want & b) ? "1" : "0", 1) < 0) return 1;
        }
        cur = want;
        done++;
        /* trapezoidal ramp: start/stop at 2.5x the delay, reach full speed over RAMP steps */
        long left = total - s - 1, edge = s < left ? s : left;
        int d = edge >= RAMP ? delay : delay + (int)((long)(delay * 3 / 2) * (RAMP - edge) / RAMP);
        next += d;
        for (;;) {
            clock_gettime(CLOCK_MONOTONIC, &t);
            long long now = (long long)t.tv_sec * 1000000LL + t.tv_nsec / 1000;
            if (now >= next) break;
            if (next - now > 12000) usleep(next - now - 11000);   /* long waits: let the tick sleep */
            else sched_yield();
        }
    }
    for (int i = 0; i < 4; i++) { if (write(fd[i], "0", 1) < 0) return 1; close(fd[i]); }   /* release coils */
    printf("stepper %s: %ld half-steps done\n", argv[1], dir * done);
    return 0;
}
