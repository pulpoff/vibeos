#!/bin/sh
# libcamera-lsc-test.sh: patches/libcamera/0.7.2-1+surya21+fajita8 is +fajita7 unchanged plus six patches (five libcamera
# commits cherry-picked with -x, and a grid-only Lsc algorithm for the soft ISP), applies to Debian's libcamera
# 0.7.2-1, and the soft ISP gets lens shading correction: Lsc::interpolate() of the new lsc.cpp is compiled into a small
# harness fed two gain sets and a range of colour temperatures, and both GPU shaders must carry the correction (the
# shader itself cannot run on the host). The same checks run on +fajita7's source first and must fail there (it has no
# lsc.cpp and no shader code). The source comes from snapshot.debian.org, checked against the .dsc's sha256, into
# $LC_SRC_CACHE (default ~/.cache/vibeos-test/libcamera-0.7.2-1).
# Needs sh, curl, tar (gz, xz), patch, awk, grep, cmp, sha256sum and a C++ compiler (c++); writes only the cache and a
# temporary directory.
set -u
T=$(cd "$(dirname "$0")/../.." && pwd)
P1=$T/patches/libcamera/0.7.2-1+surya21+fajita7 P=$T/patches/libcamera/0.7.2-1+surya21+fajita8
NEW="fajita-0011-libcamera-software_isp-Add-LSC-data-to-DebayerParams.patch fajita-0012-libcamera-shaders-Add-LSC-support.patch fajita-0013-libcamera-software_isp-Pass-LSC-availability-to-deba.patch fajita-0014-libcamera-software_isp-egl-Add-filter-parameter-to-c.patch fajita-0015-libcamera-software_isp-debayer_egl-Add-LSC-support.patch fajita-0016-ipa-simple-Add-a-grid-only-LSC-algorithm.patch"
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

[ "$(cat "$P/series")" = "$(cat "$P1/series"; printf '%s\n' $NEW)" ] && echo "  ok: series is +fajita7's, then $NEW" ||
	{ echo "  FAIL: series is not +fajita7's plus the new patches"; FAILS=$((FAILS + 1)); }
for f in $(cat "$P1/series"); do cmp -s "$P/$f" "$P1/$f" || { echo "  FAIL: $f is not +fajita7's"; FAILS=$((FAILS + 1)); }; done
[ "$(LC_ALL=C ls "$P" | grep '\.patch$' | sort)" = "$(sort "$P/series")" ] || { echo "  FAIL: series and the patch files differ"; FAILS=$((FAILS + 1)); }

# five of the new patches are libcamera's own commits, cherry-picked with -x
k=0
for f in $(tail -n 6 "$P/series"); do grep -q '^(cherry picked from commit ' "$P/$f" && k=$((k + 1)); done
[ $k = 5 ] && echo "  ok: five of the six new patches are cherry-picked with -x" ||
	{ echo "  FAIL: $k of the new patches name their upstream commit, want 5"; FAILS=$((FAILS + 1)); }

