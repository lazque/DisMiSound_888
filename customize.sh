#!/system/bin/sh
#
# 本文件只负责安装期的提示与清理。
# 真正的机型判定、vendor 文件挂载全部在 post-fs-data.sh 内完成，
# 因此 Magisk / KernelSU / APatch 三家表现一致，
# 即使 Manager 没有执行 customize.sh（KSU/APatch 常见）也不影响生效。

SKIPUNZIP=0

ui_print() { echo "$1"; }

# 机型探测（仅用于安装日志）
probe() {
  local p v
  for p in ro.product.board ro.product.vendor.board ro.product.device \
           ro.product.vendor.device ro.product.name ro.product.vendor.name \
           ro.product.model ro.product.marketname; do
    v=$(getprop "$p")
    [ -n "$v" ] && echo "$v"
  done
}

MODEL=unknown
for v in $(probe); do
  case "$v" in
    venus)                      MODEL=venus ;;
    star|mars)                  MODEL=star ;;
    haydn|haydnin)              MODEL=haydn ;;
    odin)                       MODEL=odin ;;
    *M2104J7SC*|*MIX*4*|*odin*) MODEL=odin ;;
    *M2011K2C*|*venus*)         MODEL=venus ;;
    *M2102K1C*|*star*)          MODEL=star ;;
    *M2102K1G*|*haydn*)         MODEL=haydn ;;
  esac
done

case "$MODEL" in
  venus) ui_print "- 目标机型：小米 11 标准版" ;;
  star)  ui_print "- 目标机型：小米 11 Pro/Ultra" ;;
  haydn) ui_print "- 目标机型：红米 K40 Pro/Pro+" ;;
  odin)  ui_print "- 目标机型：小米 MIX 4"
         ui_print "- MIX 4 已内置通话修正：上行增益还原 + 听筒 Boost 回落" ;;
  *)     ui_print "- 未识别机型，按 小米 11 Pro/Ultra 处理"
         ui_print "- 可在模块目录建 model 文件写死机型代号" ;;
esac

# 清理历史遗留：旧版打包了 0 字节的流音量表，会打断 MIUI 的音量曲线
rm -f "$MODPATH/system/vendor/etc/audio_policy_engine_stream_volumes_mi.xml" 2>/dev/null
rm -f "$MODPATH/files/common/vendor/etc/audio_policy_engine_stream_volumes_mi.xml" 2>/dev/null

# 旧版同名模块互斥
disable_alternatives() {
  local dir subdir prop
  for dir in /data/adb/modules /data/adb/modules_update; do
    [ -d "$dir" ] || continue
    for subdir in "$dir"/*; do
      [ -d "$subdir" ] || continue
      prop="$subdir/module.prop"
      [ -f "$prop" ] || continue
      if grep -q -i -e '［小米 11 标准版］音频通路优化' -e '［小米 11 P/U］音频通路优化' "$prop" 2>/dev/null; then
        touch "$subdir/disable"
        ui_print "- 已禁用旧版模块：$(basename "$subdir")"
      fi
    done
  done
}
disable_alternatives

if command -v set_perm_recursive >/dev/null 2>&1; then
  set_perm_recursive "$MODPATH" 0 0 0755 0644
else
  chmod -R 0755 "$MODPATH" 2>/dev/null
  find "$MODPATH" -type f -exec chmod 0644 {} \; 2>/dev/null
fi

ui_print "- 开关文件放在模块目录：tx_off / tx_high / rx_max / no_acdb / model"
ui_print "- 详见模块内 README.txt"
exit 0
