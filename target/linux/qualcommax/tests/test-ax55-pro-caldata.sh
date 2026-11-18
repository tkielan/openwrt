#!/bin/bash
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd)
events=$(mktemp)
trap 'rm -f "$events"' EXIT

. <(sed -n '/^macaddr_add() {/,/^}/p' "$root/package/base-files/files/lib/functions/system.sh")

board_name() { echo tplink,archer-ax55-pro-v1; }
get_mac_binary() { printf '%s\n' "$test_mac"; }
caldata_die() { echo "$*" >&2; exit 1; }
caldata_extract() { printf 'extract:%s:%s:%s\n' "$@" >> "$events"; }
ath11k_patch_mac() { printf 'mac:%s:%s\n' "$@" >> "$events"; }
ath11k_set_macflag() { echo flag >> "$events"; }

run_case() (
	name=$1
	FIRMWARE=$2
	test_mac=$3
	expected_status=$4
	expected_events=$5
	: > "$events"
	status=0
	(
		. <(sed '\|^\[ -e /lib/firmware/\$FIRMWARE \] && exit 0$|d; \|^\. /lib/functions/caldata.sh$|d' \
			"$root/target/linux/qualcommax/ipq50xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata")
	) || status=$?
	if [ "$status" -ne "$expected_status" ] || [ "$(cat "$events")" != "$expected_events" ]; then
		echo "$name failed: status=$status, events=$(cat "$events")" >&2
		exit 1
	fi
	echo "PASS $name"
)

ipq=ath11k/IPQ5018/hw1.0/cal-ahb-c000000.wifi.bin
qcn=ath11k/QCN6122/hw1.0/cal-ahb-b00a040.wifi.bin
run_case ipq "$ipq" 02:00:00:12:34:56 0 $'extract:0:ART:0x1000:0x20000\nmac:02:00:00:12:34:55:0\nflag'
run_case qcn "$qcn" 02:00:00:12:34:56 0 $'extract:0:ART:0x26800:0x20000\nmac:02:00:00:12:34:54:0\nflag'
run_case missing "$ipq" '' 1 ''
run_case malformed "$qcn" 02:00:00:12:34 1 ''
run_case zero "$ipq" 00:00:00:00:00:00 1 ''
run_case multicast "$qcn" 01:00:00:12:34:56 1 ''
