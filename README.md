# Как запускать

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
