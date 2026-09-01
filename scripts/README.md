# scripts

Three ways to load the stack, from most manual to fully automatic. All must run
as **root** and expect:

- the seven `.ko` files in `/data/data/com.termux/files/home/modules/`
- `mt7662.bin` and `mt7662_rom_patch.bin` in `/data/data/com.termux/files/home/`

Paths are hard-coded for a Termux + Magisk + NetHunter (`kali-arm64` chroot)
setup. Edit the variables at the top of each script if your paths differ.

| Script | What it does | When to use |
|---|---|---|
| `alfa-up.sh` | One-shot: stage firmware, load modules (card **unplugged** first, then plug in when prompted), you finish monitor mode inside NetHunter. | Simplest; good for understanding the flow. |
| `alfa-watch.sh` | Background watcher: detects the card by USB ID (`0e8d:7612`) on plug-in, loads the stack **without tripping the vendor watchdog** (autoprobe off + manual sysfs bind), then sets monitor mode via the Kali chroot automatically. | Day-to-day plug-and-play. Start once per boot (or via `alfa-boot.sh`). |
| `alfa-boot.sh` | Magisk `service.d` script that auto-starts `alfa-watch.sh` after boot. Boot-safe: waits for `sys.boot_completed`, settle delay, backgrounded, kill-switch. | Place in `/data/adb/service.d/` for zero-touch. See warnings in the main README. |

## The watchdog trick

Unisoc's `native_hang_monitor` panics the kernel if a module's `init` takes
>~2s. `mt76x2u` uploads firmware during probe, which is slower. So the scripts:

1. `echo 0 > /sys/bus/usb/drivers_autoprobe` — module `init` won't touch the HW
2. `insmod` all modules (returns instantly)
3. `echo 1 > /sys/bus/usb/drivers_autoprobe` — restore for other devices
4. `echo 1-1:1.0 > /sys/bus/usb/drivers/mt76x2u/bind` — the slow firmware
   upload happens here, outside the watchdog-timed `module_init` path

## Kill-switch (for alfa-boot.sh)

```
touch /data/adb/alfa-disable    # disable auto-start
rm    /data/adb/alfa-disable    # re-enable
```
