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
  which it looks for only once, and on a `volte provision` row (see below) `qcom-volte-provision`. As a package,
  `vibeos-device-nura-<device>`.
- **Debian's builds** of the Qualcomm services Nura runs (rmtfs, tqftpserv, qrtr, pd-mapper, hexagonrpcd, qbootctl,
  81voltd), downloaded from the Debian archive and checked against its signature (gpgv, debian-archive-keyring), for
  the first boot to install offline.
- **Nothing in the images is run.** They are read as data (debugfs, mtools, Python), never mounted.

### Another kernel: `--kernel DIR`

`--kernel DIR` puts a kernel built outside Nura's image in the place of Nura's, as that kernel's release gives it. DIR
holds its `Image.gz-dtb*` (the gzipped Image with the phone's DTB appended), its modules unpacked from the release's
tar (`DIR/<kernel release>/modules.dep`...), and may hold `config-*`, a few lines of `SOURCE` (where it is from) and
the release's `SHA256SUMS`, which every file of DIR it names must match. The boot image keeps Nura's header and
command line and takes the Image.gz-dtb as its kernel section byte for byte; the payload carries DIR's modules instead
of Nura's, and `SOURCE`, the sha256 of the files and the config in `/usr/share/vibeos-device/kernel/`.

- Every module's vermagic must name the kernel's release, and every module must carry a signature that verifies
  (`openssl cms`) against a certificate built into that kernel: the modules are the ones built with it, and a kernel
  in lockdown loads them.
- A module pmOS's initramfs loads early (`initramfs.load`) must be in the kernel, built in or as a module, or the
  conversion stops. Where the kernel's tree renamed a driver, `MODULE_RENAMES` in the converter maps the old name to
  the new one (sdm845 at Linux 7.4: `qcom_spmi_haptics` is `qcom_pmi8998_haptics`, `lc898217xc` is `lc89821x`).
  Modules of pmOS's initramfs the kernel does not have are listed in the report.

### Builds of system packages: `--device-debs DIR`

`--device-debs DIR` adds builds of system-image packages made for this phone, such as its ModemManager and
NetworkManager. Each must be a package of the system image (`data/system-packages.txt`) at a newer version, and with
its dependencies in the system image or the zip. The first boot installs them with the Debian packages and holds them.

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
A `volte provision` row (the OnePlus 6T) gets `qcom-volte-provision`: for a home network it knows (so far 1&1) it
activates the modem configuration (MBN) that registers with IMS and sets the profiles VoLTE and mobile data need,
each boot, as the modem forgets them; while 81voltd is masked or missing it changes nothing. The configurations
and profiles it picks were measured on the 6T's modem, so other phones do not get it.

| Nura device | Phone | Checked |
|---|---|---|
| `oneplus-fajita` | OnePlus 6T | harness: A/B, the root as a partition (installed twice), nested and as an image file; QEMU boot: all five root kinds. Its zip is on [Releases](https://vibeos.top/releases) |
| `qcom-sm7150` with `--device xiaomi-surya --panel huaxing\|tianma` | POCO X3 NFC | harness: A-only, nested (installed twice) and partition; QEMU boot: nested |
| `oneplus-enchilada` | OnePlus 6 | converted, report read |
| `google-sargo` | Pixel 3a | converted, report read |
| `xiaomi-nabu` | Xiaomi Pad 5 | converted, report read |

None of these zips has been installed on a phone yet. QEMU boots the phone's own kernel in the "virt" machine, so it
checks the initramfs and the root search, not the phone's drivers.

Phones with a header v3 or v4 boot image (a `vendor_boot` partition) are not supported yet.

### OnePlus 6T: JumpLink's kernel 7.4

For the 6T, the converter takes the kernel [JumpLink](https://github.com/JumpLink) builds for it instead of Nura's 7.1:
release [fajita-7.4.0-rc2-2](https://github.com/JumpLink/linux-fajita/releases/tag/fajita-7.4.0-rc2-2) of
[linux-fajita](https://github.com/JumpLink/linux-fajita), its Image.gz-dtb and modules as released. The repository's CI
builds it from branch `op6t-camera`: sdm845-mainline with the 6T's commits, since release 1 among them
mojavemesa-lgtm's charger series, Lolren's fixes for the three camera sensors, the CAMSS interconnect votes from
linux-media and an ath10k RFC. Its `SOURCE` names the commit and the run, and the converter puts it into the report.
The CI's own boot image booted on one 6T by `fastboot boot`: the modem on LTE, WLAN, sound, all three cameras, a 60 s
suspend, no module rejected. The release is a pre-release: release 1 hung at about 1 boot in 9, per the contributor,
and release 2 is not counted yet.
With it go JumpLink's ModemManager and NetworkManager changes for deep sleep with the modem on
([patches/modemmanager/1.24.2-2+surya3+fajita6](../../patches/modemmanager/1.24.2-2+surya3+fajita6/) and
[patches/network-manager/1.58.1-1+fajita1](../../patches/network-manager/1.58.1-1+fajita1/)); in the contributor's
measurements on the 6T, 4 of 4 suspends of 120 s reached deep sleep with both. VoLTE stays off (`mask 81voltd.service`).
The release also has its own builds of these (ModemManager as +fajita7, #32 on top), libcamera 0.7.2-1+surya21+fajita10
(#33 to #42) and tuning files for the three sensors; the zip does not carry the last two yet.

```sh
image/nura/nura-to-vibeos --kernel KDIR --device-debs DEBS --cmdline-add fw_devlink.sync_state=timeout \
    …-oneplus-fajita-boot.img.xz …-oneplus-fajita.img.xz
```

KDIR is the release's `Image.gz-dtb-*`, `config-*`, `SOURCE` and `SHA256SUMS` with its modules tar unpacked (into
`7.4.0-rc2-sdm845-g381388ba7548/`, as the tar holds it; `SHA256SUMS` also names the release's other files, which KDIR
need not hold); DEBS the ModemManager (`modemmanager`, `libmm-glib0`, `gir1.2-modemmanager-1.0`) and NetworkManager
(`network-manager`, `libnm0`, `gir1.2-nm-1.0`, `network-manager-tui`, `network-manager-l10n`) built from those two
folders.
`fw_devlink.sync_state=timeout` is on the release's own command line: without it a provider (an interconnect, a power
domain) with a consumer that never probes keeps the bootloader's settings, and its power on.

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
- `test/volte-provision-test.sh` runs `files/qcom-volte-provision` against a stand-in `qmicli` with the 6T's
  configurations and profiles: for a 1&1 SIM the configuration, IMS and attach profiles set and the modem online once,
  nothing changed when all is so already, for another network, a modem without the configuration, or while 81voltd
  is masked or missing.

`zip-test.sh` and `qemu-boot.sh` need `NURA_WORK` (a work directory, about 20 GB), qemu-user-static with binfmt, and
`sudo -n`; the other tests need only sh, awk or python3.

Needs (Debian 12 or later): python3, xz-utils, zstd, e2fsprogs (debugfs), mtools, dpkg (dpkg-deb), zip, gpgv and
debian-archive-keyring, and openssl with `--kernel`; about 12 GB free in `--out` while it runs. No root and no loop
mounts, and it writes nothing to a phone.
