Troubleshooting
===============

Most entries below are problems met while bringing this driver up on a Debian 12 machine
(sensor at ``27c6:55a4``, ``libfprint`` 1.94.5, ``fprintd`` 1.94.2). Each has the symptom,
the cause and the fix. Entries marked *not confirmed* are likely causes that have not been
reproduced.

Collect diagnostics first
*************************

.. code-block:: bash

    lsusb | grep 27c6                                  # is the sensor there?
    systemctl status fprintd                           # running? (it exits when idle)
    journalctl -u fprintd -b --no-pager | tail -50     # why did it stop?
    systemctl cat fprintd | grep -A2 10-goodix         # is the drop-in in place?
    fprintd-list $USER

.. warning::

    When you report a problem, do not attach USB captures (``*.pcapng``) or raw images
    (``*.pgm``, ``*.raw``). They contain your fingerprint, and the session key is public.

Sensor and fprintd
******************

.. _ts-no-devices:

``No devices available``
------------------------

*Cause.* ``fprintd`` is still using the distribution's ``libfprint``, which has no driver
for ``27c6:55a4``.

*Fix.* Check each link:

.. code-block:: bash

    ls /opt/libfprint-goodix/lib64/                         # the library is installed
    cat /etc/systemd/system/fprintd.service.d/10-goodix55a4.conf
    sudo systemctl daemon-reload && sudo systemctl restart fprintd
    sudo grep libfprint /proc/$(pidof fprintd)/maps         # which libfprint is loaded?

The ``maps`` output must show ``/opt/libfprint-goodix/lib64/libfprint-2.so.2``. If it
shows ``/usr/lib/...`` the drop-in was not read: run ``daemon-reload`` and restart. If
``/opt/libfprint-goodix`` does not exist, the install step never ran
(:ref:`install-system`).

``fprintd`` stops or crashes right after the install
----------------------------------------------------

Look at ``journalctl -u fprintd -b``.

* Missing libraries:

  .. code-block:: bash

      LD_LIBRARY_PATH=/opt/libfprint-goodix/lib64 ldd /opt/libfprint-goodix/lib64/libfprint-2.so.2 | grep 'not found'

  Install the runtime package of each missing library (OpenCV, NSS, libgusb).

* *Not confirmed:* the Debian unit sets ``MemoryDenyWriteExecute=true`` and
  ``SystemCallFilter=@system-service``. A library that maps memory as writable and
  executable (OpenCV/TBB can) is then killed. As a diagnostic only, relax it and see
  whether the crash goes away:

  .. code-block:: bash

      sudo systemctl edit fprintd      # add:  [Service]  MemoryDenyWriteExecute=no
      sudo systemctl restart fprintd

  If that fixes it, you are trading away a hardening option of the service. Prefer to
  report it rather than keep it.

To see the driver's own messages, run ``fprintd`` in the foreground:

.. code-block:: bash

    sudo systemctl stop fprintd
    sudo env G_MESSAGES_DEBUG=all LD_LIBRARY_PATH=/opt/libfprint-goodix/lib64 /usr/libexec/fprintd -t

``sensor unreachable`` / the device is busy
-------------------------------------------

*Cause.* ``fprintd`` (or a test program) holds the sensor. ``fprintd`` is started by D-Bus
whenever something asks for it, so it can come back after you stopped it.

*Fix.* Stop it just before the command and run the command right away:

.. code-block:: bash

    sudo systemctl stop fprintd
    scripts/provision.sh

Stop it with ``systemctl stop``, not ``kill -9``: the driver switches the LED off when the
device closes, and a hard kill leaves it lit.

Light stays on with nothing running
-----------------------------------

The process was killed with ``SIGKILL`` before the driver could close the device. Run any
capture or verify once and let it finish normally.

Sensor key (``provision.sh``)
*****************************

.. _ts-no-write-access:

``No write access to /dev/bus/usb/003/009``
-------------------------------------------

*Causes*, in the order to check them:

