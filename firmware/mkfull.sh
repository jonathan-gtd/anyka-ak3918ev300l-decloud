#!/bin/bash
# mkfull.sh - full 8 MiB image for a SPI programmer (CH341A + SOIC8 clip): YOUR dump with the app partition
# replaced by out/app.sqfs. Bootloader, kernel, rootfs and config stay byte-identical to your dump.
# Usage: mkfull.sh [dump.bin]  -> $WORK/out/full.bin (+ .md5)
set -e
WORK=${WORK:-/work}
DUMP=${1:-$WORK/dump.bin}
APP=$WORK/out/app.sqfs
OUTF=$WORK/out/full.bin
[ "$(stat -c %s "$DUMP")" = 8388608 ] || { echo "expected an 8 MiB dump"; exit 1; }
[ -f "$APP" ] || { echo "missing $APP (run firmware/mkapp.sh)"; exit 1; }
python3 - "$DUMP" "$APP" "$OUTF" <<'PY'
import sys
dump, app, out = sys.argv[1:4]
d = bytearray(open(dump, 'rb').read())
a = open(app, 'rb').read()
OFF, LEN = 0x300000, 0x4A0000          # mtd4 "app"
assert len(a) <= LEN and a[:4] == b'hsqs'
d[OFF:OFF+LEN] = b'\xff' * LEN
d[OFF:OFF+len(a)] = a
open(out, 'wb').write(d)
orig = open(dump, 'rb').read()
for name, s, e in [('uboot',0,0x40000),('dtb',0x40000,0x50000),('kernel',0x50000,0x210000),
                   ('rootfs',0x210000,0x300000),('app',0x300000,0x7a0000),('config',0x7a0000,0x800000)]:
    print(f"{name:7s} {'unchanged' if orig[s:e]==d[s:e] else 'REPLACED'}")
PY
(cd $WORK/out && md5sum full.bin > full.bin.md5 && cat full.bin.md5)
echo "Flash $OUTF with your programmer (erase, write, VERIFY). Keep your original dump!"
