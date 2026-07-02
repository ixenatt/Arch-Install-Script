# Arch Linux Installation — LUKS2 + btrfs + TPM2 + Minimal GNOME

**HP 15s-eq000au | AMD Ryzen | Full Disk Encryption + TPM2 Auto-unlock | Dual Boot Windows**

---

## 🇬🇧 English

### Overview

| Item | Detail |
|---|---|
| Machine | HP 15s-eq000au (AMD Ryzen / Radeon Vega) |
| Disk | `/dev/nvme0n1` |
| Boot | `nvme0n1p1` → `/boot` (vfat, unencrypted, EFI + GRUB inside) |
| Root | `nvme0n1p2` → LUKS2 → btrfs |
| Swap | 8 GB swapfile inside LUKS (`@swap` subvolume, no-COW) |
| Windows | Untouched (`nvme0n1p4–p6`) |
| Data | Untouched (`nvme0n1p7`) |
| Unlock | TPM2 auto-unlock (PCR 7), passphrase kept as fallback |
| Desktop | Minimal GNOME + GDM (extension-ready, no extensions pre-installed) |
| Extras | Chaotic-AUR, Yaru theme, Xenlism GRUB theme (1080p) |

### btrfs Subvolume Layout

| Subvolume | Mount Point |
|---|---|
| `@` | `/` |
| `@home` | `/home` |
| `@log` | `/var/log` |
| `@pkg` | `/var/cache/pacman/pkg` |
| `@snapshots` | `/.snapshots` |
| `@swap` | `/swap` (nodatacow) |

### Scripts

| Script | When | Purpose |
|---|---|---|
| `01-partition-luks-btrfs.sh` | Live ISO | Partition detection, LUKS2, btrfs, mount |
| `02-pacstrap-fstab.sh` | Live ISO | pacstrap minimal system, fstab |
| `03-chroot-config.sh` | Inside chroot | locale, mkinitcpio (sd-encrypt), GRUB, services |
| `04-chaotic-aur.sh` | Inside chroot | Chaotic-AUR repo + optional rtl8821ce driver |
| `05-theme-setup.sh` | Inside chroot | Xenlism GRUB theme + Yaru GTK/icon theme |
| `06-enroll-tpm.sh` | After first boot | Enroll TPM2 for auto-unlock |

### Installation Steps

#### A. Boot into Ventoy → Arch ISO (UEFI mode)

```bash
# Verify UEFI
ls /sys/firmware/efi/efivars

# Connect internet (LAN/USB tether recommended — RTL8821CE may not work in live ISO)
iwctl   # or plug in ethernet
```

#### B. Get scripts from GitHub (no need to mount Ventoy)

```bash
git clone https://github.com/xenatt/arch-install.git /root/arch-install
chmod +x /root/arch-install/scripts/*.sh
```

> If `git` is not available in live ISO: `pacman -Sy git` first.
> RTL8821CE pkg (if needed) must be mounted from Ventoy separately after cloning.

#### C. Script 01 — Partition + LUKS2 + btrfs

```bash
/root/arch-install/scripts/01-partition-luks-btrfs.sh
```

- Lists all partitions, detects Linux filesystems, lets you choose which to use
- If `/boot` is already vfat: skips format, removes only Linux files (grub/, vmlinuz*, initramfs*), keeps `EFI/Microsoft/` intact
- `cryptsetup` will ask `YES` (its own prompt) then your passphrase ×2

#### D. Script 02 — pacstrap + fstab

```bash
/root/arch-install/scripts/02-pacstrap-fstab.sh
```

#### E. (Optional) Mount Ventoy for local pkgs

```bash
# Only needed if using local rtl8821ce pkg
lsblk -f   # find Ventoy exFAT partition UUID
mkdir -p /mnt-ventoy
mount -t exfat -o uid=0,gid=0 UUID=<ventoy-uuid> /mnt-ventoy
mkdir -p /mnt/root/arch-install/pkgs
mount --bind /mnt-ventoy/Arch-install/pkgs /mnt/root/arch-install/pkgs
```

#### F. chroot

```bash
arch-chroot /mnt
```

#### G. Set up users (inside chroot)

```bash
passwd
useradd -m -G wheel,video,audio yourname
passwd yourname
EDITOR=vim visudo   # uncomment: %wheel ALL=(ALL:ALL) ALL
```

#### H. Scripts 03–05 (inside chroot)

```bash
cd /root/arch-install/scripts
./03-chroot-config.sh   # locale, sd-encrypt hook, GRUB, services
./04-chaotic-aur.sh     # Chaotic-AUR + optional rtl8821ce
./05-theme-setup.sh     # Xenlism GRUB theme + Yaru theme
```

