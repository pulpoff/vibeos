# libcamera 0.7.2-1+surya21+fajita2

[+fajita1](../0.7.2-1+surya21+fajita1/) unchanged, and one patch to the soft ISP's white balance.

| Patch | What it does |
| --- | --- |
| everything in +fajita1's `series` | see there |
| `fajita-0005-ipa-simple-awb-Keep-the-gains-in-a-dark-frame.patch` | white balance: no new gains from a frame whose green averages less than one level above the black level; red and blue gains clamped to 1/4 .. 4 |

In a dim room the first frames of a stream, and a dark scene at the longest exposure, lie within a level of the black
level. Green above black then rounds down to the floor of 1 the code keeps against a division by zero, while red or
blue keep a few levels of noise, and the grey-world ratio came out as a blue gain of 0.0001 and a colour temperature
of 1700 K. The +surya20 white balance moves only 30 % a frame towards its estimate, so the wrong colours lasted
seconds after the exposure had come up. Only the upper end of the gains was clamped (4); the lower one now is too.
The code is the +surya20 white balance every soft-ISP device runs; it is only measured on the OnePlus 6T.

`series` lists all nineteen in the order they were applied. They go after Debian's own `debian/patches/series`.

## Base

Debian source package `libcamera` 0.7.2-1 (`libcamera_0.7.2-1.dsc`, sha256
`b162125bb8d26641b3b71ed32d344a06ae7fb4e732043db7a081615ffd039983`).

## Rebuild

    apt-get source libcamera=0.7.2-1        # or dget the .dsc from snapshot.debian.org
    cd libcamera-0.7.2
    cp PATCHES/libcamera/0.7.2-1+surya21+fajita2/*.patch debian/patches/
    cat PATCHES/libcamera/0.7.2-1+surya21+fajita2/series >> debian/patches/series
    dch -v 0.7.2-1+surya21+fajita2 -D unstable "VibeOS: OnePlus 6T cameras, white balance in a dark frame"
    dpkg-buildpackage -b -uc -us            # on arm64

## Shipped in

Not in a VibeOS image yet. Built this way, it runs on the OnePlus 6T with the kernel branch
[op6t-camera](https://github.com/JumpLink/linux-fajita/tree/op6t-camera), as +fajita1 does.

## Licence

LGPL-2.1-or-later, as the files they change, except the +surya20 changes to the BSD-2-Clause shader
`src/libcamera/shaders/bayer_1x_packed.frag`; see Debian's `debian/copyright`.

## How this set was checked

[`image/test/libcamera-awb-dark-test.sh`](../../../image/test/libcamera-awb-dark-test.sh) checks that the series is
+fajita1's plus the new patch, applies it to the source from snapshot.debian.org, and compiles the gain computation
of the patched `awb.cpp` into a small harness fed the channel sums of a dark, an ordinary and a strongly red frame;
on +fajita1's `awb.cpp` the same harness fails.
