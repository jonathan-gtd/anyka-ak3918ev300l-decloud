#!/bin/sh
# app_init.sh - de-clouded firmware entry point (started by /etc/init.d/rc.local of the stock rootfs)
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/app/bin
export LD_LIBRARY_PATH=/lib:/app/lib
export TZ="CET-1CEST,M3.5.0,M10.5.0/3"
ulimit -s 256

echo 1 > /proc/sys/vm/overcommit_memory
echo 5 > /proc/sys/vm/dirty_background_ratio
echo 10 > /proc/sys/vm/dirty_ratio
echo 50 > /proc/sys/vm/dirty_writeback_centisecs
echo 100 > /proc/sys/vm/dirty_expire_centisecs
echo 10000 > /proc/sys/vm/vfs_cache_pressure
echo 1 > /proc/sys/kernel/panic_on_oops
echo 4 > /proc/sys/kernel/printk

[ -e /app/lib/firmware/atbm_txpwer_dcxo_cfg.txt ] && cp /app/lib/firmware/atbm_txpwer_dcxo_cfg.txt /tmp/

# hardware watchdog (nowayout): kept armed, fed by wdkeep -> if wdkeep dies the camera reboots within 60 s
/app/bin/wdkeep 60

insmod /app/drivers/exfat.ko 2>/dev/null
/app/ak/load.sh            # vendor modules (isp, venc, i2c, pcm...) + gv-gpio
sh /app/ak/sensor_drin.sh  # probes I2C 0x40 and loads the sensor module (F26a = id 0852); the cloud app used to do this

[ -f /conf/daynight.mode ] && cp /conf/daynight.mode /tmp/daynight.mode   # day/night default (auto otherwise)
/app/bin/ptz home > /dev/null 2>&1 &   # pan + tilt into their end stops, then home preset

/app/init/net.sh &         # Wi-Fi + SSH + NTP
/app/init/video.sh &       # RTSP server (respawned) + JPEG snapshot
/app/init/web.sh &         # HTTP :80 (snapshot.jpg, ONVIF) + WS-Discovery
[ -x /app/init/ircut.sh ] && /app/init/ircut.sh &
