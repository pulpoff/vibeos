# libcamera 0.7.2-1+surya21+fajita7

[+fajita6](../0.7.2-1+surya21+fajita6/) unchanged, and one patch by Pascal Garber to the soft ISP's contrast.

| Patch | What it does |
| --- | --- |
| everything in +fajita6's `series` | see there |
| `fajita-0010-libcamera-software_isp-Apply-contrast-after-gamma.patch` | contrast: the S-curve is applied to the gamma-encoded value, in both GPU shaders and the CPU lookup table |

The contrast S-curve pivots at 0.5. Applied in linear light, before the gamma, 0.5 is a highlight: everything below
it, most of a picture, got darker and flatter instead of gaining contrast. On the OnePlus 6T a contrast of 1.25
darkened rooms without making them look less washed out. With the patch the curve runs on the gamma-encoded value,
where 0.5 is a mid tone. The code is the one every soft-ISP device runs; it is only measured on the OnePlus 6T.

`series` lists all 24 in the order they were applied. They go after Debian's own `debian/patches/series`.

## Base

Debian source package `libcamera` 0.7.2-1 (`libcamera_0.7.2-1.dsc`, sha256
`b162125bb8d26641b3b71ed32d344a06ae7fb4e732043db7a081615ffd039983`).

## Rebuild

    apt-get source libcamera=0.7.2-1        # or dget the .dsc from snapshot.debian.org
    cd libcamera-0.7.2
    cp PATCHES/libcamera/0.7.2-1+surya21+fajita7/*.patch debian/patches/
    cat PATCHES/libcamera/0.7.2-1+surya21+fajita7/series >> debian/patches/series
    dch -v 0.7.2-1+surya21+fajita7 -D unstable "VibeOS: OnePlus 6T cameras, contrast after gamma"
    dpkg-buildpackage -b -uc -us            # on arm64

## Shipped in

Not in a VibeOS image yet. Built this way, it runs on the OnePlus 6T with the kernel branch
[op6t-camera](https://github.com/JumpLink/linux-fajita/tree/op6t-camera), as +fajita1 does.

## Licence

LGPL-2.1-or-later, as the files they change, except the +surya20 changes to the BSD-2-Clause shader
`src/libcamera/shaders/bayer_1x_packed.frag`; see Debian's `debian/copyright`.

## How this set was checked

[`image/test/libcamera-contrast-order-test.sh`](../../../image/test/libcamera-contrast-order-test.sh) checks that the
series is +fajita6's plus the new patch, applies it to the source from snapshot.debian.org, compiles
`DebayerCpu::updateGammaTable()` of the patched `debayer_cpu.cpp` into a small harness whose table is compared with
gamma first and the S-curve second at four contrast and gamma settings, and checks the order of the two lines in both
shaders; on +fajita6's source all of them fail.
