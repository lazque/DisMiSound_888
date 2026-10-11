# ［小米 888 系列］音频通路优化　DisMiSound 888s

> 酷安 [@坠欢啊] 自研
> 二次修改 / 重新打包 / 搬运，请先取得本人认可

本模块针对骁龙 888（SM8350 / lahaina）这一代机型，把整套音频栈——通路配置、声学校准、ADSP 固件、音频策略、音效引擎、蓝牙编解码——逐层重做，再配合一组系统属性把 HAL 的能力全部打开。

---

## 支持机型

| 代号 | 机型 |
| --- | --- |
| `venus` | 小米 11 标准版 |
| `star` | 小米 11 Pro / 11 Ultra（含 `mars` 子型号） |
| `haydn` | 红米 K40 Pro / Pro+ |
| `odin` | 小米 MIX 4 |

Root 方案：Magisk / KernelSU / APatch 全部支持。模块不依赖任何一家的私有挂载方式，vendor 侧文件由开机阶段自行挂载，三家行为完全一致。

---

## 一、音频通路：整套重写，不是单纯改音量

两个核心文件：

```text
/vendor/etc/audio/sku_lahaina/mixer_paths.xml
/vendor/etc/audio/sku_lahaina/mixer_paths_overlay_static.xml
```

### 1. 播放通路全量重配

`deep-buffer`、`low-latency`、`audio-ull`（超低延迟）、`compress-offload` 1~9 共九条 offload 通路，以及它们各自的 `speaker`、`headphones`、`handset`、`display-port`、`usb-headphones`、`bt-sco`、`bt-a2dp` 组合分支，全部重设。

涉及的控制项包括 `WSA_RX0/RX1`、`RX_RX0~RX2` 数字音量、耳机左右声道增益、各路 Switch 的开合顺序。耳放档位按场景区分：主输出给到 20，部分低负载回放分支收到 16，避免小音量下细节被压掉，也避免大音量顶到失真。

其中 `speaker-protected` 分支单独走智能功放保护通道，外放命中的是 cs35l41 的保护算法路径，而不是裸 PA 直出。

### 2. 通话与 VoIP 通路

`compress-voip-call`（含 `bt-sco` / `headphones` / `usb` / `afe-proxy` 各分支）、`audio-playback-voip`、`voicemmode1/2-call` 全部重设。

听筒侧的 `RCV AMP PCM Gain` 按用途分成三档：**旁路 6 / 通话 18 / 回放 20**。通话场景吃的是专门为语音调整的那一档，而不是沿用音乐通路的参数。

### 3. 小米超声波 Sensing 通路

`ultrasound-proximity`、`-output`、`-input`、`rampdown`、`screen-on`、`suspend`、`stop-report` 这一整套保留并重设，抬手亮屏、通话息屏这些依赖超声波检测的场景不会因为通路改动而失效。

### 4. 回声参考通路

`echo-reference` 与 `echo-reference-voip`（`speaker`、`earpiece`、`headphones`）独立配置，VoIP 通话的双工降噪能拿到干净的参考信号。

### 5. 智能功放 cs35l41 参数

Class-H 升压追踪使能，并根据 use case 切换不同的 Delta File（`spk2_playback_delta` / `spk2_voice_delta` / `rcv_voice_delta`）；听筒（RCV）和扬声器分开设置升压目标电压，各机型给到合适档位。MIX 4 的听筒 Boost 电压与其余机型取值不同，因为是两种听筒器件。

### 6. 多版本底板

除主 `mixer_paths` 外还带了 `mixer_paths_cdp` / `hdk` / `qrd` / `hhg` 四套底板和 `overlay_dynamic`，覆盖不同 SKU 的机型变体。

---

## 二、声学校准（acdb）

```text
Tutu_*  （venus / star / odin）  小米 11 系列同款声学标定
Forte_* （haydn）                 K40 Pro 系列适用的标定
```

每个机型包含 `Bluetooth` / `General` / `Global` / `Handset` / `Speaker` / `Headset` / `Hdmi` 七份 `*_cal.acdb`，外加 `workspaceFile.qwsp` 工程档。

