#!/usr/bin/env bash
# =====================================================================
# GLYPH C6 Diagnostic
# Tests esptool connectivity with the PCBCupid GLYPH C6 (ESP32-C6)
# and optionally flashes the included blink firmware.
# Works on macOS and Linux. Needs: bash + esptool (or Arduino IDE).
# =====================================================================
set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRMWARE="$SELF_DIR/firmware/glyph-c6-blink.merged.bin"
PORT=""
MODE="auto"          # auto | manual  (how we got the chip into download mode)
ESPTOOL_LOG=""       # full esptool output is saved here

# ----------------------------- colors -----------------------------
if [ -t 1 ]; then
  BOLD=$'\033[1m'
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  CYAN=$'\033[36m'
  RESET=$'\033[0m'
else
  BOLD=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; RESET=""
fi

ok()   { printf '%s✔%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s⚠%s %s\n' "$YELLOW" "$RESET" "$*"; }
bad()  { printf '%s✘%s %s\n' "$RED" "$RESET" "$*"; }
info() { printf '%s•%s %s\n' "$CYAN" "$RESET" "$*"; }

trap 'printf "\n"; bad "Aborted."; exit 130' INT

banner() {
  printf '%s' "$BOLD$CYAN"
  cat <<'EOF'
┌──────────────────────────────────────────────────────────┐
│   GLYPH C6 DIAGNOSTIC · esptool connection test          │
└──────────────────────────────────────────────────────────┘
EOF
  printf '%s' "$RESET"
}

# --------------------------- esptool -------------------------------
# Finds esptool on the PATH, or the copy bundled with Arduino IDE.
find_esptool() {
  local p="" d
  if command -v esptool >/dev/null 2>&1; then
    p="$(command -v esptool)"
  elif command -v esptool.py >/dev/null 2>&1; then
    p="$(command -v esptool.py)"
  else
    for d in "$HOME/Library/Arduino15" "$HOME/.arduino15"; do
      if [ -d "$d/packages/esp32/tools/esptool_py" ]; then
        p="$(ls -d "$d"/packages/esp32/tools/esptool_py/*/esptool 2>/dev/null | head -n1)"
        [ -n "$p" ] && break
      fi
    done
  fi
  ESPTOOL="$p"
}

# ----------------------------- port --------------------------------
# Finds the board's serial port. On macOS the port NUMBER can change
# every time the chip resets (usbmodem1201 -> usbmodem1202 -> ...),
# so this is re-run after every reset dance.
refresh_port() {
  local ports count old="$PORT"
  if [ "$(uname -s)" = "Darwin" ]; then
    ports="$(ls /dev/cu.usbmodem* 2>/dev/null)"
  else
    ports="$(ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null)"
  fi
  if [ -z "$ports" ]; then
    bad "No USB serial port found. Is the board plugged in with a data cable?"
    return 1
  fi
  # keep the same port if it still exists
  if [ -n "$old" ] && printf '%s\n' "$ports" | grep -qx "$old"; then
    return 0
  fi
  count="$(printf '%s\n' "$ports" | wc -l | tr -d ' ')"
  if [ "$count" -eq 1 ]; then
    PORT="$(printf '%s\n' "$ports" | head -n1)"
    info "Port detected: $PORT"
    return 0
  fi
  warn "More than one serial port found — unplug other USB devices, then press Enter."
  printf '%s\n' "$ports" | sed 's/^/    /'
  read -r _
  refresh_port
}

check_busy() {
  if [ "$(uname -s)" = "Darwin" ]; then
    if command -v lsof >/dev/null 2>&1 && lsof "$PORT" >/dev/null 2>&1; then
      warn "$PORT is in use by another program:"
      lsof "$PORT" | tail -n +2 | sed 's/^/    /'
      echo "  Close it (Serial Monitor, screen, ...) and press Enter to continue."
      read -r _
    fi
  else
    if command -v fuser >/dev/null 2>&1 && fuser "$PORT" >/dev/null 2>&1; then
      warn "$PORT is in use by another program:"
      fuser -v "$PORT" 2>&1 | sed 's/^/    /'
      echo "  Close it (Serial Monitor, screen, ...) and press Enter to continue."
      read -r _
    fi
  fi
}

# -------------------------- connecting -----------------------------
# Runs the esptool chip-id test. Extra args (e.g. --before no_reset)
# are passed straight to esptool. Returns esptool's exit status.
connect_test() {
  "$ESPTOOL" --port "$PORT" --chip esp32c6 "$@" "$CMD_CHIP_ID" 2>&1 | tee "$ESPTOOL_LOG"
  return "${PIPESTATUS[0]}"
}

