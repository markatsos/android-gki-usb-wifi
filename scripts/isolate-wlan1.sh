#!/system/bin/sh
# isolate-wlan1.sh - keep Android's Wi-Fi framework from touching wlan1 while you
# capture. OPT-IN. Reverts on reboot. Does NOT kill netd/wificond globally and
# does NOT touch wlan0 (your internal Wi-Fi).
#
#   su
#   sh isolate-wlan1.sh on     # before airodump / long captures
#   sh isolate-wlan1.sh off    # restore
#
# Why: on some Android 12+ builds, wificond/netd try to manage every new wlan
# interface (scans, MAC randomization, power save), which disrupts monitor mode.

IFACE=wlan1
act="$1"
[ "$(id -u)" = "0" ] || { echo "run as root"; exit 1; }

case "$act" in
  on)
    # 1) mark the interface down so the HAL stops managing it, then let iw own it
    ip link set "$IFACE" down 2>/dev/null
    # 2) disable power save (a common cause of capture drops)
    #    (best-effort; needs iw from the chroot if not present here)
    command -v iw >/dev/null 2>&1 && iw dev "$IFACE" set power_save off 2>/dev/null
    # 3) ask wificond to forget it, if the tool is present (non-fatal)
    cmd wifi force-country-code disable >/dev/null 2>&1 || true
    echo "[on] $IFACE released from Android Wi-Fi management (revert: reboot or '$0 off')."
    echo "     Now set monitor mode via the chroot: iw dev $IFACE set type monitor; ip link set $IFACE up"
    ;;
  off)
    ip link set "$IFACE" down 2>/dev/null
    command -v iw >/dev/null 2>&1 && iw dev "$IFACE" set type managed 2>/dev/null
    ip link set "$IFACE" up 2>/dev/null
    echo "[off] $IFACE back to managed."
    ;;
  *)
    echo "usage: $0 on|off"; exit 1 ;;
esac
