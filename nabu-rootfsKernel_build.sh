#!/bin/sh

set -x
if [ "$(id -u)" -ne 0 ]
then
  echo "rootfs can only be built as root"
  exit
fi

VERSION="23.10"

#DEPS dpkg, wget, binfmt support(or arm64 device), 7zip, make, aarch64 gcc,
#DEPS openssl headers, bc, bison, flex, bash, kmod, cpio, binutils, tar, git

git clone https://github.com/map220v/sm8150-mainline.git --branch nabu-6.7 --depth 1 linux
cd linux
make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig sm8150.config
make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
mkdir ../linux-xiaomi-nabu/boot
cp arch/arm64/boot/Image.gz ../linux-xiaomi-nabu/boot/vmlinuz-6.7.0-sm8150
cp arch/arm64/boot/dts/qcom/sm8150-xiaomi-nabu.dtb ../linux-xiaomi-nabu/boot/dtb-6.7.0-sm8150
rm -rf ../linux-xiaomi-nabu/lib
make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=../linux-xiaomi-nabu modules_install
rm ../linux-xiaomi-nabu/lib/modules/**/build
cd ..
rm -rf linux

dpkg-deb --build --root-owner-group linux-xiaomi-nabu
dpkg-deb --build --root-owner-group firmware-xiaomi-nabu
dpkg-deb --build --root-owner-group alsa-xiaomi-nabu



truncate -s 10G rootfs.img
mkfs.ext4 rootfs.img
mkdir rootdir
mount -o loop rootfs.img rootdir

apt-get install debootstrap -y
debootstrap --arch=arm64 --include=w3m,ca-certificates,htop,neofetch,nethack-console,rmtfs,protection-domain-mapper,tqftpserv,bash-completion,fish,sudo,ssh --variant=minbase bookworm rootdir

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount --bind /proc rootdir/proc
mount --bind /sys rootdir/sys

echo "nameserver 1.1.1.1" | tee rootdir/etc/resolv.conf
echo "xiaomi-nabu" | tee rootdir/etc/hostname
echo "127.0.0.1 localhost
127.0.1.1 xiaomi-nabu" | tee rootdir/etc/hosts

if uname -m | grep -q aarch64
then
  echo "cancel qemu install for arm64"
else
  wget https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-aarch64-static
  install -m755 qemu-aarch64-static rootdir/

  echo ':aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/qemu-aarch64-static:' | tee /proc/sys/fs/binfmt_misc/register
  #ldconfig.real abi=linux type=dynamic
  echo ':aarch64ld:M::\x7fELF\x02\x01\x01\x03\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/qemu-aarch64-static:' | tee /proc/sys/fs/binfmt_misc/register
fi


#chroot installation
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH
export DEBIAN_FRONTEND=noninteractive

chroot rootdir apt update
chroot rootdir apt upgrade -y

#u-boot-tools breaks grub installation
chroot rootdir apt install -y u-boot-tools- kde-standard 

#chroot rootdir gsettings set org.gnome.shell.extensions.dash-to-dock show-mounts-only-mounted true


#Remove check for "*-laptop"
sed -i '/ConditionKernelVersion/d' rootdir/lib/systemd/system/pd-mapper.service

cp *-xiaomi-nabu.deb rootdir/tmp/
chroot rootdir dpkg -i /tmp/linux-xiaomi-nabu.deb
chroot rootdir dpkg -i /tmp/firmware-xiaomi-nabu.deb
chroot rootdir dpkg -i /tmp/alsa-xiaomi-nabu.deb
rm rootdir/tmp/*-xiaomi-nabu.deb


#EFI
chroot rootdir apt install -y grub-efi-arm64

sed --in-place 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' rootdir/etc/default/grub
sed --in-place 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT=""/' rootdir/etc/default/grub

#this done on device for now
#grub-install
#grub-mkconfig -o /boot/grub/grub.cfg

#create fstab!
echo "PARTLABEL=linux / ext4 errors=remount-ro,x-systemd.growfs 0 1
PARTLABEL=esp /boot/efi vfat umask=0077 0 1" | tee rootdir/etc/fstab

mkdir rootdir/var/lib/gdm
touch rootdir/var/lib/gdm/run-initial-setup

chroot rootdir apt clean

if uname -m | grep -q aarch64
then
  echo "cancel qemu install for arm64"
else
  #Remove qemu emu
  echo -1 | tee /proc/sys/fs/binfmt_misc/aarch64
  echo -1 | tee /proc/sys/fs/binfmt_misc/aarch64ld
  rm rootdir/qemu-aarch64-static
  rm qemu-aarch64-static
fi

umount rootdir/sys
umount rootdir/proc
umount rootdir/dev/pts
umount rootdir/dev
umount rootdir

rm -d rootdir

echo 'cmdline for legacy boot: "root=PARTLABEL=linux"'

7zz a rootfs.7z rootfs.img
