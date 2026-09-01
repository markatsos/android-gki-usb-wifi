#!/system/bin/sh
# alfa-watch.sh - Plug-triggered loader + auto monitor-mode for AWUS036ACM
# (MT7612U) on Teclast P30T (UMS9230), NetHunter/Kali chroot.
#
# Polls USB; when the Alfa card (0e8d:7612) appears it loads the mt76 stack
# with USB autoprobe DISABLED (module_init returns instantly, never tripping
# the native_hang_monitor watchdog), binds the card manually via sysfs
# (firmware upload happens here, outside the watchdog), then enters the Kali
# chroot to put wlan1 into monitor mode.
#
# Run once per session as root (or via the Magisk boot script):
#   nohup sh /data/data/com.termux/files/home/alfa-watch.sh \
#     >/data/data/com.termux/files/home/alfa-watch.log 2>&1 &
# Stop:  pkill -f alfa-watch.sh
# Log:   cat /data/data/com.termux/files/home/alfa-watch.log

MODDIR=/data/data/com.termux/files/home/modules
FWDIR=/data/local/tmp/fw
HOME_FW=/data/data/com.termux/files/home
USB_ID="0e8d:7612"
DRV=/sys/bus/usb/drivers/mt76x2u
CHROOT_BIN=/data/data/com.termux/files/usr/bin/chroot
ROOTFS=/data/local/nhsystem/kali-arm64
IW=/usr/sbin/iw            # path INSIDE the chroot

log() { echo "$(date '+%H:%M:%S') $*"; }

[ "$(id -u)" = "0" ] || { log "ERROR: must run as root"; exit 1; }
[ -f "$MODDIR/mt76x2u.ko" ] || { log "ERROR: modules missing in $MODDIR"; exit 1; }

stage_fw() {
  mkdir -p "$FWDIR"
  for f in mt7662.bin mt7662_rom_patch.bin; do
    [ -f "$FWDIR/$f" ] && continue
    if [ -f "$HOME_FW/$f" ]; then cp "$HOME_FW/$f" "$FWDIR/$f"
    else log "ERROR: $f missing in $FWDIR and $HOME_FW"; return 1; fi
  done
  chmod 644 "$FWDIR"/mt7662.bin "$FWDIR"/mt7662_rom_patch.bin
  chcon u:object_r:vendor_file:s0 "$FWDIR"/mt7662.bin "$FWDIR"/mt7662_rom_patch.bin 2>/dev/null
  echo "$FWDIR" > /sys/module/firmware_class/parameters/path
}

find_card() {
  for d in /sys/bus/usb/devices/*/idProduct; do
    dir=$(dirname "$d"); [ -f "$dir/idVendor" ] || continue
    [ "$(cat "$dir/idVendor"):$(cat "$d")" = "$USB_ID" ] && { basename "$dir"; return 0; }
  done
  return 1
}

load_stack() {
  echo 0 > /sys/bus/usb/drivers_autoprobe        # gate off: init won't touch HW
  ins() {
    n=$(basename "$1" .ko); ln=$(echo "$n" | tr '-' '_')
    lsmod | grep -q "^$ln " && { log "  $n already loaded"; return 0; }
    insmod "$MODDIR/$1" && log "  $n loaded" || { log "  ERROR $n"; return 1; }
  }
  log "Loading modules (autoprobe off)..."
  ins mac80211.ko && ins mt76.ko && ins mt76-usb.ko && \
  ins mt76x02-lib.ko && ins mt76x02-usb.ko && \
  ins mt76x2-common.ko && ins mt76x2u.ko || { echo 1 > /sys/bus/usb/drivers_autoprobe; return 1; }
  echo 1 > /sys/bus/usb/drivers_autoprobe        # restore for other devices

  iface="${1}:1.0"
  if [ -e "$DRV" ] && [ ! -e "$DRV/$iface" ]; then
    log "Binding $iface (firmware upload)..."
    echo "$iface" > "$DRV/bind" 2>/dev/null
  fi
  return 0
}

set_monitor() {
  # run iw inside the Kali chroot; /proc /sys /dev are already mounted by NH
  if [ ! -x "$CHROOT_BIN" ] || [ ! -e "$ROOTFS$IW" ]; then
    log "[i] chroot/iw not found; set monitor manually inside NetHunter:"
    log "    iw dev wlan1 set type monitor && ip link set wlan1 up"
    return 1
  fi
  ip link set wlan1 down 2>/dev/null
  "$CHROOT_BIN" "$ROOTFS" "$IW" dev wlan1 set type monitor 2>/dev/null
  ip link set wlan1 up 2>/dev/null
  mode=$("$CHROOT_BIN" "$ROOTFS" "$IW" dev wlan1 info 2>/dev/null | grep -o 'type monitor')
  if [ "$mode" = "type monitor" ]; then
    log "[OK] wlan1 is UP in MONITOR mode."
  else
    log "[!] monitor mode not confirmed; check: iw dev wlan1 info"
  fi
}

# Force a clean USB re-enumeration of the adapter. On a busy boot (or marginal
# OTG power) the firmware upload can time out (-110) and probe fails (-5); a full
# unbind/rebind of the USB device recovers it faster than waiting for the next
# watch cycle. $1 = usb device id like "1-1".
usb_reset() {
  ud="$1"
  if [ -e "/sys/bus/usb/devices/$ud" ]; then
    log "  USB reset ($ud): unbind/rebind to recover firmware upload"
    echo "$ud" > /sys/bus/usb/drivers/usb/unbind 2>/dev/null
    sleep 2
    echo "$ud" > /sys/bus/usb/drivers/usb/bind   2>/dev/null
    sleep 3
  fi
}

# bring the card fully up: load stack if needed, wait for wlan1, set monitor
bring_up() {
  dev="$1"
  # already up? just (re)assert monitor
  if ip link show wlan1 >/dev/null 2>&1; then set_monitor; return 0; fi

  stage_fw
  load_stack "$dev" || return 1

  # try up to 3 times: wait for wlan1; if it doesn't show, the firmware upload
  # likely timed out (-110) - force a USB re-enumeration and retry.
  attempt=1
  while [ $attempt -le 3 ]; do
    i=0
    while [ $i -lt 12 ]; do ip link show wlan1 >/dev/null 2>&1 && break; sleep 1; i=$((i+1)); done
    if ip link show wlan1 >/dev/null 2>&1; then
      set_monitor; return 0
    fi
    log "[!] wlan1 not up (attempt $attempt/3) - firmware upload may have timed out"
    usb_reset "$dev"
    # the card re-enumerates at the same id; module is loaded, so just rebind
    if [ -e "$DRV" ] && [ ! -e "$DRV/${dev}:1.0" ]; then
      echo "${dev}:1.0" > "$DRV/bind" 2>/dev/null
    fi
    attempt=$((attempt+1))
  done

  log "[!] wlan1 did not appear after 3 tries. Check: dmesg | grep -iE 'mt76|firmware'"
  log "    If you see 'firmware upload failed: -110', it's a USB timeout — try a"
  log "    POWERED OTG hub (the adapter draws more current than OTG alone gives)."
  return 1
}

stage_fw
log "Watching for Alfa card ($USB_ID)..."
ACTIVE=0

while true; do
  if dev=$(find_card); then
    if [ "$ACTIVE" = "0" ]; then
      log "Card detected at $dev"
      bring_up "$dev" && ACTIVE=1
    fi
  else
    [ "$ACTIVE" = "1" ] && { log "Card removed."; ACTIVE=0; }
  fi
  sleep 2
done
