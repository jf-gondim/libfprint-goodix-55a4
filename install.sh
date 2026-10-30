#!/usr/bin/env bash
# Install the Goodix 55a4 fingerprint driver, and leave nothing behind.
#
# Everything is built in a temporary directory and deleted afterwards. When this
# finishes, your home directory is exactly as it was. What stays on the system:
#
#   /opt/libfprint-goodix/lib64/libfprint-2.so.*      the patched library
#   /etc/systemd/system/fprintd.service.d/10-*.conf   points fprintd at it
#   one SELinux policy module (enforcing systems only)
#
# scripts/uninstall-system.sh removes all three. The one-time sensor key is
# written as YOU, not root, and only after you confirm; a udev rule that lets
# your session reach the sensor exists just for that step and is removed again.
#
# Your distribution's own libfprint is neither replaced nor downgraded — only
# fprintd is redirected, every other program keeps using the system library.
#
# If you want to read the code, run the test harness, or work on the driver,
# use ./setup.sh instead: it keeps the build tree so you can rebuild and hack.
#
#   ./install.sh          install and clean up
#   ./setup.sh            developer path, keeps ./work/
set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
# Full 40-character commit IDs on purpose, not abbreviations. A 7-character
# prefix is 28 bits: anyone able to push to those repositories could add a commit
# sharing it and make the checkout ambiguous. The libfprint pin matters for a
# second reason too — the patch's context hunks apply only to that revision, and
# a branch tip moves.
FORK_URL="https://github.com/TheWeirdDev/libfprint.git"
FORK_REV="d1ca62a801aa565e67d1a2a47aaa7a33232b7990"
DUMP_URL="https://github.com/goodix-fp-linux-dev/goodix-fp-dump.git"
DUMP_REV="cc43bb3b3154a0bccc0412ae024013c7e1923139"

# Check out an exact commit and refuse to continue if we did not land on it.
pin() {  # pin <dir> <full-sha>
  git -C "$1" checkout -q "$2"
  got="$(git -C "$1" rev-parse HEAD)"
  [ "$got" = "$2" ] || {
    echo "ERROR: $1 is at $got, expected $2 — refusing to build." >&2
    exit 1
  }
}

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user, not with sudo." >&2
  echo "It builds unprivileged and asks for sudo only for the install step." >&2
  exit 1
fi

for c in git meson ninja python3 gcc g++; do
  command -v "$c" >/dev/null 2>&1 || {
    echo "missing: $c" >&2
    "$REPO/scripts/print-build-deps.sh"
    exit 1
  }
done

# /var/tmp rather than /tmp: the build is ~200 MB and /tmp is often a tmpfs,
# i.e. RAM. Overridable for anyone who wants it elsewhere.
BUILD="$(mktemp -d -p "${GOODIX_BUILD_DIR:-/var/tmp}" goodix55a4.XXXXXXXX)"
UDEV_GRANTED=0
cleanup() {
  # Never leave the sensor open to every program in your session.
  if [ "$UDEV_GRANTED" = 1 ]; then
    sudo bash "$REPO/scripts/udev-access.sh" revoke ||
      echo "WARNING: remove /etc/udev/rules.d/70-goodix55a4.rules by hand." >&2
  fi
  echo "== cleaning up the build tree =="
  rm -rf "$BUILD" 2>/dev/null
  # Verify rather than assume: the install step runs as root inside $BUILD, so a
  # root-owned file left behind would defeat the whole point of building here.
  if [ -e "$BUILD" ]; then
    echo "WARNING: $BUILD could not be removed completely." >&2
    echo "         Remove it with:  sudo rm -rf $BUILD" >&2
  fi
}
trap cleanup EXIT
echo "building in $BUILD (removed when this finishes)"

echo "== 1/4 build the patched libfprint =="
git clone -q --branch 55b4-experimental "$FORK_URL" "$BUILD/libfprint"
pin "$BUILD/libfprint" "$FORK_REV"
git -C "$BUILD/libfprint" apply "$REPO/patches/55a4-driver.patch"
"$REPO/scripts/meson-build-libfprint.sh" "$BUILD/libfprint"
echo "   built"

# The sensor only accepts the all-zero TLS key once a fixed public blob has been
# written to it, and that write lives in goodix-fp-dump's Python driver. It is
# needed exactly once, so it gets a throwaway venv holding only what the write
# path imports — no OpenCV, no numpy, which is the difference between ~15 MB and
# ~250 MB. The research tooling in ./setup.sh does pull those in.
# Every package is pinned by hash (requirements/): this code runs against your
# sensor, so it must be exactly what was reviewed. build.txt goes first and
# --no-build-isolation keeps pip from fetching an unpinned setuptools to build
# crcmod, which only ships as source.
echo "== 2/4 prepare one-time key provisioning =="
git clone -q "$DUMP_URL" "$BUILD/goodix-fp-dump"
pin "$BUILD/goodix-fp-dump" "$DUMP_REV"
python3 -m venv "$BUILD/goodix-fp-dump/.venv"
PIP="$BUILD/goodix-fp-dump/.venv/bin/pip"
"$PIP" install -q --require-hashes --no-deps -r "$REPO/requirements/build.txt"
"$PIP" install -q --require-hashes --no-deps --no-build-isolation \
  -r "$REPO/requirements/provision.txt"
# stub: protocol.py imports spidev unconditionally, for the SPI variants of this
# sensor family. Ours is USB, so nothing ever calls into it — but the import has
# to resolve or driver_55x4 will not load.
printf 'class SpiDev:\n    pass\n' > "$BUILD/goodix-fp-dump/spidev.py"
echo "   ready"

echo "== 3/4 install (needs sudo) =="
sudo env FP_SO_SRC="$BUILD/libfprint/build/libfprint" \
  bash "$REPO/scripts/install-system.sh"

echo "== 4/4 one-time sensor key (runs as you, asks before writing) =="
UDEV_GRANTED=1
sudo bash "$REPO/scripts/udev-access.sh" grant
# fprintd would hold the sensor; a plain stop is polite enough for it to switch
# its LED off.
sudo systemctl stop fprintd.service 2>/dev/null || true
rc=0
"$REPO/scripts/provision.sh" "$BUILD/goodix-fp-dump" || rc=$?
sudo bash "$REPO/scripts/udev-access.sh" revoke
UDEV_GRANTED=0
sudo systemctl restart fprintd.service 2>/dev/null || true
case "$rc" in
  0) ;;
  3) echo "WARNING: key not written; the driver will not activate until it is." >&2
     echo "         Re-run ./install.sh when you are ready to allow it." >&2 ;;
  *) echo "WARNING: key provisioning failed (exit $rc); the driver may not activate." >&2 ;;
esac
