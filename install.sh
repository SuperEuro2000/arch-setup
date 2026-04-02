#!/bin/bash
set -euxo pipefail

DISK="/dev/nvme0n1"
HOSTNAME="rch"
USERNAME="m"
PASSWORD="changeme"

echo "[1] Partitioning..."

sgdisk --zap-all $DISK

parted -s $DISK mklabel gpt
parted -s $DISK mkpart ESP fat32 1MiB 513MiB
parted -s $DISK set 1 esp on
parted -s $DISK mkpart ROOT btrfs 513MiB 100%

EFI="${DISK}p1"
ROOT="${DISK}p2"

mkfs.fat -F32 $EFI
mkfs.btrfs -f $ROOT

mount $ROOT /mnt
mkdir -p /mnt/boot
mount $EFI /mnt/boot

echo "[2] pacstrap..."

pacstrap -K /mnt \
base linux linux-firmware amd-ucode \
btrfs-progs sudo openssh git curl \
zellij nvim zenith \
bat eza zoxide fd ripgrep procs sd \
rsync unzip zip man-db man-pages less

genfstab -U /mnt >> /mnt/etc/fstab

echo "[3] copy post-install..."

mkdir -p /mnt/root/setup
cp post-install.sh /mnt/root/setup/

arch-chroot /mnt /bin/bash <<EOF

ln -sf /usr/share/zoneinfo/Europe/Riga /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$HOSTNAME" > /etc/hostname

useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "root:$PASSWORD" | chpasswd

sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

bootctl install
UUID=\$(blkid -s UUID -o value $ROOT)

cat > /boot/loader/entries/arch.conf <<EOL
title Arch Linux
linux /vmlinuz-linux
initrd /amd-ucode.img
initrd /initramfs-linux.img
options root=UUID=\$UUID rw
EOL

cat > /boot/loader/loader.conf <<EOL
default arch
timeout 3
editor no
EOL

systemctl enable sshd

EOF

echo "[4] DONE → reboot"
