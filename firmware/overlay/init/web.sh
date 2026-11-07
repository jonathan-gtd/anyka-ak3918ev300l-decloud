#!/bin/sh
# web.sh - HTTP on port 80 (JPEG snapshot + ONVIF CGI) and ONVIF WS-Discovery
#   http://<ip>/snapshot.jpg           latest JPEG (written by rtspd, 1 fps)
#   http://<ip>/onvif/device_service   ONVIF (onvif_simple_server, Media2/Profile T for H.265)
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/app/bin
mkdir -p /tmp/onvif

# wait for Wi-Fi (MAC, hostname and address are needed below)
i=0; while [ $i -lt 90 ] && ! ifconfig wlan0 2>/dev/null | grep -q "inet addr"; do sleep 2; i=$((i+1)); done

# ONVIF config: /conf override, else the default; HOSTNAME and SERIAL (wlan0 MAC) filled in
CONF=/app/etc/onvif_simple_server.conf
[ -f /conf/onvif_simple_server.conf ] && CONF=/conf/onvif_simple_server.conf
MAC=$(cat /sys/class/net/wlan0/address 2>/dev/null | tr -d ':')
sed -e "s/^serial_num=SERIAL/serial_num=${MAC:-000000000000}/" -e "s/HOSTNAME/$(hostname)/" $CONF > /tmp/onvif/onvif_simple_server.conf
# ONVIF authentication (WS-UsernameToken digest): /conf/onvif.auth holds "user=NAME" and "password=SECRET"
# (no | & or \ in the values). Without that file ONVIF is open.
if [ -f /conf/onvif.auth ]; then
    U=$(sed -n 's/^user=//p' /conf/onvif.auth); P=$(sed -n 's/^password=//p' /conf/onvif.auth)
    [ -n "$U" ] && [ -n "$P" ] && sed -i -e "s|^#*user=.*|user=$U|" -e "s|^#*password=.*|password=$P|" /tmp/onvif/onvif_simple_server.conf
fi
chmod 600 /tmp/onvif/onvif_simple_server.conf

httpd -p 80 -h /app/www

SCOPES=$(grep '^scope=' /tmp/onvif/onvif_simple_server.conf | cut -d= -f2- | tr '\n' ' ')
wsd_simple_server -i wlan0 -x "http://%s/onvif/device_service" -m AK3918EV300L-PTZ -n Anyka \
    -s "$SCOPES" -p /tmp/onvif/wsd.pid -t /app/www/wsd_files
