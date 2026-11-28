#!/bin/sh
# libcamera-fajita-test.sh: patches/libcamera/0.7.2-1+surya21+fajita1 applies to Debian's libcamera 0.7.2-1, starts
# with the system image's +surya20 series and +surya21's GStreamer patch unchanged, and gives the OnePlus 6T's three
# sensors (imx371, imx376, imx519) a camera sensor helper with the Sony gain model 1024 / (1024 - code) and a 10-bit
# black level of 64, and imx371/imx376 sensor properties. Without a helper the +surya20 auto exposure computes NaN
# gains and the picture stays black. The same checks run on Debian's source first and must fail there, so they see
# the gap. The source comes from snapshot.debian.org, checked against the .dsc's sha256, into $LC_SRC_CACHE (default
# ~/.cache/vibeos-test/libcamera-0.7.2-1).
# Needs sh, curl, tar (gz, xz), patch, awk, grep, cmp and sha256sum; writes only the cache and a temporary directory.
set -u
T=$(cd "$(dirname "$0")/../.." && pwd)
P=$T/patches/libcamera/0.7.2-1+surya21+fajita1
S20=$T/patches/libcamera/0.7.2-1+surya20 S21=$T/patches/libcamera/0.7.2-1+surya21
C=${LC_SRC_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/vibeos-test/libcamera-0.7.2-1}
DSC=libcamera_0.7.2-1.dsc DSC_SHA256=b162125bb8d26641b3b71ed32d344a06ae7fb4e732043db7a081615ffd039983
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
FAILS=0
mkdir -p "$C"
# get NAME SHA1: the file as snapshot.debian.org stores it, by its sha1
get() {
	[ -s "$C/$1" ] && return
	curl -fsSL -o "$C/$1.part" "https://snapshot.debian.org/file/$2" && mv "$C/$1.part" "$C/$1" ||
		{ echo "FAIL: cannot download $1"; exit 1; }
}
get $DSC 7fa054701a1eaa9dd9e51077f469288ccb8d908c
get libcamera_0.7.2.orig.tar.gz 0bf151348f76cfb63c0a28dfae6b45dcddd94fc4
get libcamera_0.7.2-1.debian.tar.xz ca4cc34f6d1aa4825fbfc2b397aa4581e9335405
echo "$DSC_SHA256  $C/$DSC" | sha256sum -c --quiet - || { echo "FAIL: $DSC is not the pinned one"; exit 1; }
awk '/^Checksums-Sha256:/ { s = 1; next } /^[^ ]/ { s = 0 } s { print $1 "  " C "/" $3 }' C="$C" "$C/$DSC" |
	sha256sum -c --quiet - || { echo "FAIL: the source tarballs do not match $DSC"; exit 1; }

S=$W/libcamera-0.7.2
mkdir "$S" && tar -C "$S" --strip-components=1 -xzf "$C/libcamera_0.7.2.orig.tar.gz" &&
	tar -C "$S" -xJf "$C/libcamera_0.7.2-1.debian.tar.xz" || { echo "FAIL: cannot unpack the source"; exit 1; }
# apply DIR SERIES: every patch SERIES names, in order, to the source
apply() { grep -v '^[[:space:]]*\(#\|$\)' "$2" | while read -r p; do
	(cd "$S" && patch -s -N -p1 --no-backup-if-mismatch < "$1/$p") || { echo "  FAIL: $p does not apply"; exit 1; }
done; }
[ ! -e "$S/debian/patches/series" ] || apply "$S/debian/patches" "$S/debian/patches/series" ||
	{ echo "FAIL: Debian's own series does not apply"; exit 1; }
H=$S/src/ipa/libipa/camera_sensor_helper.cpp PR=$S/src/libcamera/sensor/camera_sensor_properties.cpp
for f in "$H" "$PR"; do [ -f "$f" ] || { echo "FAIL: no $f"; exit 1; }; done

# check LABEL COMMAND...: one result line, counted when it fails
check() { l=$1; shift; if "$@"; then echo "  ok: $l"; else echo "  FAIL: $l"; FAILS=$((FAILS + 1)); fi; }
# helper NAME CLASS: NAME has a helper CLASS with the Sony gain model and a 10-bit black level of 64
helper() { grep -q "^REGISTER_CAMERA_SENSOR_HELPER(\"$1\", $2)\$" "$H" &&
	awk -v c="class $2 :" 'index($0, c) == 1 { s = 1 } s { print } s && /^};/ { exit }' "$H" > "$W/h" &&
	grep -q 'gain_ = AnalogueGainLinear{ 0, 1024, -1, 1024 };' "$W/h" && grep -q 'blackLevel_ = 4096;' "$W/h"; }
# props NAME: NAME has an entry in the sensor property table
props() { grep -q "^[[:space:]]*{ \"$1\", {\$" "$PR"; }
imx371() { helper imx371 CameraSensorHelperImx371; }
imx376() { helper imx376 CameraSensorHelperImx376; }
imx519() { helper imx519 CameraSensorHelperImx519; }
props_front() { props imx371 && props imx376; }

for c in imx371 imx376 imx519 props_front; do
	! $c || { echo "  FAIL: Debian's 0.7.2-1 already passes $c"; FAILS=$((FAILS + 1)); }
done
echo "  ok: Debian's 0.7.2-1 has no helper for imx371, imx376 and imx519, and no imx371/imx376 properties"

n=$(grep -c . "$S20/series")
[ "$(sed -n "1,${n}p" "$P/series")" = "$(cat "$S20/series")" ] &&
	[ "$(sed -n "$((n + 1))p" "$P/series")" = "$(cat "$S21/series")" ] &&
	echo "  ok: series starts with +surya20's, then +surya21's" || { echo "  FAIL: series does not start with +surya20, +surya21"; FAILS=$((FAILS + 1)); }
for f in $(cat "$S20/series"); do cmp -s "$P/$f" "$S20/$f" || { echo "  FAIL: $f is not +surya20's"; FAILS=$((FAILS + 1)); }; done
for f in $(cat "$S21/series"); do cmp -s "$P/$f" "$S21/$f" || { echo "  FAIL: $f is not +surya21's"; FAILS=$((FAILS + 1)); }; done
[ "$(LC_ALL=C ls "$P" | grep '\.patch$' | sort)" = "$(sort "$P/series")" ] || { echo "  FAIL: series and the patch files differ"; FAILS=$((FAILS + 1)); }

apply "$P" "$P/series" && echo "  ok: the series applies to Debian's 0.7.2-1" || exit 1
check "imx371 (front) has a helper: gain 1024 / (1024 - code), black level 64" imx371
check "imx376 (rear, second) has a helper: gain 1024 / (1024 - code), black level 64" imx376
check "imx519 (rear, main) has a helper: gain 1024 / (1024 - code), black level 64" imx519
check "imx371 and imx376 have sensor properties" props_front
[ $FAILS = 0 ] && echo "all ok" || { echo "$FAILS failed"; exit 1; }
