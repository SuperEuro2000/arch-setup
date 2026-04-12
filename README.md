# Как запускать

## 0. Создание загрузочной флешки

Используем [Ventoy](https://www.ventoy.net/en/index.html) либо [balenaEtcher](https://etcher.balena.io), затем [скачиваем](https://github.com/ikatson/rqbit?tab=readme-ov-file) [ISO образ с оф сайта арча](https://archlinux.org/download/) 

## 1. В Live ISO:

```bash
pacman -Sy git
git clone https://github.com/SuperEuro2000/arch-setup
cd arch-setup
chmod +x install.sh
./install.sh
```

## 2. После перезагрузки:

```bash
ssh user@IP
sudo bash /root/setup/post-install.sh
```

---

## ручная установка
Для этого также нужно иметь физический доступ (подключены: клавиатура, монитор) 
Загружаемся через iso образ арча

```bash
passwd

```
На ПК расположенном в локальной сети вводим команды:
```bash
ssh-keygen -R [IP_ADDRESS]
ssh root@[IP_ADDRESS]
```

Производим очистку диска:
```bash
sgdisk --zap-all /dev/nvme0n1
wipefs -a /dev/nvme0n1
```

Создаем разметку:
```bash
sgdisk -n 1:0:+512M -t 1:ef00 /dev/nvme0n1 # EFI 512Mb
sgdisk -n 2:0:+8G  -t 2:8200 /dev/nvme0n1  # SWOP 8Gb
sgdisk -n 3:0:0     -t 3:8300 /dev/nvme0n1 # Root (остаток)
```

Форматирование:
```bash
mkfs.fat -F32 /dev/nvme0n1p1
mkswap -f /dev/nvme0n1p2
mkfs.btrfs -f /dev/nvme0n1p3
```

### 4 создаем в subVolumes

```bash
mount /dev/nvme0n1p3 /mnt

btrfs subvolume create /mnt/@           # корень (root)
btrfs subvolume create /mnt/@home       # домашняя директория (пользователь)
btrfs subvolume create /mnt/@var_log    # логи
btrfs subvolume create /mnt/@var_pkg    # пакеты (pacman cache)
btrfs subvolume create /mnt/@var_tmp    # временные файлы
btrfs subvolume create /mnt/@data       # данные (LLM / модели)
btrfs subvolume create /mnt/@snapshots  # снимки (snapper)

umount /mnt

mount -o subvol=@,compress=zstd:3,noatime,ssd,discard=async,space_cache=v2 /dev/nvme0n1p3 /mnt

mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,.snapshots,data}
mkdir -p /mnt/var/tmp

mount -o subvol=@home /dev/nvme0n1p3 /mnt/home
mount -o subvol=@var_log /dev/nvme0n1p3 /mnt/var/log
mount -o subvol=@var_pkg /dev/nvme0n1p3 /mnt/var/cache/pacman/pkg
mount -o subvol=@var_tmp /dev/nvme0n1p3 /mnt/var/tmp
mount -o subvol=@data /dev/nvme0n1p3 /mnt/data
mount -o subvol=@snapshots /dev/nvme0n1p3 /mnt/.snapshots
```

Проверка
```bash
lsblk
```
```bash
NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
loop0         7:0    0 967.1M  1 loop /run/archiso/airootfs
sda           8:0    1 115.5G  0 disk 
├─sda1        8:1    1   1.2G  0 part 
└─sda2        8:2    1   252M  0 part 
nvme0n1     259:0    0 931.5G  0 disk 
├─nvme0n1p1 259:2    0   512M  0 part /mnt/boot
├─nvme0n1p2 259:4    0     8G  0 part [SWAP]
└─nvme0n1p3 259:5    0   923G  0 part /mnt/.snapshots
                                      /mnt/data
                                      /mnt/var/tmp
                                      /mnt/var/cache/pacman/pkg
                                      /mnt/var/log
                                      /mnt/home
                                      /mnt
```


Проверка:
```bash
findmnt -R /mnt
```
```bash
TARGET                      SOURCE                      FSTYPE OPTIONS
/mnt                        /dev/nvme0n1p3[/@]          btrfs  rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvolid=256,subvol=/@
├─/mnt/home                 /dev/nvme0n1p3[/@home]      btrfs  rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvolid=257,subvol=/@home
├─/mnt/var/log              /dev/nvme0n1p3[/@var_log]   btrfs  rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvolid=258,subvol=/@var_log
├─/mnt/var/cache/pacman/pkg /dev/nvme0n1p3[/@var_pkg]   btrfs  rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvolid=259,subvol=/@var_pkg
├─/mnt/var/tmp              /dev/nvme0n1p3[/@var_tmp]   btrfs  rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvolid=260,subvol=/@var_tmp
├─/mnt/data                 /dev/nvme0n1p3[/@data]      btrfs  rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvolid=261,subvol=/@data
├─/mnt/.snapshots           /dev/nvme0n1p3[/@snapshots] btrfs  rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvolid=262,subvol=/@snapshots
└─/mnt/boot                 /dev/nvme0n1p1              vfat   rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro
```

### Базовая установка

```bash

pacstrap /mnt base linux linux-firmware btrfs-progs sudo nvim networkmanager openssh git curl base-devel 
```

```bash
genfstab -U /mnt >> /mnt/etc/fstab
```
Редактируем файл fstab (UUID=XXXX /boot vfat umask=0077 0 2)
```bash
nano /mnt/etc/fstab
```

```bash
echo "KEYMAP=us" > /etc/vconsole.conf
```

#### chroot - заходим в будущую систему

```bash
arch-chroot /mnt
```


```bash
# timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
# locale
nvim /etc/locale.gen # раскомментируем en_US.UTF-8 UTF-8
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
# hostname
echo "arch" > /etc/hostname
nvim /etc/hosts # 127.0.0.1 localhost ::1 localhost 127.0.1.1   arch.localdomain arch

cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   arch.localdomain arch
EOF


# keymap
echo "KEYMAP=us" > /etc/vconsole.conf

# root password
passwd
useradd -m -G wheel -s /bin/bash user
passwd user
EDITOR=nvim visudo # разкомментируй %wheel ALL=(ALL:ALL) ALL 
usermod -aG wheel user

# bootloader
bootctl install
nvim /boot/loader/entries/arch.conf

ROOT_UUID=$(blkid -s UUID -o value /dev/nvme0n1p3)

cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=$ROOT_UUID rootflags=subvol=@ rw
EOF


nvim /boot/loader/loader.conf

cat > /boot/loader/loader.conf <<EOF
default arch
timeout 3
editor no
EOF


# services
systemctl enable NetworkManager
systemctl enable sshd

```

#### Выход из chroot

```bash
exit
umount -R /mnt
reboot
```


## Пост-установка

```bash
pacman -Syu

sudo systemctl status NetworkManager
sudo systemctl status sshd

pacman -S reflector snapper zram-generator 
```

Вход по SSH без пароля:
```bash
ssh-keygen -t ed25519 -C "arch-server"
ssh-copy-id user@[IP_ADDRESS] # на локальной машине
```
(cat ~/.ssh/id_ed25519.pub | ssh m@192.168.1.128 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys") # на локальной машине (ручной способ)

```bash
sudo nvim /etc/ssh/sshd_config # разкомментируй #PermitRootLogin prohibit-password и закомментируй PermitRootLogin no
```

PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes

KbdInteractiveAuthentication no
ChallengeResponseAuthentication no

UsePAM yes

MaxAuthTries 3
LoginGraceTime 20

```bash
sudo systemctl restart sshd
```


---

# 🧠 1. Почему zram тебе нужен

У тебя:

* 32 GB RAM
* LLM (Ollama) → пики памяти

👉 zram:

* сжимает память (zstd)
* уменьшает swap thrashing
* спасает от OOM

---

# ✅ 2. Установка

```bash
sudo pacman -S zram-generator
```

---

# ⚙️ 3. Конфиг (самое важное)

Создаём файл:

```bash
sudo nvim /etc/systemd/zram-generator.conf
```

---

## 🔥 Рекомендуемый конфиг (для тебя)

```ini
[zram0]
zram-size = ram * 0.5
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
```

---

## 🧠 Объяснение:

* `ram * 0.5` → ~16GB (идеально для 32GB RAM)
* `zstd` → лучший баланс скорость/сжатие
* `priority=100` → будет использоваться раньше обычного swap

---

# ⚠️ 4. У тебя уже есть swap-раздел (8GB)

👉 это нормально — оставляем

НО:

* zram → быстрый (RAM)
* swap → fallback (SSD)

👉 именно так и должно быть

---

# 🚀 5. Включаем

```bash
sudo systemctl daemon-reexec
sudo systemctl start systemd-zram-setup@zram0
```

---

# 🔍 6. Проверка

```bash
swapon --show
```

✔ должно быть:

```text
/dev/zram0    partition   ...   [SWAP]
/dev/nvme0n1p2 partition ...   [SWAP]
```

---

```bash
zramctl
```

✔ увидишь:

* размер
* алгоритм (zstd)

---

# ⚡ 7. Приоритеты (важно)

```bash
cat /proc/swaps
```

✔ zram должен иметь **более высокий priority**

---

# 🧠 8. (Очень рекомендую) tuning swappiness

```bash
sudo nvim /etc/sysctl.d/99-sysctl.conf
```

Добавь:

```text
vm.swappiness=180
vm.vfs_cache_pressure=50
```

---

## Почему:

* `180` → активнее использует zram
* меньше давление на RAM
* лучше для LLM

---

Применить:

```bash
sudo sysctl --system
```

---

# 🔥 9. Опционально — отключить swap раздел

Если хочешь full RAM-based:

```bash
sudo swapoff /dev/nvme0n1p2
```

---
---

# ✅ Правильное решение (чисто и без костылей)

Сейчас нужно **один раз правильно создать конфиг**, не ломая твою структуру.

---

# 🔧 Шаги (строго по порядку)

## 1. Временно убираем `.snapshots`

```bash
sudo umount /.snapshots
sudo mv /.snapshots /.snapshots.bak
```

---

## 2. Создаём конфиг Snapper (чисто)

```bash
sudo snapper -c root create-config /
```

👉 теперь ОШИБКИ БЫТЬ НЕ ДОЛЖНО

---

## 3. Удаляем то, что создал Snapper

```bash
sudo umount /.snapshots
sudo rm -rf /.snapshots
```

---

## 4. Возвращаем твой subvolume

```bash
sudo mv /.snapshots.bak /.snapshots
sudo mkdir -p /.snapshots   # на всякий случай
sudo mount -a
```

---

## 5. Проверяем

```bash
snapper list
```

👉 теперь ДОЛЖНО работать

---

# 🔍 Почему это работает

Ты:

1. дал Snapper создать конфиг (без конфликта)
2. потом вернул свою архитектуру

👉 Snapper уже “знает” про config `root` и больше не требует создавать subvolume

---

# ⚠️ По поводу ошибки доступа

```bash
ls /.snapshots → Permission denied
```

👉 это НОРМАЛЬНО

Ты поставил:

```bash
chmod 750
```

👉 значит:

* root может читать
* обычный пользователь — нет

Проверяй так:

```bash
sudo ls /.snapshots
```

---

# 💥 Контрольная проверка

После всех шагов:

```bash
sudo snapper create --description "test"
snapper list
```

---

