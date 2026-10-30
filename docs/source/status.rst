Status and limits
=================

What works
**********

On the development unit (Lenovo ThinkBook 15 G2 ITL, Fedora), enrolment and verification
work through the stock ``fprintd``, including PAM: screen unlock, login and ``sudo``. Ubuntu
22.04 is reported working in issue #2. On Debian 12 the sensor key has been written
and verified; install, enrolment and PAM follow :doc:`install` and are not yet reported.

Measured on one unit, by one person, with a real finger:

.. list-table::
    :header-rows: 1
    :widths: 70 30

    * - Test
      - Result
    * - True accept, deliberate displacement
      - 87.5 % (7/8)
    * - True accept, rotation up to 90°
      - 87.5 % (7/8)
    * - True accept, cross-finger run
      - 100 % (6/6)
    * - **False accepts, 38 impostor presses**
      - **0**

The impostor figure covers 14 presses with non-enrolled fingers identified against every
enrolled print, 12 against a single print, and 12 cross-finger trials against a second
enrolled finger (the hardest case). Read it as "no gross hole was opened", not as a
false-accept rate: 0/38 only bounds it at about 8 % with 95 % confidence.

Limitations
***********

* Tested on exactly **one** 55a4 unit. Treat the numbers as indicative.
* Finger-detect threshold learning is restricted to the 55a4 by device id. The 55b4 has
  three threshold tables, and one learned set would raise its finger-lift threshold by
  about a third. The flag is ``GOODIX_55X4_FLAG_LEARN_FDT`` in ``goodix55x4.h``.
* The touch threshold is calibrated on one finger. If capture is unreliable, override it
  with ``GOODIX55X4_TOUCH_DIFF=200``.
* The base fork is libfprint 1.94.6-era. The matcher fixes are worth carrying upstream;
  the driver itself has no upstream home, since freedesktop libfprint has no ``goodixtls``
  tree.
* No liveness detection and host-side matching: see :doc:`security`.

What was wrong
**************

The 55b4 driver ran on this sensor but matched about one press in three. Getting to a
working driver meant fixing eight defects; the ones that generalise:

* **Finger-detect thresholds are per sensor.** The device reports its own base in the
  ``FDT_MODE`` reply and the vendor sends back ``base >> 1``. The driver shipped 55b4
  constants, about 10× off.
* **Three bugs in the SIGFM matcher**, which affect every device using it: a comparator
  that reduced to ordering on ``y`` and discarded about half the matches; a relative
  difference on angles that becomes ``0/0`` at a quarter turn, so a 90° rotation was
  always rejected; and ``asin``/``acos`` domain overflow giving ``NaN`` at zero rotation.
* **The background frame was captured while a finger could still be on the plate**, which
  caused phantom touches and corrupted every image (frames are ``|frame - background|``).
* **The status LED is switchable** by command ``0xae``, the one the community notes call
  ``QUERY_MCU_STATE``.

:doc:`/TECHNICAL` has the full account and :doc:`/PROTOCOL` the protocol findings.

Credits and licence
*******************

Built on `TheWeirdDev/libfprint <https://github.com/TheWeirdDev/libfprint>`_ (LGPL-2.1+),
which is built on `freedesktop libfprint <https://gitlab.freedesktop.org/libfprint/libfprint>`_.
Protocol groundwork, the device config and the whitebox key come from
`goodix-fp-dump <https://github.com/goodix-fp-linux-dev/goodix-fp-dump>`_. The patch is a
derivative of libfprint and carries LGPL-2.1+; the scripts use the same terms.

The host-side finger-detect poll (``frame_diff_score()``, ``retry_finger_poll()``, the
``poll_attempts`` counter and the ``GOODIX55X4_FINGER_DETECT_*`` constants) is
`sidevesh's work <https://github.com/TheWeirdDev/libfprint/pull/4>`_, not this author's.
This repository changed the threshold (100 → 300, with a runtime override) and the role of
the poll: with the FDT fix, device-side detection works and the poll is a backstop.

How the protocol was established
--------------------------------

No vendor code is included and none was copied. The sources, all on the author's own
hardware, were USB traffic captured with ``usbmon`` while the stock Windows driver ran in
a VM, values the device reports in its own replies, and the vendor's Windows driver
examined for interoperability (a few strings and the frame-selection rule in
:doc:`/PROTOCOL`), then re-implemented independently. The result describes behaviour,
not expression. Interoperability reverse engineering is treated differently in each
jurisdiction and under conditions (for example Art. 6 of Directive 2009/24/EC in the EU);
this is a description of what was done, not legal advice.
