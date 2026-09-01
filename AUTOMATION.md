# Automated setup (any rooted GKI device)

This flow tries to make the whole thing work on **any** rooted Android device
with Magisk — not just the Teclast P30T. It cannot be fully one-click, because
the kernel modules **must** be built from your device's exact kernel source
(that's what makes them load), and that build can only run on a real Linux box /
GitHub Actions, not on the phone. So the flow is:

```
detect.sh  →  Run workflow (with your profile)  →  install.sh
 (device)          (GitHub, ~35 min)                (device)
```

## Honesty about scope

This works cleanly when **all** of these hold (detect.sh checks them):

- `CONFIG_MODULES=y` and `MODULE_SIG_FORCE` is **not** set (unsigned modules load)
- your kernel's commit is **public** on the Android Common Kernel tree
- you can match `CONFIG_DEBUG_INFO_BTF` and the LTO mode of the stock kernel

It will **not** work if the vendor never published the matching kernel source,
if the kernel enforces module signatures, or if `CONFIG_MODULES` is off. Those
are hard blockers, not bugs — detect.sh will tell you.

The **fast path** (Teclast P30T / Unisoc UMS9230 T615, kernel
`...g4ea0fcb5d130...`) is fully tested. Everything else is best-effort.

---

## Step 1 — probe the device

In Termux, as root (needs `curl`: `pkg install curl`):

```
su
sh detect.sh
cat device-profile.txt
```

Read the **VERDICT**:

- **FAST PATH** → you're on the known-good UMS9230; use workflow defaults.
- **LIKELY BUILDABLE** → use the values from `device-profile.txt` as inputs.
- **NOT BUILDABLE** → a blocker is listed; stop here.

Plug the Wi-Fi adapter in before running, so it can detect the chipset/firmware.

## Step 2 — build the modules (GitHub Actions)

1. Fork the repo, open **Actions → Build Wi-Fi modules (parametrized) → Run**.
2. Fill the inputs from `device-profile.txt`:
   - **kcommit** = `COMMIT_SHORT` (or the full hash)
   - **clang_ver** = your toolchain (P30T: `clang-r450784e`)
   - **btf** = value of `CONFIG_DEBUG_INFO_BTF` (`y`/`n`)
   - **lto** = `full` if `LTO_FULL=y`, else `thin`/`none`
   - **driver** = value of `DRIVER` (e.g. `mt76x2u`)
   On the P30T you can just press Run — the defaults are its values.
3. Wait ~35 min. The run log prints the **module_layout CRC** — compare it to
   the one detect.sh will show if you re-run it; they must match, or the modules
   won't load.

## Step 3 — install on the device

In Termux, as root (needs `curl` + `unzip`):

```
su
sh install.sh <your-github-user>/<repo>
```

This downloads the artifact your build produced, fetches the right firmware from
`linux-firmware`, installs the plug-and-play watcher, and (if Magisk
`service.d` exists) sets up boot auto-start.

For a **private** fork, export a token first: `export GH_TOKEN=ghp_...`.

## Step 4 — use it

```
nohup sh ~/alfa-watch.sh >~/alfa-watch.log 2>&1 &
# plug in the adapter; wlan1 comes up in monitor mode automatically
```

Or just reboot (if you installed the boot script) and plug the adapter in ~30s
after the system is up.

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
