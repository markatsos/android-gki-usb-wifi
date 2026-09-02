#!/system/bin/sh
# Best-effort unload on module removal. A reboot fully reverts regardless.
for m in mt76x2u mt76x2_common mt76x02_usb mt76x02_lib mt76_usb mt76 mac80211; do
  rmmod "$m" 2>/dev/null
done
