# libcamera 0.7.2-1+surya21+fajita3

[+fajita2](../0.7.2-1+surya21+fajita2/) unchanged, and one patch by Loren Bufanu (Lolren) to the GPU debayer, from
[lolren/oneplus6t-pmos-fixes](https://github.com/lolren/oneplus6t-pmos-fixes).

| Patch | What it does |
| --- | --- |
| everything in +fajita2's `series` | see there |
| `fajita-0006-libcamera-software_isp-Align-EGL-statistics-with-output-crop.patch` | GPU debayer: the statistics cover the part of the sensor frame the picture shows |

The GPU debayer scales the whole frame down, keeping its aspect ratio, and clips what does not fit the output. The
statistics that auto exposure, white balance and autofocus run on were still taken from a block of the output's size
in the frame's top left corner: for the OnePlus 6T's second rear camera at 720p, 1280x720 of a 2592x1940 frame, a
fifth of it. The exposure followed whatever was in that corner, and the autofocus, which measures the middle third of
the statistics window, focused on a point left of and above the middle of the picture. With the patch the window is
what the picture takes from the frame (2588x1455 there). The debayer code is the one every device with the GPU soft
ISP runs; it is only measured on the OnePlus 6T.

`series` lists all twenty in the order they were applied. They go after Debian's own `debian/patches/series`.

## Base

Debian source package `libcamera` 0.7.2-1 (`libcamera_0.7.2-1.dsc`, sha256
`b162125bb8d26641b3b71ed32d344a06ae7fb4e732043db7a081615ffd039983`).

## Rebuild

    apt-get source libcamera=0.7.2-1        # or dget the .dsc from snapshot.debian.org
    cd libcamera-0.7.2
    cp PATCHES/libcamera/0.7.2-1+surya21+fajita3/*.patch debian/patches/
    cat PATCHES/libcamera/0.7.2-1+surya21+fajita3/series >> debian/patches/series
    dch -v 0.7.2-1+surya21+fajita3 -D unstable "VibeOS: OnePlus 6T cameras, statistics over the visible picture"
    dpkg-buildpackage -b -uc -us            # on arm64

## Shipped in

Not in a VibeOS image yet. Built this way, it runs on the OnePlus 6T with the kernel branch
[op6t-camera](https://github.com/JumpLink/linux-fajita/tree/op6t-camera), as +fajita1 does.

## Licence

LGPL-2.1-or-later, as the files they change, except the +surya20 changes to the BSD-2-Clause shader
`src/libcamera/shaders/bayer_1x_packed.frag`; see Debian's `debian/copyright`.

## How this set was checked

[`image/test/libcamera-stats-window-test.sh`](../../../image/test/libcamera-stats-window-test.sh) checks that the
series is +fajita2's plus the new patch, applies it to the source from snapshot.debian.org, and compiles the lines of
`DebayerEGL::configure()` that set the statistics window into a small harness fed four of the 6T's modes; on
+fajita2's `debayer_egl.cpp` all four fail.
