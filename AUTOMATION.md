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

## Step 1 — clone the repo (gets scripts + tools)

In Termux:

```
pkg install git curl unzip
git clone https://github.com/markatsos/p30t-mt76
cd p30t-mt76
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
- attach its zip to a release named `mt76-modules.zip` and let `install.sh` fetch
  it, **or**
- unzip its `.ko` files straight into `/data/data/com.termux/files/home/mt76/`.

## Step 4 — install (firmware + loader + boot)

As root, from the cloned repo folder:

```
su
sh scripts/install.sh
```

By default it pulls the prebuilt modules from release **`v1.0`** of
`markatsos/p30t-mt76`. Override any of these with env vars:

```
REPO=youruser/yourrepo TAG=v1.0 MODS_ZIP=mt76-modules.zip sh scripts/install.sh
```

`install.sh` downloads the modules zip (release asset, plain curl — no token),
reads `device-profile.txt` to fetch the right firmware from `linux-firmware`,
installs the plug-and-play watcher, and (if Magisk `service.d` exists) sets up
boot auto-start. It never deploys a custom `cfg80211.ko`.

## Step 5 — use it

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
