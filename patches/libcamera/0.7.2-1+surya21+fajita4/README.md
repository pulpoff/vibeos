# libcamera 0.7.2-1+surya21+fajita4

[+fajita3](../0.7.2-1+surya21+fajita3/) unchanged, and one patch by Loren Bufanu (Lolren) to the soft ISP's image
adjustment, from [lolren/oneplus6t-pmos-fixes](https://github.com/lolren/oneplus6t-pmos-fixes).

| Patch | What it does |
| --- | --- |
| everything in +fajita3's `series` | see there |
| `fajita-0007-ipa-simple-Make-image-adjustment-defaults-tunable.patch` | Adjust: gamma, contrast and saturation defaults come from the tuning file |

The soft ISP's `Adjust` algorithm started every stream with gamma 2.2, contrast 1.0 and no saturation change, fixed in
the code. With the patch it reads `gamma`, `contrast` and `saturation` from its section of the tuning file, falls back
to the old values when they are missing, and refuses to start when one lies outside the range its control accepts
(gamma 0.1 .. 10, contrast and saturation 0 .. 2). The tuned values are also the defaults the controls report and what
the stream starts with. Without a tuning file nothing changes.

`series` lists all 21 in the order they were applied. They go after Debian's own `debian/patches/series`.

## Base

Debian source package `libcamera` 0.7.2-1 (`libcamera_0.7.2-1.dsc`, sha256
`b162125bb8d26641b3b71ed32d344a06ae7fb4e732043db7a081615ffd039983`).

## Rebuild

    apt-get source libcamera=0.7.2-1        # or dget the .dsc from snapshot.debian.org
    cd libcamera-0.7.2
    cp PATCHES/libcamera/0.7.2-1+surya21+fajita4/*.patch debian/patches/
    cat PATCHES/libcamera/0.7.2-1+surya21+fajita4/series >> debian/patches/series
    dch -v 0.7.2-1+surya21+fajita4 -D unstable "VibeOS: OnePlus 6T cameras, image adjustment defaults from the tuning file"
    dpkg-buildpackage -b -uc -us            # on arm64

## Shipped in

Not in a VibeOS image yet. Built this way, it runs on the OnePlus 6T with the kernel branch
[op6t-camera](https://github.com/JumpLink/linux-fajita/tree/op6t-camera), as +fajita1 does.

## Licence

LGPL-2.1-or-later, as the files they change, except the +surya20 changes to the BSD-2-Clause shader
`src/libcamera/shaders/bayer_1x_packed.frag`; see Debian's `debian/copyright`.

## How this set was checked

[`image/test/libcamera-adjust-defaults-test.sh`](../../../image/test/libcamera-adjust-defaults-test.sh) checks that the
series is +fajita3's plus the new patch, applies it to the source from snapshot.debian.org, and compiles
`Adjust::init()` and `Adjust::configure()` of the patched `adjust.cpp` into a small harness fed six tunings; on
+fajita3's `adjust.cpp` the same harness fails.
