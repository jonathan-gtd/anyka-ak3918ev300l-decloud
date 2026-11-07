#!/bin/bash
# mkapp.sh - build the de-clouded app partition (squashfs) from the stock one.
# Inputs : $WORK/vendor/app.sqfs (from extract_dump.sh), $WORK/out/{rtspd,librtsp_server.so,wdkeep,notso,tools/*}
#          $WORK/local/wpa_supplicant.conf (your Wi-Fi) and $WORK/local/authorized_keys (your SSH public key)
# Output : $WORK/out/app.sqfs + app.sqfs.md5
set -e
REPO=${REPO:-$(cd "$(dirname "$0")/.." && pwd)}
WORK=${WORK:-/work}
OUT=$WORK/out
LOCAL=$WORK/local
LIMIT=$((0x4A0000))               # size of mtd4 (app)
T=/tmp/app_build

for f in $WORK/vendor/app.sqfs $OUT/rtspd $OUT/librtsp_server.so $OUT/wdkeep $OUT/notso $OUT/stepper $OUT/ptzmath $OUT/tools/busybox $OUT/tools/dropbearmulti $LOCAL/wpa_supplicant.conf; do
    [ -e "$f" ] || { echo "missing: $f"; exit 1; }
done

rm -rf $T && unsquashfs -q -d $T $WORK/vendor/app.sqfs >/dev/null
cd $T

# --- remove the cloud ---
rm -f bin/ipc bin/daemon bin/update bin/log bin/wifi
rm -f lib/libgv_*.so* lib/libhome_security_sdk.so lib/libgv_device_id_decryption.so*
rm -f drivers/atbm613x_wifi_usb.ko          # this board has the ATBM6132C
rm -rf sound music

# --- add the homemade firmware ---
mkdir -p etc
cp $REPO/firmware/overlay/init/*.sh init/
cp $REPO/firmware/overlay/etc/rtsp.ini etc/
cp $REPO/firmware/overlay/bin/cam-update bin/
cp $LOCAL/wpa_supplicant.conf etc/wpa_default.conf
[ -f $LOCAL/authorized_keys ] && cp $LOCAL/authorized_keys etc/authorized_keys || : > etc/authorized_keys
cp $OUT/rtspd bin/rtspd
cp $OUT/librtsp_server.so lib/
cp $OUT/wdkeep $OUT/notso $OUT/stepper $OUT/ptzmath bin/
cp $REPO/firmware/overlay/bin/ptz $REPO/firmware/overlay/bin/daynight bin/

# full static busybox: links only for applets missing from the stock rootfs busybox
cp $OUT/tools/busybox bin/busybox
find $WORK/vendor/rootfs -type l -lname "*busybox" -printf "%f\n" | sort -u > /tmp/rootfs_applets
for a in $(comm -13 /tmp/rootfs_applets <(sort -u $OUT/tools/busybox.applets)); do
    [ -e bin/$a ] || ln -s busybox bin/$a
done
cp $OUT/tools/dropbearmulti bin/dropbearmulti
for a in dropbear dbclient dropbearkey scp ssh; do ln -sf dropbearmulti bin/$a; done

# --- web: JPEG snapshot + ONVIF (onvif_simple_server CGI under busybox httpd) + WS-Discovery ---
if [ -d $OUT/onvif ]; then
    mkdir -p www/onvif
    cp $OUT/onvif/onvif_simple_server www/onvif/
    for d in device_service_files media_service_files media2_service_files deviceio_service_files events_service_files ptz_service_files generic_files; do
        cp -r $OUT/onvif/templates/$d www/onvif/
    done
    for s in device_service media_service media2_service deviceio_service events_service ptz_service; do ln -s onvif_simple_server www/onvif/$s; done
    cp -r $OUT/onvif/templates/wsd_files www/wsd_files
    cp $OUT/onvif/wsd_simple_server bin/
    cp $OUT/onvif/LICENSE www/onvif/LICENSE.onvif_simple_server
    cp $REPO/firmware/overlay/etc/onvif_simple_server.conf etc/
    chmod 755 www/onvif/onvif_simple_server bin/wsd_simple_server
fi
mkdir -p www
ln -sf /tmp/snapshot.jpg www/snapshot.jpg

sed -i 's/\r$//' init/*.sh etc/* bin/cam-update bin/ptz bin/daynight
chmod 755 init/*.sh bin/rtspd bin/wdkeep bin/notso bin/stepper bin/ptzmath bin/ptz bin/daynight bin/cam-update bin/busybox bin/dropbearmulti
chmod 644 etc/*

rm -f $OUT/app.sqfs
mksquashfs $T $OUT/app.sqfs -comp xz -b 65536 -noappend -all-root -no-progress >/dev/null
SZ=$(stat -c %s $OUT/app.sqfs)
echo "app.sqfs = $SZ bytes (limit $LIMIT, free $((LIMIT-SZ)))"
[ $SZ -le $LIMIT ] || { echo "TOO BIG"; exit 1; }
(cd $OUT && md5sum app.sqfs > app.sqfs.md5 && cat app.sqfs.md5)
