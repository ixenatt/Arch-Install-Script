#!/bin/bash
# =============================================================
# 04-chaotic-aur.sh
# Run INSIDE arch-chroot /mnt, after script 03.
# Sets up Chaotic-AUR binary repo and optionally installs
# rtl8821ce-dkms from local pkg file if present.
# =============================================================
set -euo pipefail

echo "==> Importing Chaotic-AUR signing key..."
pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
pacman-key --lsign-key 3056513887B78AEB

echo "==> Installing Chaotic-AUR keyring and mirrorlist..."
pacman -U --noconfirm \
  'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
  'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

echo "==> Adding [chaotic-aur] to /etc/pacman.conf..."
if ! grep -q "\[chaotic-aur\]" /etc/pacman.conf; then
  cat >> /etc/pacman.conf <<EOF

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
  echo "    Added."
else
  echo "    Already present, skipping."
fi

echo "==> Syncing all databases..."
pacman -Syyu --noconfirm

# ---------------------------------------------------------------
# Optional: RTL8821CE wifi driver from local pkg
# ---------------------------------------------------------------
PKG_DIR="/root/Arch-install/pkgs"
if compgen -G "${PKG_DIR}/rtl8821ce-dkms*.pkg.tar.zst" > /dev/null 2>&1; then
  echo "==> Found rtl8821ce-dkms package in ${PKG_DIR}. Installing..."
  pacman -U --noconfirm "${PKG_DIR}"/rtl8821ce-dkms*.pkg.tar.zst
else
  echo "==> No rtl8821ce-dkms pkg found in ${PKG_DIR}. Skipping."
  echo "    To install later: pacman -Ss rtl8821ce-dkms (check Chaotic-AUR)"
fi

echo
echo "==> Script 04 complete. Next: run 05-theme-setup.sh (still inside chroot)"
