# Security policy

This driver handles biometric data, so it is worth being precise about what is a
vulnerability here and what is a documented property of the hardware. The full
account is in [`docs/source/security.rst`](docs/source/security.rst).

## Known and not a vulnerability

Please do not open a security report for these. They are real limitations of the sensor
or of upstream, and none of them can be fixed by this project.

- **The USB channel uses a pre-shared key of 32 zero bytes.** The sensor only accepts a key
  wrapped by vendor white-box crypto, and the all-zeros blob is the only one that has been
  published. Anyone who can capture the traffic (root with `usbmon`, a VM that owns the
  device, a hostile hub, physical access) can decrypt it. Every open-source Goodix driver is
  in this position.
- **A USB capture of this sensor can be decrypted into fingerprint images.** That follows
  from the point above, and is why `CONTRIBUTING.md` says never to attach one.
- **`fprintd` stores enrolled templates unencrypted** under `/var/lib/fprint`. That is
  upstream behaviour.
- **Matching happens on the host**; the 55a4 has no on-chip matcher.
- **There is no liveness detection.** A good copy of an enrolled finger (lifted print,
  mould) is not an attack this project can defend against.
- **The sensor key is permanent** once written, and `uninstall-system.sh` does not remove
  it. It is a public, non-device-specific key written to slot `0xbb010003` only.

Treat this fingerprint as a convenience factor, not a security boundary.

## Worth reporting privately

Anything that makes the driver *less safe than the above describes*, for example:

- a way to corrupt memory, crash `fprintd` or run code through data sent by the USB device.
  The driver runs inside `fprintd` as root, so a hostile sensor is in scope. Known
  defects of this kind were fixed in the `fix(driver)` commit; new ones are welcome;
- it writes captured images or templates somewhere not documented;
- the installer or the scripts do something with root that they should not, create
  world-readable files holding sensor data, or leave the temporary udev rule
  (`/etc/udev/rules.d/70-goodix55a4.rules`) in place after `install.sh`;
- `/opt/libfprint-goodix` ends up writable by anyone but root (it is loaded by a root
  service);
- a way to make verification succeed against a finger that was not enrolled;
- the key-provisioning path writes to a slot other than `0xbb010003`, writes without the
  confirmation, or damages the sensor;
- a dependency that is fetched without being pinned by commit or hash.

## How to report

Use GitHub's private vulnerability reporting: this repository's **Security** tab, then
*Report a vulnerability*.

**Do not attach a capture, a frame dump, or an image of a fingerprint**, not even to a
private report and not even your own. If a trace is genuinely needed, say so and it can be
arranged; `CONTRIBUTING.md` explains how to record one that holds no biometric data.

There is no bounty and no guaranteed response time; this is one person with one laptop.

## Scope

This policy covers the patch in `patches/` and the scripts in this repository.

Problems in `libfprint`, `fprintd` or the sensor firmware belong upstream:
[libfprint](https://gitlab.freedesktop.org/libfprint/libfprint) and
[fprintd](https://gitlab.freedesktop.org/libfprint/fprintd). The fork this patch builds on
([TheWeirdDev/libfprint](https://github.com/TheWeirdDev/libfprint)) has the same
memory-safety defects fixed here. If you are unsure which applies, report it here and it
will be forwarded.
