This project is a working ``libfprint`` driver for the Goodix 55a4 fingerprint
sensor (USB ``27c6:55a4``), found in the Lenovo ThinkBook 15 G2 ITL and other
machines of that generation. Before it, ``fprintd-enroll`` answered
*"No devices available"* on these machines and the reader never appeared in the
desktop settings.

It is a patch (``patches/55a4-driver.patch``) on top of the
`TheWeirdDev/libfprint <https://github.com/TheWeirdDev/libfprint/tree/55b4-experimental>`_
branch ``55b4-experimental``, plus the scripts that build, install and test it.

.. _intro:

Introduction
************

Does this apply to me?
----------------------

.. code-block:: bash

    lsusb | grep 27c6

If the output contains ``27c6:55a4`` (``Shenzhen Goodix Technology Co.,Ltd. Goodix
FingerPrint Device``), yes. If it shows ``27c6:55b4`` use
`libfprint-goodixtls-55x4 <https://aur.archlinux.org/packages/libfprint-goodixtls-55x4>`_
instead.

How it works
------------

.. list-table::
    :header-rows: 1
    :widths: 28 72

    * - Piece
      - What it does
    * - ``libfprint`` driver (``goodixtls55x4``)
      - Talks to the sensor over USB bulk endpoints ``0x01`` (out) and ``0x82`` (in)
        and tunnels a TLS 1.2 PSK session through them. Images are matched on the
        host with the SIGFM matcher (OpenCV).
    * - Sensor key
      - The sensor only accepts the all-zero TLS key after a fixed, public blob has
        been written into slot ``0xbb010003``. This happens once, as your user
        and only after you confirm (see :ref:`install-key`).
    * - ``/opt/libfprint-goodix``
      - Where the patched library lives. A systemd drop-in points only
        ``fprintd`` at it, through ``LD_LIBRARY_PATH``. The distribution's own
        ``libfprint`` is neither replaced nor downgraded.
    * - PAM
      - ``pam_fprintd`` is what lets login, the lock screen and ``sudo`` accept a
        fingerprint. It is configured separately (see :ref:`install-pam`).

What you should know first
--------------------------

.. warning::

    * The USB channel is encrypted but not confidential: the pre-shared key is 32
      zero bytes. Anyone who knows the protocol can decrypt a capture of it.
    * The sensor has no on-chip matcher. Raw images cross the bus and are processed in
      ordinary memory.
    * ``fprintd`` stores enrolled templates as plain files in ``/var/lib/fprint``.
      Use full-disk encryption.
    * The fingerprint is a convenience factor. Do not rely on it as a security boundary.

.. note::

    This was developed and measured on one unit, by one person. The sensor detection and
    the key write were confirmed on a Debian 12 machine while this guide was written. The
    build, installation, enrolment and PAM steps follow the installer and the Debian
    packaging and have not all been confirmed end to end there; the
    :doc:`/source/troubleshooting` page lists what can go wrong.

Security fixes carried by the patch
-----------------------------------

The upstream driver trusted lengths sent by the USB device. The patch adds a bounds check
on the TLS data frame (a frame shorter than 9 bytes used to wrap an unsigned length), fixes
a heap overflow and a NULL dereference in the TLS error path, joins the TLS accept thread
before freeing what it uses, and stops a failed TLS start from aborting ``fprintd``.
These changes were reviewed by reading the code and were **not compiled or run against a
sensor** when they were written.
