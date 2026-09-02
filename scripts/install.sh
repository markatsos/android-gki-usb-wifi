#!/system/bin/sh
# install.sh - Set up MT7612U (or other) USB Wi-Fi on a rooted device.
#
# Simple architecture: no GitHub API, no tokens.
#   - modules (.ko) come from a RELEASE ASSET zip (plain curl download)
#   - scripts come from the repo you already `git clone`d (or are fetched raw)
#   - firmware comes from linux-firmware
#
# Run as root in Termux (needs curl + unzip):
#   su
#   sh install.sh
#
# Optional overrides (env vars):
#   REPO=user/repo         (default: markatsos/android-gki-usb-wifi)
#   TAG=v3.0               (release tag holding the modules zip)
#   MODS_ZIP=name.zip      (asset filename; default modules.zip)
#   PROFILE=path           (device-profile.txt from detect.sh)

REPO="${REPO:-markatsos/android-gki-usb-wifi}"
TAG="${TAG:-v3.0}"
MODS_ZIP="${MODS_ZIP:-modules.zip}"

HOME_DIR=/data/data/com.termux/files/home
MODDIR="$HOME_DIR/modules"

# find profile
if [ -z "$PROFILE" ]; then
  for c in ./device-profile.txt "$HOME_DIR/device-profile.txt"; do
    [ -f "$c" ] && PROFILE="$c" && break
  done
fi

# curl/unzip may be Termux-only
for p in /data/data/com.termux/files/usr/bin; do
  case ":$PATH:" in *":$p:"*) ;; *) [ -d "$p" ] && PATH="$PATH:$p";; esac
done
export PATH
have() { command -v "$1" >/dev/null 2>&1; }
have curl  || { echo "need curl:  pkg install curl";  exit 1; }
have unzip || { echo "need unzip: pkg install unzip"; exit 1; }
[ "$(id -u)" = "0" ] || { echo "run as root (su)"; exit 1; }

# --- migrate from older layout (v1.x used ~/mt76) --------------------------
# Old installs kept modules in ~/mt76 and may have left a boot script pointing
# there. Clean that up so this (v2.x, ~/modules) install is authoritative.
OLD_MOD="$HOME_DIR/mt76"
if [ -d "$OLD_MOD" ] && [ "$OLD_MOD" != "$MODDIR" ]; then
  echo "[*] Migrating: removing old module dir $OLD_MOD"
  rm -rf "$OLD_MOD"
fi
# v2.x used alfa-* script names; v3 uses generic usbwifi-*. Remove the old ones
# (and the old boot script) so two loaders can't fight over the same device.
for old in "$HOME_DIR/alfa-watch.sh" "$HOME_DIR/alfa-up.sh" "$HOME_DIR/alfa-watch.log"; do
  [ -e "$old" ] && { echo "[*] Migrating: removing $old"; rm -f "$old"; }
done
if [ -f /data/adb/service.d/alfa-boot.sh ]; then
  echo "[*] Migrating: removing old /data/adb/service.d/alfa-boot.sh"
  rm -f /data/adb/service.d/alfa-boot.sh
fi
# carry over an old kill-switch if the user had one
if [ -f /data/adb/alfa-disable ] && [ ! -f /data/adb/usbwifi-disable ]; then
  mv /data/adb/alfa-disable /data/adb/usbwifi-disable
  echo "[*] Migrating: kill-switch moved to /data/adb/usbwifi-disable"
fi
pkill -f alfa-watch.sh 2>/dev/null
# stop any running watcher so it reloads with the new paths
pkill -f usbwifi-watch.sh 2>/dev/null && echo "[*] Stopped running watcher (will restart with new paths)"

echo "=== install: $REPO @ $TAG ==="

# ---- modules from release asset -----------------------------------------
URL="https://github.com/$REPO/releases/download/$TAG/$MODS_ZIP"
echo "[*] Downloading modules: $URL"
mkdir -p "$MODDIR"; cd "$MODDIR" || exit 1
if ! curl -fsSL "$URL" -o mods.zip; then
  echo "[!] Could not download $MODS_ZIP from release $TAG."
  echo "    Make sure you attached the built modules zip to that release, e.g.:"
  echo "      - build the modules (Actions), download the artifact"
  echo "      - upload it as an asset named $MODS_ZIP on release $TAG"
  exit 1
