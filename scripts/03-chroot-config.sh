#!/bin/bash
# =============================================================
# 03-chroot-config.sh
# Run INSIDE arch-chroot /mnt only.
# Uses sd-encrypt hook (systemd-based) for TPM2 auto-unlock.
# TPM2 enrollment is done AFTER first boot via 06-enroll-tpm.sh
# =============================================================
set -euo pipefail
set -x

# ---- Adjust these if needed ----
DISK="/dev/nvme0n1"
ROOT_PART="${DISK}p2"
LUKS_NAME="cryptroot"
HOSTNAME="xenarch"
TIMEZONE="Asia/Bangkok"
USERNAME="xenatt"
# --------------------------------

# ---------------------------------------------------------------
# STEP 1: Root password + user setup
# ---------------------------------------------------------------
echo "==> Set password for root"
passwd

echo "==> Creating user: ${USERNAME}"
useradd -m -g users -G wheel,storage,network,power,video,audio -s /bin/bash "$USERNAME"

echo "==> Set password for ${USERNAME}"
passwd "$USERNAME"

echo "==> Granting sudo to wheel group"
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# ---------------------------------------------------------------
# STEP 2: Timezone, locale, hostname
# ---------------------------------------------------------------
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc


# ---------------------------------------------------------------
# STEP 2.1: Configure NTP (Thailand + Global)
# ---------------------------------------------------------------

echo "==> Configuring systemd-timesyncd..."

cat >/etc/systemd/timesyncd.conf <<'EOF'
[Time]
# Thailand NTP servers
NTP=time1.nimt.or.th time2.nimt.or.th

# Global fast fallback
FallbackNTP=time.cloudflare.com time.google.com pool.ntp.org
EOF





echo "==> Generating locale (en_US + th_TH)"
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/; s/^#th_TH.UTF-8/th_TH.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "==> Setting hostname: ${HOSTNAME}"
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF


# ---------------------------------------------------------------
# STEP 3: mkinitcpio + GRUB
# ---------------------------------------------------------------
echo "==> Configuring mkinitcpio hooks (systemd + sd-encrypt for TPM2)"
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)/' \
  /etc/mkinitcpio.conf
mkinitcpio -P

UUID=$(blkid -s UUID -o value "$ROOT_PART")
echo "==> LUKS UUID: ${UUID}"

echo "==> Installing GRUB to /boot"
grub-install \
  --target=x86_64-efi \
  --efi-directory=/boot \
  --boot-directory=/boot \
  --bootloader-id=GRUB \
  --recheck

echo "==> Configuring /etc/default/grub"
sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet\"|" /etc/default/grub
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"rd.luks.name=${UUID}=${LUKS_NAME} root=/dev/mapper/${LUKS_NAME} rootflags=subvol=@ rw\"|" \
  /etc/default/grub

echo "==> Generating GRUB config (os-prober will scan for Windows)"
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Backing up GRUB EFI to fallback path (prevents HP BIOS from losing boot entry)"
mkdir -p /boot/EFI/BOOT
cp /boot/EFI/GRUB/grubx64.efi /boot/EFI/BOOT/BOOTX64.EFI


# ---------------------------------------------------------------
# STEP 4: Services
# ---------------------------------------------------------------
# =============================================================
# 04-systemd-resolved.sh
# Configure NetworkManager + systemd-resolved + Cloudflare DNS
# =============================================================

echo "==> Configuring systemd-resolved..."

mkdir -p /etc/systemd

cat >/etc/systemd/resolved.conf <<'EOF'
[Resolve]
DNS=1.1.1.1 1.0.0.1
FallbackDNS=2606:4700:4700::1111 2606:4700:4700::1001
DNSSEC=allow-downgrade
DNSOverTLS=opportunistic
Cache=yes
MulticastDNS=no
LLMNR=no
EOF

echo "==> Configuring NetworkManager..."

mkdir -p /etc/NetworkManager/conf.d

cat >/etc/NetworkManager/conf.d/10-dns.conf <<'EOF'
[main]
dns=systemd-resolved
EOF



# =============================================================
# Setup reflector (Arch Linux mirror auto optimizer)
# =============================================================


echo
echo "==> Creating reflector config..."

mkdir -p /etc/xdg/reflector

cat >/etc/xdg/reflector/reflector.conf <<'EOF'
--country Thailand,Singapore,Japan
--latest 20
--protocol https
--sort rate
--age 12
--save /etc/pacman.d/mirrorlist
EOF

echo
echo "==> Running reflector immediately (update mirrorlist)..."

reflector \
  --country Thailand,Singapore,Japan \
  --latest 20 \
  --protocol https \
  --sort rate \
  --age 12 \
  --save /etc/pacman.d/mirrorlist
echo
echo "==> Done."
echo "Mirrorlist updated and auto-refresh enabled."



echo
echo "============================================================"
echo " Configuration complete"
echo "============================================================"
echo
echo "After reboot, verify with:"
echo
echo "  resolvectl status"
echo "  resolvectl query archlinux.org"
echo "==> Enabling system services"
systemctl enable gdm
systemctl enable NetworkManager
systemctl enable systemd-resolved
systemctl enable reflector.timer
systemctl enable fstrim.timer
systemctl enable systemd-timesyncd

echo "==> Creating /etc/resolv.conf symlink..."

rm -f /etc/resolv.conf
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

echo
echo "==> Script 03 complete. Next: run 04-chaotic-aur.sh (still inside chroot)"
