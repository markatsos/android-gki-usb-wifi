#!/system/bin/sh
# service.sh - Magisk late_start service for the GKI USB Wi-Fi module.
# Loads mac80211 + the USB driver the SAFE way (autoprobe off, then sysfs bind)
# so the Unisoc native_hang_monitor watchdog can't panic on the slow firmware
# upload. Waits for the device to be unlocked first (CE storage / stable USB).
#
# This file is generated into the flashable ZIP; MODDIR is the module's own dir.

MODDIR="${0%/*}"                      # this module's install dir
KMOD="$MODDIR/modules"
FW="$MODDIR/firmware"
USB_ID="__USB_ID__"                   # filled in by the build (e.g. 0e8d:7612)
DRV_KO="__DRV_KO__"                   # leaf module filename (e.g. mt76x2u.ko)
DRV_NAME="__DRV_NAME__"               # driver dir under /sys/bus/usb/drivers (e.g. mt76x2u)

LOG="$MODDIR/load.log"
log() { echo "$(date '+%H:%M:%S') $*" >> "$LOG"; }
: > "$LOG"

# 1) wait for boot + a stable moment
n=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $n -lt 150 ]; do sleep 2; n=$((n+1)); done
sleep 20

# 2) stage firmware where the kernel loader can read it
FWDIR=/data/local/tmp/fw
mkdir -p "$FWDIR"
for f in "$FW"/*; do
  [ -e "$f" ] || continue
  b=$(basename "$f")
  cp "$f" "$FWDIR/$b"
  chmod 644 "$FWDIR/$b"
  chcon u:object_r:vendor_file:s0 "$FWDIR/$b" 2>/dev/null
done
echo "$FWDIR" > /sys/module/firmware_class/parameters/path 2>/dev/null
log "firmware staged at $FWDIR"

# 3) load modules with USB autoprobe OFF so module_init never touches the HW
echo 0 > /sys/bus/usb/drivers_autoprobe 2>/dev/null
for m in "$KMOD"/mac80211.ko "$KMOD"/mt76.ko "$KMOD"/mt76-usb.ko \
         "$KMOD"/mt76x02-lib.ko "$KMOD"/mt76x02-usb.ko \
         "$KMOD"/mt76x2-common.ko "$KMOD"/*.ko ; do
  [ -e "$m" ] || continue
  base=$(basename "$m" .ko); lsn=$(echo "$base" | tr '-' '_')
  lsmod | grep -q "^$lsn " && continue
  insmod "$m" 2>/dev/null && log "loaded $base"
done
echo 1 > /sys/bus/usb/drivers_autoprobe 2>/dev/null

# 4) if the card is already attached, bind it now (firmware upload happens here,
#    outside module_init → watchdog can't fire). Retry with USB reset on timeout.
DRV="/sys/bus/usb/drivers/$DRV_NAME"
find_dev() {
  for d in /sys/bus/usb/devices/*/idProduct; do
    dir=$(dirname "$d"); [ -f "$dir/idVendor" ] || continue
    [ "$(cat "$dir/idVendor"):$(cat "$d")" = "$USB_ID" ] && { basename "$dir"; return 0; }
  done; return 1
}
dev=$(find_dev) || { log "card not attached; modules ready, will bind on plug-in"; exit 0; }

attempt=1
while [ $attempt -le 3 ]; do
  [ -e "$DRV/${dev}:1.0" ] || echo "${dev}:1.0" > "$DRV/bind" 2>/dev/null
  i=0; while [ $i -lt 12 ]; do ip link show wlan1 >/dev/null 2>&1 && break; sleep 1; i=$((i+1)); done
  if ip link show wlan1 >/dev/null 2>&1; then log "wlan1 up (attempt $attempt)"; break; fi
  log "wlan1 not up (attempt $attempt) - USB reset"
  echo "$dev" > /sys/bus/usb/drivers/usb/unbind 2>/dev/null; sleep 2
  echo "$dev" > /sys/bus/usb/drivers/usb/bind   2>/dev/null; sleep 3
  dev=$(find_dev) || break
  attempt=$((attempt+1))
done

# 5) set monitor mode once wlan1 exists AND the Kali chroot is usable.
#    Runs in the background so boot is never held up; gives up quietly after
#    ~10 min (e.g. NetHunter never opened this session).
CHROOT_BIN=/data/data/com.termux/files/usr/bin/chroot
ROOTFS=/data/local/nhsystem/kali-arm64
IW=/usr/sbin/iw

set_monitor_bg() {
  (
    i=0
    while [ $i -lt 300 ]; do          # up to ~10 min
      if ip link show wlan1 >/dev/null 2>&1 \
         && [ -x "$CHROOT_BIN" ] && [ -e "$ROOTFS$IW" ]; then
        ip link set wlan1 down 2>/dev/null
        "$CHROOT_BIN" "$ROOTFS" "$IW" dev wlan1 set type monitor 2>/dev/null
        ip link set wlan1 up 2>/dev/null
        m=$("$CHROOT_BIN" "$ROOTFS" "$IW" dev wlan1 info 2>/dev/null | grep -o 'type monitor')
        if [ "$m" = "type monitor" ]; then
          log "wlan1 set to MONITOR mode"
          return 0
        fi
      fi
      sleep 2; i=$((i+1))
    done
    log "monitor mode not set (wlan1 or Kali chroot unavailable) - use the Action button in Magisk, or set it manually"
  ) &
}

# only try if the module is configured to auto-enable monitor (default: yes)
AUTOMON="$MODDIR/automonitor"
[ -f "$AUTOMON" ] || echo 1 > "$AUTOMON"
if [ "$(cat "$AUTOMON" 2>/dev/null)" = "1" ]; then
  set_monitor_bg
  log "monitor mode: auto-enable requested (background)"
else
  log "monitor mode: auto-enable disabled (toggle via Magisk Action button)"
fi

log "done"
