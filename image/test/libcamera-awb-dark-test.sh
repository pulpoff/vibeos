#!/bin/sh
# libcamera-awb-dark-test.sh: patches/libcamera/0.7.2-1+surya21+fajita2 is +fajita1 unchanged plus one patch, applies to
# Debian's libcamera 0.7.2-1, and its soft ISP white balance keeps the gains in a frame whose green lies within a level
# of the black level, and clamps the red and blue gains to 1/4 .. 4. The gain computation of the patched awb.cpp is
# compiled into a small harness and fed the channel sums of a dark, an ordinary and a strongly red frame; the
# same harness runs on +fajita1's awb.cpp first and must fail there (a blue gain of 1/30 from noise). The source comes
# from snapshot.debian.org, checked against the .dsc's sha256, into $LC_SRC_CACHE (default
# ~/.cache/vibeos-test/libcamera-0.7.2-1).
# Needs sh, curl, tar (gz, xz), patch, awk, grep, cmp, sha256sum and a C++ compiler (c++); writes only the cache and a
# temporary directory.
set -u
T=$(cd "$(dirname "$0")/../.." && pwd)
P1=$T/patches/libcamera/0.7.2-1+surya21+fajita1 P=$T/patches/libcamera/0.7.2-1+surya21+fajita2
NEW=fajita-0005-ipa-simple-awb-Keep-the-gains-in-a-dark-frame.patch
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

[ "$(cat "$P/series")" = "$(cat "$P1/series"; echo $NEW)" ] && echo "  ok: series is +fajita1's, then $NEW" ||
	{ echo "  FAIL: series is not +fajita1's plus $NEW"; FAILS=$((FAILS + 1)); }
for f in $(cat "$P1/series"); do cmp -s "$P/$f" "$P1/$f" || { echo "  FAIL: $f is not +fajita1's"; FAILS=$((FAILS + 1)); }; done
[ "$(LC_ALL=C ls "$P" | grep '\.patch$' | sort)" = "$(sort "$P/series")" ] || { echo "  FAIL: series and the patch files differ"; FAILS=$((FAILS + 1)); }

# the harness: Awb::process()'s lines from the channel sums to greyB, with just enough around them to compile; it
# prints "R B" (the grey-world gains), or "kept" when the code returns before computing them
cat > "$W/harness.cpp" <<'EOF'
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
struct Sum { uint64_t v[3]; uint64_t r() const { return v[0]; } uint64_t g() const { return v[1]; } uint64_t b() const { return v[2]; } };
struct Stats { uint64_t neutralCount; };
struct Ctx { struct { struct { float gains[3]; } awb; } activeState; };
struct Null { template<class T> Null &operator<<(const T &) { return *this; } };
#define LOG(category, level) Null()
static bool printed;
static void f(Ctx &context, const Stats *stats, bool neutral, uint64_t nPixels, const Sum &sum)
{
#include "snippet.inc"
	(void)gains;
	std::printf("%.4f %.4f\n", greyR, greyB);
	printed = true;
}
int main(int, char **argv)
{
	Ctx context{};
	Stats stats{ std::strtoull(argv[6], nullptr, 10) };
	Sum sum{ { std::strtoull(argv[1], nullptr, 10), std::strtoull(argv[2], nullptr, 10), std::strtoull(argv[3], nullptr, 10) } };
	f(context, &stats, argv[5][0] == '1', std::strtoull(argv[4], nullptr, 10), sum);
	if (!printed)
		std::printf("kept\n");
}
EOF
# build NAME SRC: the harness from SRC's awb.cpp as $W/NAME
build() {
	a=$2/src/ipa/simple/algorithms/awb.cpp
	awk 'f { print } /: stats->sum_\.max\(offset \+ minValid\) - offset;/ { f = 1 } f && /const float greyB/ { exit }' "$a" \
		> "$W/snippet.inc"
	grep -q 'const float greyB' "$W/snippet.inc" || { echo "FAIL: no gain computation found in $a"; exit 1; }
	"$CXX" -std=c++17 -w -I"$W" -o "$W/$1" "$W/harness.cpp" || { echo "FAIL: the harness does not compile from $a"; exit 1; }
}
# cases HARNESS: the frames, as "LABEL|R G B|NPIXELS NEUTRAL NEUTRALCOUNT|WANT"; prints a FAIL line per miss and
# returns the count
cases() {
	n=0
	while IFS='|' read -r l s p want; do
		got=$("$W/$1" $s $p)
		[ "$got" = "$want" ] && echo "  ok: $l" || { echo "  FAIL: $l: got '$got', want '$want'"; n=$((n + 1)); }
	done <<'EOF'
dark frame (green within a level of black, blue noise): gains kept|60 1 30|1000 0 0|kept
ordinary frame: grey-world gains|50000 100000 80000|1000 0 0|2.0000 1.2500
strongly red frame: red gain clamped to 1/4|1000000 100000 100000|1000 0 0|0.2500 1.0000
almost no red: red gain clamped to 4|1000 100000 100000|1000 0 0|4.0000 1.0000
near-neutral pixels lit: their own gains|200 500 400|1000 1 100|2.5000 1.2500
near-neutral pixels dark: gains kept|20 50 40|1000 1 100|kept
EOF
	return $n
}

S1=$W/src1
unpack "$S1"
apply "$S1" "$P1" "$P1/series" || exit 1
build old "$S1"
cases old > "$W/old.out"
grep -q FAIL "$W/old.out" && echo "  ok: on +fajita1 the dark and red frames fail ($(grep -c FAIL "$W/old.out") cases)" ||
	{ echo "  FAIL: +fajita1 already passes"; FAILS=$((FAILS + 1)); }

S=$W/src
unpack "$S"
apply "$S" "$P" "$P/series" && echo "  ok: the series applies to Debian's 0.7.2-1" || exit 1
build new "$S"
cases new || FAILS=$((FAILS + $?))
[ $FAILS = 0 ] && echo "all ok" || { echo "$FAILS failed"; exit 1; }
