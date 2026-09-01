# p30t-mt76

Build and run MediaTek **MT7612U** USB Wi-Fi adapters (e.g. **ALFA AWUS036ACM**)
in **monitor mode** on the **Teclast P30T** tablet — alongside the internal
Wi-Fi, without replacing the kernel or flashing anything.

![AWUS036ACM on the Teclast P30T — wlan1 auto-loaded in monitor mode](docs/hardware-setup.jpg)

The watcher loads the mt76 stack automatically on plug-in and brings up `wlan1`
in monitor mode — no typing, straight from boot.

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

## Quick install (Teclast P30T / UMS9230 — the tested fast path)

Prebuilt modules for this exact kernel are attached to the
[latest release](../../releases/latest), so you don't have to build anything.
In Termux, rooted (Magisk):

```
pkg install git curl unzip
git clone https://github.com/markatsos/p30t-mt76
cd p30t-mt76
su
sh scripts/detect.sh          # confirms your device matches
sh scripts/install.sh         # pulls modules + firmware, sets up auto-load
```

Then start it (or reboot) and plug in the adapter:

```
nohup sh ~/alfa-watch.sh >~/alfa-watch.log 2>&1 &
cat ~/alfa-watch.log          # -> [OK] wlan1 is UP in MONITOR mode.
```

`iw` / `airodump-ng` run inside the NetHunter (Kali) chroot; the watcher already
sets monitor mode through it. `install.sh` also drops a Magisk boot script (if
`/data/adb/service.d` exists) so it all comes up automatically after a reboot.

On **any other device**, or to build the modules yourself, see
[AUTOMATION.md](AUTOMATION.md).

---

## Demo

`airodump-ng wlan1` scanning in monitor mode via the external MT7612U adapter,
alongside the tablet's internal Wi-Fi. BSSIDs and network names are redacted.

![airodump-ng in monitor mode on wlan1](docs/airodump-demo.jpg)

![airodump-ng in monitor mode on wlan1 — with associated stations](docs/airodump-demo1.jpg)

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
`scripts/detect.sh` checks all of this for you.

---

## What this repo does NOT contain

By design, and for licensing/correctness reasons, this repo does **not** commit:

- compiled `.ko` modules in the source tree (they are GPL-derived **and**
  build-specific — a module built for another kernel is rejected by
  `CONFIG_MODVERSIONS`). Prebuilt modules for the P30T are attached to a
  **release** for convenience, not committed to `main`.
- MediaTek firmware blobs (`mt7662*.bin`) — proprietary; fetched at install time
  from [`linux-firmware`](https://gitlab.com/kernel-firmware/linux-firmware)
- boot/vendor images or extracted vendor trees

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

## Building it yourself

If you're not on the fast path, or you want to build rather than trust the
release binaries, the full flow is in [AUTOMATION.md](AUTOMATION.md):

1. `scripts/detect.sh` reads your kernel/commit/config and emits
   `device-profile.txt`.
2. **Actions → Build Wi-Fi modules (parametrized)** takes those values as inputs
   (defaults are the P30T's) and builds the `.ko` set.
3. `scripts/install.sh` fetches the modules (from a release asset) + firmware and
   sets everything up.

There is also a fixed, non-parametrized workflow (`build.yml`) hard-wired to the
P30T values, if you prefer.

---

## Scripts

See [`scripts/README.md`](scripts/README.md). In short:

| Script | Role |
|---|---|
| `detect.sh` | Probe device; write `device-profile.txt`; verdict. Changes nothing. |
| `install.sh` | Download modules (release) + firmware; install loader + boot script. |
| `alfa-watch.sh` | Plug-triggered loader; sets monitor mode via the Kali chroot. |
| `alfa-boot.sh` | Magisk `service.d` auto-start (boot-safe, kill-switch). |
| `alfa-up.sh` | Manual one-shot loader (understand the flow). |

---

## Warnings

- **Only for networks you own or are explicitly authorized to test.**
- This is a **hybrid** wireless runtime (stock `cfg80211` + custom `mac80211`).
  It works for monitor mode and scanning; injection was not exhaustively
  validated — test with `aireplay-ng --test wlan1` if you need it.
- **Never load a custom `cfg80211.ko`.** The internal Unisoc Wi-Fi
  (`sprd_wlan_combo`) depends on the stock one. The build produces a
  `cfg80211.ko` only so `mac80211` can link; the scripts delete it and never
  deploy it.
- **Boot auto-start carries a small bootloop risk.** `alfa-boot.sh` is written to
  be boot-safe (waits for `sys.boot_completed`, settle delay, backgrounded,
  kill-switch). Still, keep `adb` handy the first time. Kill-switch:
  `touch /data/adb/alfa-disable` disables it; `rm` re-enables.
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
