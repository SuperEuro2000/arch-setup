#!/bin/bash
set -euxo pipefail

# ===============================
#  USER CONFIG
# ===============================
DISK="/dev/nvme0n1"
HOSTNAME="rch"
USERNAME="m"
SSH_PUB_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILoV8lFVHA2O965fslT+OdBhNb2XJdKY1tls0TlMUAxV supereuro2000@outlook.com"
TIMEZONE="Asia/Yekaterinburg"
LOCALE="en_US.UTF-8"

# ===============================
#  PRECHECKS
# ===============================
echo "[0] PRECHECKS"
if [ ! -b "$DISK" ]; then
    echo "ERROR: Disk not found: $DISK"
    lsblk
    exit 1
fi

# ===============================
#  NETWORK (Live ISO)
# ===============================
echo "[1] NETWORK SETUP"
IFACE=$(ls /sys/class/net | grep -v lo | head -n1)
ip link set "$IFACE" up
dhcpcd "$IFACE"

sleep 3
if ! ping -c 1 archlinux.org >/dev/null 2>&1; then
    echo "[FATAL] No network"
    exit 1
fi
echo "[OK] Network: $IFACE"

# ===============================
#  MIRRORS
# ===============================
echo "[2] SET MIRRORS"
cat > /etc/pacman.d/mirrorlist <<EOL
## Russia (first priority)
Server = http://mirror.kamtv.ru/archlinux/\$repo/os/\$arch
Server = https://mirror.kamtv.ru/archlinux/\$repo/os/\$arch
Server = http://mirror.kpfu.ru/archlinux/\$repo/os/\$arch
Server = https://mirror.kpfu.ru/archlinux/\$repo/os/\$arch
Server = http://ru.mirrors.cicku.me/archlinux/\$repo/os/\$arch
Server = https://ru.mirrors.cicku.me/archlinux/\$repo/os/\$arch
Server = http://mirror.yandex.ru/archlinux/\$repo/os/\$arch
Server = https://mirror.yandex.ru/archlinux/\$repo/os/\$arch

## Latvia (fallback)
Server = http://ftp.linux.edu.lv/archlinux/\$repo/os/\$arch
Server = https://ftp.linux.edu.lv/archlinux/\$repo/os/\$arch
Server = http://archlinux.koyanet.lv/archlinux/\$repo/os/\$arch
Server = https://archlinux.koyanet.lv/archlinux/\$repo/os/\$arch
EOL

# ===============================
#  PARTITION
# ===============================
echo "[3] PARTITIONING"
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
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
umount /mnt

mount -o defaults,noatime,compress=zstd,subvol=@ $ROOT /mnt
mkdir -p /mnt/{boot,home,.snapshots}
mount -o defaults,noatime,compress=zstd,subvol=@home $ROOT /mnt/home
mount -o defaults,noatime,compress=zstd,subvol=@snapshots $ROOT /mnt/.snapshots
mount $EFI /mnt/boot

# ===============================
#  BASE INSTALL
# ===============================
echo "[4] PACSTRAP BASE SYSTEM"
pacman-key --init
pacman-key --populate archlinux

pacstrap -K /mnt base linux linux-firmware amd-ucode \
btrfs-progs sudo openssh git curl networkmanager iwd snapper snap-pac \
--overwrite "*"

genfstab -U /mnt >> /mnt/etc/fstab

# ===============================
#  CONFIGURATION (CHROOT)
# ===============================
echo "[5] CHROOT CONFIG"
arch-chroot /mnt /bin/bash <<EOF
set -eux

# TIMEZONE
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# LOCALE
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# HOSTNAME
echo "$HOSTNAME" > /etc/hostname

# USER
useradd -m -G wheel -s /bin/bash $USERNAME
mkdir -p /home/$USERNAME/.ssh
echo "$SSH_PUB_KEY" > /home/$USERNAME/.ssh/authorized_keys
chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
chmod 700 /home/$USERNAME/.ssh
chmod 600 /home/$USERNAME/.ssh/authorized_keys

# SUDO
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# BOOTLOADER (systemd-boot)
bootctl install

UUID=\$(blkid -s UUID -o value $ROOT)

cat > /boot/loader/entries/arch.conf <<EOL
title Arch Linux
linux /vmlinuz-linux
initrd /amd-ucode.img
initrd /initramfs-linux.img
options root=UUID=\$UUID rw,subvol=@
EOL

cat > /boot/loader/loader.conf <<EOL
default arch
timeout 3
editor no
EOL

# SSH HARDENING
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config

# ENABLE SERVICES
systemctl enable sshd
systemctl enable NetworkManager  # включаем, но в Live ISO не нужен

EOF

echo "[DONE] Installation complete. Reboot now."

echo "⚠️  Reminder: Run snapper create-config after first SSH login:"
echo "sudo snapper -c root create-config / && sudo systemctl enable snapper-timeline.timer snapper-cleanup.timer"
