#!/bin/sh
# up.sh - DEV/LIVE MODE: download and start the RTSP server from RAM
# Optional: K0 (main stream kbps), K1 (sub stream kbps), F (fps), W0/H0 (main resolution)
SRV=${SRV:?set SRV=http://your-server:port}
K0=${K0:-700}; K1=${K1:-250}; F=${F:-15}; W0=${W0:-1920}; H0=${H0:-1080}
export LD_LIBRARY_PATH=/tmp:/app/lib:/lib
cd /tmp
killall -9 rtspd 2>/dev/null
i=0; while ps | grep -v grep | grep -q "bin/rtspd" && [ $i -lt 20 ]; do sleep 1; i=$((i+1)); done
sleep 2
[ -x /tmp/rtspd ] || { wget -q -O /tmp/rtspd $SRV/rtspd; chmod +x /tmp/rtspd; }
[ -f /tmp/librtsp_server.so ] || wget -q -O /tmp/librtsp_server.so $SRV/librtsp_server.so
rm -f /tmp/r.ini
for l in '[camera]' 'mode = 0' 'sensor_cnt = 1' \
         '[single_cfg]' 'isp_conf = /app/ak/sensor/isp_f26a_mipi_2lane_av100_3mp.conf' 'single_dev = 0' \
         '[video0]' 'code_type = h.265' "width = $W0" "height = $H0" "fps = $F" "target_kbps = $K0" \
         '[video1]' 'code_type = h.265' 'width = 640' 'height = 360' "fps = $F" "target_kbps = $K1" \
         '[audio]' 'code_type = aac' 'sample_rate = 16000'; do
    echo "$l" >> /tmp/r.ini
done
/tmp/rtspd -i /tmp/r.ini > /mnt/sdcard/r.log 2>&1 &
sleep 3
echo "UP_DONE K0=$K0 K1=$K1 F=$F ${W0}x${H0} $(grep MemAvailable /proc/meminfo)"
