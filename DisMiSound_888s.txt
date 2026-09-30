================================================================
［小米 888 系列］音频通路优化　DisMiSound 888s
酷安 @坠欢啊 自研
================================================================

这不是那种挂个「音质提升」名头、实际只改一行属性的模块。
它把骁龙 888 这一代机器（SM8350 / lahaina）整套音频栈
——通路配置、声学校准、ADSP 固件、音频策略、音效引擎、蓝牙编解码——
一条链路全部捋了一遍，再配合一组系统属性把 HAL 的能力彻底打开。

下面按模块里实际放了什么东西、每一项具体带来什么，逐条讲清楚。


────────────────────────────────────────────
支持机型
────────────────────────────────────────────
  代号        机型
  ──────────────────────────────────────
  venus       小米 11 标准版
  star        小米 11 Pro / 11 Ultra（含 mars 子型号）
  haydn       红米 K40 Pro / Pro+
  odin        小米 MIX 4

Root 方案：Magisk / KernelSU / APatch 全部支持。
模块不依赖任何一家的私有挂载方式，
vendor 侧文件由开机阶段自行挂载，三家行为完全一致。


────────────────────────────────────────────
一、音频通路：整套重写，不是单纯改音量
────────────────────────────────────────────

两个核心文件：
  /vendor/etc/audio/sku_lahaina/mixer_paths.xml
  /vendor/etc/audio/sku_lahaina/mixer_paths_overlay_static.xml

1）播放通路全量重配
deep-buffer、low-latency、audio-ull（超低延迟）、
compress-offload 1~9 共九条 offload 通路，
以及它们各自的 speaker、headphones、handset、display-port、
usb-headphones、bt-sco、bt-a2dp 组合分支，全部重设。

涉及的控制项包括 WSA_RX0/RX1、RX_RX0~RX2 数字音量、
耳机左右声道增益、各路 Switch 的开合顺序。
耳放档位按场景区分：主输出给到 20，部分低负载回放分支收到 16，
避免小音量下细节被压掉，也避免大音量顶到失真。

其中 speaker-protected 分支单独走智能功放保护通道，
外放命中的是 cs35l41 的保护算法路径，而不是裸 PA 直出。

2）通话与 VoIP 通路
compress-voip-call（含 bt-sco / headphones / usb / afe-proxy 各分支）、
audio-playback-voip、voicemmode1/2-call 全部重设。
听筒侧的 RCV AMP PCM Gain 按用途分成三档：
旁路 6、通话 18、回放 20，
通话场景吃的是专门为语音调整的那一档，而不是沿用音乐通路的参数。

3）小米超声波 Sensing 通路
ultrasound-proximity、-output、-input、rampdown、screen-on、
suspend、stop-report 这一整套保留并重设，
抬手亮屏、通话息屏这些依赖超声波检测的场景不会因为通路改动而失效。

4）回声参考通路
echo-reference 与 echo-reference-voip（speaker、earpiece、headphones）
独立配置，VoIP 通话的双工降噪能拿到干净的参考信号。

5）智能功放 cs35l41 参数
Class-H 升压追踪使能、根据 use case 切换不同的 Delta File
（spk2_playback_delta / spk2_voice_delta / rcv_voice_delta），
听筒（RCV）和扬声器分开设置升压目标电压，各机型给到合适档位。
听筒 Boost 电压这一项 MIX 4 与其它机型取值不同，因为是两种听筒器件。

6）多版本底板
除主 mixer_paths 外还带了 mixer_paths_cdp / hdk / qrd / hhg
四套底板和 overlay_dynamic，覆盖不同 SKU 的机型变体。


────────────────────────────────────────────
二、声学校准（acdb）
────────────────────────────────────────────
  Tutu_*（venus / star / odin）　小米 11 系列同款声学标定
  Forte_*（haydn）　　　　　　　K40 Pro 系列适用的标定

每个机型包含 Bluetooth / General / Global / Handset /
Speaker / Headset / Hdmi 七份 *_cal.acdb，外加 workspaceFile.qwsp 工程档。

