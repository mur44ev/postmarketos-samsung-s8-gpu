#!/bin/sh
# Check the two proprietary inputs against the known-good hashes and make sure
# the stock SYSTEM is mounted read-only.
#
#   verify-stock-inputs.sh [/mnt/android-system]
set -eu

root=${1:-/mnt/android-system}
root=${root%/}

printf '%s  %s\n' \
 '67f07575f92ea0aedb8522140a7ad08d3be201e3a07eaa5e42a7f7d751d9fac4' "$root/vendor/lib64/egl/libGLES_mali.so" \
 '919bf9f118b3116fc8c403db8e1f863c64e0d3963ff2e74f158e5e2e584a7df7' "$root/lib64/hw/gralloc.exynos5.so" | sha256sum -c -

# /proc/mounts is available everywhere (busybox has no findmnt); the last
# matching entry is the effective mount.
opts=$(awk -v r="$root" '$2 == r { o = $4 } END { print o }' /proc/mounts)
[ -n "$opts" ] || {
    echo "verify-stock-inputs: $root is not a mount point" >&2
    exit 1
}
case ",$opts," in
    *,ro,*) ;;
    *)
        echo "verify-stock-inputs: refusing non-read-only SYSTEM mount ($opts)" >&2
        exit 1
        ;;
esac
echo "verify-stock-inputs: $root is read-only"
