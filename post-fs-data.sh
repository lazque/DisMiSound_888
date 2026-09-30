#!/system/bin/sh
#
# DisMiSound 888 series - vendor 挂载引擎
# 由 酷安 坠欢啊 自研模块使用，二次修改请取得本人认可
#
# 说明：本模块不再依赖 Magisk 的 magic mount 去覆盖 /vendor。
# vendor 分区在 Magisk / KernelSU / APatch 三家的覆盖方式各不相同，
# 且 magic mount 过来的文件仍然是 system_file 上下文，HAL 常常读不到
# （也就是旧版"KSU/APatch 挂载权限不足"的真正原因）。
# 这里统一改为：在 post-fs-data 阶段手工 bind mount + 重新打 SELinux 标签。
# 三家共用一个实现，行为一致。

MODDIR=${0%/*}
FILES=$MODDIR/files

TAG="DisMiSound"
OK=0
FAIL=0

log() { echo "$TAG: $1" > /dev/kmsg 2>/dev/null; }

# ---------- 等待 vendor 分区就绪 ----------
wait_vendor() {
  local i=0
  while [ ! -d /vendor/etc ]; do
    i=$((i + 1))
    [ $i -gt 40 ] && { log "vendor 分区超时未挂载"; return 1; }
    sleep 0.25
  done
  return 0
}

# ---------- 单个文件的 bind mount ----------
# $1 = 源文件, $2 = 目标文件
bind_file() {
  local src="$1"
  local dst="$2"
  [ -f "$src" ] || { log "源文件缺失 $src"; FAIL=$((FAIL + 1)); return 1; }
  [ -e "$dst" ] || { log "目标不存在，跳过 $dst"; return 0; }

  # 关键：挂载后目标 inode 变成源 inode，
  # 必须先把源文件打上 vendor_file 标签，否则 HAL 进程会被 SELinux 拒绝读取。
  chcon u:object_r:vendor_file:s0 "$src" 2>/dev/null \
    || log "chcon 失败（内核/root 环境可能限制），继续挂载"
  chmod 0644 "$src" 2>/dev/null
  chown 0:0 "$src" 2>/dev/null

  if mount -o bind "$src" "$dst" 2>/dev/null; then
    OK=$((OK + 1))
    return 0
  fi
  if mount --bind "$src" "$dst" 2>/dev/null; then
    OK=$((OK + 1))
    return 0
  fi
  log "挂载失败 $dst"
  FAIL=$((FAIL + 1))
  return 1
}

# ---------- 机型识别 ----------
detect_model() {
  local p v
  for p in ro.product.board ro.product.vendor.board \
           ro.product.device ro.product.vendor.device \
           ro.product.name ro.product.vendor.name \
           ro.boot.hardware.sku; do
    v=$(getprop "$p")
    case "$v" in
      venus|star|mars|haydn|haydnin|odin) echo "$v"; return 0 ;;
    esac
  done
  # 兜底：从机型相关的其它字段里抓代号
  for p in ro.product.model ro.product.vendor.model ro.product.marketname; do
    v=$(getprop "$p")
    case "$v" in
      *M2104J7SC*|*MIX*4*|*odin*) echo "odin"; return 0 ;;
      *M2011K2C*|*venus*)         echo "venus"; return 0 ;;
      *M2102K1C*|*star*|*mars*)   echo "star"; return 0 ;;
      *M2102K1G*|*haydn*)         echo "haydn"; return 0 ;;
    esac
  done
  echo "unknown"
}

wait_vendor || { log "放弃挂载"; exit 0; }

# 用户可以在 $MODDIR/model 里写死机型，优先级最高
if [ -s "$MODDIR/model" ]; then
  MODEL=$(tr -d ' \t\r\n' < "$MODDIR/model")
  log "使用手动指定机型: $MODEL"
else
  MODEL=$(detect_model)
fi

case "$MODEL" in
  venus) DISPLAY="小米 11 标准版" ;;
  star|mars) DISPLAY="小米 11 Pro/Ultra"; MODEL=star ;;
  haydn|haydnin) DISPLAY="红米 K40 Pro/Pro+"; MODEL=haydn ;;
  odin) DISPLAY="小米 MIX 4" ;;
  *)
    DISPLAY="未支持机型（按 11 Pro/Ultra 处理）"
    MODEL=star
    ;;
esac
log "机型: $MODEL ($DISPLAY)"

# ---------- 1. 通用 vendor 文件 ----------
if [ -d "$FILES/common/vendor/etc" ]; then
  COMMON_LIST=$(cd "$FILES/common/vendor/etc" && find . -type f | sed 's|^\./||')
  for rel in $COMMON_LIST; do
    bind_file "$FILES/common/vendor/etc/$rel" "/vendor/etc/$rel"
  done
fi

# ---------- 2. 机型专属文件 ----------
MODEL_DIR=$FILES/model/$MODEL

# 2.1 mixer overlay（MIX 4 有多档通话增益组合）
if [ -d "$MODEL_DIR" ] && [ "$MODEL" = "odin" ]; then
  VARIANT=mixer_paths_overlay_static.xml
  if   [ -f "$MODDIR/tx_high" ]; then VARIANT=overlay.tx-high.xml
  elif [ -f "$MODDIR/tx_off"  ]; then VARIANT=overlay.tx-off.xml
  fi
  if [ -f "$MODDIR/rx_max" ]; then
    case "$VARIANT" in
      overlay.tx-high.xml) VARIANT=overlay.tx-high-rxmax.xml ;;
      overlay.tx-off.xml)  VARIANT=overlay.tx-off-rxmax.xml ;;
      *)                   VARIANT=overlay.rxmax.xml ;;
    esac
  fi
  ORIGINAL=$FILES/model/odin/mixer_paths_overlay_static.xml
  if [ "$VARIANT" != "mixer_paths_overlay_static.xml" ]; then
    cp -f "$MODEL_DIR/$VARIANT" "$ORIGINAL" 2>/dev/null
    chcon u:object_r:vendor_file:s0 "$ORIGINAL" 2>/dev/null
  fi
  log "MIX 4 通话档位: $VARIANT"
fi

if [ -f "$MODEL_DIR/mixer_paths_overlay_static.xml" ]; then
  for dst in /vendor/etc/audio/sku_lahaina/mixer_paths_overlay_static.xml \
             /vendor/etc/audio/mixer_paths_overlay_static.xml; do
    [ -e "$dst" ] && bind_file "$MODEL_DIR/mixer_paths_overlay_static.xml" "$dst"
  done
fi

# 2.2 smart PA 固件 / misound 资源（目标存在才挂，自动适配 mars 等子型号）
if [ -d "$MODEL_DIR/firmware" ]; then
  FW_LIST=$(cd "$MODEL_DIR/firmware" && find . -type f | sed 's|^\./||')
  for rel in $FW_LIST; do
    bind_file "$MODEL_DIR/firmware/$rel" "/vendor/firmware/$rel"
  done
fi
if [ -d "$MODEL_DIR/lib" ]; then
  LIB_LIST=$(cd "$MODEL_DIR/lib" && find . -type f | sed 's|^\./||')
  for rel in $LIB_LIST; do
    bind_file "$MODEL_DIR/lib/$rel" "/vendor/lib/$rel"
  done
fi

# ---------- 3. acdb 声学校准 ----------
# 各机型的校准目录名不同（Tutu / Forte 等），这里按后缀自动配对，
# 不做机型硬编码，避免把别的机型的 TX 校准挂到错误的目录上。
if [ ! -f "$MODDIR/no_acdb" ]; then
  case "$MODEL" in
    haydn|haydnin) ACDB_SRC=$FILES/model/acdb/forte ;;
    *)             ACDB_SRC=$FILES/model/acdb/tutu  ;;
  esac

  ACDB_DST=""
  for cand in $(find /vendor/etc/acdbdata -maxdepth 1 -type d 2>/dev/null); do
    if ls "$cand"/*_Handset_cal.acdb >/dev/null 2>&1; then
      ACDB_DST=$cand
      break
    fi
  done

  if [ -d "$ACDB_SRC" ] && [ -n "$ACDB_DST" ]; then
    log "acdb 目标目录: $ACDB_DST"
    ACDB_LIST=$(cd "$ACDB_SRC" && find . -type f | sed 's|^\./||')
    for rel in $ACDB_LIST; do
      suffix=${rel#*_}
      target=$(ls "$ACDB_DST"/*_"$suffix" 2>/dev/null | head -n 1)
      [ -n "$target" ] && bind_file "$ACDB_SRC/$rel" "$target"
    done
  else
    log "未找到可用的 acdb 目录，跳过校准替换"
  fi
else
  log "检测到 no_acdb，保留原厂声学校准"
fi

log "挂载完成: 成功 $OK 项，失败 $FAIL 项"
exit 0
