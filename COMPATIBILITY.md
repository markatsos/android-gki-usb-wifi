# Compatibility

Confirmed device + adapter combos, from testing and community
[compatibility reports](../../issues/new?template=compatibility.yml).

**Legend:** ✅ working · 🟡 partial · ❌ failed · (blank) untested

## Devices

| Device | SoC | Kernel gen | Status | Reporter | Notes |
|---|---|---|---|---|---|
| Teclast P30T | Unisoc UMS9230 (T615) | android13-5.15 | ✅ | @markatsos | reference; MT7612U, monitor+scan, survives reboot |

## Adapters (on a confirmed device)

| Adapter | Chipset | USB ID | Driver | Status | Notes |
|---|---|---|---|---|---|
| ALFA AWUS036ACM | MT7612U | 0e8d:7612 | mt76x2u | ✅ | monitor + scan confirmed on P30T |

---

Want to add a row? Open a
[compatibility report](../../issues/new?template=compatibility.yml) with your
`detect.sh` output — confirmed combos get added here.

If you're not sure whether your device can work, just run `scripts/detect.sh`;
it reads your kernel/config/adapter and prints a yes/no verdict without changing
anything.
