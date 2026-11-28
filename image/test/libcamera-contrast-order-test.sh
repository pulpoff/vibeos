#!/bin/sh
# libcamera-contrast-order-test.sh: patches/libcamera/0.7.2-1+surya21+fajita7 is +fajita6 unchanged plus one patch,
# applies to Debian's libcamera 0.7.2-1, and the soft ISP applies the contrast S-curve to the gamma-encoded value, in
# the CPU lookup table and in both GPU shaders. DebayerCpu::updateGammaTable() of the patched debayer_cpu.cpp is
# compiled into a small harness and its table compared with gamma first, S-curve second; the shaders are checked for
# the order of the gamma and the contrast lines. The same checks run on +fajita6's source first and must fail there.
# The source comes from snapshot.debian.org, checked against the .dsc's sha256, into $LC_SRC_CACHE (default
# ~/.cache/vibeos-test/libcamera-0.7.2-1).
# Needs sh, curl, tar (gz, xz), patch, awk, grep, cmp, sha256sum and a C++ compiler (c++); writes only the cache and a
# temporary directory.
set -u
T=$(cd "$(dirname "$0")/../.." && pwd)
P1=$T/patches/libcamera/0.7.2-1+surya21+fajita6 P=$T/patches/libcamera/0.7.2-1+surya21+fajita7
NEW="fajita-0010-libcamera-software_isp-Apply-contrast-after-gamma.patch"
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

[ "$(cat "$P/series")" = "$(cat "$P1/series"; printf '%s\n' $NEW)" ] && echo "  ok: series is +fajita6's, then $NEW" ||
	{ echo "  FAIL: series is not +fajita6's plus the new patches"; FAILS=$((FAILS + 1)); }
for f in $(cat "$P1/series"); do cmp -s "$P/$f" "$P1/$f" || { echo "  FAIL: $f is not +fajita6's"; FAILS=$((FAILS + 1)); }; done
[ "$(LC_ALL=C ls "$P" | grep '\.patch$' | sort)" = "$(sort "$P/series")" ] || { echo "  FAIL: series and the patch files differ"; FAILS=$((FAILS + 1)); }

# the harness: DebayerCpu::updateGammaTable() with just enough around it to compile; it prints the table at five
# inputs of the 1024 entry table, on the 0..255 scale
cat > "$W/harness.cpp" <<'EOF'
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <utility>
namespace utils {
template<class C> struct Enum {
	C &c;
	struct It {
		C &c; size_t i;
		bool operator!=(const It &o) const { return i != o.i; }
		void operator++() { ++i; }
		std::pair<size_t, double &> operator*() { return { i, c[i] }; }
	};
	It begin() { return { c, 0 }; }
	It end() { return { c, c.size() }; }
};
template<class C> Enum<C> enumerate(C &c) { return { c }; }
}
struct DebayerParams { float gamma, contrastExp; };
struct DebayerCpu {
	static constexpr unsigned int kGammaLookupSize = 1024;
	std::array<double, kGammaLookupSize> gammaTable_;
	void updateGammaTable(const DebayerParams &params);
};
#include "snippet.inc"
int main(int, char **argv)
{
	DebayerCpu d;
	d.updateGammaTable({ (float)std::atof(argv[1]), (float)std::atof(argv[2]) });
	std::printf("%.2f %.2f %.2f %.2f %.2f\n", d.gammaTable_[0], d.gammaTable_[256], d.gammaTable_[512], d.gammaTable_[768],
		    d.gammaTable_[1023]);
}
EOF
# build NAME SRC: the harness from SRC's debayer_cpu.cpp as $W/NAME; remembers SRC for the shader check
build() {
	a=$2/src/libcamera/software_isp/debayer_cpu.cpp
	awk '/^void DebayerCpu::updateGammaTable/ { f = 1 } f { print } f && /^}/ { exit }' "$a" > "$W/snippet.inc"
	grep -q 'updateGammaTable' "$W/snippet.inc" || { echo "FAIL: no updateGammaTable() found in $a"; exit 1; }
	"$CXX" -std=c++17 -w -I"$W" -o "$W/$1" "$W/harness.cpp" || { echo "FAIL: the harness does not compile from $a"; exit 1; }
	echo "$2" > "$W/$1.dir"
}
# cases HARNESS: the table for "GAMMA CONTRASTEXP" must be the gamma curve first, then the S-curve around the middle
# of the encoded range, within 0.1 of 255; then both shaders must apply gamma before contrast; prints a FAIL line per
# miss and returns the count
cases() {
	n=0
	while IFS='|' read -r l s; do
		got=$("$W/$1" $s)
		if echo "$s $got" | awk '{ g = $1; e = $2; ok = 1
			for (k = 0; k < 5; k++) { x = (k == 4 ? 1023 : k * 256) / 1023; y = x ^ g
				y = y < 0.5 ? 0.5 * ((y / 0.5) ^ e) : 1 - 0.5 * (((1 - y) / 0.5) ^ e); y *= 255
				if (($(3 + k) - y > 0.1) || (y - $(3 + k) > 0.1)) ok = 0 }
			exit !ok }'; then echo "  ok: $l"
		else echo "  FAIL: $l: table '$got'"; n=$((n + 1)); fi
	done <<'EOF'
contrast 1.25, gamma 2.2 (the 6T's setting)|0.4545 2.4142
contrast 1.5, gamma 2.2|0.4545 6.3138
contrast 0.5, gamma 2.2|0.4545 0.4142
contrast 1.25, gamma 1.0|1.0 2.4142
EOF
	for s in bayer_1x_packed bayer_unpacked; do
		if awk '/pow\(rgb, vec3\(gamma\)\)/ { g = NR } /rgb\.r = apply_contrast\(rgb\.r\)/ { c = NR } END { exit !(g && c && g < c) }' \
			"$(cat "$W/$1.dir")/src/libcamera/shaders/$s.frag"; then echo "  ok: $s.frag applies gamma before contrast"
		else echo "  FAIL: $s.frag applies contrast before gamma"; n=$((n + 1)); fi
	done
	return $n
}

S1=$W/src1
unpack "$S1"
apply "$S1" "$P1" "$P1/series" || exit 1
build old "$S1"
cases old > "$W/old.out"
grep -q FAIL "$W/old.out" && echo "  ok: +fajita6 fails the behaviour check ($(grep -c FAIL "$W/old.out") cases)" ||
	{ echo "  FAIL: +fajita6 already passes"; FAILS=$((FAILS + 1)); }

S=$W/src
unpack "$S"
apply "$S" "$P" "$P/series" && echo "  ok: the series applies to Debian's 0.7.2-1" || exit 1
build new "$S"
cases new || FAILS=$((FAILS + $?))
[ $FAILS = 0 ] && echo "all ok" || { echo "$FAILS failed"; exit 1; }
