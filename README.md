# anyka-ak3918ev300l-decloud

Take a cheap **Anyka AK3918EV300L** Wi-Fi pan/tilt camera off its vendor cloud and turn it into a **local RTSP camera you control**: no cloud, no phone app, H.265 over RTSP, SSH access and over-the-network updates.

OpenIPC has no working build for this SoC (no Majestic for Anyka, no video stack in the `ak3918ev300` image), so this project keeps the vendor **bootloader, kernel and video drivers** and replaces the whole **user space**: the cloud app is deleted and a small set of open scripts and tools takes over.

Tested on a PTZ camera sold with the InstaView app (board `EVB_CBDM_AK3918EV300L_V1.0.0`, SOI F26a sensor, AltoBeam ATBM6132C Wi-Fi). See [docs/hardware.md](docs/hardware.md) for the full hardware and firmware analysis.

> **No vendor binary is distributed here.** Libraries, kernel modules and sensor configs are extracted from **your own** flash dump; the RTSP server is built from the public Anyka SDK sample. You only need this repo, your dump and a SPI programmer.

## Status

| Feature | State |
|---|---|
| Cloud app removed, no outbound traffic (only ports 22, 80, 554 and WS-Discovery open) | ✅ |
| RTSP **H.265** `rtsp://<ip>:554/vs0` 1920×1080 and `/vs1` 640×360, ~15 fps | ✅ |
| **JPEG snapshot** `http://<ip>/snapshot.jpg` 1920×1080, refreshed every second (hardware JPEG encoder) | ✅ |
| **ONVIF** `http://<ip>/onvif/device_service` (onvif_simple_server): Profile S + Profile T / Media2 with H.265, stream and snapshot URIs, WS-Discovery | ✅ |
| Wi-Fi client (WPA2), DHCP, automatic reconnection | ✅ |
| SSH (dropbear, key and password), full BusyBox (vi, top, awk, nc…), NTP | ✅ |
| Over-the-network firmware update (`cam-update`) | ✅ |
| Hardware watchdog kept armed (camera reboots itself if user space hangs) | ✅ |
| **Day/night** automatic (ISP luminance + hysteresis): IR-cut filter, IR LEDs, ISP night profile; `daynight auto\|day\|night` | ✅ (no light sensor on this board) |
| **Pan + tilt** motors: homing into the end stops at boot, `ptz` command, **ONVIF PTZ** (continuous move, stop, home, absolute/relative, 8 presets) | ✅ |
| **Frigate autotracking** ready: ONVIF RelativeMove in `TranslationSpaceFov` solved with the real dome geometry (two rotations, `src/ptzmath.c`: near the dome axis a pan move rotates the image instead of shifting it), lens ≈94°×62°, reliable `MoveStatus` (MOVING/IDLE) | ✅ |
| Audio, RTSP/ONVIF authentication | 🚧 |
| H.264 | ❌ the EV300L encoder only does H.265 and JPEG |

## How it works

```
U-Boot (stock) ─> Linux 4.4.282 (stock) ─> rootfs (stock squashfs) ─> /etc/init.d/rc.local
                                                                        └─> /app/init/app_init.sh   (this repo, app partition)
   app_init.sh : wdkeep (watchdog) · vendor modules (load.sh) · sensor probe (sensor_drin.sh)
   ├─ net.sh   : ATBM6132C driver · wpa_supplicant · udhcpc · TSO off · dropbear · ntpd · Wi-Fi link watchdog
   ├─ video.sh : rtspd (Anyka SDK RTSP sample, patched: H.265 RTSP + 1 fps JPEG snapshot) respawned forever
   └─ web.sh   : BusyBox httpd :80 (/snapshot.jpg, /onvif/* CGI) · wsd_simple_server (WS-Discovery)
```

## Using it

