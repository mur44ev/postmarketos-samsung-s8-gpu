# Galaxy S8 · Mali‑G71 on postmarketOS

> **Short version:** use the phone's matching Android 9 `r16p0` blobs through patched libhybris; fix musl TLS key `0`, Samsung gralloc1 ownership, Android 9 `ANativeWindow`, and X11 buffer presentation. The command‑mode AMOLED additionally needs a 60 Hz `pan` commit pump.

## Known-good result

| | Result |
|---|---|
| GPU | ARM Mali‑G71 MP20, EGL 1.4 Bifrost `r16p0`, GLES 3.2 |
| X11 cube | **3600 frames / 60.000 s = 60.00 FPS**, p95 18.434 ms |
| GLX via gl4es | 137.26 FPS, `GL_ERROR=0` |
| Health | 0 reset, 0 MMU fault; SSH/server workloads stayed online |
| UI | SXMO mobile shell, 1440×2960 portrait, touch gestures |

## What changed

1. Mount stock `SYSTEM` **read-only** and verify the two proprietary inputs:
   - `libGLES_mali.so` — `67f07575f92ea0aedb8522140a7ad08d3be201e3a07eaa5e42a7f7d751d9fac4`
   - `gralloc.exynos5.so` — `919bf9f118b3116fc8c403db8e1f863c64e0d3963ff2e74f158e5e2e584a7df7`
2. Apply [`patches/libhybris-android9-musl-x11.patch`](patches/libhybris-android9-musl-x11.patch) and build for AArch64/musl with Android 9 headers.
3. Launch GLES programs with [`scripts/s8-mali-run`](scripts/s8-mali-run); optional GLX programs use gl4es.
4. Run [`scripts/s8-frame-pump.c`](scripts/s8-frame-pump.c) at 60 Hz. Samsung DECON otherwise displays only one committed frame even while X11 screenshots keep changing.

## Important

- **No blobs, boot images, dumps, tokens, or device secrets are in this repository.** Extract blobs from your own matching firmware.
- Xorg remains fbdev because the downstream 4.4 kernel has no DRM node. Native EGL/GLES windows are accelerated; XFCE/SXMO 2D composition is not DRI accelerated.
- Do not open and close `/dev/fb0` casually: this Samsung driver calls `decon_release()` and sleeps the panel. Keep it root-only.
- Internal ABOX audio is not part of this GPU fix; the archived driver rejects the available Calliope firmware.

Full measured evidence: [`evidence/known-good.txt`](evidence/known-good.txt).