acdb 里装的是麦克风灵敏度、TX/RX 频响补偿、器件线性度、扬声器特性这些数据。原厂给的那套偏保守，这套标定把听筒、扬声器、耳机三条路的目标响度曲线都抬了一档，声音不再是「蒙了一层」的状态。

不同 ROM 的校准目录名不一样（Tutu / Forte 之类），模块会自动探测机器上真实在用的目录再挂载，不会把别的机型的上行标定错装到你的目录上。

---

## 三、ADSP 固件与喇叭保护

```text
/vendor/firmware/cs35l41-dsp1-diag-z-*.bin
/vendor/firmware/cs35l41-dsp1-spk-prot-*.bin
/vendor/lib/rfsa/adsp/misound_res_spk.bin
```

cs35l41 是这代机器用的 smart PA。`diag` 与 `spk-prot` 两份固件分别对应诊断模式和保护模式，听筒（RCV）另有一套独立 variant。`misound_res_spk.bin` 是 ADSP 侧的扬声器资源文件，外放的低频管理算法读的就是它。

---

## 四、音频策略与平台信息

```text
audio_policy_configuration.xml（含新版布局）
sku_lahaina / sku_lahaina_qssi 目录下的 policy
audio_platform_info.xml 及 _hdk / _intcodec / _qrd 三份变体
audio_io_policy.conf
a2dp_audio_policy_configuration.xml
bluetooth_qti_audio_policy_configuration.xml
r_submix_audio_policy_configuration.xml
```

把音频模块、输入源、设备之间的路由关系和设备能力描述重写了一遍：USB 声卡、蓝牙 A2DP / SCO、r_submix（录屏内录）、新版 qssi policy 布局都覆盖到，不会再出现「某些场景被路由到低质量 output」的情况。

---

## 五、音效引擎

配置文件：`/vendor/etc/audio_effects.conf` 与 `.xml`

启用的库包括：

| 类别 | 库名 |
| --- | --- |
| 基础音染 | `equalizer`、`bassboost`、`virtualizer`、`reverb`（aux/ins、pre/ins 四组） |
| 分析与多声道 | `visualizer`、`downmix`、`loudness_enhancer`、`dynamics_processing` |
| 硬件加速 | `hw_acc`（offload_bundle）、`volume` |
| 空间音频 | `audiosphere`、`shoebox`、`ozo_processing` |
| 交互 | `haptic_effect`、`volume_listener`（music / ring / alarm / voice / notification 五种 helper） |
| 前处理 | `audio_pre_processing`：`aec`（回声消除）、`ns`（降噪） |

重点是 `offload_bundle` 和 `hw_acc`：开启之后均衡、低频增强这类处理可以在 DSP 侧完成，不再占用 CPU 去做软件重采样。

---

## 六、杜比解码能力

配置文件：`/vendor/etc/media_codecs_dolby_audio.xml`

声明 `audio/ac3`、`audio/eac3`、`audio/eac3-joc`、`audio/ac4` 四种类型。带杜比内容的流媒体和本地片源能正常走硬件解码，不会被系统转成 PCM 降级处理。

---

## 七、硬件特性声明

```text
android.hardware.audio.low_latency
android.hardware.audio.pro
```

声明之后系统会把本机识别为「低延迟音频设备」和「专业音频设备」，各类播放器、USB 音频、录音类 APP 会自动切到高速通道，相关的能力限制也会一并放开。

---

## 八、补齐米音音效面板

```text
/system/priv-app/MusicFX（com.miui.audioeffect）
```

部分第三方 ROM 把这个 App 精简掉了，音效设置进去是空的或者干脆打不开。模块把它补回去，调节界面可以正常使用。

---

## 九、系统属性：把 HAL 的能力全部打开

### 高码率输出

```properties
audio.offload.pcm.16bit.enable=true
audio.offload.pcm.24bit.enable=true
audio.offload.pcm.32bit.enable=true
audio.offload.pcm.float.enable=true
persist.audio.format.24bit=true
persist.audio.format.32bit=true
persist.audio.format.float=true
vendor.audio.offload.track.enable=true
vendor.audio.offload.multiple.enabled=true
vendor.audio.offload.passthrough=true
```

offload 通路支持 16 / 24 / 32bit 和浮点 PCM，多音轨并行 offload 一并打开，不会再出现 music 流被系统从 offload 降级到 deep-buffer 的情况。

