# p30t-mt76

Build and run MediaTek **MT7612U** USB Wi-Fi adapters (e.g. **ALFA AWUS036ACM**)
in **monitor mode** on the **Teclast P30T** tablet — alongside the internal
Wi-Fi, without replacing the kernel or flashing anything.

The P30T uses a **Unisoc UMS9230 (T615)** SoC. Its stock vendor kernel ships
`cfg80211` but **not** `mac80211` or the `mt76` driver stack, so external USB
Wi-Fi adapters don't work out of the box. This repo builds the missing modules
against the **exact** Android Common Kernel commit the device runs, so they load
onto the running stock kernel with matching symbol CRCs — no custom kernel, no
boot-image patching.

> **Scope / honesty:** this is confirmed working on my device (details below).
> It is a *hybrid* runtime — stock `cfg80211` + externally built `mac80211`/`mt76`.
> It passes symbol/version checks and works for monitor mode + scanning, but it
> is not a vendor-blessed configuration. Read the [warnings](#warnings) before
> using it. Only test against networks you own or are authorized to test.

---

## Confirmed environment

| Item | Value |
|---|---|
| Device | Teclast P30T (`P30T_ROW`) |
| Android | 16 (SDK 36) |
| SoC | Unisoc/Spreadtrum UMS9230 (`ums9230_6h10`, T615) |
| Kernel | `5.15.178-android13-8-00012-g4ea0fcb5d130-ab13530115` |
| ACK commit | `4ea0fcb5d1308f2f5a5dec0a3a5c8f1b261e00c7` |
| Toolchain | Android Clang `r450784e` (14.0.7) |
| `CONFIG_MODULES` / `CONFIG_MODVERSIONS` | y / y |
| `module_layout` CRC | `0x0222dd63` |
| Adapter | ALFA AWUS036ACM |
| Chipset | MediaTek MT7612U (USB ID `0e8d:7612`) |

Other UMS9230/T615 devices on the **same kernel string** may work with the same
build (the boot image appears to be a shared Unisoc reference image), but you
must verify your own kernel string and, ideally, your own `module_layout` CRC.

---

## What this repo does NOT contain

By design, and for licensing/correctness reasons, this repo does **not** ship:

- compiled `.ko` modules (they are GPL-derived **and** build-specific — a module
  built for another kernel will be rejected by `CONFIG_MODVERSIONS`)
- MediaTek firmware blobs (`mt7662*.bin`) — proprietary; get them from
  [`linux-firmware`](https://gitlab.com/kernel-firmware/linux-firmware)
- boot/vendor images or extracted vendor trees

You build your own modules with the included GitHub Actions workflow and fetch
firmware from the upstream project. This keeps everything legal and, more
importantly, guarantees the CRCs match *your* device.

---

## How it works (the three problems solved)

1. **Missing driver stack.** The workflow builds `mac80211` + the full `mt76`
   USB stack as modules from the exact ACK commit, with `CONFIG_MODVERSIONS` so
   the resulting `mac80211.ko` links against the *stock* `cfg80211` already
   loaded on the device.
2. **BTF/CRC mismatch.** The stock kernel is built with `CONFIG_DEBUG_INFO_BTF=y`,
   which changes `struct module` and therefore the `module_layout` CRC. The
   workflow installs `pahole` and keeps BTF enabled so the CRC matches
   (`0x0222dd63` on this device).
3. **Vendor watchdog panic.** Unisoc ships a `native_hang_monitor` module that
   panics the kernel if any module's `init` takes longer than ~2s. `mt76x2u`
   uploads firmware to the chip during probe, which is slower than that. The
   loader script inserts the modules with the USB **autoprobe disabled** (so
   `module_init` returns instantly), then binds the device manually via sysfs —
   the slow firmware upload then happens *outside* the watchdog-timed path.

---

## Quick start

### 1. Build the modules (GitHub Actions, no local Linux needed)

1. Fork this repo.
2. **Verify your kernel matches** (on the tablet, in a root shell):
   ```
   uname -r
   ```
   If it is **not** `5.15.178-android13-8-00012-g4ea0fcb5d130-ab13530115`, see
   [Adapting to another build](#adapting-to-another-build) first.
3. Actions tab → **Build mt76 for UMS9230** → **Run workflow**.
4. When it finishes (~35 min), download the `mt76-modules` artifact. It contains
   the seven `.ko` files, plus `Module.symvers` and the `module_layout` CRC in
   the run log (compare it to yours).

### 2. Get the firmware

From [`linux-firmware`](https://gitlab.com/kernel-firmware/linux-firmware/-/tree/main/mediatek),
download `mediatek/mt7662.bin` and `mediatek/mt7662_rom_patch.bin`.

### 3. Put files on the device

Assuming Termux is installed and rooted (Magisk):

```
# modules
mkdir -p /data/data/com.termux/files/home/mt76
# copy the 7 .ko files into that folder

# firmware (next to home, the scripts stage it into /data/local/tmp/fw)
# copy mt7662.bin and mt7662_rom_patch.bin into:
#   /data/data/com.termux/files/home/
```

### 4. Load it

Manual, one-shot (see [`scripts/alfa-up.sh`](scripts/alfa-up.sh)):

```
su
sh /data/data/com.termux/files/home/alfa-up.sh
# then plug in the card when prompted
```

Plug-and-play watcher (see [`scripts/alfa-watch.sh`](scripts/alfa-watch.sh)) —
loads the stack automatically whenever the card is plugged in, and sets monitor
mode via the Kali chroot:

```
su
nohup sh /data/data/com.termux/files/home/alfa-watch.sh \
  >/data/data/com.termux/files/home/alfa-watch.log 2>&1 &
```

Auto-start at boot (see [`scripts/alfa-boot.sh`](scripts/alfa-boot.sh)) — place
it in `/data/adb/service.d/` (Magisk) so the watcher starts after every boot.
**Read the [warnings](#warnings) about this first.**

---

## Adapting to another build

If your kernel string differs:

1. Read the ACK commit from your own kernel — the `gXXXXXXXX` part of `uname -r`
   is the short commit hash. Confirm it exists in the public tree:
   ```
   curl -sI https://android.googlesource.com/kernel/common/+/<hash>
   ```
   A `200` means it's a public ACK commit you can build from.
2. If it's a **different** commit, set `KCOMMIT` in the workflow to yours.
3. If your toolchain differs, change `CLANG_VER` / the branch in the workflow.
4. If your device does **not** have `CONFIG_DEBUG_INFO_BTF=y`, or uses thin LTO,
   adjust the config block. Check with:
   ```
   zcat /proc/config.gz | grep -E "DEBUG_INFO_BTF|LTO|MODVERSIONS"
   ```
5. After building, compare the `module_layout` CRC in the run log to your device.
   If they differ, the modules will be rejected with *"disagrees about version of
   symbol module_layout"* — recheck the commit/config.

---

## Warnings

- **Only for networks you own or are explicitly authorized to test.**
- This is a **hybrid** wireless runtime (stock `cfg80211` + custom `mac80211`).
  It works for monitor mode and scanning; injection was not exhaustively
  validated — test with `aireplay-ng --test wlan1` if you need it.
- **Never load a custom `cfg80211.ko`.** The internal Unisoc Wi-Fi
  (`sprd_wlan_combo`) depends on the stock one. The build produces a
  `cfg80211.ko` only so `mac80211` can link; do not deploy it.
- **Boot auto-start carries a small bootloop risk.** The `alfa-boot.sh` script is
  written to be boot-safe (waits for `sys.boot_completed`, adds a settle delay,
  backgrounds everything, and honors a kill-switch). Still, keep `adb` handy the
  first time. Kill-switch: `touch /data/adb/alfa-disable` disables auto-start;
  `rm` it to re-enable.
- **Boot with the card unplugged**, then plug it in ~30s after the system is up.
  This keeps the card out of the boot-time probe path entirely.
- OTG provides limited current; the AWUS036ACM draws a fair amount on TX. If you
  see drops under load, use a **powered OTG hub**.
- Reboots wipe loaded modules and `/data/local/tmp`; the scripts re-stage
  firmware and reload on demand.

---

## Credits

Built through iterative debugging on real hardware. The general "external modules
on a stock GKI kernel" approach — and the specific ACK commit / `module_layout`
CRC for this exact kernel — were cross-checked against the
[Cubot KingKong ES3 root guide](https://github.com/KiMiGuel/Root-Guide-Cubot-KingKong-ES-3---Unisoc-T615-ums9230-)
by KiMiGuel, which proved the method for AR9271 on the same kernel. This repo
extends it to the MediaTek `mt76` stack and full plug-and-play automation.

## License

Scripts and workflow in this repo: MIT (see `LICENSE`). Built kernel modules are
GPL-2.0 (they derive from the Linux kernel). Firmware is proprietary to MediaTek
and is not distributed here.
