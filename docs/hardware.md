# Hardware report: Anyka AK3918EV300L PTZ Wi-Fi camera (InstaView / "GV" SDK)


## TL;DR
- Board `EVB_CBDM_AK3918EV300L_V1.0.0` (DT `compatible = "anyka,ak3918ev300l"`), 64 MB DDR2, 8 MB SPI NOR (Puya **P25Q64H**, JEDEC `85 60 17`).
- Sensor **SOI F26a** (I2C 0x40, id `0x0852`, driver `jxfxx`), Wi-Fi **AltoBeam ATBM6132C** (USB `007a:6162`), no Ethernet PHY populated, 2-axis stepper PTZ.
- Stock firmware: kernel **4.4.282** (`#20 Mon Sep 23 2024`, Buildroot 2018.02.7 gcc 5.5.0, uClibc 1.0.31), cloud app "gv_ipc / instaview".
- **The EV300L hardware encoder is H.265 + JPEG only — no H.264.** `libmpi_venc V2.0.44` rejects `enc_out_type` 0 (H264) and 3; only 1 (JPEG) and 2 (HEVC) pass `venc_check_and_format_param`.
- With the vendor modules/libs from the flash, the public **AnyCloud39AV130 SDK headers** are layout-compatible for VI/VENC: we built a local RTSP server (SDK `rtsp` sample) that streams **1080p + 360p H.265** with the cloud app removed.

## Flash layout (from U-Boot env `mtdparts`)
| mtd | name | offset | size | content |
|---|---|---|---|---|
| 0 | uboot | 0x000000 | 256K | U-Boot 2019.10.0-V4.0.27 |
| 1 | dtb | 0x040000 | 64K | FDT |
| 2 | kernel | 0x050000 | 1792K | uImage Linux-4.4.282 |
| 3 | rootfs | 0x210000 | 960K | squashfs xz, 64K blocks |
| 4 | app | 0x300000 | 4736K | squashfs xz (mounted /app) |
| 5 | config | 0x7a0000 | 384K | jffs2 (mounted /conf) |

U-Boot: `bootdelay=1`, `bootcmd=gvsdupdate;run boot_normal`. `gvsdupdate` looks for `akv300Lall.bin` / `akv300Lsd.bin` / `akv300Lota.bin` on a FAT SD card, but the packages are **encrypted** ("decrypt update pack") — not usable for custom images. Serial console `ttySAK0` 115200 on pads `G R T V`.

## Vendor userspace versions (useful to match an SDK)
`libplat_vi V3.4.21`, `libplat_vpss V2.1.09`, `libmpi_venc V2.0.44`, `libplat_isp_sdk V8.0.01`, `libplat_common V1.0.23`, `libapp_video V1.0.14`, `libplat_ai V1.14.02`, `libplat_ao V1.13.04`, `libmpi_aenc V1.2.06`, `Media Lib V1.19.23`. Encoder core: `AKV AV100 Encoder Lib V1.1.03`. ISP driver: `isp_drv_lib-V0.2.31-AV100&300L`.

Kernel modules (vermagic `4.4.282 mod_unload ARMv5`): `ak_isp`, `ak_venc_adapter`, `ak_venc_bridge`, `ak_i2c`, `ak_pcm`, `ak_ion`, `ak_mci`, `ak_hcd`, `ak_eth`, `ak_saradc`, `ak_pwm_char`, `usbcore`, `usb-common`, `loop`, sensors `sensor_f26a`, `sensor_f2x_f3x`, `sensor_f22_f23_f28_f28p_f35_f37`, `sensor_h63_h63p`, `sensor_gc2063`, Wi-Fi `atbm6132c_wifi_usb` / `atbm613x_wifi_usb`, plus vendor `gv-gpio`, `gv_step_motor`, `exfat`.

## Findings that may save someone time
1. **H.265 only.** Disassembly of `venc_check_and_format_param` in `libmpi_venc V2.0.44`: `ldr r4,[r0,#0x24] ; sub r3,r4,#1 ; cmp r3,#1 ; bls ok` → only `enc_out_type` 1/2 accepted; type 1 requires `profile == PROFILE_JPEG (7)`, type 2 requires an HEVC profile.
2. **`struct venc_param` layout matches the AV130 SDK V3 header** (`profile` @0x0C, `br_mode` @0x10, `chroma_mode` @0x20, `enc_out_type` @0x24, size 0x40), despite lib V2.0.44 vs V3.0.02. VI (`ak_vi_*`) calls also worked with the V3 headers.
3. **Sensor module is loaded by the cloud app**, not by the init scripts (`/app/ak/sensor_drin.sh` is commented out in `load_ak_driver.sh`). Without the app, run the probe script yourself.
4. **Watchdog**: the vendor `daemon` opens `/dev/watchdog` (driver is `nowayout`) and reboots when its child dies; killing it requires taking over `/dev/watchdog` immediately. A shell `echo > /dev/watchdog` loop gets starved under encode + Wi-Fi load; a small C keeper (`WDIOC_SETTIMEOUT 60`, `SCHED_FIFO`) is reliable.
5. **Wi-Fi**: `wpa_supplicant 2.10 -Dnl80211` works with the vendor `atbm6132c_wifi_usb.ko wifi_bt_comb=1`. The binary is built with `CONFIG_NO_STDOUT_DEBUG` (any `-d` → exit 255) and its config must not contain `update_config=1` (also exit 255).
6. **Vendor `librtsp_server` (ak_rtsp_server_V1.0.02) stalls after the first video frame if the SDP advertises an audio track that never delivers frames.** Remove the audio track and it streams fine.
7. **Brown-outs**: powering the board from a USB-TTL adapter's VCC causes hard resets (no oops) on every Wi-Fi TX burst. Use the real 5 V supply.

## What does *not* work for OpenIPC as-is
- The OpenIPC `ak3918ev300` lite image (Linux 4.4.302, musl) boots a base system but has no ISP/VENC/sensor stack and no Majestic for Anyka; the vendor modules above are built for 4.4.282 and the vendor libs for uClibc.
- ATBM6132C is not in the lite image; `gtxaspec/atbm-wifi` (branch `atbm-606x-c`) lists ATBM6132-C and could be built for the OpenIPC kernel.

## Testing offer (for OpenIPC developers)
I can boot the OpenIPC `ak3918ev300` image on this board (CH341A + clip, full dump kept) and post the serial boot log, and test any build you want to try.
