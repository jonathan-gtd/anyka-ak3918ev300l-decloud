#!/bin/bash
# extract_dump.sh - carve and unpack the partitions of YOUR OWN 8 MB flash dump.
# Vendor binaries (libs, kernel modules, sensor configs) come from here; nothing proprietary lives in this repo.
# Usage: extract_dump.sh [dump.bin]    (default: $WORK/dump.bin) -> $WORK/vendor/{rootfs,app,config}
set -e
WORK=${WORK:-/work}
DUMP=${1:-$WORK/dump.bin}
V=$WORK/vendor
[ "$(stat -c %s "$DUMP")" = 8388608 ] || { echo "expected an 8 MiB dump"; exit 1; }
mkdir -p $V && cd $V
B=65536
dd if="$DUMP" of=rootfs.sqfs bs=$B skip=33 count=15  status=none   # 0x210000, 960K
dd if="$DUMP" of=app.sqfs    bs=$B skip=48 count=74  status=none   # 0x300000, 4736K
dd if="$DUMP" of=config.jffs2 bs=$B skip=122 count=6 status=none   # 0x7a0000, 384K
rm -rf rootfs app config
unsquashfs -q -d rootfs rootfs.sqfs >/dev/null
unsquashfs -q -d app app.sqfs >/dev/null
jefferson config.jffs2 -d config >/dev/null 2>&1 || echo "(jefferson not installed: config partition not unpacked)"
echo "vendor tree ready in $V:"
grep -ao "libmpi_venc V[0-9.]*\|libplat_vi V[0-9.]*" app/lib/libmpi_venc.so app/lib/libplat_vi.so | sort -u
