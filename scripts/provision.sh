#!/usr/bin/env bash
# Write the sensor key as the NORMAL user. The Python that does it comes from
# PyPI, so it must not run as root; the user gets access to the sensor through
# the udev rule in scripts/70-goodix55a4.rules (see scripts/udev-access.sh).
#
#   scripts/provision.sh [goodix-fp-dump dir]     default: ./work/goodix-fp-dump
#
# fprintd must not be holding the sensor: `sudo systemctl stop fprintd` first.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PYDIR="${1:-$REPO/work/goodix-fp-dump}"
PYBIN="$PYDIR/.venv/bin/python"

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user, not root." >&2
  exit 1
fi
[ -x "$PYBIN" ] || { echo "no $PYBIN (run ./install.sh or ./setup.sh first)" >&2; exit 1; }

dev="$(lsusb -d 27c6:55a4 2>/dev/null | sed -E 's/Bus ([0-9]+) Device ([0-9]+).*/\1 \2/')"
if [ -n "$dev" ]; then
  # lsusb pads with zeros ("011"); printf would read that as octal (= 9).
  # shellcheck disable=SC2086
  set -- $dev
  node="/dev/bus/usb/$1/$2"
  [ -w "$node" ] || {
    echo "No write access to $node. Install the udev rule first:" >&2
    echo "  sudo bash $REPO/scripts/udev-access.sh grant" >&2
    exit 1
  }
fi

install -m0644 "$REPO/scripts/provision_psk.py" "$PYDIR/"
cd "$PYDIR"
PYTHONDONTWRITEBYTECODE=1 exec "$PYBIN" provision_psk.py