#### I. Exit and reboot

```bash
exit
umount -R /mnt
swapoff -a
reboot   # remove Ventoy USB when screen goes dark
```

First boot will ask for LUKS **passphrase** (TPM not enrolled yet).

#### J. Script 06 — Enroll TPM2 (after first successful boot)

> **BIOS prerequisite:** HP → Security → TPM Device → **Enabled** (before this step)

```bash
sudo /path/to/06-enroll-tpm.sh
# or download directly:
curl -fsSL https://raw.githubusercontent.com/xenatt/arch-install/main/scripts/06-enroll-tpm.sh | sudo bash
```

- Prompts for LUKS passphrase once (to authorize enrollment)
- Subsequent boots unlock automatically via TPM2
- Passphrase keyslot is **kept as fallback**

### After First Login

```bash
# Apply Yaru theme
gsettings set org.gnome.desktop.interface gtk-theme 'Yaru'
gsettings set org.gnome.desktop.interface icon-theme 'Yaru'

# Verify TPM unlock on next boot
journalctl -b | grep -i 'tpm\|luks\|crypt'
```

### Notes

| Topic | Note |
|---|---|
| TPM PCR policy | PCR 7 (Secure Boot state) — stable across minor updates |
| BIOS update | PCR values change → system falls back to passphrase → re-run script 06 |
| HP boot entry lost | Script 03 copies GRUB to `/boot/EFI/BOOT/BOOTX64.EFI` as fallback |
| Windows not in GRUB | `ntfs-3g` included; check `os-prober`, disable Windows Fast Startup |
| RTL8821CE wifi | Prepare `rtl8821ce-dkms-git` pkg in `Arch-install/pkgs/` on Ventoy |
| GNOME extensions | Install via `extensions.gnome.org` or `pacman`/AUR after login |

---

## 🇹🇭 ภาษาไทย

### ภาพรวม

| รายการ | รายละเอียด |
|---|---|
| เครื่อง | HP 15s-eq000au (AMD Ryzen / Radeon Vega) |
| ดิสก์ | `/dev/nvme0n1` |
| Boot | `nvme0n1p1` → `/boot` (vfat, ไม่เข้ารหัส มี EFI + GRUB อยู่ข้างใน) |
| Root | `nvme0n1p2` → LUKS2 → btrfs |
| Swap | swapfile 8 GB อยู่ใน LUKS (subvolume `@swap`, no-COW) |
| Windows | ไม่แตะต้อง (`nvme0n1p4–p6`) |
| Data | ไม่แตะต้อง (`nvme0n1p7`) |
| ปลดล็อก | TPM2 auto-unlock (PCR 7) — passphrase เป็น fallback |
| Desktop | GNOME แบบ minimal + GDM (รองรับ extension ไม่ได้ลงไว้ล่วงหน้า) |
| เพิ่มเติม | Chaotic-AUR, Yaru theme, Xenlism GRUB theme (1080p) |

### รายการสคริปต์

| สคริปต์ | เมื่อไหร่ | หน้าที่ |
|---|---|---|
| `01-partition-luks-btrfs.sh` | Live ISO | ตรวจ partition, LUKS2, btrfs, mount |
| `02-pacstrap-fstab.sh` | Live ISO | ติดตั้งระบบฐาน, fstab |
| `03-chroot-config.sh` | ข้างใน chroot | locale, mkinitcpio (sd-encrypt), GRUB, services |
| `04-chaotic-aur.sh` | ข้างใน chroot | Chaotic-AUR + ลง rtl8821ce ถ้ามี pkg |
| `05-theme-setup.sh` | ข้างใน chroot | Xenlism GRUB theme + Yaru GTK/icon theme |
| `06-enroll-tpm.sh` | หลัง boot ครั้งแรก | ลงทะเบียน TPM2 ให้ unlock อัตโนมัติ |

### ลำดับการติดตั้ง

#### A. บูตเข้า Ventoy → Arch ISO (UEFI mode)

```bash
ls /sys/firmware/efi/efivars   # เช็คว่าเป็น UEFI จริง
iwctl                          # ต่อ wifi หรือเสียบ LAN/USB tether
```

#### B. ดึงสคริปต์จาก GitHub (ไม่ต้อง mount Ventoy)

```bash
git clone https://github.com/xenatt/arch-install.git /root/arch-install
chmod +x /root/arch-install/scripts/*.sh
```

> ถ้า live ISO ไม่มี `git`: `pacman -Sy git` ก่อน

#### C. สคริปต์ 01 — Partition + LUKS2 + btrfs

