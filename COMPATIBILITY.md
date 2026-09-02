# Compatibility

Confirmed device + adapter combos, from testing and community
[compatibility reports](../../issues/new?template=compatibility.yml).

**Legend:** ✅ working · 🟡 partial · ❌ failed · (blank) untested

## Devices

| Device | SoC | Kernel string | Status | Prebuilt modules | Reporter |
|---|---|---|---|---|---|
| Teclast P30T | Unisoc UMS9230 (T615) | `5.15.178-android13-8-…-g4ea0fcb5d130-ab13530115` | ✅ | [release](../../releases/latest) | @markatsos |

## Adapters (on a confirmed device)

| Adapter | Chipset | USB ID | Driver | Status | Notes |
|---|---|---|---|---|---|
| ALFA AWUS036ACM | MT7612U | `0e8d:7612` | mt76x2u | ✅ | monitor + scan confirmed on P30T |

---

## About the "Prebuilt modules" column

Modules only load on a kernel whose **`module_layout` CRC matches** the one they
were built against. In practice that means the **exact same kernel string** —
same ACK commit, same build. If your `uname -r` matches a row above **exactly**,
that row's prebuilt modules should load on your device too; otherwise you need
to build your own (the workflow does it in ~35 min).

Links in that column point to the **reporter's own** release. Treat third-party
kernel modules with the same caution as any code that runs in kernel space:
prefer building your own from the workflow, and only use someone else's binaries
if you trust the source.

## Add your device

Run `scripts/detect.sh` — at the end it prints a **pre-filled issue link** with
your kernel and adapter already in it. Nothing is sent automatically; you open
the link, review it, and submit. Confirmed combos get added to the tables above.
