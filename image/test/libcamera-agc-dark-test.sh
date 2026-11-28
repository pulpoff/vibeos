#!/bin/sh
# libcamera-agc-dark-test.sh: patches/libcamera/0.7.2-1+surya21+fajita11 is +fajita10 unchanged plus one patch, applies
# to Debian's libcamera 0.7.2-1, and the soft ISP's exposure jumps from a frame at the mean sample value's floor of 1.0
# whose mean is below 80% of the target's, where with a target close to 1.0 it stayed put (1.1) or rose by 1% a frame
# (1.3). Agc::updateExposure() is compiled whole into a small harness fed a run of frames; the same harness runs on
# +fajita10's agc.cpp first and must fail there. The source comes from snapshot.debian.org, checked against the .dsc's
# sha256, into $LC_SRC_CACHE (default ~/.cache/vibeos-test/libcamera-0.7.2-1).
# Needs sh, curl, tar (gz, xz), patch, awk, grep, cmp, sha256sum and a C++ compiler (c++); writes only the cache and a
# temporary directory.
# temporary directory.
set -u
T=$(cd "$(dirname "$0")/../.." && pwd)
P1=$T/patches/libcamera/0.7.2-1+surya21+fajita10 P=$T/patches/libcamera/0.7.2-1+surya21+fajita11
NEW="fajita-0019-ipa-simple-agc-Jump-when-the-frame-is-far-darker-tha.patch"
C=${LC_SRC_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/vibeos-test/libcamera-0.7.2-1}
DSC=libcamera_0.7.2-1.dsc DSC_SHA256=b162125bb8d26641b3b71ed32d344a06ae7fb4e732043db7a081615ffd039983
CXX=${CXX:-c++}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
FAILS=0
command -v "$CXX" >/dev/null || { echo "FAIL: no C++ compiler ($CXX)"; exit 1; }
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

# unpack DIR: Debian's 0.7.2-1 with its own series applied, unpacked into DIR
unpack() {
	mkdir "$1" && tar -C "$1" --strip-components=1 -xzf "$C/libcamera_0.7.2.orig.tar.gz" &&
		tar -C "$1" -xJf "$C/libcamera_0.7.2-1.debian.tar.xz" || { echo "FAIL: cannot unpack the source"; exit 1; }
	[ ! -e "$1/debian/patches/series" ] || apply "$1" "$1/debian/patches" "$1/debian/patches/series" ||
		{ echo "FAIL: Debian's own series does not apply"; exit 1; }
}
# apply SRC DIR SERIES: every patch SERIES names, in order, to SRC
apply() { grep -v '^[[:space:]]*\(#\|$\)' "$3" | while read -r p; do
	(cd "$1" && patch -s -N -p1 --no-backup-if-mismatch < "$2/$p") || { echo "  FAIL: $p does not apply"; exit 1; }
done; }

[ "$(cat "$P/series")" = "$(cat "$P1/series"; printf '%s\n' $NEW)" ] && echo "  ok: series is +fajita10's, then $NEW" ||
	{ echo "  FAIL: series is not +fajita10's plus the new patches"; FAILS=$((FAILS + 1)); }
for f in $(cat "$P1/series"); do cmp -s "$P/$f" "$P1/$f" || { echo "  FAIL: $f is not +fajita10's"; FAILS=$((FAILS + 1)); }; done
[ "$(LC_ALL=C ls "$P" | grep '\.patch$' | sort)" = "$(sort "$P/series")" ] || { echo "  FAIL: series and the patch files differ"; FAILS=$((FAILS + 1)); }


