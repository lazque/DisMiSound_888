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

# 模块目录只读时（KernelSU meta-overlayfs 等模式），
# 临时文件 / 变体 / 报告自动改写到 /data/local/tmp，避免静默失败（坠欢 2026.10.11）
WORKDIR=$MODDIR
[ -w "$MODDIR" ] || WORKDIR=/data/local/tmp/DisMiSound_888s
mkdir -p "$WORKDIR" 2>/dev/null

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

# ------------------------------------------------------------------
# ROM 判定（坠欢 2026.10.11）
#
# MIUI14 刷入卡第一屏的根因：本模块的策略/音效/平台配置取自澎湃 OS4，
# 直接 bind 到 MIUI（Android 12/13）的 vendor 上，audioserver 解析
# 不兼容的 audio_effects / audio_policy_configuration 后反复崩溃，
# 开机动画停在第一屏。这里识别 MIUI（非澎湃 OS）后走兼容档：
# 只保留 acdb 校准、smart PA 固件、ADSP 资源和机型 mixer overlay
# （目标存在才挂），其余跨 ROM 的整包替换一律跳过。
# 想在 MIUI 上强行全量挂载，建 full_patch（后果自负）。
# ------------------------------------------------------------------
MI_OS_NAME=$(getprop ro.mi.os.version.name 2>/dev/null)
MIUI_NAME=$(getprop ro.miui.ui.version.name 2>/dev/null)
if [ -z "$MI_OS_NAME" ] && [ -n "$MIUI_NAME" ]; then
  LEGACY_ROM=1
  log "ROM: MIUI ($MIUI_NAME)，启用兼容档（防卡第一屏）"
else
  LEGACY_ROM=0
  log "ROM: 澎湃 OS / 其它 ($(getprop ro.build.display.id 2>/dev/null))"
fi
[ -f "$MODDIR/full_patch" ] && { LEGACY_ROM=0; log "full_patch: 关闭 MIUI 兼容档"; }

# ------------------------------------------------------------------
# 蓝牙保护（坠欢 2026.10.11）
#
# 小米11 Ultra 蓝牙失效（耳机/车载连上后媒体和通话都从扬声器出声）的
# 根因：本模块自带的主策略 audio_policy_configuration.xml 把 A2DP 写成
# 旧式 primary 内联端口，整包覆盖掉原厂策略后，原厂 bluetooth_qti 策略
# 模块不再被加载，A2DP / HFP 注册不出来，音频全部回落扬声器。
#
# 处理：默认不再整包替换任何 audio_policy_configuration（含 a2dp /
# bluetooth_qti / r_submix 策略文件），策略交还原厂；屏录所需的
# r_submix 改由第 4 节的自适应注入在原厂策略上完成，效果不变。
# 确要恢复旧的整包替换行为，建 policy_patch。
# ------------------------------------------------------------------
SKIP_POLICY=1
[ -f "$MODDIR/policy_patch" ] && { SKIP_POLICY=0; log "policy_patch: 恢复整包策略替换"; }

# ---------- 1. 通用 vendor 文件 ----------
if [ -d "$FILES/common/vendor/etc" ]; then
  COMMON_LIST=$(cd "$FILES/common/vendor/etc" && find . -type f | sed 's|^\./||')
  for rel in $COMMON_LIST; do
    base=${rel##*/}
    # 1.1 蓝牙保护：策略文件一律交还原厂（防止 bluetooth_qti 模块丢失）
    case "$base" in
      audio_policy_configuration.xml|a2dp_audio_policy_configuration.xml|\
      bluetooth_qti_audio_policy_configuration.xml|r_submix_audio_policy_configuration.xml)
        if [ "$SKIP_POLICY" = 1 ]; then
          log "蓝牙保护: 跳过策略 $rel"
          continue
        fi
        ;;
    esac
    # 1.2 MIUI 兼容档：跨 ROM 的音效/平台/通路配置不替换
    if [ "$LEGACY_ROM" = 1 ]; then
      case "$base" in
        audio_effects.conf|audio_effects.xml|audio_io_policy.conf|\
        audio_platform_info*.xml|media_codecs_dolby_audio.xml|mixer_paths*.xml)
          log "MIUI 兼容: 跳过 $rel"
          continue
          ;;
      esac
    fi
    bind_file "$FILES/common/vendor/etc/$rel" "/vendor/etc/$rel"
  done
