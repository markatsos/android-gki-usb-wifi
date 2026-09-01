#!/system/bin/sh
# install.sh - Fetch built modules from your GitHub Actions run, download the
# right firmware, and set up the plug-and-play loader on the device.
#
# Run as root in Termux (needs curl + unzip: pkg install curl unzip):
#   su
#   sh install.sh <github-user>/<repo>
#
# It:
#   1. downloads the latest successful "wifi-modules" artifact from your repo
#      (public repos only; for private, set GH_TOKEN env var)
#   2. reads device-profile.txt (from detect.sh) to know which firmware to grab
#   3. fetches firmware from linux-firmware
#   4. installs alfa-watch.sh + alfa-boot.sh (Magisk) for auto monitor mode
#
# It does NOT flash anything and keeps a kill-switch for the boot script.

REPO="$1"
[ -n "$REPO" ] || { echo "usage: sh install.sh <user>/<repo>"; exit 1; }

HOME_DIR=/data/data/com.termux/files/home
MODDIR="$HOME_DIR/mt76"
PROFILE="$HOME_DIR/device-profile.txt"
[ -f ./device-profile.txt ] && PROFILE=./device-profile.txt

# curl/unzip may be Termux-only
for p in /data/data/com.termux/files/usr/bin; do
  case ":$PATH:" in *":$p:"*) ;; *) [ -d "$p" ] && PATH="$PATH:$p";; esac
done
export PATH
have() { command -v "$1" >/dev/null 2>&1; }
have curl  || { echo "need curl: pkg install curl"; exit 1; }
have unzip || { echo "need unzip: pkg install unzip"; exit 1; }

AUTH=""
[ -n "$GH_TOKEN" ] && AUTH="-H \"Authorization: Bearer $GH_TOKEN\""

echo "[*] Finding latest successful build in $REPO ..."
# get the most recent successful run of any workflow that produced artifacts
RUNS_JSON=$(curl -s ${GH_TOKEN:+-H "Authorization: Bearer $GH_TOKEN"} \
  "https://api.github.com/repos/$REPO/actions/artifacts?per_page=20")

# pick the newest artifact named wifi-modules or mt76-modules
ART_URL=$(printf '%s' "$RUNS_JSON" | tr ',' '\n' \
  | grep -A3 -E '"name": *"(wifi|mt76)-modules"' \
  | grep archive_download_url | head -1 \
  | sed -E 's/.*"(https:[^"]+)".*/\1/')

if [ -z "$ART_URL" ]; then
  echo "[!] No wifi-modules/mt76-modules artifact found."
  echo "    Run the build workflow first, and make sure it finished successfully."
  exit 1
fi

echo "[*] Downloading modules artifact ..."
mkdir -p "$MODDIR"
cd "$MODDIR" || exit 1
curl -sL ${GH_TOKEN:+-H "Authorization: Bearer $GH_TOKEN"} "$ART_URL" -o mods.zip
unzip -o mods.zip >/dev/null && rm -f mods.zip
# never deploy a built cfg80211 - stock one must stay
rm -f cfg80211.ko
echo "[*] Modules in $MODDIR:"; ls -1 "$MODDIR"/*.ko

# ---- firmware ------------------------------------------------------------
FW_LIST=""
if [ -f "$PROFILE" ]; then
  FW_LIST=$(grep '^FIRMWARE=' "$PROFILE" | cut -d= -f2)
  DRIVER=$(grep '^DRIVER=' "$PROFILE" | cut -d= -f2)
fi
# fallback to MT7612U if profile missing/empty
[ -z "$FW_LIST" ] || [ "$FW_LIST" = "unknown" ] && FW_LIST="mt7662.bin,mt7662_rom_patch.bin"

LF="https://gitlab.com/kernel-firmware/linux-firmware/-/raw/main/mediatek"
echo "[*] Fetching firmware: $FW_LIST"
OLD_IFS=$IFS; IFS=','
for f in $FW_LIST; do
  [ "$f" = "none(in-driver)" ] && continue
  [ "$f" = "none" ] && continue
  # ath9k firmware lives elsewhere; handle the common mediatek case here
  case "$f" in
    mt76*) url="$LF/$f" ;;
    htc_9271*) url="https://gitlab.com/kernel-firmware/linux-firmware/-/raw/main/ath9k_htc/$f" ;;
    *) url="$LF/$f" ;;
  esac
  echo "    - $f"
  curl -sL "$url" -o "$HOME_DIR/$f"
done
IFS=$OLD_IFS

# ---- scripts -------------------------------------------------------------
echo "[*] Installing loader scripts ..."
# fetch alfa-watch.sh and alfa-boot.sh from the same repo (raw)
RAW="https://raw.githubusercontent.com/$REPO/main/scripts"
curl -sL "$RAW/alfa-watch.sh" -o "$HOME_DIR/alfa-watch.sh"
chmod +x "$HOME_DIR/alfa-watch.sh"

if [ -d /data/adb/service.d ]; then
  curl -sL "$RAW/alfa-boot.sh" -o /data/adb/service.d/alfa-boot.sh
  chmod 755 /data/adb/service.d/alfa-boot.sh
  echo "[*] Boot auto-start installed (Magisk service.d)."
  echo "    Kill-switch: touch /data/adb/alfa-disable   (rm to re-enable)"
else
  echo "[i] /data/adb/service.d not found - skipping boot auto-start."
  echo "    Start manually: nohup sh $HOME_DIR/alfa-watch.sh >$HOME_DIR/alfa-watch.log 2>&1 &"
fi

echo ""
echo "[OK] Done. Start the watcher now (or reboot):"
echo "     nohup sh $HOME_DIR/alfa-watch.sh >$HOME_DIR/alfa-watch.log 2>&1 &"
echo "     then plug in the adapter."
