Security
========

The defaults invite the wrong assumption, so plainly: treat the fingerprint as a
convenience factor, not a security boundary. Keep the disk, the account password and
anything valuable behind a real secret.

.. _sec-limits:

Properties of the hardware
**************************

None of these can be fixed by this project. Every open-source Goodix driver is in the same
position.

**The USB channel is encrypted but not confidential.**
    It runs TLS 1.2 (``PSK-AES128-CBC-SHA256``), so the bytes differ in every session.
    But the pre-shared key is 32 zero bytes, because the sensor only accepts a key wrapped
    by the vendor's white-box crypto and the all-zeros blob is the only one that has been
    published. Anyone who can *capture* the traffic can decrypt it. That takes root with
    ``usbmon``, a VM that owns the device, a hostile hub or physical access, so it is a
    local threat, not a remote one. It is also why a USB capture of this sensor is your
    fingerprint in a file (see ``CONTRIBUTING.md``).

**The sensor matches on the host.**
    There is no on-chip matcher, so the raw image crosses the bus and is processed in
    ordinary memory. Sensors that match on-chip exist and libfprint supports several
    (``goodixmoc``, ``elanmoc``, ``fpcmoc``, ``synaptics``).

**Templates are stored unencrypted.**
    ``fprintd`` writes them as plain files under ``/var/lib/fprint``, readable by root
    only. That is upstream behaviour, not something this driver adds. On an unencrypted
    disk anyone who can pull the drive can read them. Use full-disk encryption and keep
    SELinux or AppArmor enforcing.

**There is no liveness detection.**
    The sensor cannot tell a finger from a good copy of one (a lifted print, a mould).
    The accuracy figures in :doc:`status` measure impostor *fingers*, not spoofing.

.. _sec-hardening:

What this repository hardened
*****************************

The driver parses frames that come from the USB device, and it runs inside ``fprintd``,
which is root. A fake or compromised sensor is therefore an input source to defend
against. The patch fixes the memory-safety defects found by reading ``goodix.c`` and
``goodixtls.c`` in full:

.. list-table::
    :header-rows: 1
    :widths: 35 65

    * - Defect
      - Fix
    * - ``payload_len - 9`` wrapped around (unsigned 16-bit) for a short TLS data frame
      - Frames shorter than 9 bytes are rejected with ``G_IO_ERROR_INVALID_DATA``
    * - ``err_from_ssl`` allocated ``strlen`` bytes (one short) and called ``strlen(NULL)``
      - Rewritten with ``g_error_new_literal`` and a ``NULL`` fallback
    * - The SSL accept thread was never joined
      - ``deinit`` shuts the socket down and joins the thread
    * - ``tls_hop`` stayed set after a failed init, so the next init hit ``g_assert``
      - Allocated with ``g_new0`` and cleared on failure
    * - A buffer leaked when ``SSL_read`` failed
      - Freed on that path

The fix is in the ``fix(driver)`` commit. The same defects exist in the fork the patch is
based on; they are not reported upstream.

One more defect was left alone because it is dead code: ``goodix_send_preset_psk_write``
uses ``sizeof`` of a pointer, but nothing calls it. The C driver never writes a key.

Installer
*********

* **Pinned inputs.** The two external repositories are fetched at fixed commits
  (``libfprint`` fork ``d1ca62a``, ``goodix-fp-dump`` ``cc43bb3``), and every Python
  package is installed with ``--require-hashes --no-deps --no-build-isolation`` from
  ``requirements/``.
* **PyPI code never runs as root.** The key write runs as your user. Root is only used
  for the install steps.
* **Confirmation before the write.** Nothing is written to the sensor unless you type
  ``y`` on the terminal; see :doc:`sensor-key`.
* **Temporary device access.** ``scripts/70-goodix55a4.rules`` tags the sensor
  ``uaccess`` only for the key step. While it exists any program you run can read raw
  images from the sensor, so ``install.sh`` revokes it afterwards, and its cleanup trap
  revokes it if the script fails. It works for a local graphical session, not over SSH.
* **Nothing replaces your libfprint.** The patched library is installed as
  ``/opt/libfprint-goodix/lib64/libfprint-2.so.2.0.0`` with root ownership, ``0755``. A
  systemd drop-in sets ``LD_LIBRARY_PATH`` for ``fprintd`` only. Because ``fprintd`` runs
  as root and loads that file, keep the directory root-owned and not writable by others.
* **SELinux.** On Fedora a one-rule ``dontaudit`` module hides the harmless alert that
  OpenCV's TBB allocator triggers; it grants no access.
* **PAM.** The installer enables ``authselect``'s ``with-fingerprint`` feature where
  ``authselect`` exists. Elsewhere it skips the step and tells you to run
  ``sudo pam-auth-update``. After either, GDM, ``login`` and ``sudo`` accept a fingerprint.

``scripts/uninstall-system.sh`` removes the library, the drop-in, the policy module and
the udev rule. It does not undo three things: PAM still accepts fingerprints
(``authselect disable-feature with-fingerprint`` or ``pam-auth-update``), the sensor key
stays (:doc:`sensor-key`), and your enrolled prints stay in ``/var/lib/fprint``
(``fprintd-delete $USER``).

Not verified
************

* The Debian ``fprintd`` unit sets ``MemoryDenyWriteExecute=true``, ``ProtectSystem=strict``
  and a system-call filter. Whether OpenCV/TBB runs under them with the patched library
  has to be confirmed by enrolling on the machine; if ``fprintd`` dies at the first scan,
  see :doc:`troubleshooting`.
* The hardening patch applies cleanly to the pinned base and was written from a full
  read of the two files. Run ``./setup.sh`` and a capture to confirm it builds and works
  on your system.

Reporting a vulnerability
*************************

See ``SECURITY.md`` in the repository root. Never attach a capture, a frame dump or an
image of a fingerprint.