fi
unzip -o mods.zip >/dev/null && rm -f mods.zip
rm -f cfg80211.ko          # NEVER deploy a custom cfg80211; stock must stay
echo "[*] Modules installed in $MODDIR:"; ls -1 "$MODDIR"/*.ko 2>/dev/null

# ---- firmware ------------------------------------------------------------
FW_LIST=""
if [ -f "$PROFILE" ]; then
  FW_LIST=$(grep '^FIRMWARE=' "$PROFILE" | cut -d= -f2)
fi
case "$FW_LIST" in ""|unknown) FW_LIST="mt7662.bin,mt7662_rom_patch.bin";; esac

LF_MTK="https://gitlab.com/kernel-firmware/linux-firmware/-/raw/main/mediatek"
LF_ATH="https://gitlab.com/kernel-firmware/linux-firmware/-/raw/main/ath9k_htc"
echo "[*] Fetching firmware: $FW_LIST"
OIFS=$IFS; IFS=','
for f in $FW_LIST; do
  case "$f" in
    none*|"") continue;;
    mt76*)     url="$LF_MTK/$f";;
    htc_9271*) url="$LF_ATH/$f";;
    *)         url="$LF_MTK/$f";;
  esac
  echo "    - $f"
  curl -fsSL "$url" -o "$HOME_DIR/$f" || echo "      [!] failed: $f (grab it manually)"
done
IFS=$OIFS

# ---- loader scripts ------------------------------------------------------
# Prefer a local clone; fall back to raw download.
echo "[*] Installing loader scripts ..."
SRC_WATCH=""; SRC_BOOT=""
# Prefer the CURRENT repo checkout. Stop at the first match so a stale old
# clone (e.g. ~/p30t-mt76) can't shadow the fresh scripts. Old repo folder is
# only a last resort.
for base in "." ".." "$HOME_DIR/android-gki-usb-wifi"; do
  if [ -f "$base/scripts/usbwifi-watch.sh" ]; then SRC_WATCH="$base/scripts/usbwifi-watch.sh"; fi
  if [ -f "$base/scripts/usbwifi-boot.sh" ];  then SRC_BOOT="$base/scripts/usbwifi-boot.sh"; fi
  [ -n "$SRC_WATCH" ] && [ -n "$SRC_BOOT" ] && break
done
RAW="https://raw.githubusercontent.com/$REPO/main/scripts"

if [ -n "$SRC_WATCH" ]; then cp "$SRC_WATCH" "$HOME_DIR/usbwifi-watch.sh"
else curl -fsSL "$RAW/usbwifi-watch.sh" -o "$HOME_DIR/usbwifi-watch.sh"; fi
chmod +x "$HOME_DIR/usbwifi-watch.sh"

if [ -d /data/adb/service.d ]; then
  if [ -n "$SRC_BOOT" ]; then cp "$SRC_BOOT" /data/adb/service.d/usbwifi-boot.sh
  else curl -fsSL "$RAW/usbwifi-boot.sh" -o /data/adb/service.d/usbwifi-boot.sh; fi
  chmod 755 /data/adb/service.d/usbwifi-boot.sh
  echo "[*] Boot auto-start installed (Magisk)."
  echo "    Kill-switch: touch /data/adb/usbwifi-disable   (rm to re-enable)"
else
  echo "[i] No Magisk service.d - start the watcher manually (below)."
fi

# --- start the watcher now so it's live immediately -----------------------
echo "[*] Starting watcher..."
pkill -f usbwifi-watch.sh 2>/dev/null
nohup sh "$HOME_DIR/usbwifi-watch.sh" > "$HOME_DIR/usbwifi-watch.log" 2>&1 &
sleep 2

echo ""
echo "[OK] Done. The watcher is running."
echo "     - If the adapter is plugged in, wlan1 should be in monitor mode now:"
echo "         cat $HOME_DIR/usbwifi-watch.log"
echo "     - If not, just plug it in; it loads automatically."
echo ""
# offer the (opt-in) compatibility report
if [ -f "./scripts/report.sh" ]; then sh ./scripts/report.sh
elif [ -f "./report.sh" ];        then sh ./report.sh; fi

echo ""
echo "     NOTE: open the NetHunter app once this session before using airodump/"
echo "     aireplay, so the Kali chroot mounts are active (monitor mode is set"
echo "     via iw inside that chroot)."
