Install
=======

The driver is built from source: the repository holds a patch and the scripts, and the
build downloads ``libfprint`` at a pinned commit. There are two ways in:

1. :ref:`install-one-shot`: ``./install.sh`` builds in a temporary directory, installs
   and deletes the build tree. Use it if you only want a working reader.
2. :ref:`install-step-by-step`: build with ``./setup.sh``, test the capture, then install
   each piece yourself. Use it the first time on a machine, or to read the code or work on
   the driver.

Both end the same way: the sensor key is written once, ``fprintd`` uses the patched
library, and you enable PAM (:ref:`install-pam`) and enrol a finger.

.. _install-requirements:

Requirements
************

* A ``27c6:55a4`` sensor (see :ref:`intro`).
* ``sudo`` rights, and a real terminal for the commands that ask a question.
* Network access to GitHub and PyPI during the build.
* Build tools. On Debian/Ubuntu:

  .. code-block:: bash

      sudo apt install meson ninja-build gcc g++ cmake pkg-config git \
          libglib2.0-dev libgusb-dev libusb-1.0-0-dev libnss3-dev libssl-dev \
          libcairo2-dev libpixman-1-dev libgudev-1.0-dev libopencv-dev doctest-dev

  On Fedora:

  .. code-block:: bash

      sudo dnf install meson ninja-build gcc gcc-c++ libgusb-devel nss-devel \
          openssl-devel cairo-devel glib2-devel opencv-devel \
          gobject-introspection-devel libgudev-devel pixman-devel doctest-devel cmake

* ``fprintd`` and its PAM module (``libpam-fprintd`` on Debian/Ubuntu).
* Python 3 with ``venv``. On a Debian-family system that gives ``ensurepip is not
  available`` the package ``python3-venv`` is missing.

.. note::

    ``./install.sh`` lists the missing tools and prints the package line for your
    distribution (``scripts/print-build-deps.sh``) if one of ``git``, ``meson``, ``ninja``,
    ``python3``, ``gcc`` or ``g++`` is absent.

Check what is installed before you start:

.. code-block:: bash

    lsusb | grep 27c6         # the sensor must be listed as 27c6:55a4
    fprintd-list $USER        # before the install: "No devices available"

.. _install-one-shot:

One command
***********

.. code-block:: bash

    git clone https://github.com/Hydrogell/goodix-27c6-55a4-fingerprint-linux
    cd goodix-27c6-55a4-fingerprint-linux
    ./install.sh

Run it as your normal user, without ``sudo``: it refuses to run as root. In order it
does the following.

1. Builds the patched ``libfprint`` in a temporary directory under ``/var/tmp``.
2. Prepares a throwaway Python venv for the key write. Every package is pinned by hash
   (``requirements/``).
3. Asks for your password and installs the library, the systemd drop-in and, on SELinux
   systems, a one-rule policy module.
4. Writes the sensor key, as you, after asking (:ref:`install-key`). A udev rule that
   gives your session access to the sensor exists only during this step.
5. Deletes the build tree.

Then continue with :ref:`install-pam` and :doc:`usage`.

.. _install-step-by-step:

Step by step
************

This is the order used to bring the sensor up on a Debian 12 machine, with a check after
each step so a failure shows up where it happened.

.. _install-build:

1. Build
--------

.. code-block:: bash

    cd goodix-27c6-55a4-fingerprint-linux
    ./setup.sh

``setup.sh`` keeps everything under ``./work/`` (about 300 MB): the ``libfprint`` checkout
with the patch applied and built, and ``goodix-fp-dump`` with a virtualenv. It needs no
``sudo`` and does not touch the sensor or the system. Check the result:

.. code-block:: bash

    ls work/twd-libfprint/build/libfprint/libfprint-2.so*
    ls work/twd-libfprint/build/examples/img-capture

If the build fails, see :ref:`ts-build`.

.. _install-udev:

2. Give your user access to the sensor (temporarily)
----------------------------------------------------

The sensor node ``/dev/bus/usb/BBB/DDD`` belongs to ``root`` and is not writable by
others. For the key write, and to test captures without ``sudo``, install a udev rule that
tags the sensor ``uaccess``:

.. code-block:: bash

    sudo bash scripts/udev-access.sh grant
    getfacl /dev/bus/usb/$(lsusb -d 27c6:55a4 | sed -E 's#Bus ([0-9]+) Device ([0-9]+).*#\1/\2#')