| What | Where |
|---|---|
| Main stream | `rtsp://<ip>:554/vs0` (H.265 1920×1080) |
| Sub stream | `rtsp://<ip>:554/vs1` (H.265 640×360) |
| Snapshot | `http://<ip>/snapshot.jpg` |
| ONVIF | `http://<ip>/onvif/device_service` (add the camera by IP in Frigate, Home Assistant, ONVIF Device Manager…) |
| Shell | `ssh root@<ip>` |
| Pan/tilt | `ptz left\|right\|up\|down\|stop\|center\|goto P T\|rel DP DT\|fov DX DY\|pos\|preset set N NAME\|goto N\|list` (half-steps; pan 0 = left stop, tilt 0 = dome axis, 1024 = horizon; settings in `/conf/ptz.conf`) |
| Day/night | `daynight auto\|day\|night [--save]`, `daynight status` |

### GPIO map (EVB_CBDM_AK3918EV300L board)

| GPIO | Function |
|---|---|
| 17 / 18 | IR-cut H-bridge: 150 ms pulse on 17 = filter out (night), on 18 = filter in (day) |
| 56 | IR LEDs (1 = on) |
| 69 | white LEDs (1 = on); PWM `pwmchip3/pwm0` also drives them |
| 68 | green status LED (1 = on) |
| 50, 24, 25, 27 | pan stepper phases (in this order), 1.3 ms per half-step with ramp, ~4340 half-steps end to end |
| 65, 66, 26, 58 | tilt stepper phases |

The pins of the two steppers are interleaved (taken from the vendor `gv_step_motor.ko` table). The kernel only wakes sleepers on its 10 ms tick, so `stepper` busy-waits on the monotonic clock for the step timing.

WS-Discovery answers unicast probes; multicast probes need your router to forward `239.255.255.250` to Wi-Fi clients (an IGMP-snooping bridge with an empty group table drops them).

Only the **app** partition (`mtd4`, squashfs mounted on `/app`) is rewritten. Persistent settings live in the **config** partition (`/conf`, jffs2):

| File | Purpose |
|---|---|
| `/conf/wpa_supplicant.conf` | Wi-Fi (created from the build default on first boot) |
| `/conf/dropbear/authorized_keys`, `ed25519_host_key` | SSH keys |
| `/conf/shadow` | optional root password (bind-mounted over the read-only `/etc/shadow`) |
| `/conf/hostname`, `/conf/rtsp.ini`, `/conf/update_url` | optional overrides |

## Repository layout

```
firmware/  extract_dump.sh  mkapp.sh  mkfull.sh  overlay/{init,etc,bin}
rtsp/      build_rtsp.sh + patches applied to the SDK "rtsp" sample
tools/     build_tools.sh (static BusyBox 1.36.1 + Dropbear 2024.86, wdkeep, notso) + dropbear patch
src/       wdkeep.c (watchdog keeper)  notso.c (disable TSO/GSO/GRO/SG)
serial/    PowerShell serial relay used during bring-up (serlog/sq/sercmd/camup)
dev/       live-mode helpers (run the RTSP server from RAM, colour probe)
docker/    build environment (Ubuntu 24.04 + GCC 5.5 / uClibc-ng cross toolchain + qemu-user)
docs/      hardware.md - hardware report and findings
```

## Build

1. **Dump your flash** (8 MiB SPI NOR) with a CH341A and a SOIC8 clip, camera unpowered. Read it **twice** and compare the hashes. Keep this dump safe: it is your only way back.
2. Prepare a work directory (never committed):
   ```
   work/
     dump.bin                     your 8 MiB dump
     sdk/ANYKA_130L_SDK/          git clone --depth 1 --filter=blob:limit=3m https://github.com/Link-WQS/ANYKA_130L_SDK.git
     src/busybox-1.36.1.tar.bz2   https://busybox.net/downloads/
     src/dropbear-2024.86.tar.bz2 https://matt.ucc.asn.au/dropbear/releases/
     src/onvif_simple_server-0.0.5.tar.gz  https://github.com/roleoroleo/onvif_simple_server (tag 0.0.5)
     src/crypt-1.18.2.tar.xz      https://github.com/libtom/libtomcrypt/releases
     src/zlib-1.3.1.tar.gz        https://github.com/madler/zlib/releases
     src/json-c-0.17.tar.gz       https://github.com/json-c/json-c (tag json-c-0.17-20230812)
     local/wpa_supplicant.conf    copy of firmware/overlay/etc/wpa_supplicant.conf.example with your Wi-Fi
     local/authorized_keys        your SSH public key(s)
   ```
