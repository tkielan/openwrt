#!/bin/bash
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd)
events=$(mktemp)
test_dir=$(mktemp -d)
board_dir="$test_dir/sysupgrade-tplink_archer-ax55-pro-v1"
image="$test_dir/image.tar"
mkdir "$board_dir"
printf kernel > "$board_dir/kernel"
printf root > "$board_dir/root"
tar -cf "$image" -C "$test_dir" "sysupgrade-tplink_archer-ax55-pro-v1"
tar -cf "$test_dir/no-root.tar" -C "$test_dir" --no-recursion "sysupgrade-tplink_archer-ax55-pro-v1" "sysupgrade-tplink_archer-ax55-pro-v1/kernel"
tar -cf "$test_dir/no-kernel.tar" -C "$test_dir" --no-recursion "sysupgrade-tplink_archer-ax55-pro-v1" "sysupgrade-tplink_archer-ax55-pro-v1/root"
mkdir "$test_dir/sysupgrade-other"
printf kernel > "$test_dir/sysupgrade-other/kernel"
printf root > "$test_dir/sysupgrade-other/root"
tar -cf "$test_dir/multiple-dirs.tar" -C "$test_dir" sysupgrade-other "sysupgrade-tplink_archer-ax55-pro-v1"
tar -cf "$test_dir/no-dir.tar" -C "$test_dir" "sysupgrade-tplink_archer-ax55-pro-v1/kernel" "sysupgrade-tplink_archer-ax55-pro-v1/root"
: > "$board_dir/root"
tar -cf "$test_dir/empty-root.tar" -C "$test_dir" "sysupgrade-tplink_archer-ax55-pro-v1"
printf root > "$board_dir/root"
: > "$board_dir/kernel"
tar -cf "$test_dir/empty-kernel.tar" -C "$test_dir" "sysupgrade-tplink_archer-ax55-pro-v1"
printf kernel > "$board_dir/kernel"
gzip -c "$image" > "$test_dir/image.tar.gz"
printf invalid > "$test_dir/invalid.tar"
cleanup() {
	rm -f "$events" "$image" "$test_dir/no-root.tar" "$test_dir/empty-root.tar" \
		"$test_dir/no-kernel.tar" "$test_dir/empty-kernel.tar" \
		"$test_dir/multiple-dirs.tar" "$test_dir/no-dir.tar" \
		"$test_dir/image.tar.gz" "$test_dir/invalid.tar" "$board_dir/kernel" "$board_dir/root" \
		"$test_dir/sysupgrade-other/kernel" "$test_dir/sysupgrade-other/root"
	rmdir "$board_dir" "$test_dir/sysupgrade-other" "$test_dir"
}
trap cleanup EXIT

. <(tail -n +2 "$root/target/linux/qualcommax/ipq50xx/base-files/lib/upgrade/platform.sh")

case " $RAMFS_COPY_BIN " in
	*" mktemp "*) ;;
	*) echo "mktemp is missing from the upgrade ramfs" >&2; exit 1 ;;
esac

board_name() { echo "${test_board:-tplink,archer-ax55-pro-v1}"; }
identify_if_gzip() {
	case "$1" in
		*.gz) printf z ;;
	esac
}
cat() {
	if [ "${1:-}" = /proc/cmdline ]; then
		printf '%s\n' "$cmdline"
	else
		command cat "$@"
	fi
}
fw_printenv() {
	[ "${env_fail:-0}" = 0 ] || return 1
	[ "${env_warning:-0}" = 0 ] || echo "Warning: Bad CRC" >&2
	printf '%s\n' "$fake_tp"
}
mktemp() {
	[ "${mktemp_fail:-0}" = 0 ] || return 1
	command mktemp "$@"
}
find_mtd_index() {
	case "$1" in
		0:BOOTCONFIG) echo 2 ;;
		0:BOOTCONFIG1) echo 3 ;;
		rootfs|rootfs_1)
			[ "${missing:-0}" = 1 ] || echo 11
			;;
	esac
}
dd() {
	case "${dd_fail:-0}:$1" in
		0:*) return 0 ;;
		3:if=/dev/mtd3|1:*) return 1 ;;
		*) return 0 ;;
	esac
}
validate_bootconfig_magic() { [ "${invalid_bc:-0}" = 0 ]; }
get_bootconfig_primaryboot() { printf '%s\n' "${fake_primaryboot:-0}"; }
remove_oem_ubi_volume() { printf 'remove:%s:%s\n' "$CI_UBIPART" "$1" >> "$events"; }
sync() {
	printf 'sync\n' >> "$events"
	sync_count=$((sync_count + 1))
	[ "${sync_fail:-0}" != "$sync_count" ]
}
nand_do_flash_file() {
	printf 'flash:%s\n' "$CI_UBIPART" >> "$events"
	[ "${flash_fail:-0}" = 0 ]
}
fw_setenv() {
	printf 'set:%s:%s\n' "$1" "$2" >> "$events"
	[ "${set_fail:-0}" = 0 ]
}
nand_do_upgrade_failed() { printf 'failed\n' >> "$events"; }
nand_do_upgrade_success() { printf 'success\n' >> "$events"; }