### 低延迟

```properties
aaudio.mmap_policy=2
aaudio.mmap_exclusive_policy=2
aaudio.hw_burst_min_usec=2000
vendor.audio_hal.period_multiplier=2
vendor.audio.adm.buffering.ms=3
vendor.audio.offload.buffer.size.kb=128
af.fast_track_multiplier=1
```

AAudio 直达模式优先，中间层不再多写一次缓冲；offload 缓冲给到 128KB，突发写入更少，低延迟场景不会因为缓冲太小频繁申请而被系统拖回普通通路。

### 采样率与重采样

```properties
af.resampler.quality=12
persist.dev.pm.dyn_samplingrate=1
persist.vendor.audio.format.24bit=true
persist.vendor.audio.format.32bit=true
persist.vendor.audio.format.float=true
audio.playback.mch.downsample=true
vendor.audio.feature.hifi_audio.enable=true
```

重采样器质量拉到最高档；打开动态采样率，播放 44.1k 的内容时 HAL 直接跑 44.1k，不再统一到 48k 过一遍 SRC。这一条是整个模块里听感提升最明显的项之一。

### 硬件通路

```properties
vendor.audio.tunnel.encode=true
vendor.audio.tunnel.decode=true
audio.deep_buffer.media=true
vendor.audio.spkr_prot.tx.sampling_rate=96000
```

编解码启用硬件隧道（tunnel）模式，压缩码流直通 DSP；deep-buffer 明确给媒体流使用；喇叭保护的反馈采样提到 96k，保护算法的判断更准，大动态下不容易误限。

### 关闭干扰项

```properties
persist.vendor.audio.bcl.enabled=false
persist.vendor.audio.ras.enabled=false
vendor.audio.feature.ras.enable=false
vendor.audio.feature.src_trkn.enable=false
ro.vendor.audio.misound.bluetooth.enable=false
ro.vendor.audio.soundfx.usb=false
ro.vendor.audio.sfx.earadj=false
ro.vendor.audio.sfx.scenario=false
ro.vendor.audio.game.mode=false
persist.vendor.audio.misoundasc=false
```

上面这些后处理每一道都会把信号再加工一遍，放着的后果就是前面做好的高码率 offload 被重新采样回去。统一关掉，链路才是干净的。

> `ro.vendor.audio.sfx.harmankardon` 已从这一组里摘出来，改成 `true`，
> 见文末「坠欢 2026.10.2 补充」。

### 蓝牙

```properties
persist.bluetooth.a2dp_offload.cap=sbc-aptx-aptxtws-aptxhd-aptxadaptiver2-aac-lc3-ldac-lhdc
persist.vendor.qcom.bluetooth.aac_frm_ctl.enabled=true
persist.vendor.qcom.bluetooth.aac_vbr_ctl.enabled=true
persist.vendor.bt.aac_frm_ctl.enabled=false
persist.vendor.bt.aac_vbr_frm_ctl.enabled=false
bluetooth.profile.bap.broadcast.assist.enabled=true
bluetooth.profile.bap.unicast.client.enabled=true
bluetooth.profile.bap.broadcast.source.enabled=true
bluetooth.profile.vcp.controller.enabled=true
bluetooth.profile.avrcp.controller.enabled=true
bluetooth.profile.sap.server.enabled=true
```

（上面第 1 条在 `persist.bluetooth.*`、`persist.vendor.bt.*`、`persist.vendor.qcom.bluetooth.*`、`persist.vendor.btstack.*` 四组目录中均下发。）

offload 能力里集齐 aptX TWS / aptX HD / aptX Adaptive R2 / LDAC / LHDC / LC3；AAC 的帧控制交回高通实现，VBR 控制打开。LE Audio 的 BAP 广播与单播、VCP 音量控制一并启用，新的 TWS 耳机能吃到 LE 通道而不是只能走传统 SBC / A2DP。

---

## 十、开关

在模块目录放同名空文件，重启生效；删掉文件重启即回默认。

