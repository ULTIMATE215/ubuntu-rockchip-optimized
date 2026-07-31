# Ubuntu 26.04 LTS 迷你镜像，带硬件加速，面向 Orange Pi 5 / 5 Plus

针对 Orange Pi 5 及 Orange Pi 5 Plus，极度轻量化、优化的 Ubuntu 26.04 LTS (Resolute Raccoon) 硬件加速定制磁盘镜像及其自动构建工具。

采用最新主线环境（Linux Kernel 7.1 系列 & Mesa 26.0 系列），彻底排除不需要的模块和组件，实现超轻量且极为流畅的桌面体验。

## 🚀 主要特性

- **完全主线的图形驱动**:
  Mesa 26.0 (Panfrost/PanVK) 100% 发挥 Mali-G610 GPU 的潜力，在 GNOME (Wayland) 桌面环境下实现丝滑般流畅的渲染。
- **高效的硬件视频编解码**:
  Linux 7.1 内核的 V4L2 Request API 与 GStreamer 1.28+ (v4l2codecs) 直接联动。支持低发热、低CPU负载下的4K视频播放。
  并通过 out-of-tree 补丁集成 **VEPU580 硬件编码**（H.265），配套的 MPP 用户态库已预装进 rootfs。
- **极致的极简主义 (1.6 GB)**:
  将内核压缩到极限，压缩后镜像大小仅 **1.6 GB (xz)**。
- **100% Snap-Free**:
  完全排除 Ubuntu 标准的 Snap 守护进程及 Snap 应用。将系统开销降至极致。（之后安装 snapd 也可正常运行）
- **Panthor 优化构建**:
  为轻量化，采用 Mesa 重构版本及 Ubuntu 标准版、Freedesktop Mesa 26.0 版两种类型。
- **可选的内核模式**:
  内核按 CPUFreq governor 分为 `ondemand` / `conservative` / `performance` / `schedutil` 四种，
  构建时自由勾选，可同时收录多个到一个镜像里，启动时选择。详见下方「构建」与「CPU Governor」两节。
- **洁净构建环境**:
  U-Boot、内核、Mesa、rootfs 分别在独立的洁净环境（systemd-nspawn）中构建。排除构建环境污染，生成高再现性的最高品质二进制文件。

## 🛠️ 内核优化

内核配置集中在 `my-add.txt`（kconfig 片段，由 `merge_config.sh` 与 `make defconfig` 合并）。
配置以 Orange Pi 5 Plus / RK3588 实机实测为准调优。

### 硬件加速

- **零拷贝缓冲**: `CONFIG_DMABUF_HEAPS` + `CONFIG_ROCKCHIP_IOMMU`，GPU↔VPU 之间零拷贝传输，优化 Chromium 硬件解码
- **CMA 256MB**: defconfig 默认仅 32MB，实测 4K 硬解 + RGA + DMABUF 同时工作时极易分配失败并静默回退软解
- **硬件编码**: `CONFIG_VIDEO_ROCKCHIP_RKVENC`（VEPU580，来自 `kernel-patches/` 下的 out-of-tree 补丁）
- **存储**: NVMe、eMMC HS400 + 命令队列（CQE）、M.2 PCIe→SATA 转换（JMB582 等）

### 桌面响应速度

- **MGLRU** (`CONFIG_LRU_GEN`): 多标签浏览器 + 视频播放等内存压力场景下回收决策更准，卡顿明显减少
- **HZ=1000 + PREEMPT_DYNAMIC**: 可用内核参数 `preempt=full|lazy|voluntary|none` 运行时调整
- **透明大页**: 匿名页 always，并对只读文件页（可执行段）启用
- **PSI**: systemd-oomd 依赖，缺失会导致其启动失败

### 已禁用的组件

- **非 Rockchip 平台**: `make defconfig` 会打开 52 个 arm64 SoC 平台族，全部关闭以缩短构建时间、减小模块与 DTB 体积
- **ARMv8.2 用不到的扩展**: Cortex-A76/A55 不具备 PAC / BTI / MTE / SVE / SME，关闭以减小内核 text 与 I-cache 压力
- **不需要的子系统**: MTD、VFIO、REMOTEPROC、RPMSG、CAN 总线、DVB_NET、调谐器、SND_HDA、SOF、休眠(HIBERNATION)

