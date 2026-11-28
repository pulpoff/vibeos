#!/bin/sh
# mm-terse-test.sh: patches/modemmanager/1.24.2-2+surya3+fajita6 and +fajita7 apply to Debian's modemmanager 1.24.2-2,
# their first three patches are the system image's +surya3, 0012 and 0013 are upstream MR !1511, and the patched modem's
# terse state (entered while the host sleeps) also quiets the bearers' WDS event reports and the 3GPP profile manager
# events, which woke a sleeping phone, and the resume sync turns them on again. The QMI bearer also limits the MTU it
# reports to the one its multiplexed link accepts (+fajita7, which is +fajita6 plus that patch). The same checks run
# on Debian's source first and must fail there, so they see the bug. The source comes from snapshot.debian.org, checked
# against the .dsc's sha256, into $MM_SRC_CACHE (default ~/.cache/vibeos-test/modemmanager-1.24.2-2).
# Needs sh, curl, tar (xz), patch, awk, grep, cmp and sha256sum; writes only the cache and a temporary directory.
set -u
T=$(cd "$(dirname "$0")/../.." && pwd)
P6=$T/patches/modemmanager/1.24.2-2+surya3+fajita6 P7=$T/patches/modemmanager/1.24.2-2+surya3+fajita7
C=${MM_SRC_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/vibeos-test/modemmanager-1.24.2-2}
DSC=modemmanager_1.24.2-2.dsc DSC_SHA256=51f3682ceb1f0ba154107d9cf2f75218b332823be19302c875d8d6874f1694a2
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
FAILS=0
mkdir -p "$C"
# get NAME SHA1: the file as snapshot.debian.org stores it, by its sha1
get() {
	[ -s "$C/$1" ] && return
	curl -fsSL -o "$C/$1.part" "https://snapshot.debian.org/file/$2" && mv "$C/$1.part" "$C/$1" ||
		{ echo "FAIL: cannot download $1"; exit 1; }
}
get $DSC 6c6f5de0a2cf7efaed24a00589f547f6a0f121b8
get modemmanager_1.24.2.orig.tar.xz 8ec832ab71d49bd86ffc81f8ba04bed56d674903
get modemmanager_1.24.2-2.debian.tar.xz c4717ba03bf9737c1a7b1ddc33070d592f24e690
echo "$DSC_SHA256  $C/$DSC" | sha256sum -c --quiet - || { echo "FAIL: $DSC is not the pinned one"; exit 1; }
awk '/^Checksums-Sha256:/ { s = 1; next } /^[^ ]/ { s = 0 } s { print $1 "  " C "/" $3 }' C="$C" "$C/$DSC" |
	sha256sum -c --quiet - || { echo "FAIL: the source tarballs do not match $DSC"; exit 1; }

# unpack DIR: Debian's 1.24.2-2 into DIR, and B, Q and M the three files the checks read
unpack() {
	S=$1
	mkdir "$S" && tar -C "$S" --strip-components=1 -xJf "$C/modemmanager_1.24.2.orig.tar.xz" &&
		tar -C "$S" -xJf "$C/modemmanager_1.24.2-2.debian.tar.xz" || { echo "FAIL: cannot unpack the source"; exit 1; }
	[ ! -e "$S/debian/patches/series" ] || { echo "FAIL: Debian's 1.24.2-2 has a series of its own now"; exit 1; }
	B=$S/src/mm-broadband-modem.c Q=$S/src/mm-bearer-qmi.c M=$S/src/mm-iface-modem-3gpp-profile-manager.c
	for f in "$B" "$Q" "$M"; do [ -f "$f" ] || { echo "FAIL: no $f"; exit 1; }; done
}
unpack "$W/debian"

