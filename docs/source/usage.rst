Usage
=====

Everything here uses the standard ``fprintd`` tools, so it works the same from a terminal,
from GNOME/KDE settings and from the lock screen. The driver adds no new command.

Check that the device is seen
*****************************

.. code-block:: bash

    lsusb | grep 27c6:55a4
    fprintd-list $USER

``fprintd-list`` must show the Goodix device and the fingers already enrolled. ``No
devices available`` means the patched library is not in use: see :ref:`ts-no-devices`.

Enrol a fingerprint
*******************

.. code-block:: bash

    fprintd-enroll                              # default finger
    fprintd-enroll -f right-index-finger        # a named finger

The sensor is small, so enrolment takes 16 touches. Lift the finger between touches
and vary the position (centre, slightly left, right, up, down): more positions cover a
wider area and make later matches more tolerant. The command prints ``enroll-stage-passed``
after each good touch and ``enroll-completed`` at the end. ``enroll-retry-scan`` or
``remove-and-retry`` mean the touch was too light or off-centre; repeat it.

Enrol at least two fingers, in case a cut or a dry day makes one unreliable.

Verify
******

.. code-block:: bash

    fprintd-verify                              # the enrolled fingers
    fprintd-verify -f any                       # accept any finger, enrolled or not

The result is ``verify-match`` or ``verify-no-match``. ``verify-retry-scan`` asks for
another touch. If a clean press is rejected, press firmly and centred.

Desktop prompts while testing
*****************************

``scripts/fp-notify.sh`` mirrors the prompts as desktop notifications and sounds, so you
can follow the test without watching the terminal. It needs no root:

.. code-block:: bash

    scripts/fp-notify.sh enroll                 # full enrolment, one popup per touch
    scripts/fp-notify.sh verify 8               # eight verifications in a row
    scripts/fp-notify.sh impostor 5             # press a finger that is NOT enrolled

In ``impostor`` mode a rejection is the correct result and a match is reported as a
false accept.

Accuracy checks
***************

``scripts/fp-stress.sh [rounds]`` presses an enrolled thumb and an enrolled index finger
against each other and counts false accepts between two fingers of the same hand, which is
the hardest impostor case. Both fingers must be enrolled first
(``fprintd-enroll -f right-thumb`` and ``-f right-index-finger``).

Use the fingerprint to log in and for ``sudo``
**********************************************

After :ref:`install-pam`, the lock screen, the login prompt and ``sudo`` offer the
fingerprint first and fall back to the password:

.. code-block:: bash

    sudo -k                                     # forget the cached credentials
    sudo true                                   # "Place your finger on the reader."

.. note::

    The first login after a boot normally still needs the password, because the password
    is what unlocks the keyring. ``pam_fprintd`` behaves this way with any driver.

Remove enrolled fingerprints
****************************

.. code-block:: bash

    fprintd-delete $USER

Tune the touch threshold
************************

The driver decides a finger is present when the image differs from the empty-sensor
background by more than a threshold (default ``300``). If a light touch is ignored, lower
it; if the sensor reacts to nothing, raise it. ``fprintd`` is a systemd service, so set
the variable in a drop-in and restart:

.. code-block:: bash

    sudo systemctl edit fprintd
    # add:
    #   [Service]
    #   Environment=GOODIX55X4_TOUCH_DIFF=200
    sudo systemctl restart fprintd

The driver logs ``touch threshold overridden to 200`` when it picks the value up.

The sensor LED
**************

The light in the power button is switched by the sensor and lit by the driver for as long as
the device is open. Stopping ``fprintd`` with ``systemctl stop`` lets it switch the LED off;
a ``kill -9`` does not, and leaves the light on until the sensor is used again.
