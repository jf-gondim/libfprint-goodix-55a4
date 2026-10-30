# Goodix 27c6:55a4 fingerprint sensor on Linux

A working libfprint driver for the **Goodix 55a4** fingerprint sensor, found in the
Lenovo ThinkBook 15 G2 ITL and other machines of that generation (ThinkBook 13/14/15,
ThinkPad E14/E15, IdeaPad 3 14). It is a patch on top of
[TheWeirdDev/libfprint][fork] branch `55b4-experimental`, plus the scripts to build,
install and test it.

[fork]: https://github.com/TheWeirdDev/libfprint/tree/55b4-experimental

If `lsusb | grep 27c6` shows **`27c6:55a4`**, this applies to you. For `27c6:55b4` use
[libfprint-goodixtls-55x4](https://aur.archlinux.org/packages/libfprint-goodixtls-55x4).
Before you rely on this, check that no maintained 55a4 driver has appeared since July 2026.

## Install

Install the build dependencies, then:

```sh
git clone https://github.com/Hydrogell/goodix-27c6-55a4-fingerprint-linux
cd goodix-27c6-55a4-fingerprint-linux
./install.sh          # as your normal user, not root
fprintd-enroll        # 16 touches; vary the finger position
fprintd-verify
```

`install.sh` builds in a temporary directory, installs, and deletes the build tree. It
asks for `sudo` for the install steps and for a `y` before it writes the sensor key (once,
permanent, a public key). It does not replace your distribution's libfprint: the patched
build goes to `/opt/libfprint-goodix` and a systemd drop-in points only `fprintd` at it.
Then enable PAM: `authselect` on Fedora (done by the installer), `sudo pam-auth-update`
on Debian/Ubuntu.

To read the code, rebuild or run the accuracy tests, use `./setup.sh` instead; it keeps
the build in `work/` (about 300 MB, git-ignored).

Tested on Fedora 44 (development unit) and reported on Ubuntu 22.04. On Debian 12 the key
write is confirmed; the rest is not yet reported.

## Security, in short

The USB channel is encrypted but **not confidential** (the pre-shared key is 32 zero
bytes), matching happens on the host, templates are unencrypted under `/var/lib/fprint`,
and there is no liveness detection. Treat the fingerprint as a convenience factor, not a
security boundary. This fork also bound-checks device-supplied TLS frames and fixes
memory-safety defects in the driver. See [SECURITY.md](SECURITY.md) and
[docs/source/security.rst](docs/source/security.rst).

**Never attach a USB capture to an issue.** It is your fingerprint in a file, and anyone
who has it can decrypt it. [CONTRIBUTING.md](CONTRIBUTING.md) says what to send instead.

## Documentation

Built with Sphinx (`pip install -r docs/requirements.txt && make -C docs html`):

| Topic | File |
|---|---|
| Introduction, install, usage, troubleshooting | `docs/source/{about,install,usage,troubleshooting}.rst` |
| Threat model, hardening, installer behaviour | `docs/source/security.rst` |
| The sensor key and dual-boot | `docs/source/sensor-key.rst` |
| Accuracy, limitations, credits, legal note | `docs/source/status.rst` |
| Protocol findings | `docs/PROTOCOL.md` |
| Full technical account | `docs/TECHNICAL.md` |

## Licence

LGPL-2.1+, as a derivative of libfprint. Protocol groundwork and the key blob come from
[goodix-fp-dump](https://github.com/goodix-fp-linux-dev/goodix-fp-dump); the host-side
finger-detect poll is [sidevesh](https://github.com/TheWeirdDev/libfprint/pull/4)'s work.
Details in `docs/source/status.rst`.
