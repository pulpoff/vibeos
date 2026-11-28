#!/bin/sh
# libcamera-stats-window-test.sh: patches/libcamera/0.7.2-1+surya21+fajita3 is +fajita2 unchanged plus one patch,
# applies to Debian's libcamera 0.7.2-1, and the GPU debayer gives the statistics (auto exposure, white balance,
# autofocus) the part of the sensor frame the picture shows: as many columns and lines as the picture, scaled with its
# aspect ratio kept, takes from the frame, instead of a block of the output's size in the frame's top left corner. DebayerEGL::configure()'s lines from
# the native output size to setWindow() are compiled into a small harness and fed the OnePlus 6T's modes; the same
# harness runs on +fajita2's debayer_egl.cpp first and must fail there. The source comes from snapshot.debian.org,
# checked against the .dsc's sha256, into $LC_SRC_CACHE (default ~/.cache/vibeos-test/libcamera-0.7.2-1).
# Needs sh, curl, tar (gz, xz), patch, awk, grep, cmp, sha256sum and a C++ compiler (c++); writes only the cache and a
# temporary directory.
set -u
T=$(cd "$(dirname "$0")/../.." && pwd)
P1=$T/patches/libcamera/0.7.2-1+surya21+fajita2 P=$T/patches/libcamera/0.7.2-1+surya21+fajita3
NEW=fajita-0006-libcamera-software_isp-Align-EGL-statistics-with-output-crop.patch
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

[ "$(cat "$P/series")" = "$(cat "$P1/series"; echo $NEW)" ] && echo "  ok: series is +fajita2's, then $NEW" ||
	{ echo "  FAIL: series is not +fajita2's plus $NEW"; FAILS=$((FAILS + 1)); }
for f in $(cat "$P1/series"); do cmp -s "$P/$f" "$P1/$f" || { echo "  FAIL: $f is not +fajita2's"; FAILS=$((FAILS + 1)); }; done
[ "$(LC_ALL=C ls "$P" | grep '\.patch$' | sort)" = "$(sort "$P/series")" ] || { echo "  FAIL: series and the patch files differ"; FAILS=$((FAILS + 1)); }

# the harness: the lines of DebayerEGL::configure() after the native output size is known, up to setWindow(), with
# just enough around them to compile; it prints the statistics window as "WIDTHxHEIGHT"
cat > "$W/harness.cpp" <<'EOF'
#include <algorithm>
#include <cstdio>
#include <cstdlib>
struct Size { unsigned int width = 0, height = 0; Size() = default; Size(unsigned int w, unsigned int h) : width(w), height(h) {} };
struct Rectangle {
	int x = 0, y = 0; unsigned int width = 0, height = 0;
	Rectangle() = default;
	explicit Rectangle(const Size &s) : width(s.width), height(s.height) {}
	Size size() const { return { width, height }; }
};
struct Cfg { Size size; };
struct InCfg { Size patternSize; };
struct Stats { Rectangle w; void setWindow(const Rectangle &r) { w = r; } };
struct DebayerEGL {
	unsigned int width_, height_;
	Size outputSize_, nativeOutputSize_;
	Rectangle window_;
	InCfg inputConfig_{ { 2, 2 } };
	Stats s, *stats_ = &s;
	void configure(const Cfg &inputCfg, const Cfg &outputCfg)
	{
#include "snippet.inc"
	}
};
int main(int, char **argv)
{
	DebayerEGL d;
	Cfg in{ { (unsigned)std::atoi(argv[1]), (unsigned)std::atoi(argv[2]) } };
	Cfg out{ { (unsigned)std::atoi(argv[3]), (unsigned)std::atoi(argv[4]) } };
	d.width_ = in.size.width; d.height_ = in.size.height;
	d.outputSize_ = out.size;
	/* the debayer's largest output: the input less the 2 pixel border on each side */
	d.nativeOutputSize_ = { in.size.width - 4, in.size.height - 4 };
	d.configure(in, out);
	std::printf("%ux%u\n", d.s.w.width, d.s.w.height);
}
EOF
# build NAME SRC: the harness from SRC's debayer_egl.cpp as $W/NAME
build() {
	e=$2/src/libcamera/software_isp/debayer_egl.cpp
	awk 'f { print } /nativeOutputSize_ = outSizeRange\.max;/ { f = 1 } f && /stats_->setWindow\(/ { exit }' "$e" \
		> "$W/snippet.inc"
	grep -q 'stats_->setWindow(' "$W/snippet.inc" || { echo "FAIL: no setWindow() found in $e"; exit 1; }
	"$CXX" -std=c++17 -w -I"$W" -o "$W/$1" "$W/harness.cpp" || { echo "FAIL: the harness does not compile from $e"; exit 1; }
}
# cases HARNESS: the modes, as "LABEL|INPUT-W INPUT-H OUTPUT-W OUTPUT-H"; the window must be the columns and lines
# the picture takes from the frame (output size / scale, the scale the larger of the two output to native ratios),
# within 2; prints a FAIL line per miss and returns the count
cases() {
	n=0
	while IFS='|' read -r l m; do
		got=$("$W/$1" $m)
		if echo "$m $got" | awk '{ split($5, g, "x"); s = $3 / ($1 - 4); if ($4 / ($2 - 4) > s) s = $4 / ($2 - 4)
			w = $3 / s; h = $4 / s; ok = g[1] >= w - 2 && g[1] <= w + 2 && g[2] >= h - 2 && g[2] <= h + 2
			exit !ok }'; then echo "  ok: $l: $got"
		else echo "  FAIL: $l: window $got"; n=$((n + 1)); fi
	done <<'EOF'
IMX376 full frame to 720p (4:3 to 16:9)|2592 1940 1280 720
IMX519 binned to 1080p (4:3 to 16:9)|2328 1748 1920 1080
IMX371 full frame to 640x480 (4:3 to 4:3)|4656 3456 640 480
IMX519 4K mode to 1080p (16:9 to 16:9)|3840 2160 1920 1080
EOF
	return $n
}

S1=$W/src1
unpack "$S1"
apply "$S1" "$P1" "$P1/series" || exit 1
build old "$S1"
cases old > "$W/old.out"
grep -q FAIL "$W/old.out" && echo "  ok: on +fajita2 the window is the output's size ($(grep -c FAIL "$W/old.out") modes fail)" ||
	{ echo "  FAIL: +fajita2 already passes"; FAILS=$((FAILS + 1)); }

S=$W/src
unpack "$S"
apply "$S" "$P" "$P/series" && echo "  ok: the series applies to Debian's 0.7.2-1" || exit 1
build new "$S"
cases new || FAILS=$((FAILS + $?))
[ $FAILS = 0 ] && echo "all ok" || { echo "$FAILS failed"; exit 1; }