| 文件 | 作用 |
| --- | --- |
| `no_acdb` | 不替换声学校准，只保留通路优化 |
| `tx_off` | MIX 4：通话上行不额外提升 |
| `tx_high` | MIX 4：通话上行再高一档 |
| `rx_max` | MIX 4：保留更大的听筒升压 |
| `model` | 内容写机型代号，识别不到时手动指定 |
| `no_misound_patch` | 不覆盖系统的 MiSound.apk |
| `no_misound_fix` | 不改哈曼卡顿开关、不补发权限 |
| `force_harman` | 把默认音效实施者钉成 `harmankardon` |
| `misound_full` | 连场景音效 / 耳道适配 / misoundasc 一起打开 |

---

## 十一、安装

1. 卸载旧版同名模块
2. 在管理器里刷入本模块
3. 重启后先用中等以上音量听一轮，让 ADSP 侧保护算法完成自适应
4. 出现异常时把模块目录下的 `mount.log` 连同机型代号一起反馈

本版的挂载方式对 Magisk / KernelSU / APatch 三家做了统一，通话的上行电平与听筒泄漏量也重新校准过，不再需要额外补丁。

---

## 备注

音频调校主观性很强，喜欢偏响还是偏淡，用上面的开关自己试。刷机有风险，操作前请自行备份。

**酷安 @坠欢啊 自研**
**二次修改 / 重新打包 / 搬运，请先取得本人认可**


---

## 坠欢 2026.10.1 补充：屏幕录制修复（r_submix 音频策略）

屏录失败这部分由坠欢于 2026.10.1 修复并合入本模块，与原版音频优化是一体的，
不需要再刷其它东西。

小米屏录录系统内部声音时走 AudioPlaybackCapture，底层依赖音频策略里
名为 r_submix（远程混音）的模块。原模块覆盖的 vendor 音频策略里，这个模块
没有真正进入生效配置，于是每次录制都会走到这条失败链：

    E APM_AudioPolicyManager: Unable to find audio module for submix, aborting mix 0 registration
    W AS.AudioService: IllegalStateException: Could not connect mix, error: -3
    E StableScreenRecorderCore: java.lang.UnsupportedOperationException:
                                Error: could not register audio policy
    E StableScreenRecorderCore: finalize success=false muxerOk=true videoFrames=0
    I RecorderService: miui.screenrecorder.record.fail

视频编码器其实是正常起来的，卡的是音频 policy 注册，应用随后整体回滚，
最终 0 帧、录制失败。

另一个隐藏问题：XInclude 只要有一个 href 指向的文件不存在，整份
audio_policy_configuration.xml 就会被判解析失败，APM 随即退回系统默认配置
（那份同样没有 r_submix）。本模块自带的 policy 里引用了
vehicle_display_audio_policy_configuration.xml 和
bluetooth_qti_hearing_aid_audio_policy_configuration.xml，
而这两个文件并没有打包进来，属于断链。

### 修复方式

1. 打包前已把 4 份主配置里的 r_submix include 离线内联为完整模块定义：
   - vendor/etc/audio_policy_configuration.xml
   - vendor/etc/audio/audio_policy_configuration.xml
   - vendor/etc/audio/sku_lahaina/audio_policy_configuration.xml
   - vendor/etc/audio/sku_lahaina_qssi/audio_policy_configuration.xml
2. post-fs-data.sh 新增第 4 阶段，在挂载全部完成后做真机兜底：
   扫描 /vendor、/odm、/system 下所有生效的主配置，缺 r_submix 就注入，
   并把指向不存在文件的 include 删掉。执行顺序天然在本模块自己的 bind mount
   之后，不需要任何额外的挂载前提。
3. 全部操作都是生成副本后 bind mount，原分区文件一个字节都没改，卸载即还原。
   脚本幂等，重复刷写 / 重复开机结果一致。

### 查看结果

- /data/adb/modules/DisMiSound_888s/record_fix_report.txt
- /sdcard/Download/DisMiSound-recordfix.txt（开机后由 service.sh 复制）
- /data/adb/modules/DisMiSound_888s/mount.log 里也带 r_submix 校验行

报告里若出现这一行：

    HAL : 未找到 audio.r_submix.default.so