1. The access rule is not installed. Run ``sudo bash scripts/udev-access.sh grant``
   and look for ``user:<you>:rw-`` in ``getfacl`` of the node.
2. You are not in a local session. ``uaccess`` is given to the active seat user, so it fails over
   SSH. Use a local terminal. ``loginctl show-session $XDG_SESSION_ID -p Remote -p Active``
   must say ``Remote=no`` and ``Active=yes``.
3. A wrong node was checked. The device number changes every time the sensor
   re-enumerates (it was 005, 009, then 011 during one session), so never copy an old path.
   An early version of ``provision.sh`` also built the path with ``printf %03d``, which
   reads ``011`` as octal 9 and checked ``/dev/bus/usb/003/009``, a hub. Confirm what you
   are looking at:

   .. code-block:: bash

       lsusb -d 27c6:55a4                    # Bus 003 Device 011
       udevadm info /dev/bus/usb/003/011 | grep -E 'ID_VENDOR_ID|ID_MODEL_ID|CURRENT_TAGS'

   The node must say ``27c6`` / ``55a4`` and carry the ``uaccess`` tag. Update the
   repository (``git pull``) if your ``provision.sh`` still uses ``printf``.
4. The rule never matched. ``udevadm test $(udevadm info -q path -n <node>) 2>&1 | grep 70-goodix``
   shows whether ``/etc/udev/rules.d/70-goodix55a4.rules`` was read.

``no terminal to ask on; set GOODIX_ASSUME_YES=1``
--------------------------------------------------

The confirmation is read from ``/dev/tty`` and none could be opened.

* Running through something that has no terminal (a pipe, a script, a tool that runs
  commands without a TTY, some "run in IDE" buttons) is the usual reason. Run it in a
  normal terminal.
* An earlier version also failed inside a real terminal: it opened ``/dev/tty`` in
  ``r+`` mode, which Python rejects because a terminal cannot seek, and treated the error as
  "no terminal". Update the repository if you see this in a real terminal.
* To give the answer in advance, once you have decided to write the key:

  .. code-block:: bash

      GOODIX_ASSUME_YES=1 scripts/provision.sh

Exit codes
----------

.. list-table::
    :header-rows: 1
    :widths: 10 90

    * - Code
      - Meaning
    * - 0
      - The key was already there, or it was written and verified.
    * - 1
      - The sensor is unreachable (busy, missing, no permission), or the script was run
        from the wrong directory or as root.
    * - 2
      - The write was attempted and the sensor still does not report the key.
    * - 3
      - The sensor needs the key and you declined, or there was no terminal to ask on.

``sudo: sorry, you must have a tty to run sudo``
------------------------------------------------

The command ran where there is no terminal. ``install.sh`` and the steps that use
``sudo`` must be run from a real terminal session.

Build and install
*****************

.. _ts-build:

The build fails
---------------

* Missing tools or headers: ``meson`` names the missing dependency
  (``Dependency "gusb" not found``). Install the package line from
  :ref:`install-requirements`. Run ``scripts/print-build-deps.sh`` for the list.
* ``meson setup --wipe`` error on a fresh clone (Ubuntu 22.04, meson 0.61): fixed in
  ``scripts/meson-build-libfprint.sh``, which now recreates a dedicated ``build/``
  directory. If you see it, update the repository.
* A broken or half-built tree: delete it and build again:

  .. code-block:: bash

      rm -rf work/twd-libfprint/build
      ./setup.sh

* The patch does not apply (``error: patch failed``). The patch only fits the pinned
  commit ``d1ca62a``. ``setup.sh`` and ``install.sh`` stop if the checkout is not at that
  commit. To check by hand:

  .. code-block:: bash

      git -C work/twd-libfprint apply --check ../../patches/55a4-driver.patch

* ``ERROR: ... is at <sha>, expected <sha> — refusing to build``. The checkout is not
  at the pinned commit. Remove ``work/`` and run ``./setup.sh`` again.

``pip`` problems in the Python venv
-----------------------------------

