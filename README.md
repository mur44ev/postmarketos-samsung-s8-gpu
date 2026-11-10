# Galaxy S8 · Mali-G71 on postmarketOS

> **Short version:** use the phone's matching Android 9 `r16p0` blobs through patched libhybris; fix musl TLS key `0`, Samsung gralloc1 ownership, Android 9 `ANativeWindow`, and X11 buffer presentation. The command-mode AMOLED additionally needs a 60 Hz `pan` commit pump.

[![CI](https://github.com/mur44ev/postmarketos-samsung-s8-gpu/actions/workflows/ci.yml/badge.svg)](https://github.com/mur44ev/postmarketos-samsung-s8-gpu/actions/workflows/ci.yml)

## Known-good result

| | Result |
|---|---|
| GPU | ARM Mali-G71 MP20, EGL 1.4 Bifrost `r16p0`, GLES 3.2 |
| X11 cube | **3600 frames / 60.000 s = 60.00 FPS**, p95 18.434 ms |
| GLX via gl4es | 137.26 FPS, `GL_ERROR=0` |
| Health | 0 reset, 0 MMU fault; SSH/server workloads stayed online |
| UI | SXMO mobile shell, 1440×2960 portrait, touch gestures |

Measured on 2026-07-16 with the first revision of the patch; see [`evidence/known-good.txt`](evidence/known-good.txt) and [Patch revisions](#patch-revisions).

## What changed

1. Mount stock `SYSTEM` **read-only** and verify the two proprietary inputs with [`scripts/verify-stock-inputs.sh`](scripts/verify-stock-inputs.sh):
   - `libGLES_mali.so` — `67f07575f92ea0aedb8522140a7ad08d3be201e3a07eaa5e42a7f7d751d9fac4`
   - `gralloc.exynos5.so` — `919bf9f118b3116fc8c403db8e1f863c64e0d3963ff2e74f158e5e2e584a7df7`
2. Apply [`patches/libhybris-android9-musl-x11.patch`](patches/libhybris-android9-musl-x11.patch) to libhybris `60100a7` and build for AArch64/musl with Android 9 headers ([`scripts/build-libhybris.sh`](scripts/build-libhybris.sh) does all of it).
3. Launch GLES programs with [`scripts/s8-mali-run`](scripts/s8-mali-run); optional GLX programs use gl4es.
4. Run [`scripts/s8-frame-pump.c`](scripts/s8-frame-pump.c) at 60 Hz (shipped with an OpenRC service). Samsung DECON otherwise displays only one committed frame even while X11 screenshots keep changing.

## Build and install

Everything below runs on the phone, in a `pmbootstrap` chroot, or in any AArch64 Alpine environment (CI does exactly this in an `alpine:3.21` container on an arm64 runner).

```sh
apk add build-base autoconf automake libtool pkgconf linux-headers bsd-compat-headers \
        git patch libx11-dev libxcb-dev libxext-dev

# Android 9 headers: the Halium set works, or generate your own with
# libhybris' utils/extract-headers.sh from a matching AOSP/Lineage 16 tree.
git clone --depth 1 -b halium-9.0 https://github.com/Halium/android-headers.git

# Clones libhybris, pins it to the commit the patch targets, applies the
# patch, configures with --enable-x11 and installs to /opt/libhybris-s8.
ANDROID_HEADERS=$PWD/android-headers scripts/build-libhybris.sh libhybris

# Frame pump, launcher and OpenRC service (needs root).
make -C scripts install
rc-update add s8-frame-pump default && rc-service s8-frame-pump start
```

`build-libhybris.sh` honours `PREFIX`, `DESTDIR`, `ARCH`, `ANDROID_SYSTEM`, `JOBS` and `ENABLE_WAYLAND=1`; the X11 platform itself no longer needs Wayland.

## Running GLES programs

```sh
scripts/verify-stock-inputs.sh /mnt/android-system   # hashes + read-only mount
s8-mali-run test_egl                                  # any EGL/GLES client
```

The launcher refuses to start unless `SYSTEM` is mounted, libhybris is installed with the X11 platform and the user can open `/dev/mali0` and `/dev/ion` read-write (video group). It exports:

| Variable | Purpose |
|---|---|
| `HYBRIS_LD_LIBRARY_PATH` | where the Android linker finds the blobs (`vendor/lib64`, `lib64` of the mounted `SYSTEM`) |
| `HYBRIS_EGLPLATFORM=x11`, `HYBRIS_EGLPLATFORM_DIR` | select the X11 platform from this build |
| `HYBRIS_ANDROID_SDK_VERSION=28` | pick the Android 9 linker without reading Android properties |
| `HYBRIS_FORCE_LEGACY_PROPERTIES=1` | keep libhybris' property hooks for Samsung's Android 9 blobs |
| `HYBRIS_GRALLOC1_RELEASE_IMPLY_DELETE=1` | Exynos gralloc1 already deletes released handles; avoids a double free |
| `HYBRIS_PTHREAD_KEY_ZERO_VALID=1` | musl may hand out TLS key 0, which Mali uses for its current context |
| `LIBEGL`, `LIBGLESV1`, `LIBGLESV2` | all three APIs live in `libGLES_mali.so` |

Debugging knobs understood by the patched libhybris: `HYBRIS_WINDOW_DEBUG=1` (trace every buffer/query operation), `HYBRIS_X11_DISABLE_SHM=1` (use `XPutImage` instead of MIT-SHM, e.g. over a remote display), `HYBRIS_X11_DUMP_BUFFERS=1` (dump every queued buffer to a file), `HYBRIS_X11_FORCE_WIDTH` / `HYBRIS_X11_FORCE_HEIGHT`.

## Patch revisions

The patch is a plain `git diff` against libhybris commit `60100a70f03d91224340d0b7e741e6f44e0f9618` (2020-04-29); CI checks that it still applies and builds it for aarch64/musl.

- **v1 (2026-07-16)** — the revision behind the measurements above. It could not be rebuilt from this repository alone: it `#include`d `hybris/common/musl_compat.h` (the `TEMP_FAILURE_RETRY` shim from postmarketOS' old libhybris package) without shipping it.
- **v2 (current)** — adds the missing header and fixes bugs found while reviewing the X11 platform: undefined behaviour in `eglSwapBuffers` when no frame was drawn (`std::deque::front()` on an empty queue), presenting cancelled buffers, every second buffer leaked on window teardown, an off-by-one in `setBufferCount`, a dangling last-buffer pointer after reallocation, MIT-SHM segments that outlived crashed clients (`IPC_RMID`), XImage/GC/visual-info leaks, unchecked `gralloc_lock`, heap overflow risk when the window is resized, the truncated EGL extension string (Mali's list exceeds the old 1 KiB buffer), and `getenv()` on the GL hot path. The platform now has a proper `--enable-x11` configure switch with pkg-config detection, no longer depends on Wayland, and the upstream test list is kept (only `test_camera` is gated on Wayland). v2 is compile-verified on aarch64/musl (CI) and x86-64 musl/glibc; the 60 FPS figures above have **not yet been re-measured** with it — rerun the cube test after rebuilding and update `evidence/known-good.txt`.

## Important

- **No blobs, boot images, dumps, tokens, or device secrets are in this repository.** Extract blobs from your own matching firmware.
- Xorg remains fbdev because the downstream 4.4 kernel has no DRM node. Native EGL/GLES windows are accelerated; XFCE/SXMO 2D composition is not DRI accelerated.
- Do not open and close `/dev/fb0` casually: this Samsung driver calls `decon_release()` and sleeps the panel. Keep it root-only. The frame pump only touches the sysfs `pan` attribute.
- Internal ABOX audio is not part of this GPU fix; the archived driver rejects the available Calliope firmware.

Full measured evidence: [`evidence/known-good.txt`](evidence/known-good.txt).
