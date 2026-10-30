#!/usr/bin/env python3
"""One-time key provisioning for the Goodix 55x4 sensor.

The driver talks to the sensor over TLS-PSK, and the key it uses is all zeros —
the sensor only agrees to that once a fixed, publicly known "whitebox" blob has
been written into it. That blob is not device-specific and not derived from
anyone's hardware; it has shipped in goodix-fp-dump for years. Writing it is a
one-time provisioning step: after that the sensor keeps the setting.

The C driver deliberately does not write keys — it only checks and refuses to
activate if the expected key is absent, which on an untouched sensor looks like
an unexplained activation failure. Hence this step, run once by the installer.

Exit codes:
  0  the sensor already had the key, or it was written successfully
  1  the sensor is unreachable (busy, missing, no permission)
  2  the write was attempted and the sensor still does not report the key
  3  the sensor needs the key and you declined (or no terminal to ask on)

Nothing is written without a "y" typed on the terminal. Scripted installs can
set GOODIX_ASSUME_YES=1 to answer for you.

Note for dual-boot: this writes slot 0xbb010003 only. Windows keeps its own
DPAPI-wrapped key material in slot 0xbb010002, which nothing here touches. It
is expected to re-provision itself if it ever needs to, but that was seen once
on one machine, not tested repeatedly — see the dual-boot note in README.
"""
import os
import sys

try:
    import driver_55x4
except ImportError:
    print("provision_psk: run from the goodix-fp-dump directory", file=sys.stderr)
    sys.exit(1)


def confirmed():
    if os.environ.get("GOODIX_ASSUME_YES") == "1":
        return True
    try:
        # /dev/tty, not stdin: this may run inside a pipeline. Two handles, because
        # "r+" needs a seekable file and a terminal is not one.
        out, inp = open("/dev/tty", "w"), open("/dev/tty", "r")
    except OSError:
        print("  no terminal to ask on; set GOODIX_ASSUME_YES=1 to allow the write",
              file=sys.stderr)
        return False
    with out, inp:
        out.write("  This writes a public, non-device-specific key into slot 0xbb010003\n"
                  "  of the sensor, once. Windows' own slot (0xbb010002) is not touched,\n"
                  "  and uninstalling does not undo it. Write it now? [y/N] ")
        out.flush()
        return inp.readline().strip().lower() in ("y", "yes")


def main():
    try:
        dev = driver_55x4.init_device(0x55a4)
    except Exception as e:  # noqa: BLE001 — any USB failure is the same story
        print(f"  sensor unreachable: {e}", file=sys.stderr)
        print("  (busy in another process? stop fprintd and try again)",
              file=sys.stderr)
        return 1

    try:
        already = driver_55x4.check_psk(dev)
    except Exception as e:  # noqa: BLE001
        print(f"  could not read the key: {e}", file=sys.stderr)
        return 1

    if already:
        print("  key already present — nothing to do")
        return 0

    print("  no key on the sensor")
    if not confirmed():
        print("  not written; the driver will refuse to activate without it",
              file=sys.stderr)
        return 3
    print("  writing it (one-time step)...")
    try:
        driver_55x4.write_psk(dev)
    except Exception as e:  # noqa: BLE001
        print(f"  write failed: {e}", file=sys.stderr)
        return 2

    if driver_55x4.check_psk(dev):
        print("  key written and verified")
        return 0

    print("  write went through, but the sensor still does not report the key",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