3. Build:
   ```sh
   docker build -t ak39-build docker/
   docker run --rm -it -v "$PWD":/repo -v /path/to/work:/work ak39-build bash -c '
     firmware/extract_dump.sh && tools/build_tools.sh all && rtsp/build_rtsp.sh &&
     tools/build_onvif.sh && firmware/mkapp.sh && firmware/mkfull.sh'
   ```
   Outputs in `work/out/`: `app.sqfs` (+ `.md5`) for network updates and `full.bin` for a programmer.

## Install

**First install, with the programmer (simplest):** flash `out/full.bin` (erase, write, **verify**). Only the app partition differs from your dump. Power the camera from its **own 5 V supply**, then `ssh root@<camera-ip>` with your key.

**First install, from a running camera:** if you already have a root shell on the stock firmware (serial console), download `app.sqfs`, copy `/app/bin/flashcp` to `/tmp`, stop the vendor app and run `flashcp -v app.sqfs /dev/mtd4`. Note the vendor `daemon` owns `/dev/watchdog` and reboots the camera when the app dies (see docs).

**Updates:** serve `app.sqfs` and `app.sqfs.md5` over HTTP on your LAN, then
```sh
ssh root@<camera-ip> cam-update http://<server>:<port>/app.sqfs
```
`cam-update` checks md5, squashfs magic and size, copies itself and the tools to RAM, writes with `flashcp -v` (read-back verification) and reboots. The URL can be stored in `/conf/update_url`.

**Going back:** flash your original dump with the programmer.

## Lessons learned (details in [docs/hardware.md](docs/hardware.md))

- **Power it properly.** Powered from a USB-TTL adapter's VCC, the board browns out and hard-resets on every Wi-Fi transmit burst. Use the real supply; connect only GND/TX/RX.
- **H.265 only.** `libmpi_venc` V2.0.44 accepts `enc_out_type` 1 (JPEG) and 2 (HEVC) only.
- The public **AnyCloud39AV130 SDK** headers match the EV300L libs for VI/VENC (`venc_param` layout verified).
- The vendor `librtsp_server` **stalls after one frame** if the SDP advertises an audio track that never delivers data.
- The **sensor module is loaded by the cloud app**, not by the init scripts: without the app, run `sensor_drin.sh`.
- `wpa_supplicant` is built without debug output and **rejects `update_config=1`** (exit 255).
- A shell loop feeding `/dev/watchdog` gets starved under encode + Wi-Fi load; `wdkeep` (C, SCHED_FIFO, 60 s timeout) does not.
- The kernel has no ext2/3/4, overlay or FUSE (vfat, squashfs, jffs2, nfs only).

## Roadmap

Day/night (IR-cut, IR LEDs, light sensor) · pan/tilt over HTTP and ONVIF PTZ · audio · RTSP/ONVIF authentication · OpenIPC hardware report.

## Credits

Anyka AnyCloud39AV130 SDK ([Link-WQS/ANYKA_130L_SDK](https://github.com/Link-WQS/ANYKA_130L_SDK)) for headers and the RTSP sample · cross toolchain from [michelostojski/ipcd](https://github.com/michelostojski/ipcd) · [onvif_simple_server](https://github.com/roleoroleo/onvif_simple_server) (GPLv3, built from source, not redistributed here) · [OpenIPC](https://openipc.org) for the Anyka groundwork · [BusyBox](https://busybox.net) · [Dropbear](https://matt.ucc.asn.au/dropbear/dropbear.html).

## Disclaimer

For devices you own. Flashing can brick your camera; keep your dump and a programmer at hand. MIT license for the content of this repository only (see [LICENSE](LICENSE)).