```bash
/root/arch-install/scripts/01-partition-luks-btrfs.sh
```

- แสดง partition ทั้งหมด ให้เลือก partition ที่ต้องการใช้เป็น LUKS root
- ถ้า `/boot` เป็น vfat อยู่แล้ว: ข้าม format ลบเฉพาะ Linux files เก็บ `EFI/Microsoft/` ไว้ครบ
- `cryptsetup` จะขอ `YES` (ตัวพิมพ์ใหญ่ — prompt ของตัวโปรแกรมเอง) แล้วตามด้วย passphrase 2 ครั้ง

#### D. สคริปต์ 02 — pacstrap + fstab

```bash
/root/arch-install/scripts/02-pacstrap-fstab.sh
```

#### E. (ถ้าต้องการ) Mount Ventoy สำหรับ pkg wifi

```bash
lsblk -f   # หา UUID ของ Ventoy exFAT partition
mkdir -p /mnt-ventoy
mount -t exfat -o uid=0,gid=0 UUID=<ventoy-uuid> /mnt-ventoy
mkdir -p /mnt/root/arch-install/pkgs
mount --bind /mnt-ventoy/Arch-install/pkgs /mnt/root/arch-install/pkgs
```

#### F. chroot

```bash
arch-chroot /mnt
```

#### G. ตั้งค่า user (ข้างใน chroot)

```bash
passwd
useradd -m -G wheel,video,audio ชื่อ
passwd ชื่อ
EDITOR=vim visudo   # ลบ # หน้า: %wheel ALL=(ALL:ALL) ALL
```

#### H. สคริปต์ 03–05 (ข้างใน chroot)

```bash
cd /root/arch-install/scripts
./03-chroot-config.sh   # locale, sd-encrypt hook, GRUB, เปิด services
./04-chaotic-aur.sh     # Chaotic-AUR + ลง rtl8821ce ถ้ามี pkg
./05-theme-setup.sh     # Xenlism GRUB theme + Yaru theme
```

#### I. ออกจาก chroot และ reboot

```bash
exit
umount -R /mnt
swapoff -a
reboot   # ถอด Ventoy USB ตอนหน้าจอดับ
```

Boot ครั้งแรกจะถาม LUKS **passphrase** ตามปกติ (ยังไม่ได้ enroll TPM)

#### J. สคริปต์ 06 — ลงทะเบียน TPM2 (หลัง boot ครั้งแรกสำเร็จ)

> **เตรียม BIOS ก่อน:** HP → Security → TPM Device → **Enabled**

```bash
sudo bash /root/arch-install/scripts/06-enroll-tpm.sh
# หรือ download ตรงจาก GitHub:
curl -fsSL https://raw.githubusercontent.com/xenatt/arch-install/main/scripts/06-enroll-tpm.sh | sudo bash
```

- ถาม LUKS passphrase ครั้งเดียวเพื่ออนุมัติการ enroll
- boot ครั้งถัดไปจะ unlock อัตโนมัติผ่าน TPM2
- passphrase keyslot **ยังเก็บไว้เป็น fallback** ถ้า TPM ใช้ไม่ได้

### หลังเข้าระบบครั้งแรก

```bash
# ปรับ Yaru theme
gsettings set org.gnome.desktop.interface gtk-theme 'Yaru'
gsettings set org.gnome.desktop.interface icon-theme 'Yaru'

# เช็ค TPM unlock หลัง reboot ครั้งถัดไป
journalctl -b | grep -i 'tpm\|luks\|crypt'
```

### หมายเหตุ / จุดที่ต้องระวัง

| หัวข้อ | รายละเอียด |
|---|---|
| TPM PCR policy | PCR 7 (Secure Boot state) เสถียรที่สุด รอดจาก update เล็กน้อย |
| อัปเดต BIOS | PCR value เปลี่ยน → ระบบ fallback ถาม passphrase → รัน script 06 ใหม่ |
| HP BIOS ลบ boot entry | script 03 สำรอง GRUB ไว้ที่ `/boot/EFI/BOOT/BOOTX64.EFI` อัตโนมัติ |
| Windows ไม่โชว์ใน GRUB | มี `ntfs-3g` ลงไว้แล้ว ถ้ายังไม่โชว์ให้ปิด Fast Startup ใน Windows ก่อน |
| RTL8821CE wifi | เตรียม `rtl8821ce-dkms-git` pkg ใส่ใน Ventoy `Arch-install/pkgs/` |
| GNOME extensions | ติดตั้งเพิ่มเองผ่าน `extensions.gnome.org` หรือ `pacman`/AUR |
