#!/system/bin/sh
# usbwifi-up.sh — Load MT7612U (AWUS036ACM) stack on Teclast P30T (UMS9230)
# Run as root AFTER a reboot. See the warning about card order below.
#
# Usage:
#   su
#   sh /data/local/tmp/usbwifi-up.sh
#
# IMPORTANT: unplug the USB Wi-Fi adapter before running this. The script loads the
# modules first (fast), then tells you to plug the card in. Loading with the
# card already attached triggers the vendor watchdog (native_hang_monitor)
# and panics the kernel.

MODDIR=/data/data/com.termux/files/home/modules
FWDIR=/data/local/tmp/fw
HOME_FW=/data/data/com.termux/files/home

# --- sanity checks ---------------------------------------------------------
if [ "$(id -u)" != "0" ]; then
  echo "ERROR: run me as root (su first)."
  exit 1
fi

if [ ! -f "$MODDIR/mt76x2u.ko" ]; then
  echo "ERROR: modules not found in $MODDIR"
  exit 1
fi

# --- firmware staging ------------------------------------------------------
# Firmware lives in /data/local/tmp/fw with vendor_file SELinux label so the
# kernel firmware loader can read it. Re-stage every boot (tmp may be wiped).
mkdir -p "$FWDIR"
for f in mt7662.bin mt7662_rom_patch.bin; do
  if [ ! -f "$FWDIR/$f" ]; then
    if [ -f "$HOME_FW/$f" ]; then
      cp "$HOME_FW/$f" "$FWDIR/$f"
    else
      echo "ERROR: $f not found in $FWDIR or $HOME_FW"
      exit 1
    fi
  fi
done
chmod 644 "$FWDIR"/mt7662.bin "$FWDIR"/mt7662_rom_patch.bin
chcon u:object_r:vendor_file:s0 "$FWDIR"/mt7662.bin "$FWDIR"/mt7662_rom_patch.bin
echo "$FWDIR" > /sys/module/firmware_class/parameters/path
echo "[*] Firmware staged at $FWDIR"

# --- load stack (order matters) --------------------------------------------
# Skip any module that's already loaded, so re-running is safe.
load() {
  name=$(basename "$1" .ko)
  # module names use underscores in lsmod
  lsname=$(echo "$name" | tr '-' '_')
  if lsmod | grep -q "^$lsname "; then
    echo "    $name already loaded"
  else
    insmod "$MODDIR/$1" && echo "    $name loaded" || {
      echo "ERROR loading $name"; exit 1; }
  fi
}

echo "[*] Loading modules..."
load mac80211.ko
load mt76.ko
load mt76-usb.ko
load mt76x02-lib.ko
load mt76x02-usb.ko
load mt76x2-common.ko
load mt76x2u.ko

echo ""
echo "[✓] Stack loaded. NOW PLUG IN THE ALFA CARD."
echo "    Waiting for wlan1 to appear (up to 30s)..."

# --- wait for the interface ------------------------------------------------
i=0
while [ $i -lt 30 ]; do
  if ip link show wlan1 >/dev/null 2>&1; then
    echo "[✓] wlan1 detected."
    break
  fi
  sleep 1
  i=$((i+1))
done

if ! ip link show wlan1 >/dev/null 2>&1; then
  echo "[!] wlan1 did not appear. Check: dmesg | grep -iE 'mt76|firmware'"
  exit 1
fi

# --- monitor mode ----------------------------------------------------------
# 'iw' lives in the Kali chroot, not the Android shell. If it's missing here,
# the script sets the interface up and you finish inside NetHunter:
#     iw dev wlan1 set type monitor ; ip link set wlan1 up
if command -v iw >/dev/null 2>&1; then
  ip link set wlan1 down
  iw dev wlan1 set type monitor
  ip link set wlan1 up
  echo "[✓] wlan1 is UP in monitor mode:"
  iw dev wlan1 info | sed -n '1,8p'
else
  ip link set wlan1 up
  echo "[i] 'iw' not in this shell (it's in the Kali chroot)."
  echo "    wlan1 is up. Finish inside NetHunter with:"
  echo "        iw dev wlan1 set type monitor && ip link set wlan1 up"
fi