说明这台机器的 ROM 连 r_submix 的 HAL 库都没有。策略补上了，但真正建立
audio patch 还需要这个库，需另行放到 /vendor/lib64/hw/ 下（可从同 ROM 的
/system/lib64/hw/ 找同名文件，或取 AOSP
hardware/libhardware/modules/audio_remote_submix 的编译产物）。

### 临时绕过

只想马上录到视频：屏录界面的声音来源改成「麦克风」或「不录声音」，绕开
内录路径即可正常录制，代价是录不到系统内部声音。

---

屏录修复部分 —— 坠欢 2026.10.1

---

## 坠欢 2026.10.2 补充：修复「音质音效」闪退 + 开启 MIX 4 哈曼卡顿

澎湃 OS 4 上官方「音质音效」（`com.miui.misound`）一点开就停止运行。
这一版顺手把它修掉，并把 MIX 4 的哈曼卡顿一并打开。

### 崩溃长这样

    java.lang.NullPointerException: Attempt to invoke virtual method
      'void d0.e.g()' on a null object reference
      at d0.d.F(...)    MiSoundUtils.initMiSoundIfNeed()
      at d0.d.i(...)    MiSoundUtils.isEnabled()
      at h.i.F0(...)    HeadsetSettings.getEnabledEffect()
      at h.i.onCreatePreferences(...)

### 为什么必崩

反编译后能看到 `MiSoundUtils` 里的两处硬伤：

1. `initialize()` 先把 `mInitialized` 置成 `true`，再去 `new MiSound(0, 0)`。
   MiSound 只要创建失败一次（反射不到 `android.media.audiofx.MiSound`，
   或者 AudioEffect 引擎那会儿还没起来），异常被 `catch` 吞掉只打一行 log，
   但标志位已经是 `true` —— 之后重建函数变成空转，`mMiSound` 永久为 `null`。
2. `initMiSoundIfNeed()` 拿到 `hasControl() == false` 之后直接
   `mMiSound.release()`，既没判空也没 `try/catch`。上一步留下 `null`，
   这里必然 NPE，而且抛在 catch 范围之外，主线程直接崩。

`hasControl()` 自己把 NPE 当普通 `Exception` 吞了返回 `false`，所以真正
致命的是第 2 处。**只要 MiSound 有一次没起来，之后每次打开都必崩**，
重启也一样 —— 因为 `mInitialized` 那个标志位只在进程内存里，但每次进程
起来都会先失败一次，然后走到同一条路。

完整的反编译证据和改动点写在模块内
`patch/MiSoundUtils-NPE-fix.txt`，这里不重复。

### 修法

* `initialize()`：new 成功才置标志位，失败则复位，保证下次还能重试；
  同时把 catch 里的 `move-exception` 从 `p0` 挪到 `v2`，否则 catch 块里
  拿不到 `this`，写不了字段。
* `initMiSoundIfNeed()`：`release` 前判空 + 包 `try/catch`。MiSound 真的
  不可用时，音效开关显示为不可用，App 正常打开，不再 FC。

打包上只替换 `classes.dex`，其余 1918 个条目逐条 CRC 校验一致；dex 版本
按 minSdk 33 重新生成为 `040`（原包 `039`，用默认的 `035` 会触发
"Interface virtual method ... is not public" 校验告警）；重新签名
（v1 + v2 + v3）+ zipalign。

产物：`files/app/MiSound-patched.apk`。
开机时 `post-fs-data.sh` 会自动扫描系统里的 MiSound.apk 并 bind mount 覆盖，
原分区文件一个字节不动。

### 开启 MIX 4 哈曼卡顿

App 判断哈曼卡顿能不能用，读的是这两个值：

```properties
ro.vendor.audio.sfx.harmankardon=true
```

```
settings put global settings_system_harman_kardon_enable 1
```

原版模块为了保持链路干净，把 `ro.vendor.audio.sfx.harmankardon` 写成了
`false`，于是「音效选择」里的哈曼卡顿项直接被摘掉（`HarmanKardon is not
supported`）。这一版改成 `true`，`service.sh` 里再把全局开关写成 1，
MIX 4 的哈曼卡顿立体声就能选了。

想一步到位把默认音效实施者钉成哈曼卡顿，在模块目录建 `force_harman`；
想把场景音效 / 耳道适配 / misoundasc 这些后处理也一起开回来，建
`misound_full`（注意：开了之后 offload 链路会被再加工一遍）。