# the harness: Agc::updateExposure() as it is, with the constants of agc.cpp; it is fed a target and a run of frames
# ("MSV:MEAN:EXP" is one frame of that mean sample value and mean above black, taken at exposure EXP at unity gain) and
# prints the exposure asked for after the last one
cat > "$W/harness.cpp" <<'EOH'
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
struct Null { template<class T> Null &operator<<(const T &) { return *this; } };
#define LOG(category, level) Null()
struct IPAContext {
	struct { struct { int32_t exposureMin, exposureMax; double againMin, againMax, again10, againMinStep; } agc; } configuration;
	struct { struct { int32_t exposure; double again; bool valid; double digitalGain = 1.0; } agc; } activeState;
};
struct IPAFrameContext { struct { int32_t exposure; double gain; } sensor; };
#include "consts.inc"
struct Agc {
	double exposureOptimal_, meanOptimal_;
	void updateExposure(IPAContext &context, IPAFrameContext &frameContext, double exposureMSV, double mean);
};
#include "update.inc"
int main(int argc, char **argv)
{
	Agc agc;
	agc.exposureOptimal_ = std::atof(argv[1]);
	agc.meanOptimal_ = std::max((agc.exposureOptimal_ - 0.5) / 5, 0.05);
	IPAContext context{ { { 4, 3000, 1.0, 16.0, 1.0, 0.06 } }, {} };
	int32_t asked = 0;
	for (int i = 2; i < argc; i++) {
		double msv, mean; int exp;
		std::sscanf(argv[i], "%lf:%lf:%d", &msv, &mean, &exp);
		if (i == 2)
			context.activeState.agc = { exp, 1.0, true, 1.0 };
		IPAFrameContext fc{ { exp, 1.0 } };
		agc.updateExposure(context, fc, msv, mean);
		asked = fc.sensor.exposure;
	}
	std::printf("%d\n", asked);
}
EOH
# build NAME SRC: the harness from SRC's agc.cpp as $W/NAME
build() {
	a=$2/src/ipa/simple/algorithms/agc.cpp
	awk '/^void Agc::updateExposure\(/ { f = 1 } f { print } f && /^}/ { exit }' "$a" > "$W/update.inc"
	grep -q '^}' "$W/update.inc" || { echo "FAIL: no Agc::updateExposure() found in $a"; exit 1; }
	grep '^static constexpr' "$a" > "$W/consts.inc"
	"$CXX" -std=c++17 -w -I"$W" -o "$W/$1" "$W/harness.cpp" || { echo "FAIL: the harness does not compile from $a"; exit 1; }
}
# cases HARNESS: the runs of frames, as "LABEL|TARGET FRAMES|WANT"; prints a FAIL line per miss and returns the count
cases() {
	n=0
	while IFS='|' read -r l s want; do
		got=$("$W/$1" $s)
		[ "$got" = "$want" ] && echo "  ok: $l" || { echo "  FAIL: $l: got '$got', want '$want'"; n=$((n + 1)); }
	done <<'EOC'
target 1.1: an all-dark frame asks for 8x the exposure|1.1 1:0.008:100|800
target 1.3: an all-dark frame asks for 8x the exposure|1.3 1:0.008:100|800
target 1.1: the jump is asked for again until the sensor delivers it|1.1 1:0.008:100 1:0.008:100|800
target 1.1: delivered, a frame at the floor at 62% of the target's mean jumps again|1.1 1:0.008:100 1:0.075:800|1280
target 1.3: delivered, a frame at the floor at 62% of the target's mean jumps again|1.3 1:0.008:100 1:0.1:800|1280
target 1.1: a frame at the target changes nothing|1.1 1.1:0.137:800|800
target 1.1: above the floor a low mean (a few highlights) is left to the MSV|1.1 1.2:0.05:800|800
target 2: an all-dark frame jumps as before|2 1:0.008:100|800
EOC
	return $n
}
S1=$W/src1
unpack "$S1"
apply "$S1" "$P1" "$P1/series" || exit 1
build old "$S1"
cases old > "$W/old.out"
grep -q FAIL "$W/old.out" && echo "  ok: +fajita10 fails the behaviour check ($(grep -c FAIL "$W/old.out") cases)" ||
	{ echo "  FAIL: +fajita10 already passes"; FAILS=$((FAILS + 1)); }

S=$W/src
unpack "$S"
apply "$S" "$P" "$P/series" && echo "  ok: the series applies to Debian's 0.7.2-1" || exit 1
build new "$S"
cases new || FAILS=$((FAILS + $?))
[ $FAILS = 0 ] && echo "all ok" || { echo "$FAILS failed"; exit 1; }
