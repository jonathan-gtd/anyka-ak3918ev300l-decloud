/* wdkeep.c - keep /dev/watchdog fed reliably.
 * - opens /dev/watchdog once and keeps it open
 * - tries to extend the timeout (WDIOC_SETTIMEOUT)
 * - runs SCHED_FIFO so encode + Wi-Fi load can never starve it
 * - feeds with WDIOC_KEEPALIVE every timeout/3
 * Usage: wdkeep [timeout_s]   (default 60) - forks to the background
 */
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/watchdog.h>
#include <sched.h>
#include <sys/mman.h>

int main(int argc, char **argv)
{
    int to = argc > 1 ? atoi(argv[1]) : 60;

    pid_t pid = fork();
    if (pid < 0) { perror("fork"); return 1; }
    if (pid > 0) { printf("wdkeep started pid=%d requested_timeout=%ds\n", pid, to); return 0; }

    /* child: daemon */
    setsid();

    int fd = open("/dev/watchdog", O_WRONLY);
    if (fd < 0) { fd = open("/dev/watchdog0", O_WRONLY); }
    if (fd < 0) { perror("open watchdog"); _exit(1); }

    int cur = 0;
    if (ioctl(fd, WDIOC_SETTIMEOUT, &to) == 0)
        ioctl(fd, WDIOC_GETTIMEOUT, &cur);

    FILE *f = fopen("/tmp/wdkeep.log", "w");
    if (f) { fprintf(f, "wdkeep: requested timeout=%d, effective=%d\n", to, cur); fflush(f); }

    /* real-time priority + locked memory so it is never starved */
    struct sched_param sp; sp.sched_priority = 50;
    sched_setscheduler(0, SCHED_FIFO, &sp);
    mlockall(MCL_CURRENT | MCL_FUTURE);

    int feed_int = cur > 3 ? cur / 3 : 1;
    for (;;) {
        ioctl(fd, WDIOC_KEEPALIVE, 0);
        sleep(feed_int);
    }
}