### 一个需要知道的前提

覆盖安装后签名变了，系统级权限会被收回。`service.sh` 已经用
`pm grant` 补发 `WRITE_SECURE_SETTINGS`、`MODIFY_AUDIO_ROUTING`、
`BLUETOOTH_PRIVILEGED` 等；个别 ROM 上 `pm grant` 补不上去的话，
调节音效时可能写不进设置，这时在模块目录建 `no_misound_patch`
退回官方原版 APK（闪退本身的修复依赖这个覆盖，取舍自己定）。

### 查看结果

- `/data/adb/modules/DisMiSound_888s/record_fix_report.txt` 末尾的
  「音质音效修复包」几行
- `/data/adb/modules/DisMiSound_888s/mount.log` 里的 `-- 音质音效 --` 段
- `getprop ro.vendor.audio.sfx.harmankardon` 应为 `true`

### 开关

| 文件 | 作用 |
| --- | --- |
| `no_misound_patch` | 不覆盖系统 MiSound.apk |
| `no_misound_fix` | 不动哈曼卡顿开关、不补发权限 |
| `force_harman` | 默认音效实施者钉成哈曼卡顿 |
| `misound_full` | 场景音效 / 耳道适配 / misoundasc 一起开 |

---

### 还有一层：KernelSU 的「卸载模块挂载」

如果日志里能看到这两行同时出现：

    I KernelSU: ksu_handle_umount: unmounting: /vendor/etc/audio_effects.xml
    E EffectFactoryHAL: Error querying effect descriptor for 9d4921da-...: No such file or directory

那就是 KernelSU 把本模块挂上去的 `audio_effects.xml` 给撤了，
音效 HAL 读回原厂那份之后起不来，Dirac / Dolby 引擎全部建不出来。
连 `9d4921da-...`（EFFECT_TYPE_NULL）都查不到，就是这个特征。

处理：KernelSU 管理器 → 设置里关掉「默认卸载模块挂载 / umount modules」，
或把 `audioserver`、`com.miui.misound` 加进例外。不想关的话也没关系，
上面的补丁已经让 App 在这种情况下不再 FC，只是音效开关会显示不可用。

---

### 独立版「音质音效」App

模块里另带了一个独立包名的 App：**com.dismisound.audiofx**，开机自动安装。
不覆盖任何系统文件，和官方那个互不干扰，卸载模块后可以单独卸掉。

- 界面按 HyperOS 设置页做：灰底 + 圆角卡片，开关行 / 单选行 / 跳转行，跟随深色模式
- 功能对齐官方：米音总开关、音效选择（无 / 米音 / 哈曼卡顿 / 杜比）、
  Hi-Fi、3D 环绕、空间音频、低音增强、图形均衡器（预设 + 10 段微调）、
  耳机类型、场景选择
- 读写通道和官方一致：`Settings.Global` + `AudioManager.setParameters` +
  `android.media.audiofx.MiSound` 反射，三条并存，哪条活着哪条生效
- 自带 hidden api 豁免，绕开重签名后的反射限制
- 模块那一栏直接操作模块开关（force_harman / misound_full / tx_off /
  tx_high / rx_max / no_acdb）、重新挂载、看挂载日志

想连系统自带那个一起修，在模块目录建 `misound_patch`；
默认不覆盖，避免换签名带来的权限损失。

详细说明见模块内 `patch/独立版音质音效说明.txt`。

---

### 独立版「音质音效」App

模块里另带了一个独立包名的 App：**com.dismisound.audiofx**，开机自动安装。
不覆盖任何系统文件，和官方那个互不干扰，卸载模块后可以单独卸掉。

- 界面按 HyperOS 设置页做：灰底 + 圆角卡片，开关行 / 单选行 / 跳转行，跟随深色模式
- 功能对齐官方：米音总开关、音效选择（无 / 米音 / 哈曼卡顿 / 杜比）、
  Hi-Fi、3D 环绕、空间音频、低音增强、图形均衡器（预设 + 10 段微调）、
  耳机类型、场景选择
- 读写通道和官方一致：`Settings.Global` + `AudioManager.setParameters` +
  `android.media.audiofx.MiSound` 反射，三条并存，哪条活着哪条生效
