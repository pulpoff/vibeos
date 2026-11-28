#!/bin/sh
# libcamera-pdaf-pixels-test.sh: patches/libcamera/0.7.2-1+surya21+fajita9 is +fajita8 unchanged plus one patch,
# applies to Debian's libcamera 0.7.2-1, and the soft ISP replaces the Sony IMX376's uncorrected phase-detection pixels
# (eight sites in every 16x16 tile) by the mean of their same-colour neighbours. The patch's own pdaf_pixels.cpp is
# compiled with c++ alone, against a few mock libcamera headers, and run on a raw frame whose sites are 1.7x too bright,
# in 10-bit CSI-2 packed, 8-bit and 16-bit container formats; the same harness runs on +fajita8's source first and
# must fail there (it has no pdaf_pixels.cpp). The source comes from snapshot.debian.org, checked against the .dsc's
# sha256, into $LC_SRC_CACHE (default ~/.cache/vibeos-test/libcamera-0.7.2-1).
# Needs sh, curl, tar (gz, xz), patch, awk, grep, cmp, sha256sum and a C++20 compiler (c++); writes only the cache and a
# temporary directory.
set -u
T=$(cd "$(dirname "$0")/../.." && pwd)
P1=$T/patches/libcamera/0.7.2-1+surya21+fajita8 P=$T/patches/libcamera/0.7.2-1+surya21+fajita9
NEW="fajita-0017-libcamera-software_isp-Correct-static-phase-detectio.patch"
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

[ "$(cat "$P/series")" = "$(cat "$P1/series"; printf '%s\n' $NEW)" ] && echo "  ok: series is +fajita8's, then $NEW" ||
	{ echo "  FAIL: series is not +fajita8's plus the new patches"; FAILS=$((FAILS + 1)); }
for f in $(cat "$P1/series"); do cmp -s "$P/$f" "$P1/$f" || { echo "  FAIL: $f is not +fajita8's"; FAILS=$((FAILS + 1)); }; done
[ "$(LC_ALL=C ls "$P" | grep '\.patch$' | sort)" = "$(sort "$P/series")" ] || { echo "  FAIL: series and the patch files differ"; FAILS=$((FAILS + 1)); }

