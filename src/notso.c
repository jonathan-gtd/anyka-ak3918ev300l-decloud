/* notso.c - show then disable TSO / GSO / GRO / SG on an interface (ethtool -K equivalent) */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <linux/ethtool.h>
#include <linux/sockios.h>

static int ethval(int fd, const char *ifn, unsigned cmd, unsigned *val, int set)
{
    struct ifreq ifr;
    struct ethtool_value ev;
    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, ifn, IFNAMSIZ - 1);
    ev.cmd = cmd;
    ev.data = set ? *val : 0;
    ifr.ifr_data = (void *)&ev;
    if (ioctl(fd, SIOCETHTOOL, &ifr) < 0) return -1;
    if (!set) *val = ev.data;
    return 0;
}

int main(int argc, char **argv)
{
    const char *ifn = argc > 1 ? argv[1] : "wlan0";
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) { perror("socket"); return 1; }
    struct { const char *name; unsigned get, set; } f[] = {
        { "tso", ETHTOOL_GTSO, ETHTOOL_STSO },
        { "gso", ETHTOOL_GGSO, ETHTOOL_SGSO },
        { "gro", ETHTOOL_GGRO, ETHTOOL_SGRO },
        { "sg",  ETHTOOL_GSG,  ETHTOOL_SSG  },
    };
    for (unsigned i = 0; i < sizeof(f) / sizeof(f[0]); i++) {
        unsigned v = 0, z = 0;
        int g = ethval(fd, ifn, f[i].get, &v, 0);
        int s = ethval(fd, ifn, f[i].set, &z, 1);
        unsigned after = 99;
        ethval(fd, ifn, f[i].get, &after, 0);
        printf("notso %s %s: before=%s after=%s%s\n", ifn, f[i].name,
               g ? "?" : (v ? "on" : "off"),
               after == 99 ? "?" : (after ? "on" : "off"),
               s ? " (set refused)" : "");
    }
    close(fd);
    return 0;
}
