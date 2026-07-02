#!/bin/bash
# =============================================================
# 00-mount-ventoy.sh
# Run in Arch live ISO as root.
# Detects the Ventoy data partition (exFAT) by UUID,
# mounts it, and copies Arch-install/ to /root/.
# =============================================================
set -euo pipefail

ARCH_INSTALL_DIR="Arch-install"
VENTOY_MOUNT="/mnt-ventoy"

echo "==> Current block devices:"
echo
lsblk -f
echo

# ---------------------------------------------------------------
# Detect exFAT partitions on non-nvme drives (Ventoy data partition)
# ---------------------------------------------------------------
echo "==> Detecting exFAT partitions on USB drives..."
echo

# Build list: NAME UUID LABEL for exfat on sd* devices only
mapfile -t EXFAT_LIST < <(lsblk -lno NAME,FSTYPE,UUID,LABEL,SIZE | awk '$2=="exfat" && $1~/^sd/ {print NR")", "/dev/"$1, "UUID="$3, "LABEL="$4, $5}')

if [[ ${#EXFAT_LIST[@]} -eq 0 ]]; then
  echo "   No exFAT partitions found on USB drives."
  echo "   Make sure Ventoy USB is plugged in. Check lsblk output above."
  exit 1
fi

echo "   Found exFAT partitions:"
for line in "${EXFAT_LIST[@]}"; do
  echo "   $line"
done
echo

# If only one candidate, auto-select it
if [[ ${#EXFAT_LIST[@]} -eq 1 ]]; then
  SELECTED="${EXFAT_LIST[0]}"
  echo "==> Auto-selected (only one found): $SELECTED"
  VENTOY_UUID=$(echo "$SELECTED" | awk '{print $4}' | sed 's/UUID=//')
else
  read -rp "Enter number to select Ventoy data partition: " SEL_NUM
  SELECTED="${EXFAT_LIST[$((SEL_NUM - 1))]}"
  VENTOY_UUID=$(echo "$SELECTED" | awk '{print $4}' | sed 's/UUID=//')
fi

if [[ -z "$VENTOY_UUID" ]]; then
  echo "!! Could not determine UUID. Exiting."
  exit 1
fi

echo "==> Ventoy data partition UUID: $VENTOY_UUID"

# ---------------------------------------------------------------
# Mount by UUID (safe and stable regardless of device name)
# ---------------------------------------------------------------
mkdir -p "$VENTOY_MOUNT"
mount -t exfat -o uid=0,gid=0,fmask=0022,dmask=0022 \
  "UUID=${VENTOY_UUID}" "$VENTOY_MOUNT"

echo "==> Mounted UUID=${VENTOY_UUID} at ${VENTOY_MOUNT}"
echo
echo "==> Contents of Ventoy partition:"
ls "$VENTOY_MOUNT"
echo

# ---------------------------------------------------------------
# Copy Arch-install folder
# ---------------------------------------------------------------
if [[ ! -d "${VENTOY_MOUNT}/${ARCH_INSTALL_DIR}" ]]; then
  echo "!! Folder '${ARCH_INSTALL_DIR}' not found in Ventoy partition."
  echo "   Make sure the folder exists at: Ventoy/${ARCH_INSTALL_DIR}/"
  exit 1
fi

echo "==> Copying ${ARCH_INSTALL_DIR}/ to /root/ ..."
cp -r "${VENTOY_MOUNT}/${ARCH_INSTALL_DIR}" /root/
chmod +x /root/${ARCH_INSTALL_DIR}/scripts/*.sh

echo
echo "==> Done. Scripts are at /root/${ARCH_INSTALL_DIR}/scripts/"
ls /root/${ARCH_INSTALL_DIR}/scripts/
echo
echo "==> Ventoy remains mounted at ${VENTOY_MOUNT} (needed for pkgs/ later)."
echo "==> Next step: /root/${ARCH_INSTALL_DIR}/scripts/01-partition-luks-btrfs.sh"
