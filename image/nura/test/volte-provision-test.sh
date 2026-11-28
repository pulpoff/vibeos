#!/bin/sh
# volte-provision-test.sh: files/qcom-volte-provision against a stand-in qmicli that answers the way the OnePlus 6T's
# modem does (libqmi 1.38's layout; IDs, IMSIs and APNs made up where they are not public) and records every
# change it is asked for: for a 1&1 SIM the Vodafone NL config is activated, its IMS profile set
# to IPv6, its default profile to the APN of NetworkManager's mobile connection, and the modem goes online once
# so the new config has taken effect before ModemManager sets up the data path; nothing is changed when all
# is already so, for another network, when the modem lacks the config, or while 81voltd is masked or missing; the
# config file wins over the table; a qmicli that does not end on SIGTERM is killed.
# Needs only sh and awk; touches only a temporary directory.
set -u
S=${1:-$(cd "$(dirname "$0")/.." && pwd)/files/qcom-volte-provision}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
FAILS=0
mkdir "$W/bin" "$W/nm"
cat > "$W/bin/qmicli" <<'EOF'
#!/bin/sh
case "$3" in
--uim-read-transparent=0x3F00,0x7FFF,0x6F07)
	[ -n "$SIM_IMSI" ] || exit 1
	# EF_IMSI: length 8, first digit with parity 9, then the rest two digits a byte, nibbles swapped
	h="08:$(printf %s "$SIM_IMSI" | cut -c1)9"
	r=$(printf %s "$SIM_IMSI" | cut -c2-)
	while [ -n "$r" ]; do a=$(printf %s "$r" | cut -c1); b=$(printf %s "$r" | cut -c2); h="$h:${b:-F}$a"; r=$(printf %s "$r" | cut -c3-); done
	printf "[qrtr://0] Successfully read information from the UIM:\nCard result:\n\tSW1: '0x90'\n\tSW2: '0x00'\nRead result:\n\t%s\n\n" "$h" ;;
--nas-get-home-network)
	[ -n "$HOME_NET" ] || exit 1
	printf "[qrtr://0] Successfully got home network:\n\tHome network:\n\t\tMCC: '%s'\n\t\tMNC: '%s'\n\tNetwork name source: mcc-mnc\n" \
		"${HOME_NET%-*}" "${HOME_NET#*-}" ;;
--pdc-list-configs=software)
	# the modem restarting its configuration: no answer, and like qmicli the first SIGTERM does not end it
	[ -n "${HANG:-}" ] && [ -s "$CALLS" ] && { trap '' TERM; exec sleep 60; }
	active=$(cat "$ACTIVE")
	echo "Total configurations: $(wc -l < "$MBNS" | tr -d ' ')"
	n=0
	while IFS='|' read -r id desc; do
		n=$((n + 1)); st=Inactive; [ "$desc" = "$active" ] && st=Active
		printf 'Configuration %s:\n\tDescription: %s\n\tType:        software\n\tSize:        45416\n\tStatus:      %s\n\tVersion:     0x801F139\n\tID:          %s\n\n' \
			"$n" "$desc" "$st" "$id"
	done < "$MBNS"
	;;
--pdc-activate-config=software,*)
	echo "$3" >> "$CALLS"
	[ -n "${NO_ACTIVATE:-}" ] || grep "^${3#*,}|" "$MBNS" | cut -d'|' -f2 > "$ACTIVE"
	echo "[qrtr://0] Successfully requested config activation" ;;
--dms-get-operating-mode)
	printf "[qrtr://0] Operating mode retrieved:\n\tMode: 'low-power'\n\tHW restricted: 'no'\n" ;;
--dms-set-operating-mode=*)
	echo "$3" >> "$CALLS"
	echo "[qrtr://0] Operating mode set successfully" ;;
--wds-get-default-profile-number=3gpp)
	printf "Default profile number retrieved:\n\tDefault profile number: '1'\n" ;;
--wds-get-profile-list=3gpp)
	echo "Profile list retrieved:"
	while IFS='|' read -r n apn pdp; do
		printf "\t[%s] 3gpp - \n\t\tAPN: '%s'\n\t\tAPN type: 'none'\n\t\tPDP type: '%s'\n\t\tPDP context number: '%s'\n\t\tUsername: ''\n" \
			"$n" "$apn" "$pdp" "$n"
	done < "$PROFILES" ;;