> **注意**: 早期版本曾禁用 Wi-Fi、蓝牙、IPv6、Netfilter、VLAN、NFS，
> **这些现已全部启用**——防火墙（UFW / nftables / iptables 全兼容）、
> RTL8852BE Wi-Fi 6 与蓝牙、2.5GbE 网络高可用、WireGuard、容器网络均可正常使用。

## 🔨 构建

### GitHub Actions（仅构建内核）

在 Actions 页面手动触发 `kernel-only-build`，勾选需要的内核模式即可，
可多选，产出的 `.deb` 会作为 artifact 上传。

| 勾选项 | 默认 | 说明 |
|---|---|---|
| `gov_ondemand` | ✅ | 性能与功耗平衡 |
| `gov_conservative` | ✅ | 省电 / 防过热 |
| `gov_performance` | ⬜ | 最高性能 |
| `gov_schedutil` | ⬜ | 不推荐，见下节实测 |

### 本地完整构建（内核 + Mesa + rootfs + 磁盘镜像）

```bash
sudo ./main-control.sh <mesa变体>

# 指定内核模式（默认 conservative,ondemand）
KERNEL_GOVS=ondemand,performance sudo ./main-control.sh <mesa变体>

# 构建 server 版 rootfs（默认 desktop）
BUILD_TYPE=server sudo ./main-control.sh <mesa变体>
```

U-Boot、内核、Mesa、rootfs 分别在独立的 systemd-nspawn 洁净环境中构建，排除构建环境污染。

## ⚡ 关于 CPU Governor

内核按 governor 分为多个版本，同一镜像内可收录多个。
为从 U-Boot 启动指定版本，请将 `/boot/extlinux/extlinux.conf` 的 `default` 改为对应的 `l0` / `l1` … 后重启。

| Governor | 特性 | 推荐用途 |
|---|---|---|
| **performance** | 始终锁定最高频率 | 最高性能·跑分 |
| **ondemand** | 高负载时立即响应最大频率 | 3D图形·游戏（推荐默认） |
| **conservative** | 仅提升所需的频率 | 视频播放·省电·夏季防过热 |
| **schedutil** | 按调度器平均利用率定频 | **不推荐**，见下方实测 |

## 📊 实测性能数据

### Governor 对比（Orange Pi 5 Plus, Linux 7.1.5）

突发负载测试：单线程在 A76 核心上执行 20ms 计算 + 60ms 空闲，重复 45 轮取中位数，
模拟 GUI 帧循环 / 浏览器滚动这类交互场景。频率驻留由 cpufreq `time_in_state` 精确统计。

| Governor | 突发耗时(中位) | 平均频率 | 满频占比 | 持续满载吞吐 |
|---|---|---|---|---|
| **performance** | **20.0 ms** | 2400 MHz | 100% | ~2700 Mops/s |
| **ondemand** | 25.0 ms | 1720 MHz | 32% | ~2700 Mops/s |
| **schedutil** | 37.9 ms | 1210 MHz | 0% | ~2700 Mops/s |

- **持续满载时三者完全等价**——都锁在最高频，差异全在突发/交互负载上。
- **schedutil 慢 89% 且全程摸不到满频**。它按 PELT 平均利用率定频，25% 占空比的任务只分到 ~1.2GHz。
  能量模型确实注册成功、EAS 也确实激活（`sched_energy_aware=1`），但 EAS 只影响任务在哪个簇上运行，
  不影响调频激进程度。唯一能纠正的 uclamp 提频机制需要 `CONFIG_UCLAMP_TASK`，且通用 Ubuntu 桌面
  没有任何组件会去设置 `uclamp.min`——这正是 Android 能用好 schedutil 而桌面发行版不能的原因。

### glmark2-es2-wayland 得分

GNOME (Wayland) 会话，使用 Mesa 26.0.8 (Panfrost) 时的实测值。

| 板子 | Governor | 得分 |
|---|---|---|
| Orange Pi 5 | ondemand | **3241** |
| Orange Pi 5 | conservative | 2740 |
| Orange Pi 5 Plus | ondemand | **3138** |
| Orange Pi 5 Plus | conservative | 2654 |

### 4K视频硬件解码时的 CPU 负载 (uptime)

测试素材: YouTube 4K HDR「3 Hours of Rainy Night Walk in Tokyo」
使用 Chromium + enhanced-h264ify 时的实测值。