acdb 里装的是麦克风灵敏度、TX/RX 频响补偿、器件线性度、
扬声器特性这些数据。原厂给的那套偏保守，
这套标定把听筒、扬声器、耳机三条路的目标响度曲线都抬了一档，
声音不再是「蒙了一层」的状态。

不同 ROM 的校准目录名不一样（Tutu / Forte 之类），
模块会自动探测你机器上真实在用的目录再挂载，
不会把别的机型的上行标定错装到你的目录上。


────────────────────────────────────────────
三、ADSP 固件与喇叭保护
────────────────────────────────────────────
  /vendor/firmware/cs35l41-dsp1-diag-z-*.bin
  /vendor/firmware/cs35l41-dsp1-spk-prot-*.bin
  /vendor/lib/rfsa/adsp/misound_res_spk.bin

cs35l41 是这代机器用的 smart PA。
diag 与 spk-prot 两份固件分别对应诊断模式和保护模式，
听筒（RCV）另有一套独立 variant。
misound_res_spk.bin 是 ADSP 侧的扬声器资源文件，
外放的低频管理算法读的就是它。


────────────────────────────────────────────
四、音频策略与平台信息
────────────────────────────────────────────
  audio_policy_configuration.xml（含新版布局）
  sku_lahaina / sku_lahaina_qssi 目录下的 policy
  audio_platform_info.xml 及 _hdk / _intcodec / _qrd 三份变体
  audio_io_policy.conf
  a2dp_audio_policy_configuration.xml
  bluetooth_qti_audio_policy_configuration.xml
  r_submix_audio_policy_configuration.xml

把音频模块、输入源、设备之间的路由关系和设备能力描述重写了一遍：
USB 声卡、蓝牙 A2DP / SCO、r_submix（录屏内录）、
新版 qssi policy 布局都覆盖到，
不会再出现「某些场景被路由到低质量 output」的情况。


────────────────────────────────────────────
五、音效引擎
────────────────────────────────────────────
  /vendor/etc/audio_effects.conf 与 .xml

启用的库包括：
  equalizer / bassboost / virtualizer
  reverb（aux 与 ins、pre 与 ins 四组）
  visualizer / downmix / loudness_enhancer / dynamics_processing
  hw_acc（offload_bundle）/ volume
  audiosphere / shoebox / ozo_processing / haptic_effect
  volume_listener（music / ring / alarm / voice / notification 五种 helper）
  audio_pre_processing：aec（回声消除）与 ns（降噪）

重点是 offload_bundle 和 hw_acc：
开启之后均衡、低频增强这类处理可以在 DSP 侧完成，
不再占用 CPU 去做软件重采样。


────────────────────────────────────────────
六、杜比解码能力
────────────────────────────────────────────
  /vendor/etc/media_codecs_dolby_audio.xml

声明 audio/ac3、audio/eac3、audio/eac3-joc、audio/ac4 四种类型。
带杜比内容的流媒体和本地片源能正常走硬件解码，
不会被系统转成 PCM 降级处理。


────────────────────────────────────────────
七、硬件特性声明
────────────────────────────────────────────
  android.hardware.audio.low_latency
  android.hardware.audio.pro

声明之后系统会把本机识别为「低延迟音频设备」和「专业音频设备」，
各类播放器、USB 音频、录音类 APP 会自动切到高速通道，
相关的能力限制也会一并放开。


────────────────────────────────────────────
八、补齐米音音效面板
────────────────────────────────────────────
  /system/priv-app/MusicFX（com.miui.audioeffect）

部分第三方 ROM 把这个 App 精简掉了，
音效设置进去是空的或者干脆打不开。模块把它补回去，调节界面可以正常使用。


────────────────────────────────────────────
九、系统属性：把 HAL 的能力全部打开
────────────────────────────────────────────

【高码率输出】
  audio.offload.pcm.16bit.enable=true
  audio.offload.pcm.24bit.enable=true
  audio.offload.pcm.32bit.enable=true
  audio.offload.pcm.float.enable=true
  persist.audio.format.24bit / 32bit / float=true
  vendor.audio.offload.track.enable=true
  vendor.audio.offload.multiple.enabled=true
  vendor.audio.offload.passthrough=true

offload 通路支持 16 / 24 / 32bit 和浮点 PCM，
多音轨并行 offload 一并打开，
不会再出现 music 流被系统从 offload 降级到 deep-buffer 的情况。

