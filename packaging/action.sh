#!/system/bin/sh
# action.sh - runs when you press the "Action" button on this module in
# Magisk Manager (Magisk v27+) or KernelSU. Toggles wlan1 between MONITOR and
# MANAGED, and remembers the choice for next boot.
#
# Output shows up in the app's dialog.

MODDIR="${0%/*}"
AUTOMON="$MODDIR/automonitor"
CHROOT_BIN=/data/data/com.termux/files/usr/bin/chroot
ROOTFS=/data/local/nhsystem/kali-arm64
IW=/usr/sbin/iw

have_chroot() { [ -x "$CHROOT_BIN" ] && [ -e "$ROOTFS$IW" ]; }
iwc() { "$CHROOT_BIN" "$ROOTFS" "$IW" "$@" 2>/dev/null; }

echo "GKI USB Wi-Fi — monitor mode toggle"
echo ""

if ! ip link show wlan1 >/dev/null 2>&1; then
  echo "wlan1 not present."
  echo "Plug the adapter in, wait a few seconds, then press Action again."
  exit 0
fi

if ! have_chroot; then
  echo "Kali chroot / iw not found at:"
  echo "  $ROOTFS$IW"
  echo ""
  echo "Open the NetHunter app once, then press Action again."
  exit 0
fi

cur=$(iwc dev wlan1 info | grep -o 'type [a-z]*' | head -1 | cut -d' ' -f2)
echo "current mode: ${cur:-unknown}"

if [ "$cur" = "monitor" ]; then
  ip link set wlan1 down 2>/dev/null
  iwc dev wlan1 set type managed
  ip link set wlan1 up 2>/dev/null
  echo 0 > "$AUTOMON"
  echo ""
  echo "-> switched to MANAGED (auto-enable on boot: OFF)"
else
  ip link set wlan1 down 2>/dev/null
  iwc dev wlan1 set type monitor
  ip link set wlan1 up 2>/dev/null
  echo 1 > "$AUTOMON"
  echo ""
  echo "-> switched to MONITOR (auto-enable on boot: ON)"
fi

new=$(iwc dev wlan1 info | grep -o 'type [a-z]*' | head -1 | cut -d' ' -f2)
echo "now: ${new:-unknown}"

# --- optional: share that this works on your device -----------------------
# Nothing is sent from here. This just prints (and offers to open) a GitHub
# issue form with your kernel/adapter pre-filled, so others with the same
# device can skip the guesswork.
enc() { printf '%s' "$1" | sed -e 's|%|%25|g' -e 's| |%20|g' -e 's|/|%2F|g' \
        -e 's|(|%28|g' -e 's|)|%29|g' -e 's|:|%3A|g' -e 's|&|%26|g'; }
KREL="$(uname -r)"
ADP="$(cat /sys/bus/usb/devices/*/idVendor 2>/dev/null >/dev/null; echo)"
for d in /sys/bus/usb/devices/*/idProduct; do
  dir=$(dirname "$d"); [ -f "$dir/idVendor" ] || continue
  id="$(cat "$dir/idVendor"):$(cat "$d")"
  case "$id" in 0e8d:*|0bda:*|148f:*|0cf3:*|0846:*) ADP="$id";; esac
done
URL="https://github.com/markatsos/android-gki-usb-wifi/issues/new?template=compatibility.yml&kernel=$(enc "$KREL")&adapter=$(enc "$ADP")"
echo ""
echo "--- share your result (optional) ---"
echo "Opening a pre-filled report form; review it and submit if you want."
am start -a android.intent.action.VIEW -d "$URL" >/dev/null 2>&1 \
  || { echo "Open this manually:"; echo "$URL"; }
