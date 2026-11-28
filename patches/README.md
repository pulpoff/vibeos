# Patched open-source packages

VibeOS ships changed builds of a few open-source packages. This folder holds the source changes of each build: one
folder per package and version, with the patches in order, a `series` file, and a README naming the source the
patches apply to, how to rebuild, which VibeOS packages and images carry the build, and the licence. Every set here
was checked against the build that made the shipped binaries; each README says how.

| Package | Version | Applies to | Shipped in | Licence |
| --- | --- | --- | --- | --- |
| [mutter](mutter/) | 51.0-3+gp1 | Debian mutter 51.0-3 | apt archive (component `mutter`), system image | GPL-2.0-or-later |
| [mutter](mutter/) (mutter-mobile) | 51.1.mobile.22 | mutter-mobile tag 51.1.mobile.22 | system image, `/opt/gnome-mobile` | GPL-2.0-or-later |
| [gnome-shell](gnome-shell/) (gnome-shell-mobile) | 51.1.mobile.22 | gnome-shell-mobile tag 51.1.mobile.22 | system image, `/opt/gnome-mobile` | GPL-2.0-or-later |
| [modemmanager](modemmanager/1.24.2-2+surya3/) | 1.24.2-2+surya3 | Debian modemmanager 1.24.2-2 | system image | GPL-2.0-or-later |
| [modemmanager](modemmanager/1.24.2-2+surya6/) | 1.24.2-2+surya6 | Debian modemmanager 1.24.2-2 | POCO X3 NFC image | GPL-2.0-or-later |
| [modemmanager](modemmanager/1.24.2-2+surya3+fajita6/) | 1.24.2-2+surya3+fajita6 | Debian modemmanager 1.24.2-2 | OnePlus 6T device zip (kernel 7.4) | GPL-2.0-or-later |
| [network-manager](network-manager/1.58.1-1+fajita1/) | 1.58.1-1+fajita1 | Debian network-manager 1.58.1-1 | OnePlus 6T device zip (kernel 7.4) | GPL-2.0-or-later |
| [libcamera](libcamera/0.7.2-1+surya20/) | 0.7.2-1+surya20 | Debian libcamera 0.7.2-1 | system image | LGPL-2.1-or-later |
| [libcamera](libcamera/0.7.2-1+surya21/) (gstreamer1.0-libcamera) | 0.7.2-1+surya21 | Debian libcamera 0.7.2-1 | system image | LGPL-2.1-or-later |
| [libcamera](libcamera/0.7.2-1+surya17/) | 0.7.2-1+surya17 | Debian libcamera 0.7.2-1 | POCO X3 NFC image | LGPL-2.1-or-later |
| [libcamera](libcamera/0.7.2-1+gts4lv1/) | 0.7.2-1+gts4lv1 | Debian libcamera 0.7.2-1 | Galaxy Tab S5e image | LGPL-2.1-or-later |
| [libcamera](libcamera/0.7.2-1+surya21+fajita1/) | 0.7.2-1+surya21+fajita1 | Debian libcamera 0.7.2-1 | not in an image yet (OnePlus 6T) | LGPL-2.1-or-later |
| [libcamera](libcamera/0.7.2-1+surya21+fajita2/) | 0.7.2-1+surya21+fajita2 | Debian libcamera 0.7.2-1 | not in an image yet (OnePlus 6T) | LGPL-2.1-or-later |
| [libcamera](libcamera/0.7.2-1+surya21+fajita3/) | 0.7.2-1+surya21+fajita3 | Debian libcamera 0.7.2-1 | not in an image yet (OnePlus 6T) | LGPL-2.1-or-later |
| [libcamera](libcamera/0.7.2-1+surya21+fajita4/) | 0.7.2-1+surya21+fajita4 | Debian libcamera 0.7.2-1 | not in an image yet (OnePlus 6T) | LGPL-2.1-or-later |
| [libcamera](libcamera/0.7.2-1+surya21+fajita5/) | 0.7.2-1+surya21+fajita5 | Debian libcamera 0.7.2-1 | not in an image yet (OnePlus 6T) | LGPL-2.1-or-later |
| [libcamera](libcamera/0.7.2-1+surya21+fajita6/) | 0.7.2-1+surya21+fajita6 | Debian libcamera 0.7.2-1 | not in an image yet (OnePlus 6T) | LGPL-2.1-or-later |
| [libcamera](libcamera/0.7.2-1+surya21+fajita7/) | 0.7.2-1+surya21+fajita7 | Debian libcamera 0.7.2-1 | not in an image yet (OnePlus 6T) | LGPL-2.1-or-later |
| [webkit2gtk](webkit2gtk/2.54.2-2+neo1/) | 2.54.2-2+neo1 | Debian webkit2gtk 2.54.2-2 | system image | BSD-2-Clause (the files changed) |
| [iio-sensor-proxy](iio-sensor-proxy/3.9-1+gts4lv3/) | 3.9-1+gts4lv3 | Debian iio-sensor-proxy 3.9-1 | Galaxy Tab S5e image, 0.1.4.3 | GPL-3 |
| [iio-sensor-proxy](iio-sensor-proxy/3.9-1+vibeos1/) | 3.9-1+vibeos1 | Debian iio-sensor-proxy 3.9-1 | Galaxy Tab S5e image, 0.1.5 | GPL-3 |
| [hexagonrpc](hexagonrpc/0.5.0-24-g40e5041/) | 0.5.0-24-g40e5041 | hexagonrpc 598b591 + upstream pull request #27 | POCO X3 NFC, Galaxy Tab S5e and Xiaomi Pad 5 device packages | GPL-3.0-or-later |

