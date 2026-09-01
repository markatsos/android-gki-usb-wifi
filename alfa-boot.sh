#!/system/bin/sh
# alfa-boot.sh - Magisk service.d boot script.
# Auto-starts the Alfa watcher AFTER boot completes. Boot-safe by design:
#   - waits for sys.boot_completed before doing anything
#   - adds a settle delay so the system is stable first
#   - backgrounds everything so a hang here can never stall boot
#   - honors a persistent kill-switch so you never need recovery to disable it
#
# INSTALL: place at /data/adb/service.d/alfa-boot.sh  (chmod 755)
#
# DISABLE PERMANENTLY (if it ever misbehaves), from adb/recovery/root shell:
#   touch /data/adb/alfa-disable
# RE-ENABLE:
#   rm /data/adb/alfa-disable

# persistent kill-switch (survives reboot, unlike /data/local/tmp)
[ -f /data/adb/alfa-disable ] && exit 0

# detach entirely so nothing here can block the boot sequence
(
  n=0
  while [ "$(getprop sys.boot_completed)" != "1" ] && [ $n -lt 120 ]; do
    sleep 2; n=$((n+1))
  done
  sleep 30   # let the system settle

  WATCH=/data/data/com.termux/files/home/alfa-watch.sh
  LOG=/data/data/com.termux/files/home/alfa-watch.log
  [ -f "$WATCH" ] && nohup sh "$WATCH" > "$LOG" 2>&1 &
) &

exit 0