The ``getfacl`` output must contain a line ``user:<you>:rw-``.

.. warning::

    While this rule exists, any program you run can open the sensor and read raw
    images from it. Remove it as soon as you are done (:ref:`install-revoke`).

``uaccess`` is granted by ``systemd-logind`` to the user of a local, active session.
It does not work over SSH. Check with ``loginctl show-session $XDG_SESSION_ID -p Remote
-p Active``.

3. Test the capture (optional, reads only)
------------------------------------------

``fprintd`` must not be holding the sensor:

.. code-block:: bash

    sudo systemctl stop fprintd
    G_MESSAGES_DEBUG=all work/twd-libfprint/build/examples/img-capture /tmp/out.pgm

Touch the sensor when it is armed. If the driver reports that the key is missing it will
refuse to activate: that is expected on an untouched sensor, and the next step fixes it.
The captured image is a picture of your fingertip: delete ``/tmp/out.pgm`` when you are
done.

.. _install-key:

4. Write the sensor key (once)
------------------------------

.. code-block:: bash

    sudo systemctl stop fprintd
    scripts/provision.sh

The script reads the key slot first. If the key is already there it prints ``key already
present — nothing to do`` and stops. Otherwise it asks:

.. code-block:: text

    This writes a public, non-device-specific key into slot 0xbb010003
    of the sensor, once. Windows' own slot (0xbb010002) is not touched,
    and uninstalling does not undo it. Write it now? [y/N]

Anything other than ``y`` writes nothing (exit code 3). On success it ends with ``key
written and verified``.

.. note::

    The question is asked on ``/dev/tty``, so run this in a real terminal. For a scripted
    install set ``GOODIX_ASSUME_YES=1`` to give the answer in advance.

The key is a fixed public blob, the same for every unit, and it is written in the slot
that the stock Windows driver does not use. It stays in the sensor after an uninstall.
The dual-boot notes are in the repository README, section *The sensor key*.

.. _install-revoke:

5. Remove the temporary access
------------------------------

.. code-block:: bash

    sudo bash scripts/udev-access.sh revoke

If ``getfacl`` still shows your user afterwards, unplug and replug the sensor, or reboot.

.. _install-system:

6. Install for the whole system
-------------------------------

.. code-block:: bash

    sudo bash scripts/install-system.sh

It installs ``libfprint-2.so`` into ``/opt/libfprint-goodix/lib64``, writes the drop-in
``/etc/systemd/system/fprintd.service.d/10-goodix55a4.conf`` (only ``fprintd`` sees the new
library), loads the SELinux module on enforcing systems, restarts ``fprintd`` and finally
checks whether ``/var/lib/fprint`` sits on an encrypted volume. Verify:

.. code-block:: bash

    systemctl cat fprintd | grep LD_LIBRARY_PATH
    fprintd-list $USER          # should now show the Goodix device

.. _install-pam:

7. Enable fingerprint in PAM
----------------------------

Until PAM is configured, enrolment works but nothing asks for a fingerprint.

On Debian and Ubuntu:

.. code-block:: bash

    sudo pam-auth-update

Tick "Fingerprint authentication" with the space bar, then OK. Check:

.. code-block:: bash

    grep fprintd /etc/pam.d/common-auth

A line with ``pam_fprintd.so`` must appear, ahead of the password module (``pam_unix.so``).

On Fedora:

.. code-block:: bash

    sudo authselect enable-feature with-fingerprint

``install-system.sh`` does this itself when ``authselect`` exists. On Debian it prints
``skipped: no authselect`` and leaves PAM alone, so the installer cannot lock you out.

.. warning::

    Before testing, keep a second terminal open with ``sudo -i`` and do not log out. If
    a module breaks authentication, you can still undo it from that shell
    (``sudo pam-auth-update`` again, or ``authselect disable-feature with-fingerprint``).
    Your password always works as a fallback.

.. _install-uninstall:

Uninstall
*********

.. code-block:: bash

    sudo bash scripts/uninstall-system.sh

This removes the library, the systemd drop-in, the SELinux module and the udev rule, and
restarts ``fprintd`` on the distribution's library. It does not undo three things:

* PAM keeps accepting fingerprints. Turn it off with ``sudo pam-auth-update`` (untick) or
  ``authselect disable-feature with-fingerprint``.
* The key written into the sensor is permanent.
* Enrolled fingerprints stay in ``/var/lib/fprint``. Remove them with
  ``fprintd-delete $USER``.
