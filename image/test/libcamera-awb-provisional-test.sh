#!/bin/sh
# libcamera-awb-provisional-test.sh: patches/libcamera/0.7.2-1+surya21+fajita10 is +fajita9 unchanged plus one patch,
# applies to Debian's libcamera 0.7.2-1, and the soft ISP's white balance shows a frame too dark to settle on (green at
# least 2 levels above black) with its own grey world estimate, without counting it towards settling, where it used to
# keep the start gains (1, 1) until a well exposed frame came or 30 frames had passed. The lines of Awb::process() from
# the settling decision to the grey-world gains are compiled into a small harness fed a run of frames; the same harness
# runs on +fajita9's awb.cpp first and must fail there. The source comes from snapshot.debian.org, checked against the
# .dsc's sha256, into $LC_SRC_CACHE (default ~/.cache/vibeos-test/libcamera-0.7.2-1).
# Needs sh, curl, tar (gz, xz), patch, awk, grep, cmp, sha256sum and a C++ compiler (c++); writes only the cache and a
# temporary directory.
set -u
T=$(cd "$(dirname "$0")/../.." && pwd)
P1=$T/patches/libcamera/0.7.2-1+surya21+fajita9 P=$T/patches/libcamera/0.7.2-1+surya21+fajita10
NEW="fajita-0018-ipa-simple-awb-Balance-the-frames-too-dark-to-settle.patch"
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

[ "$(cat "$P/series")" = "$(cat "$P1/series"; printf '%s\n' $NEW)" ] && echo "  ok: series is +fajita9's, then $NEW" ||
	{ echo "  FAIL: series is not +fajita9's plus the new patches"; FAILS=$((FAILS + 1)); }
for f in $(cat "$P1/series"); do cmp -s "$P/$f" "$P1/$f" || { echo "  FAIL: $f is not +fajita9's"; FAILS=$((FAILS + 1)); }; done
[ "$(LC_ALL=C ls "$P" | grep '\.patch$' | sort)" = "$(sort "$P/series")" ] || { echo "  FAIL: series and the patch files differ"; FAILS=$((FAILS + 1)); }

# the harness: the lines of Awb::process() from the settling decision to the grey-world gains, with the constants of
# awb.h; it is fed runs of frames ("COUNT:R,G,B" is COUNT frames of those mean levels above black, 1000 pixels, none
# near-neutral) and prints the last red and blue estimate, and the estimates counted towards settling, or "kept"
cat > "$W/harness.cpp" <<'EOF'
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
struct Null { template<class T> Null &operator<<(const T &) { return *this; } };
#define LOG(category, level) Null()
template<class T> struct RGB {
	T v[3];
	T r() const { return v[0]; } T g() const { return v[1]; } T b() const { return v[2]; }
	RGB max(T m) const { RGB o; for (int i = 0; i < 3; i++) o.v[i] = std::max(v[i], m); return o; }
	RGB operator-(T m) const { RGB o; for (int i = 0; i < 3; i++) o.v[i] = v[i] - m; return o; }
};
struct Stats { uint64_t neutralCount; RGB<uint64_t> sum_, sumNeutral_; };
struct Ctx { struct { struct { struct { float v[3]; float r() const { return v[0]; } float b() const { return v[2]; } } gains; } awb; } activeState; };
struct Awb {
#include "consts.inc"
	unsigned int startFrames_ = 0, settleWait_ = 0, lockedFrames_ = 0;
	Ctx context;
	bool ok = false;
	float R = 0, B = 0;
	void step(const Stats *stats)
	{
		const uint8_t blackLevel = 0;
		const uint64_t nPixels = 1000, offset = 0, minValid = 1;
		ok = false;
#include "snippet.inc"
		(void)gains;
		R = greyR; B = greyB; ok = true;
	}
};
int main(int argc, char **argv)
{
	Awb a;
	bool any = false;
	float R = 0, B = 0;
	for (int i = 1; i < argc; i++) {
		int n; double r, g, b;
		std::sscanf(argv[i], "%d:%lf,%lf,%lf", &n, &r, &g, &b);
		while (n--) {
			Stats s{ 0, { { (uint64_t)(r * 1000), (uint64_t)(g * 1000), (uint64_t)(b * 1000) } }, {} };
			s.sumNeutral_ = s.sum_;
			a.step(&s);
			if (a.ok) { any = true; R = a.R; B = a.B; }
		}
	}
	if (any)
		std::printf("%.4f %.4f %u\n", R, B, a.startFrames_);
	else
		std::printf("kept\n");
}
EOF
# build NAME SRC: the harness from SRC's awb.cpp and awb.h as $W/NAME
build() {
	a=$2/src/ipa/simple/algorithms/awb.cpp
	awk '/const bool settling = startFrames_/ { f = 1 } f { print } f && /const float greyB/ { exit }' "$a" > "$W/snippet.inc"
	grep -q 'const float greyB' "$W/snippet.inc" || { echo "FAIL: no gain computation found in $a"; exit 1; }
	grep 'static constexpr' "$2/src/ipa/simple/algorithms/awb.h" > "$W/consts.inc"
	"$CXX" -std=c++17 -w -I"$W" -o "$W/$1" "$W/harness.cpp" || { echo "FAIL: the harness does not compile from $a"; exit 1; }
}
# cases HARNESS: the runs of frames, as "LABEL|FRAMES|WANT"; prints a FAIL line per miss and returns the count
cases() {
	n=0
	while IFS='|' read -r l s want; do
		got=$("$W/$1" $s)
		[ "$got" = "$want" ] && echo "  ok: $l" || { echo "  FAIL: $l: got '$got', want '$want'"; n=$((n + 1)); }
	done <<'EOF'
a frame 3 levels above black is balanced at once, not counted|1:2.5,3,1|1.2000 3.0000 0
a frame under 2 levels keeps the gains|1:1.5,1.5,1.5|kept
the gains of a dark frame stay when a darker one follows|1:2.5,3,1 1:1.5,1.5,1.5|1.2000 3.0000 0
five dark frames are balanced and none counted|5:2.5,3,1|1.2000 3.0000 0
a well exposed frame after dark ones settles in full|5:2.5,3,1 1:32,40,20|1.2500 2.0000 1
after 30 dark frames the next one counts|30:2.5,3,1 1:2.5,3,1|1.2000 3.0000 1
EOF
	return $n
}

S1=$W/src1
unpack "$S1"
apply "$S1" "$P1" "$P1/series" || exit 1
build old "$S1"
cases old > "$W/old.out"
grep -q FAIL "$W/old.out" && echo "  ok: +fajita9 fails the behaviour check ($(grep -c FAIL "$W/old.out") cases)" ||
	{ echo "  FAIL: +fajita9 already passes"; FAILS=$((FAILS + 1)); }

S=$W/src
unpack "$S"
apply "$S" "$P" "$P/series" && echo "  ok: the series applies to Debian's 0.7.2-1" || exit 1
build new "$S"
cases new || FAILS=$((FAILS + $?))
[ $FAILS = 0 ] && echo "all ok" || { echo "$FAILS failed"; exit 1; }
