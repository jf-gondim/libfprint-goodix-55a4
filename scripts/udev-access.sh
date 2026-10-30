#!/usr/bin/env bash
# Grant or revoke the logged-in user's access to the sensor (root).
#   sudo bash scripts/udev-access.sh grant
#   sudo bash scripts/udev-access.sh revoke
set -e
RULE="/etc/udev/rules.d/70-goodix55a4.rules"
HERE="$(cd "$(dirname "$0")" && pwd)"

case "${1:-}" in
grant)  install -m0644 "$HERE/70-goodix55a4.rules" "$RULE" ;;
revoke) rm -f "$RULE" ;;
*)      echo "usage: $0 grant|revoke" >&2; exit 2 ;;
esac
udevadm control --reload
udevadm trigger --subsystem-match=usb --attr-match=idVendor=27c6 --attr-match=idProduct=55a4
udevadm settle