fi

# ---------- 2. 机型专属文件 ----------
MODEL_DIR=$FILES/model/$MODEL

# 2.1 mixer overlay（MIX 4 有多档通话增益组合）
VARIANT_FILE=$MODEL_DIR/mixer_paths_overlay_static.xml
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
    # 写到 WORKDIR 再挂载：模块目录只读时 cp 回模块目录会静默失效
    VARIANT_FILE=$WORKDIR/mixer_paths_overlay_selected.xml
    cp -f "$MODEL_DIR/$VARIANT" "$VARIANT_FILE" 2>/dev/null
    chcon u:object_r:vendor_file:s0 "$VARIANT_FILE" 2>/dev/null
  fi
  log "MIX 4 通话档位: $VARIANT"
fi

if [ -f "$MODEL_DIR/mixer_paths_overlay_static.xml" ]; then
  for dst in /vendor/etc/audio/sku_lahaina/mixer_paths_overlay_static.xml \
             /vendor/etc/audio/mixer_paths_overlay_static.xml; do
    [ -e "$dst" ] && bind_file "$VARIANT_FILE" "$dst"
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
  # 建 acdb_thyme 换用小米10s（thyme/kona）整套声学校准（含 adsp_avs_config）
  if [ -f "$MODDIR/acdb_thyme" ] && [ -d "$FILES/model/acdb/thyme" ]; then
    ACDB_SRC=$FILES/model/acdb/thyme
    log "acdb: 使用小米10s(thyme) 校准"
  fi

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
      # adsp_avs_config.acdb 挂在校准目录上一级（acdbdata 根目录）
      if [ -z "$target" ] && [ "$suffix" = "avs_config.acdb" ]; then
        [ -e /vendor/etc/acdbdata/adsp_avs_config.acdb ] && target=/vendor/etc/acdbdata/adsp_avs_config.acdb
      fi
      [ -n "$target" ] && bind_file "$ACDB_SRC/$rel" "$target"
    done
  else
    log "未找到可用的 acdb 目录，跳过校准替换"
  fi
else
  log "检测到 no_acdb，保留原厂声学校准"
fi

# ------------------------------------------------------------------
# 4. 屏录修复：补回 r_submix(远程混音) 音频策略模块
#    坠欢 2026.10.1
#
# 背景：小米屏录录系统内部声音走 AudioPlaybackCapture，依赖名为 r_submix 的
#       audio policy 模块。只要这份模块没出现在生效配置里，注册 audio policy
#       就会返回 -3(NO_INIT)，屏录直接失败，日志为：
#         APM_AudioPolicyManager: Unable to find audio module for submix
#         StableScreenRecorderCore: could not register audio policy
#       另一个坑：XInclude 只要有一个 href 打不开，整份 policy 就会被判解析失败，
#       APM 退回系统默认配置(同样没有 r_submix)。本模块自带的 policy 里有
#       vehicle_display / hearing_aid 两处 include，而这两个文件并没有打包进来，
#       这里统一按断链处理掉。
#
# 模块自带的 4 份主配置已经在打包前把 r_submix 内联好了；
# 这一段负责真机上剩下的边缘情况：/odm/etc、/system/etc 以及所有 sku 变体。
# 幂等：不论文件当前处于哪种形态，重复执行结果都一样。
# ------------------------------------------------------------------

INS=$MODDIR/files/_fix/r_submix_inline.xml

# WORKDIR 已在脚本开头定义：模块目录只读时自动落到 /data/local/tmp
FIX_TMP=$WORKDIR/tmp
REPORT=$WORKDIR/record_fix_report.txt
FOK=0
FFAIL=0
FSKIP=0

