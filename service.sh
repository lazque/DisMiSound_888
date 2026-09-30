#!/system/bin/sh
#
# 开机自检：把本次挂载结果写到 $MODDIR/mount.log，方便反馈。
# 不在这里重启任何服务，避免开机时抢音频焦点。

MODDIR=${0%/*}
LOG=$MODDIR/mount.log

sleep 15

{
  echo "==== DisMiSound 888s ===="
  date
  echo "board=$(getprop ro.product.board) device=$(getprop ro.product.device)"
  echo "model=$(getprop ro.product.model)"
  echo "-- 生效中的挂载 --"
  grep -i -e "DisMiSound" /proc/mounts 2>/dev/null | awk '{print $1" -> "$2}'
  echo "-- audioserver --"
  pidof audioserver 2>/dev/null || echo "audioserver 未运行"
  echo "-- 关键文件的实际大小 --"
  for f in /vendor/etc/audio/sku_lahaina/mixer_paths_overlay_static.xml \
           /vendor/etc/audio_policy_engine_stream_volumes_mi.xml \
           /vendor/etc/audio_policy_engine_stream_volumes.xml; do
    [ -e "$f" ] && echo "$f : $(stat -c %s "$f" 2>/dev/null) bytes"
  done
} > "$LOG" 2>&1

echo "DisMiSound: 自检完成 -> $LOG" > /dev/kmsg 2>/dev/null
exit 0
