# Clean slate on the device (before testing a fresh install)

Removes everything this project put on the device, so you can install from
scratch like a new user. **Nothing here touches partitions** — a reboot alone
already unloads the modules.

Run as root in Termux:

```sh
su

# 1) stop any running watcher
pkill -f usbwifi-watch.sh 2>/dev/null
pkill -f alfa-watch.sh    2>/dev/null   # old name, if present

# 2) remove boot scripts (both old and new names)
rm -f /data/adb/service.d/usbwifi-boot.sh
rm -f /data/adb/service.d/alfa-boot.sh

# 3) remove kill-switches
rm -f /data/adb/usbwifi-disable /data/adb/alfa-disable

# 4) remove scripts, modules and firmware from the Termux home
H=/data/data/com.termux/files/home
rm -f  "$H"/usbwifi-watch.sh "$H"/usbwifi-up.sh "$H"/usbwifi-watch.log
rm -f  "$H"/alfa-watch.sh    "$H"/alfa-up.sh    "$H"/alfa-watch.log
rm -rf "$H"/modules "$H"/mt76
rm -f  "$H"/mt7662.bin "$H"/mt7662_rom_patch.bin
rm -f  "$H"/device-profile.txt

# 5) remove the staged firmware
rm -rf /data/local/tmp/fw

# 6) remove the cloned repo (optional)
rm -rf "$H"/android-gki-usb-wifi "$H"/p30t-mt76
```

If you also installed the **Magisk module**, remove it from
**Magisk Manager → Modules → (module) → Remove**, then reboot.

Finally reboot so all loaded modules are gone:

```sh
reboot
```

After the reboot, `lsmod | grep -E "mt76|mac80211"` should return nothing — you
are back to stock and ready to test the install from scratch.
