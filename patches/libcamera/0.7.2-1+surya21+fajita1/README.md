# libcamera 0.7.2-1+surya21+fajita1

The libcamera of the OnePlus 6T (fajita): the system image's [+surya20](../0.7.2-1+surya20/) series and
[+surya21](../0.7.2-1+surya21/)'s GStreamer patch, unchanged, and four patches by Loren Bufanu (Lolren) for the
phone's three Sony sensors, from [lolren/oneplus6t-pmos-fixes](https://github.com/lolren/oneplus6t-pmos-fixes).

| Patch | What it does |
| --- | --- |
| `surya-*.patch`, `s10e-exynos9820.patch` | the +surya20 series; see there |
| `gst-disconnect-request-completed.patch` | the +surya21 patch; see there |
| `fajita-0001-libipa-camera_sensor_helper-Add-Sony-IMX371-helper.patch` | libipa: a sensor helper for the IMX371 (front): gain 1024 / (1024 - code), 10-bit black level 64 |
| `fajita-0002-ipa-libipa-Add-Sony-IMX376-helper.patch` | libipa: the same for the IMX376 (rear, second camera) |
| `fajita-0003-ipa-libipa-Add-Sony-IMX519-helper.patch` | libipa: the same for the IMX519 (rear, main camera) |
| `fajita-0004-libcamera-sensor-Add-IMX371-and-IMX376-properties.patch` | sensor properties: unit cell size and test-pattern modes of the IMX371 and IMX376 |

Without a helper the soft ISP takes the sensors' gain register codes for linear gains, and the +surya20 auto
exposure computes no usable gain: the picture stays black or swings. The gain model is the one OnePlus's IMX376 sensor
library and Raspberry Pi's IMX519 helper use; with it the auto exposure reaches the sensors' full range (16x at code
960) in the dark.

`series` lists all eighteen in the order they were applied. They go after Debian's own `debian/patches/series`.
Patch 0003 did not apply as published, because +surya20's `surya-sensor-helpers.patch` adds helpers right after
it; here its context is refreshed, and the change is the same.

## Base

Debian source package `libcamera` 0.7.2-1 (`libcamera_0.7.2-1.dsc`, sha256
`b162125bb8d26641b3b71ed32d344a06ae7fb4e732043db7a081615ffd039983`).

## Rebuild

    apt-get source libcamera=0.7.2-1        # or dget the .dsc from snapshot.debian.org
    cd libcamera-0.7.2
    cp PATCHES/libcamera/0.7.2-1+surya21+fajita1/*.patch debian/patches/
    cat PATCHES/libcamera/0.7.2-1+surya21+fajita1/series >> debian/patches/series
    dch -v 0.7.2-1+surya21+fajita1 -D unstable "VibeOS: sensor helpers for the OnePlus 6T cameras"
    dpkg-buildpackage -b -uc -us            # on arm64

## Shipped in

Not in a VibeOS image yet. `libcamera0.7`, `libcamera-ipa`, `libcamera-v4l2` and `gstreamer1.0-libcamera`
0.7.2-1+surya21+fajita1, built this way, run on the OnePlus 6T with the kernel branch
[op6t-camera](https://github.com/JumpLink/linux-fajita/tree/op6t-camera). That branch also caps the IMX371 and IMX376
gain codes at 960 (Lolren's kernel patches) and gives CAMSS its interconnect votes; without the votes, captures with
the display off stall and the next stream start can reset the SoC.

## Licence

LGPL-2.1-or-later, as the files they change, except the +surya20 changes to the BSD-2-Clause shader
`src/libcamera/shaders/bayer_1x_packed.frag`; see Debian's `debian/copyright`.

## How this set was checked

The packages were built from Debian's 0.7.2-1 source with this series, in an arm64 Debian sid container
(`dpkg-buildpackage -b`); these files are the ones that build used.
[`image/test/libcamera-fajita-test.sh`](../../../image/test/libcamera-fajita-test.sh) applies the series to the source
from snapshot.debian.org, checks that the +surya20 and +surya21 patches are the system image's unchanged, and that the
three sensors get the helper and the two the properties; on Debian's source the same checks fail.

On the phone, with the display off, twelve captures of 30 frames switching between the three cameras all delivered
frames, and captures of 180 frames reached the full exposure and gain in a dark room on all three. The front camera
delivers 4640x3448 from its full 4656x3456 mode.
