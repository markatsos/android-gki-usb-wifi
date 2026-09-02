#!/system/bin/sh
# report.sh - offer to send a compatibility report (opt-in, no credentials).
#
# Collects what we already know (kernel, adapter, driver, result), shows it to
# you, asks Y/n, and on "yes" opens the GitHub issue form in your browser with
# the fields PRE-FILLED. You still press Submit yourself — nothing is uploaded
# automatically and no token is ever needed.
#
#   su
#   sh report.sh
#
# Called at the end of install.sh too (you can always answer "n").

REPO="${REPO:-markatsos/android-gki-usb-wifi}"
HOME_DIR=/data/data/com.termux/files/home
PROFILE=""
for c in ./device-profile.txt "$HOME_DIR/device-profile.txt"; do
  [ -f "$c" ] && PROFILE="$c" && break
done

get() { [ -n "$PROFILE" ] && grep "^$1=" "$PROFILE" 2>/dev/null | cut -d= -f2- ; }

KREL="$(uname -r)"
USBID="$(get USB_ID)"
CHIP="$(get CHIPSET)"
DRV="$(get DRIVER)"

# result: derive from the current state
if ip link show wlan1 >/dev/null 2>&1; then
  if ip link show wlan1 2>/dev/null | grep -q radiotap; then
    RESULT="Working — monitor mode confirmed"
  else
    RESULT="Partial — interface up, monitor not confirmed"
  fi
else
  RESULT="Failed — wlan1 did not appear"
fi

echo ""
echo "=== Compatibility report ==="
echo "This helps others with the same device skip the guesswork."
echo "Nothing is sent automatically — a browser opens with a pre-filled form"
echo "and you decide whether to submit."
echo ""
echo "  kernel : $KREL"
echo "  adapter: ${USBID:-unknown} ${CHIP:-}"
echo "  driver : ${DRV:-unknown}"
echo "  result : $RESULT"
echo "  (device model is NOT auto-detected — you'll type it in the form)"
echo ""
printf "Open the pre-filled report form now? [Y/n] "
read ans
case "$ans" in
  n|N|no|NO) echo "Skipped. You can run 'sh report.sh' any time."; exit 0 ;;
esac

enc() { printf '%s' "$1" | sed -e 's|%|%25|g' -e 's| |%20|g' -e 's|/|%2F|g' \
        -e 's|(|%28|g' -e 's|)|%29|g' -e 's|:|%3A|g' -e 's|&|%26|g' \
        -e 's|+|%2B|g' -e 's|#|%23|g' -e 's|,|%2C|g' -e 's|—|-|g'; }

URL="https://github.com/$REPO/issues/new?template=compatibility.yml"
URL="$URL&kernel=$(enc "$KREL")"
URL="$URL&adapter=$(enc "${USBID:-unknown} ${CHIP:-}")"
[ -n "$DRV" ] && URL="$URL&driver=$(enc "$DRV")"

echo ""
echo "Opening:"
echo "$URL"
echo ""
am start -a android.intent.action.VIEW -d "$URL" >/dev/null 2>&1 \
  && echo "Browser opened — review the form, paste your detect.sh output, submit." \
  || { echo "Couldn't open a browser automatically."; echo "Copy the URL above into your browser."; }
