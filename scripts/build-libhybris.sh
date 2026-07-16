#!/bin/sh
# Run inside an Alpine AArch64 build environment.
set -eu
: "${ANDROID_HEADERS:?path to Android 9 headers}"
: "${PREFIX:=/opt/libhybris-s8}"

cd "${1:-libhybris}"
autoreconf -fiv
CPPFLAGS='-D_LARGEFILE64_SOURCE' \
CFLAGS='-O2 -std=gnu99 -Wno-int-conversion -Wno-incompatible-pointer-types -Wno-implicit-function-declaration' \
CXXFLAGS='-O2 -std=gnu++11' \
./configure \
  --prefix="$PREFIX" \
  --enable-arch=arm64 \
  --enable-experimental \
  --enable-mali-quirks \
  --enable-wayland \
  --with-default-egl-platform=x11 \
  --with-android-headers="$ANDROID_HEADERS"
make -j"$(getconf _NPROCESSORS_ONLN)"
make install
