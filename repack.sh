#!/usr/bin/env bash
# ============================================================
# Repack your existing boot.img with the SukiSU kernel.
#
# IMPORTANT: magiskboot is an ARM64 binary. Run this script
# ON THE PHONE (Termux) or on an ARM64 Linux machine.
# On a normal x86_64 PC it will not execute magiskboot.
#
# ---- On-phone quick start (Termux, recommended) ----
#   pkg update && pkg install -y magiskboot curl unzip git
#   # boot.img = the one from the SAME Android 12 ROM you run,
#   # e.g. extracted from the ROM zip, or in TWRP root shell:
#   #   dd if=/dev/block/by-name/boot of=/sdcard/boot.img
#   cp /path/to/Image.gz-dtb /sdcard/
#   bash repack.sh /sdcard/boot.img /sdcard/Image.gz-dtb
#   # -> produces /sdcard/sukisu-boot.img  (flash on PC)
#
# The boot.img MUST come from the same ROM you are running,
# otherwise WiFi / Bluetooth / etc. may break.
# Our Image.gz-dtb already embeds the device tree (dtb); the
# script drops any separately-extracted dtb so it is not doubled.
# ============================================================
set -euo pipefail

BOOT_IMG="${1:-}"
KERNEL_IMG="${2:-artifact/Image.gz-dtb}"

if [ -z "${BOOT_IMG:-}" ] || [ ! -f "$BOOT_IMG" ]; then
  echo "Usage: $0 /path/to/your/boot.img [path/to/Image.gz-dtb]"
  exit 1
fi
if [ ! -f "$KERNEL_IMG" ]; then
  echo "[!] Kernel image not found: $KERNEL_IMG"
  echo "    Build first (GitHub Actions) and download the artifact."
  exit 1
fi

WORK="$(mktemp -d)"
cd "$WORK"
echo "[*] Working in $WORK"

# ---- obtain magiskboot (ARM64) ----
MAGISK_VER="27.0"
if command -v magiskboot >/dev/null 2>&1; then
  MBAIN="$(command -v magiskboot)"
else
  echo "[*] Downloading magiskboot (Magisk v$MAGISK_VER)..."
  URL="https://github.com/topjohnwu/Magisk/releases/download/v${MAGISK_VER}/Magisk-v${MAGISK_VER}.apk"
  curl -LSs -o magisk.apk "$URL"
  # magiskboot lives inside the APK as a shared lib
  ( command -v unzip >/dev/null 2>&1 && unzip -o -q magisk.apk "lib/arm64-v8a/libmagiskboot.so" -d . ) || true
  if [ -f lib/arm64-v8a/libmagiskboot.so ]; then
    cp lib/arm64-v8a/libmagiskboot.so magiskboot
    chmod +x magiskboot
  else
    echo "[!] Could not extract magiskboot."
    echo "    Copy a magiskboot binary next to this script, or run on an ARM64 host."
    exit 1
  fi
  MBAIN="$PWD/magiskboot"
fi

echo "[*] Unpacking boot.img..."
"$MBAIN" unpack "$BOOT_IMG"

echo "[*] Replacing kernel with the SukiSU build..."
cp "$KERNEL_IMG" kernel
# Our Image.gz-dtb already embeds the device tree; drop the
# separately-extracted dtb so repack does not double-add it.
[ -f dtb ] && rm -f dtb

echo "[*] Repacking..."
"$MBAIN" repack "$BOOT_IMG" new-boot.img

OUT_DIR="$(cd "$(dirname "$BOOT_IMG")" && pwd)"
OUT="$OUT_DIR/sukisu-boot.img"
cp new-boot.img "$OUT"
echo "[+] Done: $OUT"
echo ""
echo "Flash with (bootloader unlocked):"
echo "    fastboot flash boot $OUT"
echo "    fastboot --disable-verity --disable-verification flash vbmeta"
