# libcamera 0.7.2-1+surya21+fajita8

[+fajita7](../0.7.2-1+surya21+fajita7/) unchanged, and six patches that give the soft ISP's GPU debayer lens shading
correction: five commits of libcamera itself, cherry-picked with `-x`, and a grid-only `Lsc` algorithm for the soft ISP.

| Patch | What it does |
| --- | --- |
| everything in +fajita7's `series` | see there |
| `fajita-0011-libcamera-software_isp-Add-LSC-data-to-DebayerParams.patch` | libcamera commit: `DebayerParams` carries a shading table and its version |
| `fajita-0012-libcamera-shaders-Add-LSC-support.patch` | libcamera commit: the shaders multiply by a shading texture |
| `fajita-0013-libcamera-software_isp-Pass-LSC-availability-to-deba.patch` | libcamera commit: the debayer is told whether shading is available |
| `fajita-0014-libcamera-software_isp-egl-Add-filter-parameter-to-c.patch` | libcamera commit: texture creation takes a filter parameter |
| `fajita-0015-libcamera-software_isp-debayer_egl-Add-LSC-support.patch` | libcamera commit: the GPU debayer uploads the table and applies it |
| `fajita-0016-ipa-simple-Add-a-grid-only-LSC-algorithm.patch` | soft ISP: an `Lsc` algorithm that reads gain grids from the tuning file and interpolates them by colour temperature |

The `Lsc` algorithm reads tabular grids (17 x 17 per colour channel, for one or more colour temperatures) from its
section of the tuning file, picks or interpolates the table for the white balance's colour temperature, and hands it to
the debayer; it does not use libipa's `LscAlgorithm`. Without an `Lsc` section in the tuning file nothing changes.

On the OnePlus 6T at strength 0.8 the main camera's corners went from 0.71 to 0.95 of the centre brightness. The GPU
shader applied the tables (updated about 25 times per capture, no errors).

`series` lists all 30 in the order they were applied. They go after Debian's own `debian/patches/series`.

## Base

Debian source package `libcamera` 0.7.2-1 (`libcamera_0.7.2-1.dsc`, sha256
`b162125bb8d26641b3b71ed32d344a06ae7fb4e732043db7a081615ffd039983`).

## Rebuild

    apt-get source libcamera=0.7.2-1        # or dget the .dsc from snapshot.debian.org
    cd libcamera-0.7.2
    cp PATCHES/libcamera/0.7.2-1+surya21+fajita8/*.patch debian/patches/
    cat PATCHES/libcamera/0.7.2-1+surya21+fajita8/series >> debian/patches/series
    dch -v 0.7.2-1+surya21+fajita8 -D unstable "VibeOS: OnePlus 6T cameras, lens shading correction"
    dpkg-buildpackage -b -uc -us            # on arm64

## Shipped in

Not in a VibeOS image yet. Built this way, it runs on the OnePlus 6T with the kernel branch
[op6t-camera](https://github.com/JumpLink/linux-fajita/tree/op6t-camera), as +fajita1 does.

## Licence

LGPL-2.1-or-later, as the files they change, except the +surya20 changes to the BSD-2-Clause shader
`src/libcamera/shaders/bayer_1x_packed.frag`; see Debian's `debian/copyright`.

## How this set was checked

[`image/test/libcamera-lsc-test.sh`](../../../image/test/libcamera-lsc-test.sh) checks that the series is +fajita7's
plus the new patches, that five of them name their upstream commit, applies the series to the source from
snapshot.debian.org, compiles `Lsc::interpolate()` of the new `lsc.cpp` into a small harness fed six colour
temperatures, and checks that both shaders carry the correction (the shader cannot run on the host); on +fajita7's
source all of it fails.
