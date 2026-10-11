# DisMiSound 888s 更新日志

> 酷安 [@坠欢啊] 自研，二改需本人认可

---

## 2026.10.11

兼容性大修 + 与小米10s「028黑鲨混搭音效」二改版（原作者 酷安@浮尘染溪哦）融合。
版本号改为日期制。

### 修复

1. **Magisk（面具）刷入报 `! Unzip error`**
   10.2 的 zip 里缺少 `META-INF/com/google/android/update-binary`。
   面具刷模块的第一步就是把 zip 里的安装器解出来，解不到直接报错退出；
   KernelSU / APatch 不需要这个文件，所以只在面具上翻车。
   现已补回标准安装器（update-binary + updater-script），三种 root 方案表现统一。

2. **小米11 Ultra 蓝牙失效：耳机 / 车载的媒体和通话全从扬声器出声**
   根因：模块自带的主策略 `audio_policy_configuration.xml` 把 A2DP 写成旧式
   primary 内联端口，整包覆盖原厂策略后，原厂 `bluetooth_qti` 策略模块不再被
   加载，A2DP / HFP 注册不出来，音频路由全部回落扬声器。
   处理：默认不再整包替换任何音频策略（含 `a2dp` / `bluetooth_qti` /
   `r_submix` / `audio_policy_configuration`），策略交还原厂；
   屏录所需的 r_submix 改由 post-fs-data 里的自适应注入直接补进原厂策略，
   屏录修复效果不变。需要旧行为请在模块目录建 `policy_patch`。

3. **MIUI14 刷入卡第一屏**
   根因：模块的策略 / 音效 / 平台配置取自澎湃 OS4，直接 bind 到 MIUI
   （Android 12/13）的 vendor 上，audioserver 解析不兼容后反复崩溃，
   开机动画停在第一屏。
   处理：post-fs-data 开机自动识别 ROM（`ro.mi.os.version.name` /
   `ro.miui.ui.version.name`）。MIUI 上自动进**兼容档**：只保留 acdb 声学校准、
   smart PA 固件、ADSP 资源、机型 mixer overlay（目标存在才挂）和独立版 App，
   其余跨 ROM 的整包替换一律跳过。需在 MIUI 上强制全量挂载建 `full_patch`。

### 新增 / 融合

4. **小米10s 028黑鲨混搭音效包**（默认关闭，模块目录建 `mi10s_fx` 开启）
   只挂原厂已有同名文件，找不到就跳过：
   - qcom soundfx 音效库（lib / lib64 各 17 个）—— 028黑鲨混搭的实现层
   - misound ADSP 资源：`misound_res.bin`、`misound_res_headphone.bin`、
     `misound_karaoke_res.bin`、`misound_karaokemix_res.bin`
   - MusicFX（028黑鲨音效界面，apk + oat，/system、/product、/system_ext 找到哪挂哪）

5. **`acdb_thyme`**
   建该文件把声学校准整套换成小米10s（thyme/kona）的 Tutu 校准组
   （含 `adsp_avs_config.acdb`）。默认仍用本模块原校准，建 `no_acdb` 保留原厂。

### 其它调整

- post-fs-data / service 的日志与临时文件，在模块目录只读时
  （KernelSU `meta-overlayfs` 等模式）自动改写到 `/data/local/tmp/DisMiSound_888s`，
  不再静默失败；自检报告仍会导出到 `/sdcard/Download`。
- MIX 4 通话档位变体（tx_off / tx_high / rx_max）不再 cp 回模块目录，
  改写到工作目录后再挂载，只读模块目录也能正常切换档位。

### 开关一览

| 开关 | 作用 | 默认 |
| --- | --- | --- |
| `policy_patch` | 恢复旧的整包策略替换（可能重现蓝牙失效） | 关 |
| `full_patch` | 在 MIUI 上强制全量挂载（可能卡第一屏） | 关 |
| `mi10s_fx` | 小米10s 028黑鲨混搭音效包 | 关 |
| `acdb_thyme` | 换用小米10s 声学校准组 | 关 |
| `tx_off` / `tx_high` / `rx_max` | MIX 4 通话上行增益 / 听筒 Boost 档位 | 原版增益 |
| `no_acdb` | 保留原厂声学校准 | 关 |
| `misound_patch` | 覆盖系统「音质音效」为修复版 MiSound.apk | 关 |
| `no_misound_fix` | 跳过哈曼卡顿 / 权限补发 | 关 |
| `force_harman` | 音效实施者钉死为哈曼卡顿 | 关 |
| `misound_full` | 打开场景音效 / 耳道适配 / misoundasc | 关 |
| `model` | 写死机型代号（venus / star / haydn / odin） | 自动识别 |

—— 坠欢 2026.10.11

---

## 2026.10.2（fix3）

- 修复澎湃 OS 4 官方「音质音效」打开即闪退：`MiSoundUtils` 空指针
  （`initialize()` 提前置 `mInitialized=true` 导致 `mMiSound` 恒为 null，
  `initMiSoundIfNeed()` 里 `release()` 未判空未捕获异常）。
  classes.dex 补判空 + try/catch + 失败复位标志位，重签名后由 `misound_patch`
  开关控制是否覆盖系统 MiSound.apk（默认不覆盖）。
- 开启 MIX 4 哈曼卡顿：`ro.vendor.audio.sfx.harmankardon=true`。
- 追加独立版「音质音效」App（com.dismisound.audiofx），开机自动安装、
  自动补发权限，与模块开关互通，不覆盖任何系统文件。
- system.prop 把哈曼卡顿单独打开，米音其余开关仍保持链路干净。

## 2026.10.1

- 修复屏幕录制失败：修正 audio policy 缺少 `r_submix`（远程混音）模块导致的
  屏录失败（`Unable to find audio module for submix` / `could not register audio policy`）。
  账号适配 includes 断链：策略里指向不存在文件的 `xi:include` 会被剔除，
  否则整份 policy 解析失败后 APM 退回默认配置（同样没有 r_submix）。
- 幂等：重复刷新结果一致。

## 初版

- 针对骁龙 888（SM8350 / lahaina）机型重写整套音频栈：
  通路配置、声学校准、ADSP 固件、音频策略、音效引擎、蓝牙编解码逐层重做，
  配合一组系统属性打开 HAL 全部能力（硬件 offload、高码率、低延迟）。
- 支持 Magisk / KernelSU / APatch，vendor 文件由 post-fs-data 手工 bind mount
  + 重新打 SELinux 标签，三家行为一致（解决旧版 KSU/APatch 挂载权限不足）。
