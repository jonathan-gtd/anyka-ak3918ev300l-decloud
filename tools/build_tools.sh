#!/bin/bash
# build_tools.sh - static full busybox + dropbear (+ helpers) for the camera (ARM926EJ-S, uClibc-ng)
# Sources: $WORK/src/busybox-1.36.1.tar.bz2 and $WORK/src/dropbear-2024.86.tar.bz2   Usage: build_tools.sh [all|busybox|dropbear|helpers]
set -e
XT=${XT:-/opt/xt/x-tools/arm-unknown-linux-uclibcgnueabi/bin}
export PATH=$XT:$PATH
CROSS=arm-unknown-linux-uclibcgnueabi-
WORK=${WORK:-/work}
REPO=${REPO:-$(cd "$(dirname "$0")/.." && pwd)}
OUT=$WORK/out/tools; mkdir -p $OUT
B=/tmp/tools_build; mkdir -p $B

what=${1:-all}

if [ "$what" = all -o "$what" = busybox ]; then
  rm -rf $B/busybox-1.36.1 && tar -xjf $WORK/src/busybox-1.36.1.tar.bz2 -C $B
  cd $B/busybox-1.36.1
  make -s defconfig >/dev/null
  python3 $REPO/tools/patch_busybox_httpd.py networking/httpd.c   # /onvif/* served as CGI
  # static, cross prefix, drop what breaks with uClibc-ng 1.0.28 / kernel 4.4
  sed -i -e 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' \
         -e "s|^CONFIG_CROSS_COMPILER_PREFIX=.*|CONFIG_CROSS_COMPILER_PREFIX=\"$CROSS\"|" \
         -e 's/^CONFIG_TC=y/# CONFIG_TC is not set/' \
         -e 's/^CONFIG_FEATURE_TC_INGRESS=y/# CONFIG_FEATURE_TC_INGRESS is not set/' \
         -e 's/^CONFIG_SHA1_HWACCEL=y/# CONFIG_SHA1_HWACCEL is not set/' \
         -e 's/^CONFIG_SHA256_HWACCEL=y/# CONFIG_SHA256_HWACCEL is not set/' \
         -e 's/^CONFIG_NSENTER=y/# CONFIG_NSENTER is not set/' \
         -e 's/^CONFIG_UNSHARE=y/# CONFIG_UNSHARE is not set/' \
         .config
  echo 'CONFIG_EXTRA_CFLAGS="-march=armv5te -mtune=arm926ej-s"' >> .config
  yes "" | make -s oldconfig >/dev/null 2>&1 || true
  make -s -j"$(nproc)" 2>&1 | grep -E "error|Error" | head -20 || true
  ${CROSS}strip busybox
  cp busybox $OUT/busybox
  ./busybox --list > $OUT/busybox.applets 2>/dev/null || true
  file $OUT/busybox | cut -c1-90; ls -la $OUT/busybox
  echo "BUSYBOX_OK"
fi

if [ "$what" = all -o "$what" = dropbear ]; then
  rm -rf $B/dropbear-2024.86 && tar -xjf $WORK/src/dropbear-2024.86.tar.bz2 -C $B
  cd $B/dropbear-2024.86
  # host keys and authorized_keys in /conf (read-only rootfs, root $HOME is /)
  cat > localoptions.h <<'EOF'
#define DROPBEAR_SVR_PASSWORD_AUTH 1
#define DROPBEAR_SVR_PUBKEY_AUTH 1
#define DSS_PRIV_FILENAME "/conf/dropbear/dss_host_key"
#define RSA_PRIV_FILENAME "/conf/dropbear/rsa_host_key"
#define ECDSA_PRIV_FILENAME "/conf/dropbear/ecdsa_host_key"
#define ED25519_PRIV_FILENAME "/conf/dropbear/ed25519_host_key"
#define DROPBEAR_DSS 0
#define DEFAULT_PATH "/bin:/sbin:/usr/bin:/usr/sbin:/app/bin"
#define DEFAULT_ROOT_PATH "/bin:/sbin:/usr/bin:/usr/sbin:/app/bin"
#define SFTPSERVER_PATH "/app/bin/sftp-server"
EOF
  # authorized_keys read from /conf/dropbear/authorized_keys instead of ~/.ssh/
  python3 $REPO/tools/patch_dropbear.py src/svr-authpubkey.c
  grep -n 'AUTHKEYS' src/svr-authpubkey.c | head -6
  ./configure --host=arm-unknown-linux-uclibcgnueabi --disable-zlib --disable-wtmp --disable-lastlog --disable-utmp --disable-utmpx --disable-wtmpx --disable-pututline --disable-pututxline --enable-static \
     CC=${CROSS}gcc CFLAGS="-Os -march=armv5te -mtune=arm926ej-s" >/dev/null
  make -s -j"$(nproc)" PROGRAMS="dropbear dbclient dropbearkey scp" MULTI=1 STATIC=1 2>&1 | grep -E "error|Error" | head -20 || true
  ${CROSS}strip dropbearmulti
  cp dropbearmulti $OUT/dropbearmulti
  file $OUT/dropbearmulti | cut -c1-90; ls -la $OUT/dropbearmulti
  echo "DROPBEAR_OK"
fi

if [ "$what" = all -o "$what" = helpers ]; then
  # wdkeep (watchdog keeper) and notso (ethtool -K equivalent), static
  for p in wdkeep notso stepper ptzmath; do
    ${CROSS}gcc -march=armv5te -Os -static -std=gnu99 -D_GNU_SOURCE -o $WORK/out/$p $REPO/src/$p.c -lm
    ${CROSS}strip $WORK/out/$p
  done
  ls -la $WORK/out/wdkeep $WORK/out/notso $WORK/out/stepper $WORK/out/ptzmath
  echo "HELPERS_OK"
fi

if [ "$what" = all -o "$what" = busybox ]; then
  # list of applets (needs qemu-user-static) for mkapp.sh
  command -v qemu-arm-static >/dev/null && qemu-arm-static $OUT/busybox --list > $OUT/busybox.applets
fi
