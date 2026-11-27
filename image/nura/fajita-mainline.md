# OnePlus 6T on a newer mainline kernel

Work in progress. The 6T's zip uses Nura's kernel (7.1). This page tracks a VibeOS root on the
sdm845-mainline `v7.4-wip` branch (7.4.0-rc2), until it is good enough for its own device stage.

## Kernel

- Base: [sdm845-mainline](https://gitlab.com/sdm845-mainline/linux) `v7.4-wip`, Nura's config plus
  `INPUT_QCOM_PMI8998_HAPTICS=m` (vibration) and `VIDEO_LC89821X=m` (the focus actuators).
- Extra commits on top: the focus actuators wired up with their `vio` supply, the 10nm DSI PLL digtop fix, and since
  2026-11-26 the fixes for calls: the tfa98xx speaker amplifier accepts a call's front end (speaker in calls)
  and the WCD934x RX0–RX2 digital gains stop at 0 dB (the earpiece clipped at PipeWire's 100 %, which was
  +40 dB). The panel's backlight callback now restores DSI low-power mode when a brightness write fails, as every
  write with the display off does. Tree: [JumpLink/linux-fajita](https://github.com/JumpLink/linux-fajita) branch
  `op6t-fixes-1126`, 17 commits on a history-less import of `v7.4-wip` (the last reverts an earlier MM1
  interconnect workaround, see Screen blanking), then `v7.4-wip`'s move to `fb1b9ff838cf` as one more commit
  (an LG panel rename and an sdm845-hdk fix, nothing for the 6T).
- Pre-release [fajita-7.4.0-rc2-1](https://github.com/JumpLink/linux-fajita/releases/tag/fajita-7.4.0-rc2-1)
  (tag at `6c315d6074fe`, the kernel in `boot_a`): boot image, `Image.gz-dtb`, modules, config, and the
  ModemManager and NetworkManager builds deep sleep needs, as arm64 debs with their patches.
- Command line: VibeOS 0.1.3's plus `fw_devlink.sync_state=timeout`.
- Test variants ran with `fastboot boot` against the installed VibeOS 0.1.3 root. They differ only in the
  command line (`module_blacklist=…`), repacked with mkbootimg: header v0, base 0, kernel offset 0x8000,
  ramdisk offset 0x1000000, tags offset 0x100, page size 4096.
- Since 2026-11-24 the kernel with these fixes lives in `boot_a` for daily use, written with `dd` from the
  running system and read back. Never switch slots with `qbootctl -s` on the 6T: it gave `boot_b` the
  GUID of `abl_b`, and the bootloader then refused both slots until the GPT attributes were repaired over EDL.

## How to watch a test kernel

A crash ends in Qualcomm's CrashDump mode, which leaves pstore empty and the journal without that boot.
Only a log streamed to the PC while it runs survives. On SDM845 the WLAN firmware runs on the modem DSP,
so the stream goes over the USB network (`vibeos-usb-net`, PR #7):
`ssh user@172.16.42.1 'sudo dmesg -w'` on the PC, written to a file.

## Status

| Area | 7.4.0-rc2 |
|---|---|
| Boot to the desktop, WLAN, USB network | works |
| Screen blanking (GNOME idle, DPMS) | fixed with `fw_devlink.sync_state=timeout` on the command line: 7.4 reset once the display went off, because the GPU's GMU node has no driver of its own and gcc/gpucc never reached `sync_state()`. With the option, 13 min display off and 5 DPMS cycles plus GNOME's blank survive; without it the first DPMS off resets. An earlier workaround kept BCM MM1 voted in the RPMh sleep set; it also kept the SoC out of deep sleep and was reverted |
| Normal reboot from `boot_a` | works, SSH after ~32 s |
| Bluetooth | works once the controller has an address: the 6T DT and bootloader give none, so the QCA chip stays "unconfigured" and BlueZ hides it. A boot service sets one derived from `androidboot.serialno` (`btmgmt public-addr`, retried until the firmware download finished) |
| Battery (bq27411), WLAN, sound cards | detected; battery reads 100 %, 4.385 V, full charge 2.43 Ah of 3.64 Ah design (aged cell). `energy-full-design` missing in DT (warning) |
| Modem | works with a SIM: LTE, registered, `connected`. The modem reads the card but opens no provisioning session by itself (ModemManager: `sim-missing`); `qcom-uim-provision` opens it before ModemManager starts ([#12](https://github.com/pulpoff/vibeos/pull/12)). The 6T-own firmware from `modem_a` behaves the same as the enchilada files. Do not stop/start the modem remoteproc: it sent the phone into Qualcomm CrashDump once |
| Calls | work, judged by ear on landline calls. CS (CSFB): both directions with #24 and #25. VoLTE: registers at boot for a 1&1 SIM with `qcom-volte-provision` (#29, on #12) and 81voltd waiting for ModemManager's modem (#28); speech both ways, the radio stays on LTE. Speaker in calls: #26, #27 and the tfa98xx kernel fix. Earpiece volume: normal with the 0 dB gain limit |
| Camera focus (lc89821x) | works: the actuators share the CCI bus whose pull-ups hang on `cam_vio_1p8`, which their node did not request (`-110` while the sensor slept). With `vio-supply` (linux-fajita `175fde03c`, `c7f666693`) focus moves on both cameras with runtime PM on |
| DSI PLL warning at probe | fixed: the clock core enabled the 10nm PLL before the PHY's digital top was powered, so the lock failed and the count went unbalanced. linux-fajita `e9ac0107b` powers digtop with the PLL bias, as on 7nm; no WARN at boot, display and touch fine |
| ramoops | the region at `0xac300000` survives CrashDump intact (read with a Sahara memory dump), but not a reboot: after a cold or warm reboot the zone headers come back with bit errors or uncorrectable, so pstore is empty. Practical path: after a panic, dump the region from CrashDump ([linux-fajita#4](https://github.com/JumpLink/linux-fajita/issues/4)) |
| Audio | playback path works (tfa98xx up, no xrun); microphone works after a fresh boot (UCM HiFi Mic1 `hw:0,1`, Mic2 `hw:0,3`, PipeWire default source has signal); the zeros seen earlier came after long uptime and did not reproduce, the dmesg "no backend DAIs" lines also appear in good runs. Vibration: works (`qcom_pmi8998_haptics`, an FF_RUMBLE effect is felt). Plymouth: to test |
| Suspend | s2idle reaches the SoC's deep sleep with a SIM and VoLTE, given two userspace fixes: NetworkManager disconnects only its own bearer on sleep (#30; before, it dropped the IMS bearer, 81voltd reconnected it and that woke the phone), and ModemManager turns the bearers' WDS event reports and the profile manager's "profile changed" events off while the phone sleeps (#31, with upstream MR !1511; each woke 4 of 4 suspends 1 ms after entry, with both off 4 of 4 suspends of 120 s ran the full time). The modem's IPCRTR channel stays a wakeup source, so calls wake the phone. Daily use: 21 min in deep sleep, an incoming call woke it and worked, about 3 % battery in 1 h 40 min. Open: a call answered from deep sleep takes a few seconds until both sides hear each other; wake by SMS untested. With the cable in during suspend, USB stays dead afterwards (dwc3 run/stop off) until the USB role is switched to `host` and back |
| Camera image | the back imx376 and the front imx371 work with Debian's libcamera 0.7.2-1; the image's `+surya20` build turns them black: without a `CameraSensorHelper` for these sensors its soft-ISP AGC computes `again nan`, holds the exposure at its minimum and the debayer gains go nan. The main imx519 (C-PHY, 3 trios) delivers only zeros, even its own test pattern, so its CSIPHY/CSID path is the open kernel part |
| Video recording | works at 1080p with x264enc; Venus fails to init its HFI on the first encoder probe and recovers, so the probe picks x264enc (PR #10) |
| Boot reliability | about 1 boot in 9 hangs 6 to 13 s in: a silent freeze after the DSPs come up, a modem SFR watchdog (`SSR`, then CrashDump), or `msm_dpu … vblank wait timed out` followed by a freeze. No Oops in any of them. Countermeasure in the root: systemd's `RuntimeWatchdogSec=20s` keeps qcom_wdt armed, `panic_on_oops=1` with `kernel.panic=5`, `download_mode=0`; a watchdog bite still lands in CrashDump, which a PC watcher leaves with a Sahara `reset` after reading ramoops, and the phone boots again on its own. Two of the hangs began with the modem crashing 1.3 s after it came up, then the system did not survive the modem's restart |