copy_con() {
  local dst="$1" src="$2" con
  con=$(ls -Z "$dst" 2>/dev/null | awk 'NF{print $NF; exit}')
  [ -n "$con" ] && chcon "$con" "$src" 2>/dev/null
  case "$dst" in
    /vendor/*|/odm/*) [ -z "$con" ] && chcon u:object_r:vendor_file:s0 "$src" 2>/dev/null ;;
    *)                [ -z "$con" ] && chcon u:object_r:system_file:s0 "$src" 2>/dev/null ;;
  esac
  chmod 0644 "$src" 2>/dev/null
  chown 0:0 "$src" 2>/dev/null
}

fix_policy() {
  local dst="$1"
  local name out needfix=0 HAS=0 MISS=""

  [ -f "$dst" ] || return 1
  grep -q '<audioPolicyConfiguration' "$dst" 2>/dev/null || return 1
  grep -q '<modules' "$dst" 2>/dev/null || return 1

  grep -q '<module name="r_submix"' "$dst" 2>/dev/null && HAS=1 || { HAS=0; needfix=1; }

  # 逐条校验 xi:include 指向的文件是否真的存在
  for href in $(grep -o 'href="[^"]*"' "$dst" 2>/dev/null | sed 's/href="//; s/"$//'); do
    case "$href" in
      /*) chk="$href" ;;
      *)  chk="$(dirname "$dst")/$href" ;;
    esac
    [ -e "$chk" ] || { MISS="$MISS$(basename "$href")|"; needfix=1; }
  done

  if [ "$needfix" -eq 0 ]; then
    echo "$dst : OK(无需修复)" >> "$REPORT"
    FSKIP=$((FSKIP + 1))
    return 0
  fi

  name=$(echo "$dst" | tr '/' '_')
  out="$FIX_TMP/$name"
  rm -f "$out" 2>/dev/null

  awk -v ins="$INS" -v miss="$MISS" -v has="$HAS" '
    BEGIN { done = 0; n = split(miss, A, "|") }
    index($0, "xi:include") > 0 && index($0, "r_submix") > 0 {
      while ((getline L < ins) > 0) print L
      close(ins)
      done = 1
      next
    }
    index($0, "xi:include") > 0 {
      for (i = 1; i <= n; i++) {
        if (A[i] != "" && index($0, A[i]) > 0) next
      }
    }
    index($0, "</modules>") > 0 && done == 0 && has == 0 {
      while ((getline L < ins) > 0) print L
      close(ins)
      done = 1
      print
      next
    }
    { print }
  ' "$dst" > "$out" 2>/dev/null

  grep -q '<module name="r_submix"' "$out" 2>/dev/null || {
    echo "$dst : 修复失败(r_submix 未生成)" >> "$REPORT"
    rm -f "$out" 2>/dev/null
    FFAIL=$((FFAIL + 1))
    return 1
  }
  grep -q '</audioPolicyConfiguration>' "$out" 2>/dev/null || {
    echo "$dst : 修复失败(结构损坏, 已丢弃)" >> "$REPORT"
    rm -f "$out" 2>/dev/null
    FFAIL=$((FFAIL + 1))
    return 1
  }

  copy_con "$dst" "$out"

  if mount -o bind "$out" "$dst" 2>/dev/null || mount --bind "$out" "$dst" 2>/dev/null; then
    echo "$dst : FIXED(r_submix 已就位)" >> "$REPORT"
    FOK=$((FOK + 1))
    return 0
  fi

  echo "$dst : 挂载失败" >> "$REPORT"
  rm -f "$out" 2>/dev/null
  FFAIL=$((FFAIL + 1))
  return 1
}

rm -rf "$FIX_TMP" 2>/dev/null
mkdir -p "$FIX_TMP" 2>/dev/null

{
  echo "==== DisMiSound 屏录修复自检 $(date) ===="
  echo "device=$(getprop ro.product.device) rom=$(getprop ro.build.display.id)"
} > "$REPORT" 2>/dev/null

FIX_CAND=""
for p in /vendor/etc/audio_policy_configuration.xml \
         /vendor/etc/audio/audio_policy_configuration.xml \
         /odm/etc/audio_policy_configuration.xml \
         /odm/etc/audio/audio_policy_configuration.xml \
         /system/etc/audio_policy_configuration.xml; do
  [ -f "$p" ] && FIX_CAND="$FIX_CAND $p"
done
for p in $(find /vendor/etc/audio /odm/etc/audio -maxdepth 2 -type f -name 'audio_policy_configuration*.xml' 2>/dev/null); do
  FIX_CAND="$FIX_CAND $p"
done

SEEN=""
for dst in $FIX_CAND; do
  echo "$SEEN" | grep -q -w "$dst" && continue
  SEEN="$SEEN $dst"
  fix_policy "$dst"
done

# r_submix HAL 是否可用：策略修好了，但真正建 audio patch 还需要这个库
FHAL=0
for lib in /vendor/lib64/hw/audio.r_submix.default.so \
           /vendor/lib/hw/audio.r_submix.default.so \
           /system/lib64/hw/audio.r_submix.default.so \
           /system/lib/hw/audio.r_submix.default.so \
           /system_ext/lib64/hw/audio.r_submix.default.so \
           /system_ext/lib/hw/audio.r_submix.default.so; do
  [ -f "$lib" ] && { echo "HAL : $lib" >> "$REPORT"; FHAL=1; }
done
[ "$FHAL" -eq 0 ] && echo "HAL : 未找到 audio.r_submix.default.so —— 仍需补 r_submix HAL, 见 README" >> "$REPORT"

{
  echo "修复: 注入 $FOK 项, 无需修复 $FSKIP 项, 失败 $FFAIL 项"
} >> "$REPORT" 2>/dev/null
log "屏录修复: 注入 $FOK 项, 无需修复 $FSKIP 项, 失败 $FFAIL 项"

# ------------------------------------------------------------------
# 5. 音质音效（com.miui.misound）打开即闪退修复
#    坠欢 2026.10.2
#
#    澎湃 OS 4 上官方「音质音效」一进就 FC，堆栈是这样的：
#      java.lang.NullPointerException: Attempt to invoke virtual method
#        'void d0.e.g()' on a null object reference
#        at d0.d.F(...)   <- MiSoundUtils.initMiSoundIfNeed()
#        at d0.d.i(...)   <- MiSoundUtils.isEnabled()
#        at h.i.F0(...)   <- HeadsetSettings.getEnabledEffect()
#        at h.i.onCreatePreferences(...)
#
#    根因在 MiSoundUtils 自己身上，两处叠加：
#      1) initialize() 先把 mInitialized 置成 true，再去 new MiSound(0, 0)。
#         MiSound 一旦创建失败（反射不到 android.media.audiofx.MiSound，
#         或者 AudioEffect 引擎当时起不来），异常被 catch 吞掉打一行 log，
#         但 mInitialized 已经是 true —— 之后 g() 变成空转，永远不再重试，
#         mMiSound 就此恒为 null。
#      2) initMiSoundIfNeed() 拿到 hasControl()==false 之后，直接
#         mMiSound.release()，既没判空也没 try/catch。上一步留下 null，
#         这里必然 NPE，而且是抛在 catch 范围外的，进程直接崩。
#
#    修法：classes.dex 里这两处改掉（判空 + try/catch + 失败复位标志位），
#    重新签名后在这里 bind mount 覆盖系统里的 MiSound.apk。
#    原分区文件一个字节不动；放 no_misound_patch 或卸载即还原。
# ------------------------------------------------------------------

PATCH_APK=$FILES/app/MiSound-patched.apk

# 默认不再覆盖系统 App：独立版 com.dismisound.audiofx 已经能干同样的事，
# 想连系统自带那个一起修就建 misound_patch。
if [ ! -f "$MODDIR/misound_patch" ]; then
  echo "音质音效系统覆盖: 未启用（建 misound_patch 开启，独立版不受影响）" >> "$REPORT" 2>/dev/null
else
  if [ -f "$PATCH_APK" ]; then
    MISOUND_CAND=""
    for d in /system/app /system/priv-app \
             /system/product/app /system/product/priv-app \
             /product/app /product/priv-app \
             /system_ext/app /system_ext/priv-app \
             /vendor/app /odm/app; do
      [ -d "$d" ] || continue
      for sub in "$d"/*; do
        [ -d "$sub" ] || continue
        case "$(basename "$sub")" in
          *[Mm]i[Ss]ound*|*[Mm]isound*) ;;
          *) continue ;;
        esac
        for apk in "$sub"/*.apk; do
          [ -f "$apk" ] && MISOUND_CAND="$MISOUND_CAND $apk"
        done
      done
    done

    HIT=0
    for apk in $MISOUND_CAND; do
      # 同一个分区可能同时被 /system/xxx 和 /xxx 两条路径指到，挂一次就够
      if grep -q " $apk " /proc/mounts 2>/dev/null; then
        echo "$apk : 已被本模块覆盖" >> "$REPORT" 2>/dev/null
        HIT=1
        continue
      fi
      con=$(ls -Z "$apk" 2>/dev/null | awk 'NF{print $NF; exit}')
      if [ -n "$con" ]; then
        chcon "$con" "$PATCH_APK" 2>/dev/null
      else
        chcon u:object_r:system_file:s0 "$PATCH_APK" 2>/dev/null
      fi
      chmod 0644 "$PATCH_APK" 2>/dev/null
      chown 0:0 "$PATCH_APK" 2>/dev/null
      if mount -o bind "$PATCH_APK" "$apk" 2>/dev/null \
         || mount --bind "$PATCH_APK" "$apk" 2>/dev/null; then
        echo "$apk : 已替换为修复版（MiSoundUtils NPE 已修）" >> "$REPORT" 2>/dev/null
        log "音质音效修复包已挂载: $apk"
        HIT=1
      else
        echo "$apk : 挂载失败（签名不匹配的机器请改用非覆盖方式）" >> "$REPORT" 2>/dev/null
        log "音质音效修复包挂载失败: $apk"
      fi
    done

    [ "$HIT" -eq 0 ] && echo "音质音效修复包: 系统里没找到 MiSound.apk，跳过" >> "$REPORT" 2>/dev/null
  else
    echo "音质音效修复包: files/app/MiSound-patched.apk 缺失，跳过" >> "$REPORT" 2>/dev/null
  fi
fi

# ------------------------------------------------------------------
# 6. 小米10s 混搭音效包（028黑鲨） 坠欢 2026.10.11
#
# 与小米10s「028黑鲨混搭音效」二改版（原作者 酷安@浮尘染溪哦）融合：
#   6.1 qcom soundfx 音效库（lib / lib64，只挂原厂已有同名文件）
#   6.2 misound ADSP 资源（卡拉OK / 耳机米音等 DSP 资源，只挂已存在的）
#   6.3 MusicFX（028黑鲨音效界面，apk + oat，找到哪挂哪）
# 默认关闭；在模块目录建 mi10s_fx 开启。
# 注意：音效库来自 kona（小米10s）vendor，如开音效后 audioserver 异常，
# 删掉 mi10s_fx 重启即可还原，无需卸载模块。
# ------------------------------------------------------------------
if [ -f "$MODDIR/mi10s_fx" ]; then
  M10=$FILES/mi10s
  log "mi10s_fx: 挂载小米10s 混搭音效包"
  M10_OK=0
  # 6.1 音效库
  for d in lib lib64; do
    [ -d "$M10/vendor/$d/soundfx" ] || continue
    for f in "$M10/vendor/$d/soundfx"/*; do
      rel="/vendor/$d/soundfx/$(basename "$f")"
      if [ -e "$rel" ]; then
        bind_file "$f" "$rel" && M10_OK=$((M10_OK + 1))
      fi
    done
  done
  # 6.2 misound DSP 资源
  for f in "$M10/vendor/lib/rfsa/adsp/"misound*.bin; do
    [ -f "$f" ] || continue
    rel="/vendor/lib/rfsa/adsp/$(basename "$f")"
    if [ -e "$rel" ]; then
      bind_file "$f" "$rel" && M10_OK=$((M10_OK + 1))
    fi
  done
  # 6.3 MusicFX（/system、/product、/system_ext 哪找到挂哪）
  if [ -d "$M10/system" ]; then
    for f in $(find "$M10/system" -type f 2>/dev/null); do
      rel=${f#"$M10/system"}
      for pre in /system /product /system_ext; do
        if [ -e "$pre$rel" ]; then
          bind_file "$f" "$pre$rel" && M10_OK=$((M10_OK + 1))
          break
        fi
      done
    done
  fi
  log "mi10s_fx: 完成 $M10_OK 项"
else
  log "mi10s_fx: 未开启（建 mi10s_fx 启用小米10s 混搭音效包）"
fi

log "挂载完成: 成功 $OK 项，失败 $FAIL 项"
exit 0
