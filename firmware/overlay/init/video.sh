#!/bin/sh
# video.sh - H.265 RTSP server (rtsp://<ip>:554/vs0 and /vs1), respawned if it exits
export LD_LIBRARY_PATH=/lib:/app/lib
INI=/app/etc/rtsp.ini
[ -f /conf/rtsp.ini ] && INI=/conf/rtsp.ini    # optional override (bitrate, fps...)
sleep 3
while :; do
    /app/bin/rtspd -i $INI > /tmp/rtsp.log 2>&1
    echo "rtspd exited (code $?), restarting in 5 s" >> /tmp/rtsp.log
    sleep 5
done
