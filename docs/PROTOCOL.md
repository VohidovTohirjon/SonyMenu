# WH-1000XM5 protocol notes (firmware 2.3.1)

Captured from a real WH-1000XM5 with `--dump` and `--selftest` on 2026-11-24. Payload bytes are table 1
(frame type 0x0C) unless marked T2 (frame type 0x0E). Layouts follow libmdr's generated `ProtocolV2T1/T2.hpp`.

## Support list

`06 00` → 33 table-1 functions: codec indicator, power off, auto power off with wearing detection,
battery, general settings 1 and 2, preset EQ, NC dual + ambient level (0x6B), AUTO_NCASM, playback controller,
action log, time-series operation log, connection mode, DSEE (upscaling auto-off), voice assistant settings,
NC/AMB button select, reset settings, SAR / head tracker (spatial audio), auto pause on removal, quick access,
Speak-to-Chat type 2, and others. Table 2: voice guidance, safe listening, quick-access easy setting, link auto switch.

Not in the list: **assignable settings** (so the touch panel's gestures can't be reassigned on the headphones),
pairing-device management (no connected-devices list).

## Reads and writes used by SonyMenu (all verified by `--selftest`)

| Feature | GET | Reply seen | SET |
| --- | --- | --- | --- |
| Model / firmware | `04 01`, `04 02` | `05 01 0a "WH-1000XM5"`, `05 02 05 "2.3.1"` | — |
| Codec | `12 02` | `13 02 02` (AAC) | — |
| NC / ambient | `66 17` | `67 17 01 01 01 00 0a` | `68 17 01 on mode voice level` |
| Left button cycle | `66 30` | `67 30 02` (NC↔AMB) | `68 30 fn` (01 all, 02 NC/AMB, 03 NC/Off, 04 AMB/Off) |
| EQ presets | `50 00 01` | `51 00 06 15 0c` + 12 preset ids | — |
| EQ | `56 00` | `57 00 00 06 0a×6` | `58 00 id 00` (preset), `58 00 a0 06 cb b1…b5` (custom, 10 = 0 dB) |
| DSEE Extreme | `e6 01` | `e7 01 00` | `e8 01 00/01` |
| Connection quality | `e6 00` | `e7 00 00` | `e8 00 00/01` |
| Speak-to-Chat | `f6 0c`, `fa 0c` | `f7 0c 01 01`, `fb 0c 00 01` | `f8 0c on(00)/off(01) 01`, `fc 0c sens time` |
| Pause when removed | `f6 01` | `f7 01 00` | `f8 01 00/01` |
| Touch and hold | `f0 04`, `f6 04` | `f1 04 01 04 30 31 32 ff`, `f7 04 ff` | `f8 04 30/ff` |
| Auto power off | `20 05`, `26 05` | `21 05 02 10 11`, `27 05 10 00` | `28 05 10/11 00` |
| Touch panel (GS1) | `d0 d1 01`, `d6 d1` | `"TOUCH_PANEL_SETTING"`, `d7 d1 00 00` | `d8 d1 00 00/01` |
| Multipoint (GS2) | `d0 d2 01`, `d6 d2` | `"MULTIPOINT_SETTING"`, `d7 d2 00 01` | `d8 d2 00 00/01` (not self-tested: may reconnect) |
| Voice guidance (T2) | `46 01` | `47 01 00 0b` | `48 01 00/01` |
| Volume | `a6 20` | `a7 20 0f` | `a8 20 vol` (0–30) |
| Playback | `a2 01` | `a3 01 00 st 00` | `a4 01 00 ctl` (01 pause, 02 next, 03 prev, 07 play); not self-tested |
| Power off | — | — | `24 03 01` (not self-tested) |

## Gestures

With the time-series log on (`c4 01 00`), every touch arrives as `c9 01 len "name"`:
`keyRDoubleTap`, `keyRRightFlick` (forward), `keyRLeftFlick` (backward), `keyRUpFlick`, `keyRDownFlick`,
`keyRHold`, `keyRTwoFingerHold`, `keyCustomBtn` (left NC/AMB press), `keyCustomBtnHold` (left hold), plus
`unitWear` / `unitRemove`. Some entries use a two-byte length with a trailing zero:
`c9 01 00 len "opPrev" 00`, `opNC`, `opQAStart`, `opQAEnd` (Quick Attention).
The events only come while the headphones are worn. `c4 00 00` (action log) dumps usage counters as JSON instead;
SonyMenu doesn't turn it on.
