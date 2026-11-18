#!/bin/bash
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
events=$(mktemp)
image=$(mktemp)
trap 'rm -f "$events" "$image"' EXIT

. <(sed '\|^\. /lib/functions.sh$|d' "$root/package/base-files/files/lib/upgrade/nand.sh")

tar() {
	command cat >/dev/null
	case "$1:${3:-}" in
		tf:*) echo 'sysupgrade-test/' ;;
		xOf:sysupgrade-test/root)
			printf root
			[ "${extract_fail:-}" != root ]
			;;
		xOf:sysupgrade-test/kernel)
			printf kernel
			[ "${extract_fail:-}" != kernel ]
			;;
		*) return 1 ;;
	esac
}
find_mtd_index() {
	[ "${fake_kernel_mtd:-0}" = 0 ] || echo 5
}
nand_upgrade_prepare_ubi() { return 0; }
nand_find_ubi() { echo ubi0; }
nand_find_volume() { echo "ubi0_$2"; }
identify_tar() { echo squashfs; }
ubiupdatevol() {
	printf 'ubi:%s\n' "$1" >> "$events"
	command cat >/dev/null
	[ "${ubi_fail:-}" != "$1" ]
}
mtd() {
	printf 'mtd\n' >> "$events"
	command cat >/dev/null
	local count
	count=$(grep -c '^mtd$' "$events")
	[ "${mtd_fail:-0}" != "$count" ]
}
flash_erase() {
	printf 'erase\n' >> "$events"
	[ "${erase_fail:-0}" = 0 ]
}
nandwrite() {
	printf 'nandwrite\n' >> "$events"
	command cat >/dev/null
	[ "${nandwrite_fail:-0}" = 0 ]
}

run_case() (
	name=$1
	expected_status=$2
	expected_events=$3
	shift 3
	fake_kernel_mtd=0
	extract_fail=
	ubi_fail=
	mtd_fail=0
	erase_fail=0
	nandwrite_fail=0
	CI_JFFS2_CLEAN_MARKERS=0
	while [ "$#" -gt 0 ]; do
		case "$1" in
			kernel_mtd=*) fake_kernel_mtd=${1#*=} ;;
			extract_fail=*) extract_fail=${1#*=} ;;
			ubi_fail=*) ubi_fail=${1#*=} ;;
			mtd_fail=*) mtd_fail=${1#*=} ;;
			erase_fail=*) erase_fail=${1#*=} ;;
			nandwrite_fail=*) nandwrite_fail=${1#*=} ;;
			jffs2=*) CI_JFFS2_CLEAN_MARKERS=${1#*=} ;;
			*) echo "unknown test setting: $1" >&2; exit 1 ;;
		esac
		shift
	done
	: > "$events"
	status=0
	set +u
	nand_upgrade_tar "$image" cat || status=$?
	set -u
	actual_events=$(command cat "$events")
	if [ "$status" -ne "$expected_status" ] || [ "$actual_events" != "$expected_events" ]; then
		printf '%s failed: status=%s, events:\n%s\n' "$name" "$status" "$actual_events" >&2
		exit 1
	fi
	echo "PASS $name"
)

run_case ubi-success 0 $'ubi:/dev/ubi0_rootfs\nubi:/dev/ubi0_kernel'
run_case root-write-fails 1 'ubi:/dev/ubi0_rootfs' ubi_fail=/dev/ubi0_rootfs
run_case kernel-write-fails 1 $'ubi:/dev/ubi0_rootfs\nubi:/dev/ubi0_kernel' ubi_fail=/dev/ubi0_kernel
run_case root-extraction-fails 1 'ubi:/dev/ubi0_rootfs' extract_fail=root
run_case kernel-extraction-fails 1 $'ubi:/dev/ubi0_rootfs\nubi:/dev/ubi0_kernel' extract_fail=kernel
run_case mtd-success 0 $'mtd\nubi:/dev/ubi0_rootfs\nmtd' kernel_mtd=1
run_case invalidation-fails 1 'mtd' kernel_mtd=1 mtd_fail=1
run_case mtd-write-fails 1 $'mtd\nubi:/dev/ubi0_rootfs\nmtd' kernel_mtd=1 mtd_fail=2
run_case mtd-extraction-fails 1 $'mtd\nubi:/dev/ubi0_rootfs\nmtd' kernel_mtd=1 extract_fail=kernel
run_case nandwrite-success 0 $'mtd\nubi:/dev/ubi0_rootfs\nerase\nnandwrite' kernel_mtd=1 jffs2=1
run_case erase-fails 1 $'mtd\nubi:/dev/ubi0_rootfs\nerase' kernel_mtd=1 jffs2=1 erase_fail=1
run_case nandwrite-fails 1 $'mtd\nubi:/dev/ubi0_rootfs\nerase\nnandwrite' kernel_mtd=1 jffs2=1 nandwrite_fail=1

