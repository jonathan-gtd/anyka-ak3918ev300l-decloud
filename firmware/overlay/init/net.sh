#!/bin/sh
# net.sh - Wi-Fi (persistent config in /conf), DHCP, SSH (dropbear), NTP, link watchdog
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/app/bin
CONF=/conf/wpa_supplicant.conf
HOST=$(cat /conf/hostname 2>/dev/null || echo cam-ptz)

[ -f $CONF ] || cp /app/etc/wpa_default.conf $CONF
hostname "$HOST"
# persistent root password (otherwise: root has no password)
[ -f /conf/shadow ] && mount --bind /conf/shadow /etc/shadow

insmod /app/drivers/atbm6132c_wifi_usb.ko wifi_bt_comb=1
i=0; while [ $i -lt 30 ] && ! ifconfig wlan0 >/dev/null 2>&1; do sleep 1; i=$((i+1)); done
ifconfig wlan0 up
mkdir -p /var/run/wpa_supplicant

wifi_up() {
    killall -9 wpa_supplicant udhcpc 2>/dev/null
    sleep 1
    /app/bin/wpa_supplicant -Dnl80211 -i wlan0 -c $CONF -B -P /tmp/wpa.pid
    udhcpc -i wlan0 -s /usr/share/udhcpc/default.script -b -x hostname:$HOST -p /tmp/udhcpc.pid
    sleep 5
    /app/bin/notso wlan0 >/dev/null 2>&1   # TSO/GSO/GRO/SG off on the ATBM driver
}
wifi_up

# --- SSH (dropbear): keys live in /conf/dropbear ---
mkdir -p /conf/dropbear && chmod 700 /conf/dropbear
[ -f /conf/dropbear/authorized_keys ] || cp /app/etc/authorized_keys /conf/dropbear/authorized_keys 2>/dev/null
chmod 600 /conf/dropbear/authorized_keys 2>/dev/null
[ -f /conf/dropbear/ed25519_host_key ] || /app/bin/dropbearkey -t ed25519 -f /conf/dropbear/ed25519_host_key >/dev/null 2>&1
if /app/bin/dropbear -r /conf/dropbear/ed25519_host_key -p 22; then
    echo "dropbear OK"
else
    telnetd -l /bin/login       # fallback only if SSH fails to start
fi

# --- time: DHCP gateway first, then public pool ---
GW=$(ip route 2>/dev/null | awk '/^default/ {print $3; exit}')
/app/bin/ntpd ${GW:+-p $GW} -p pool.ntp.org

# link watchdog: no IP / not associated for ~1 min -> restart Wi-Fi
bad=0
while :; do
    sleep 20
    if /app/bin/wpa_cli -i wlan0 status 2>/dev/null | grep -q "wpa_state=COMPLETED" && ifconfig wlan0 | grep -q "inet addr"; then
        bad=0
    else
        bad=$((bad+1))
        [ $bad -ge 3 ] && { wifi_up; bad=0; }
    fi
done