--wds-modify-profile=3gpp,*)
	echo "$3" >> "$CALLS"
	set -- $(echo "${3#*=3gpp,}" | tr ',' ' ')
	n=$1; shift
	for kv in "$@"; do
		case $kv in
		apn=*) awk -F'|' -v OFS='|' -v n="$n" -v v="${kv#apn=}" '$1 == n { $2 = v } 1' "$PROFILES" > "$PROFILES.new" ;;
		pdp-type=*) awk -F'|' -v OFS='|' -v n="$n" -v v="$(echo "${kv#pdp-type=}" | tr A-Z a-z)" '$1 == n { $3 = v } 1' "$PROFILES" > "$PROFILES.new" ;;
		esac
		mv "$PROFILES.new" "$PROFILES"
	done
	echo "Profile successfully modified." ;;
*) exit 1 ;;
esac
EOF
chmod 755 "$W/bin/qmicli"
# systemctl is-enabled 81voltd.service, as VOLTD says ("" = the unit is not there: systemd prints nothing on stdout)
cat > "$W/bin/systemctl" <<'EOF'
#!/bin/sh
[ "$1 $2" = "is-enabled 81voltd.service" ] || exit 1
[ -n "$VOLTD" ] || { echo "Failed to get unit file state for 81voltd.service: No such file or directory" >&2; exit 1; }
echo "$VOLTD"; case $VOLTD in enabled | static) ;; *) exit 1 ;; esac
EOF
chmod 755 "$W/bin/systemctl"
VOLTD=enabled; export VOLTD
cat > "$W/mbns" <<'EOF'
8D:E6:16:18:49:B8:CD:9C:FF:D0:96:E1:A0:31:E8:C2:7B:82:1D:41|Oversea-Commercial_DS
D2:E6:E3:B3:A1:FB:14:8F:67:52:2D:0F:D9:F9:08:DB:A4:44:E7:41|UK-VoLTE-Vodafone
12:7E:ED:26:45:39:74:6C:EA:DD:9B:EE:2E:A8:DC:98:87:C7:A6:1B|Netherlands-VoLTE-Vodafone
10:0F:D8:DD:4A:10:AC:64:16:FB:C3:62:5B:D1:72:2D:A3:ED:2F:7D|Telefonica_UK_Commercial
EOF
NL=12:7E:ED:26:45:39:74:6C:EA:DD:9B:EE:2E:A8:DC:98:87:C7:A6:1B
# the Vodafone NL config's own profiles, as the modem lists them after activating it
FRESH='1|live.vodafone.com|ipv4-or-ipv6
2|ims|ipv4-or-ipv6
3|sos|ipv4-or-ipv6'
DONE='1|web.vodafone.de|ipv4
2|ims|ipv6
3|sos|ipv4-or-ipv6'
nm() { printf '[connection]\nid=mobile\ntype=gsm\n%s\n[gsm]\napn=%s\n' "$2" "$1" > "$W/nm/mobile.nmconnection"; }
WANT_ALL="--pdc-activate-config=software,$NL
--wds-modify-profile=3gpp,2,pdp-type=IPV6
--wds-modify-profile=3gpp,1,apn=web.vodafone.de,pdp-type=IPV4
--dms-set-operating-mode=online
--dms-set-operating-mode=low-power"

# run NAME SIM-IMSI NAS-HOME ACTIVE PROFILES CONF WANT-OUTPUT WANT-CALLS: the script with that IMSI on the SIM and
# that home network from NAS ("" = no answer), that config active, those profiles and that config file ("" =
# none); its last line and the changes it asked for, one per line ("" for none)
run() {
	: > "$W/calls"; echo "$4" > "$W/active"; printf '%s\n' "$5" > "$W/profiles"
	if [ -n "$6" ]; then printf '%s\n' "$6" > "$W/conf"; else rm -f "$W/conf"; fi
	out=$(PATH="$W/bin:$PATH" SIM_IMSI="$2" HOME_NET="$3" MBNS="$W/mbns" ACTIVE="$W/active" CALLS="$W/calls" \
		PROFILES="$W/profiles" VOLTE_CONF="$W/conf" NM_CONNECTIONS="$W/nm" VOLTE_WAIT=0 VOLTE_SLEEP=0 VOLTE_SETTLE=0 \
		sh "$S" | tail -1)
	calls=$(cat "$W/calls")
	if [ "$out" = "$7" ] && [ "$calls" = "$8" ]; then echo "  ok: $1"
	else echo "  FAIL: $1: said '$out', asked for '$(echo $calls)'"; FAILS=$((FAILS + 1)); fi
}