# -------------------------- diagnostics ----------------------------
# Reads the last esptool run from ESPTOOL_LOG and explains the failure
# in plain language instead of leaving the user with raw error text.
analyze_failure() {
  echo ""
  info "What esptool said:"
  grep -E "fatal error|error" "$ESPTOOL_LOG" | tail -3 | sed 's/^/    /'
  echo ""
  if grep -qi "could not open.*port\|no such file\|busy" "$ESPTOOL_LOG"; then
    info "This means: the port couldn't be opened — it vanished, or another program holds it."
    info "Fix: close Serial Monitor / screen sessions, replug the board."
  elif grep -qi "no serial data received\|failed to connect" "$ESPTOOL_LOG"; then
    info "This means: the chip did not answer — it is NOT in download mode, or the port is not the board."
    info "Fix: the BOOT dance, and confirm the port really belongs to the board."
  elif grep -qi "unsupported detection protocol\|unexpected chip" "$ESPTOOL_LOG"; then
    info "This means: the device on this port is NOT an ESP32-C6 (wrong device, or the board isn't enumerating)."
    info "Fix: unplug other USB devices; check cable and board power."
  fi
}

# Checks the USB device tree for an Espressif device (vendor 0x303a).
check_usb_tree() {
  if [ "$(uname -s)" = "Darwin" ]; then
    if system_profiler SPUSBDataType 2>/dev/null | grep -qi "303a"; then
      ok "Espressif device found in the USB tree — the board is enumerating."
    else
      warn "No Espressif (vendor 0x303a) device in the USB tree — the port found above may belong to another device, or the board isn't enumerating (cable/power problem)."
    fi
  else
    if command -v lsusb >/dev/null 2>&1; then
      if lsusb 2>/dev/null | grep -qi "303a"; then
        ok "Espressif device found on the USB bus — the board is enumerating."
      else
        warn "No Espressif (vendor 0x303a) device on the USB bus — the port found above may belong to another device, or the board isn't enumerating (cable/power problem)."
      fi
    fi
  fi
}

# Definitive identity test: if unplugging the board makes the port
# disappear, the port IS the board.
identity_test() {
  local ans now
  echo ""
  info "Identity check — is the port really your board?"
  printf '%sUnplug the boards USB cable now, wait 2 seconds, then press Enter (q = skip): %s' "$YELLOW" "$RESET"
  read -r ans || { echo; return 0; }
  [ "$ans" = "q" ] && return 0
  if [ "$(uname -s)" = "Darwin" ]; then
    now="$(ls /dev/cu.usbmodem* 2>/dev/null)"
  else
    now="$(ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null)"
  fi
  if printf '%s\n' "$now" | grep -qx "$PORT"; then
    bad "The port $PORT is STILL there after unplugging — it is NOT your board."
    warn "Your board is not enumerating. Check: data cable (not charge-only), USB port, board power switch."
    printf '%sPress Enter to continue anyway (q = quit): %s' "$YELLOW" "$RESET"
    read -r ans || { echo; return 0; }
    [ "$ans" = "q" ] && exit 1
  else
    ok "$PORT disappeared when you unplugged — that IS your board."
    printf '%sPlug the board back in, then press Enter: %s' "$YELLOW" "$RESET"
    read -r _ || true
    # wait for the port to come back (the name may have changed)
    local i
    for i in $(seq 1 15); do
      if [ "$(uname -s)" = "Darwin" ]; then
        now="$(ls /dev/cu.usbmodem* 2>/dev/null)"
      else
        now="$(ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null)"
      fi
      printf '%s\n' "$now" | grep -qx "$PORT" && break
      sleep 1
    done
    refresh_port || return 0
  fi
}

dance_prompt() {
  echo ""
  printf '%sBOOT DANCE%s\n' "$BOLD" "$RESET"
  echo "   1. HOLD the BOOT button"
  echo "   2. TAP  the RESET button"
  echo "   3. RELEASE the BOOT button"
  echo "  (This puts the chip into download mode.)"
}

manual_connect() {
  local attempt ans
  for attempt in 1 2 3; do
    printf '%sAttempt %s/3%s\n' "$BOLD" "$attempt" "$RESET"
    dance_prompt
    printf '%sPress Enter when you have done the dance (q = quit): %s' "$YELLOW" "$RESET"
    read -r ans || { echo; return 1; }
    [ "$ans" = "q" ] && return 1
    refresh_port || return 1
    if connect_test --before no_reset; then
      return 0
    fi
    bad "No response from the chip."
    analyze_failure
  done
  return 1
}

