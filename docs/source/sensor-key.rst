The sensor key
===============

The driver speaks TLS-PSK with an all-zero key. The sensor accepts that only after a fixed
"whitebox" blob has been written into it. The blob is public, the same for every unit, and
ships in `goodix-fp-dump <https://github.com/goodix-fp-linux-dev/goodix-fp-dump>`_; it is
not extracted from your hardware.

Writing it is a one-time operation (``scripts/provision_psk.py``, idempotent). The C
driver writes no key: it reads the hash in slot ``0xbb020007`` and refuses to activate if
it is wrong, which on an untouched sensor looks like an unexplained activation failure.

How it is run
*************

* As **your user**, never root. The Python and its PyPI packages (pinned by hash in
  ``requirements/``) therefore have no root rights. ``scripts/provision.sh`` refuses to
  run as root.
* After a **prompt on the terminal** (``/dev/tty``). Anything other than ``y`` writes
  nothing and exits with code 3. ``GOODIX_ASSUME_YES=1`` answers for scripted installs.
* With **temporary device access** from a udev rule, removed afterwards
  (see :doc:`install`).

Exit codes
**********

.. list-table::
    :header-rows: 1
    :widths: 10 90

    * - Code
      - Meaning
    * - 0
      - The sensor already had the key, or it was written and verified
    * - 1
      - The sensor is unreachable (busy, missing, no permission)
    * - 2
      - The write was attempted and the sensor still does not report the key
    * - 3
      - The sensor needs the key and you declined, or there was no terminal to ask on

The key is permanent: uninstalling does not remove it.

Dual-boot
*********

The slots are distinct, and that half is a fact about the code. Windows keeps its key
material in ``0xbb010002``. The only slot anything here writes is ``0xbb010003``, through
``preset_psk_write(0xbb010003, PSK_WHITE_BOX)`` in ``driver_55x4.py``. No code path
addresses ``0xbb010002``.

What Windows does afterwards was seen once, not measured. With the sensor passed through
to a Windows VM, after the unit had been provisioned, a Windows session enrolled a
fingerprint. The USB trace shows the vendor driver writing its own 324-byte DPAPI blob into
``0xbb010002``, so it provisions that slot itself. A check afterwards found the whitebox
key still in effect on the Linux side. That is one session on one machine, and passthrough
is not a real dual-boot: treat "both sides coexist" as an expectation with one observation
behind it. If Windows fingerprint login misbehaves, re-enrolling under Windows should
restore it; please open an issue either way.
