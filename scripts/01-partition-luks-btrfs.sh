#!/bin/bash
# =============================================================
# 01-partition-luks-btrfs.sh
# Run in Arch live ISO as root, BEFORE arch-chroot.
#
# - Detects existing Linux partitions and lets you choose
#   which one to use as LUKS2 root (can also specify manually)
# - Checks /boot: if already vfat → skip format, only remove
#   Linux-specific files (grub/, vmlinuz*, initramfs*, *-ucode*)
#   leaving Windows EFI/Microsoft/ untouched
# - Creates LUKS2 + btrfs subvolumes + swapfile
# =============================================================
set -euo pipefail

DISK="/dev/nvme0n1"
BOOT="${DISK}p1"
LUKS_NAME="cryptroot"
SWAPFILE_SIZE="8G"

# ---------------------------------------------------------------
# STEP 1: Show current partition layout
# ---------------------------------------------------------------
echo "============================================================"
echo " Current partition layout"
echo "============================================================"
lsblk -f "$DISK"
echo
parted -s "$DISK" unit GiB print
echo

# ---------------------------------------------------------------
# STEP 2: Detect Linux partitions (ext4 / btrfs / xfs)
# ---------------------------------------------------------------
echo "==> Detecting existing Linux partitions on $DISK ..."
LINUX_PARTS=$(lsblk -lno NAME,FSTYPE "$DISK" | awk '$2 ~ /^(ext4|btrfs|xfs|linux-swap)$/ {print "/dev/"$1" ("$2")"}')

if [[ -n "$LINUX_PARTS" ]]; then
  echo
  echo "   Found Linux partitions:"
  echo "$LINUX_PARTS" | nl -ba
  echo
else
  echo "   No Linux filesystems detected on $DISK."
  echo
fi

echo "   Available partitions (all):"
lsblk -lno NAME,FSTYPE,SIZE,LABEL "$DISK" | nl -ba
echo

# ---------------------------------------------------------------
# STEP 3: Let user choose partition to use as LUKS root
# ---------------------------------------------------------------
read -rp "Enter partition to use as LUKS2 root (e.g. nvme0n1p2): " CHOSEN
NEW_ROOT="/dev/${CHOSEN}"

if [[ ! -b "$NEW_ROOT" ]]; then
  echo "!! Device $NEW_ROOT not found. Exiting."
  exit 1
fi

echo
echo "   DISK      : $DISK"
echo "   BOOT      : $BOOT"
echo "   LUKS ROOT : $NEW_ROOT"
echo "   SWAP      : swapfile ${SWAPFILE_SIZE} inside LUKS (no separate swap partition)"
echo
read -rp "Confirm: ALL DATA on $NEW_ROOT will be destroyed. Type YES to continue: " CONFIRM
[[ "${CONFIRM^^}" == "YES" ]] || { echo "Aborted."; exit 1; }

# ---------------------------------------------------------------
# STEP 4: Handle /boot partition
# ---------------------------------------------------------------
BOOT_FSTYPE=$(lsblk -no FSTYPE "$BOOT" 2>/dev/null || echo "")

