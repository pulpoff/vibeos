# libcamera 0.7.2-1+surya21+fajita6

[+fajita5](../0.7.2-1+surya21+fajita5/) unchanged, and one patch by Pascal Garber to the soft ISP's white balance.

| Patch | What it does |
| --- | --- |
| everything in +fajita5's `series` | see there |
| `fajita-0009-ipa-simple-awb-Settle-on-a-well-exposed-frame.patch` | white balance: the first estimate settles on a frame whose green averages at least 24 levels above black |

The near-neutral refinement only counts pixels that look grey under the gains in use, so with the gains more than 25 %
off the true greys drop out and the remaining pixels confirm the wrong gains. The auto exposure starts from its
shortest exposure, and the first estimates were taken from frames a few levels above black, where a black level off by
one level moves the ratios by a third. On the OnePlus 6T's second rear camera that settled at a blue gain of 1.27
where a well exposed frame gives 1.75, and the camera stayed yellow-green. With the patch settling waits for a frame
whose green averages at least 24 levels above black, or for 30 frames of a scene that stays dark; only estimates that
were applied count towards settling. When few pixels are neutral and grey world disagrees by more than the near-neutral
window for 30 frames, it settles anew from grey world. The debug log now shows the level and the share of neutral
pixels with the gains. The code is the +surya20 white balance every soft-ISP device runs; it is only measured on the
OnePlus 6T.

`series` lists all 23 in the order they were applied. They go after Debian's own `debian/patches/series`.

## Base

Debian source package `libcamera` 0.7.2-1 (`libcamera_0.7.2-1.dsc`, sha256
`b162125bb8d26641b3b71ed32d344a06ae7fb4e732043db7a081615ffd039983`).

## Rebuild

    apt-get source libcamera=0.7.2-1        # or dget the .dsc from snapshot.debian.org
    cd libcamera-0.7.2
    cp PATCHES/libcamera/0.7.2-1+surya21+fajita6/*.patch debian/patches/
    cat PATCHES/libcamera/0.7.2-1+surya21+fajita6/series >> debian/patches/series
    dch -v 0.7.2-1+surya21+fajita6 -D unstable "VibeOS: OnePlus 6T cameras, white balance settles on a well exposed frame"
    dpkg-buildpackage -b -uc -us            # on arm64

## Shipped in

Not in a VibeOS image yet. Built this way, it runs on the OnePlus 6T with the kernel branch
[op6t-camera](https://github.com/JumpLink/linux-fajita/tree/op6t-camera), as +fajita1 does.

## Licence

LGPL-2.1-or-later, as the files they change, except the +surya20 changes to the BSD-2-Clause shader
`src/libcamera/shaders/bayer_1x_packed.frag`; see Debian's `debian/copyright`.

## How this set was checked

[`image/test/libcamera-awb-settle-test.sh`](../../../image/test/libcamera-awb-settle-test.sh) checks that the series is
+fajita5's plus the new patch, applies it to the source from snapshot.debian.org, and compiles the lines of
`Awb::process()` from the settling decision to the grey-world gains into a small harness fed six runs of frames; on
+fajita5's `awb.cpp` the same harness fails.