OV=Oversea-Commercial_DS
NLD=Netherlands-VoLTE-Vodafone
nm web.vodafone.de ""
run "1&1 SIM, modem in low power: config, IMS profile and attach APN set" 262231234567890 "" $OV "$FRESH" "" \
	done "$WANT_ALL"
run "Vodafone DE SIM (262-02): not proven, nothing changed" 262029876543210 "" $OV "$FRESH" "" \
	"no settings for this network, nothing changed" ""
run "SIM unreadable, NAS knows 1&1: the same" "" 262-23 $OV "$FRESH" "" done "$WANT_ALL"
run "all already so: nothing changed" 262231234567890 "" $NLD "$DONE" "" done ""
run "config active, profiles fresh: only the profiles" 262231234567890 "" $NLD "$FRESH" "" done \
	"--wds-modify-profile=3gpp,2,pdp-type=IPV6
--wds-modify-profile=3gpp,1,apn=web.vodafone.de,pdp-type=IPV4"
run "other home network: nothing changed" 234101234567890 "" $OV "$FRESH" "" \
	"no settings for this network, nothing changed" ""
run "Telekom DE (262-01): nothing changed" 262011234567890 "" $OV "$FRESH" "" \
	"no settings for this network, nothing changed" ""
run "no answer at all: nothing changed" "" "" $OV "$FRESH" "" "no settings for this network, nothing changed" ""
run "config file wins" 262231234567890 "" $OV "$FRESH" "MBN=Telefonica_UK_Commercial
ATTACH_APN=internet.example" done "--pdc-activate-config=software,10:0F:D8:DD:4A:10:AC:64:16:FB:C3:62:5B:D1:72:2D:A3:ED:2F:7D
--wds-modify-profile=3gpp,2,pdp-type=IPV6
--wds-modify-profile=3gpp,1,apn=internet.example,pdp-type=IPV4
--dms-set-operating-mode=online
--dms-set-operating-mode=low-power"
nm web.vodafone.de autoconnect=false
run "mobile connection not autoconnecting: attach APN left alone" 262231234567890 "" $NLD "$FRESH" "" done \
	"--wds-modify-profile=3gpp,2,pdp-type=IPV6"
nm web.vodafone.de ""
NO_ACTIVATE=1; export NO_ACTIVATE
run "config never reported active: profiles left alone" 262231234567890 "" $OV "$FRESH" "" \
	"MBN Netherlands-VoLTE-Vodafone not reported active, profiles left alone" "--pdc-activate-config=software,$NL"
unset NO_ACTIVATE
HANG=1 QMI_TIMEOUT=1; export HANG QMI_TIMEOUT
t0=$(date +%s)
run "modem silent after the activation, qmicli ignoring SIGTERM: given up on" 262231234567890 "" $OV "$FRESH" "" \
	"MBN Netherlands-VoLTE-Vodafone not reported active, profiles left alone" "--pdc-activate-config=software,$NL"
t=$(($(date +%s) - t0))
if [ $t -le 10 ]; then echo "  ok: a hanging qmicli is killed (${t}s)"
else echo "  FAIL: a hanging qmicli held the script ${t}s"; FAILS=$((FAILS + 1)); fi
unset HANG QMI_TIMEOUT
VOLTD=masked
run "81voltd masked: nothing changed" 262231234567890 "" $OV "$FRESH" "" \
	"81voltd masked or not installed, nothing changed" ""
VOLTD=
run "81voltd not installed: nothing changed" 262231234567890 "" $OV "$FRESH" "" \
	"81voltd masked or not installed, nothing changed" ""
VOLTD=disabled
run "81voltd only disabled (another unit may start it): provisioned" 262231234567890 "" $OV "$FRESH" "" \
	done "$WANT_ALL"
VOLTD=enabled
grep -v Netherlands "$W/mbns" > "$W/m2"; mv "$W/m2" "$W/mbns"
run "modem without that config: nothing changed" 262231234567890 "" $OV "$FRESH" "" \
	"MBN Netherlands-VoLTE-Vodafone not on this modem, nothing changed" ""

[ $FAILS = 0 ] && echo "all ok" || { echo "$FAILS failed"; exit 1; }
