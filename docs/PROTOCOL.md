# Pressplay NOVA V4 HID configuration protocol

Recovered from the official Windows driver installer (`NOVA V4.exe`) and checked against a real mouse. The driver's files are PressPlay's and aren't included in this repository. Addresses below (`0x4…`) refer to its program `GamingMS.exe`.

| Source | Identity | How it was read |
|---|---|---|
| `GamingMS.exe` from the installer | native MFC, PE32 x86, SHA-256 `8810378c91dec50e2c7dceb2a1d2c81a3ee2fb3e6da57b9e29ea36ed4f3a5309` | [REA](https://rea.tools) (PE imports), Ghidra 12.2 headless decompilation, `objdump` |
| `config/*.psf` from the installer | UTF-16 profile files | default key, DPI and lighting values |
| The mouse (USB `248A:5B2E`, "USB Gaming Mouse", vendor "DA TECH") | status reply `… 'M2982' … 11 …` | `novav4ctl status` / `--trace` |

**Confidence levels:** *observed* means confirmed on the device; *code* means read from the decompiled driver; *inferred* means matched by position or name only.

## Transport

* VID `0x248A`. PID `0x5B2E` is the wired mouse (observed). PID `0x5B2F` is also accepted by the driver and is probably the receiver (code).
* The driver uses the HID interface whose feature report is **33 bytes** (check at 0x4354ee). On macOS that's usage `0001:0006`. The descriptor declares vendor collection `FF00:0001`, feature report ID `0x0C`, 32 data bytes.
* Writes use `HidD_SetFeature`, followed by `Sleep(60)`. Reads are `HidD_SetFeature(0x20)`, then `Sleep(10)`, then `HidD_GetFeature` (0x43a670). The read is retried once if byte 2 is 0.
* No Input Monitoring permission was needed on this Mac (observed).

## Frame (33 bytes)

| Offset | Field |
|---|---|
| 0 | `0x0C` report ID |
| 1 | `0x01` (set to 0 only when both the wired and receiver handles are open) |
| 2 | command |
| 3 | 0 |
| 4 | sequence counter (+1 per frame) |
| 5 | `0x01`. For `0x0E` it's `chunk << 4 \| total`; for `0x20` it's 0 |
| 6 | data length |
| 7… | data, zero padded |

## Commands

| Cmd | Data | Notes |
|---|---|---|
| 0x04 | `slot, b0, b1, b2` | Button function. Profile keys 3 and 4 are swapped when sent, so slot 3 is back and slot 4 is forward (code) |
| 0x05 | 18 bytes: `count \| (active+1)<<4, enabledMask, 8 × code(lo,hi)` | DPI stages. The driver fills only 5 codes; this app fills all 8. Echoed in status byte 0x10 (observed) |
| 0x06 | 24 bytes: 8 × `R,G,B` | DPI stage colours |
| 0x07 | `code` | Polling rate: 8 = 125 Hz, 4 = 250, 2 = 500, 1 = 1000. Echoed in status byte 0x11 (observed) |
| 0x08 | `mode, brightness<<4 \| speed, …` | Lighting, see below |
| 0x09 | `1` or `2` | Lift-off distance in mm (code: profile value 1 → 1, otherwise 2) |
| 0x0A | `ms` | Debounce (UI shows `%dms` = slider position × 2) |
| 0x0B | `minutes, flag` | Power manager. Sleep time; the flag is probably "lights off while moving" (inferred) |
| 0x0C | `flag` | Probably "motion wake-up" (inferred) |
| 0x0E | macro chunks | Not implemented |
| 0x0F | `0xFF` | Sent by "Restore" (code); not used by the macOS app |
| 0x20 | — | Status query, reply described below |

### DPI codes (PAW3311)

The driver builds one table per sensor at 0x40d580. For sensor code `0x11` it has 120 entries, value `2(i+1)` in units of 50 DPI, code `i+1`. So **code = DPI / 100, range 100–12000**. Tables for other sensors aren't implemented.

### Lighting (`0x08`)

| Mode | Name (Lan_En order) | Extra bytes |
|---|---|---|
| 0 | off | — |
| 1 | colourful streaming | direction (0/1) |
| 2 | breathing | `n`, then n × RGB (n ≤ 7, selected non-black colours) |
| 3 | steady | RGB |
| 4, 5, 8, 9 | neon, tail, tailing, wave | — |
| 6 | colourful steady | 7 × RGB (black if not selected) |
| 7 | flicker | 2 × RGB |

Brightness and speed are 1-based nibbles (profile index + 1). Mode names are matched to mode numbers by list order (inferred). The upper limit of the levels isn't known; the app offers 1–5.

### Button functions

The confirmed codes come from the default profiles:

* `10 01 00` left, `10 02 00` right, `10 04 00` middle, `10 08 00` back, `10 10 00` forward
* `40 01 00` DPI cycle
* `90 …` macro (code)

Codes for the other menu entries (DPI ±, fire key, media keys, shortcuts, disable) are built at runtime from list items and weren't recovered.

### Status reply (`0x20`)

| Offset | Meaning |
|---|---|
| 2, 3 | `0x20`, `0x00` |
| 8–12 | `"M2982"` (the driver checks `"M298"`) |
| 0x0F | sensor code (`0x11` = PAW3311) |
| 0x10 | last DPI header (observed) |
| 0x11 | polling-rate code (observed) |
| 0x12 | battery % |
| 0x13 | 1 = charging, 2 = full (shown as 100 %) |
| 0x15 | mouse reachable (used for the receiver) |

## Unknowns

* Codes for keyboard shortcuts, media keys, DPI ±, fire key and disable, plus the macro format details.
* What the 64-byte vendor interface (`FFEF:0000`) is for; it also answers `0x20`.
* Behaviour through the receiver (`0x5B2F`) hasn't been tested.