"System image" is the VibeOS system image (`vibeos-system`, 0.1.4.3 and later), which every device image is built
on. A device image installs its own builds over the system image's where the table names one.

The `mutter` and `gnome-shell` folders keep their patches at the top level: the image build scripts
(`image/build-mutter.sh`, `image/build-mobile.sh`) apply them from there.

## Built from upstream source without changes

- **libssc** 0.4.4 in the Galaxy Tab S5e device package: [libssc](https://codeberg.org/DylanVanAssche/libssc) at
  tag v0.4.4 (commit 0cf77b93b557), GPL-3.0.
- **MapLibre Native** android-v13.7.1 (commit 4cf121e515d8), linked into `vibeos-navi`: built by
  [`apps/navi/maplibre/build-maplibre.sh`](../apps/navi/maplibre/build-maplibre.sh), BSD-2-Clause and the licences of
  the libraries it bundles.
- **Vosk** 0.3.45 and **Moonshine** 0.1.6 in `vibeos-dictate-vosk` and `vibeos-dictate-moonshine`: their own
  release builds, unmodified (see `tools/vibeos-dictate-speech/`).

## Published in the apt archive

The games' engines are GPL builds with changes; their complete source is in the VibeOS apt archive next to the
binaries: `quake3-arena` (ioquake3, source package `pool/main/q/quake3-arena/`) and `generalsx` (GeneralsX,
`sources/generalsx/`: the upstream source, VibeOS's patches and build files, the build dependencies and FFmpeg).

## Kernels

Each device's kernel, with its patches and configuration, is in that device's repository:
[linux-beyond0lte](https://github.com/pulpoff/linux-beyond0lte) (Galaxy S10e),
[linux-gts4lv](https://github.com/pulpoff/linux-gts4lv) (Galaxy Tab S5e),
[linux-surya](https://github.com/pulpoff/linux-surya) (POCO X3 NFC),
[linux-r8s](https://github.com/pulpoff/linux-r8s) (Galaxy S20 FE) and
[linux-nabu](https://github.com/pulpoff/linux-nabu) (Xiaomi Pad 5). The kernel a release ships is tagged
`vibeos-<release>` there (for example `vibeos-0.1.5`): the tag's tree builds that release's kernel, modules and
devicetree, with the configuration it names.

## U-Boot

The U-Boot each device starts Linux from, as a patch series on its upstream U-Boot, with a README naming the base,
the build and how it was checked against the shipped binary. The Xiaomi Pad 5 has none: its own bootloader starts
the kernel.

| Device | Applies to | Shipped in | Licence |
| --- | --- | --- | --- |
| [Galaxy S10e](u-boot-s10e/) | [chiffathefox/u-boot](https://github.com/chiffathefox/u-boot) `exynos9820` at `dec4927b4ad5` | 0.1.4.3, 0.1.5 | GPL-2.0-or-later; see the README |
| [Galaxy Tab S5e](u-boot-s5e/) | [sm7150-mainline/u-boot](https://github.com/sm7150-mainline/u-boot) at `f8c04469e828` | 0.1.4.3, 0.1.5 | GPL-2.0-or-later; logo LGPL-3.0-or-later |
| [POCO X3 NFC](u-boot-poco/) | [sm7150-mainline/u-boot](https://github.com/sm7150-mainline/u-boot) at `f8c04469e828` | 0.1.4.3, 0.1.5 | GPL-2.0-or-later; logo LGPL-3.0-or-later |
| [Galaxy S20 FE](u-boot-s20/) | [chiffathefox/u-boot](https://github.com/chiffathefox/u-boot) at `dec4927b4ad5` | 0.1.4.3, 0.1.5 | GPL-2.0-or-later; see the README |
