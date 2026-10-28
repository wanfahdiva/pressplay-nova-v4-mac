# NOVA V4 for macOS

A native macOS configurator for the PressPlay NOVA V4 gaming mouse (USB `248A:5B2E`, PAW3311 sensor). PressPlay's own software only runs on Windows.

The protocol was recovered from the Windows driver and checked on a real mouse; see [`docs/PROTOCOL.md`](docs/PROTOCOL.md).

> Unofficial project, not affiliated with or endorsed by PressPlay. Use at your own risk.

## Download

Get `NOVA-V4-macOS.zip` from [Releases](../../releases), unzip it and move **NOVA V4.app** to Applications.

The app isn't notarized by Apple. On first launch, right-click it and choose **Open**, then **Open** again. If macOS still blocks it, go to System Settings → Privacy & Security and click **Open Anyway**.

Requires macOS 14 or later on Apple silicon. On an Intel Mac, build it from source.

## Features

* **Overview**: connection, model, sensor, battery, "Write all settings", reset.
* **DPI**: 8 stages from 100 to 12000 DPI (step 100), which stages the DPI button cycles through, the active stage, and a colour per stage.
* **Performance**: polling rate (125–1000 Hz), lift-off distance, debounce, wireless sleep time and power options.
* **Lighting**: off, colourful streaming, breathing, steady, neon, tail, colourful steady, flicker, tailing, wave, plus brightness, speed and colours.
* **Buttons**: left, right, middle, back, forward or DPI cycle on any of the 6 buttons. One button always keeps the left click.

The mouse can't report most of its settings. The app keeps its own copy and sends a group about 0.35 s after you change it. Opening the app sends nothing. Use **Write All Settings to Mouse** to push everything, for example after configuring the mouse on Windows. The active DPI stage and polling rate *are* reported by the mouse, so DPI-button presses show up in the app.

## Bluetooth

Settings can only be changed over the **USB cable** or the **2.4 GHz receiver**, not over Bluetooth. Over Bluetooth the mouse shows up as `248A:8266` and doesn't offer the configuration report the app uses. PressPlay's Windows software doesn't support the Bluetooth connection either.

Settings are stored in the mouse, so set it up once over the cable or receiver and they also apply over Bluetooth. Bluetooth itself limits the polling rate to about 125 Hz.

Each time the mouse is put into pairing mode it uses a new Bluetooth address, so macOS adds another "NOVA v4" entry. Forget the old entry in System Settings → Bluetooth before pairing again. Switching back to Bluetooth mode without re-pairing keeps the existing entry.

## Build from source

Needs the Swift toolchain (Xcode or just the Command Line Tools).

```sh
./scripts/build-app.sh          # -> build/NOVA V4.app, build/novav4ctl
swift run v4kit-selftest        # protocol encoding checks
```

## Command-line tool

```sh
build/novav4ctl list                  # HID interfaces; the config one is marked
build/novav4ctl status                # model, sensor, battery (read-only)
build/novav4ctl rate 1000
build/novav4ctl dpi 2 800 1600 3200   # stages 800/1600/3200, stage 2 active
build/novav4ctl raw 07 01 --trace     # one raw frame, printing the bytes
```

## Not included yet

* Keyboard shortcuts, media keys, DPI ±, fire key, disable and macros. Their codes weren't recovered.
* The Windows app's "Restore" (command `0x0F`).
* Changing settings over Bluetooth (see [Bluetooth](#bluetooth)).

Contributions are welcome, especially button codes captured from the Windows app.

## License

[MIT](LICENSE)
