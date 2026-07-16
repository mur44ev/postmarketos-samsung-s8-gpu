#!/bin/sh
set -eu
root=${1:-/mnt/android-system}
printf '%s  %s\n' \
 '67f07575f92ea0aedb8522140a7ad08d3be201e3a07eaa5e42a7f7d751d9fac4' "$root/vendor/lib64/egl/libGLES_mali.so" \
 '919bf9f118b3116fc8c403db8e1f863c64e0d3963ff2e74f158e5e2e584a7df7' "$root/lib64/hw/gralloc.exynos5.so" | sha256sum -c -
mount | grep " on $root " | grep -q '[(,]ro[,)]' || {
  echo "refusing non-read-only SYSTEM mount" >&2
  exit 1
}
