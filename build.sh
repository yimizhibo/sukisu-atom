#!/usr/bin/env bash
# ============================================================
# SukiSU-Ultra builder for Redmi 10X 5G (codename: atom)
# Non-GKI, in-tree build for kernel 4.14.x (MediaTek MT6875)
#
# This script is meant to be run inside GitHub Actions (see
# .github/workflows/build.yml) but also works locally on Linux.
# ============================================================
set -euo pipefail

# ---- configurable inputs (override via env) ----
KERNEL_REPO="${KERNEL_REPO:-https://github.com/mt6873-dev/kernel_redmi_atom}"
KERNEL_BRANCH="${KERNEL_BRANCH:-android-4.14-r-stable}"
DEFCONFIG="${DEFCONFIG:-atom_user_defconfig}"
KSU_REF="${KSU_REF:-susfs-main}"      # a branch/tag/commit of SukiSU-Ultra
TOOLCHAIN="${TOOLCHAIN:-gcc}"        # gcc | clang
EXTRA_MAKE_FLAGS="${EXTRA_MAKE_FLAGS:-}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
KERNEL_DIR="$ROOT/kernel"
OUT_DIR="$ROOT/out"
ARTIFACT_DIR="$ROOT/artifact"

echo "=================================================="
echo " SukiSU-Ultra builder :: Redmi 10X 5G (atom)"
echo " Kernel   : $KERNEL_REPO @ $KERNEL_BRANCH"
echo " Defconfig: $DEFCONFIG"
echo " KSU ref  : $KSU_REF"
echo " Toolchain: $TOOLCHAIN"
echo "=================================================="

echo "[*] Cloning kernel source..."
rm -rf "$KERNEL_DIR"
git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_DIR"
cd "$KERNEL_DIR"

# ---- toolchain ----
if [ "$TOOLCHAIN" = "clang" ]; then
  export PATH="/usr/lib/llvm-14/bin:$PATH"
  MAKE_VARS="LLVM=1 LLVM_IAS=1 CC=clang"
  # Clang-specific quirks on old 4.14 MediaTek kernels:
  # trailing comma after clock_gettime_return in the vDSO asm.
  sed -i 's/clock_gettime_return,/clock_gettime_return/g' \
    arch/arm64/kernel/vdso/gettimeofday.S 2>/dev/null || true
else
  # GCC is the most reliable choice for 4.14 MTK; disable -Werror so a
  # newer host GCC does not fail the build on new warnings.
  MAKE_VARS="CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-"
  EXTRA_MAKE_FLAGS="$EXTRA_MAKE_FLAGS KCFLAGS=-Wno-error"
fi

# ---- integrate SukiSU-Ultra (in-tree, non-GKI) ----
echo "[*] Integrating SukiSU-Ultra (ref: $KSU_REF)..."
curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" \
  | bash -s "$KSU_REF"

# ---- locate & enable KSU in defconfig ----
# NOTE: on this MTK tree the device defconfig lives under
# arch/arm64/configs/vendor/ (NOT the top-level configs dir).
# `make <name>` only searches the top-level, so we copy it up if nested.
echo "[*] Locating defconfig '$DEFCONFIG'..."
DEF="$(find arch/arm64/configs -name "$DEFCONFIG" | head -n1)"
if [ -z "${DEF:-}" ] || [ ! -f "$DEF" ]; then
  echo "[!] Defconfig '$DEFCONFIG' not found under arch/arm64/configs/."
  echo "    Available defconfigs:"
  find arch/arm64/configs -name '*_defconfig' -o -name 'defconfig' \
    | sed 's#.*/configs/##' | sed 's#^#      - #'
  exit 1
fi
# Copy a nested (vendor/) defconfig to the top-level configs dir so
# `make <name>` can resolve it.
if [ "$(dirname "$DEF")" != "arch/arm64/configs" ]; then
  echo "[*] Defconfig is nested ($DEF); copying to top-level configs dir."
  cp "$DEF" "arch/arm64/configs/$DEFCONFIG"
  DEF="arch/arm64/configs/$DEFCONFIG"
fi
echo "[*] Enabling CONFIG_KSU in $DEF..."
{
  echo "# SukiSU-Ultra (added by build script)"
  echo "CONFIG_KSU=y"
  echo "CONFIG_KPROBES=y"
  echo "CONFIG_HAVE_KPROBES=y"
  echo "CONFIG_KPROBE_EVENTS=y"
  echo "CONFIG_KALLSYMS=y"
  echo "CONFIG_KALLSYMS_ALL=y"
} >> "$DEF"

# ---- build ----
echo "[*] Building kernel (this can take 10-30 min)..."
mkdir -p "$OUT_DIR"
make -j"$(nproc)" ARCH=arm64 O="$OUT_DIR" $MAKE_VARS "$DEFCONFIG"
make -j"$(nproc)" ARCH=arm64 O="$OUT_DIR" $MAKE_VARS $EXTRA_MAKE_FLAGS \
  Image.gz-dtb Image.gz Image 2>&1 | tail -n 60

# ---- collect artifacts ----
echo "[*] Collecting artifacts..."
mkdir -p "$ARTIFACT_DIR"
for f in Image.gz-dtb Image.gz Image; do
  [ -f "$OUT_DIR/arch/arm64/boot/$f" ] && cp "$OUT_DIR/arch/arm64/boot/$f" "$ARTIFACT_DIR/"
done
mkdir -p "$ARTIFACT_DIR/dtb"
find "$OUT_DIR/arch/arm64/boot/dts" -name '*.dtb' -exec cp {} "$ARTIFACT_DIR/dtb/" \; 2>/dev/null || true
echo "[+] Artifacts in $ARTIFACT_DIR:"
ls -lh "$ARTIFACT_DIR"
