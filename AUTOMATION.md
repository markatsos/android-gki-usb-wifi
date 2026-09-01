# Automated setup (any rooted GKI device)

This makes external USB Wi-Fi (monitor mode) work on a rooted Android device
with Magisk. It cannot be fully one-click, because the kernel modules **must**
be built from your device's exact kernel source (that's what makes them load),
and that build runs on GitHub Actions, not on the phone. The flow:

```
git clone  →  detect.sh  →  build (Actions)  →  install.sh  →  plug in card
 (device)     (device)       (GitHub, ~35m)     (device)        done
```

For the **known-good Teclast P30T / Unisoc UMS9230 (T615)** on kernel
`...g4ea0fcb5d130...`, prebuilt modules are already attached to the
[latest release](../../releases/latest), so you can skip the build entirely and
`install.sh` just downloads them.

---

## Honesty about scope

This works cleanly when **all** of these hold (detect.sh checks them):

- `CONFIG_MODULES=y` and `MODULE_SIG_FORCE` is **not** set (unsigned modules load)
- your kernel's commit is **public** on the Android Common Kernel tree
- you can match `CONFIG_DEBUG_INFO_BTF` and the LTO mode of the stock kernel

It will **not** work if the vendor never published matching kernel source, if
the kernel enforces module signatures, or if `CONFIG_MODULES` is off. Those are
hard blockers, not bugs — detect.sh tells you.

The **fast path** (P30T / UMS9230) is fully tested end-to-end. Everything else
is best-effort.

---


---

## Supported adapters & drivers

`detect.sh` recognizes the USB IDs below and picks the driver + firmware for you.

| Driver (`driver` input) | Chips | In-tree? | Firmware | Monitor/inject |
|---|---|---|---|---|
| `mt76x2u` | MT7612U/7662 | yes | `mt7662*.bin` | good |
| `mt76x0u` | MT7610U/7630U/7650U | yes | `mt7610u.bin` etc. | good |
| `rt2800usb` | RT5370/5372/3070/3072/2870/3572 | yes | none | good, no firmware needed |
| `ath9k_htc` | AR9271, AR7010 | yes | `htc_9271.fw`/`htc_7010.fw` | good (proven on this SoC) |
| `rtl8xxxu` | RTL8188CU/EU, RTL8192CU/EU | yes | none | varies by chip |
| `rtl88xxau_oot` | RTL8812AU/8814AU/8811AU/8821AU | **no – out-of-tree** | in-driver | good *if it builds* |

**In-tree** drivers build straight from the ACK kernel source and are the safe
bet. **Out-of-tree** Realtek (the popular AWUS036ACH / 8812AU family) is built
from an external repo (default `aircrack-ng/rtl8812au`) against the prepared
kernel; it works when that driver supports your kernel version, but success is
not guaranteed — if the build fails, try a different `oot_branch`.

## Supported kernel generations

Set the `kbranch` input to match your device (detect.sh prints `KERNEL_GEN`):

`android12-5.10` · `android13-5.15` · `android14-6.1` · `android15-6.6`

The `kcommit` must be a **public** commit on that branch (detect.sh checks with
a live HTTP request). If your vendor never published matching source, no build
can produce loadable modules — that's a hard limit, not a bug.

## Step 1 — clone the repo (gets scripts + tools)

In Termux:

```
pkg install git curl unzip
git clone https://github.com/markatsos/android-gki-usb-wifi
cd android-gki-usb-wifi
```

## Step 2 — probe the device

Plug the Wi-Fi adapter in first (so it can read the chipset), then, as root:

```
su
sh scripts/detect.sh
```

`curl` must be available for the commit check (`pkg install curl` if missing).
It writes `device-profile.txt` and prints a **VERDICT**:

- **FAST PATH** → you're on the known-good UMS9230; skip to Step 4 (prebuilt
  modules are in the release).
- **LIKELY BUILDABLE** → use `device-profile.txt` values as build inputs (Step 3).
- **NOT BUILDABLE** → a blocker is listed; stop here.

## Step 3 — build the modules (only if NOT on the fast path)

Fork the repo, then **Actions → Build Wi-Fi modules (parametrized) → Run**, and
fill the inputs from `device-profile.txt`:

| Input | From device-profile.txt |
|---|---|
| `kcommit` | `COMMIT_SHORT` (or the full hash) |
| `clang_ver` | your toolchain (P30T: `clang-r450784e`) |
| `btf` | value of `CONFIG_DEBUG_INFO_BTF` (`y`/`n`) |
| `lto` | `full` if `LTO_FULL=y`, else `thin` / `none` |
| `driver` | value of `DRIVER` (e.g. `mt76x2u`) |

Wait ~35 min. The run log prints the **module_layout CRC** — it must match your
device (re-run detect.sh shows nothing about CRC, but if the modules later fail
to load with *"disagrees about version of symbol module_layout"*, the CRC didn't
match and you should recheck the commit/config).

Download the `wifi-modules` artifact, then either:
- attach its zip to a release named `modules.zip` and let `install.sh` fetch
  it, **or**
- unzip its `.ko` files straight into `/data/data/com.termux/files/home/modules/`.

## Step 4 — install (firmware + loader + boot)

As root, from the cloned repo folder:

```
su
sh scripts/install.sh
```

By default it pulls the prebuilt modules from release **`v2.0`** of
`markatsos/android-gki-usb-wifi`. Override any of these with env vars:

```
REPO=youruser/yourrepo TAG=v2.0 MODS_ZIP=modules.zip sh scripts/install.sh
```

`install.sh` downloads the modules zip (release asset, plain curl — no token),
reads `device-profile.txt` to fetch the right firmware from `linux-firmware`,
installs the plug-and-play watcher, and (if Magisk `service.d` exists) sets up
boot auto-start. It never deploys a custom `cfg80211.ko`.

## Step 5 — use it

> **Prerequisite for monitor mode:** open the **NetHunter app once** after each
> boot before plugging in the adapter. `iw` runs inside the Kali chroot, and its
> mounts (`/sys`, `/dev`) must be active — otherwise the modules load and `wlan1`
> appears, but the switch to monitor mode fails silently. Opening NetHunter (or
> its terminal) once activates the chroot for the session.


```
nohup sh ~/alfa-watch.sh >~/alfa-watch.log 2>&1 &
# plug in the adapter; wlan1 comes up in monitor mode automatically
cat ~/alfa-watch.log        # look for: [OK] wlan1 is UP in MONITOR mode.
```

`iw`/`airodump-ng` live in the NetHunter (Kali) chroot; the watcher already sets
monitor mode via that chroot. If you didn't install the boot script, just start
the watcher once per boot as above.

---

## Kill-switch (boot script)

If auto-start ever misbehaves:

```
touch /data/adb/alfa-disable   # disable
rm    /data/adb/alfa-disable   # re-enable
```

## What detect.sh reads (changes nothing)

- `uname -r` → kernel version + ACK commit hash
- `curl` HEAD on gitiles → is that commit public/buildable
- `/proc/config.gz` → MODULES, MODVERSIONS, BTF, LTO, MODULE_SIG_FORCE
- `/sys/bus/usb/devices` → plugged adapter's USB ID → driver + firmware
- `getenforce`, `lsmod` → SELinux mode, Unisoc watchdog presence

## Tested

The full flow — `git clone` → `detect.sh` → `install.sh` (release asset +
firmware + Magisk boot) → watcher → `wlan1` monitor mode — was verified on a
Teclast P30T from a clean checkout.