# the harness: Lsc::interpolate() with just enough around it to compile; two sets (3000 K and 6000 K, constant over the
# grid) are interpolated for a colour temperature and the first and the last cell of the table are printed as
# "R G B PADDING R G B PADDING", UQ<2, 6> values
cat > "$W/harness.cpp" <<'EOF'
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <iterator>
#include <map>
#include <vector>
struct DebayerParams {
	static constexpr unsigned int kLscGridSize = 17;
	static constexpr unsigned int kLscValuesPerCell = 4;
	using LscLookupTable = std::array<uint8_t, kLscGridSize * kLscGridSize * kLscValuesPerCell>;
};
constexpr unsigned int kGridSize = DebayerParams::kLscGridSize;
struct Lsc {
	using Components = std::array<std::vector<uint8_t>, 3>;
	void interpolate(unsigned int ct, DebayerParams::LscLookupTable &lut) const;
	std::map<unsigned int, Components> sets_;
};
#include "snippet.inc"
int main(int, char **argv)
{
	Lsc l;
	const unsigned int n = kGridSize * kGridSize;
	l.sets_[3000] = { std::vector<uint8_t>(n, 100), std::vector<uint8_t>(n, 64), std::vector<uint8_t>(n, 40) };
	l.sets_[6000] = { std::vector<uint8_t>(n, 70), std::vector<uint8_t>(n, 64), std::vector<uint8_t>(n, 80) };
	DebayerParams::LscLookupTable lut;
	lut.fill(0xff);
	l.interpolate(std::atoi(argv[1]), lut);
	const unsigned int e = (n - 1) * DebayerParams::kLscValuesPerCell;
	std::printf("%d %d %d %d %d %d %d %d\n", lut[0], lut[1], lut[2], lut[3], lut[e], lut[e + 1], lut[e + 2], lut[e + 3]);
}
EOF
# build NAME SRC: the harness from SRC's lsc.cpp as $W/NAME (a stub that prints "absent" where there is no lsc.cpp);
# remembers SRC for the shader check
build() {
	echo "$2" > "$W/$1.dir"
	a=$2/src/ipa/simple/algorithms/lsc.cpp
	if [ ! -e "$a" ]; then
		printf '#!/bin/sh\necho absent\n' > "$W/$1"; chmod +x "$W/$1"; return
	fi
	awk '/^void Lsc::interpolate/ { f = 1 } f { print } f && /^}/ { exit }' "$a" > "$W/snippet.inc"
	grep -q 'Lsc::interpolate' "$W/snippet.inc" || { echo "FAIL: no Lsc::interpolate() found in $a"; exit 1; }
	"$CXX" -std=c++17 -w -I"$W" -o "$W/$1" "$W/harness.cpp" || { echo "FAIL: the harness does not compile from $a"; exit 1; }
}
# cases HARNESS: the interpolated table for a colour temperature, as "LABEL|CT|WANT"; then both shaders must carry the
# correction (APPLY_LSC and the lsc_tex sampler); prints a FAIL line per miss and returns the count
cases() {
	n=0
	while IFS='|' read -r l s want; do
		got=$("$W/$1" $s)
		[ "$got" = "$want" ] && echo "  ok: $l" || { echo "  FAIL: $l: got '$got', want '$want'"; n=$((n + 1)); }
	done <<'EOF'
exactly the first set's temperature|3000|100 64 40 0 100 64 40 0
exactly the second set's temperature|6000|70 64 80 0 70 64 80 0
halfway between the sets|4500|85 64 60 0 85 64 60 0
a quarter of the way (92.5 rounds up)|3750|93 64 50 0 93 64 50 0
below the first set: its table|2000|100 64 40 0 100 64 40 0
above the last set: its table|9000|70 64 80 0 70 64 80 0
EOF
	for s in bayer_1x_packed bayer_unpacked; do
		f=$(cat "$W/$1.dir")/src/libcamera/shaders/$s.frag
		if grep -q 'APPLY_LSC' "$f" && grep -q 'lsc_tex' "$f"; then echo "  ok: $s.frag applies the shading tables"
		else echo "  FAIL: $s.frag does not apply shading tables"; n=$((n + 1)); fi
	done
	return $n
}

S1=$W/src1
unpack "$S1"
apply "$S1" "$P1" "$P1/series" || exit 1
build old "$S1"
cases old > "$W/old.out"
grep -q FAIL "$W/old.out" && echo "  ok: +fajita7 fails the behaviour check ($(grep -c FAIL "$W/old.out") cases)" ||
	{ echo "  FAIL: +fajita7 already passes"; FAILS=$((FAILS + 1)); }

S=$W/src
unpack "$S"
apply "$S" "$P" "$P/series" && echo "  ok: the series applies to Debian's 0.7.2-1" || exit 1
build new "$S"
cases new || FAILS=$((FAILS + $?))
[ $FAILS = 0 ] && echo "all ok" || { echo "$FAILS failed"; exit 1; }
