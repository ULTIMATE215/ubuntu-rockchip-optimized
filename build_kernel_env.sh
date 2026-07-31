#!/bin/bash
set -eE
trap 'echo "Error in $0 on line $LINENO"' ERR

# 安装创建磁盘镜像所需的工具
sudo apt-get update && sudo apt-get -y install  systemd-container debootstrap

rm -rf arm64
mkdir arm64
chroot_dir=arm64
mem_size=`free --giga|grep Mem|awk '{print $2}'`
if [ $mem_size -gt 13 ]; then
        mount -t tmpfs -o size=10G tmpfs $chroot_dir
fi
suite=$3
Uri=$2
#Uri="http://ports.ubuntu.com/ubuntu-ports"

# 要构建的内核模式（CPUFreq governor），逗号分隔。
# 未传入时保持原有行为：conservative + ondemand。
kernel_govs=${5:-conservative,ondemand}

debootstrap --arch=arm64 $suite arm64 $Uri

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export  LC_ALL=C
export  LC_CTYPE=C
export  LANGUAGE=C
export  LANG=C

#Setup DNS
echo "127.0.0.1 localhost" > arm64/etc/hosts
echo "127.0.0.1 ubuntu-desktop" >> arm64/etc/hosts
echo "nameserver 8.8.8.8" > arm64/etc/resolv.conf
echo "nameserver 8.8.4.4" >> arm64/etc/resolv.conf

#sources.list setup
rm arm64/etc/hostname
echo "ubuntu-desktop" > arm64/etc/hostname
{
echo "Types: deb"
echo "URIs: $Uri"
echo "Suites: $suite $suite-updates $suite-backports"
echo "Components: main universe restricted multiverse"
echo "Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg"
echo ""
echo "## Ubuntu security updates. Aside from URIs and Suites,"
echo "## this should mirror your choices in the previous section."
echo "Types: deb"
echo "URIs: $Uri"
echo "Suites: $suite-security"
echo "Components: main universe restricted multiverse"
echo "Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg"
} > arm64/etc/apt/sources.list.d/ubuntu.sources
rm -f arm64/etc/apt/sources.list

# APT 重试配置（防止 CI 网络瞬断）
mkdir -p arm64/etc/apt/apt.conf.d
echo 'Acquire::Retries "5";' > arm64/etc/apt/apt.conf.d/99-retries

echo "\n##################      systemd-nspawn  START   #######################\n"

systemd-nspawn -D arm64 --resolv-conf=replace-host --as-pid2 sudo apt-get clean
systemd-nspawn -D arm64 --resolv-conf=replace-host --as-pid2 sudo apt-get update
systemd-nspawn -D arm64 --resolv-conf=replace-host --as-pid2 sudo apt-get -y upgrade
systemd-nspawn -D arm64 --resolv-conf=replace-host --as-pid2 sudo apt-get -y dist-upgrade
systemd-nspawn -D arm64 --resolv-conf=replace-host --as-pid2 sudo apt-get -y install build-essential bison \
debootstrap libssl-dev kmod cpio xz-utils fakeroot flex rsync \
device-tree-compiler zstd python3 \
python-is-python3 fdisk bc debhelper python3-pyelftools python3-setuptools \
python3-pkg-resources swig libfdt-dev libpython3-dev \
git ncurses-dev \
libelf-dev libgnutls28-dev gcc-13 g++-13 libdw-dev

systemd-nspawn -D arm64 --resolv-conf=replace-host --as-pid2 sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-13 13
systemd-nspawn -D arm64 --resolv-conf=replace-host --as-pid2 sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-13 13

echo "\n##################      systemd-nspawn  END     #######################\n"

# u-boot
cp das-u-boot.sh arm64
chmod +x arm64/das-u-boot.sh

systemd-nspawn -D arm64 \
  --resolv-conf=replace-host \
  --as-pid2 \
  --setenv=DEBIAN_FRONTEND=noninteractive \
  --setenv=DEBCONF_NONINTERACTIVE_SEEN=true \
/bin/bash -c "./das-u-boot.sh $1"

cp arm64/*.bin overlay

if [ "$4" = "kernel" ]; then
# kernel
cp build-kernel.sh arm64
cp overlay/my-add.txt arm64
cp overlay/my-add.txt arm64/my-add.txt.orig
cp overlay/rk3588-pwm-fan.dtsi arm64
cp -r kernel-patches arm64
chmod +x arm64/build-kernel.sh

# 按 $5 指定的模式依次构建，多个模式复用同一份源码树（增量编译）。
# build-kernel.sh 会把 my-add.txt 里对应 governor 的 =n 改成 =y，
# 并以该名字作为 LOCALVERSION，因此每个模式产出的 deb 文件名互不冲突。
build_cmds=""
IFS=',' read -ra _govs <<< "$kernel_govs"
for _g in "${_govs[@]}"; do
    _g=$(echo "$_g" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    [ -z "$_g" ] && continue
    case "$_g" in
        ondemand|conservative|performance|schedutil) ;;
        *) echo "错误: 未知的内核模式 '$_g' (可选: ondemand conservative performance schedutil)"; exit 1 ;;
    esac
    _sym="CONFIG_CPU_FREQ_DEFAULT_GOV_$(echo "$_g" | tr '[:lower:]' '[:upper:]')"
    # 每轮都从 .orig 还原，避免上一轮的 sed 结果串到下一轮
    build_cmds="${build_cmds}cp /my-add.txt.orig /my-add.txt
./build-kernel.sh kernel ${_sym}
"
done

if [ -z "$build_cmds" ]; then
    echo "错误: 未指定任何内核模式"
    exit 1
fi

echo "##### 将构建以下内核模式: ${kernel_govs} #####"

systemd-nspawn -D arm64 \
  --resolv-conf=replace-host \
  --as-pid2 \
  --setenv=DEBIAN_FRONTEND=noninteractive \
  --setenv=DEBCONF_NONINTERACTIVE_SEEN=true \
/bin/bash -c "set -e
${build_cmds}"

mkdir -p kernel
cp arm64/*.deb kernel
cp arm64/2-config.txt overlay
fi

if [ $mem_size -gt 13 ]; then
        sudo umount arm64
	sleep 2
fi 
exit 0

