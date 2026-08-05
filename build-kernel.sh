#!/bin/bash

set -eE
trap 'echo "Error in $0 on line $LINENO"' ERR

set -x

linux_dir=$1
mkdir -p $linux_dir && cd $linux_dir

# 固定官方稳定版标签，避免 linux-7.1.y 分支前移导致同一配置构建出不同内核。
kernel_ref="${KERNEL_REF:-v7.1.6}"

if [ ! -d linux ]; then
    git clone --depth 1 \
        --branch "$kernel_ref" \
        https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git linux
    cd linux
    # 应用 out-of-tree 内核补丁
    if ls /kernel-patches/*.patch 2>/dev/null; then
        for p in /kernel-patches/*.patch; do
            patch -p1 < "$p"
        done
    fi
    cd ..
fi

cd linux
actual_ref="$(git describe --tags --exact-match HEAD 2>/dev/null || true)"
if [ "$actual_ref" != "$kernel_ref" ]; then
    echo "错误: 内核源码不是期望的 $kernel_ref（当前: ${actual_ref:-unknown}）"
    exit 1
fi
printf 'KERNEL_REF=%s\nKERNEL_COMMIT=%s\n' \
    "$kernel_ref" "$(git rev-parse HEAD)" > /kernel-source.txt

cp /my-add.txt .
# 将 PWM 风扇节点写入设备树（仅在首次执行）
if ! grep -q 'rk3588-pwm-fan.dtsi' arch/arm64/boot/dts/rockchip/rk3588-orangepi-5-plus.dts; then
    cp /rk3588-pwm-fan.dtsi arch/arm64/boot/dts/rockchip/
    echo '#include "rk3588-pwm-fan.dtsi"' >> arch/arm64/boot/dts/rockchip/rk3588-orangepi-5-plus.dts
fi
kernel_para=$2
echo "kernel_para=${kernel_para}"
# CPUFreq 默认 governor 是一个 choice；每次构建先清空旧选择再启用目标项，
# 这样从 Ubuntu 默认 ondemand 切换到测试 governor 时不会留下两个 =y。
for gov_sym in \
    CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL \
    CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE \
    CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND \
    CONFIG_CPU_FREQ_DEFAULT_GOV_CONSERVATIVE; do
    sed -i "s/^${gov_sym}=.*/${gov_sym}=n/" my-add.txt
done
sed -i "s/$kernel_para\=n/$kernel_para\=y/" my-add.txt
kernel_name=$( echo $2 | sed 's/_/ /g' | awk '{ print $6 }' )
echo "kernel_name=$kernel_name"


make defconfig
./scripts/kconfig/merge_config.sh -m .config ./my-add.txt

./scripts/config --set-val DEBUG_INFO_NONE y
./scripts/config --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
./scripts/config --disable DEBUG_INFO_DWARF4
./scripts/config --disable DEBUG_INFO_DWARF5

make olddefconfig
cp .config /2-config.txt

# systemd-nspawn 内 fakeroot 不稳定，改为不需要 root 的打包方式
# 编译并行，打包串行（避免 dtbs_install 竞争目录）
make -j$(nproc) LOCALVERSION="-${kernel_name,,}"
MAKEFLAGS=-j1 DEB_RULES_REQUIRES_ROOT=no make LOCALVERSION="-${kernel_name,,}" bindeb-pkg
cd ..
cp *.deb /

exit 0
