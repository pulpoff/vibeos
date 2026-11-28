#!/bin/sh
# libcamera-adjust-defaults-test.sh: patches/libcamera/0.7.2-1+surya21+fajita4 is +fajita3 unchanged plus one patch,
# applies to Debian's libcamera 0.7.2-1, and the soft ISP's image adjustment (gamma, contrast, saturation) takes its
# defaults from the tuning file's Adjust section, rejects values outside the controls' ranges, and starts a stream
# with them. Adjust::init() and Adjust::configure() of the patched adjust.cpp are compiled into a small harness fed
# tuning values; the same harness runs on +fajita3's adjust.cpp first and must fail there (it ignores the tuning).
# The source comes from snapshot.debian.org, checked against the .dsc's sha256, into $LC_SRC_CACHE (default
# ~/.cache/vibeos-test/libcamera-0.7.2-1).
# Needs sh, curl, tar (gz, xz), patch, awk, grep, cmp, sha256sum and a C++ compiler (c++); writes only the cache and a
# temporary directory.
set -u
T=$(cd "$(dirname "$0")/../.." && pwd)
P1=$T/patches/libcamera/0.7.2-1+surya21+fajita3 P=$T/patches/libcamera/0.7.2-1+surya21+fajita4
NEW="fajita-0007-ipa-simple-Make-image-adjustment-defaults-tunable.patch"
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

[ "$(cat "$P/series")" = "$(cat "$P1/series"; printf '%s\n' $NEW)" ] && echo "  ok: series is +fajita3's, then $NEW" ||
	{ echo "  FAIL: series is not +fajita3's plus the new patches"; FAILS=$((FAILS + 1)); }
for f in $(cat "$P1/series"); do cmp -s "$P/$f" "$P1/$f" || { echo "  FAIL: $f is not +fajita3's"; FAILS=$((FAILS + 1)); }; done
[ "$(LC_ALL=C ls "$P" | grep '\.patch$' | sort)" = "$(sort "$P/series")" ] || { echo "  FAIL: series and the patch files differ"; FAILS=$((FAILS + 1)); }

# the harness: Adjust::init() and configure() (and the constructor, where there is one), with mocks for the tuning
# node, the control map and the context; it prints the status, the controls' defaults and the knobs the stream starts
# with, "-" for a control that is not registered
cat > "$W/harness.cpp" <<'EOF'
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <optional>
#include <string>
struct Null { template<class T> Null &operator<<(const T &) { return *this; } };
#define LOG(category, level) Null()
struct Ctl { int id; };
namespace controls { Ctl Gamma{ 1 }, Contrast{ 2 }, Saturation{ 3 }; }
struct ControlInfo { float def = 0; ControlInfo() = default; ControlInfo(float, float, float d) : def(d) {} };
struct IPAConfigInfo {};
struct IPAContext {
	bool ccmEnabled = true;
	std::map<const Ctl *, ControlInfo> ctrlMap;
	struct { struct { float gamma = 0; std::optional<float> contrast, saturation; } knobs; } activeState;
};
struct Node {
	const char *v = nullptr;
	template<class T> T get(T def) const { return v ? static_cast<T>(std::atof(v)) : def; }
};
struct ValueNode {
	const char *g, *c, *s;
	Node operator[](const std::string &k) const { Node n; n.v = k == "gamma" ? g : k == "contrast" ? c : k == "saturation" ? s : nullptr; return n; }
};
constexpr float kDefaultGamma = 2.2f;
constexpr float kDefaultContrast = 1.0f;
constexpr float kDefaultSaturation = 1.0f;
struct Adjust {
#ifdef CTOR_IN_SNIPPET
	Adjust();
#endif
	int init(IPAContext &context, const ValueNode &tuningData);
	int configure(IPAContext &context, const IPAConfigInfo &configInfo);
	float defaultGamma_, defaultContrast_, defaultSaturation_;
};
#include "snippet.inc"
static const char *arg(const char *a) { return a[0] == '-' && !a[1] ? nullptr : a; }
int main(int, char **argv)
{
	IPAContext ctx;
	ctx.ccmEnabled = argv[4][0] == '1';
	ValueNode t{ arg(argv[1]), arg(argv[2]), arg(argv[3]) };
	Adjust a;
	int rc = a.init(ctx, t);
	if (rc) { std::printf("%d\n", rc); return 0; }
	a.configure(ctx, IPAConfigInfo());
	auto d = [&](const Ctl &c) { auto i = ctx.ctrlMap.find(&c); return i == ctx.ctrlMap.end() ? -1.0f : i->second.def; };
	std::printf("0 ctl %g %g %g knob %g %g %g\n", d(controls::Gamma), d(controls::Contrast), d(controls::Saturation),
		    ctx.activeState.knobs.gamma, ctx.activeState.knobs.contrast.value_or(1.0f),
		    ctx.activeState.knobs.saturation.value_or(1.0f));
}
EOF
# build NAME SRC: the harness from SRC's adjust.cpp as $W/NAME
build() {
	a=$2/src/ipa/simple/algorithms/adjust.cpp
	awk '/^(Adjust::Adjust\(\)|int Adjust::init)/ { f = 1 } /^void Adjust::queueRequest/ { exit } f { print }' "$a" > "$W/snippet.inc"
	grep -q 'Adjust::configure' "$W/snippet.inc" || { echo "FAIL: no Adjust::configure() found in $a"; exit 1; }
	d=; grep -q 'Adjust::Adjust()' "$W/snippet.inc" && d=-DCTOR_IN_SNIPPET
	"$CXX" -std=c++17 -w $d -I"$W" -o "$W/$1" "$W/harness.cpp" || { echo "FAIL: the harness does not compile from $a"; exit 1; }
}
# cases HARNESS: the tunings, as "LABEL|GAMMA CONTRAST SATURATION CCM|WANT" ("-" for a value the tuning leaves out);
# prints a FAIL line per miss and returns the count
cases() {
	n=0
	while IFS='|' read -r l s want; do
		got=$("$W/$1" $s)
		[ "$got" = "$want" ] && echo "  ok: $l" || { echo "  FAIL: $l: got '$got', want '$want'"; n=$((n + 1)); }
	done <<'EOF'
no tuning: the old defaults|- - - 1|0 ctl 2.2 1 1 knob 2.2 1 1
gamma, contrast and saturation tuned|1.8 1.2 1.3 1|0 ctl 1.8 1.2 1.3 knob 1.8 1.2 1.3
only contrast tuned|- 1.4 - 1|0 ctl 2.2 1.4 1 knob 2.2 1.4 1
tuned without a colour matrix: no saturation control|1.8 1.2 1.3 0|0 ctl 1.8 1.2 -1 knob 1.8 1.2 1
gamma out of range is rejected|0 - - 1|-22
contrast out of range is rejected|- 2.5 - 1|-22
saturation out of range is rejected|- - -0.5 1|-22
EOF
	return $n
}

S1=$W/src1
unpack "$S1"
apply "$S1" "$P1" "$P1/series" || exit 1
build old "$S1"
cases old > "$W/old.out"
grep -q FAIL "$W/old.out" && echo "  ok: +fajita3 fails the behaviour check ($(grep -c FAIL "$W/old.out") cases)" ||
	{ echo "  FAIL: +fajita3 already passes"; FAILS=$((FAILS + 1)); }

S=$W/src
unpack "$S"
apply "$S" "$P" "$P/series" && echo "  ok: the series applies to Debian's 0.7.2-1" || exit 1
build new "$S"
cases new || FAILS=$((FAILS + $?))
[ $FAILS = 0 ] && echo "all ok" || { echo "$FAILS failed"; exit 1; }
