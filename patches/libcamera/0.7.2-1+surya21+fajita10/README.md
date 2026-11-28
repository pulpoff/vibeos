# libcamera 0.7.2-1+surya21+fajita10

[+fajita9](../0.7.2-1+surya21+fajita9/) unchanged, and one patch by Pascal Garber to the soft ISP's white balance.

| Patch | What it does |
| --- | --- |
| everything in +fajita9's `series` | see there |
| `fajita-0018-ipa-simple-awb-Balance-the-frames-too-dark-to-settle.patch` | white balance: a frame too dark to settle on is shown with its own grey world estimate once green averages 2 levels above black |

Settling waits up to 30 frames for a well exposed frame. Switching to the front camera of a OnePlus 6T in a lamp-lit
room waited all 30 at the longest exposure, about 4.6 s, at gains (1, 1), and the room looked yellow-green meanwhile.
With the patch those frames are shown with their own grey world estimate, without counting towards settling, once
green averages 2 levels above black; the first well exposed frame replaces the estimate in full. The dark estimate
may be a third off, which is still far closer than no correction. The patch carries a libcamera test,
`test/ipa/soft_simple_awb.cpp`.

`series` lists all 32 in the order they were applied. They go after Debian's own `debian/patches/series`.

## Base

Debian source package `libcamera` 0.7.2-1 (`libcamera_0.7.2-1.dsc`, sha256
`b162125bb8d26641b3b71ed32d344a06ae7fb4e732043db7a081615ffd039983`).

## Rebuild

    apt-get source libcamera=0.7.2-1        # or dget the .dsc from snapshot.debian.org
    cd libcamera-0.7.2
    cp PATCHES/libcamera/0.7.2-1+surya21+fajita10/*.patch debian/patches/
    cat PATCHES/libcamera/0.7.2-1+surya21+fajita10/series >> debian/patches/series
    dch -v 0.7.2-1+surya21+fajita10 -D unstable "VibeOS: OnePlus 6T cameras, white balance of frames too dark to settle"
    dpkg-buildpackage -b -uc -us            # on arm64

## Shipped in

Not in a VibeOS image yet. Built this way, it runs on the OnePlus 6T with the kernel branch
[op6t-camera](https://github.com/JumpLink/linux-fajita/tree/op6t-camera), as +fajita1 does.

## Licence

LGPL-2.1-or-later, as the files they change, except the +surya20 changes to the BSD-2-Clause shader
`src/libcamera/shaders/bayer_1x_packed.frag`; see Debian's `debian/copyright`.

## How this set was checked

[`image/test/libcamera-awb-provisional-test.sh`](../../../image/test/libcamera-awb-provisional-test.sh) checks that the
series is +fajita9's plus the new patch, applies it to the source from snapshot.debian.org, and compiles the lines of
`Awb::process()` from the settling decision to the grey-world gains into a small harness fed six runs of frames; on
+fajita9's `awb.cpp` the same harness fails.
