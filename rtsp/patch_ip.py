import sys
p = sys.argv[1]
s = open(p).read()
helper = r'''
#include <sys/ioctl.h>
#include <net/if.h>
static int get_if_ip(const char *ifn, char *out){
    struct ifreq ifr; int fd=socket(AF_INET,SOCK_DGRAM,0); if(fd<0) return -1;
    memset(&ifr,0,sizeof(ifr)); strncpy(ifr.ifr_name, ifn, IFNAMSIZ-1); ifr.ifr_addr.sa_family=AF_INET;
    int r=ioctl(fd,SIOCGIFADDR,&ifr); close(fd); if(r<0) return -1;
    strcpy(out, inet_ntoa(((struct sockaddr_in*)&ifr.ifr_addr)->sin_addr)); return 0; }
'''
old = 'sprintf(pParam->cAddrIPv4,"172.16.2.43");'
new = ('if(get_if_ip("wlan0",pParam->cAddrIPv4)<0 && get_if_ip("eth0",pParam->cAddrIPv4)<0) '
       'strcpy(pParam->cAddrIPv4,"0.0.0.0"); printf("rtsp ip: %s' + '\\n' + '", pParam->cAddrIPv4);')
assert old in s, "hard-coded IP line not found"
s = s.replace('#define RTSP_URL_DEV "dev"', helper + '\n#define RTSP_URL_DEV "dev"', 1).replace(old, new, 1)
open(p, 'w').write(s)
print("patch IP OK")