* ``THESE PACKAGES DO NOT MATCH THE HASHES``. A file does not match
  ``requirements/*.txt``. Do not remove ``--require-hashes`` to get past it: that check is
  there on purpose. Retry once (a download may be corrupted); if it repeats, stop and open
  an issue.
* ``Could not find a version that satisfies the requirement`` (``./setup.sh`` only).
  ``numpy==2.2.6`` needs Python 3.10 or newer.
* ``crcmod`` fails to build. It ships only as source and compiles a C extension: you
  need ``gcc`` and the Python headers (``python3-dev`` on Debian/Ubuntu,
  ``python3-devel`` on Fedora).
* ``ensurepip is not available``. Install ``python3-venv``.

SELinux alert about ``nr_hugepages`` (Fedora)
---------------------------------------------

OpenCV's TBB reads ``/proc/sys/vm/nr_hugepages``, which ``fprintd``'s domain may not read.
Nothing breaks. ``install-system.sh`` loads a ``dontaudit`` module on enforcing systems; it
is skipped when ``checkmodule``/``semodule`` are missing. Check with
``sudo semodule -l | grep goodix_fprintd``, and install ``checkpolicy`` and
``policycoreutils`` if it is not there. The module grants no access.

Enrolment and verification
**************************

Touches are ignored, or every touch says "retry"
------------------------------------------------

The finger-detect threshold does not suit your finger or your sensor. See *Tune the touch
threshold* in :doc:`usage`. Clean the sensor, press firmly and centred, and vary the
position between enrolment touches.

``enroll-failed`` or ``enroll-duplicate``
-----------------------------------------

The sensor was not activated, or the finger is already enrolled. Run
``fprintd-delete $USER`` and enrol again; if it keeps failing, run ``fprintd`` in the
foreground (above) and read the driver messages.

The driver refuses to activate
------------------------------

It checks the key hash in slot ``0xbb020007`` and does not activate without it. Run
``scripts/provision.sh`` again (:ref:`install-key`); it says ``key already present`` when
nothing is missing.

PAM
***

Fingerprint is never offered at login or ``sudo``
-------------------------------------------------

1. Is PAM enabled? ``grep fprintd /etc/pam.d/common-auth`` must match on Debian. If
   not, run ``sudo pam-auth-update`` and tick *Fingerprint authentication*
   (:ref:`install-pam`). On Fedora, ``authselect current`` must list ``with-fingerprint``.
2. Is a finger enrolled for this user? ``fprintd-list $USER``. ``pam_fprintd`` is
   skipped when the user has none, and ``sudo`` uses the invoking user's prints.
3. Is ``fprintd`` working? ``fprintd-verify`` must answer. If it does not, the problem
   is not PAM.
4. Remote logins: SSH and other sessions without the sensor never offer it.

The password prompt appears only after a pause
----------------------------------------------

``pam_fprintd`` waits for a finger for its ``timeout`` (10 seconds by default) before it
falls through to the password. Press Enter or type the password to skip it.

Undo PAM if you are locked out
------------------------------

Do this from the root shell you kept open (:ref:`install-pam`), or from a recovery boot:

.. code-block:: bash

    sudo pam-auth-update --remove fprintd         # Debian / Ubuntu
    sudo authselect disable-feature with-fingerprint   # Fedora

The password always remains a valid fallback in the default configuration.

Other
*****

The udev access rule is still there
-----------------------------------

``install.sh`` removes it in a trap even if a step fails. If the machine lost power in the
middle, remove it yourself:

.. code-block:: bash

    sudo bash scripts/udev-access.sh revoke

and replug the sensor if ``getfacl`` still lists your user.

Windows (dual boot)
-------------------

The key is written in slot ``0xbb010003`` and Windows keeps its own in ``0xbb010002``, so the
two should coexist. That was observed once, in a passthrough VM. If Windows fingerprint
login misbehaves, re-enrol under Windows and open an issue.

Still stuck
-----------

Open an issue with the output of the commands under *Collect diagnostics first*, the
distribution and version, and ``dpkg -l | grep -E 'libfprint|fprintd'`` (or ``rpm -q``).