- 自带 hidden api 豁免，绕开重签名后的反射限制
- 模块那一栏直接操作模块开关（force_harman / misound_full / tx_off /
  tx_high / rx_max / no_acdb）、重新挂载、看挂载日志

想连系统自带那个一起修，在模块目录建 `misound_patch`；
默认不覆盖，避免换签名带来的权限损失。

详细说明见模块内 `patch/独立版音质音效说明.txt`。

---

音质音效闪退修复 + 哈曼卡顿开启 —— 坠欢 2026.10.2（fix3）
独立版音质音效 App —— 坠欢 2026.10.2
独立版音质音效 App —— 坠欢 2026.10.2

---

## 2026.10.11 更新（坠欢）

本次是兼容性大修 + 与小米10s「028黑鲨混搭音效」（原作者 酷安@浮尘染溪哦）融合。

### 1. 修复：Magisk（面具）刷入报 Unzip error

10.2 的 zip 里没有 `META-INF/com/google/android/update-binary`。
面具刷模块第一步就是把 zip 里的安装器解出来，解不到就直接 `! Unzip error`；
而 KernelSU / APatch 不需要这个文件，所以只在面具上翻车。
本版已补回标准安装器（update-binary + updater-script），三家人格统一。

### 2. 修复：小米11 Ultra 蓝牙失效（耳机 / 车载，媒体和通话全从扬声器出声）

根因：模块自带的主策略 `audio_policy_configuration.xml` 把 A2DP 写成旧式
primary 内联端口，整包覆盖原厂策略后，原厂 `bluetooth_qti` 策略模块不再被
加载，A2DP / HFP 注册不出来，路由全部回落扬声器。

处理：**默认不再整包替换任何音频策略**（含 a2dp / bluetooth_qti / r_submix
策略文件），策略交还原厂；屏录所需的 r_submix 改由 post-fs-data 里的自适应
注入直接补进原厂策略，屏录修复效果不变。
确要恢复旧的整包替换行为，在模块目录建 `policy_patch`。

### 3. 修复：MIUI14 刷入卡第一屏

根因：模块的策略 / 音效 / 平台配置取自澎湃 OS4，直接 bind 到 MIUI
（Android 12/13）的 vendor 上，audioserver 解析不兼容后反复崩溃，停在第一屏。

处理：开机自动识别 ROM（`ro.mi.os.version.name` / `ro.miui.ui.version.name`）。
MIUI 上自动进**兼容档**：只保留 acdb 声学校准、smart PA 固件、ADSP 资源、
机型 mixer overlay（目标存在才挂）和独立版 App，其余跨 ROM 整包替换一律跳过。
想在 MIUI 上强制全量挂载，建 `full_patch`（后果自负）。

### 4. 融合：小米10s 028黑鲨混搭音效包（默认关闭）

在模块目录建 `mi10s_fx` 开启，包含（只挂原厂已有同名文件，找不到就跳过）：

- qcom soundfx 音效库（lib / lib64 各 17 个，028黑鲨混搭的实现层）
- misound ADSP 资源：`misound_res.bin` / `misound_res_headphone.bin` /
  `misound_karaoke_res.bin` / `misound_karaokemix_res.bin`
- MusicFX（028黑鲨音效界面，apk + oat，/system、/product、/system_ext 找到哪挂哪）

注意：音效库来自 kona（小米10s）vendor，若开启后出现无声音 / audioserver 异常，
删掉 `mi10s_fx` 重启即可还原，无需卸载模块。

### 5. 新增：`acdb_thyme`

建 `acdb_thyme` 把声学校准整套换成小米10s（thyme/kona）的 Tutu 校准组
（含 `adsp_avs_config.acdb`）。默认仍用本模块原有校准；建 `no_acdb` 保留原厂。

### 6. 其它

- post-fs-data / service 的日志与临时文件在模块目录只读时
  （KSU meta-overlayfs 等模式）自动改写到 `/data/local/tmp/DisMiSound_888s`，
  不再静默失败；自检报告仍会导出到 /sdcard/Download。
- 版本号改为日期制：`2026.10.11`。

—— 坠欢 2026.10.11