if [[ "$BOOT_FSTYPE" == "vfat" ]]; then
  echo
  echo "==> $BOOT is already vfat. Skipping format."
  echo "==> Mounting $BOOT temporarily to clean Linux bootloader files..."

  TMP_BOOT=$(mktemp -d)
  mount "$BOOT" "$TMP_BOOT"

  echo "==> Removing Linux-specific files only (keeping Windows EFI intact):"
  # Remove GRUB
  if [[ -d "${TMP_BOOT}/grub" ]]; then
    echo "    Removing /boot/grub/"
    rm -rf "${TMP_BOOT}/grub"
  fi
  # Remove Linux kernels / initramfs / microcode
  find "$TMP_BOOT" -maxdepth 1 \
    \( -name "vmlinuz*" -o -name "initramfs*" -o -name "*-ucode.img" \) \
    -exec echo "    Removing {}" \; -exec rm -f {} \;
  # Remove Linux EFI entries (keep EFI/Microsoft and EFI/BOOT)
  if [[ -d "${TMP_BOOT}/EFI" ]]; then
    for efi_dir in "${TMP_BOOT}/EFI"/*/; do
      folder=$(basename "$efi_dir")
      if [[ "${folder,,}" != "microsoft" && "${folder,,}" != "boot" ]]; then
        echo "    Removing EFI/${folder}/"
        rm -rf "$efi_dir"
      fi
    done
  fi

  echo "==> Remaining files in $BOOT after cleanup:"
  find "$TMP_BOOT" -not -path "$TMP_BOOT" | sed "s|${TMP_BOOT}||"
  umount "$TMP_BOOT"
  rmdir "$TMP_BOOT"
else
  echo
  echo "==> $BOOT is not vfat (detected: '${BOOT_FSTYPE:-none}'). Formatting as FAT32..."
  mkfs.vfat -F32 -n BOOT "$BOOT"
fi

# ---------------------------------------------------------------
# STEP 5: LUKS2
# ---------------------------------------------------------------
echo
echo "==> Creating LUKS2 container on $NEW_ROOT"
echo "    You will be asked to set a passphrase (used every boot)."
echo "    cryptsetup will ask you to type YES (capital) as its own safety prompt."
echo
cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 --key-size 512 \
  --hash sha512 --pbkdf argon2id --use-random "$NEW_ROOT"

echo "==> Opening LUKS container as /dev/mapper/${LUKS_NAME}"
cryptsetup open "$NEW_ROOT" "$LUKS_NAME"

# ---------------------------------------------------------------
# STEP 6: btrfs + subvolumes
# ---------------------------------------------------------------
echo "==> Creating btrfs filesystem"
mkfs.btrfs -L archroot "/dev/mapper/${LUKS_NAME}"

echo "==> Creating btrfs subvolumes"
mount "/dev/mapper/${LUKS_NAME}" /mnt
for sv in @ @home @log @pkg @snapshots @swap; do
  btrfs subvolume create "/mnt/$sv"
  echo "    Created @${sv#@}"
done
umount /mnt

# ---------------------------------------------------------------
# STEP 7: Mount subvolumes
# ---------------------------------------------------------------
echo "==> Mounting subvolumes"
OPTS="noatime,compress=zstd:1,space_cache=v2,discard=async"
mount -o "${OPTS},subvol=@" "/dev/mapper/${LUKS_NAME}" /mnt
mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,.snapshots,swap,boot}
mount -o "${OPTS},subvol=@home"       "/dev/mapper/${LUKS_NAME}" /mnt/home
mount -o "${OPTS},subvol=@log"        "/dev/mapper/${LUKS_NAME}" /mnt/var/log
mount -o "${OPTS},subvol=@pkg"        "/dev/mapper/${LUKS_NAME}" /mnt/var/cache/pacman/pkg
mount -o "${OPTS},subvol=@snapshots"  "/dev/mapper/${LUKS_NAME}" /mnt/.snapshots
mount -o "noatime,nodatacow,subvol=@swap" "/dev/mapper/${LUKS_NAME}" /mnt/swap

# ---------------------------------------------------------------
# STEP 8: Swapfile
# ---------------------------------------------------------------
echo "==> Creating ${SWAPFILE_SIZE} swapfile (no-COW required for btrfs)"
truncate -s 0 /mnt/swap/swapfile
chattr +C /mnt/swap/swapfile
fallocate -l "$SWAPFILE_SIZE" /mnt/swap/swapfile
chmod 600 /mnt/swap/swapfile
mkswap /mnt/swap/swapfile
swapon /mnt/swap/swapfile

# ---------------------------------------------------------------
# STEP 9: Mount /boot
# ---------------------------------------------------------------
echo "==> Mounting $BOOT → /mnt/boot"
mount "$BOOT" /mnt/boot

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo
echo "============================================================"
echo " Mount summary"
echo "============================================================"
findmnt /mnt
echo
lsblk -f "$DISK"
echo
echo "==> Script 01 complete. Next: run 02-pacstrap-fstab.sh"
