#!/bin/bash
# =============================================================
# 05-theme-setup.sh
# Run INSIDE arch-chroot /mnt (or after reboot with sudo).
# Installs:
#   - xenlism-grub-arch-1080p GRUB theme (from GitHub)
#   - yaru-gtk-theme, yaru-icon-theme (from Chaotic-AUR)
# =============================================================
set -euo pipefail

GRUB_THEME_NAME="xenlism-grub-arch-1080p"
GRUB_THEME_REPO="https://github.com/xenlism/Grub-themes"
GRUB_THEME_URL="${GRUB_THEME_REPO}/raw/main/${GRUB_THEME_NAME}.tar.xz"
THEME_DEST="/boot/grub/themes"
TMP_DIR="$(mktemp -d)"

# ---------------------------------------------------------------
# Chaotic-AUR check
# ---------------------------------------------------------------
if ! grep -q "\[chaotic-aur\]" /etc/pacman.conf; then
  echo "!! [chaotic-aur] not found in pacman.conf."
  echo "   Run 04-chaotic-aur.sh first. Exiting."
  exit 1
fi

# ---------------------------------------------------------------
# Yaru theme from Chaotic-AUR
# ---------------------------------------------------------------
echo "==> Installing yaru-gtk-theme and yaru-icon-theme from Chaotic-AUR..."
pacman -S --needed --noconfirm yaru-gtk-theme yaru-icon-theme

# ---------------------------------------------------------------
# Xenlism GRUB theme
# ---------------------------------------------------------------
echo "==> Downloading ${GRUB_THEME_NAME} from GitHub..."
curl -L --progress-bar -o "${TMP_DIR}/${GRUB_THEME_NAME}.tar.xz" "$GRUB_THEME_URL"

echo "==> Extracting archive..."
tar -xf "${TMP_DIR}/${GRUB_THEME_NAME}.tar.xz" -C "$TMP_DIR"

# Find theme.txt regardless of nested folder structure
THEME_TXT=$(find "$TMP_DIR" -name "theme.txt" | head -n1)
if [[ -z "$THEME_TXT" ]]; then
  echo "!! theme.txt not found in archive. Check contents:"
  find "$TMP_DIR" -maxdepth 4
  exit 1
fi
THEME_SRC_DIR="$(dirname "$THEME_TXT")"

echo "==> Installing theme to ${THEME_DEST}/${GRUB_THEME_NAME}/"
mkdir -p "$THEME_DEST"
rm -rf "${THEME_DEST:?}/${GRUB_THEME_NAME}"
cp -r "$THEME_SRC_DIR" "${THEME_DEST}/${GRUB_THEME_NAME}"

# ---------------------------------------------------------------
# Update /etc/default/grub
# ---------------------------------------------------------------
echo "==> Updating /etc/default/grub..."
sed -i '/^GRUB_THEME=/d' /etc/default/grub
sed -i '/^GRUB_GFXMODE=/d' /etc/default/grub
sed -i '/^GRUB_GFXPAYLOAD_LINUX=/d' /etc/default/grub

{
  echo "GRUB_THEME=\"${THEME_DEST}/${GRUB_THEME_NAME}/theme.txt\""
  echo "GRUB_GFXMODE=1920x1080,auto"
  echo "GRUB_GFXPAYLOAD_LINUX=keep"
} >> /etc/default/grub

echo "==> Regenerating GRUB config..."
grub-mkconfig -o /boot/grub/grub.cfg

# ---------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------
rm -rf "$TMP_DIR"

echo
echo "==> Script 05 complete."
echo "==> GRUB theme: ${GRUB_THEME_NAME} (1080p)"
echo "==> GTK/Icon theme: Yaru (set via GNOME Tweaks or gsettings after login)"
echo
echo "    To apply Yaru after first login:"
echo "    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru'"
echo "    gsettings set org.gnome.desktop.interface icon-theme 'Yaru'"
