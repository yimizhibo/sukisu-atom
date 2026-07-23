# 把 SukiSU-Ultra 适配到 Redmi 10X 5G（代号 atom，Android 12）

> 你的设备：Redmi 10X 5G / atom / 联发科天玑 820（MT6875）/ 内核 **4.14.186** / Android 12
> 结论先行：**SukiSU-Ultra 已经支持 Android 12，但它发布的 `.ko` 只覆盖 5.10+ 的 GKI 内核。你的 4.14 是非 GKI 老内核，必须「把 SukiSU 源码编进 kernel 树里一起编译」——也就是本仓库帮你做的事。**

---

## 1. 原理（为什么不能直接刷 .ko）

KernelSU 系分两种集成方式：

| 方式 | 适用 | 你的设备 |
|------|------|----------|
| **LKM / GKI `.ko`** | 内核 5.10+（GKI） | ❌ 不适用 |
| **in-tree 编译（内置）** | 非 GKI 老内核 4.4+ | ✅ 你就是这个 |

SukiSU-Ultra 官方 `setup.sh` 做的事就是 in-tree 集成：把仓库 `KernelSU/kernel` 软链到 `drivers/kernelsu`，再在 `drivers/Makefile` 和 `Kconfig` 挂上 `CONFIG_KSU`。我们对 4.14 的 atom 内核启用 `CONFIG_KSU=y` 后一起编译即可。

官方明确标注：*“Older kernels (4.4+) are also compatible, but the kernel will have to be built manually.”* 本仓库就是把「手动编译」自动化成 GitHub Actions。

---

## 2. 前提条件（务必确认）

1. **bootloader 已解锁**，且能进 fastboot / 有自定义 recovery（如 TWRP/OrangeFox）。
2. **你有可启动的内核源码**（GPL，开源）。本仓库默认用社区维护的 atom 内核：
   `https://github.com/mt6873-dev/kernel_redmi_atom`（正好是 **4.14.186**，和你的内核版本一致）。
   - ⚠️ 强烈建议用**你当前 ROM 对应的内核源码**编译，硬件驱动兼容性最好（WiFi/蓝牙/GPS 等）。如果你刷的是某第三方 Android 12 ROM，去那个 ROM 的内核仓库 clone 即可，改 `kernel_repo` 输入即可。
3. **你当前 ROM 的 `boot.img`**（回包时要拿它的 ramdisk）。
4. 心理准备：刷内核有变砖风险，先备份 `boot` / `vbmeta` 分区。

---

## 3. 用 GitHub Actions 编译（推荐，无需本地环境）

### 3.1 把你自己的仓库建起来
1. 把本目录（`build.sh` + `.github/`）上传到一个**你自己的** GitHub 仓库（fork 或新建都行）。
2. 进入仓库 **Settings → Actions → General → Workflow permissions**，勾选 **Read and write permissions**（上传产物需要）。

### 3.2 触发编译
- 进入 **Actions → “Build SukiSU-Ultra (atom / Redmi 10X 5G)” → Run workflow**。
- 输入参数（默认已填好，一般不用改）：
  - `kernel_repo`：`https://github.com/mt6873-dev/kernel_redmi_atom`
  - `kernel_branch`：`android-4.14-r-stable`（kernel_redmi_atom 仓库唯一的分支，仓库里没有 `main`）
  - `defconfig`：`atom_user_defconfig`（在仓库的 `arch/arm64/configs/vendor/` 子目录里，build.sh 会自动复制它到顶层再编译；若换内核仓库，用 `find arch/arm64/configs -name '*atom*'` 确认真实名字）
  - `ksu_ref`：`susfs-main`（SukiSU-Ultra 的 susfs 分支，**明确支持非 GKI 编译**；只想要纯 KSU 可填 `main`）
  - `toolchain`：`gcc`（对 4.14 MTK 最稳；clang 也行但需额外修 asm 坑）
- 点 **Run workflow**，等 10–30 分钟。
- 完成后在 **Actions → 对应 run → Artifacts** 里下载 `sukisu-atom-kernel.zip`，里面是编译好的 `Image.gz-dtb`（内核已内嵌 dtb）以及 `dtb/`。

### 3.3 本地编译（可选）
在 Linux（Ubuntu 22.04+）上，装好 `bc bison flex libssl-dev libelf-dev gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi`，然后：
```bash
git clone <你的内核仓库> kernel
cd kernel
bash /path/to/build.sh   # 用脚本内默认参数，或 export 环境变量覆盖
```
产物在 `artifact/`。

