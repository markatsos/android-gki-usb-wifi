# v3.0 — Magisk/KernelSU module, auto monitor mode, generic naming

Biggest usability jump so far: install by flashing one zip, and `wlan1` comes up
in monitor mode on its own.

## New

- **Flashable module for Magisk / KernelSU / APatch.** The build artifact *is*
  the module zip — no extracting. Flash it, reboot, plug the adapter in.
  It loads the driver stack safely (USB autoprobe off → sysfs bind, so the
  vendor watchdog can't panic), stages firmware, and sets monitor mode.
- **Action button** in the root manager: toggles `wlan1` monitor ↔ managed and
  remembers the choice for next boot. (Magisk v27+ / KernelSU / APatch.)
- **Automatic monitor mode** — a background watcher waits for `wlan1` and the
  Kali chroot, then enables monitor without you doing anything.
- **Compatibility reports made easy** — `detect.sh`/`install.sh`/the Action
  button can open a GitHub form **pre-filled** with your kernel and adapter.
  Nothing is uploaded automatically and no token is ever required.
  See [COMPATIBILITY.md](COMPATIBILITY.md).
- **CLEAN-REINSTALL.md** — wipe everything this project installed and start over.

## Changed

- **Scripts renamed to neutral names** (`alfa-*` → `usbwifi-*`): the project
  supports MediaTek, Ralink, Atheros and Realtek, so a brand name in the
  filenames was misleading. `install.sh` migrates old installs automatically
  (removes the old scripts/boot entry, moves the kill-switch to
  `/data/adb/usbwifi-disable`).
- Kernel-source and toolchain downloads now retry and force HTTP/1.1
  (googlesource intermittently drops HTTP/2 streams mid-transfer).

## Fixed

- `service.sh` skipped the monitor-mode step entirely when no adapter was
  attached at boot — the normal case. It now keeps waiting in the background.
- CI didn't check out the repo, so the module packaging templates were missing.

## Notes

- Prebuilt modules in this release are for the **reference kernel**
  (`5.15.178-android13-8-…-g4ea0fcb5d130-ab13530115`, Teclast P30T / Unisoc
  UMS9230). On any other kernel the CRC won't match — run `detect.sh` and build
  your own; the workflow does it in ~35 min.
- Only the MT7612U path is hardware-verified. Other drivers build correctly but
  aren't confirmed on real hardware yet — reports welcome.
