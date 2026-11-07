#!/bin/bash
# build_onvif.sh - static onvif_simple_server + wsd_simple_server (GPLv3, roleoroleo) for the camera,
# with zlib, libtomcrypt and json-c cross-compiled statically.
# Sources in $WORK/src: onvif_simple_server-0.0.5.tar.gz crypt-1.18.2.tar.xz zlib-1.3.1.tar.gz json-c-0.17.tar.gz
# Output: $WORK/out/onvif/{onvif_simple_server,wsd_simple_server,templates/...}
set -e
WORK=${WORK:-/work}
REPO=${REPO:-$(cd "$(dirname "$0")/.." && pwd)}
XT=${XT:-/opt/xt/x-tools/arm-unknown-linux-uclibcgnueabi/bin}
export PATH=$XT:$PATH
T=arm-unknown-linux-uclibcgnueabi
CF="-Os -march=armv5te -mtune=arm926ej-s -ffunction-sections -fdata-sections"
B=/tmp/onvif_deps; P=$B/prefix
OUT=$WORK/out/onvif
rm -rf $B && mkdir -p $B $P/include $P/lib $OUT && cd $B

echo "== zlib =="
tar -xzf $WORK/src/zlib-1.3.1.tar.gz && cd zlib-1.3.1
CC=$T-gcc AR=$T-ar RANLIB=$T-ranlib CFLAGS="$CF" ./configure --static --prefix=$P >/dev/null
make -s -j"$(nproc)" libz.a >/dev/null && make -s install >/dev/null && cd ..

echo "== libtomcrypt =="
tar -xJf $WORK/src/crypt-1.18.2.tar.xz && cd libtomcrypt-1.18.2
make -s -j"$(nproc)" CC=$T-gcc AR=$T-ar RANLIB=$T-ranlib CFLAGS="$CF -DLTC_NOTHING -DLTC_SHA1 -DLTC_SHA256 -DLTC_BASE64 -DLTC_HASH_HELPERS -DLTC_RNG_GET_BYTES -DLTC_DEVRANDOM -DLTC_FORTUNA -DLTC_AES -DLTC_SHA224 -DLTC_SHA512 -DLTC_SHA384" library >/dev/null 2>&1 \
 || make -s -j"$(nproc)" CC=$T-gcc AR=$T-ar RANLIB=$T-ranlib CFLAGS="$CF" library >/dev/null
cp libtomcrypt.a $P/lib/ && cp src/headers/*.h $P/include/ && cd ..

echo "== json-c =="
tar -xzf $WORK/src/json-c-0.17.tar.gz && mkdir -p json-c-build && cd json-c-build
cat > tc.cmake <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_C_COMPILER $XT/$T-gcc)
set(CMAKE_C_FLAGS "$CF")
EOF
cmake -DCMAKE_TOOLCHAIN_FILE=tc.cmake -DCMAKE_INSTALL_PREFIX=$P -DCMAKE_BUILD_TYPE=MinSizeRel \
      -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_TESTING=OFF -DDISABLE_EXTRA_LIBS=ON \
      -DHAVE_ARC4RANDOM=OFF -DENABLE_THREADING=OFF ../json-c-json-c-0.17-20230812 >/dev/null
make -s -j"$(nproc)" >/dev/null && make -s install >/dev/null && cd ..

echo "== onvif_simple_server =="
tar -xzf $WORK/src/onvif_simple_server-0.0.5.tar.gz && cd onvif_simple_server-0.0.5
# camera paths: read-only /etc and /var/log -> config generated in /tmp/onvif, templates in /app/www
sed -i -e 's|"/etc/onvif_simple_server.conf"|"/tmp/onvif/onvif_simple_server.conf"|' \
       -e 's|"/etc/onvif_simple_server.json"|"/tmp/onvif/onvif_simple_server.json"|' \
       -e 's|"/var/log/onvif_simple_server.log"|"/tmp/onvif/onvif_simple_server.log"|' onvif_simple_server.c
sed -i -e 's|"/var/log/wsd_simple_server.log"|"/tmp/onvif/wsd_simple_server.log"|' \
       -e 's|"/etc/wsd_simple_server"|"/app/www/wsd_files"|' wsd_simple_server.c
python3 $REPO/tools/patch_onvif_fov.py ptz_service.c
# pan unit = half-steps of a 4096 half-steps/turn stepper; lens: 102 deg diagonal ~ 94 deg horizontal (16:9)
make -s CC="$T-gcc -static -I$P/include -L$P/lib -DPTZ_HFOV=${PTZ_HFOV:-94.0} -DPTZ_DEG_PER_STEP=${PTZ_DEG_PER_STEP:-0.087890625}" STRIP=$T-strip onvif_simple_server wsd_simple_server 2>&1 | grep -E "error|undefined" || true
$T-strip onvif_simple_server wsd_simple_server
rm -rf $OUT/* && mkdir -p $OUT/templates
cp onvif_simple_server wsd_simple_server $OUT/
cp -r *_files $OUT/templates/
cp onvif_simple_server.conf.example LICENSE $OUT/
file $OUT/onvif_simple_server | cut -c1-80
du -sh $OUT/templates
echo BUILD_ONVIF_OK
