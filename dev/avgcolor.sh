#!/bin/bash
# avgcolor.sh [label] - average colour (R G B) of one frame of the vs1 stream (needs ffmpeg)
L=${1:-img}
f=/work/snap/$L.png
rm -f $f
timeout 20 ffmpeg -hide_banner -loglevel quiet -rtsp_transport tcp -i rtsp://${CAM:?set CAM=camera-ip}:554/vs1 -frames:v 1 -update 1 -y $f
if [ -s $f ]; then
  rgb=$(ffmpeg -hide_banner -loglevel quiet -i $f -vf scale=1:1 -f rawvideo -pix_fmt rgb24 - | od -An -tu1 | tr -s ' ')
  set -- $rgb
  echo "$L: R=$1 G=$2 B=$3  (G-(R+B)/2 = $(( $2 - ($1+$3)/2 )))"
else
  echo "$L: pas d'image"
fi