# mock headers: just enough of libcamera for pdaf_pixels.h and pdaf_pixels.cpp to compile; those two are the patch's own
mkdir -p "$W/mock/libcamera/base" "$W/mock/libcamera/internal"
cat > "$W/mock/libcamera/base/log.h" <<'EOF'
#pragma once
struct PdafNull { template<class T> PdafNull &operator<<(const T &) { return *this; } };
#define LOG_DEFINE_CATEGORY(name)
#define LOG(category, level) PdafNull()
EOF
cat > "$W/mock/libcamera/base/span.h" <<'EOF'
#pragma once
#include <span>
namespace libcamera { template<typename T> using Span = std::span<T>; }
EOF
cat > "$W/mock/libcamera/geometry.h" <<'EOF'
#pragma once
namespace libcamera {
struct Point { int x = 0, y = 0; };
struct Size {
	unsigned int width = 0, height = 0;
	Size() = default;
	Size(unsigned int w, unsigned int h) : width(w), height(h) {}
	bool isNull() const { return !width && !height; }
	bool operator==(const Size &o) const { return width == o.width && height == o.height; }
	bool operator!=(const Size &o) const { return !(*this == o); }
};
}
EOF
cat > "$W/mock/libcamera/internal/bayer_format.h" <<'EOF'
#pragma once
namespace libcamera {
struct BayerFormat {
	enum Order { BGGR, GBRG, GRBG, RGGB };
	enum class Packing { None, CSI2, IPU3 };
	Order order; unsigned int bitDepth; Packing packing;
	BayerFormat(Order o, unsigned int d, Packing p) : order(o), bitDepth(d), packing(p) {}
};
}
EOF
cat > "$W/mock/libcamera/internal/camera_sensor_properties.h" <<'EOF'
#pragma once
#include <vector>
#include <libcamera/geometry.h>
namespace libcamera {
struct CameraSensorProperties {
	struct PhaseDetectionPixels { Size outputSize, period; std::vector<Point> sites; };
};
}
EOF
# the harness: a 64x48 frame with a gradient, its sites made 1.7x too bright, corrected in place; it prints
# "1 WRONG-SITES CHANGED-OTHERS" (a site that is not the rounded mean of its in-frame neighbours at +-2, a pixel that is
# not a site or a padding byte that changed), or "0" when the correction is not enabled for the frame
cat > "$W/harness.cpp" <<'EOF'
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <libcamera/internal/software_isp/pdaf_pixels.h>
using namespace libcamera;
static constexpr unsigned int kW = 64, kH = 48, kPad = 16;
static unsigned int depth, stride;
static bool csi2;
static unsigned int get(const std::vector<uint8_t> &b, unsigned int x, unsigned int y)
{
	const uint8_t *r = &b[y * stride];
	if (csi2) { const uint8_t *g = r + (x >> 2) * 5; unsigned int i = x & 3; return (g[i] << 2) | ((g[4] >> (2 * i)) & 3); }
	if (depth == 8) return r[x];
	return r[2 * x] | (r[2 * x + 1] << 8);
}
static void set(std::vector<uint8_t> &b, unsigned int x, unsigned int y, unsigned int v)
{
	uint8_t *r = &b[y * stride];
	if (csi2) { uint8_t *g = r + (x >> 2) * 5; unsigned int i = x & 3; g[i] = v >> 2; g[4] = (g[4] & ~(3 << (2 * i))) | ((v & 3) << (2 * i)); }
	else if (depth == 8) r[x] = v;
	else { r[2 * x] = v & 0xff; r[2 * x + 1] = v >> 8; }
}
int main(int, char **argv)
{
	depth = std::atoi(argv[1]);
	csi2 = argv[2][0] == 'c';
	const unsigned int dsize = std::atoi(argv[3]);
	const unsigned int rowBytes = csi2 ? kW / 4 * 5 : depth == 8 ? kW : kW * 2;
	const unsigned int scale = depth == 8 ? 1 : depth == 10 ? 4 : 16;
	stride = rowBytes + kPad;
	CameraSensorProperties::PhaseDetectionPixels pattern;
	pattern.outputSize = { kW, kH };
	pattern.period = { 16, 16 };
	pattern.sites = { { 1, 1 }, { 9, 1 }, { 5, 5 }, { 13, 5 }, { 5, 9 }, { 13, 9 }, { 1, 13 }, { 9, 13 } };
	auto isSite = [&](unsigned int x, unsigned int y) {
		for (const Point &p : pattern.sites)
			if (x % 16 == (unsigned)p.x && y % 16 == (unsigned)p.y) return true;
		return false;
	};
	std::vector<uint8_t> buf(stride * kH, 0xa5);
	for (unsigned int y = 0; y < kH; y++)
		for (unsigned int x = 0; x < kW; x++) {
			unsigned int v = (10 + x + y) * scale + ((x * 3 + y) & 3);
			set(buf, x, y, isSite(x, y) ? v * 17 / 10 : v);
		}
	const std::vector<uint8_t> before = buf;
	PdafPixelCorrector c;
	BayerFormat fmt(BayerFormat::RGGB, depth, csi2 ? BayerFormat::Packing::CSI2 : BayerFormat::Packing::None);
	if (c.configure(pattern, { kW, kH + dsize }, stride, fmt) || !c.correct({ buf.data(), buf.size() })) {
		std::printf("0\n");
		return 0;
	}
	unsigned int wrong = 0, changed = 0;
	for (unsigned int y = 0; y < kH; y++) {
		for (unsigned int x = 0; x < kW; x++) {
			unsigned int v = get(buf, x, y);
			if (!isSite(x, y)) { changed += v != get(before, x, y); continue; }
			unsigned int sum = 0, n = 0;
			if (x >= 2) { sum += get(before, x - 2, y); n++; }
			if (x + 2 < kW) { sum += get(before, x + 2, y); n++; }
			if (y >= 2) { sum += get(before, x, y - 2); n++; }
			if (y + 2 < kH) { sum += get(before, x, y + 2); n++; }
			wrong += v != (sum + n / 2) / n;
		}
		for (unsigned int i = rowBytes; i < stride; i++)
			changed += buf[y * stride + i] != before[y * stride + i];
	}
	std::printf("1 %u %u\n", wrong, changed);
}
EOF
# build NAME SRC: the harness with SRC's pdaf_pixels.cpp as $W/NAME (a stub that prints "absent" where there is none)
build() {
	p=$2/src/libcamera/software_isp/pdaf_pixels.cpp
	if [ ! -e "$p" ]; then
		printf '#!/bin/sh\necho absent\n' > "$W/$1"; chmod +x "$W/$1"; return
	fi
	"$CXX" -std=c++20 -w -I"$W/mock" -I"$2/include" -o "$W/$1" "$W/harness.cpp" "$p" ||
		{ echo "FAIL: the harness does not compile from $p"; exit 1; }
}
# cases HARNESS: the frames, as "LABEL|BITS PACKING SIZE-DELTA|WANT"; prints a FAIL line per miss and returns the count
cases() {
	n=0
	while IFS='|' read -r l s want; do
		got=$("$W/$1" $s)
		[ "$got" = "$want" ] && echo "  ok: $l" || { echo "  FAIL: $l: got '$got', want '$want'"; n=$((n + 1)); }
	done <<'EOF'
10-bit CSI-2 packed (the IMX376's format): sites become the neighbours' mean|10 csi2 0|1 0 0
8-bit: sites become the neighbours' mean|8 none 0|1 0 0
12-bit in a 16-bit container: sites become the neighbours' mean|12 none 0|1 0 0
a frame of another size than the pattern's is left alone|10 csi2 2|0
12-bit CSI-2 packed is not supported, the frame is left alone|12 csi2 0|0
EOF
	return $n
}

S1=$W/src1
unpack "$S1"
apply "$S1" "$P1" "$P1/series" || exit 1
build old "$S1"
cases old > "$W/old.out"
grep -q FAIL "$W/old.out" && echo "  ok: +fajita8 fails the behaviour check ($(grep -c FAIL "$W/old.out") cases)" ||
	{ echo "  FAIL: +fajita8 already passes"; FAILS=$((FAILS + 1)); }

S=$W/src
unpack "$S"
apply "$S" "$P" "$P/series" && echo "  ok: the series applies to Debian's 0.7.2-1" || exit 1
build new "$S"
cases new || FAILS=$((FAILS + $?))
[ $FAILS = 0 ] && echo "all ok" || { echo "$FAILS failed"; exit 1; }
