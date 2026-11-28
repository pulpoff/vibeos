# ModemManager 1.24.2-2+surya3+fajita7

The system image's [1.24.2-2+surya3](../1.24.2-2+surya3/) with twelve patches more: eight fixes taken unchanged
from upstream ModemManager, three that keep the modem from waking a sleeping phone, two of them an open upstream
merge request, and one that reports a data bearer's MTU the link can carry.

| Patch | What it does |
| --- | --- |
| `0001-qmi-retry-answer-while-call-in-setup.patch` | the system image's +surya3, byte for byte |
| `0002-generic-net-port-cgact.patch` | the system image's +surya3, byte for byte |
| `0003-generic-net-port-data.patch` | the system image's +surya3, byte for byte |
| `0004-base-manager-fix-cleanup-of-multiplexed-bearers.patch` | upstream `0edcb916ad2b`: the assert when several multiplexed bearers are cleaned up |
| `0005-netlink-fix-use-after-free-calling-completion_fn.patch` | upstream `9317cbc4702c`: a use-after-free in the netlink transaction completion |
| `0006-modemmanager-handle-qmi-dms-operating-mode-shuttin.patch` | upstream `31cbf9c1bef0`: handle the QMI DMS operating mode "shutting down" |
| `0007-base-manager-fix-use-after-free-of-polkit-authenti.patch` | upstream `f994d6067645`: a use-after-free of the polkit authentication |
| `0008-shared-qmi-fix-uaf-on-duplicate-list-configs-indic.patch` | upstream `46a91399ca18`: a use-after-free on duplicate list-configs indications |
| `0009-ifaces-fix-uafs-in-signal-handlers-when-hot-unplug.patch` | upstream `2b1aaca4a0f7`: use-after-frees in signal handlers when a modem goes away |
| `0010-broadband-modem-fix-receiving-multipart-sms-from-o.patch` | upstream `ef88093931ce`: receiving a multipart SMS from one's own number |
| `0011-sms-sanitize-decoded-alphanumeric-sms-addresses.patch` | upstream `1ee3a443b127`: sanitize decoded alphanumeric SMS addresses |
| `0012-base-bearer-broadband-modem-add-terse-state-to-bearers.patch` | upstream MR [!1511](https://gitlab.freedesktop.org/mobile-broadband/ModemManager/-/merge_requests/1511), 1/2: bearers get a terse step, undone on resume |
| `0013-bearer-qmi-disable-wds-event-reports-in-terse-state.patch` | MR !1511, 2/2: the QMI bearer turns its WDS event reports off in that step |
| `0014-broadband-modem-disable-profile-manager-events-in-terse.patch` | the 3GPP profile manager's unsolicited events off in the terse state too, on again on resume |
| `0015-bearer-qmi-limit-the-reported-mtu-to-the-link.patch` | the QMI bearer reports no larger MTU than its multiplexed link accepts |

`series` lists them in order. Debian's 1.24.2-2 has no `debian/patches` of its own. 0004 to 0011 are `git
format-patch` output of the upstream commits, 0012 and 0013 of the merge request's (it is not merged yet), their
authorship kept.

## Why 0012 to 0014

ModemManager runs with `--test-quick-suspend-resume` on VibeOS, so the modem stays connected while the phone sleeps,
and the modem is a wakeup source (QRTR over glink on Qualcomm SoCs). Before suspend ModemManager enters a "terse
state" that turns off the unsolicited events it does not need while the host sleeps; Debian's 1.24.2 turns off only
the 3GPP registration events there. Two more kinds of message kept waking a OnePlus 6T 1 ms after it suspended:

- the QMI bearer's WDS event reports, which its handler only logs: "Dormancy Status: traffic-channel-dormant" for the
  IMS bearer woke 4 of 4 suspends. 0012 and 0013 (MR !1511, written for the OnePlus 6) turn them off in the terse
  state and on again on resume;
- the WDS "Profile Changed" indication of the 3GPP profile manager, sent as NetworkManager disconnects the data
  bearer on sleep: with 0012 and 0013 alone it still woke 4 of 4 suspends. 0014 turns these events off as a terse
  step too, and on resume turns them on again and emits one profile manager "Updated", as profiles may have changed
  meanwhile.

With all three, 4 of 4 suspends of 120 s on the 6T ran the full time with the cable in, and the SoC reached deep sleep
in each. On the 6T this is one of two changes deep sleep needs; the other is in NetworkManager, which disconnected the
IMS bearer on sleep.

## Why 0015

On Qualcomm SoCs the data bearer runs on a multiplexed rmnet link (`qmapmux0.0`) over the IPA interface
`rmnet_ipa0`, whose MTU is at most 1500. The kernel creates the link with what that leaves after the MAP header: 1496,
or 1492 with checksum offload. The modem still reports an MTU of 1500, ModemManager passes it on, and NetworkManager
cannot set it on the link: `do-change-link: failure 22 (Invalid argument), setting MTU to requested size is not
possible`, at connect and then every 30 seconds, 60 times in half an hour on the 6T. A Fairphone 5 logs the same.
0015 reads the link's MTU from sysfs and reports that when the modem's is larger.

## Base

Debian source package `modemmanager` 1.24.2-2 (`modemmanager_1.24.2-2.dsc`, sha256
`51f3682ceb1f0ba154107d9cf2f75218b332823be19302c875d8d6874f1694a2`), from the Debian archive or snapshot.debian.org.

## Rebuild

    apt-get source modemmanager=1.24.2-2    # or dget the .dsc from snapshot.debian.org
    cd modemmanager-1.24.2
    mkdir -p debian/patches
    cp PATCHES/modemmanager/1.24.2-2+surya3+fajita7/*.patch debian/patches/
    cp PATCHES/modemmanager/1.24.2-2+surya3+fajita7/series debian/patches/series
    dch -v 1.24.2-2+surya3+fajita7 -D unstable "VibeOS: upstream fixes, modem events off while the host sleeps, MTU the link accepts"
    dpkg-buildpackage -b -uc -us            # on arm64 (or in an arm64 chroot)

## Shipped in

Not in a VibeOS image yet. `modemmanager`, `libmm-glib0` and `gir1.2-modemmanager-1.0` 1.24.2-2+surya3+fajita7,
built this way, run on the OnePlus 6T with its kernel pre-release
[fajita-7.4.0-rc2-1](https://github.com/JumpLink/linux-fajita/releases/tag/fajita-7.4.0-rc2-1).

## Licence

GPL-2.0-or-later (the daemon and its plugins, which these patches change); libmm-glib is LGPL-2.1-or-later. See
Debian's `debian/copyright`.

## How this set was checked

The packages were built from Debian's 1.24.2-2 source with this series, in an arm64 Debian sid container
(`dpkg-buildpackage -b`, `DEB_BUILD_OPTIONS=nocheck`); these files are the ones that build used.
[`image/test/mm-terse-test.sh`](../../../image/test/mm-terse-test.sh) applies the series to the source from
snapshot.debian.org and checks that the terse state quiets the bearers' event reports and the profile manager events
and that resume turns them on again; on Debian's source the same checks fail. On a OnePlus 6T with VoLTE and the
NetworkManager change, 4 of 4 suspends of 120 s ran the full time (counted with a kprobe on the QRTR receive path). With
0015, the bearers' IP configurations carry MTU 1496 and 1492, the links' own, and NetworkManager logged no MTU
failure in the first five minutes after boot, where it had logged one every 30 seconds; pings of 1496 bytes with
"don't fragment" and an HTTPS download went through the data link. The links' MTU is what it was before, as
NetworkManager's attempts to raise it had always failed.
