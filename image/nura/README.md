# nura-to-vibeos

A VibeOS device zip from a [Nura](https://nura.eco) (postmarketOS) device build. Nura builds images for many
mainline phones, in several flavours (Phosh, GNOME Mobile, Plasma Mobile, Sxmo). What makes a phone work is the same
in all of them: the kernel and its device tree, the modules, the firmware, and the device's settings for audio,
sensors, the modem and the GPU. The converter takes that part and leaves the rest: Phosh, or whichever shell the build
has, and all of postmarketOS's Alpine user space stay behind. VibeOS brings its own, on Debian, in the system zip.

```sh
make -C image/nura/initramfs                         # once: bin/vibeos-loop for the initramfs
image/get-update-binary.sh lineage-22.2-…-signed.zip # once: LineageOS's updater, for the zip
image/nura/nura-to-vibeos https://images.nura.eco/bpo/edge/oneplus-fajita/phosh/20261114-0517/
```

Give it a build's folder at [images.nura.eco/bpo/edge](https://images.nura.eco/bpo/edge/)`/<device>/<flavour>/<build>/`,
or its two downloaded files (`…-boot.img.xz` and `….img.xz`). A URL's downloads are checked against the listing's
sha256 and kept in `OUT/nura-download/`.

It writes, in `--out` (default: the current directory):

| | |
|---|---|
| `vibeos-device-<device>_<build>.zip` | the device zip, installed from LineageOS's recovery right after the VibeOS system zip |
| `vibeos-device-<device>_<build>-boot.img` | its boot image, for a first start with `fastboot boot` that writes nothing |
| `vibeos-device-<device>_<build>.txt` | the report: inputs and their sha256, the boot image, every file carried over, and what was not |

## What it does

- **Boot image**: Nura's kernel and DTB byte for byte, with the boot image header Nura uses (version, addresses,
  page size) and the kernel command line it needs, minus postmarketOS's own parameters. postmarketOS's initramfs is
  replaced by VibeOS's (`initramfs/init`): busybox, `vibeos-loop`, the modules and firmware the early boot needs. It
  finds the VibeOS root (a partition named `linux` or `vibeos`, the root inside a `linux` partition's own GPT, or
  `/lost+found/vibeos/rootfs.img` on Android's data) and starts it. `vibeos.debug=1` on the command line starts a USB
  network and a telnet shell first (172.16.42.1).
- **Payload**: the kernel's modules (each one's vermagic checked), all the device's firmware, and the device's
  settings in the form a Debian/systemd system reads: ALSA UCM, udev rules and hwdb, modprobe and modules-load files,
  UPower, WirePlumber, feedbackd themes, the sensors' mount matrix, hexagonrpcd's firmware directory, and the units
  postmarketOS enables or disables. With 81voltd (VoLTE) also a drop-in that has it wait for ModemManager's modem,
  which it looks for only once. As a package, `vibeos-device-nura-<device>`.
- **Debian's builds** of the Qualcomm services Nura runs (rmtfs, tqftpserv, qrtr, pd-mapper, hexagonrpcd, qbootctl,
  81voltd), downloaded from the Debian archive and checked against its signature (gpgv, debian-archive-keyring), for
  the first boot to install offline.
- **Nothing in the images is run.** They are read as data (debugfs, mtools, Python), never mounted.

Replaced: `q6voiced` (call audio on Qualcomm phones) by `vibeos-q6voiced`, which opens the voice PCM while a
ModemManager call is live; without it a call connects and stays silent both ways. `msm-modem-uim-selection` (the
SIM's provisioning session) by `qcom-uim-provision`, which opens that session when the modem left it closed, as
Android's RIL would; without it the 6T's modem sees the card and ModemManager reports `sim-missing`. It needs
`qmicli` (libqmi-utils) in the system image.

Not carried, because Debian has no package for them and Alpine binaries cannot run on Debian: `bootmac` (Wi-Fi and Bluetooth addresses; the payload's `vibeos-bt-addr` and `vibeos-wlan-addr` set both from the boot
serial), `swclock-offset`. The report lists what was left out for the build you converted.

## In recovery

The zip checks that the phone is the one it is for (`data/devices.txt`, or the part of Nura's device name after the
vendor; `--android-device NAMES` or `any` changes that), then asks where the boot image goes: this slot's boot (A/B
phones; recovery on the others), or nowhere. The partition it writes is saved first, into the VibeOS root at
`/var/lib/vibeos/device/backup/`. `--boot-target` fixes the answer in the zip.

