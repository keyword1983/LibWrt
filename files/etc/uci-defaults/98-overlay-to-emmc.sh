#!/bin/sh
# Move /overlay onto the largest unused partition on the boot eMMC so
# opkg/iStore/PassWall installs aren't limited to the tiny factory
# rootfs_data slice.
#
# Unlike a plain fstab-triggered extroot switch (which would make OpenWrt's
# early-preinit mount code do the format+migrate dance on the NEXT boot,
# under the tightest resource/timing constraints of the whole boot process),
# this script does the risky part -- format + copy existing overlay content
# -- right now, while the system is already fully booted and stable. By the
# time any reboot happens, the target partition is already a complete,
# populated overlay; the early-boot fstab logic then only has to do a plain
# mount, not a mount-and-migrate. This mirrors the community-established
# manual procedure for this device family (format p27, copy existing
# /overlay onto it, then point fstab at it) rather than trusting the
# less-common loop-file-backed-overlay -> raw-partition migration path.

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

# Fresh, known-good filesystem -- don't trust whatever (if anything) the
# factory left on this partition.
mkfs.ext4 -F -q "$BEST" || exit 1

MNT="/tmp/emmc-overlay-new"
mkdir -p "$MNT"
mount -t ext4 "$BEST" "$MNT" || exit 1

# Copy the *current* live overlay mountpoint -- which already contains its
# own upper/ and work/ subdirectories -- onto the new partition, so the new
# partition ends up with the exact same upper/work layout, populated with
# whatever's there now (uci-defaults changes so far, SSH host keys, etc).
tar -C /overlay -cf - . | tar -C "$MNT" -xf - || {
	umount "$MNT"
	exit 1
}
mkdir -p "$MNT/upper" "$MNT/work"

umount "$MNT"
rmdir "$MNT"

UUID=$(block info "$BEST" 2>/dev/null | sed -n 's/.*UUID="\([^"]*\)".*/\1/p')
[ -n "$UUID" ] || exit 0

uci -q delete fstab.overlay_emmc 2>/dev/null
uci set fstab.overlay_emmc="mount"
uci set fstab.overlay_emmc.target="/overlay"
uci set fstab.overlay_emmc.uuid="$UUID"
uci set fstab.overlay_emmc.enabled="1"
uci commit fstab

exit 0
