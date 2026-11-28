# libcamera 0.7.2-1+surya21+fajita5

[+fajita4](../0.7.2-1+surya21+fajita4/) unchanged, and one patch by Loren Bufanu (Lolren) to the soft ISP's auto
exposure, from [lolren/oneplus6t-pmos-fixes](https://github.com/lolren/oneplus6t-pmos-fixes), ported by Pascal Garber
onto the +surya20 auto exposure.

| Patch | What it does |
| --- | --- |
| everything in +fajita4's `series` | see there |
| `fajita-0008-ipa-simple-Make-the-AGC-exposure-target-configurable.patch` | Agc: the exposure target comes from the `target` value of the tuning file's Agc section |

The auto exposure steers the mean sample value of its five-bin histogram to a target fixed in the code, 2.0. With the
patch it reads `target` from the tuning file, keeps 2.0 when there is none, and refuses to start when the target lies
outside 1 .. 5, the range of the histogram. The jumps of the +surya20 auto exposure aim at the mean that belongs to
the target (MSV ~ 5 * mean + 0.5) instead of a fixed 0.3. Without a tuning file nothing changes.

On the OnePlus 6T, with a target of 1.7 the main camera (IMX519) matched the stock Android photo of the same scene
(mean luma 151 against 154).

`series` lists all 22 in the order they were applied. They go after Debian's own `debian/patches/series`.

## Base

Debian source package `libcamera` 0.7.2-1 (`libcamera_0.7.2-1.dsc`, sha256
`b162125bb8d26641b3b71ed32d344a06ae7fb4e732043db7a081615ffd039983`).

## Rebuild

    apt-get source libcamera=0.7.2-1        # or dget the .dsc from snapshot.debian.org
    cd libcamera-0.7.2
    cp PATCHES/libcamera/0.7.2-1+surya21+fajita5/*.patch debian/patches/
    cat PATCHES/libcamera/0.7.2-1+surya21+fajita5/series >> debian/patches/series
    dch -v 0.7.2-1+surya21+fajita5 -D unstable "VibeOS: OnePlus 6T cameras, AGC exposure target from the tuning file"
    dpkg-buildpackage -b -uc -us            # on arm64

## Shipped in

Not in a VibeOS image yet. Built this way, it runs on the OnePlus 6T with the kernel branch
[op6t-camera](https://github.com/JumpLink/linux-fajita/tree/op6t-camera), as +fajita1 does.

## Licence

LGPL-2.1-or-later, as the files they change, except the +surya20 changes to the BSD-2-Clause shader
`src/libcamera/shaders/bayer_1x_packed.frag`; see Debian's `debian/copyright`.

## How this set was checked

[`image/test/libcamera-agc-target-test.sh`](../../../image/test/libcamera-agc-target-test.sh) checks that the series is
+fajita4's plus the new patch, applies it to the source from snapshot.debian.org, and compiles the constants,
`Agc::Agc()`, `Agc::init()` and `Agc::updateExposure()` of the patched `agc.cpp` into a small harness fed seven
tunings and frames; on +fajita4's `agc.cpp` the same harness fails.
