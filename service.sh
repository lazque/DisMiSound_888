#!/system/bin/sh
#
# 开机自检：把本次挂载结果写到 $MODDIR/mount.log，方便反馈。
# 不在这里重启任何服务，避免开机时抢音频焦点。

MODDIR=${0%/*}

# 模块目录只读时（KSU meta-overlayfs 等）日志改写到 /data/local/tmp（坠欢 2026.10.11）
WORKDIR=$MODDIR
[ -w "$MODDIR" ] || WORKDIR=/data/local/tmp/DisMiSound_888s
mkdir -p "$WORKDIR" 2>/dev/null
LOG=$WORKDIR/mount.log

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
  echo "-- 屏录所需的 r_submix 模块 --"
  for f in /vendor/etc/audio_policy_configuration.xml \
           /vendor/etc/audio/audio_policy_configuration.xml \
           /odm/etc/audio_policy_configuration.xml; do
    if [ -f "$f" ]; then
      if grep -q '<module name="r_submix"' "$f" 2>/dev/null; then
        echo "OK   $f (含 r_submix)"
      else
        echo "MISS $f (不含 r_submix! 屏录会失败)"
      fi
    fi
  done
  for lib in /vendor/lib64/hw/audio.r_submix.default.so \
             /system/lib64/hw/audio.r_submix.default.so \
             /system_ext/lib64/hw/audio.r_submix.default.so; do
    [ -f "$lib" ] && echo "HAL  $lib"
  done
} > "$LOG" 2>&1

# post-fs-data 阶段写的修复报告一并送出，方便用文件管理器直接看
if [ -f "$WORKDIR/record_fix_report.txt" ] && [ -d /sdcard/Download ]; then
  cp -f "$WORKDIR/record_fix_report.txt" /sdcard/Download/DisMiSound-recordfix.txt 2>/dev/null
  chmod 0666 /sdcard/Download/DisMiSound-recordfix.txt 2>/dev/null
fi

# ---------- 音质音效：开启 MIX 4 哈曼卡顿 + 补发系统权限 ----------
# 坠欢 2026.10.2
MS_PKG=com.miui.misound

if [ -f "$MODDIR/no_misound_fix" ]; then
  echo "-- 音质音效：已按 no_misound_fix 跳过 --" >> "$LOG" 2>&1
else
  {
    echo "-- 音质音效 --"
    # App 判断哈曼卡顿是否可用，读的就是 ro.vendor.audio.sfx.harmankardon
    setprop ro.vendor.audio.sfx.harmankardon true
    echo "prop   ro.vendor.audio.sfx.harmankardon = $(getprop ro.vendor.audio.sfx.harmankardon)"
    # 用户勾选哈曼卡顿后写的是这个全局开关
    settings put global settings_system_harman_kardon_enable 1 2>/dev/null
    echo "global settings_system_harman_kardon_enable = $(settings get global settings_system_harman_kardon_enable 2>/dev/null)"
    echo "global effect_implementer = $(settings get global effect_implementer 2>/dev/null)"
  } >> "$LOG" 2>&1

  # 建 force_harman 可以把默认音效实施者直接钉成哈曼卡顿
  if [ -f "$MODDIR/force_harman" ]; then
    settings put global effect_implementer harmankardon 2>/dev/null
    echo "global effect_implementer -> harmankardon（force_harman）" >> "$LOG" 2>&1
  fi

  # 建 misound_full 会把被关掉的米音后处理一并打开（场景音效 / 耳道适配）
  if [ -f "$MODDIR/misound_full" ]; then
    setprop ro.vendor.audio.sfx.scenario true
    setprop ro.vendor.audio.sfx.earadj true
    setprop persist.vendor.audio.misoundasc true
    echo "misound_full: scenario / earadj / misoundasc 已打开" >> "$LOG" 2>&1
  fi

  # 覆盖安装后签名变了，系统级权限会被收回；这里补发，写不动设置就是这步没成功
  for perm in android.permission.WRITE_SECURE_SETTINGS \
              android.permission.MODIFY_AUDIO_SETTINGS \
              android.permission.MODIFY_AUDIO_ROUTING \
              android.permission.BLUETOOTH_PRIVILEGED \
              android.permission.READ_DEVICE_CONFIG; do
    pm grant "$MS_PKG" "$perm" 2>/dev/null
  done
  echo "权限补发结果:" >> "$LOG" 2>&1
  dumpsys package "$MS_PKG" 2>/dev/null \
    | grep -e "WRITE_SECURE_SETTINGS" -e "MODIFY_AUDIO_ROUTING" -e "BLUETOOTH_PRIVILEGED" \
    | head -6 >> "$LOG" 2>&1
fi

# ---------- 音质音效独立版（com.dismisound.audiofx）----------
APP_PKG=com.dismisound.audiofx
APP_APK=$MODDIR/files/app/DisMiSoundAudioFX.apk
{
  echo "-- 音质音效独立版 --"
  if [ -f "$APP_APK" ]; then
    chmod 0644 "$APP_APK" 2>/dev/null
    if pm list packages 2>/dev/null | grep -q "package:$APP_PKG"; then
      echo "已安装"
    else
      pm install -r --user 0 "$APP_APK" 2>&1 | tail -2
      echo "安装完成"
    fi
    for perm in android.permission.WRITE_SECURE_SETTINGS \
                android.permission.MODIFY_AUDIO_SETTINGS \
                android.permission.READ_EXTERNAL_STORAGE; do
      pm grant "$APP_PKG" "$perm" 2>/dev/null
    done
    dumpsys package "$APP_PKG" 2>/dev/null \
      | grep -m1 "WRITE_SECURE_SETTINGS" >> "$LOG" 2>&1
  else
    echo "files/app/DisMiSoundAudioFX.apk 缺失"
  fi
} >> "$LOG" 2>&1

echo "DisMiSound: 自检完成 -> $LOG" > /dev/kmsg 2>/dev/null
exit 0
