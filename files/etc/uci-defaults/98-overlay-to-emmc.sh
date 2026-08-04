#!/bin/sh
# Point /overlay at the largest unused ext4 partition on the boot eMMC so
# opkg/iStore/PassWall installs aren't limited to the tiny factory
# rootfs_data slice. This only stages the fstab entry; OpenWrt's extroot
# mechanism performs the actual switch-over on the NEXT boot.

[ -e /etc/config/fstab ] || exit 0
command -v block >/dev/null 2>&1 || exit 0

ROOTPART=$(block info 2>/dev/null | awk -F: '/MOUNT="\/rom"/{print $1}')
BOOTDISK=$(echo "$ROOTPART" | sed -n 's/\(\/dev\/mmcblk[0-9]\+\)p[0-9]\+/\1/p')
[ -n "$BOOTDISK" ] || exit 0

BEST=""
BESTSIZE=0
for part in "${BOOTDISK}"p*; do
	[ -b "$part" ] || continue
	case "$part" in *boot0|*boot1) continue ;; esac

	info=$(block info "$part" 2>/dev/null)
	fstype=$(echo "$info" | sed -n 's/.*TYPE="\([a-zA-Z0-9]*\)".*/\1/p')
	[ "$fstype" = "ext4" ] || continue

	mnt=$(echo "$info" | sed -n 's/.*MOUNT="\([^"]*\)".*/\1/p')
	[ -z "$mnt" ] || continue

	base=$(basename "$part")
	size=$(cat "/sys/class/block/$base/size" 2>/dev/null)
	[ -n "$size" ] || continue

	if [ "$size" -gt "$BESTSIZE" ]; then
		BESTSIZE=$size
		BEST=$part
	fi
done

[ -n "$BEST" ] || exit 0
# require >1GiB (size is in 512B sectors) so we never grab a small spare partition by mistake
[ "$BESTSIZE" -gt 2097152 ] || exit 0

UUID=$(block info "$BEST" 2>/dev/null | sed -n 's/.*UUID="\([^"]*\)".*/\1/p')
[ -n "$UUID" ] || exit 0

uci -q delete fstab.overlay_emmc 2>/dev/null
uci set fstab.overlay_emmc="mount"
uci set fstab.overlay_emmc.target="/overlay"
uci set fstab.overlay_emmc.uuid="$UUID"
uci set fstab.overlay_emmc.enabled="1"
uci commit fstab

exit 0
