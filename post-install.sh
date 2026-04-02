#!/bin/bash
set -euxo pipefail

echo "[1] system update"
pacman -Syu --noconfirm

echo "[2] zram setup"
pacman -S --noconfirm zram-generator

cat > /etc/systemd/zram-generator.conf <<EOL
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOL

echo "[3] enable services"
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable sshd

ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

echo "[4] firewall"
pacman -S --noconfirm ufw
systemctl enable ufw
systemctl start ufw
ufw --force enable

echo "[5] dev tools"
pacman -S --noconfirm docker

systemctl enable docker

echo "[6] user tweaks"
mkdir -p /home/user/.config
chown -R user:user /home/user

echo "[7] ssh hardening"

sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config || true

systemctl restart sshd

echo "[DONE]"