# Build environment for the AK3918EV300L de-clouded firmware.
#   docker build -t ak39-build docker/
#   docker run --rm -it -v "$PWD":/repo -v /path/to/workdir:/work ak39-build
# /work holds YOUR files (never committed): dump.bin, sdk/, src/, local/, out/  (see README)
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential bzip2 xz-utils file ca-certificates wget git \
        squashfs-tools python3 python3-pip qemu-user-static ffmpeg openssl \
    && pip3 install --break-system-packages jefferson \
    && rm -rf /var/lib/apt/lists/*
# Cross toolchain: GCC 5.5.0 + uClibc-ng 1.0.28, ARM926EJ-S soft-float (crosstool-NG build published by the ipcd project)
RUN mkdir -p /opt/xt && wget -q -O /tmp/x-tools.tar.bz2 \
        https://raw.githubusercontent.com/michelostojski/ipcd/main/src/x-tools.tar.bz2 \
    && tar -xjf /tmp/x-tools.tar.bz2 -C /opt/xt && rm /tmp/x-tools.tar.bz2
ENV XT=/opt/xt/x-tools/arm-unknown-linux-uclibcgnueabi/bin \
    REPO=/repo WORK=/work
WORKDIR /repo