nuclear_connect() {
  local ans
  echo ""
  info "Nuclear option — force download mode from power-on:"
  echo "   1. UNPLUG the USB cable"
  echo "   2. HOLD the BOOT button and keep holding"
  echo "   3. PLUG the USB cable back in (still holding BOOT)"
  echo "   4. Wait 2 seconds, then release BOOT"
  printf '%sPress Enter when ready (q = quit): %s' "$YELLOW" "$RESET"
  read -r ans || { echo; return 1; }
  [ "$ans" = "q" ] && return 1
  refresh_port || return 1
  connect_test --before no_reset
}

# ---------------------------- flashing -----------------------------
offer_flash() {
  local ans
  echo ""
  printf '%sFlash the blink firmware now?%s (overwrites whatever is on the board) [Y/n]: ' "$BOLD" "$RESET"
  read -r ans
  case "$ans" in
    ""|y|Y|yes) ;;
    *) info "Skipping flash."; return 0 ;;
  esac
  if [ ! -f "$FIRMWARE" ]; then
    bad "Firmware file not found: $FIRMWARE"
    return 1
  fi
  if [ "$MODE" = "manual" ]; then
    # The chip left download mode after the chip-id test, so re-enter it.
    dance_prompt
    printf '%sPress Enter when you have done the dance (q = quit): %s' "$YELLOW" "$RESET"
    read -r ans
    [ "$ans" = "q" ] && return 1
    refresh_port || return 1
    "$ESPTOOL" --port "$PORT" --chip esp32c6 --baud 460800 --before no_reset "$CMD_WRITE" 0x0 "$FIRMWARE" \
      || { bad "Flash failed."; return 1; }
  else
    "$ESPTOOL" --port "$PORT" --chip esp32c6 --baud 460800 "$CMD_WRITE" 0x0 "$FIRMWARE" \
      || { bad "Flash failed."; return 1; }
  fi
  echo ""
  ok "Flash complete! The board restarted into the blink app."
  info "The onboard LED (GPIO14) should now be blinking."
  info "Open a Serial Monitor at 115200 baud to see 'LED ON / LED OFF'."
  info "If the LED is not blinking, press RESET once."
}

# ------------------------------ main -------------------------------
main() {
  local vline vmajor

  banner
  info "Host: $(uname -s) ($(uname -m))"
  echo ""

  # 1. esptool
  find_esptool
  if [ -z "$ESPTOOL" ]; then
    bad "esptool not found."
    echo "  Install it with:  pip3 install esptool"
    echo "  (or install Arduino IDE — its bundled esptool is detected automatically)"
    exit 1
  fi
  ok "esptool found: $ESPTOOL"
  vline="$("$ESPTOOL" version 2>/dev/null | head -n1)"
  vmajor="$(printf '%s' "$vline" | awk '{print $2}' | tr -cd '0-9' | cut -c1)"
  if [ "$vmajor" = "4" ]; then
    CMD_CHIP_ID="chip_id"; CMD_WRITE="write_flash"    # esptool 4.x names
  else
    CMD_CHIP_ID="chip-id";  CMD_WRITE="write-flash"   # esptool 5.x names
  fi
  info "esptool $vline"
  ESPTOOL_LOG="$(mktemp /tmp/glyph-diag.XXXXXX)"
  info "Full esptool output will be saved to: $ESPTOOL_LOG"

  # 2. port
  echo ""
  info "Looking for the board's serial port…"
  refresh_port || exit 1
  ok "Port: $PORT"
  info "If the onboard LED is blinking right now, this port is definitely your board."
  info "If it's NOT blinking, the chip may be in download mode already — the script can still connect to it."
  check_usb_tree
  identity_test
  check_busy

  # 3. connect
  echo ""
  info "Step 1 — trying esptool's automatic reset…"
  if connect_test; then
    ok "Connected automatically! esptool is talking to the chip."
  else
    warn "Automatic reset did not work — common on macOS and USB hubs, nothing is broken."
    analyze_failure
    MODE="manual"
    if manual_connect; then
      ok "Connected via BOOT dance!"
    else
      echo ""
      warn "BOOT dance got no response either."
      if nuclear_connect; then
        ok "Connected via the power-on trick!"
      else
        analyze_failure
        bad "Still no response. Possible causes:"
        echo "   • the port belongs to a different device (unplug it — if the port disappears, it was the board)"
        echo "   • charge-only cable — swap for a data cable"
        echo "   • USB hub in the way — plug directly into the computer"
        info "Share the full log if you need help: $ESPTOOL_LOG"
        exit 1
      fi
    fi
  fi

  # 4. flash (optional)
  offer_flash

  echo ""
  ok "Diagnostic complete."
}

main
