#!/bin/sh
# Build the patched libhybris for the Galaxy S8 (AArch64/musl).
# Run inside an Alpine/postmarketOS AArch64 environment (device, pmbootstrap
# chroot or an aarch64 container):
#
#   ANDROID_HEADERS=/usr/include/android-9.0 scripts/build-libhybris.sh [libhybris-checkout]
#
# The checkout is cloned if missing, pinned to the commit the patch targets and
# patched if that has not happened yet. Environment overrides:
#   ANDROID_HEADERS   directory with Android 9 headers (android-version.h)  [required]
#   PREFIX            install prefix                       (default /opt/libhybris-s8)
#   DESTDIR           staging root for make install        (default empty)
#   ARCH              libhybris --enable-arch value        (default arm64)
#   ANDROID_SYSTEM    where the stock SYSTEM is mounted    (default /mnt/android-system)
#   ENABLE_WAYLAND=1  also build the Wayland platform      (not needed for X11)
#   LIBHYBRIS_COMMIT  upstream commit the patch is based on
#   JOBS              parallel make jobs                   (default: all CPUs)
set -eu

: "${ANDROID_HEADERS:?path to Android 9 headers (directory containing android-version.h)}"
: "${PREFIX:=/opt/libhybris-s8}"
: "${DESTDIR:=}"
: "${ARCH:=arm64}"
: "${ANDROID_SYSTEM:=/mnt/android-system}"
: "${ENABLE_WAYLAND:=0}"
: "${LIBHYBRIS_COMMIT:=60100a70f03d91224340d0b7e741e6f44e0f9618}"
: "${JOBS:=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"

script_dir=$(cd "$(dirname "$0")" && pwd)
patch_file=$script_dir/../patches/libhybris-android9-musl-x11.patch
src=${1:-libhybris}

fail() {
    echo "build-libhybris: $*" >&2
    exit 1
}

[ -f "$ANDROID_HEADERS/android-version.h" ] || fail "$ANDROID_HEADERS does not contain android-version.h"
[ -f "$patch_file" ] || fail "missing $patch_file"

if [ ! -d "$src" ]; then
    git clone https://github.com/libhybris/libhybris.git "$src"
fi

if [ -d "$src/.git" ]; then
    if [ "$(git -C "$src" rev-parse HEAD)" != "$LIBHYBRIS_COMMIT" ]; then
        git -C "$src" fetch -q origin "$LIBHYBRIS_COMMIT" || true
        git -C "$src" checkout -q --detach "$LIBHYBRIS_COMMIT"
    fi
    if git -C "$src" apply --check --reverse "$patch_file" >/dev/null 2>&1; then
        echo "build-libhybris: patch already applied"
    else
        git -C "$src" apply --check "$patch_file" || fail "patch does not apply to $src"
        git -C "$src" apply "$patch_file"
    fi
else
    # Plain source tree (tarball): rely on patch(1) and its reverse check.
    if patch -d "$src" -p1 -R -s --dry-run <"$patch_file" >/dev/null 2>&1; then
        echo "build-libhybris: patch already applied"
    else
        patch -d "$src" -p1 -s --dry-run <"$patch_file" || fail "patch does not apply to $src"
        patch -d "$src" -p1 -s <"$patch_file"
    fi
fi

[ -f "$src/hybris/configure.ac" ] || fail "$src does not look like a libhybris checkout"
cd "$src/hybris"

set -- \
    --prefix="$PREFIX" \
    --enable-arch="$ARCH" \
    --enable-experimental \
    --enable-mali-quirks \
    --enable-x11 \
    --with-default-egl-platform=x11 \
    --with-default-hybris-ld-library-path="$ANDROID_SYSTEM/vendor/lib64:$ANDROID_SYSTEM/lib64" \
    --with-android-headers="$ANDROID_HEADERS"
[ "$ENABLE_WAYLAND" = 1 ] && set -- "$@" --enable-wayland

autoreconf -fi
# musl >= 1.2.4 only exposes the LFS64 names with _LARGEFILE64_SOURCE; the
# -Wno-* flags keep GCC 14 from rejecting the 2020-era bionic linker sources.
CPPFLAGS='-D_LARGEFILE64_SOURCE' \
CFLAGS='-O2 -std=gnu99 -Wno-int-conversion -Wno-incompatible-pointer-types -Wno-implicit-function-declaration' \
CXXFLAGS='-O2 -std=gnu++11' \
./configure "$@"
make -j"$JOBS"
make DESTDIR="$DESTDIR" install