| 板子 | Governor | 开始时 | 稳定后 |
|---|---|---|---|
| Orange Pi 5 | ondemand | 〜2.77 | 〜2.16 |
| Orange Pi 5 | conservative | 〜1.96 | **〜0.85** |
| Orange Pi 5 Plus | ondemand | 〜3.00 | 〜2.70 |
| Orange Pi 5 Plus | conservative | 〜1.17 | **〜0.82** |

*CPU软件解码时 uptime 超过10。硬件解码效果极为显著。*

*uptime 的值会根据视频内容的运动剧烈程度（画面变化量）而变动。动作越少的影像值越低。*

## 📦 硬件加速体验·测试方法

### 1. 3D图形 (GPU) 测试
确认 Mesa Panfrost/PanVK 是否正常处理图形。

```bash
# OpenGL ES 测试
sudo apt install glmark2-es2-wayland
glmark2-es2-wayland

# Vulkan 测试
sudo apt install vulkan-tools
vkcube
```

### 2. 视频解码 (VPU) 确认
确认内核的 V4L2 编解码引擎是否通过最新的 GStreamer 识别 H.264/H.265/AV1。

```bash
gst-inspect-1.0 v4l2codecs
```
*如果显示 `v4l2slh264dec`、`v4l2slh265dec`、`v4l2slav1dec` 等即为正常。视频播放推荐使用直接调用 GStreamer 的「Clapper」等现代播放器。*

### 3. 🔥 Special Feature: Pure APT Native Browsing (Snap-free)
此磁盘镜像为最大限度发挥 Orange Pi 5 / 5 Plus 的硬件性能，采用**完全排除 Snap 的清洁设计**。

在将初始状态的磁盘容量（镜像大小）压缩至最小的同时，预先在系统中内置了 **Mozilla Team PPA 和 xtradeb packaging team PPA 的预映射（APT Pinning）**，使用户随时可安装「APT版」Firefox、Thunderbird 和 Chromium。
通过「Chrome 网上应用店 - 扩展程序」安装 **enhanced-h264ify**，即可轻松体验**硬件解码**。

由此，不会被 Ubuntu 官方的「Snap强制虚拟包」干扰，一条命令即可获得超轻量、高速的浏览环境。

### 🚀 How to Install Native Firefox & Thunderbird & Chromium

镜像启动后，在终端中执行以下命令，即可从PPA直接安装软件包（APT版）。

```bash
sudo apt update
sudo apt install firefox-esr thunderbird-gnome-support chromium
```

- **No Snap Overhead**: 启动慢、浪费内存的Snap守护进程完全不运行。
- **Hardware Accelerator Friendly**: 请体验最大限度活用SBC资源的轻快性能。

## 📝 开发者笔记

- Mesa 版本升级带来的渲染质量提升虽然不易在性能跑分数值中体现，但在实际使用感受中可体会到清晰度的提高。与半年前的构建相比，差异更加明显。
- 作为夏季防过热措施，推荐使用 `conservative` 内核。对CPU更友好，4K视频播放的体感差异也几乎不存在。
- glmark2 得分会因测量时的系统负载（后台构建作业等）而大幅变动。空闲状态下的测量值才是公平的比较。

## 🛠️ 关于开发者 (Authors)

本项目诞生于人类工程师的构想力与AI技术支持融合的「AI共同开发（AI Co-Development）」。

- **Main Lead & Build Architect**: hakotani
  - **GitHub**: [@hakotani-o](https://github.com/hakotani-o)
  - *负责概念设计、高级内核定制、Mesa隔离构建、洁净构建环境的搭建，以及GitHub自动化流水线的构建。*

- **AI Co-Pilot & Technical Advisor**: Google AI / Anthropic Claude
  - *Google AI: 协助内核选项优化提案、Mesa构建标志验证、最新Linux 7.0/Mesa 25.3环境下V4L2/GStreamer相关问题的排查。*
  - *Anthropic Claude: 协助内核配置的审查·优化（Rockchip/RK3588专用）、DMABUF_HEAPS·AHCI/SATA支持的添加、洁净构建环境（systemd-nspawn）的设计、CPU Governor实测比较·选型、kdump-tools排除（APT Pin方式）、性能数据分析。*

---
*本项目使用 GitHub Actions，完全自动完成从源码编译内核、Mesa隔离编译（创建deb包），到发布上传的全部流程。*
