#!/bin/bash
# =============================================================
# 02-pacstrap-fstab.sh
# Run in live ISO after script 01.
# Minimal GNOME install with GNOME Shell Extension support.
# =============================================================
set -euo pipefail

echo "==> Updating mirrorlist with reflector (Thailand/Singapore/Japan)..."
timedatectl set-ntp true

reflector --country Thailand,Singapore,Japan --age 12 --protocol https \
  --sort rate --save /etc/pacman.d/mirrorlist
  
echo echo "============================================================" 
echo " Updating Arch Linux keyring" 
echo "============================================================" 
pacman -Syy --noconfirm archlinux-keyring

echo "==> Running pacstrap..."
pacstrap -K /mnt \
  base base-devel linux linux-firmware linux-headers \
  amd-ucode btrfs-progs dosfstools ntfs-3g \
  sudo vim nano curl git \
  networkmanager iwd \
  grub efibootmgr os-prober \
  dkms \
  tpm2-tools tpm2-tss \
  pipewire pipewire-pulse pipewire-alsa wireplumber \
  mesa vulkan-radeon \
  reflector \
  \
  gdm \
  gnome \
  gnome-tweaks \
  gnome-shell-extensions \
  gnome-keyring \
  polkit \
  noto-fonts \ 
  noto-fonts-cjk \ 
  noto-fonts-emoji \ 
  noto-fonts-extra \ 
  ttf-roboto \
  ttf-roboto-mono

echo
echo "==> Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
echo
echo "==> fstab content:"
cat /mnt/etc/fstab

echo
echo "==> Script 02 complete."
echo "==> Before chroot, bind-mount Arch-install folder if needed:"
echo "    mkdir -p /mnt/root/Arch-install"
echo "    mount --bind /mnt-ventoy/Arch-install /mnt/root/Arch-install"
echo
echo "==> Then: arch-chroot /mnt"
echo "==> Then: run /root/Arch-install/scripts/03-chroot-config.sh"
