#!/bin/sh
# libcamera-agc-target-test.sh: patches/libcamera/0.7.2-1+surya21+fajita5 is +fajita4 unchanged plus one patch,
# applies to Debian's libcamera 0.7.2-1, and the soft ISP's auto exposure reads its target (the mean sample value it
# steers to) from the Agc section of the tuning file, rejects a target outside the histogram's range, and uses it
# in both the proportional steps and the jumps. The constants, Agc::Agc(), Agc::init() and Agc::updateExposure() of the
# patched agc.cpp are compiled into a small harness fed a tuning and a measured frame; the same harness runs on
# +fajita4's agc.cpp first and must fail there (its target is fixed at 2.0). The source comes from snapshot.debian.org,
# checked against the .dsc's sha256, into $LC_SRC_CACHE (default ~/.cache/vibeos-test/libcamera-0.7.2-1).
# Needs sh, curl, tar (gz, xz), patch, awk, grep, cmp, sha256sum and a C++ compiler (c++); writes only the cache and a
# temporary directory.
set -u
T=$(cd "$(dirname "$0")/../.." && pwd)
P1=$T/patches/libcamera/0.7.2-1+surya21+fajita4 P=$T/patches/libcamera/0.7.2-1+surya21+fajita5
NEW="fajita-0008-ipa-simple-Make-the-AGC-exposure-target-configurable.patch"
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

[ "$(cat "$P/series")" = "$(cat "$P1/series"; printf '%s\n' $NEW)" ] && echo "  ok: series is +fajita4's, then $NEW" ||
	{ echo "  FAIL: series is not +fajita4's plus the new patches"; FAILS=$((FAILS + 1)); }
for f in $(cat "$P1/series"); do cmp -s "$P/$f" "$P1/$f" || { echo "  FAIL: $f is not +fajita4's"; FAILS=$((FAILS + 1)); }; done
[ "$(LC_ALL=C ls "$P" | grep '\.patch$' | sort)" = "$(sort "$P/series")" ] || { echo "  FAIL: series and the patch files differ"; FAILS=$((FAILS + 1)); }

# the harness: everything of agc.cpp from the histogram's bin count to the end of updateExposure(), with mocks for the
# tuning node, the context and the frame context; it prints the status of init() and the exposure, analogue gain and
# digital gain updateExposure() leaves
cat > "$W/harness.cpp" <<'EOF'
#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
struct Null { template<class T> Null &operator<<(const T &) { return *this; } };
#define LOG(category, level) Null()
struct Node {
	const char *v = nullptr;
	template<class T> T get(T def) const { return v ? static_cast<T>(std::atof(v)) : def; }
};
struct ValueNode {
	const char *target;
	Node operator[](const std::string &k) const { Node n; if (k == "target") n.v = target; return n; }
};
struct IPAContext {
	struct {
		struct { double againMin = 1, again10 = 1, againMax = 16, againMinStep = 0.1; int32_t exposureMin = 1, exposureMax = 1000; } agc;
	} configuration;
	struct { struct { int32_t exposure = 100; double again = 1, digitalGain = 1; bool valid = true; } agc; } activeState;
};
struct IPAFrameContext { struct { int32_t exposure = 100; double gain = 1; } sensor; };
namespace ipa::soft::algorithms {
struct Agc {
	Agc();
	int init(IPAContext &context, const ValueNode &tuningData);
	void updateExposure(IPAContext &context, IPAFrameContext &frameContext, double exposureMSV, double mean);
	double exposureOptimal_ = 0, meanOptimal_ = 0;
};
#include "snippet.inc"
}
int main(int, char **argv)
{
	IPAContext ctx;
	IPAFrameContext fc;
	ipa::soft::algorithms::Agc a;
	int rc = 0;
#ifdef HAVE_INIT
	rc = a.init(ctx, ValueNode{ argv[1][0] == '-' && !argv[1][1] ? nullptr : argv[1] });
	if (rc) { std::printf("%d\n", rc); return 0; }
#endif
	a.updateExposure(ctx, fc, std::atof(argv[2]), std::atof(argv[3]));
	std::printf("%d %d %g %g\n", rc, fc.sensor.exposure, fc.sensor.gain, ctx.activeState.agc.digitalGain);
}
EOF
# build NAME SRC: the harness from SRC's agc.cpp as $W/NAME
build() {
	a=$2/src/ipa/simple/algorithms/agc.cpp
	awk '/^static constexpr unsigned int kExposureBinsCount/ { f = 1 } /^void Agc::process\(/ { exit } f { print }' "$a" > "$W/snippet.inc"
	grep -q 'Agc::updateExposure' "$W/snippet.inc" || { echo "FAIL: no Agc::updateExposure() found in $a"; exit 1; }
	d=; grep -q 'Agc::init(' "$W/snippet.inc" && d=-DHAVE_INIT
	"$CXX" -std=c++17 -w $d -I"$W" -o "$W/$1" "$W/harness.cpp" || { echo "FAIL: the harness does not compile from $a"; exit 1; }
}
# cases HARNESS: the tunings and frames, as "LABEL|TARGET MSV MEAN|WANT" (TARGET "-" for a tuning without one), from
# an exposure of 100 at unity gain; WANT is "STATUS EXPOSURE GAIN DIGITAL" or the status of a rejected tuning; prints a
# FAIL line per miss and returns the count
cases() {
	n=0
	while IFS='|' read -r l s want; do
		got=$("$W/$1" $s)
		[ "$got" = "$want" ] && echo "  ok: $l" || { echo "  FAIL: $l: got '$got', want '$want'"; n=$((n + 1)); }
	done <<'EOF'
no target, a frame on the default of 2.0: nothing changes|- 2.0 0.3|0 100 1 1
target 1.7, a frame at 2.0 is too bright: exposure down|1.7 2.0 0.3|0 98 1 1
target 1.7, a frame at 1.7 is on target: nothing changes|1.7 1.7 0.3|0 100 1 1
target 3.0, a frame at 2.0 is far below it: jump to the target's mean|3.0 2.0 0.25|0 200 1 1
target 1.7, a dark frame: jump to the target's mean|1.7 1.0 0.05|0 480 1 1
target below the histogram's range is rejected|0.5 2.0 0.3|-22
target above the histogram's range is rejected|5.5 2.0 0.3|-22
EOF
	return $n
}

S1=$W/src1
unpack "$S1"
apply "$S1" "$P1" "$P1/series" || exit 1
build old "$S1"
cases old > "$W/old.out"
grep -q FAIL "$W/old.out" && echo "  ok: +fajita4 fails the behaviour check ($(grep -c FAIL "$W/old.out") cases)" ||
	{ echo "  FAIL: +fajita4 already passes"; FAILS=$((FAILS + 1)); }

S=$W/src
unpack "$S"
apply "$S" "$P" "$P/series" && echo "  ok: the series applies to Debian's 0.7.2-1" || exit 1
build new "$S"
cases new || FAILS=$((FAILS + $?))
[ $FAILS = 0 ] && echo "all ok" || { echo "$FAILS failed"; exit 1; }
