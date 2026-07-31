#!/bin/bash
set -eE
trap 'echo "Error in $0 on line $LINENO"' ERR

#suite=plucky
suite=resolute
#Uri="http://ftp.udx.icscoe.jp/Linux/ubuntu-ports/"
Uri="http://ports.ubuntu.com/ubuntu-ports"

# BUILD_TYPE: "desktop" (default) or "server"
# Set via environment: BUILD_TYPE=server sudo ./main-control.sh ...
build_type="${BUILD_TYPE:-desktop}"

# 要构建的内核模式（CPUFreq governor），逗号分隔。
# 可选: ondemand / conservative / performance / schedutil
# Set via environment: KERNEL_GOVS=ondemand,performance sudo ./main-control.sh ...
kernel_govs="${KERNEL_GOVS:-conservative,ondemand}"

start_time=$(date)

sudo rm -f log?
sudo ./build_kernel_env.sh orangepi-5-plus-rk3588_defconfig "$Uri" "$suite" kernel "$kernel_govs"
sudo ./mesa-build-env.sh arm64 "$1" "$Uri" "$suite"
sudo ./rootfs-bootstrap.sh arm64 "$Uri" "$suite" "$build_type"
sudo ./build_kernel_env.sh orangepi-5-plus-rk3588_defconfig "$Uri" "$suite" u-boot
sudo ./disk_image.sh arm64 orangepi-5-plus rk3588-orangepi-5-plus
sudo mv overlay/u-boot-rockchip.bin overlay/orangepi-5-plus-u-boot-rockchip.bin

echo "$start_time"
date