run_case() (
	name=$1
	expected_status=$2
	expected_events=$3
	shift 3
	cmdline='ubi.mtd=rootfs rootwait'
	fake_tp=0
	env_fail=0
	env_warning=0
	mktemp_fail=0
	missing=0
	dd_fail=0
	invalid_bc=0
	fake_primaryboot=0
	flash_fail=0
	set_fail=0
	sync_fail=0
	sync_count=0
	while [ "$#" -gt 0 ]; do
		case "$1" in
			cmdline=*) cmdline=${1#*=} ;;
			tp=*) fake_tp=${1#*=} ;;
			env_fail=*) env_fail=${1#*=} ;;
			env_warning=*) env_warning=${1#*=} ;;
			mktemp_fail=*) mktemp_fail=${1#*=} ;;
			missing=*) missing=${1#*=} ;;
			dd_fail=*) dd_fail=${1#*=} ;;
			invalid_bc=*) invalid_bc=${1#*=} ;;
			primaryboot=*) fake_primaryboot=${1#*=} ;;
			flash_fail=*) flash_fail=${1#*=} ;;
			set_fail=*) set_fail=${1#*=} ;;
			sync_fail=*) sync_fail=${1#*=} ;;
			*) echo "unknown test setting: $1" >&2; exit 1 ;;
		esac
		shift
	done
	: > "$events"
	preflight_status=0
	platform_check_image "$image" || preflight_status=$?
	if [ "$flash_fail" = 1 ] || [ "$set_fail" = 1 ] || [ "$sync_fail" != 0 ]; then
		expected_preflight=0
	else
		expected_preflight=$expected_status
	fi
	if [ "$preflight_status" -ne "$expected_preflight" ] || [ -s "$events" ]; then
		echo "$name failed preflight: status=$preflight_status" >&2
		exit 1
	fi
	status=0
	platform_do_upgrade "$image" || status=$?
	actual_events=$(command cat "$events")
	if [ "$status" -ne "$expected_status" ] || [ "$actual_events" != "$expected_events" ]; then
		printf '%s failed: status=%s, events:\n%s\n' "$name" "$status" "$actual_events" >&2
		exit 1
	fi
	echo "PASS $name"
)

run_case slot0 0 $'remove:rootfs_1:ubi_rootfs\nremove:rootfs_1:tp_data\nsync\nflash:rootfs_1\nsync\nset:tp_boot_idx:1\nsuccess'
run_case slot1 0 $'remove:rootfs:ubi_rootfs\nremove:rootfs:tp_data\nsync\nflash:rootfs\nsync\nset:tp_boot_idx:0\nsuccess' 'cmdline=ubi.mtd=rootfs_1 rootwait' tp=1
run_case unknown-slot 1 'failed' 'cmdline=rootwait'
run_case multiple-slots 1 'failed' 'cmdline=ubi.mtd=rootfs ubi.mtd=rootfs_1' tp=1
run_case multiple-slots-reversed 1 'failed' 'cmdline=ubi.mtd=rootfs_1 ubi.mtd=rootfs' tp=1
run_case wrong-slot 1 'failed' tp=1
run_case env-read-fails 1 'failed' env_fail=1
run_case env-warning 1 'failed' env_warning=1
run_case invalid-env-value 1 'failed' tp=invalid
run_case bootconfig-temp-fails 1 'failed' mktemp_fail=1
run_case missing-slot 1 'failed' missing=1
run_case bootconfig-read-fails 1 'failed' dd_fail=1
run_case backup-bootconfig-read-fails 1 'failed' dd_fail=3
run_case invalid-bootconfig 1 'failed' invalid_bc=1
run_case reversed-bootconfig 1 'failed' primaryboot=1
run_case flash-fails 1 $'remove:rootfs_1:ubi_rootfs\nremove:rootfs_1:tp_data\nsync\nflash:rootfs_1\nfailed' flash_fail=1
run_case preflash-sync-fails 1 $'remove:rootfs_1:ubi_rootfs\nremove:rootfs_1:tp_data\nsync\nfailed' sync_fail=1
run_case sync-fails 1 $'remove:rootfs_1:ubi_rootfs\nremove:rootfs_1:tp_data\nsync\nflash:rootfs_1\nsync\nfailed' sync_fail=2
run_case setenv-fails 1 $'remove:rootfs_1:ubi_rootfs\nremove:rootfs_1:tp_data\nsync\nflash:rootfs_1\nsync\nset:tp_boot_idx:1\nfailed' set_fail=1

test_board=tplink,archer-ax55-v1
platform_check_image "$image"
echo "PASS other-board-preflight"

ax55_pro_check_image "$test_dir/image.tar.gz"
echo "PASS compressed-image"

for invalid_image in no-root.tar no-kernel.tar empty-root.tar empty-kernel.tar multiple-dirs.tar no-dir.tar invalid.tar; do
	if ax55_pro_check_image "$test_dir/$invalid_image"; then
		echo "unexpectedly accepted $invalid_image" >&2
		exit 1
	fi
	echo "PASS reject-$invalid_image"
done

test_board=tplink,archer-ax55-pro-v1
: > "$events"
if platform_check_image "$test_dir/no-root.tar"; then
	echo "invalid image passed preflight" >&2
	exit 1
fi
if platform_do_upgrade "$test_dir/no-root.tar"; then
	echo "invalid image passed upgrade" >&2
	exit 1
fi
[ "$(command cat "$events")" = failed ]
echo "PASS invalid-image-never-flashes"
