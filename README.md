# GLYPH C6 Diagnostic

One-script esptool test + blink flasher for the PCBCupid GLYPH C6 (ESP32-C6).
Works on macOS and Linux. No compiling needed — the prebuilt firmware is included.

## Quick start

```bash
git clone <this-repo-url>
cd glyph-c6-diagnostic
./diagnose.sh
```

Answer the prompts. That's it.

## What the script does

1. **Finds esptool** — on your PATH, or the copy bundled with Arduino IDE
   (both `~/Library/Arduino15` on macOS and `~/.arduino15` on Linux are checked)
2. **Finds your board's port** — `/dev/cu.usbmodem*` on macOS, `/dev/ttyACM*` on Linux
3. **Checks the USB tree** for an actual Espressif device (vendor `0x303a`) — if your
   port was made by some other gadget, you'll know
4. **Identity check** — asks you to unplug the board: if the port disappears, it's
   definitely your board
5. **Tries esptool's automatic reset** (works on most Linux/Windows setups)
6. **Explains every failure in plain language** — esptool's error text is translated
   into what's actually wrong and how to fix it ("no serial data received" → not in
   download mode → BOOT dance; "could not open port" → busy/vanished, etc.)
7. **If auto-reset fails, walks you through the BOOT dance** step by step
8. **Flashes the blink firmware** (optional, Y/n prompt)

The full esptool output from the run is saved to a log file (its path is printed)
so it can be pasted into a chat when asking for help.

## The BOOT dance

esptool can only talk to the chip when it is in *download mode*. The
automatic reset doesn't always work (macOS, USB hubs, some cables), so
you may need to enter download mode by hand:

1. **HOLD** the BOOT button
2. **TAP** the RESET button
3. **RELEASE** the BOOT button

Nuclear option (guaranteed download mode):

1. UNPLUG the USB cable
2. HOLD BOOT and keep holding
3. PLUG the USB back in (still holding BOOT)
4. Wait 2 seconds, release BOOT

## Requirements

- esptool: `pip3 install esptool` (or Arduino IDE installed)
- A **data** USB-C cable (not charge-only)
- Plugged **directly** into the computer (no USB hub) if possible

## Rebuilding the firmware from source

```bash
arduino-cli compile --fqbn esp32:esp32:Pcbcupid_GLYPH_C6 blink
```

The merged binary produced by the build is the same file committed in
`firmware/`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Stuck at `Connecting...` | BOOT dance (the script guides you) |
| Stuck at `Connecting...` on macOS | Known quirk: macOS's USB-CDC driver often won't run esptool's auto-reset on the C6's native USB port. Use the BOOT dance — or a Windows/Linux machine (auto-reset works there first try) |
| LED not blinking | Chip may be sitting in download mode from a previous BOOT dance — that's fine, the script can still connect. Tap RESET once to confirm the board still boots normally |
| Port found but never connects | The port may belong to another device — unplug the board: if the port disappears, it was the board |
| No serial port listed | Board not plugged in / charge-only cable / try another cable |
| Port in use / busy error | Close Serial Monitor and any `screen` sessions |
| Port found but never connects | The port may belong to another device — unplug the board: if the port disappears, it was the board |
| LED not blinking after flash | Press RESET once, check USB power |
