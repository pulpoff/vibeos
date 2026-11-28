# libcamera 0.7.2-1+surya21+fajita9

[+fajita8](../0.7.2-1+surya21+fajita8/) unchanged, and one patch by Pascal Garber to the soft ISP: it corrects the Sony
IMX376's static phase-detection pixels.

| Patch | What it does |
| --- | --- |
| everything in +fajita8's `series` | see there |
| `fajita-0017-libcamera-software_isp-Correct-static-phase-detectio.patch` | soft ISP: phase-detection pixels described per sensor are replaced by the mean of their same-colour neighbours before statistics and debayering |

The IMX376 delivers its phase-detection pixels uncorrected: eight sites in every 16x16 tile, all on blue sites, which
the sensor cannot be told to correct. On the OnePlus 6T they read 3.4x their neighbours. The statistics sample the
frame sparsely, so these pixels weigh heavily in the blue average: grey world measured a blue gain of 2.83 with them
against 3.68 without, which is the yellow-green cast; the debayered picture also shows a faint grid of dots. The patch
adds `PhaseDetectionPixels` to `CameraSensorProperties` (valid only for the output size they were measured on) and a
`PdafPixelCorrector` that replaces each site, in place, by the rounded mean of its in-frame same-colour neighbours two
pixels away. It handles 10-bit CSI-2 packed, 8-bit and 16-bit container raw, is precomputed at configure time and
runs in `Debayer::process()` for both the CPU and the GPU debayer. The patch carries a libcamera test,
`test/pdaf-pixels.cpp`; its `test/meson.build` hunk is adjusted to apply to Debian's source, which comments out the
shared-fd test. After the fix the cast is gone.

`series` lists all 31 in the order they were applied. They go after Debian's own `debian/patches/series`.

## Base

Debian source package `libcamera` 0.7.2-1 (`libcamera_0.7.2-1.dsc`, sha256
`b162125bb8d26641b3b71ed32d344a06ae7fb4e732043db7a081615ffd039983`).

## Rebuild

    apt-get source libcamera=0.7.2-1        # or dget the .dsc from snapshot.debian.org
    cd libcamera-0.7.2
    cp PATCHES/libcamera/0.7.2-1+surya21+fajita9/*.patch debian/patches/
    cat PATCHES/libcamera/0.7.2-1+surya21+fajita9/series >> debian/patches/series
    dch -v 0.7.2-1+surya21+fajita9 -D unstable "VibeOS: OnePlus 6T cameras, static phase-detection pixel correction"
    dpkg-buildpackage -b -uc -us            # on arm64

## Shipped in

Not in a VibeOS image yet. Built this way, it runs on the OnePlus 6T with the kernel branch
[op6t-camera](https://github.com/JumpLink/linux-fajita/tree/op6t-camera), as +fajita1 does.

## Licence

LGPL-2.1-or-later, as the files they change, except the +surya20 changes to the BSD-2-Clause shader
`src/libcamera/shaders/bayer_1x_packed.frag`; see Debian's `debian/copyright`.

## How this set was checked

[`image/test/libcamera-pdaf-pixels-test.sh`](../../../image/test/libcamera-pdaf-pixels-test.sh) checks that the series
is +fajita8's plus the new patch, applies it to the source from snapshot.debian.org, and compiles the patch's own
`pdaf_pixels.cpp` with plain `c++` against a few mock libcamera headers into a harness that corrects a frame whose
sites are 1.7x too bright, in three raw formats, and checks two cases it must leave alone; on +fajita8's source, which
has no `pdaf_pixels.cpp`, all of them fail.
