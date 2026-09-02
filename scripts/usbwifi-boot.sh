#!/system/bin/sh
# usbwifi-boot.sh - Magisk service.d boot script.
# Auto-starts the Alfa watcher once the device is actually usable.
#
# Boot-safe by design:
#   - waits for sys.boot_completed
#   - THEN waits for the Termux home to become readable, because that folder is
#     on credential-encrypted (CE) storage and stays locked until the first
#     unlock after boot. Starting the watcher before that fails silently (the
#     modules and the script itself live there).
#   - backgrounds everything so nothing here can stall boot
#   - honors a persistent kill-switch
#
# INSTALL: /data/adb/service.d/usbwifi-boot.sh  (chmod 755)
# DISABLE: touch /data/adb/usbwifi-disable      RE-ENABLE: rm /data/adb/usbwifi-disable

[ -f /data/adb/usbwifi-disable ] && exit 0

HOME_DIR=/data/data/com.termux/files/home
WATCH="$HOME_DIR/usbwifi-watch.sh"
LOG="$HOME_DIR/usbwifi-watch.log"

(
  # 1. wait for boot to complete
  n=0
  while [ "$(getprop sys.boot_completed)" != "1" ] && [ $n -lt 150 ]; do
    sleep 2; n=$((n+1))
  done

  # 2. wait for CE storage (Termux home) to be unlocked/readable.
  #    This is the key fix: the folder exists but is unreadable until the user
  #    unlocks the device once. Poll until the watcher script is actually there.
  n=0
  while [ ! -r "$WATCH" ] && [ $n -lt 900 ]; do   # up to ~30 min of waiting
    sleep 2; n=$((n+1))
  done
  [ -r "$WATCH" ] || exit 0    # never showed up; give up quietly

  # 3. small settle, then start the watcher (only if not already running)
  sleep 5
  if ! pgrep -f usbwifi-watch.sh >/dev/null 2>&1; then
    nohup sh "$WATCH" > "$LOG" 2>&1 &
  fi
) &

exit 0
