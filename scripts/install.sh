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
#   TAG=v2.0               (release tag holding the modules zip)
#   MODS_ZIP=name.zip      (asset filename; default mt76-modules.zip)
#   PROFILE=path           (device-profile.txt from detect.sh)

REPO="${REPO:-markatsos/android-gki-usb-wifi}"
TAG="${TAG:-v2.0}"
MODS_ZIP="${MODS_ZIP:-mt76-modules.zip}"

HOME_DIR=/data/data/com.termux/files/home
MODDIR="$HOME_DIR/mt76"

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
for base in "." ".." "$HOME_DIR/android-gki-usb-wifi" "$HOME_DIR/p30t-mt76"; do
  [ -f "$base/scripts/alfa-watch.sh" ] && SRC_WATCH="$base/scripts/alfa-watch.sh"
  [ -f "$base/scripts/alfa-boot.sh" ]  && SRC_BOOT="$base/scripts/alfa-boot.sh"
done
RAW="https://raw.githubusercontent.com/$REPO/main/scripts"

if [ -n "$SRC_WATCH" ]; then cp "$SRC_WATCH" "$HOME_DIR/alfa-watch.sh"
else curl -fsSL "$RAW/alfa-watch.sh" -o "$HOME_DIR/alfa-watch.sh"; fi
chmod +x "$HOME_DIR/alfa-watch.sh"

if [ -d /data/adb/service.d ]; then
  if [ -n "$SRC_BOOT" ]; then cp "$SRC_BOOT" /data/adb/service.d/alfa-boot.sh
  else curl -fsSL "$RAW/alfa-boot.sh" -o /data/adb/service.d/alfa-boot.sh; fi
  chmod 755 /data/adb/service.d/alfa-boot.sh
  echo "[*] Boot auto-start installed (Magisk)."
  echo "    Kill-switch: touch /data/adb/alfa-disable   (rm to re-enable)"
else
  echo "[i] No Magisk service.d - start the watcher manually (below)."
fi

echo ""
echo "[OK] Done. Start it now (or reboot):"
echo "     nohup sh $HOME_DIR/alfa-watch.sh >$HOME_DIR/alfa-watch.log 2>&1 &"
echo "     then plug in the adapter -> wlan1 comes up in monitor mode."