# steps NAME: the members of the broadband modem's enum NAME (TerseStep, SyncingStep), one per line
steps() { awk -v n="$1" '/^typedef enum/ { s = 1; m = ""; next } s && /^}/ { if ($2 == n ";") printf "%s", m; s = 0; next }
	s { gsub(/[ ,]/, ""); if ($0 != "") m = m $0 "\n" }' "$B"; }
# check LABEL COMMAND...: one result line, counted when it fails
check() { l=$1; shift; if "$@"; then echo "  ok: $l"; else echo "  FAIL: $l"; FAILS=$((FAILS + 1)); fi; }
has() { steps "$1" | grep -qx "$2"; }
quiets() { grep -q 'base_bearer_class->set_terse = set_terse;' "$Q" && grep -q 'event_report_input_new (!terse)' "$Q"; }
pm_terse() { awk '/^mm_iface_modem_3gpp_profile_manager_terse \(/,/^}/' "$M" | grep -q -- '->disable_unsolicited_events ('; }
pm_sync() { awk '/^mm_iface_modem_3gpp_profile_manager_sync \(/,/^}/' "$M" | grep -q -- '->enable_unsolicited_events (' &&
	awk '/^sync_enable_unsolicited_events_ready \(/,/^}/' "$M" | grep -q 'mm_iface_modem_3gpp_profile_manager_updated (self)'; }
mtu_link() { awk '/^get_current_settings_ready \(/,/^}/' "$Q" | grep -q 'mtu = limit_mtu_to_link (self, ctx->link, mtu);' &&
	awk '/^limit_mtu_to_link \(/,/^}/' "$Q" | grep -q '"/sys/class/net/%s/mtu"'; }
bearers() { has TerseStep TERSE_STEP_BEARERS && quiets; }
pm_quiet() { has TerseStep TERSE_STEP_DISABLE_UNSOLICITED_EVENTS_3GPP_PROFILE_MANAGER && pm_terse; }
pm_resume() { has SyncingStep SYNCING_STEP_IFACE_3GPP_PROFILE_MANAGER && pm_sync; }

has TerseStep TERSE_STEP_DISABLE_UNSOLICITED_EVENTS_3GPP || { echo "FAIL: Debian's 1.24.2-2 has no 3GPP terse step"; exit 1; }
for c in bearers pm_quiet pm_resume mtu_link; do
	! $c || { echo "  FAIL: Debian's 1.24.2-2 already passes $c"; FAILS=$((FAILS + 1)); }
done
echo "  ok: Debian's 1.24.2-2 terse state leaves the bearers' event reports and the profile manager events on,"
echo "  ok: and its QMI bearer reports the modem's MTU unchecked"

# set DIR CHECKS...: DIR's patches are +surya3's and MR !1511's where they should be, apply to a fresh source, and
# pass CHECKS
set_ok() {
	P=$1; shift
	echo "$(basename "$P"):"
	for i in 1 2 3; do
		f=$(sed -n "${i}p" "$P/series")
		cmp -s "$P/$f" "$T/patches/modemmanager/1.24.2-2+surya3/$f" || { echo "  FAIL: $f is not the system image's +surya3"; FAILS=$((FAILS + 1)); }
	done
	[ "$(sed -n 1,3p "$P/series")" = "$(cat "$T/patches/modemmanager/1.24.2-2+surya3/series")" ] &&
		echo "  ok: 0001 to 0003 are the system image's +surya3" || { echo "  FAIL: series does not start with +surya3's"; FAILS=$((FAILS + 1)); }
	[ "$(LC_ALL=C ls "$P" | grep '\.patch$')" = "$(cat "$P/series")" ] || { echo "  FAIL: series and the patch files differ"; FAILS=$((FAILS + 1)); }
	head -1 "$P"/0012-*.patch | grep -q '^From 772c58bdfabda95398f8a958de328b8722386d50 ' &&
		head -1 "$P"/0013-*.patch | grep -q '^From 88e17376c7896caa3072d17f8498cf953fddc23f ' &&
		echo "  ok: 0012 and 0013 are the commits of upstream MR !1511" || { echo "  FAIL: 0012/0013 are not MR !1511's commits"; FAILS=$((FAILS + 1)); }

	unpack "$W/$(basename "$P")"
	grep -v '^[[:space:]]*\(#\|$\)' "$P/series" | while read -r p; do
		(cd "$S" && patch -s -N -p1 --no-backup-if-mismatch < "$P/$p") || { echo "  FAIL: $p does not apply"; exit 1; }
	done && echo "  ok: the series applies to Debian's 1.24.2-2" || exit 1
	check "the terse state quiets the bearers' WDS event reports (MR !1511)" bearers
	check "the terse state quiets the 3GPP profile manager events" pm_quiet
	check "the resume sync turns the profile manager events on again and reports profiles as updated" pm_resume
	[ $# = 0 ] || check "the QMI bearer limits the reported MTU to the link's" "$@"
}
set_ok "$P6"
set_ok "$P7" mtu_link
[ "$(cat "$P7/series")" = "$(cat "$P6/series"; echo 0015-bearer-qmi-limit-the-reported-mtu-to-the-link.patch)" ] &&
	echo "  ok: +fajita7's series is +fajita6's, then 0015" || { echo "  FAIL: +fajita7 is not +fajita6 plus 0015"; FAILS=$((FAILS + 1)); }
for f in $(cat "$P6/series"); do cmp -s "$P7/$f" "$P6/$f" || { echo "  FAIL: +fajita7's $f is not +fajita6's"; FAILS=$((FAILS + 1)); }; done
[ $FAILS = 0 ] && echo "all ok" || { echo "$FAILS failed"; exit 1; }
