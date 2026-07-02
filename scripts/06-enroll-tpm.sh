#!/bin/bash
# =============================================================
# 06-enroll-tpm.sh
# Run AFTER first boot into the installed system (with sudo).
# Enrolls the LUKS2 partition into TPM2 for auto-unlock.
#
# Prerequisites:
#   - System booted successfully into Arch (passphrase prompted)
#   - TPM2 enabled in BIOS (HP: Security → TPM Device → Enabled)
#   - tpm2-tools and tpm2-tss must be installed (done in script 02)
#
# After enrollment:
#   - Boot will auto-unlock LUKS via TPM2 (no passphrase prompt)
#   - Passphrase keyslot is kept as fallback (in case TPM fails)
#   - If BIOS is updated → PCR values change → system falls back
#     to passphrase automatically (re-run this script to re-enroll)
# =============================================================
set -euo pipefail

LUKS_PART="/dev/nvme0n1p2"

# ---------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------
echo "==> Checking TPM2 availability..."
if ! tpm2_getcap properties-fixed &>/dev/null; then
  echo "!! TPM2 not accessible. Check BIOS settings:"
  echo "   HP: Security → TPM Device → Enabled"
  echo "   Also ensure tpm2-tss service is available:"
  echo "   systemctl status tpm2-abrmd (optional, not always needed)"
  exit 1
fi
echo "   TPM2 found."

echo "==> Checking LUKS2 partition: ${LUKS_PART}"
if ! cryptsetup isLuks "$LUKS_PART"; then
  echo "!! ${LUKS_PART} is not a LUKS partition. Check LUKS_PART variable."
  exit 1
fi
echo "   Confirmed LUKS2."

echo
echo "==> Current LUKS2 keyslots:"
cryptsetup luksDump "$LUKS_PART" | grep -E "^Keyslots:|^\s+[0-9]+:"
echo

# ---------------------------------------------------------------
# Check if TPM2 token already enrolled
# ---------------------------------------------------------------
if cryptsetup luksDump "$LUKS_PART" | grep -q "tpm2"; then
  echo "==> TPM2 token already present in LUKS header."
  read -rp "Re-enroll (wipe old TPM token and create new)? [y/N]: " REENROLL
  if [[ "${REENROLL,,}" != "y" ]]; then
    echo "Aborted. Existing enrollment kept."
    exit 0
  fi
  echo "==> Wiping existing TPM2 token..."
  # Find and remove tpm2 keyslot
  WIPE_SLOT=$(systemd-cryptenroll "$LUKS_PART" 2>/dev/null | grep tpm2 | awk '{print $1}' || true)
  if [[ -n "$WIPE_SLOT" ]]; then
    sudo systemd-cryptenroll --wipe-slot="$WIPE_SLOT" "$LUKS_PART"
  fi
fi

# ---------------------------------------------------------------
# Enroll TPM2
# PCR 7 = Secure Boot state (most stable, survives minor updates)
# Change to 0+2+7 for stricter binding (re-enroll after BIOS update)
# ---------------------------------------------------------------
echo "==> Enrolling TPM2 with PCR policy (PCR 7 = Secure Boot state)..."
echo "    You will be prompted for your LUKS passphrase to authorize enrollment."
echo
sudo systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrs=7 \
  "$LUKS_PART"

# ---------------------------------------------------------------
# Verify enrollment
# ---------------------------------------------------------------
echo
echo "==> Verifying keyslots after enrollment:"
cryptsetup luksDump "$LUKS_PART" | grep -E "^\s*(Keyslots|[0-9]+:)" || \
cryptsetup luksDump "$LUKS_PART" | grep -A2 "Tokens"
echo

echo "==> Testing TPM2 unlock (dry-run)..."
if systemd-cryptenroll --tpm2-device=auto "$LUKS_PART" 2>&1 | grep -q "already"; then
  echo "   TPM2 token confirmed in keyslots."
fi

# ---------------------------------------------------------------
# Remind about /etc/crypttab for initramfs
# ---------------------------------------------------------------
echo
echo "==> Checking /etc/crypttab.initramfs for tpm2-device entry..."
CRYPTTAB="/etc/crypttab.initramfs"
LUKS_UUID=$(blkid -s UUID -o value "$LUKS_PART")

if grep -q "tpm2-device" "$CRYPTTAB" 2>/dev/null; then
  echo "   Already configured:"
  cat "$CRYPTTAB"
else
  echo "   Adding tpm2-device=auto to /etc/crypttab.initramfs..."
  # Check if entry exists but without tpm2
  LUKS_NAME=$(grep "$LUKS_UUID" "$CRYPTTAB" 2>/dev/null | awk '{print $1}' || echo "cryptroot")
  if grep -q "$LUKS_UUID" "$CRYPTTAB" 2>/dev/null; then
    # Update existing line to add tpm2
    sed -i "s|UUID=${LUKS_UUID}.*|UUID=${LUKS_UUID} none tpm2-device=auto,discard|" "$CRYPTTAB"
  else
    echo "cryptroot UUID=${LUKS_UUID} none tpm2-device=auto,discard" >> "$CRYPTTAB"
  fi
  echo "   Updated:"
  cat "$CRYPTTAB"
fi

echo
echo "==> Rebuilding initramfs to apply tpm2 unlock..."
sudo mkinitcpio -P

echo
echo "============================================================"
echo " TPM2 enrollment complete."
echo "============================================================"
echo
echo " Next boot: LUKS will unlock automatically via TPM2."
echo " No passphrase will be prompted (unless TPM state changes)."
echo
echo " Fallback: If TPM fails (BIOS update / Secure Boot change),"
echo " the system will fall back to asking for passphrase."
echo " Re-run this script after BIOS updates to re-enroll."
echo
echo " To verify after reboot:"
echo "   journalctl -b | grep -i 'tpm\|luks\|crypt'"
echo