---

## 4. 回包 & 刷入

编译出来的是裸内核 `Image.gz-dtb`，需要塞回 `boot.img` 的 ramdisk 才能刷。

### 方式 A：手机上用 Magisk（最省事，推荐）
1. 把下载的 `Image.gz-dtb` 和**你当前 ROM 的 `boot.img`** 拷到手机。
2. 手机装 Termux，把本仓库的 `repack.sh` 和 `magiskboot` 放进去（Magisk 自带 `magiskboot`，在 `/data/adb/magisk/magiskboot` 或 Termux 里 `pkg install magiskboot`）。
3. 运行：
   ```bash
   bash repack.sh /sdcard/boot.img /sdcard/Image.gz-dtb
   ```
   生成 `sukisu-boot.img`。
4. 电脑端：
   ```bash
   fastboot flash boot sukisu-boot.img
   fastboot --disable-verity --disable-verification flash vbmeta
   fastboot reboot
   ```

### 方式 B：电脑端（需 x86_64 的 `unpackbootimg`/`mkbootimg`）
用 osm0sis 的 `mkbootimg` 工具集先把 `boot.img` 解开，再用新内核重包：
```bash
unpackbootimg --input boot.img --output out/
mkbootimg \
  --kernel Image.gz-dtb \
  --ramdisk out/boot.img-ramdisk.gz \
  --dtb out/boot.img-dtb \          # 若 Image.gz-dtb 已含 dtb 则省略此项
  --base <out 里的 base> --pagesize <...> --os_version 12 \
  --output sukisu-boot.img
fastboot flash boot sukisu-boot.img
fastboot --disable-verity --disable-verification flash vbmeta
```

### 验证
开机后装 **SukiSU-Ultra Manager APK**（发布页里的 `SukiSU_vX.Y.Z-release.apk`），打开能识别到 KSU 即成功。

---

## 5. MediaTek 4.14 内核的已知坑（已尽量自动化处理）

- **工具链**：默认用 **GCC**，`KCFLAGS=-Wno-error` 防止新版 GCC 把警告当错误。若用 clang，脚本会自动修 `arch/arm64/kernel/vdso/gettimeofday.S` 里 `clock_gettime_return` 后的多余逗号（4.14 经典坑）。
- **`CONFIG_CC_STACKPROTECTOR_STRONG`**：clang 下建议设成 `NONE`，否则可能编不过；GCC 一般无此问题。
- **`CONFIG_KALLSYMS=y` / `CONFIG_KALLSYMS_ALL=y`**：已写入 defconfig（KPM/模块需要）。
- **`set_memory.h` 向后移植**：内核 < 4.19 时需要从 4.19 移植 `set_memory.h`，SUSFS 才正常。用 `susfs-main` 分支通常已带，否则见 SukiSU 文档。
- **`path_umount` 向后移植**：内核 < 5.9（4.14 属于）时，“Umount module”功能需要把 `path_umount` 移植进 `fs/namespace.c`，否则该功能不可用（不影响 root 本身）。

---

## 6. 排错

| 现象 | 处理 |
|------|------|
| CI 报 defconfig 找不到 | 改 `defconfig` 输入为内核仓库里真实的名字（用 `find arch/arm64/configs -name '*atom*'` 确认） |
| 内核编出来但**开机卡米/重启** | 多半是 hook 方式问题。默认走 kprobe（`CONFIG_KPROBES=y`）。若 kprobe 在该内核不稳定，需手动 hook：在 `fs/exec.c`、`fs/open.c`、`fs/read_write.c`、`fs/stat.c` 按 [官方 non-GKI 指南](https://kernelsu.org/guide/how-to-integrate-for-non-gki.html) 打补丁，并开 `CONFIG_KSU_MANUAL_HOOK=y` |
| WiFi/蓝牙/GPS 不工作 | 内核源码和当前 ROM 不匹配，换用 ROM 对应的内核仓库重编 |
| 管理器识别不到 KSU | 确认刷的是合并了 `Image.gz-dtb` 的 `boot.img`，且 `vbmeta` 已 disable 校验 |

---

## 7. 免责声明

刷内核 / root 会使保修失效、有变砖风险。操作前请完整备份。本仓库仅做自动化集成，不保证所有硬件在任意 ROM 上都完美工作——非 GKI 内核碎片化严重，遇到问题多参考上方的排错表和官方文档。
