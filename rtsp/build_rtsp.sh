#!/bin/bash
# build_rtsp.sh - build the RTSP server (vendor SDK "rtsp" sample + our patches) against the libs of YOUR dump.
# Needs : $SDK (AnyCloud39AV130 SDK tree: platform/include, platform/lib/librtsp_server.so, platform/sample/rtsp)
#         $WORK/vendor/app/lib (from firmware/extract_dump.sh)
# Output: $WORK/out/rtspd, $WORK/out/librtsp_server.so      DBG=1 adds frame traces (PUSH/GETV)
set -e
REPO=${REPO:-$(cd "$(dirname "$0")/.." && pwd)}
WORK=${WORK:-/work}
SDK=${SDK:-$WORK/sdk/ANYKA_130L_SDK}
LIBS_DIR=$WORK/vendor/app/lib
XT=${XT:-/opt/xt/x-tools/arm-unknown-linux-uclibcgnueabi/bin}
GCC=$XT/arm-unknown-linux-uclibcgnueabi-gcc
OUT=$WORK/out; mkdir -p $OUT
B=/tmp/rtsp_build; rm -rf $B && mkdir -p $B/lib && cd $B

cp $SDK/platform/sample/rtsp/*.c $SDK/platform/sample/rtsp/*.h .     # never patch the SDK in place
cp $SDK/platform/lib/librtsp_server.so lib/
python3 $REPO/rtsp/patch_enc_type.py ak_rtsp_stream.c        # enc_type override in ini + drop AENC codec registration
python3 $REPO/rtsp/patch_ip.py ak_rtsp_server_sample.c       # announce the wlan0 IP instead of a hard-coded one
python3 $REPO/rtsp/patch_noaudio.py ak_rtsp_stream.c         # no audio track (a dead one stalls librtsp_server)
python3 $REPO/rtsp/patch_snapshot.py ak_rtsp_stream.c        # JPEG snapshot thread (1 fps -> /tmp/www/snapshot.jpg)
[ "${DBG:-0}" = 1 ] && python3 $REPO/rtsp/patch_debug.py ak_rtsp_stream.c ak_rtsp_server_sample.c

for f in ak_rtsp_server_sample.c ak_rtsp_stream.c aas_ini_parser.c; do
    $GCC -march=armv5te -mtune=arm926ej-s -Os -std=gnu99 -D__CHIP_AK3918EV300L_SERIES -I. -I$SDK/platform/include -c $f -o ${f%.c}.o
done
L="-lrtsp_server -lplat_common -lplat_vi -lmpi_venc -lplat_ai -lplat_ao -lplat_vqe -lplat_vpss -lplat_isp_sdk -lplat_mem -lplat_osal -lplat_thread -lplat_log -lplat_dbg -lplat_timer -lakmedia -lakaudiofilter -lakaudiocodec -lapp_video -lapp_mem_ex -lmpi_aenc -lmpi_adec -lmpi_osd -lapp_osd_ex -lapp_its"
$GCC -march=armv5te -o rtspd *.o -L$LIBS_DIR -Llib -Wl,--start-group $L -Wl,--end-group -lpthread -ldl -lm -lrt -Wl,-rpath,/app/lib
cp rtspd lib/librtsp_server.so $OUT/
md5sum $OUT/rtspd
echo BUILD_RTSP_OK
