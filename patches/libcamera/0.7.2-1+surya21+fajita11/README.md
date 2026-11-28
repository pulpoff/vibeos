# libcamera 0.7.2-1+surya21+fajita11

[+fajita10](../0.7.2-1+surya21+fajita10/) unchanged, and one patch by Pascal Garber to the soft ISP's exposure.

| Patch | What it does |
| --- | --- |
| everything in +fajita10's `series` | see there |
| `fajita-0019-ipa-simple-agc-Jump-when-the-frame-is-far-darker-tha.patch` | exposure: a frame at the mean sample value's floor whose mean is below 80% of the target's jumps towards it |

The mean sample value (MSV) over five histogram bins cannot go below 1.0: with almost every pixel in the lowest bin it
no longer tells how dark the picture is. The OnePlus 6T's tuning files (in the
[kernel release](https://github.com/JumpLink/linux-fajita/releases/tag/fajita-7.4.0-rc2-2)) set exposure targets close to
that floor, 1.1 for the IMX519 and 1.3 for the IMX376, and there an all-dark frame was not far from the target: at 1.1 the error of 0.1 was
within the hysteresis and the exposure never moved; at 1.3 it rose by 1% a frame. With the patch, a frame with an MSV
below 1.05 and a mean below 80% of the target's mean jumps towards the target's mean, as a large MSV error already
did. Above the floor, and for targets of 2 and more, nothing changes. The patch carries a libcamera test,
`test/ipa/soft_simple_agc.cpp`.

`series` lists all 33 in the order they were applied. They go after Debian's own `debian/patches/series`.

## Base

Debian source package `libcamera` 0.7.2-1 (`libcamera_0.7.2-1.dsc`, sha256
`b162125bb8d26641b3b71ed32d344a06ae7fb4e732043db7a081615ffd039983`).

## Rebuild

    apt-get source libcamera=0.7.2-1        # or dget the .dsc from snapshot.debian.org
    cd libcamera-0.7.2
    cp PATCHES/libcamera/0.7.2-1+surya21+fajita11/*.patch debian/patches/
    cat PATCHES/libcamera/0.7.2-1+surya21+fajita11/series >> debian/patches/series
    dch -v 0.7.2-1+surya21+fajita11 -D unstable "VibeOS: OnePlus 6T cameras, exposure from an all-dark frame"
    dpkg-buildpackage -b -uc -us            # on arm64

## Shipped in

Not in a VibeOS image yet. Built this way, it runs on the OnePlus 6T with the kernel branch
[op6t-camera](https://github.com/JumpLink/linux-fajita/tree/op6t-camera), as +fajita1 does.

## Licence

LGPL-2.1-or-later, as the files they change, except the +surya20 changes to the BSD-2-Clause shader
`src/libcamera/shaders/bayer_1x_packed.frag`; see Debian's `debian/copyright`.

## How this set was checked

[`image/test/libcamera-agc-dark-test.sh`](../../../image/test/libcamera-agc-dark-test.sh) checks that the series is
+fajita10's plus the new patch, applies it to the source from snapshot.debian.org, and compiles
`Agc::updateExposure()` whole into a small harness fed eight runs of frames for targets 1.1, 1.3 and 2; on +fajita10's
`agc.cpp` five of them fail.
