# Troubleshooting

Common problems, what the log/dmesg looks like, and how to fix them. Check the
watcher log first:

```
cat /data/data/com.termux/files/home/usbwifi-watch.log
```

and kernel messages:

```
su
dmesg | grep -iE "mt76|firmware|usb 1-1|wlan"
```

---

## `wlan1` appears but monitor mode fails in airodump

```
ioctl(SIOCSIWMODE) failed: Operation not supported
Error setting monitor mode on wlan1
```

**Cause:** airodump is trying the old wireless-extensions API; mt76 needs
`nl80211` (`iw`), which lives in the Kali chroot. Also, the chroot mounts must be
active.

**Fix:**
1. Open the **NetHunter app once** this session (activates the chroot mounts).
2. Let the watcher set monitor mode (it uses `iw` in the chroot). Confirm:
   ```
   cat ~/usbwifi-watch.log     # -> [OK] wlan1 is UP in MONITOR mode.
   ```
3. Then in NetHunter, run `airodump-ng wlan1` **without** letting it change the
   mode. If it still complains, set it manually first:
   ```
   ip link set wlan1 down
   iw dev wlan1 set type monitor
   ip link set wlan1 up
   airodump-ng wlan1
   ```

---

## `firmware upload failed: -110` / `probe failed with error -5`

```
mt76x2u 1-1:1.0: firmware upload failed: -110
mt76x2u: probe of 1-1:1.0 failed with error -5
```

**Cause:** `-110` is a USB **timeout** — the firmware was found and started
uploading, but the chip didn't respond in time. This is almost always **USB
power/stability**, worst right after boot when the system draws a lot of current
and OTG can't feed the adapter cleanly. (The AWUS036ACM pulls a fair bit on its
radios.)

**What the watcher does automatically:** on failure it forces a USB
unbind/rebind (a clean re-enumeration) and retries up to 3 times. You'll see:
```
[!] wlan1 not up (attempt 1/3) - firmware upload may have timed out
  USB reset (1-1): unbind/rebind to recover firmware upload
```
It usually succeeds within a couple of tries.

**Permanent fix if it keeps happening:** use a **powered OTG hub / powered OTG
cable**. Stable external power makes the timeout disappear entirely.

---

## Modules don't load: `disagrees about version of symbol module_layout`

```
insmod: ERROR: could not insert module ...: Invalid module format
dmesg: mac80211: disagrees about version of symbol module_layout
```

**Cause:** the modules were built for a *different* kernel than the one running.
With `CONFIG_MODVERSIONS`, the `module_layout` CRC must match exactly.

**Fix:**
- On the reference device (P30T / UMS9230) use the release binaries — they match.
- On any other device you **must build your own** against your exact kernel:
  ```
  sh scripts/detect.sh      # shows your commit + config
  ```
  Then run the parametrized workflow with those values, and compare the
  `module_layout` CRC in the build log to your kernel. If they differ, the
  `kcommit` / `btf` / `lto` inputs don't match your device — recheck them.

---

## Modules missing: `ERROR: modules missing in .../mt76`

**Cause:** an old install left a watcher pointing at the pre-v2 path (`~/mt76`).

**Fix:** re-run `install.sh` from a fresh clone — it now migrates the old layout
and overwrites stale scripts:
```
cd ~ && rm -rf android-gki-usb-wifi
git clone https://github.com/markatsos/android-gki-usb-wifi
cd android-gki-usb-wifi
su
sh scripts/install.sh
```
Also delete any leftover old clone: `rm -rf ~/p30t-mt76`.

---

## Kernel panic / reboot when loading the driver

```
Kernel panic: mt76x2u.ko loads too long time
sprd_modules_exit ... [native_hang_monitor]
```

**Cause:** Unisoc's `native_hang_monitor` watchdog panics if a module's `init`
takes >~2s, and firmware upload during probe is slower.

**Fix:** this is already handled — the loader inserts modules with USB
**autoprobe disabled** so `module_init` returns instantly, then binds manually.
Only relevant if you're loading modules **by hand**: load with the card
**unplugged**, or use the watcher (which does it correctly). Never `insmod` the
USB driver with the card already attached on a Unisoc device.

---

## Boot: card not recognized until I run something

**Cause (old):** the boot script started before the encrypted Termux storage was
unlocked, so it couldn't find the scripts/modules.

**Fix:** already handled — `usbwifi-boot.sh` now waits for the device to be unlocked
before starting. If you still hit it, make sure:
- you **unlock** the device after reboot (the script waits for that)
- the kill-switch isn't set: `ls /data/adb/usbwifi-disable` (delete it if present)

---

## The internal Wi-Fi (`wlan0`) broke

**Cause:** a custom `cfg80211.ko` was loaded over the stock one.

**Fix:** **never** load a built `cfg80211.ko` — the scripts delete it on purpose.
Reboot to restore the stock stack. Only `mac80211` + the USB driver modules
should be loaded on top of the **stock** `cfg80211`.

---

## Still stuck?

Collect these and open an issue:

```
su
uname -r
cat ~/usbwifi-watch.log
dmesg | grep -iE "mt76|firmware|usb 1-1|wlan|native_hang" | tail -40
sh scripts/detect.sh        # paste device-profile.txt too
```