**Nowhere** is the safe first try: the payload goes into the VibeOS root and no boot partition is written. Then
`fastboot boot vibeos-device-…-boot.img` starts VibeOS once. If it comes up, install the device zip again and choose
the boot partition.

## Phones

`data/devices.txt` holds what the converter cannot read from an image: the LineageOS device names, and for a
generic SoC image (Nura's `qcom-sm7150`, which U-Boot and systemd-boot start, so it has no boot.img) the phone's DTB,
the boot image header its bootloader expects, and the panels it was sold with.
A `watchdog reset` row (the OnePlus 6T) also gets two systemd drop-ins: the hardware watchdog resets a reboot that
hangs in the modem shutdown path, and rmtfs gets 15 s to stop instead of systemd's default 90 s.
A `modemwake settle` row (the OnePlus 6T) gets a systemd-sleep hook: the modem may wake the phone for an incoming
call, and WLAN goes down before the suspend, because its QMI traffic runs through the modem and would abort it.

| Nura device | Phone | Checked |
|---|---|---|
| `oneplus-fajita` | OnePlus 6T | harness: A/B, the root as a partition (installed twice), nested and as an image file; QEMU boot: all five root kinds. Its zip is on [Releases](https://vibeos.top/releases). A newer mainline kernel: [fajita-mainline.md](fajita-mainline.md) |
| `qcom-sm7150` with `--device xiaomi-surya --panel huaxing\|tianma` | POCO X3 NFC | harness: A-only, nested (installed twice) and partition; QEMU boot: nested |
| `oneplus-enchilada` | OnePlus 6 | converted, report read |
| `google-sargo` | Pixel 3a | converted, report read |
| `xiaomi-nabu` | Xiaomi Pad 5 | converted, report read |

None of these zips has been installed on a phone yet. QEMU boots the phone's own kernel in the "virt" machine, so it
checks the initramfs and the root search, not the phone's drivers.
Phones with a header v3 or v4 boot image (a `vendor_boot` partition) are not supported yet.

## Tests

- `test/zip-test.sh DEVZIP LAYOUT KIND [SLOT] [RUNS]` runs a device zip with its own update-binary in a chroot of
  LineageOS recovery's ramdisk (qemu-user), on a fake UFS disk holding what the system zip would have left: `ab`
  (boot_a and boot_b) or `aonly` (boot and recovery), and the root as a partition, nested in a partition's own GPT,
  or an image file in Android's data. It checks the boot partition written, the backup, the other slot and every
  other partition untouched. `RUNS=2` installs twice: the backup must stay the first one's.
- `test/qemu-boot.sh BOOT.img KIND` boots the boot image's kernel and initramfs in qemu-system-aarch64 against a
  stand-in root, to check that the initramfs finds the root and switches to it.
- `test/compare-boot.py` compares a converted boot image with Nura's, field by field.
- `test/uim-provision-test.sh` runs `files/qcom-uim-provision` against a stand-in `qmicli` with the 6T's card
  status: the session opened on the USIM's slot and AID, nothing done with a session open, no card or no USIM; it
  stops at the modem's first answer when no slot has a card, and keeps asking while the modem gives none.
- `test/voltd-wait-test.sh` runs the wait of `files/81voltd-wait-modem.conf` against a stand-in `mmcli`: it returns
  once the modem is listed and gives up after 90 s, letting 81voltd start anyway.

`zip-test.sh` and `qemu-boot.sh` need `NURA_WORK` (a work directory, about 20 GB), qemu-user-static with binfmt, and
`sudo -n`; the other tests need only sh, awk or python3.

Needs (Debian 12 or later): python3, xz-utils, zstd, e2fsprogs (debugfs), mtools, dpkg (dpkg-deb), zip, gpgv and
debian-archive-keyring; about 12 GB free in `--out` while it runs. No root and no loop mounts, and it writes nothing
to a phone.