【低延迟】
  aaudio.mmap_policy=2
  aaudio.mmap_exclusive_policy=2
  aaudio.hw_burst_min_usec=2000
  vendor.audio_hal.period_multiplier=2
  vendor.audio.adm.buffering.ms=3
  vendor.audio.offload.buffer.size.kb=128
  af.fast_track_multiplier=1

AAudio 直达模式优先，中间层不再多写一次缓冲；
offload 缓冲给到 128KB，突发写入更少，
低延迟场景不会因为缓冲太小频繁申请而被系统拖回普通通路。

【采样率与重采样】
  af.resampler.quality=12
  persist.dev.pm.dyn_samplingrate=1
  persist.vendor.audio.format.24bit / 32bit / float=true
  audio.playback.mch.downsample=true
  vendor.audio.feature.hifi_audio.enable=true

重采样器质量拉到最高档；打开动态采样率，
播放 44.1k 的内容时 HAL 直接跑 44.1k，
不再统一到 48k 过一遍 SRC。这一条是整个模块里听感提升最明显的项之一。

【硬件通路】
  vendor.audio.tunnel.encode=true
  vendor.audio.tunnel.decode=true
  audio.deep_buffer.media=true
  vendor.audio.spkr_prot.tx.sampling_rate=96000

编解码启用硬件隧道（tunnel）模式，压缩码流直通 DSP；deep-buffer 明确给媒体流使用；
喇叭保护的反馈采样提到 96k，
保护算法的判断更准，大动态下不容易误限。

【关闭干扰项】
  persist.vendor.audio.bcl.enabled=false
  persist.vendor.audio.ras.enabled=false
  vendor.audio.feature.ras.enable=false
  vendor.audio.feature.src_trkn.enable=false
  ro.vendor.audio.misound.bluetooth.enable=false
  ro.vendor.audio.soundfx.usb=false
  ro.vendor.audio.sfx.harmankardon=false
  ro.vendor.audio.sfx.earadj=false
  ro.vendor.audio.sfx.scenario=false
  ro.vendor.audio.game.mode=false
  persist.vendor.audio.misoundasc=false

上面这些后处理每一道都会把信号再加工一遍，
放着的后果就是前面做好的高码率 offload 被重新采样回去。
统一关掉，链路才是干净的。

【蓝牙】
  persist.bluetooth.a2dp_offload.cap（含 vendor / qcom / btstack 各份）
    = sbc-aptx-aptxtws-aptxhd-aptxadaptiver2-aac-lc3-ldac-lhdc
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

offload 能力里集齐 aptX TWS / aptX HD / aptX Adaptive R2 /
LDAC / LHDC / LC3；AAC 的帧控制交回高通实现，VBR 控制打开。
LE Audio 的 BAP 广播与单播、VCP 音量控制一并启用，
新的 TWS 耳机能吃到 LE 通道而不是只能走传统 SBC / A2DP。


────────────────────────────────────────────
十、开关
────────────────────────────────────────────
在模块目录放同名空文件，重启生效；删掉文件重启即回默认。

  no_acdb     不替换声学校准，只保留通路优化
  tx_off      MIX 4：通话上行不额外提升
  tx_high     MIX 4：通话上行再高一档
  rx_max      MIX 4：保留更大的听筒升压
  model       内容写机型代号，识别不到时手动指定


────────────────────────────────────────────
十一、安装
────────────────────────────────────────────
1. 卸载旧版同名模块
2. 在管理器里刷入本模块
3. 重启后先用中等以上音量听一轮，让 ADSP 侧保护算法完成自适应
4. 出现异常时把模块目录下的 mount.log 连同机型代号一起反馈

本版同时挂载方式对 Magisk / KernelSU / APatch 三家做了统一，
通话的上行电平与听筒泄漏量也重新校准过，不再需要额外补丁。


────────────────────────────────────────────
音频调校主观性很强，喜欢偏响还是偏淡，用上面的开关自己试。
刷机有风险，操作前请自行备份。

酷安 @坠欢啊 自研
二次修改 / 重新打包 / 搬运，请先取得本人认可
================================================================
